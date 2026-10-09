import express from 'express';

const uuid = (value) => typeof value === 'string' && /^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$/i.test(value);
const has = (body, key) => Object.hasOwn(body, key);
class SchoolInputError extends Error {
  constructor(status, code) { super(code); this.status = status; this.code = code; }
}
const fail = (status, code) => { throw new SchoolInputError(status, code); };
function id(value) { if (!uuid(value)) fail(400, 'invalid_id'); return value; }
function text(value, max, nullable = false) {
  if (nullable && value == null) return null;
  if (nullable && typeof value === 'string' && !value.trim()) return null;
  if (typeof value !== 'string' || !value.trim() || value.trim().length > max) fail(400, 'invalid_input');
  return value.trim();
}
function date(value) {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value) || value.startsWith('0000-')) return null;
  const parsed = new Date(`${value}T00:00:00Z`);
  return Number.isFinite(parsed.getTime()) && parsed.toISOString().slice(0, 10) === value ? value : null;
}
function time(value) {
  if (typeof value !== 'string' || !/^(?:[01]\d|2[0-3]):[0-5]\d(?::[0-5]\d)?$/.test(value)) fail(400, 'invalid_class_time');
  return value.length === 5 ? value + ':00' : value;
}
function occurred(value) {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?Z$/.test(value)) fail(400, 'invalid_occurred_at');
  const parsed = new Date(value);
  if (!Number.isFinite(parsed.getTime()) || parsed.toISOString().slice(0, 19) !== value.slice(0, 19) || parsed.getTime() > Date.now() + 60000) fail(400, 'invalid_occurred_at');
  return parsed;
}
const checkinRow = (row) => ({ ...row, isEvidenceOfStudy: false });
const route = (handler) => async (req, res, next) => {
  try { await handler(req, res); }
  catch (error) {
    if (error instanceof SchoolInputError) return res.status(error.status).json({ error: error.code });
    next(error);
  }
};
async function transaction(pool, operation) {
  const client = await pool.connect();
  try {
    await client.query('begin');
    const result = await operation(client);
    await client.query('commit');
    return result;
  } catch (error) {
    await client.query('rollback').catch(() => {});
    throw error;
  } finally { client.release(); }
}
async function ownedTerm(client, termId, userId, status = 403) {
  const result = await client.query(`select t.*,t.starts_on::text as first_day,t.ends_on::text as last_day
    from academic_term t join academic_year y on y.id=t.academic_year_id
    join life_context l on l.id=y.life_context_id
    where t.id=$1 and y.student_user_id=$2 and l.user_id=$2 and y.active and l.active
    for share of t,y,l`, [termId, userId]);
  if (!result.rowCount) fail(status, status === 403 ? 'academic_term_forbidden' : 'school_parent_inactive');
  return result.rows[0];
}
async function activeSubject(client, subjectId, userId) {
  const result = await client.query('select * from subject where id=$1 and student_user_id=$2 for share', [subjectId, userId]);
  if (!result.rowCount) fail(403, 'subject_forbidden');
  if (result.rows[0].archived_at) fail(409, 'subject_archived');
  return { subject: result.rows[0], term: await ownedTerm(client, result.rows[0].academic_term_id, userId, 409) };
}
function classFields(body, current) {
  const next = { ...current };
  if (has(body, 'weekday')) {
    if (!Number.isInteger(body.weekday) || body.weekday < 1 || body.weekday > 7) fail(400, 'invalid_weekday');
    next.weekday = body.weekday;
  }
  if (has(body, 'startsAt')) next.starts_at = time(body.startsAt);
  if (has(body, 'endsAt')) next.ends_at = time(body.endsAt);
  if (next.ends_at <= next.starts_at) fail(400, 'invalid_class_time');
  if (has(body, 'location')) next.location = text(body.location, 240, true);
  if (has(body, 'recurrenceUntil')) {
    if (body.recurrenceUntil != null && !date(body.recurrenceUntil)) fail(400, 'invalid_recurrence_date');
    next.recurrence_until = body.recurrenceUntil ?? null;
  }
  return next;
}
function checkinFields(body, current) {
  const next = { ...current };
  for (const field of ['confidence', 'difficulty']) if (has(body, field)) {
    if (!Number.isInteger(body[field]) || body[field] < 1 || body[field] > 5) fail(400, 'invalid_input');
    next[field] = body[field];
  }
  if (has(body, 'note')) next.note = text(body.note, 2000, true);
  if (has(body, 'learningGoalId')) next.learning_goal_id = body.learningGoalId == null ? null : id(body.learningGoalId);
  if (has(body, 'occurredAt')) next.occurred_at = occurred(body.occurredAt);
  if ((has(body, 'source') && body.source !== 'self_reported') || (has(body, 'isEvidenceOfStudy') && body.isEvidenceOfStudy !== false)) fail(400, 'self_report_only');
  return next;
}
async function ownedGoal(client, goalId, userId) {
  if (goalId == null) return;
  const result = await client.query("select 1 from learning_goal where id=$1 and owner_user_id=$2 and status<>'archived' for share", [goalId, userId]);
  if (!result.rowCount) fail(403, 'learning_goal_forbidden');
}

export function createSchoolCrudRouter({ pool, auth }) {
  const router = express.Router();
  router.post('/school/subjects/:id/classes', auth, route(async (req, res) => {
    const subjectId = id(req.params.id), body = req.body ?? {};
    if (!['weekday', 'startsAt', 'endsAt'].every((key) => has(body, key))) fail(400, 'invalid_input');
    const next = classFields(body, { location: null, recurrence_until: null });
    const result = await transaction(pool, async (client) => {
      const { term } = await activeSubject(client, subjectId, req.identity.sub);
      if (next.recurrence_until && (next.recurrence_until < term.first_day || next.recurrence_until > term.last_day)) fail(400, 'class_recurrence_outside_term');
      return (await client.query(`insert into class_session(subject_id,weekday,starts_at,ends_at,location,recurrence_until)
        values($1,$2,$3,$4,$5,$6) returning *`, [subjectId, next.weekday, next.starts_at, next.ends_at, next.location, next.recurrence_until])).rows[0];
    });
    res.status(201).json(result);
  }));
  router.get('/school/subjects/:id', auth, route(async (req, res) => {
    const result = await pool.query('select * from subject where id=$1 and student_user_id=$2', [id(req.params.id), req.identity.sub]);
    if (!result.rowCount) fail(404, 'subject_not_found');
    res.json(result.rows[0]);
  }));
  router.patch('/school/subjects/:id', auth, route(async (req, res) => {
    const subjectId = id(req.params.id), body = req.body ?? {};
    if (!['name', 'teacherName', 'colorKey', 'academicTermId'].some((key) => has(body, key))) fail(400, 'invalid_input');
    const name = has(body, 'name') ? text(body.name, 120) : null;
    const teacher = has(body, 'teacherName') ? text(body.teacherName, 120, true) : null;
    const color = has(body, 'colorKey') ? text(body.colorKey, 40, true) : null;
    if (has(body, 'academicTermId')) id(body.academicTermId);
    const result = await transaction(pool, async (client) => {
      const current = await client.query('select * from subject where id=$1 and student_user_id=$2 for update', [subjectId, req.identity.sub]);
      if (!current.rowCount) fail(404, 'subject_not_found');
      if (current.rows[0].archived_at) fail(409, 'subject_archived');
      const termId = body.academicTermId ?? current.rows[0].academic_term_id;
      const term = await ownedTerm(client, termId, req.identity.sub, has(body, 'academicTermId') ? 403 : 409);
      const invalidClass = await client.query(`select 1 from class_session where subject_id=$1 and archived_at is null
        and recurrence_until is not null and (recurrence_until<$2::date or recurrence_until>$3::date) limit 1`, [subjectId, term.first_day, term.last_day]);
      if (invalidClass.rowCount) fail(400, 'class_recurrence_outside_term');
      return (await client.query(`update subject set name=coalesce($3,name),
        teacher_name=case when $4 then $5 else teacher_name end,
        color_key=case when $6 then $7 else color_key end,academic_term_id=$8,updated_at=now()
        where id=$1 and student_user_id=$2 returning *`, [subjectId, req.identity.sub, name, has(body, 'teacherName'), teacher, has(body, 'colorKey'), color, termId])).rows[0];
    });
    res.json(result);
  }));
  router.delete('/school/subjects/:id', auth, route(async (req, res) => {
    const result = await pool.query(`update subject set updated_at=case when archived_at is null then now() else updated_at end,
      archived_at=coalesce(archived_at,now()) where id=$1 and student_user_id=$2 returning id`, [id(req.params.id), req.identity.sub]);
    if (!result.rowCount) fail(404, 'subject_not_found');
    res.status(204).end();
  }));

  router.get('/school/classes/:id', auth, route(async (req, res) => {
    const result = await pool.query(`select c.*,s.name as subject_name,s.archived_at as subject_archived_at
      from class_session c join subject s on s.id=c.subject_id where c.id=$1 and s.student_user_id=$2`, [id(req.params.id), req.identity.sub]);
    if (!result.rowCount) fail(404, 'class_not_found');
    res.json(result.rows[0]);
  }));
  router.patch('/school/classes/:id', auth, route(async (req, res) => {
    const classId = id(req.params.id), body = req.body ?? {};
    if (!['subjectId', 'weekday', 'startsAt', 'endsAt', 'location', 'recurrenceUntil'].some((key) => has(body, key))) fail(400, 'invalid_input');
    if (has(body, 'subjectId')) id(body.subjectId);
    const result = await transaction(pool, async (client) => {
      const current = await client.query(`select c.*,c.recurrence_until::text as recurrence_until
        from class_session c join subject s on s.id=c.subject_id
        where c.id=$1 and s.student_user_id=$2 for update of c`, [classId, req.identity.sub]);
      if (!current.rowCount) fail(404, 'class_not_found');
      if (current.rows[0].archived_at) fail(409, 'class_archived');
      await activeSubject(client, current.rows[0].subject_id, req.identity.sub);
      const subjectId = body.subjectId ?? current.rows[0].subject_id;
      const { term } = await activeSubject(client, subjectId, req.identity.sub);
      const next = classFields(body, current.rows[0]);
      if (next.recurrence_until && (next.recurrence_until < term.first_day || next.recurrence_until > term.last_day)) fail(400, 'class_recurrence_outside_term');
      return (await client.query(`update class_session set subject_id=$2,weekday=$3,starts_at=$4,ends_at=$5,
        location=$6,recurrence_until=$7,updated_at=now() where id=$1 returning *`, [classId, subjectId, next.weekday, next.starts_at, next.ends_at, next.location, next.recurrence_until])).rows[0];
    });
    res.json(result);
  }));
  router.delete('/school/classes/:id', auth, route(async (req, res) => {
    const result = await pool.query(`update class_session c set updated_at=case when c.archived_at is null then now() else c.updated_at end,
      archived_at=coalesce(c.archived_at,now()) from subject s
      where c.id=$1 and c.subject_id=s.id and s.student_user_id=$2 returning c.id`, [id(req.params.id), req.identity.sub]);
    if (!result.rowCount) fail(404, 'class_not_found');
    res.status(204).end();
  }));

  router.post('/learning/checkins', auth, route(async (req, res) => {
    const body = req.body ?? {};
    if (!has(body, 'confidence') || !has(body, 'difficulty')) fail(400, 'invalid_input');
    const next = checkinFields(body, { learning_goal_id: null, note: null, occurred_at: new Date() });
    const result = await transaction(pool, async (client) => {
      await ownedGoal(client, next.learning_goal_id, req.identity.sub);
      return (await client.query(`insert into learning_checkin(owner_user_id,learning_goal_id,confidence,difficulty,note,occurred_at)
        values($1,$2,$3,$4,$5,$6) returning *`, [req.identity.sub, next.learning_goal_id, next.confidence, next.difficulty, next.note, next.occurred_at])).rows[0];
    });
    res.status(201).json(checkinRow(result));
  }));
  router.get('/learning/checkins', auth, route(async (req, res) => {
    const result = await pool.query('select * from learning_checkin where owner_user_id=$1 and archived_at is null order by occurred_at desc,id', [req.identity.sub]);
    res.json({ items: result.rows.map(checkinRow) });
  }));
  router.get('/learning/checkins/:id', auth, route(async (req, res) => {
    const result = await pool.query('select * from learning_checkin where id=$1 and owner_user_id=$2', [id(req.params.id), req.identity.sub]);
    if (!result.rowCount) fail(404, 'checkin_not_found');
    res.json(checkinRow(result.rows[0]));
  }));
  router.patch('/learning/checkins/:id', auth, route(async (req, res) => {
    const checkinId = id(req.params.id), body = req.body ?? {};
    if (!['learningGoalId', 'confidence', 'difficulty', 'note', 'occurredAt'].some((key) => has(body, key))) fail(400, 'invalid_input');
    const result = await transaction(pool, async (client) => {
      const current = await client.query('select * from learning_checkin where id=$1 and owner_user_id=$2 for update', [checkinId, req.identity.sub]);
      if (!current.rowCount) fail(404, 'checkin_not_found');
      if (current.rows[0].archived_at) fail(409, 'checkin_archived');
      const next = checkinFields(body, current.rows[0]);
      if (has(body, 'learningGoalId')) await ownedGoal(client, next.learning_goal_id, req.identity.sub);
      return (await client.query(`update learning_checkin set learning_goal_id=$3,confidence=$4,difficulty=$5,note=$6,
        occurred_at=$7,updated_at=now() where id=$1 and owner_user_id=$2 returning *`, [checkinId, req.identity.sub, next.learning_goal_id, next.confidence, next.difficulty, next.note, next.occurred_at])).rows[0];
    });
    res.json(checkinRow(result));
  }));
  router.delete('/learning/checkins/:id', auth, route(async (req, res) => {
    const result = await pool.query(`update learning_checkin set updated_at=case when archived_at is null then now() else updated_at end,
      archived_at=coalesce(archived_at,now()) where id=$1 and owner_user_id=$2 returning id`, [id(req.params.id), req.identity.sub]);
    if (!result.rowCount) fail(404, 'checkin_not_found');
    res.status(204).end();
  }));
  return router;
}
