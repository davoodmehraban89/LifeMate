import crypto from 'node:crypto';
import express from 'express';
import { applyPlanMutation, createPlanItem, updatePlanItem, planTransaction, serializePlanItem, validUuid, PlanMutationError } from './plan_mutations.js';

const allowedKinds = new Set(['task','event','routine','goal','assignment','exam','study_session']);
const schoolText = (value, max = 120) => typeof value === 'string' && Boolean(value.trim()) && value.trim().length <= max;
const schoolOptionalText = (value, max = 120) => value == null || (typeof value === 'string' && value.trim().length <= max);
function schoolDate(value) {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value) || value.startsWith('0000-')) return false;
  const date = new Date(`${value}T00:00:00Z`);
  return Number.isFinite(date.getTime()) && date.toISOString().slice(0, 10) === value;
}

function asDate(value) {
  if (value == null || value === '') return null;
  const d = new Date(value);
  return Number.isNaN(d.getTime()) ? null : d;
}

async function familyMember(pool, familyId, userId) {
  const r = await pool.query(
    'select m.role,m.is_admin from family_membership m join family_workspace f on f.id=m.family_id where m.family_id=$1 and m.user_id=$2 and m.ended_at is null and f.archived_at is null',
    [familyId, userId],
  );
  return r.rows[0] ?? null;
}

async function assertPlanWrite(pool, itemId, userId) {
  if (!validUuid(itemId)) return { error: 'invalid_id', status: 400 };
  const r = await pool.query('select * from plan_item where id=$1', [itemId]);
  if (!r.rowCount) return { error: 'not_found', status: 404 };
  if (r.rows[0].owner_user_id !== userId) {
    return { error: 'forbidden', status: 403 };
  }
  if (r.rows[0].family_id && !(await familyMember(pool, r.rows[0].family_id, userId))) return { error: 'family_membership_required', status: 403 };
  return { item: r.rows[0] };
}

async function assertStudentAcademic(pool, studentUserId, viewerUserId) {
  if (!validUuid(studentUserId)) return false;
  const r = await pool.query(
    'select can_view_student_academic($1,$2) as allowed',
    [viewerUserId, studentUserId],
  );
  return r.rows[0]?.allowed === true;
}

async function audit(pool, actorUserId, familyId, action, targetType, targetId, metadata = {}) {
  await pool.query(
    `insert into access_audit(actor_user_id,family_id,action,target_type,target_id,metadata)
     values($1,$2,$3,$4,$5,$6::jsonb)`,
    [actorUserId, familyId, action, targetType, String(targetId ?? ''), JSON.stringify(metadata)],
  );
}

export function createPhase3Router({ pool, auth }) {
  const router = express.Router();

  router.get('/today', auth, async (req, res) => {
    const from = asDate(req.query.from) ?? new Date();
    const to = asDate(req.query.to) ?? new Date(from.getTime() + 24 * 60 * 60 * 1000);
    const r = await pool.query(
      `select p.*
         from plan_item p
        where can_view_plan_item($1,p.id)
          and p.status not in ('completed','cancelled')
          and coalesce(p.starts_at,p.due_at,p.created_at) >= $2
          and coalesce(p.starts_at,p.due_at,p.created_at) < $3
        order by coalesce(p.starts_at,p.due_at,p.created_at), p.priority desc`,
      [req.identity.sub, from, to],
    );
    res.json({ items: r.rows.map((item) => serializePlanItem(item, req.identity.sub)), asOf: new Date() });
  });

  router.get('/plan-items', auth, async (req, res) => {
    const from = asDate(req.query.from);
    const to = asDate(req.query.to);
    const values = [req.identity.sub];
    const filters = ["can_view_plan_item($1,p.id)", "p.status<>'cancelled'"];
    if (from) {
      values.push(from);
      filters.push(`coalesce(p.starts_at,p.due_at,p.created_at) >= $${values.length}`);
    }
    if (to) {
      values.push(to);
      filters.push(`coalesce(p.starts_at,p.due_at,p.created_at) < $${values.length}`);
    }
    if (req.query.kind && allowedKinds.has(String(req.query.kind))) {
      values.push(String(req.query.kind));
      filters.push(`p.kind = $${values.length}`);
    }
    const r = await pool.query(
      `select p.*
         from plan_item p
        where ${filters.join(' and ')}
        order by coalesce(p.starts_at,p.due_at,p.created_at), p.created_at`,
      values,
    );
    res.json({ items: r.rows.map((item) => serializePlanItem(item, req.identity.sub)), asOf: new Date() });
  });

  router.get('/plan-items/:itemId', auth, async (req, res) => {
    if (!validUuid(req.params.itemId)) return res.status(400).json({ error: 'invalid_id' });
    const result = await pool.query('select * from plan_item where id=$1 and can_view_plan_item($2,id)', [req.params.itemId, req.identity.sub]);
    if (!result.rowCount) return res.status(404).json({ error: 'not_found' });
    res.json(serializePlanItem(result.rows[0], req.identity.sub));
  });

  router.post('/plan-items', auth, async (req, res) => {
    const item = await planTransaction(pool, req.identity.sub, (client) => createPlanItem(client, req.identity.sub, req.body, req.body.id ?? crypto.randomUUID()));
    res.status(201).json(serializePlanItem(item, req.identity.sub));
  });

  router.patch('/plan-items/:itemId', auth, async (req, res) => {
    const item = await planTransaction(pool, req.identity.sub, (client) => updatePlanItem(client, req.identity.sub, req.params.itemId, req.body, req.body.expectedVersion));
    res.json(serializePlanItem(item, req.identity.sub));
  });

  router.delete('/plan-items/:itemId', auth, async (req, res) => {
    const item = await planTransaction(pool, req.identity.sub, (client) => updatePlanItem(client, req.identity.sub, req.params.itemId, { status: 'cancelled' }, req.body.expectedVersion));
    res.json(serializePlanItem(item, req.identity.sub));
  });

  router.post('/plan-items/:itemId/reminders', auth, async (req, res) => {
    const access = await assertPlanWrite(pool, req.params.itemId, req.identity.sub);
    if (access.error) return res.status(access.status).json({ error: access.error });
    const minutes = Number(req.body.minutesBefore);
    if (!Number.isInteger(minutes) || minutes < 0 || minutes > 10080) {
      return res.status(400).json({ error: 'invalid_reminder' });
    }
    const baseTime = access.item.starts_at ?? access.item.due_at;
    if (!baseTime) return res.status(400).json({ error: 'plan_item_has_no_time' });
    const r = await pool.query(
      `insert into reminder(plan_item_id,owner_user_id,minutes_before,scheduled_for)
       values($1,$2,$3,$4::timestamptz - make_interval(mins => $3))
       on conflict(plan_item_id,owner_user_id,minutes_before)
       do update set scheduled_for=excluded.scheduled_for,status='scheduled',claimed_at=null
       returning *`,
      [req.params.itemId, req.identity.sub, minutes, baseTime],
    );
    res.status(201).json(r.rows[0]);
  });

  router.post('/reminders/claim-due', auth, async (req, res) => {
    const limit = Math.min(Math.max(Number(req.body.limit ?? 20), 1), 100);
    const client = await pool.connect();
    try {
      await client.query('begin');
      const r = await client.query(
        `select r.id,r.plan_item_id,r.owner_user_id,p.title,r.scheduled_for
           from reminder r
           join plan_item p on p.id=r.plan_item_id
          where r.owner_user_id=$1
            and r.status='scheduled'
            and r.scheduled_for <= now()
            and p.status not in ('completed','cancelled')
          order by r.scheduled_for
          for update skip locked
          limit $2`,
        [req.identity.sub, limit],
      );
      for (const row of r.rows) {
        await client.query(
          `update reminder set status='claimed',claimed_at=now() where id=$1`,
          [row.id],
        );
        await client.query(
          `insert into notification_outbox(reminder_id,user_id,payload)
           values($1,$2,$3::jsonb)
           on conflict(reminder_id) do nothing`,
          [row.id, row.owner_user_id, JSON.stringify({
            type: 'plan_reminder',
            planItemId: row.plan_item_id,
            title: row.title,
            scheduledFor: row.scheduled_for,
          })],
        );
      }
      await client.query('commit');
      res.json({ claimed: r.rows.length, reminders: r.rows });
    } catch (e) {
      await client.query('rollback').catch(() => {});
      throw e;
    } finally {
      client.release();
    }
  });

  router.get('/notification-outbox', auth, async (req, res) => {
    const r = await pool.query(
      `select id,reminder_id,payload,available_at,delivered_at,attempts
         from notification_outbox
        where user_id=$1
        order by available_at desc
        limit 100`,
      [req.identity.sub],
    );
    res.json({ notifications: r.rows });
  });

  router.get('/life-contexts', auth, async (req, res) => {
    const r = await pool.query(
      'select * from life_context where user_id=$1 and active order by created_at',
      [req.identity.sub],
    );
    res.json({ contexts: r.rows });
  });

  router.post('/life-contexts', auth, async (req, res) => {
    const kind = String(req.body.kind ?? '');
    const title = String(req.body.title ?? '').trim();
    if (!['student','work','personal'].includes(kind) || !title) {
      return res.status(400).json({ error: 'invalid_life_context' });
    }
    const r = await pool.query(
      'insert into life_context(user_id,kind,title) values($1,$2,$3) returning *',
      [req.identity.sub, kind, title],
    );
    res.status(201).json(r.rows[0]);
  });

  router.post('/school/years', auth, async (req, res) => {
    const body = req.body ?? {};
    const title = String(body.title ?? '').trim();
    const startsOn = body.startsOn;
    const endsOn = body.endsOn;
    const lifeContextId = body.lifeContextId;
    if (!validUuid(lifeContextId) || !schoolText(body.title) || !schoolDate(startsOn) || !schoolDate(endsOn) || endsOn < startsOn) {
      return res.status(400).json({ error: 'invalid_academic_year' });
    }
    const ctx = await pool.query(
      `select 1 from life_context
        where id=$1 and user_id=$2 and kind='student' and active`,
      [lifeContextId, req.identity.sub],
    );
    if (!ctx.rowCount || !title || !startsOn || !endsOn) {
      return res.status(400).json({ error: 'invalid_academic_year' });
    }
    const r = await pool.query(
      `insert into academic_year(student_user_id,life_context_id,title,starts_on,ends_on)
       values($1,$2,$3,$4,$5) returning *`,
      [req.identity.sub, lifeContextId, title, startsOn, endsOn],
    );
    res.status(201).json(r.rows[0]);
  });

  router.post('/school/years/:yearId/terms', auth, async (req, res) => {
    const body = req.body ?? {};
    if (!validUuid(req.params.yearId) || !schoolText(body.title) || !schoolDate(body.startsOn) || !schoolDate(body.endsOn) || body.endsOn < body.startsOn) {
      return res.status(400).json({ error: 'invalid_academic_term' });
    }
    const y = await pool.query(
      'select student_user_id,active,starts_on::text,ends_on::text from academic_year where id=$1',
      [req.params.yearId],
    );
    if (!y.rowCount) return res.status(404).json({ error: 'not_found' });
    if (y.rows[0].student_user_id !== req.identity.sub) {
      return res.status(403).json({ error: 'forbidden' });
    }
    if (!y.rows[0].active || body.startsOn < y.rows[0].starts_on || body.endsOn > y.rows[0].ends_on) {
      return res.status(400).json({ error: 'invalid_academic_term' });
    }
    const r = await pool.query(
      `insert into academic_term(academic_year_id,title,starts_on,ends_on)
       values($1,$2,$3,$4) returning *`,
      [req.params.yearId, String(body.title ?? '').trim(), body.startsOn, body.endsOn],
    );
    res.status(201).json(r.rows[0]);
  });

  router.post('/school/terms/:termId/subjects', auth, async (req, res) => {
    const body = req.body ?? {};
    if (!validUuid(req.params.termId) || !schoolText(body.name) ||
        !schoolOptionalText(body.teacherName) ||
        !schoolOptionalText(body.colorKey, 40)) return res.status(400).json({ error: 'invalid_subject' });
    const t = await pool.query(
      `select y.student_user_id
         from academic_term t
         join academic_year y on y.id=t.academic_year_id
         join life_context l on l.id=y.life_context_id
        where t.id=$1 and y.active and l.active`,
      [req.params.termId],
    );
    if (!t.rowCount) return res.status(404).json({ error: 'not_found' });
    if (t.rows[0].student_user_id !== req.identity.sub) {
      return res.status(403).json({ error: 'forbidden' });
    }
    const name = String(body.name ?? '').trim();
    if (!name) return res.status(400).json({ error: 'invalid_subject' });
    const r = await pool.query(
      `insert into subject(student_user_id,academic_term_id,name,teacher_name,color_key)
       values($1,$2,$3,$4,$5) returning *`,
      [req.identity.sub, req.params.termId, name, body.teacherName?.trim() || null, body.colorKey?.trim() || null],
    );
    res.status(201).json(r.rows[0]);
  });

  router.get('/school/:studentUserId/overview', auth, async (req, res) => {
    const studentUserId = req.params.studentUserId;
    if (!(await assertStudentAcademic(pool, studentUserId, req.identity.sub))) {
      return res.status(403).json({ error: 'forbidden' });
    }
    const [years, subjects, workload, grades] = await Promise.all([
      pool.query(
        `select y.* from academic_year y where y.student_user_id=$1 and y.active
          and ($1=$2 or exists(select 1 from academic_term t join subject s on s.academic_term_id=t.id
            join plan_item p on p.subject_id=s.id where t.academic_year_id=y.id and can_view_plan_item($2,p.id)))
          order by y.starts_on desc`,
        [studentUserId, req.identity.sub],
      ),
      pool.query(
        `select s.*,t.title as term_title,y.title as year_title
           from subject s join academic_term t on t.id=s.academic_term_id
           join academic_year y on y.id=t.academic_year_id
          where s.student_user_id=$1 and s.archived_at is null and ($1=$2 or exists(select 1 from plan_item p
            where p.subject_id=s.id and can_view_plan_item($2,p.id))) order by s.name`,
        [studentUserId, req.identity.sub],
      ),
      pool.query(
        `select *
           from plan_item
          where owner_user_id=$1 and can_view_plan_item($2,id)
            and kind in ('assignment','exam','study_session')
            and status not in ('completed','cancelled')
          order by coalesce(due_at,starts_at) nulls last`,
        [studentUserId, req.identity.sub],
      ),
      pool.query(
        `select id,title,subject_id,grade_points,grade_out_of,due_at
           from plan_item
          where owner_user_id=$1 and can_view_plan_item($2,id)
            and grade_points is not null
            and grade_out_of is not null
          order by due_at desc nulls last`,
        [studentUserId, req.identity.sub],
      ),
    ]);
    res.json({
      years: years.rows,
      subjects: subjects.rows,
      workload: workload.rows.map((item) => serializePlanItem(item, req.identity.sub)),
      grades: grades.rows,
    });
  });

  router.get('/school/:studentUserId/timetable', auth, async (req, res) => {
    if (!(await assertStudentAcademic(pool, req.params.studentUserId, req.identity.sub))) {
      return res.status(403).json({ error: 'forbidden' });
    }
    const r = await pool.query(
      `select c.*,s.name as subject_name,s.color_key
         from class_session c
         join subject s on s.id=c.subject_id
        where s.student_user_id=$1 and s.archived_at is null and c.archived_at is null and ($1=$2 or exists(select 1 from plan_item p
          where p.subject_id=s.id and can_view_plan_item($2,p.id)))
        order by c.weekday,c.starts_at`,
      [req.params.studentUserId, req.identity.sub],
    );
    res.json({ classes: r.rows });
  });

  router.patch('/school/plan-items/:itemId/grade', auth, async (req, res) => {
    const access = await assertPlanWrite(pool, req.params.itemId, req.identity.sub);
    if (access.error) return res.status(access.status).json({ error: access.error });
    if (!['assignment','exam'].includes(access.item.kind)) {
      return res.status(400).json({ error: 'grade_not_applicable' });
    }
    const points = Number(req.body.points);
    const outOf = Number(req.body.outOf);
    if (!Number.isFinite(points) || !Number.isFinite(outOf) || outOf <= 0 || points < 0 || points > outOf) {
      return res.status(400).json({ error: 'invalid_grade' });
    }
    const item = await planTransaction(pool, req.identity.sub, (client) => updatePlanItem(client,
      req.identity.sub, req.params.itemId, { gradePoints: points, gradeOutOf: outOf }, req.body.expectedVersion));
    res.json(serializePlanItem(item, req.identity.sub));
  });

  router.get('/families/:familyId/calendar', auth, async (req, res) => {
    const member = await familyMember(pool, req.params.familyId, req.identity.sub);
    if (!member) return res.status(403).json({ error: 'forbidden' });
    const r = await pool.query(
      `select p.*,pr.display_name as owner_name
         from plan_item p
         join profile pr on pr.user_id=p.owner_user_id
        where p.family_id=$1
          and can_view_plan_item($2,p.id)
          and p.status <> 'cancelled'
        order by coalesce(p.starts_at,p.due_at,p.created_at)`,
      [req.params.familyId, req.identity.sub],
    );
    res.json({ items: r.rows.map((item) => serializePlanItem(item, req.identity.sub)), asOf: new Date() });
  });

  router.get('/families/:familyId/children/:studentUserId/support-summary', auth, async (req, res) => {
    const familyId = req.params.familyId;
    const studentUserId = req.params.studentUserId;
    const g = await pool.query(
      `select 1 where is_active_guardian($1,$2,$3)`,
      [familyId, req.identity.sub, studentUserId],
    );
    if (!g.rowCount) return res.status(403).json({ error: 'guardian_required' });

    const [upcoming, completed, overdue, study, grades] = await Promise.all([
      pool.query(
        `select id,kind,title,due_at,starts_at,priority,status
           from plan_item
          where owner_user_id=$1 and family_id=$3 and can_view_plan_item($2,id)
            and kind in ('assignment','exam','study_session')
            and status not in ('completed','cancelled')
            and coalesce(due_at,starts_at) >= now()
            and coalesce(due_at,starts_at) < now()+interval '14 days'
          order by coalesce(due_at,starts_at) limit 20`,
        [studentUserId, req.identity.sub, familyId],
      ),
      pool.query(
        `select count(*)::int as n from plan_item
          where owner_user_id=$1 and family_id=$3 and can_view_plan_item($2,id) and kind in ('assignment','study_session') and status='completed'
            and completed_at >= now()-interval '7 days'`,
        [studentUserId, req.identity.sub, familyId],
      ),
      pool.query(
        `select count(*)::int as n from plan_item
          where owner_user_id=$1 and family_id=$3 and can_view_plan_item($2,id) and kind in ('assignment','study_session')
            and status not in ('completed','cancelled') and due_at < now()`,
        [studentUserId, req.identity.sub, familyId],
      ),
      pool.query(
        `select floor(coalesce(sum(greatest(0,extract(epoch from
            least(coalesce(i.ends_at,now()),now())-greatest(i.starts_at,now()-interval '7 days')))),0))::int as seconds
           from study_session s join study_interval i on i.session_id=s.id join plan_item p on p.id=s.plan_item_id
          where s.child_user_id=$1 and s.archived_at is null and p.family_id=$3 and can_view_plan_item($2,p.id)
            and i.starts_at<now() and coalesce(i.ends_at,now())>now()-interval '7 days'`,
        [studentUserId, req.identity.sub, familyId],
      ),
      pool.query(
        `select
           case when sum(grade_out_of)>0 then round(sum(grade_points)/sum(grade_out_of)*100,1) end as percent
           from plan_item
          where owner_user_id=$1 and family_id=$3 and can_view_plan_item($2,id) and grade_points is not null and grade_out_of is not null`,
        [studentUserId, req.identity.sub, familyId],
      ),
    ]);
    await audit(pool, req.identity.sub, familyId, 'parent.support_summary.view', 'student', studentUserId);
    res.json({
      upcoming: upcoming.rows,
      metrics: {
        completedLast7Days: completed.rows[0].n,
        overdue: overdue.rows[0].n,
        studyMinutesLast7Days: Math.floor(study.rows[0].seconds / 60),
        recordedStudySecondsLast7Days: study.rows[0].seconds,
        recordedTimeIsProofOfStudy: false,
        gradePercent: grades.rows[0].percent == null ? null : Number(grades.rows[0].percent),
      },
    });
  });

  router.post('/sync/mutations', auth, async (req, res) => {
    const mutations = req.body?.mutations;
    if (!Array.isArray(mutations) || mutations.length > 100) return res.status(400).json({ error: 'invalid_mutations' });
    const results = [];
    for (const mutation of mutations) results.push(await applyPlanMutation(pool, req.identity.sub, mutation));
    res.json({ results, asOf: new Date() });
  });

  router.use((error, _req, res, next) => {
    if (error instanceof PlanMutationError) return res.status(error.status).json({ error: error.code, ...error.details });
    next(error);
  });

  return router;
}
