import test, { after, before } from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import net from 'node:net';
import pg from 'pg';
import jwt from 'jsonwebtoken';
import fs from 'node:fs/promises';

assert.ok(process.env.DATABASE_URL, 'School tests require migrated synthetic PostgreSQL');
assert.ok(process.env.JWT_SECRET?.length >= 32, 'School tests require a synthetic JWT secret');
const pool = new pg.Pool({ connectionString: process.env.DATABASE_URL });
const users = [], families = [];
let child, base, output = '', errors = '';

async function start() {
  const reservation = net.createServer().listen(0, '127.0.0.1');
  await once(reservation, 'listening');
  const port = reservation.address().port;
  await new Promise((resolve) => reservation.close(resolve));
  base = `http://127.0.0.1:${port}`;
  let startup = '';
  child = spawn(process.execPath, ['src/entrypoint.js'], {
    env: { ...process.env, NODE_ENV: 'production', PORT: String(port), EMAIL_FROM: '', RESEND_API_KEY: '', SMTP_HOST: '',
      CORS_ORIGINS: '', TRUSTED_PROXY_CIDRS: '', ENABLE_SENSITIVE_FEATURES: 'false',
      RATE_LIMIT_AUTH_MAX: '2000', RATE_LIMIT_GENERAL_MAX: '4000', RATE_LIMIT_AI_MAX: '2000' },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  child.stdout.on('data', (chunk) => { output += chunk.toString(); startup += chunk.toString(); });
  child.stderr.on('data', (chunk) => { errors += chunk.toString(); });
  await new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('School fixture startup timed out')), 10000);
    const onData = () => {
      if (!startup.includes('"type":"startup"')) return;
      clearTimeout(timer); child.stdout.off('data', onData); resolve();
    };
    child.stdout.on('data', onData);
    child.once('error', (error) => { clearTimeout(timer); reject(error); });
  });
}
async function stop() {
  if (child && child.exitCode === null && child.signalCode === null) {
    const closed = once(child, 'close'); child.kill('SIGTERM'); await closed;
  }
}
before(start);
after(async () => {
  await stop();
  try {
    await pool.query('delete from access_audit where family_id=any($1::uuid[]) or actor_user_id=any($2::uuid[])', [families, users]);
    await pool.query('delete from family_workspace where id=any($1::uuid[])', [families]);
    await pool.query('delete from app_user where id=any($1::uuid[])', [users]);
  } finally { await pool.end(); }
});
async function user() {
  const id = crypto.randomUUID(), sid = crypto.randomUUID();
  users.push(id);
  await pool.query('insert into app_user(id,identity_subject,email_normalized,email_verified_at) values($1,$2,$3,now())', [id, `school-fixture:${id}`, `school-${id}@example.test`]);
  await pool.query("insert into profile(user_id,display_name,theme_preference) values($1,'Synthetic School User','adult_blue')", [id]);
  await pool.query("insert into auth_session(id,user_id,refresh_digest,expires_at) values($1,$2,$3,now()+interval '1 day')", [sid, id, crypto.randomBytes(32).toString('hex')]);
  return { id, token: jwt.sign({ sub: id, sid, aud: 'lifemate-api' }, process.env.JWT_SECRET, { issuer: 'lifemate', expiresIn: '15m' }) };
}
async function request(path, { method = 'GET', actor, body } = {}) {
  const response = await fetch(base + path, { method, headers: { 'content-type': 'application/json', ...(actor ? { authorization: `Bearer ${actor.token}` } : {}) }, body: body === undefined ? undefined : JSON.stringify(body) });
  const text = await response.text();
  return { status: response.status, body: text && response.headers.get('content-type')?.includes('application/json') ? JSON.parse(text) : text || null };
}
async function school(actor = undefined) {
  actor ??= await user();
  const context = await request('/v1/life-contexts', { method: 'POST', actor, body: { kind: 'student', title: 'Synthetic School' } });
  assert.equal(context.status, 201);
  const year = await request('/v1/school/years', { method: 'POST', actor, body: { lifeContextId: context.body.id, title: 'Synthetic Year', startsOn: '2026-09-01', endsOn: '2027-06-30' } });
  assert.equal(year.status, 201);
  const term = await request(`/v1/school/years/${year.body.id}/terms`, { method: 'POST', actor, body: { title: 'Synthetic Term', startsOn: '2026-09-01', endsOn: '2027-01-31' } });
  assert.equal(term.status, 201);
  const subject = await request(`/v1/school/terms/${term.body.id}/subjects`, { method: 'POST', actor, body: { name: 'Synthetic Math', teacherName: 'Synthetic Teacher', colorKey: 'blue' } });
  assert.equal(subject.status, 201);
  const lesson = await request(`/v1/school/subjects/${subject.body.id}/classes`, { method: 'POST', actor, body: { weekday: 1, startsAt: '09:00', endsAt: '10:00', location: 'Synthetic Room', recurrenceUntil: '2027-01-31' } });
  assert.equal(lesson.status, 201);
  return { actor, context: context.body, year: year.body, term: term.body, subject: subject.body, lesson: lesson.body };
}
async function familyFixture() {
  const f = await school();
  const parent = await user(), outsider = await user();
  const familyId = crypto.randomUUID(); families.push(familyId);
  await pool.query("insert into family_workspace(id,name,created_by) values($1,'Synthetic School Family',$2)", [familyId, parent.id]);
  await pool.query("insert into family_membership(family_id,user_id,role) values($1,$2,'teen_minor'),($1,$3,'parent_guardian')", [familyId, f.actor.id, parent.id]);
  await pool.query('insert into guardian_relationship(family_id,guardian_user_id,minor_user_id) values($1,$2,$3)', [familyId, parent.id, f.actor.id]);
  return { ...f, parent, outsider, familyId };
}

test('subject create/read/edit survives a real API process restart and archive preserves homework and report names', async () => {
  const f = await familyFixture();
  const path = `/v1/school/subjects/${f.subject.id}`;
  assert.equal((await request(path, { actor: f.actor })).status, 200);
  const updated = await request(path, { method: 'PATCH', actor: f.actor, body: { name: 'Renamed Math', teacherName: null, colorKey: 'green' } });
  assert.equal(updated.status, 200);
  const homework = await request('/v1/plan-items', { method: 'POST', actor: f.actor, body: { kind: 'assignment', title: 'Historical Math Homework', subjectId: f.subject.id, familyId: f.familyId, visibility: 'parent_guardian', notes: 'PRIVATE-SCHOOL-NOTE-MARKER' } });
  assert.equal(homework.status, 201);
  await stop(); await start();
  const reopened = await request(path, { actor: f.actor });
  assert.equal(reopened.status, 200);
  assert.equal(reopened.body.name, 'Renamed Math');
  assert.equal(reopened.body.teacher_name, null);
  assert.equal((await request(path, { method: 'DELETE', actor: f.actor })).status, 204);
  assert.equal((await request(path, { method: 'DELETE', actor: f.actor })).status, 204);
  assert.equal((await request(path, { method: 'PATCH', actor: f.actor, body: { name: 'Must Not Restore' } })).status, 409);
  assert.ok((await request(path, { actor: f.actor })).body.archived_at);
  const current = await request(`/v1/school/${f.actor.id}/overview`, { actor: f.actor });
  assert.equal(current.status, 200);
  assert.equal(current.body.subjects.some((item) => item.id === f.subject.id), false);
  assert.equal((await request(`/v1/school/${f.actor.id}/timetable`, { actor: f.actor })).body.classes.length, 0);
  const stored = (await pool.query('select p.subject_id,s.name,s.archived_at from plan_item p join subject s on s.id=p.subject_id where p.id=$1', [homework.body.id])).rows[0];
  assert.equal(stored.subject_id, f.subject.id);
  assert.equal(stored.name, 'Renamed Math');
  assert.ok(stored.archived_at);
  const report = await request(`/v1/families/${f.familyId}/children/${f.actor.id}/learning-report`, { actor: f.parent });
  assert.equal(report.status, 200);
  assert.equal(report.body.items.find((item) => item.id === homework.body.id).subjectName, 'Renamed Math');
  assert.equal(JSON.stringify(report.body).includes('PRIVATE-SCHOOL-NOTE-MARKER'), false);
});

test('class edits validate real times/dates and ownership, and archive remains persistent and owner-only', async () => {
  const f = await school();
  const other = await school();
  const path = `/v1/school/classes/${f.lesson.id}`;
  assert.equal((await request(path, { actor: f.actor })).status, 200);
  for (const bad of [{ weekday: 8 }, { weekday: '2' }, { startsAt: '10:00', endsAt: '09:00' }, { startsAt: '25:00' }, { endsAt: '10:00Z' }, { recurrenceUntil: '2026-02-30' }, { recurrenceUntil: '2027-02-01' }, { location: 'x'.repeat(241) }]) {
    assert.equal((await request(path, { method: 'PATCH', actor: f.actor, body: bad })).status, 400);
  }
  assert.equal((await request(path, { method: 'PATCH', actor: f.actor, body: { subjectId: other.subject.id } })).status, 403);
  assert.equal((await request(path, { method: 'PATCH', actor: f.actor, body: { weekday: 3, startsAt: '11:15', endsAt: '12:00', location: null, recurrenceUntil: null } })).status, 200);
  await stop(); await start();
  const reopened = await request(path, { actor: f.actor });
  assert.equal(reopened.body.weekday, 3);
  assert.equal(reopened.body.starts_at, '11:15:00');
  assert.equal(reopened.body.location, null);
  assert.equal((await request(path, { method: 'DELETE', actor: other.actor })).status, 404);
  assert.equal((await request(path, { method: 'DELETE', actor: f.actor })).status, 204);
  assert.equal((await request(path, { method: 'DELETE', actor: f.actor })).status, 204);
  assert.equal((await request(`/v1/school/${f.actor.id}/timetable`, { actor: f.actor })).body.classes.length, 0);
  assert.ok((await pool.query('select archived_at from class_session where id=$1', [f.lesson.id])).rows[0].archived_at);
  assert.equal((await request(path, { method: 'PATCH', actor: f.actor, body: { weekday: 2 } })).status, 409);
});

test('guardians can read only currently authorized school projections and cannot mutate owner courses/classes', async () => {
  const f = await familyFixture();
  await request('/v1/plan-items', { method: 'POST', actor: f.actor, body: { title: 'Shared Class Homework', kind: 'assignment', familyId: f.familyId, subjectId: f.subject.id, visibility: 'parent_guardian' } });
  for (const actor of [f.parent, f.outsider]) {
    for (const path of [`/v1/school/subjects/${f.subject.id}`, `/v1/school/classes/${f.lesson.id}`]) {
      for (const method of ['GET', 'PATCH', 'DELETE']) assert.equal((await request(path, { method, actor, body: method === 'PATCH' ? { name: 'Forbidden', weekday: 2 } : undefined })).status, 404);
    }
  }
  assert.equal((await request(`/v1/school/${f.actor.id}/timetable`, { actor: f.parent })).body.classes.length, 1);
  assert.equal((await request(`/v1/school/${f.actor.id}/timetable`, { actor: f.outsider })).status, 403);
  await pool.query('update guardian_relationship set active=false where family_id=$1', [f.familyId]);
  assert.equal((await request(`/v1/school/${f.actor.id}/overview`, { actor: f.parent })).status, 403);
  await pool.query('update guardian_relationship set active=true where family_id=$1', [f.familyId]);
  await pool.query('update family_workspace set archived_at=now() where id=$1', [f.familyId]);
  assert.equal((await request(`/v1/school/${f.actor.id}/timetable`, { actor: f.parent })).status, 403);
  assert.equal((await request(`/v1/school/subjects/${f.subject.id}`, { actor: f.actor })).status, 200);
});

test('subject edits require an active owned term and reject invalid fields without partial changes', async () => {
  const f = await school(), other = await school();
  const path = `/v1/school/subjects/${f.subject.id}`;
  for (const body of [{ name: '' }, { name: 'x'.repeat(121) }, { teacherName: 'x'.repeat(121) }, { colorKey: 'x'.repeat(41) }, { academicTermId: 'invalid' }]) {
    assert.equal((await request(path, { method: 'PATCH', actor: f.actor, body })).status, 400);
  }
  assert.equal((await request(path, { method: 'PATCH', actor: f.actor, body: { name: 'Must Not Change', academicTermId: other.term.id } })).status, 403);
  assert.equal((await request(path, { actor: f.actor })).body.name, 'Synthetic Math');
  const nextTerm = await request(`/v1/school/years/${f.year.id}/terms`, { method: 'POST', actor: f.actor, body: { title: 'Next Term', startsOn: '2027-02-01', endsOn: '2027-06-30' } });
  assert.equal(nextTerm.status, 201);
  assert.equal((await request(path, { method: 'PATCH', actor: f.actor, body: { academicTermId: nextTerm.body.id } })).status, 400);
  assert.equal((await request(`/v1/school/classes/${f.lesson.id}`, { method: 'PATCH', actor: f.actor, body: { recurrenceUntil: null } })).status, 200);
  assert.equal((await request(path, { method: 'PATCH', actor: f.actor, body: { academicTermId: nextTerm.body.id } })).status, 200);
  await pool.query('update academic_year set active=false where id=$1', [f.year.id]);
  assert.equal((await request(path, { method: 'PATCH', actor: f.actor, body: { name: 'Inactive Term' } })).status, 409);
});

test('school create rejects malformed dates/times and archived subject links without inserting records', async () => {
  const f = await school();
  for (const body of [
    { title: 'Invalid Year', startsOn: '2026-02-30', endsOn: '2026-06-30' },
    { title: 'Reversed Year', startsOn: '2027-06-30', endsOn: '2026-09-01' },
    { title: 'x'.repeat(121), startsOn: '2026-09-01', endsOn: '2027-06-30' },
  ]) assert.equal((await request('/v1/school/years', { method: 'POST', actor: f.actor, body: { ...body, lifeContextId: f.context.id } })).status, 400);
  assert.equal((await request(`/v1/school/years/${f.year.id}/terms`, { method: 'POST', actor: f.actor, body: { title: 'Outside Year', startsOn: '2026-08-01', endsOn: '2027-01-31' } })).status, 400);
  assert.equal((await request(`/v1/school/terms/${f.term.id}/subjects`, { method: 'POST', actor: f.actor, body: { name: 'x'.repeat(121) } })).status, 400);
  const classPath = `/v1/school/subjects/${f.subject.id}/classes`;
  for (const body of [{ weekday: 0, startsAt: '09:00', endsAt: '10:00' }, { weekday: 1, startsAt: '25:00', endsAt: '26:00' }, { weekday: 1, startsAt: '10:00', endsAt: '09:00' }, { weekday: 1, startsAt: '09:00', endsAt: '10:00', recurrenceUntil: '2026-02-30' }]) {
    assert.equal((await request(classPath, { method: 'POST', actor: f.actor, body })).status, 400);
  }
  assert.equal((await request(`/v1/school/subjects/${f.subject.id}`, { method: 'DELETE', actor: f.actor })).status, 204);
  assert.equal((await request(classPath, { method: 'POST', actor: f.actor, body: { weekday: 1, startsAt: '09:00', endsAt: '10:00' } })).status, 409);
  assert.equal((await pool.query('select count(*)::int as n from class_session where subject_id=$1', [f.subject.id])).rows[0].n, 1);
});

test('learning check-ins have persistent owner CRUD, explicit self-report timestamps and private notes', async () => {
  const f = await familyFixture();
  const goal = await request('/v1/learning/goals', { method: 'POST', actor: f.actor, body: { title: 'Synthetic Goal', subjectId: f.subject.id } });
  assert.equal(goal.status, 201);
  const created = await request('/v1/learning/checkins', { method: 'POST', actor: f.actor, body: { learningGoalId: goal.body.id, confidence: 2, difficulty: 4, note: 'PRIVATE-CHECKIN-SYNTHETIC-MARKER' } });
  assert.equal(created.status, 201);
  assert.equal(created.body.source, 'self_reported');
  assert.equal(created.body.isEvidenceOfStudy, false);
  assert.ok(created.body.occurred_at);
  const path = `/v1/learning/checkins/${created.body.id}`;
  assert.equal((await request(path, { actor: f.actor })).body.note, 'PRIVATE-CHECKIN-SYNTHETIC-MARKER');
  for (const actor of [f.parent, f.outsider]) {
    assert.equal((await request(path, { actor })).status, 404);
    assert.equal((await request(path, { method: 'PATCH', actor, body: { note: 'Forbidden' } })).status, 404);
    assert.equal((await request(path, { method: 'DELETE', actor })).status, 404);
    assert.equal(JSON.stringify((await request('/v1/learning/checkins', { actor })).body).includes('PRIVATE-CHECKIN-SYNTHETIC-MARKER'), false);
  }
  const occurredAt = new Date(Date.now() - 86400000).toISOString();
  const updated = await request(path, { method: 'PATCH', actor: f.actor, body: { confidence: 5, difficulty: 1, note: null, occurredAt } });
  assert.equal(updated.status, 200);
  await stop(); await start();
  const reopened = await request(path, { actor: f.actor });
  assert.equal(reopened.status, 200);
  assert.equal(reopened.body.confidence, 5);
  assert.equal(reopened.body.note, null);
  assert.equal(reopened.body.occurred_at, occurredAt);
  assert.equal((await request(path, { method: 'DELETE', actor: f.actor })).status, 204);
  assert.equal((await request(path, { method: 'DELETE', actor: f.actor })).status, 204);
  assert.equal((await request('/v1/learning/checkins', { actor: f.actor })).body.items.some((item) => item.id === created.body.id), false);
  assert.equal((await request(path, { method: 'PATCH', actor: f.actor, body: { confidence: 3 } })).status, 409);
  const stored = (await pool.query('select archived_at,note,learning_goal_id from learning_checkin where id=$1', [created.body.id])).rows[0];
  assert.ok(stored.archived_at);
  assert.equal(stored.learning_goal_id, goal.body.id);
  assert.equal(stored.note, null);
  assert.equal(errors.includes('PRIVATE-CHECKIN-SYNTHETIC-MARKER'), false);
  assert.equal(output.includes('PRIVATE-CHECKIN-SYNTHETIC-MARKER'), false);
});

test('check-in validation rejects forged/archived goals, invalid timestamps and claimed evidence without data loss', async () => {
  const actor = await user(), other = await user();
  const own = await request('/v1/learning/goals', { method: 'POST', actor, body: { title: 'Own Goal' } });
  const foreign = await request('/v1/learning/goals', { method: 'POST', actor: other, body: { title: 'Foreign Goal' } });
  const body = { confidence: 3, difficulty: 3, note: 'Unchanged Note', learningGoalId: own.body.id };
  assert.equal((await request('/v1/learning/checkins', { method: 'POST', actor, body: { ...body, learningGoalId: foreign.body.id } })).status, 403);
  const created = await request('/v1/learning/checkins', { method: 'POST', actor, body });
  assert.equal(created.status, 201);
  const path = `/v1/learning/checkins/${created.body.id}`;
  for (const bad of [{ confidence: 0 }, { difficulty: 6 }, { difficulty: '3' }, { note: 'x'.repeat(2001) }, { occurredAt: '2026-02-30T12:00:00Z' }, { occurredAt: new Date(Date.now() + 300000).toISOString() }, { source: 'verified' }, { isEvidenceOfStudy: true }]) {
    assert.equal((await request(path, { method: 'PATCH', actor, body: { ...bad, note: bad.note ?? 'Must Not Save' } })).status, 400);
  }
  assert.equal((await request(path, { method: 'PATCH', actor, body: { learningGoalId: foreign.body.id } })).status, 403);
  assert.equal((await request(path, { actor })).body.note, 'Unchanged Note');
  assert.equal((await request(`/v1/learning/goals/${own.body.id}`, { method: 'DELETE', actor })).status, 204);
  assert.equal((await request('/v1/learning/checkins', { method: 'POST', actor, body })).status, 403);
  assert.equal((await request(path, { method: 'PATCH', actor, body: { learningGoalId: own.body.id } })).status, 403);
  assert.equal((await request(path, { method: 'PATCH', actor, body: { learningGoalId: null, note: 'Detached Private Note' } })).status, 200);
});

test('every new school/check-in operation requires current verified sessions and validates IDs', async () => {
  const id = crypto.randomUUID();
  const actor = await user();
  for (const path of [`/v1/school/subjects/${id}`, `/v1/school/classes/${id}`, `/v1/learning/checkins/${id}`]) {
    for (const method of ['GET', 'PATCH', 'DELETE']) assert.equal((await request(path, { method, body: method === 'PATCH' ? {} : undefined })).status, 401);
  }
  for (const path of ['/v1/school/subjects/bad', '/v1/school/classes/bad', '/v1/learning/checkins/bad']) {
    assert.equal((await request(path, { actor })).status, 400);
  }
  await pool.query('update app_user set disabled_at=now() where id=$1', [actor.id]);
  assert.equal((await request('/v1/learning/checkins', { actor })).status, 401);
});

test('school and check-in migration preserves legacy IDs, linked homework, notes and original timestamps', async () => {
  const client = new pg.Client({ connectionString: process.env.DATABASE_URL });
  await client.connect();
  try {
    await client.query(`create temporary table subject(id uuid primary key,student_user_id uuid,name text,created_at timestamptz);
      create temporary table class_session(id uuid primary key,subject_id uuid,weekday smallint,starts_at time,created_at timestamptz);
      create temporary table learning_checkin(id uuid primary key,owner_user_id uuid,learning_goal_id uuid,note text,confidence smallint,created_at timestamptz);
      create temporary table plan_item(id uuid primary key,subject_id uuid)`);
    const subjectId = crypto.randomUUID(), classId = crypto.randomUUID(), checkinId = crypto.randomUUID(), owner = crypto.randomUUID(), goalId = crypto.randomUUID();
    await client.query("insert into subject values($1,$2,'Legacy Course','2025-01-01T09:00:00Z')", [subjectId, owner]);
    await client.query("insert into class_session values($1,$2,2,'09:00','2025-01-02T09:00:00Z')", [classId, subjectId]);
    await client.query("insert into learning_checkin values($1,$2,$3,'Legacy Private Note',4,'2025-01-03T09:00:00Z')", [checkinId, owner, goalId]);
    await client.query('insert into plan_item values($1,$2)', [crypto.randomUUID(), subjectId]);
    await client.query(await fs.readFile(new URL('../migrations/0012_school_archive.sql', import.meta.url), 'utf8'));
    const course = (await client.query('select s.id,s.name,s.created_at=s.updated_at as timestamp_preserved,s.archived_at,p.subject_id from subject s join plan_item p on p.subject_id=s.id')).rows[0];
    assert.equal(course.id, subjectId); assert.equal(course.subject_id, subjectId); assert.equal(course.name, 'Legacy Course'); assert.equal(course.timestamp_preserved, true); assert.equal(course.archived_at, null);
    const lesson = (await client.query('select id,subject_id,weekday,starts_at,created_at=updated_at as timestamp_preserved,archived_at from class_session')).rows[0];
    assert.equal(lesson.id, classId); assert.equal(lesson.subject_id, subjectId); assert.equal(lesson.weekday, 2); assert.equal(lesson.timestamp_preserved, true); assert.equal(lesson.archived_at, null);
    const checkin = (await client.query('select id,learning_goal_id,note,confidence,source,created_at=occurred_at and created_at=updated_at as timestamp_preserved,archived_at from learning_checkin')).rows[0];
    assert.equal(checkin.id, checkinId); assert.equal(checkin.learning_goal_id, goalId); assert.equal(checkin.note, 'Legacy Private Note'); assert.equal(checkin.confidence, 4); assert.equal(checkin.source, 'self_reported'); assert.equal(checkin.timestamp_preserved, true); assert.equal(checkin.archived_at, null);
  } finally { await client.end(); }
});
