import test, { after, before } from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import net from 'node:net';
import pg from 'pg';
import jwt from 'jsonwebtoken';
import fs from 'node:fs/promises';
import { assertSchoolSession } from '../src/school_lifecycle.js';

assert.ok(process.env.DATABASE_URL, 'School lifecycle tests require migrated synthetic PostgreSQL');
assert.ok(process.env.JWT_SECRET?.length >= 32, 'School lifecycle tests require a synthetic JWT secret');
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
    env: { ...process.env, NODE_ENV: 'production', PORT: String(port),
      SMS_PROVIDER: 'disabled', SMS_PROVIDER_URL: '', SMS_PROVIDER_TOKEN: '', EMAIL_FROM: '', RESEND_API_KEY: '', SMTP_HOST: '',
      CORS_ORIGINS: '', TRUSTED_PROXY_CIDRS: '', ENABLE_SENSITIVE_FEATURES: 'false',
      RATE_LIMIT_AUTH_MAX: '2000', RATE_LIMIT_GENERAL_MAX: '4000', RATE_LIMIT_AI_MAX: '2000' },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  child.stdout.on('data', (chunk) => { output += chunk.toString(); startup += chunk.toString(); });
  child.stderr.on('data', (chunk) => { errors += chunk.toString(); });
  await new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('School lifecycle fixture startup timed out')), 10000);
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

async function observedBlock(blocker) {
  const pid = (await blocker.query('select pg_backend_pid() as pid')).rows[0].pid;
  const deadline = Date.now() + 3000;
  while (Date.now() < deadline) {
    const waiting = await pool.query('select 1 from pg_stat_activity where $1=any(pg_blocking_pids(pid))', [pid]);
    if (waiting.rowCount) return;
    await new Promise((resolve) => setTimeout(resolve, 15));
  }
  throw new Error('Request never reached the observed PostgreSQL row-lock wait');
}

async function expireAfterObservedWait(blocker, expiresAt) {
  await observedBlock(blocker);
  while (Date.now() <= expiresAt + 25) await new Promise((resolve) => setTimeout(resolve, Math.min(25, expiresAt + 26 - Date.now())));
  await blocker.query('commit');
}


test('owner lifecycle list starts empty and rejects anonymous access', async () => {
  const actor = await user();
  assert.equal((await request('/v1/school/lifecycle')).status, 401);
  const result = await request('/v1/school/lifecycle', { actor });
  assert.equal(result.status, 200);
  assert.deepEqual(result.body.contexts, []);
  assert.deepEqual(result.body.years, []);
  assert.deepEqual(result.body.terms, []);
  assert.ok(Date.parse(result.body.fetchedAt));
});

function intent(operation = 'create', data = {}, entityId = crypto.randomUUID(), expectedVersion = operation === 'create' ? 0 : 1) {
  return { mutationId: crypto.randomUUID(), entityId, operation, expectedVersion, data };
}
const mutate = (actor, type, body) => request(`/v1/school/lifecycle/${type}/mutations`, { method: 'POST', actor, body });
async function lifecycle(actor = undefined) {
  actor ??= await user();
  const contextIntent = intent('create', { kind: 'student', title: 'مدرسه آزمایشی' });
  const context = await mutate(actor, 'contexts', contextIntent); assert.equal(context.status, 201);
  const yearIntent = intent('create', { lifeContextId: context.body.entity.id, title: 'سال انتخابی', startsOn: '2026-08-12', endsOn: '2027-07-05' });
  const year = await mutate(actor, 'years', yearIntent); assert.equal(year.status, 201);
  const termIntent = intent('create', { academicYearId: year.body.entity.id, title: 'دوره انتخابی', startsOn: '2026-08-15', endsOn: '2027-02-10' });
  const term = await mutate(actor, 'terms', termIntent); assert.equal(term.status, 201);
  return { actor, context: context.body.entity, year: year.body.entity, term: term.body.entity, contextIntent, yearIntent, termIntent };
}

test('stable school creates survive lost ACK, process restart and old retry returns current version', async () => {
  const f = await lifecycle();
  await stop(); await start();
  const retry = await mutate(f.actor, 'years', f.yearIntent);
  assert.equal(retry.status, 200); assert.equal(retry.body.acknowledgement.status, 'already_applied');
  assert.equal(retry.body.acknowledgement.appliedVersion, 1);
  const edited = await mutate(f.actor, 'years', intent('update', { title: 'سال ویرایش‌شده' }, f.year.id, 1));
  assert.equal(edited.status, 200); assert.equal(edited.body.entity.version, 2);
  const oldRetry = await mutate(f.actor, 'years', f.yearIntent);
  assert.equal(oldRetry.body.entity.title, 'سال ویرایش‌شده'); assert.equal(oldRetry.body.entity.version, 2);
  assert.equal(oldRetry.body.acknowledgement.appliedVersion, 1);
  assert.equal((await pool.query('select count(*)::int as n from academic_year where student_user_id=$1', [f.actor.id])).rows[0].n, 1);
  assert.equal((await mutate(f.actor, 'years', { ...f.yearIntent, data: { ...f.yearIntent.data, title: 'UUID reused with changed content' } })).status, 409);
  const reopened = await request('/v1/school/lifecycle', { actor: f.actor });
  assert.equal(reopened.body.years[0].starts_on, '2026-08-12');
  assert.equal(reopened.body.terms[0].starts_on, '2026-08-15');
});

test('school version conflicts reject stale edits and archive preserves linked tasks and history', async () => {
  const f = await lifecycle();
  const subject = await request(`/v1/school/terms/${f.term.id}/subjects`, { method: 'POST', actor: f.actor, body: { name: 'فیزیک انتخابی' } });
  assert.equal(subject.status, 201);
  const homework = await request('/v1/plan-items', { method: 'POST', actor: f.actor, body: { kind: 'assignment', title: 'تکلیف تاریخی', subjectId: subject.body.id, visibility: 'private' } });
  assert.equal(homework.status, 201);
  const edit = await mutate(f.actor, 'contexts', intent('update', { title: 'نام تازه' }, f.context.id));
  assert.equal(edit.status, 200);
  assert.equal((await mutate(f.actor, 'contexts', intent('update', { title: 'stale' }, f.context.id))).status, 409);
  const archivedIntent = intent('archive', {}, f.context.id, 2);
  const archived = await mutate(f.actor, 'contexts', archivedIntent);
  assert.equal(archived.status, 200); assert.equal(archived.body.entity.active, false);
  await stop(); await start();
  assert.equal((await mutate(f.actor, 'contexts', archivedIntent)).body.acknowledgement.status, 'already_applied');
  const list = await request('/v1/school/lifecycle', { actor: f.actor });
  assert.equal(list.body.contexts[0].active, false);
  assert.equal(list.body.years[0].id, f.year.id);
  assert.equal(list.body.terms[0].id, f.term.id);
  const retained = (await pool.query('select p.subject_id,s.name from plan_item p join subject s on s.id=p.subject_id where p.id=$1', [homework.body.id])).rows[0];
  assert.equal(retained.subject_id, subject.body.id); assert.equal(retained.name, 'فیزیک انتخابی');
  const overview = await request(`/v1/school/${f.actor.id}/overview`, { actor: f.actor });
  assert.deepEqual(overview.body.years, []); assert.deepEqual(overview.body.subjects, []);
  assert.ok(overview.body.workload.some((row) => row.id === homework.body.id));
  assert.equal((await mutate(f.actor, 'terms', intent('update', { title: 'Cannot edit archived ancestor' }, f.term.id))).status, 409);
  assert.equal((await mutate(f.actor, 'contexts', intent('update', { title: 'Cannot unarchive' }, f.context.id, 3))).status, 409);
});

test('guardian and other-family actors cannot read or write another owner lifecycle', async () => {
  const f = await lifecycle(), parent = await user(), outsider = await user();
  const familyId = crypto.randomUUID(); families.push(familyId);
  await pool.query("insert into family_workspace(id,name,created_by) values($1,'Lifecycle Synthetic Family',$2)", [familyId, parent.id]);
  await pool.query("insert into family_membership(family_id,user_id,role) values($1,$2,'teen_minor'),($1,$3,'parent_guardian')", [familyId, f.actor.id, parent.id]);
  await pool.query('insert into guardian_relationship(family_id,guardian_user_id,minor_user_id) values($1,$2,$3)', [familyId, parent.id, f.actor.id]);
  for (const actor of [parent, outsider]) {
    const list = await request('/v1/school/lifecycle', { actor });
    assert.deepEqual(list.body.contexts, []); assert.deepEqual(list.body.years, []); assert.deepEqual(list.body.terms, []);
    for (const [type, entity] of [['contexts', f.context], ['years', f.year], ['terms', f.term]]) {
      assert.equal((await mutate(actor, type, intent('update', { title: 'forged' }, entity.id))).status, 404);
      assert.equal((await mutate(actor, type, intent('archive', {}, entity.id))).status, 404);
    }
    assert.equal((await mutate(actor, 'years', intent('create', { lifeContextId: f.context.id, title: 'forged', startsOn: '2026-09-01', endsOn: '2027-01-01' }))).status, 403);
    assert.equal((await mutate(actor, 'terms', intent('create', { academicYearId: f.year.id, title: 'forged', startsOn: '2026-09-01', endsOn: '2027-01-01' }))).status, 403);
  }
});

test('date nesting and historical class recurrence prevent invalid parent date edits', async () => {
  const f = await lifecycle();
  for (const date of ['2026-02-30', '0000-01-01', '2026-8-01', '۱۴۰۵-۰۶-۰۱']) {
    assert.equal((await mutate(f.actor, 'years', intent('create', { lifeContextId: f.context.id, title: 'invalid', startsOn: date, endsOn: '2027-01-01' }))).status, 400);
  }
  assert.equal((await mutate(f.actor, 'terms', intent('create', { academicYearId: f.year.id, title: 'outside', startsOn: '2026-08-11', endsOn: '2027-01-01' }))).status, 400);
  assert.equal((await mutate(f.actor, 'years', intent('update', { startsOn: '2026-09-01' }, f.year.id))).status, 409);
  const subject = await request(`/v1/school/terms/${f.term.id}/subjects`, { method: 'POST', actor: f.actor, body: { name: 'درس' } });
  const lesson = await request(`/v1/school/subjects/${subject.body.id}/classes`, { method: 'POST', actor: f.actor, body: { weekday: 1, startsAt: '09:00', endsAt: '10:00', recurrenceUntil: '2027-02-10' } });
  assert.equal(lesson.status, 201);
  assert.equal((await mutate(f.actor, 'terms', intent('update', { endsOn: '2027-02-09' }, f.term.id))).status, 409);
  await request(`/v1/school/classes/${lesson.body.id}`, { method: 'DELETE', actor: f.actor });
  assert.equal((await mutate(f.actor, 'terms', intent('update', { endsOn: '2027-02-09' }, f.term.id))).status, 409);
  assert.equal((await mutate(f.actor, 'contexts', intent('update', { kind: 'work' }, f.context.id))).status, 409);
});

test('term archive blocks both new and legacy child writes and hides active timetable', async () => {
  const f = await lifecycle();
  const subject = await request(`/v1/school/terms/${f.term.id}/subjects`, { method: 'POST', actor: f.actor, body: { name: 'درس تاریخی' } });
  const lesson = await request(`/v1/school/subjects/${subject.body.id}/classes`, { method: 'POST', actor: f.actor, body: { weekday: 2, startsAt: '12:00', endsAt: '13:00' } });
  assert.equal(lesson.status, 201);
  assert.equal((await mutate(f.actor, 'terms', intent('archive', {}, f.term.id))).status, 200);
  assert.equal((await request(`/v1/school/terms/${f.term.id}/subjects`, { method: 'POST', actor: f.actor, body: { name: 'Must not create' } })).status, 404);
  assert.equal((await request(`/v1/school/subjects/${subject.body.id}`, { method: 'PATCH', actor: f.actor, body: { name: 'Must not edit' } })).status, 409);
  assert.equal((await request(`/v1/school/subjects/${subject.body.id}/classes`, { method: 'POST', actor: f.actor, body: { weekday: 2, startsAt: '14:00', endsAt: '15:00' } })).status, 409);
  assert.equal((await request(`/v1/school/classes/${lesson.body.id}`, { method: 'PATCH', actor: f.actor, body: { location: 'Must not edit' } })).status, 409);
  assert.deepEqual((await request(`/v1/school/${f.actor.id}/timetable`, { actor: f.actor })).body.classes, []);
  assert.equal((await request(`/v1/school/subjects/${subject.body.id}`, { method: 'DELETE', actor: f.actor })).status, 204);
  assert.equal((await request(`/v1/school/classes/${lesson.body.id}`, { method: 'DELETE', actor: f.actor })).status, 204);
});

test('legacy inserts waiting behind ancestor archival recheck current state without a 500 or duplicate', async () => {
  const f = await lifecycle();
  const locking = await pool.connect();
  try {
    await locking.query('begin');
    await locking.query('select 1 from app_user where id=$1 for update', [f.actor.id]);
    await locking.query('update life_context set active=false where id=$1', [f.context.id]);
    const pending = request('/v1/school/years', { method: 'POST', actor: f.actor, body: { lifeContextId: f.context.id, title: 'Racing legacy insert', startsOn: '2028-01-01', endsOn: '2028-12-31' } });
    await new Promise((resolve) => setTimeout(resolve, 100));
    await locking.query('commit');
    const result = await pending;
    assert.equal(result.status, 400);
    assert.equal(result.body.error, 'invalid_academic_year');
    assert.equal((await pool.query('select count(*)::int as n from academic_year where student_user_id=$1', [f.actor.id])).rows[0].n, 1);
  } finally { await locking.query('rollback').catch(() => {}); locking.release(); }
});

test('lifecycle input rejects excess fields, invalid versions and malformed IDs', async () => {
  const actor = await user();
  const good = intent('create', { kind: 'student', title: 'school' });
  for (const raw of [{ ...good, extra: 'ignored' }, { ...good, expectedVersion: 1 }, { ...good, entityId: 'not-uuid' }, { ...good, data: { ...good.data, active: false } }, { ...good, data: { ...good.data, title: 'x'.repeat(121) } }]) {
    assert.equal((await mutate(actor, 'contexts', raw)).status, 400);
  }
  assert.equal((await mutate(actor, 'unknown', good)).status, 404);
});


test('revoked session after an owner lock wait cannot commit a lifecycle or legacy write', async () => {
  for (const legacy of [false, true]) {
    const actor = await user(), locking = await pool.connect();
    const claims = jwt.decode(actor.token);
    try {
      await locking.query('begin');
      await locking.query('select 1 from app_user where id=$1 for update', [actor.id]);
      const body = legacy ? { kind: 'student', title: 'Revoked legacy create' } : intent('create', { kind: 'student', title: 'Revoked lifecycle create' });
      const pending = legacy ? request('/v1/life-contexts', { method: 'POST', actor, body }) : mutate(actor, 'contexts', body);
      await new Promise((resolve) => setTimeout(resolve, 100));
      await locking.query('update auth_session set revoked_at=clock_timestamp() where id=$1', [claims.sid]);
      await locking.query('commit');
      assert.equal((await pending).status, 401);
      assert.equal((await pool.query('select count(*)::int as n from life_context where user_id=$1', [actor.id])).rows[0].n, 0);
    } finally { await locking.query('rollback').catch(() => {}); locking.release(); }
  }
});

test('session expiry after a read lock wait returns 401 rather than private lifecycle data', async () => {
  const f = await lifecycle(), locking = await pool.connect(), claims = jwt.decode(f.actor.token);
  try {
    await locking.query('begin');
    await locking.query('select 1 from app_user where id=$1 for update', [f.actor.id]);
    const pending = request('/v1/school/lifecycle', { actor: f.actor });
    await new Promise((resolve) => setTimeout(resolve, 100));
    await locking.query("update auth_session set expires_at=clock_timestamp()-interval '1 second' where id=$1", [claims.sid]);
    await locking.query('commit');
    const result = await pending;
    assert.equal(result.status, 401); assert.equal(result.body.contexts, undefined);
  } finally { await locking.query('rollback').catch(() => {}); locking.release(); }
});

test('private check-in create, edit and archive roll back JWT expiry after observed record waits', async () => {
  const actor = await user();
  const goal = await request('/v1/learning/goals', { method: 'POST', actor, body: { title: 'SYNTHETIC wait goal' } });
  assert.equal(goal.status, 201);
  const checkin = await request('/v1/learning/checkins', { method: 'POST', actor, body: { learningGoalId: goal.body.id, confidence: 2, difficulty: 3, note: 'SYNTHETIC private original' } });
  assert.equal(checkin.status, 201);
  const claims = jwt.decode(actor.token);
  for (const method of ['POST', 'PATCH', 'DELETE']) {
    const token = jwt.sign({ sub: actor.id, sid: claims.sid, aud: 'lifemate-api' }, process.env.JWT_SECRET, { issuer: 'lifemate', expiresIn: 2 });
    const exp = jwt.decode(token).exp * 1000;
    const locking = await pool.connect();
    try {
      await locking.query('begin');
      await locking.query(method === 'POST' ? 'select 1 from learning_goal where id=$1 for update' : 'select 1 from learning_checkin where id=$1 for update', [method === 'POST' ? goal.body.id : checkin.body.id]);
      const pending = request(method === 'POST' ? '/v1/learning/checkins' : `/v1/learning/checkins/${checkin.body.id}`, {
        method, actor: { ...actor, token }, body: method === 'POST' ? { learningGoalId: goal.body.id, confidence: 1, difficulty: 1 } : method === 'PATCH' ? { note: 'SYNTHETIC must roll back' } : undefined,
      });
      await expireAfterObservedWait(locking, exp);
      const result = await pending;
      assert.equal(result.status, 401, method + ' cannot commit an expired bearer');
      const stored = (await pool.query('select note,archived_at from learning_checkin where id=$1', [checkin.body.id])).rows[0];
      assert.equal(stored.note, 'SYNTHETIC private original'); assert.equal(stored.archived_at, null);
      assert.equal((await pool.query('select count(*)::int n from learning_checkin where owner_user_id=$1', [actor.id])).rows[0].n, 1);
    } finally { await locking.query('rollback').catch(() => {}); locking.release(); }
  }
});

test('private check-in edit and read reject database session expiry after an observed row wait', async () => {
  const actor = await user(), claims = jwt.decode(actor.token);
  const created = await request('/v1/learning/checkins', { method: 'POST', actor, body: { confidence: 2, difficulty: 3, note: 'SYNTHETIC private original' } });
  assert.equal(created.status, 201);
  for (const method of ['PATCH', 'GET']) {
    const expiresAt = Date.now() + 1700;
    await pool.query('update auth_session set expires_at=$2 where id=$1', [claims.sid, new Date(expiresAt)]);
    const locking = await pool.connect();
    try {
      await locking.query('begin');
      // UPDATE waits on the private row; GET must serialize with account state.
      await locking.query(method === 'PATCH' ? 'select 1 from learning_checkin where id=$1 for update' : 'select 1 from app_user where id=$1 for update', [method === 'PATCH' ? created.body.id : actor.id]);
      const pending = request(`/v1/learning/checkins/${created.body.id}`, { method, actor, body: method === 'PATCH' ? { note: 'SYNTHETIC must roll back' } : undefined });
      await expireAfterObservedWait(locking, expiresAt);
      const result = await pending;
      assert.equal(result.status, 401); assert.equal(result.body.note, undefined);
      assert.equal((await pool.query('select note from learning_checkin where id=$1', [created.body.id])).rows[0].note, 'SYNTHETIC private original');
    } finally { await locking.query('rollback').catch(() => {}); locking.release(); }
  }
});

test('school session validation samples fresh database time after the observed session-row lock wait', async () => {
  const actor = await user(), claims = jwt.decode(actor.token), locking = await pool.connect();
  const expiresAt = Date.now() + 1700;
  await pool.query('update auth_session set expires_at=$2 where id=$1', [claims.sid, new Date(expiresAt)]);
  try {
    await locking.query('begin');
    await locking.query('select 1 from auth_session where id=$1 for update', [claims.sid]);
    const pending = request('/v1/school/lifecycle', { actor });
    await expireAfterObservedWait(locking, expiresAt);
    const result = await pending;
    assert.equal(result.status, 401); assert.equal(result.body.contexts, undefined);
  } finally { await locking.query('rollback').catch(() => {}); locking.release(); }
});

test('school session guard itself rejects elapsed expiry after its locking statement began', async () => {
  const actor = await user(), claims = jwt.decode(actor.token), locking = await pool.connect(), validating = await pool.connect();
  const expiresAt = Date.now() + 1700;
  await pool.query('update auth_session set expires_at=$2 where id=$1', [claims.sid, new Date(expiresAt)]);
  try {
    await locking.query('begin'); await validating.query('begin');
    await locking.query('select 1 from auth_session where id=$1 for update', [claims.sid]);
    const pending = assertSchoolSession(validating, claims).then(() => ({ accepted: true }), (error) => ({ error }));
    await expireAfterObservedWait(locking, expiresAt);
    const result = await pending;
    assert.equal(result.error?.code, 'session_invalid');
  } finally {
    await locking.query('rollback').catch(() => {}); locking.release();
    await validating.query('rollback').catch(() => {}); validating.release();
  }
});

test('legacy academic reads reject session expiry at observed account waits', async () => {
  const f = await lifecycle(), claims = jwt.decode(f.actor.token), locking = await pool.connect();
  const expiresAt = Date.now() + 1700;
  await pool.query('update auth_session set expires_at=$2 where id=$1', [claims.sid, new Date(expiresAt)]);
  try {
    await locking.query('begin');
    await locking.query('select 1 from app_user where id=$1 for update', [f.actor.id]);
    const pending = Promise.all(['/v1/life-contexts', `/v1/school/${f.actor.id}/overview`, `/v1/school/${f.actor.id}/timetable`]
      .map((path) => request(path, { actor: f.actor })));
    await expireAfterObservedWait(locking, expiresAt);
    for (const result of await pending) {
      assert.equal(result.status, 401); assert.equal(result.body.contexts, undefined);
      assert.equal(result.body.subjects, undefined); assert.equal(result.body.classes, undefined);
    }
  } finally { await locking.query('rollback').catch(() => {}); locking.release(); }
});
