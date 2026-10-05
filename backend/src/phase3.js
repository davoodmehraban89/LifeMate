import express from 'express';

const allowedKinds = new Set(['task','event','routine','goal','assignment','exam','study_session']);
const allowedStatus = new Set(['planned','in_progress','completed','cancelled']);
const allowedPriority = new Set(['low','normal','high','urgent']);
const allowedVisibility = new Set(['private','selected_members','parent_guardian','family']);

function asDate(value) {
  if (value == null || value === '') return null;
  const d = new Date(value);
  return Number.isNaN(d.getTime()) ? null : d;
}

async function familyMember(pool, familyId, userId) {
  const r = await pool.query(
    'select role,is_admin from family_membership where family_id=$1 and user_id=$2 and ended_at is null',
    [familyId, userId],
  );
  return r.rows[0] ?? null;
}

async function assertPlanWrite(pool, itemId, userId) {
  const r = await pool.query('select * from plan_item where id=$1', [itemId]);
  if (!r.rowCount) return { error: 'not_found', status: 404 };
  if (r.rows[0].owner_user_id !== userId) {
    return { error: 'forbidden', status: 403 };
  }
  return { item: r.rows[0] };
}

async function assertStudentAcademic(pool, studentUserId, viewerUserId) {
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
    res.json({ items: r.rows });
  });

  router.get('/plan-items', auth, async (req, res) => {
    const from = asDate(req.query.from);
    const to = asDate(req.query.to);
    const values = [req.identity.sub];
    const filters = ['can_view_plan_item($1,p.id)'];
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
    res.json({ items: r.rows });
  });

  router.post('/plan-items', auth, async (req, res) => {
    const kind = String(req.body.kind ?? 'task');
    const title = String(req.body.title ?? '').trim();
    const priority = String(req.body.priority ?? 'normal');
    const visibility = String(req.body.visibility ?? 'private');
    const familyId = req.body.familyId || null;
    const startsAt = asDate(req.body.startsAt);
    const dueAt = asDate(req.body.dueAt);
    if (!allowedKinds.has(kind) || !title || !allowedPriority.has(priority) || !allowedVisibility.has(visibility)) {
      return res.status(400).json({ error: 'invalid_plan_item' });
    }
    if (familyId) {
      const member = await familyMember(pool, familyId, req.identity.sub);
      if (!member) return res.status(403).json({ error: 'family_membership_required' });
    }
    if ((visibility === 'family' || visibility === 'parent_guardian') && !familyId) {
      return res.status(400).json({ error: 'family_required_for_visibility' });
    }
    if (req.body.subjectId) {
      const s = await pool.query('select student_user_id from subject where id=$1', [req.body.subjectId]);
      if (!s.rowCount || s.rows[0].student_user_id !== req.identity.sub) {
        return res.status(403).json({ error: 'subject_forbidden' });
      }
    }

    const client = await pool.connect();
    try {
      await client.query('begin');
      const r = await client.query(
        `insert into plan_item(
           owner_user_id,family_id,subject_id,kind,title,notes,status,priority,visibility,
           starts_at,due_at,duration_minutes,recurrence_rule,parent_item_id
         ) values($1,$2,$3,$4,$5,$6,'planned',$7,$8,$9,$10,$11,$12,$13)
         returning *`,
        [
          req.identity.sub, familyId, req.body.subjectId || null, kind, title,
          req.body.notes || null, priority, visibility, startsAt, dueAt,
          req.body.durationMinutes || null, req.body.recurrenceRule || null,
          req.body.parentItemId || null,
        ],
      );
      const item = r.rows[0];

      const selected = Array.isArray(req.body.selectedMemberIds)
        ? [...new Set(req.body.selectedMemberIds.map(String))]
        : [];
      if (visibility === 'selected_members') {
        if (!familyId || selected.length === 0) {
          await client.query('rollback');
          return res.status(400).json({ error: 'selected_members_required' });
        }
        for (const userId of selected) {
          const m = await client.query(
            'select 1 from family_membership where family_id=$1 and user_id=$2 and ended_at is null',
            [familyId, userId],
          );
          if (!m.rowCount) {
            await client.query('rollback');
            return res.status(400).json({ error: 'selected_member_not_in_family' });
          }
          await client.query(
            `insert into sharing_grant(resource_type,resource_id,grantee_user_id,granted_by)
             values('plan_item',$1,$2,$3)
             on conflict do nothing`,
            [item.id, userId, req.identity.sub],
          );
        }
      }

      const leadTimes = Array.isArray(req.body.reminderMinutesBefore)
        ? [...new Set(req.body.reminderMinutesBefore.map(Number))]
        : [];
      const baseTime = startsAt ?? dueAt;
      if (baseTime) {
        for (const minutes of leadTimes) {
          if (!Number.isInteger(minutes) || minutes < 0 || minutes > 10080) continue;
          await client.query(
            `insert into reminder(plan_item_id,owner_user_id,minutes_before,scheduled_for)
             values($1,$2,$3,$4 - make_interval(mins => $3))
             on conflict(plan_item_id,owner_user_id,minutes_before)
             do update set scheduled_for=excluded.scheduled_for,status='scheduled',claimed_at=null`,
            [item.id, req.identity.sub, minutes, baseTime],
          );
        }
      }

      await client.query('commit');
      res.status(201).json(item);
    } catch (e) {
      await client.query('rollback').catch(() => {});
      throw e;
    } finally {
      client.release();
    }
  });

  router.patch('/plan-items/:itemId', auth, async (req, res) => {
    const access = await assertPlanWrite(pool, req.params.itemId, req.identity.sub);
    if (access.error) return res.status(access.status).json({ error: access.error });

    const fields = [];
    const values = [req.params.itemId];
    const add = (column, value, cast = '') => {
      values.push(value);
      fields.push(`${column}=$${values.length}${cast}`);
    };
    if (req.body.title != null) {
      const title = String(req.body.title).trim();
      if (!title) return res.status(400).json({ error: 'invalid_title' });
      add('title', title);
    }
    if (req.body.notes !== undefined) add('notes', req.body.notes || null);
    if (req.body.status != null) {
      const status = String(req.body.status);
      if (!allowedStatus.has(status)) return res.status(400).json({ error: 'invalid_status' });
      add('status', status);
      if (status === 'completed') add('completed_at', new Date());
      if (status !== 'completed') add('completed_at', null);
    }
    if (req.body.priority != null) {
      const priority = String(req.body.priority);
      if (!allowedPriority.has(priority)) return res.status(400).json({ error: 'invalid_priority' });
      add('priority', priority);
    }
    if (req.body.startsAt !== undefined) add('starts_at', asDate(req.body.startsAt));
    if (req.body.dueAt !== undefined) add('due_at', asDate(req.body.dueAt));
    if (req.body.durationMinutes !== undefined) add('duration_minutes', req.body.durationMinutes || null);
    if (!fields.length) return res.status(400).json({ error: 'no_changes' });
    fields.push('updated_at=now()');

    const client = await pool.connect();
    try {
      await client.query('begin');
      const r = await client.query(
        `update plan_item set ${fields.join(',')} where id=$1 returning *`,
        values,
      );
      if (r.rows[0].status === 'completed' || r.rows[0].status === 'cancelled') {
        await client.query(
          `update reminder set status='cancelled'
            where plan_item_id=$1 and status in ('scheduled','claimed')`,
          [req.params.itemId],
        );
      } else {
        await client.query('select recompute_reminder_schedule($1)', [req.params.itemId]);
      }
      await client.query('commit');
      res.json(r.rows[0]);
    } catch (e) {
      await client.query('rollback').catch(() => {});
      throw e;
    } finally {
      client.release();
    }
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
    const title = String(req.body.title ?? '').trim();
    const startsOn = req.body.startsOn;
    const endsOn = req.body.endsOn;
    const lifeContextId = req.body.lifeContextId;
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
    const y = await pool.query(
      'select student_user_id from academic_year where id=$1',
      [req.params.yearId],
    );
    if (!y.rowCount) return res.status(404).json({ error: 'not_found' });
    if (y.rows[0].student_user_id !== req.identity.sub) {
      return res.status(403).json({ error: 'forbidden' });
    }
    const r = await pool.query(
      `insert into academic_term(academic_year_id,title,starts_on,ends_on)
       values($1,$2,$3,$4) returning *`,
      [req.params.yearId, String(req.body.title ?? '').trim(), req.body.startsOn, req.body.endsOn],
    );
    res.status(201).json(r.rows[0]);
  });

  router.post('/school/terms/:termId/subjects', auth, async (req, res) => {
    const t = await pool.query(
      `select y.student_user_id
         from academic_term t
         join academic_year y on y.id=t.academic_year_id
        where t.id=$1`,
      [req.params.termId],
    );
    if (!t.rowCount) return res.status(404).json({ error: 'not_found' });
    if (t.rows[0].student_user_id !== req.identity.sub) {
      return res.status(403).json({ error: 'forbidden' });
    }
    const name = String(req.body.name ?? '').trim();
    if (!name) return res.status(400).json({ error: 'invalid_subject' });
    const r = await pool.query(
      `insert into subject(student_user_id,academic_term_id,name,teacher_name,color_key)
       values($1,$2,$3,$4,$5) returning *`,
      [req.identity.sub, req.params.termId, name, req.body.teacherName || null, req.body.colorKey || null],
    );
    res.status(201).json(r.rows[0]);
  });

  router.post('/school/subjects/:subjectId/classes', auth, async (req, res) => {
    const s = await pool.query('select student_user_id from subject where id=$1', [req.params.subjectId]);
    if (!s.rowCount) return res.status(404).json({ error: 'not_found' });
    if (s.rows[0].student_user_id !== req.identity.sub) {
      return res.status(403).json({ error: 'forbidden' });
    }
    const weekday = Number(req.body.weekday);
    if (!Number.isInteger(weekday) || weekday < 1 || weekday > 7) {
      return res.status(400).json({ error: 'invalid_weekday' });
    }
    const r = await pool.query(
      `insert into class_session(subject_id,weekday,starts_at,ends_at,location,recurrence_until)
       values($1,$2,$3,$4,$5,$6) returning *`,
      [req.params.subjectId, weekday, req.body.startsAt, req.body.endsAt, req.body.location || null, req.body.recurrenceUntil || null],
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
        `select * from academic_year where student_user_id=$1 and active order by starts_on desc`,
        [studentUserId],
      ),
      pool.query(
        `select s.*,t.title as term_title,y.title as year_title
           from subject s join academic_term t on t.id=s.academic_term_id
           join academic_year y on y.id=t.academic_year_id
          where s.student_user_id=$1 order by s.name`,
        [studentUserId],
      ),
      pool.query(
        `select *
           from plan_item
          where owner_user_id=$1
            and kind in ('assignment','exam','study_session')
            and status not in ('completed','cancelled')
          order by coalesce(due_at,starts_at) nulls last`,
        [studentUserId],
      ),
      pool.query(
        `select id,title,subject_id,grade_points,grade_out_of,due_at
           from plan_item
          where owner_user_id=$1
            and grade_points is not null
            and grade_out_of is not null
          order by due_at desc nulls last`,
        [studentUserId],
      ),
    ]);
    res.json({
      years: years.rows,
      subjects: subjects.rows,
      workload: workload.rows,
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
        where s.student_user_id=$1
        order by c.weekday,c.starts_at`,
      [req.params.studentUserId],
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
    const r = await pool.query(
      `update plan_item set grade_points=$2,grade_out_of=$3,updated_at=now()
        where id=$1 returning *`,
      [req.params.itemId, points, outOf],
    );
    res.json(r.rows[0]);
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
    res.json({ items: r.rows });
  });

  router.get('/families/:familyId/children/:studentUserId/support-summary', auth, async (req, res) => {
    const familyId = req.params.familyId;
    const studentUserId = req.params.studentUserId;
    const g = await pool.query(
      `select 1 from guardian_relationship
        where family_id=$1 and guardian_user_id=$2 and minor_user_id=$3 and active`,
      [familyId, req.identity.sub, studentUserId],
    );
    if (!g.rowCount) return res.status(403).json({ error: 'guardian_required' });

    const [upcoming, completed, overdue, study, grades] = await Promise.all([
      pool.query(
        `select id,kind,title,due_at,starts_at,priority,status
           from plan_item
          where owner_user_id=$1
            and kind in ('assignment','exam','study_session')
            and status not in ('completed','cancelled')
            and coalesce(due_at,starts_at) >= now()
            and coalesce(due_at,starts_at) < now()+interval '14 days'
          order by coalesce(due_at,starts_at) limit 20`,
        [studentUserId],
      ),
      pool.query(
        `select count(*)::int as n from plan_item
          where owner_user_id=$1 and kind in ('assignment','study_session') and status='completed'
            and completed_at >= now()-interval '7 days'`,
        [studentUserId],
      ),
      pool.query(
        `select count(*)::int as n from plan_item
          where owner_user_id=$1 and kind in ('assignment','study_session')
            and status not in ('completed','cancelled') and due_at < now()`,
        [studentUserId],
      ),
      pool.query(
        `select coalesce(sum(duration_minutes),0)::int as minutes
           from plan_item
          where owner_user_id=$1 and kind='study_session' and status='completed'
            and completed_at >= now()-interval '7 days'`,
        [studentUserId],
      ),
      pool.query(
        `select
           case when sum(grade_out_of)>0 then round(sum(grade_points)/sum(grade_out_of)*100,1) end as percent
           from plan_item
          where owner_user_id=$1 and grade_points is not null and grade_out_of is not null`,
        [studentUserId],
      ),
    ]);
    await audit(pool, req.identity.sub, familyId, 'parent.support_summary.view', 'student', studentUserId);
    res.json({
      upcoming: upcoming.rows,
      metrics: {
        completedLast7Days: completed.rows[0].n,
        overdue: overdue.rows[0].n,
        studyMinutesLast7Days: study.rows[0].minutes,
        gradePercent: grades.rows[0].percent == null ? null : Number(grades.rows[0].percent),
      },
    });
  });

  router.post('/sync/mutations', auth, async (req, res) => {
    const mutations = Array.isArray(req.body.mutations) ? req.body.mutations : [];
    if (mutations.length > 100) {
      return res.status(400).json({ error: 'too_many_mutations' });
    }

    const client = await pool.connect();
    const results = [];
    try {
      for (const mutation of mutations) {
        const id = String(mutation.id ?? '');
        const operation = String(mutation.operation ?? '');
        const entityType = String(mutation.entityType ?? 'plan_item');
        const entityId = mutation.entityId ? String(mutation.entityId) : null;
        const clientUpdatedAt = asDate(mutation.clientUpdatedAt);
        const payload = mutation.payload && typeof mutation.payload === 'object'
          ? mutation.payload
          : {};

        if (
          !id ||
          entityType !== 'plan_item' ||
          !entityId ||
          !clientUpdatedAt ||
          !['update', 'complete', 'reschedule'].includes(operation)
        ) {
          results.push({ id, status: 'rejected', error: 'invalid_mutation' });
          continue;
        }

        await client.query('begin');
        try {
          const duplicate = await client.query(
            'select accepted_at from sync_mutation where id=$1 and user_id=$2',
            [id, req.identity.sub],
          );
          if (duplicate.rowCount) {
            await client.query('rollback');
            results.push({
              id,
              status: 'already_applied',
              acceptedAt: duplicate.rows[0].accepted_at,
            });
            continue;
          }

          const current = await client.query(
            'select * from plan_item where id=$1 for update',
            [entityId],
          );
          if (!current.rowCount) {
            await client.query('rollback');
            results.push({ id, status: 'rejected', error: 'not_found' });
            continue;
          }
          const item = current.rows[0];
          if (item.owner_user_id !== req.identity.sub) {
            await client.query('rollback');
            results.push({ id, status: 'rejected', error: 'forbidden' });
            continue;
          }

          const serverUpdatedAt = new Date(item.updated_at);
          if (serverUpdatedAt.getTime() > clientUpdatedAt.getTime() + 1000) {
            await client.query('rollback');
            results.push({
              id,
              status: 'conflict',
              serverUpdatedAt: serverUpdatedAt.toISOString(),
            });
            continue;
          }

          if (operation === 'complete') {
            await client.query(
              `update plan_item
                  set status='completed',completed_at=now(),updated_at=now()
                where id=$1`,
              [entityId],
            );
            await client.query(
              `update reminder set status='cancelled'
                where plan_item_id=$1 and status in ('scheduled','claimed')`,
              [entityId],
            );
          } else if (operation === 'reschedule') {
            const dueAt = asDate(payload.dueAt);
            const startsAt = asDate(payload.startsAt);
            if (!dueAt && !startsAt) {
              await client.query('rollback');
              results.push({ id, status: 'rejected', error: 'invalid_reschedule' });
              continue;
            }
            await client.query(
              `update plan_item
                  set due_at=coalesce($2,due_at),
                      starts_at=coalesce($3,starts_at),
                      updated_at=now()
                where id=$1`,
              [entityId, dueAt, startsAt],
            );
            await client.query('select recompute_reminder_schedule($1)', [entityId]);
          } else {
            const title = payload.title == null ? null : String(payload.title).trim();
            const status = payload.status == null ? null : String(payload.status);
            if (status != null && !allowedStatus.has(status)) {
              await client.query('rollback');
              results.push({ id, status: 'rejected', error: 'invalid_status' });
              continue;
            }
            await client.query(
              `update plan_item
                  set title=coalesce($2,title),
                      status=coalesce($3::plan_item_status,status),
                      updated_at=now()
                where id=$1`,
              [entityId, title || null, status],
            );
          }

          await client.query(
            `insert into sync_mutation(
               id,user_id,entity_type,entity_id,operation,client_updated_at,payload
             ) values($1,$2,$3,$4,$5,$6,$7::jsonb)`,
            [
              id,
              req.identity.sub,
              entityType,
              entityId,
              operation,
              clientUpdatedAt,
              JSON.stringify(payload),
            ],
          );
          await client.query('commit');
          results.push({ id, status: 'accepted' });
        } catch (error) {
          await client.query('rollback').catch(() => {});
          throw error;
        }
      }
      res.json({ results });
    } finally {
      client.release();
    }
  });

  return router;
}
