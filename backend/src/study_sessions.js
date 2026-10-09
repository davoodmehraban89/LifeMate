import crypto from 'node:crypto';
import express from 'express';

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const states = new Set(['planned', 'started', 'paused', 'completed', 'verified']);
const sources = new Set(['timer', 'self_reported']);
class InputError extends Error {
  constructor(status, code, details = {}) { super(code); this.status = status; this.code = code; this.details = details; }
}
const fail = (status, code, details) => { throw new InputError(status, code, details); };
const uuid = (value) => typeof value === 'string' && uuidPattern.test(value);
function instant(value) {
  if (typeof value !== 'string' || !/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{1,6})?Z$/.test(value)) return null;
  const date = new Date(value);
  return Number.isFinite(date.getTime()) && date.toISOString().slice(0, 19) === value.slice(0, 19) ? date : null;
}
function eventTime(value) {
  const date = instant(value);
  if (!date || date.getTime() > Date.now() + 60000 || date.getTime() < Date.now() - 366 * 86400000) fail(400, 'invalid_timestamp');
  return date;
}
function canonical(value) {
  if (Array.isArray(value)) return value.map(canonical);
  if (value && typeof value === 'object') return Object.fromEntries(Object.keys(value).sort().map((key) => [key, canonical(value[key])]));
  return value;
}
function checkVersion(expected, actual) {
  if (!Number.isSafeInteger(expected) || expected < 0) fail(400, 'expected_version_required');
  if (expected !== Number(actual)) fail(409, 'version_conflict', { serverVersion: Number(actual) });
}
async function ownerLock(client, userId) {
  await client.query('select pg_advisory_xact_lock(hashtextextended($1::text,0))', [userId]);
}
async function guardian(client, familyId, viewerId, childId) {
  const result = await client.query(
    `select 1 from family_workspace f
     where f.id=$1 and f.archived_at is null and is_active_guardian($1,$2,$3)`,
    [familyId, viewerId, childId],
  );
  return result.rowCount > 0;
}
// Current sharing and both current memberships are required in addition to the
// relationship. Reports deliberately project no notes or sensitive table data.
const sharedItem = `(p.visibility='parent_guardian' or p.visibility='family'
  or (p.visibility='selected_members' and exists(
    select 1 from sharing_grant sg where sg.resource_type='plan_item'
      and sg.resource_id=p.id and sg.grantee_user_id=$2 and sg.granted_by=p.owner_user_id)))`;
async function planForOwner(client, id, userId) {
  const result = await client.query('select * from plan_item where id=$1 for update', [id]);
  if (!result.rowCount || result.rows[0].owner_user_id !== userId) fail(404, 'not_found');
  if (result.rows[0].status === 'cancelled') fail(409, 'activity_archived');
  return result.rows[0];
}
async function sessionForOwner(client, id, userId, lock = false) {
  const result = await client.query(`select * from study_session where id=$1 and child_user_id=$2${lock ? ' for update' : ''}`, [id, userId]);
  if (!result.rowCount) fail(404, 'not_found');
  return result.rows[0];
}
async function activity(client, plan) {
  const result = await client.query('select * from activity_state_event where plan_item_id=$1 order by version desc limit 1', [plan.id]);
  const row = result.rows[0];
  return row ? {
    state: row.state, version: Number(row.version), occurredAt: row.occurred_at, acceptedAt: row.accepted_at,
    source: row.source, confirmedBy: row.state === 'verified' ? row.actor_user_id : null,
  } : { state: plan.status === 'completed' ? 'completed' : plan.status === 'in_progress' ? 'started' : 'planned',
    version: Number(plan.activity_version), occurredAt: plan.created_at, acceptedAt: plan.updated_at, source: 'self_reported', confirmedBy: null };
}
async function setActivity(client, plan, actorId, state, source, occurredAt, confirmation = null) {
  const current = await activity(client, plan);
  if (new Date(current.occurredAt).getTime() > occurredAt.getTime() && current.version > 0) fail(409, 'non_monotonic_activity_time');
  const row = (await client.query(
    `update plan_item set activity_version=activity_version+1,status=$2::plan_item_status,
      completed_at=case when $2::plan_item_status='completed' then coalesce(completed_at,$3) else null end,updated_at=now()
     where id=$1 returning *`, [plan.id, ['completed', 'verified'].includes(state) ? 'completed' : state === 'planned' ? 'planned' : 'in_progress', occurredAt],
  )).rows[0];
  await client.query(
    `insert into activity_state_event(plan_item_id,actor_user_id,state,source,occurred_at,version,confirmation)
     values($1,$2,$3,$4,$5,$6,$7)`, [plan.id, actorId, state, source, occurredAt, row.activity_version, confirmation],
  );
  if (row.status === 'completed') await client.query("update reminder set status='cancelled' where plan_item_id=$1 and status in ('scheduled','claimed')", [plan.id]);
  return activity(client, row);
}
async function ensureNoOverlap(client, userId, startsAt, endsAt = null, excludedSession = null) {
  const result = await client.query(
    `select 1 from study_interval i join study_session s on s.id=i.session_id
     where s.child_user_id=$1 and s.archived_at is null and ($4::uuid is null or s.id<>$4)
       and tstzrange(i.starts_at,i.ends_at,'[)') && tstzrange($2::timestamptz,$3::timestamptz,'[)') limit 1`,
    [userId, startsAt, endsAt, excludedSession],
  );
  if (result.rowCount) fail(409, 'study_time_overlap');
}
async function sessionJson(client, row) {
  const result = await client.query('select starts_at,ends_at from study_interval where session_id=$1 order by starts_at,id', [row.id]);
  return { id: row.id, childId: row.child_user_id, planItemId: row.plan_item_id, source: row.source, status: row.status,
    startedAt: row.started_at, endedAt: row.ended_at, recordedDurationSeconds: row.recorded_duration_seconds,
    version: row.version, lastSyncAt: row.last_sync_at, lastEventAt: row.last_event_at,
    intervals: result.rows.map((x) => ({ start: x.starts_at, end: x.ends_at })), isEvidenceOfStudy: false };
}
async function readSnapshot(pool, read) {
  const client = await pool.connect();
  try {
    await client.query('begin isolation level repeatable read read only');
    const result = await read(client);
    await client.query('commit');
    return result;
  } catch (error) { await client.query('rollback').catch(() => {}); throw error; }
  finally { client.release(); }
}
async function mutation(pool, req, res, resource, execute, authorize = null) {
  if (!uuid(req.body?.mutationId)) return res.status(400).json({ error: 'mutation_id_required' });
  const hash = crypto.createHash('sha256').update(JSON.stringify(canonical({ resource, payload: req.body }))).digest('hex');
  const client = await pool.connect();
  try {
    await client.query('begin');
    // Serializes one actor's duplicate retries before touching any data.
    await ownerLock(client, req.identity.sub);
    // Guardian confirmation retries must not bypass a subsequently revoked
    // relation, role, membership or resource grant through the idempotency ledger.
    const authorized = authorize ? await authorize(client) : null;
    const previous = await client.query('select * from study_mutation where user_id=$1 and id=$2', [req.identity.sub, req.body.mutationId]);
    if (previous.rowCount) {
      if (previous.rows[0].request_hash !== hash) fail(409, 'mutation_payload_conflict');
      const response = previous.rows[0].response_body;
      response.acknowledgement.status = 'already_applied';
      await client.query('commit');
      return res.status(previous.rows[0].response_status).json(response);
    }
    const { body, status = 200 } = await execute(client, authorized);
    const acceptedAt = (await client.query('select clock_timestamp() as ts')).rows[0].ts;
    body.acknowledgement = { mutationId: req.body.mutationId, acceptedAt, status: 'accepted' };
    await client.query(
      'insert into study_mutation(user_id,id,request_hash,response_body,response_status,accepted_at) values($1,$2,$3,$4::jsonb,$5,$6)',
      [req.identity.sub, req.body.mutationId, hash, JSON.stringify(body), status, acceptedAt],
    );
    await client.query('commit');
    return res.status(status).json(body);
  } catch (error) {
    await client.query('rollback').catch(() => {});
    if (error instanceof InputError) return res.status(error.status).json({ error: error.code, ...error.details });
    if (error.code === '23505') return res.status(409).json({ error: 'study_session_exists' });
    throw error;
  } finally { client.release(); }
}

export function createStudySessionsRouter({ pool, auth }) {
  const router = express.Router();
  router.use(auth);
  router.post('/study/sessions', async (req, res) => mutation(pool, req, res, 'session:create', async (client) => {
    const { id, planItemId, source, childId } = req.body;
    if (!uuid(id) || !uuid(planItemId) || !sources.has(source) || req.body.recordedDurationSeconds !== undefined) fail(400, 'invalid_study_session');
    if (childId !== undefined && childId !== req.identity.sub) fail(403, 'forbidden');
    const startedAt = eventTime(req.body.startedAt);
    const endedAt = source === 'self_reported' ? eventTime(req.body.endedAt) : null;
    if ((endedAt && endedAt <= startedAt) || (source === 'timer' && req.body.endedAt !== undefined)) fail(400, 'invalid_study_interval');
    const plan = await planForOwner(client, planItemId, req.identity.sub);
    if (plan.status === 'completed') fail(409, 'activity_completed');
    await ensureNoOverlap(client, req.identity.sub, startedAt, endedAt);
    const seconds = endedAt ? Math.floor((endedAt - startedAt) / 1000) : 0;
    const row = (await client.query(
      `insert into study_session(id,child_user_id,plan_item_id,source,status,started_at,ended_at,last_event_at,recorded_duration_seconds)
       values($1,$2,$3,$4,$5,$6,$7,$8,$9) returning *`,
      [id, req.identity.sub, planItemId, source, endedAt ? 'completed' : 'running', startedAt, endedAt, endedAt ?? startedAt, seconds],
    )).rows[0];
    await client.query('insert into study_interval(session_id,starts_at,ends_at) values($1,$2,$3)', [id, startedAt, endedAt]);
    const state = await setActivity(client, plan, req.identity.sub, endedAt ? 'paused' : 'started', source === 'timer' ? 'client_timer' : 'self_reported', endedAt ?? startedAt);
    return { status: 201, body: { session: await sessionJson(client, row), activity: state } };
  }));
  router.get('/study/sessions', async (req, res) => {
    if (req.query.planItemId !== undefined && !uuid(req.query.planItemId)) return res.status(400).json({ error: 'invalid_id' });
    res.json(await readSnapshot(pool, async (client) => {
      const result = await client.query(
        'select * from study_session where child_user_id=$1 and archived_at is null and ($2::uuid is null or plan_item_id=$2) order by started_at desc limit 500',
        [req.identity.sub, req.query.planItemId ?? null],
      );
      return { sessions: await Promise.all(result.rows.map((x) => sessionJson(client, x))), asOf: new Date() };
    }));
  });
  router.get('/study/sessions/:id', async (req, res) => {
    if (!uuid(req.params.id)) return res.status(400).json({ error: 'invalid_id' });
    try { res.json(await readSnapshot(pool, async (client) => ({ session: await sessionJson(client, await sessionForOwner(client, req.params.id, req.identity.sub)), asOf: new Date() }))); }
    catch (error) { if (error instanceof InputError) return res.status(error.status).json({ error: error.code }); throw error; }
  });
  router.patch('/study/sessions/:id', async (req, res) => {
    if (!uuid(req.params.id)) return res.status(400).json({ error: 'invalid_id' });
    return mutation(pool, req, res, `session:correct:${req.params.id}`, async (client) => {
      const row = await sessionForOwner(client, req.params.id, req.identity.sub, true);
      checkVersion(req.body.expectedVersion, row.version);
      if (row.source !== 'self_reported' || row.status !== 'completed') fail(409, 'only_completed_self_report_can_be_corrected');
      if (req.body.recordedDurationSeconds !== undefined) fail(400, 'duration_is_server_computed');
      const startedAt = eventTime(req.body.startedAt);
      const endedAt = eventTime(req.body.endedAt);
      if (endedAt <= startedAt) fail(400, 'invalid_study_interval');
      await ensureNoOverlap(client, req.identity.sub, startedAt, endedAt, row.id);
      await client.query('delete from study_interval where session_id=$1', [row.id]);
      await client.query('insert into study_interval(session_id,starts_at,ends_at) values($1,$2,$3)', [row.id, startedAt, endedAt]);
      const updated = (await client.query(
        `update study_session set started_at=$2,ended_at=$3,last_event_at=$3,recorded_duration_seconds=$4,
         version=version+1,last_sync_at=now(),updated_at=now() where id=$1 returning *`,
        [row.id, startedAt, endedAt, Math.floor((endedAt - startedAt) / 1000)],
      )).rows[0];
      return { body: { session: await sessionJson(client, updated) } };
    });
  });
  router.post('/study/sessions/:id/events', async (req, res) => {
    if (!uuid(req.params.id)) return res.status(400).json({ error: 'invalid_id' });
    return mutation(pool, req, res, `session:event:${req.params.id}`, async (client) => {
      const row = await sessionForOwner(client, req.params.id, req.identity.sub, true);
      checkVersion(req.body.expectedVersion, row.version);
      if (row.status === 'completed' || row.status === 'archived') fail(409, 'study_session_closed');
      const { action } = req.body;
      if (!['pause', 'resume', 'stop'].includes(action)) fail(400, 'invalid_study_action');
      const when = eventTime(req.body.occurredAt);
      if (when < new Date(row.last_event_at)) fail(409, 'non_monotonic_session_time');
      const plan = await planForOwner(client, row.plan_item_id, req.identity.sub);
      if (action === 'resume') {
        if (row.status !== 'paused') fail(409, 'study_not_paused');
        if (plan.status === 'completed') fail(409, 'activity_completed');
        await ensureNoOverlap(client, req.identity.sub, when);
        await client.query('insert into study_interval(session_id,starts_at) values($1,$2)', [row.id, when]);
      } else if (row.status === 'running') {
        await client.query('update study_interval set ends_at=$2 where session_id=$1 and ends_at is null', [row.id, when]);
      } else if (action === 'pause') fail(409, 'study_not_running');
      const updated = (await client.query(
        `update study_session set status=$2,ended_at=$3,last_event_at=$4,
         recorded_duration_seconds=(select floor(coalesce(sum(extract(epoch from ends_at-starts_at)),0))::int from study_interval where session_id=$1),
         version=version+1,last_sync_at=now(),updated_at=now() where id=$1 returning *`,
        [row.id, action === 'stop' ? 'completed' : action === 'pause' ? 'paused' : 'running', action === 'stop' ? when : null, when],
      )).rows[0];
      const current = await activity(client, plan);
      const state = plan.status === 'completed' ? current : await setActivity(client, plan, req.identity.sub, action === 'resume' ? 'started' : 'paused', 'client_timer', when);
      return { body: { session: await sessionJson(client, updated), activity: state } };
    });
  });
  router.delete('/study/sessions/:id', async (req, res) => {
    if (!uuid(req.params.id)) return res.status(400).json({ error: 'invalid_id' });
    return mutation(pool, req, res, `session:archive:${req.params.id}`, async (client) => {
      const row = await sessionForOwner(client, req.params.id, req.identity.sub, true);
      checkVersion(req.body.expectedVersion, row.version);
      if (row.status === 'running' || row.status === 'paused') fail(409, 'stop_session_before_archive');
      if (row.status === 'archived') fail(409, 'study_session_closed');
      const updated = (await client.query("update study_session set status='archived',archived_at=now(),version=version+1,last_sync_at=now(),updated_at=now() where id=$1 returning *", [row.id])).rows[0];
      return { body: { session: await sessionJson(client, updated) } };
    });
  });
  router.post('/plan-items/:id/activity-state', async (req, res) => {
    if (!uuid(req.params.id)) return res.status(400).json({ error: 'invalid_id' });
    const authorize = async (client) => {
      const result = await client.query('select * from plan_item where id=$1', [req.params.id]);
      if (!result.rowCount) fail(404, 'not_found');
      const candidate = result.rows[0];
      if (candidate.owner_user_id !== req.identity.sub) await ownerLock(client, candidate.owner_user_id);
      const plan = (await client.query('select * from plan_item where id=$1 for update', [req.params.id])).rows[0];
      if (!plan) fail(404, 'not_found');
      if (req.body.state === 'verified') {
        if (!plan.family_id || plan.owner_user_id === req.identity.sub || !await guardian(client, plan.family_id, req.identity.sub, plan.owner_user_id)) fail(403, 'forbidden');
        const shared = await client.query(`select 1 from plan_item p where p.id=$1 and ${sharedItem}`, [plan.id, req.identity.sub]);
        if (!shared.rowCount) fail(403, 'forbidden');
      } else if (plan.owner_user_id !== req.identity.sub) fail(403, 'forbidden');
      return plan;
    };
    return mutation(pool, req, res, `activity:${req.params.id}`, async (client, plan) => {
      const verified = req.body.state === 'verified';
      if (plan.status === 'cancelled') fail(409, 'activity_archived');
      const current = await activity(client, plan);
      checkVersion(req.body.expectedVersion, plan.activity_version);
      const state = req.body.state;
      if (!states.has(state)) fail(400, 'invalid_activity_state');
      const source = req.body.source;
      const when = eventTime(req.body.occurredAt);
      let confirmation = null;
      if (verified) {
        confirmation = typeof req.body.confirmation === 'string' ? req.body.confirmation.trim() : '';
        if (source !== 'guardian_confirmation' || !confirmation || confirmation.length > 1000) fail(400, 'explicit_confirmation_required');
        if (current.state !== 'completed') fail(409, 'complete_before_verification');
      } else if (!['client_timer', 'self_reported'].includes(source) || req.body.confirmation !== undefined) fail(400, 'invalid_activity_source');
      if (state === current.state) fail(409, 'activity_state_unchanged');
      if (['completed', 'verified'].includes(current.state) && !['planned', 'verified'].includes(state)) fail(409, 'reopen_activity_first');
      const next = await setActivity(client, plan, req.identity.sub, state, source, when, confirmation);
      const updated = (await client.query('select version from plan_item where id=$1', [plan.id])).rows[0];
      return { body: { activity: next, planItemId: plan.id, planVersion: Number(updated.version) } };
    }, authorize);
  });
  router.get('/plan-items/:id/activity-state', async (req, res) => {
    if (!uuid(req.params.id)) return res.status(400).json({ error: 'invalid_id' });
    try {
      res.json(await readSnapshot(pool, async (client) => {
        const plan = (await client.query('select * from plan_item where id=$1', [req.params.id])).rows[0];
        if (!plan) fail(404, 'not_found');
        if (plan.owner_user_id !== req.identity.sub) {
          if (!plan.family_id || !await guardian(client, plan.family_id, req.identity.sub, plan.owner_user_id)) fail(403, 'forbidden');
          if (!(await client.query(`select 1 from plan_item p where p.id=$1 and ${sharedItem}`, [plan.id, req.identity.sub])).rowCount) fail(403, 'forbidden');
        }
        const rows = (await client.query(
          'select state,source,occurred_at,accepted_at,version,actor_user_id from activity_state_event where plan_item_id=$1 order by version desc limit 500', [plan.id],
        )).rows.reverse();
        return { planItemId: plan.id, planVersion: Number(plan.version), activity: await activity(client, plan),
          history: rows.map((x) => ({ state: x.state, source: x.source, occurredAt: x.occurred_at, acceptedAt: x.accepted_at,
            version: Number(x.version), confirmedBy: x.state === 'verified' ? x.actor_user_id : null })), asOf: new Date() };
      }));
    } catch (error) { if (error instanceof InputError) return res.status(error.status).json({ error: error.code }); throw error; }
  });
  router.get('/families/:familyId/children/:childId/learning-report', async (req, res) => {
    if (!uuid(req.params.familyId) || !uuid(req.params.childId)) return res.status(400).json({ error: 'invalid_id' });
    const to = req.query.to === undefined ? new Date() : instant(req.query.to);
    const from = req.query.from === undefined && to ? new Date(to.getTime() - 30 * 86400000) : instant(req.query.from);
    if (!from || !to || to <= from || to - from > 366 * 86400000) return res.status(400).json({ error: 'invalid_report_range' });
    const client = await pool.connect();
    try {
      await client.query('begin isolation level repeatable read read only');
      if (!await guardian(client, req.params.familyId, req.identity.sub, req.params.childId)) { await client.query('rollback'); return res.status(403).json({ error: 'forbidden' }); }
      const asOf = (await client.query('select clock_timestamp() as ts')).rows[0].ts;
      const items = (await client.query(
        `select p.id,p.title,p.kind,p.status,p.priority,p.starts_at,p.due_at,p.duration_minutes,p.planned_duration_seconds,p.completed_at,p.updated_at,p.version,
          p.activity_version,sub.name as subject_name,p.grade_points,p.grade_out_of,
          e.state as activity_state,e.source as activity_source,e.occurred_at as activity_at
         from plan_item p left join subject sub on sub.id=p.subject_id
         left join lateral(select state,source,occurred_at from activity_state_event where plan_item_id=p.id order by version desc limit 1) e on true
         where p.family_id=$1 and p.owner_user_id=$3 and p.status<>'cancelled' and ${sharedItem}
         order by coalesce(p.starts_at,p.due_at,p.created_at),p.id`,
        [req.params.familyId, req.identity.sub, req.params.childId],
      )).rows;
      const ids = items.map((x) => x.id);
      const intervals = (await client.query(
        `select s.id,s.plan_item_id,s.source,s.last_sync_at,s.version,
           greatest(i.starts_at,$2::timestamptz) as starts_at,
           least(coalesce(i.ends_at,$4::timestamptz),$3::timestamptz,$4::timestamptz) as ends_at
         from study_session s join study_interval i on i.session_id=s.id
         where s.plan_item_id=any($1::uuid[]) and s.archived_at is null and i.starts_at<$3
           and coalesce(i.ends_at,$4)>$2`, [ids, from, to, asOf],
      )).rows.filter((x) => x.ends_at > x.starts_at);
      const timeByItem = new Map();
      const daily = new Map();
      let totalMilliseconds = 0;
      for (const interval of intervals) {
        const milliseconds = interval.ends_at - interval.starts_at;
        totalMilliseconds += milliseconds;
        timeByItem.set(interval.plan_item_id, (timeByItem.get(interval.plan_item_id) ?? 0) + milliseconds);
        // Split at Tehran midnight. Recorded time is never inferred as learning evidence.
        let start = interval.starts_at.getTime();
        const end = interval.ends_at.getTime();
        while (start < end) {
          const local = new Date(start + 210 * 60000);
          const key = local.toISOString().slice(0, 10);
          const next = Date.UTC(local.getUTCFullYear(), local.getUTCMonth(), local.getUTCDate() + 1) - 210 * 60000;
          const part = Math.min(end, next) - start;
          daily.set(key, (daily.get(key) ?? 0) + part);
          start += part;
        }
      }
      const projected = items.map((x) => ({ id: x.id, title: x.title, kind: x.kind, status: x.status, priority: x.priority, version: Number(x.version),
        startsAt: x.starts_at, dueAt: x.due_at, plannedDurationSeconds: x.planned_duration_seconds ?? (x.duration_minutes ?? 0) * 60,
        recordedDurationSeconds: Math.floor((timeByItem.get(x.id) ?? 0) / 1000), completedAt: x.completed_at,
        activityState: x.activity_state ?? (x.status === 'completed' ? 'completed' : x.status === 'in_progress' ? 'started' : 'planned'),
        activitySource: x.activity_source ?? 'self_reported', activityAt: x.activity_at ?? x.updated_at,
        subjectName: x.subject_name, gradePoints: x.grade_points, gradeOutOf: x.grade_out_of }));
      const planned = projected.filter((x) => { const at = x.startsAt ?? x.dueAt; return at && new Date(at) >= from && new Date(at) < to; });
      const complete = projected.filter((x) => x.status === 'completed').length;
      const latest = [...items.map((x) => x.updated_at), ...intervals.map((x) => x.last_sync_at)].sort((a, b) => b - a)[0] ?? null;
      const subjects = new Map();
      for (const item of projected) {
        const key = item.subjectName ?? 'بدون درس';
        const existing = subjects.get(key) ?? { subjectName: key, totalTasks: 0, completedTasks: 0, recordedDurationSeconds: 0 };
        existing.totalTasks++;
        if (item.status === 'completed') existing.completedTasks++;
        existing.recordedDurationSeconds += item.recordedDurationSeconds;
        subjects.set(key, existing);
      }
      const response = { childId: req.params.childId, familyId: req.params.familyId, from, to, asOf, lastSyncAt: latest,
        sourceVersion: crypto.createHash('sha256').update(JSON.stringify({ items: items.map((x) => [x.id, x.updated_at, x.activity_version]), intervals: intervals.map((x) => [x.id, x.version, x.last_sync_at]) })).digest('hex'),
        timezone: 'Asia/Tehran', recordingDisclaimerKey: 'recorded_time_is_not_proof_of_study', items: projected,
        metrics: { totalTasks: projected.length, completedTasks: complete, completionPercent: projected.length ? Math.round(complete * 100 / projected.length) : 0,
          overdueTasks: projected.filter((x) => x.status !== 'completed' && x.dueAt && new Date(x.dueAt) < asOf).length,
          plannedDurationSeconds: projected.reduce((sum, x) => sum + x.plannedDurationSeconds, 0),
          plannedInRangeDurationSeconds: planned.reduce((sum, x) => sum + x.plannedDurationSeconds, 0),
          recordedDurationSeconds: Math.floor(totalMilliseconds / 1000) },
        daily: [...daily.entries()].sort(([a], [b]) => a.localeCompare(b)).map(([date, ms]) => ({ date, recordedDurationSeconds: Math.floor(ms / 1000) })),
        subjects: [...subjects.values()], sources: [...new Set(intervals.map((x) => x.source))], isEvidenceOfStudy: false };
      await client.query('commit');
      res.json(response);
    } catch (error) { await client.query('rollback').catch(() => {}); throw error; }
    finally { client.release(); }
  });
  return router;
}
