import test, { after } from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import express from 'express';
import jwt from 'jsonwebtoken';
import pg from 'pg';
import { createSessionAuth } from '../src/session_auth.js';
import { createPhase3Router } from '../src/phase3.js';

// A missing router must fail the HTTP acceptance assertion, never skip a gate.
const studyModule = await import('../src/study_sessions.js').catch((error) => {
  if (error.code === 'ERR_MODULE_NOT_FOUND') return null;
  throw error;
});
if (!process.env.DATABASE_URL) throw new Error('study tests require a synthetic PostgreSQL DATABASE_URL');
const pool = new pg.Pool({ connectionString: process.env.DATABASE_URL });
const jwtSecret = 'synthetic-study-test-secret-32-characters';
const auth = createSessionAuth({ pool, jwtSecret });
const app = express();
app.use(express.json({ limit: '64kb' }));
app.use('/v1', createPhase3Router({ pool, auth }));
if (studyModule) app.use('/v1', studyModule.createStudySessionsRouter({ pool, auth }));
app.use((error, _req, res, _next) => {
  console.error(error);
  res.status(500).json({ error: 'internal_error' });
});
let server = app.listen(0);
let base = `http://127.0.0.1:${server.address().port}`;
after(async () => {
  await new Promise((resolve) => server.close(resolve));
  await pool.end();
});

async function request(path, { method = 'GET', body, user } = {}) {
  const response = await fetch(base + path, {
    method,
    headers: { 'content-type': 'application/json', ...(user ? { authorization: `Bearer ${user.token}` } : {}) },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const raw = await response.text();
  return { status: response.status, body: raw && response.headers.get('content-type')?.includes('application/json') ? JSON.parse(raw) : raw || null };
}
async function user() {
  const id = crypto.randomUUID();
  const sid = crypto.randomUUID();
  await pool.query('insert into app_user(id,identity_subject,email_normalized,email_verified_at) values($1,$2,$3,now())',
    [id, `study-test:${id}`, `${id}@example.test`]);
  await pool.query("insert into profile(user_id,display_name,theme_preference) values($1,'Synthetic study tester','adult_blue')", [id]);
  await pool.query("insert into auth_session(id,user_id,refresh_digest,expires_at) values($1,$2,$3,now()+interval '1 day')", [sid, id, crypto.randomUUID()]);
  return { id, sid, token: jwt.sign({ sub: id, sid, aud: 'lifemate-api' }, jwtSecret, { issuer: 'lifemate', expiresIn: '15m' }) };
}
async function fixture() {
  const child = await user();
  const mother = await user();
  const father = await user();
  const outsider = await user();
  const familyId = crypto.randomUUID();
  await pool.query("insert into family_workspace(id,name,created_by) values($1,'Synthetic study family',$2)", [familyId, mother.id]);
  for (const [u, role] of [[child, 'teen_minor'], [mother, 'parent_guardian'], [father, 'parent_guardian']]) {
    await pool.query('insert into family_membership(family_id,user_id,role,is_admin) values($1,$2,$3,$4)', [familyId, u.id, role, u === mother]);
  }
  for (const u of [mother, father]) {
    await pool.query('insert into guardian_relationship(family_id,guardian_user_id,minor_user_id) values($1,$2,$3)', [familyId, u.id, child.id]);
  }
  const task = await request('/v1/plan-items', { method: 'POST', user: child, body: {
    kind: 'assignment', title: 'تمرین ریاضی آزمایشی', notes: 'PRIVATE-NOTE-DO-NOT-REPORT', familyId,
    visibility: 'parent_guardian', durationMinutes: 30, dueAt: new Date(Date.now() + 86400000).toISOString(),
  } });
  assert.equal(task.status, 201);
  return { child, mother, father, outsider, familyId, task: task.body };
}
const iso = (ms) => new Date(ms).toISOString();
const mutationId = () => crypto.randomUUID();
async function createSession(f, overrides = {}) {
  return request('/v1/study/sessions', { method: 'POST', user: f.child, body: {
    id: crypto.randomUUID(), mutationId: mutationId(), planItemId: f.task.id,
    source: 'timer', startedAt: iso(Date.now() - 3600000), ...overrides,
  } });
}
async function event(f, session, action, occurredAt, overrides = {}) {
  return request(`/v1/study/sessions/${session.id}/events`, { method: 'POST', user: f.child, body: {
    mutationId: mutationId(), expectedVersion: session.version, action, occurredAt, ...overrides,
  } });
}
const reportPath = (f) => `/v1/families/${f.familyId}/children/${f.child.id}/learning-report`;

test('real HTTP and independent PostgreSQL prove eight-step homework/study family slice across server restart', async () => {
  const f = await fixture();
  const taskRow = await pool.query('select owner_user_id,title from plan_item where id=$1', [f.task.id]);
  assert.equal(taskRow.rows[0].owner_user_id, f.child.id);
  const motherBefore = await request(reportPath(f), { user: f.mother });
  assert.equal(motherBefore.status, 200);
  assert.ok(motherBefore.body.items.some((x) => x.id === f.task.id));
  const startAt = Date.now() - 3600000;
  const created = await createSession(f, { startedAt: iso(startAt) });
  assert.equal(created.status, 201);
  const stopped = await event(f, created.body.session, 'stop', iso(startAt + 20 * 60000));
  assert.equal(stopped.status, 200);
  assert.equal(stopped.body.session.recordedDurationSeconds, 1200);
  assert.equal(stopped.body.session.isEvidenceOfStudy, false);
  const report = await request(reportPath(f), { user: f.mother });
  assert.equal(report.status, 200);
  assert.equal(report.body.metrics.recordedDurationSeconds, 1200);
  assert.equal(report.body.metrics.plannedDurationSeconds, 1800);
  assert.equal(report.body.recordingDisclaimerKey, 'recorded_time_is_not_proof_of_study');
  assert.ok(!JSON.stringify(report.body).includes('PRIVATE-NOTE-DO-NOT-REPORT'));
  const complete = await request(`/v1/plan-items/${f.task.id}/activity-state`, { method: 'POST', user: f.child, body: {
    mutationId: mutationId(), expectedVersion: stopped.body.activity.version, state: 'completed',
    occurredAt: iso(startAt + 21 * 60000), source: 'self_reported',
  } });
  assert.equal(complete.status, 200);
  const father = await request(reportPath(f), { user: f.father });
  assert.equal(father.body.items.find((x) => x.id === f.task.id).status, 'completed');
  assert.equal(father.body.items.find((x) => x.id === f.task.id).activityState, 'completed');
  assert.ok(father.body.asOf && father.body.lastSyncAt && father.body.sourceVersion);
  await new Promise((resolve) => server.close(resolve));
  server = app.listen(0);
  base = `http://127.0.0.1:${server.address().port}`;
  for (const u of [f.child, f.mother, f.father]) {
    const persisted = u === f.child
      ? await request(`/v1/study/sessions/${created.body.session.id}`, { user: u })
      : await request(reportPath(f), { user: u });
    assert.equal(persisted.status, 200);
  }
  const rows = await pool.query('select status,recorded_duration_seconds from study_session where id=$1', [created.body.session.id]);
  assert.deepEqual(rows.rows[0], { status: 'completed', recorded_duration_seconds: 1200 });
});

test('pause/resume survives API restart and duration excludes pauses; duplicate offline retries and conflicts never add time twice', async () => {
  const f = await fixture();
  const t = Date.now() - 3600000;
  const createBody = { id: crypto.randomUUID(), mutationId: mutationId(), planItemId: f.task.id, source: 'timer', startedAt: iso(t) };
  const created = await request('/v1/study/sessions', { method: 'POST', user: f.child, body: createBody });
  assert.equal(created.status, 201);
  const replay = await request('/v1/study/sessions', { method: 'POST', user: f.child, body: createBody });
  assert.equal(replay.body.acknowledgement.status, 'already_applied');
  const changedDuplicate = await request('/v1/study/sessions', { method: 'POST', user: f.child, body: { ...createBody, startedAt: iso(t - 1) } });
  assert.equal(changedDuplicate.status, 409);
  const paused = await event(f, created.body.session, 'pause', iso(t + 10 * 60000));
  assert.equal(paused.status, 200);
  assert.equal(paused.body.session.status, 'paused');
  const stale = await event(f, created.body.session, 'resume', iso(t + 20 * 60000));
  assert.equal(stale.status, 409);
  assert.equal(stale.body.error, 'version_conflict');
  await new Promise((resolve) => server.close(resolve));
  server = app.listen(0);
  base = `http://127.0.0.1:${server.address().port}`;
  const persisted = await request(`/v1/study/sessions/${created.body.session.id}`, { user: f.child });
  assert.equal(persisted.body.session.status, 'paused');
  const resumed = await event(f, persisted.body.session, 'resume', iso(t + 20 * 60000));
  assert.equal(resumed.status, 200);
  const stopBody = { mutationId: mutationId(), expectedVersion: resumed.body.session.version, action: 'stop', occurredAt: iso(t + 35 * 60000) };
  const stopped = await request(`/v1/study/sessions/${resumed.body.session.id}/events`, { method: 'POST', user: f.child, body: stopBody });
  assert.equal(stopped.body.session.recordedDurationSeconds, 1500);
  const stoppedReplay = await request(`/v1/study/sessions/${resumed.body.session.id}/events`, { method: 'POST', user: f.child, body: stopBody });
  assert.equal(stoppedReplay.body.acknowledgement.status, 'already_applied');
  assert.equal(stoppedReplay.body.session.version, stopped.body.session.version);
  const rows = await pool.query('select count(*)::int n,sum(extract(epoch from ends_at-starts_at))::int duration from study_interval where session_id=$1', [created.body.session.id]);
  assert.deepEqual(rows.rows[0], { n: 2, duration: 1500 });
  const all = await request('/v1/study/sessions', { user: f.child });
  assert.equal(all.body.sessions.length, 1);
});

test('concurrent/overlapping study sessions are rejected and interval boundaries do not double count', async () => {
  const f = await fixture();
  const t = Date.now() - 3600000;
  const [a, b] = await Promise.all([createSession(f, { startedAt: iso(t) }), createSession(f, { startedAt: iso(t + 1000) })]);
  assert.deepEqual([a.status, b.status].sort(), [201, 409]);
  const running = (a.status === 201 ? a : b).body.session;
  const stopped = await event(f, running, 'stop', iso(t + 600000));
  assert.equal(stopped.status, 200);
  const overlap = await createSession(f, { source: 'self_reported', startedAt: iso(t + 300000), endedAt: iso(t + 900000) });
  assert.equal(overlap.status, 409);
  assert.equal(overlap.body.error, 'study_time_overlap');
  const boundary = await createSession(f, { source: 'self_reported', startedAt: iso(t + 600000), endedAt: iso(t + 900000) });
  assert.equal(boundary.status, 201);
  assert.equal(boundary.body.session.recordedDurationSeconds, 300);
  assert.equal(boundary.body.session.source, 'self_reported');
});

test('reports enforce current guardian roles, both memberships, family state, relations and sharing on every read', async () => {
  const f = await fixture();
  assert.equal((await request(reportPath(f))).status, 401);
  assert.equal((await request(reportPath(f), { user: f.outsider })).status, 403);
  const s = await createSession(f);
  assert.equal(s.status, 201);
  for (const u of [f.mother, f.father, f.outsider]) {
    assert.equal((await request(`/v1/study/sessions/${s.body.session.id}`, { user: u })).status, 404);
    assert.equal((await request(`/v1/study/sessions/${s.body.session.id}/events`, { method: 'POST', user: u,
      body: { mutationId: mutationId(), expectedVersion: 1, action: 'stop', occurredAt: iso(Date.now()) } })).status, 404);
  }
  await pool.query("update plan_item set visibility='private' where id=$1", [f.task.id]);
  const privateReport = await request(reportPath(f), { user: f.mother });
  assert.equal(privateReport.status, 200);
  assert.equal(privateReport.body.items.length, 0);
  assert.equal(privateReport.body.metrics.recordedDurationSeconds, 0);
  await pool.query("update plan_item set visibility='selected_members' where id=$1", [f.task.id]);
  await pool.query("insert into sharing_grant(resource_type,resource_id,grantee_user_id,granted_by) values('plan_item',$1,$2,$3)", [f.task.id, f.mother.id, f.child.id]);
  assert.equal((await request(reportPath(f), { user: f.mother })).body.items.length, 1);
  assert.equal((await request(reportPath(f), { user: f.father })).body.items.length, 0);
  await pool.query("update family_membership set role='adult_member' where family_id=$1 and user_id=$2", [f.familyId, f.mother.id]);
  assert.equal((await request(reportPath(f), { user: f.mother })).status, 403);
  await pool.query("update family_membership set role='parent_guardian',ended_at=now() where family_id=$1 and user_id=$2", [f.familyId, f.mother.id]);
  assert.equal((await request(reportPath(f), { user: f.mother })).status, 403);
  await pool.query('update family_membership set ended_at=null where family_id=$1 and user_id=$2', [f.familyId, f.mother.id]);
  await pool.query('update guardian_relationship set active=false where family_id=$1 and guardian_user_id=$2', [f.familyId, f.mother.id]);
  assert.equal((await request(reportPath(f), { user: f.mother })).status, 403);
  await pool.query('update guardian_relationship set active=true where family_id=$1 and guardian_user_id=$2', [f.familyId, f.mother.id]);
  await pool.query('update family_membership set ended_at=now() where family_id=$1 and user_id=$2', [f.familyId, f.child.id]);
  assert.equal((await request(reportPath(f), { user: f.mother })).status, 403);
  await pool.query('update family_membership set ended_at=null where family_id=$1 and user_id=$2', [f.familyId, f.child.id]);
  await pool.query('update family_workspace set archived_at=now() where id=$1', [f.familyId]);
  assert.equal((await request(reportPath(f), { user: f.mother })).status, 403);
});

test('activity completion remains self-reported until explicit authorized guardian confirmation; sessions archive safely', async () => {
  const f = await fixture();
  const created = await createSession(f, { source: 'self_reported', startedAt: iso(Date.now() - 600000), endedAt: iso(Date.now() - 300000) });
  assert.equal(created.status, 201);
  const complete = await request(`/v1/plan-items/${f.task.id}/activity-state`, { method: 'POST', user: f.child,
    body: { mutationId: mutationId(), expectedVersion: created.body.activity.version, state: 'completed', source: 'self_reported', occurredAt: iso(Date.now() - 200000) } });
  assert.equal(complete.status, 200);
  assert.equal(complete.body.activity.state, 'completed');
  const body = { mutationId: mutationId(), expectedVersion: complete.body.activity.version, state: 'verified', source: 'guardian_confirmation', occurredAt: iso(Date.now() - 100000), confirmation: 'I confirm reviewing this homework.' };
  assert.equal((await request(`/v1/plan-items/${f.task.id}/activity-state`, { method: 'POST', user: f.child, body })).status, 403);
  assert.equal((await request(`/v1/plan-items/${f.task.id}/activity-state`, { method: 'POST', user: f.outsider, body })).status, 403);
  assert.equal((await request(`/v1/plan-items/${f.task.id}/activity-state`, { method: 'POST', user: f.mother, body: { ...body, confirmation: '' } })).status, 400);
  const verified = await request(`/v1/plan-items/${f.task.id}/activity-state`, { method: 'POST', user: f.mother, body });
  assert.equal(verified.status, 200);
  assert.equal(verified.body.activity.state, 'verified');
  assert.equal(verified.body.activity.source, 'guardian_confirmation');
  assert.equal(verified.body.activity.confirmedBy, f.mother.id);
  const archived = await request(`/v1/study/sessions/${created.body.session.id}`, { method: 'DELETE', user: f.child,
    body: { mutationId: mutationId(), expectedVersion: created.body.session.version } });
  assert.equal(archived.status, 200);
  assert.equal(archived.body.session.status, 'archived');
  assert.equal((await request('/v1/study/sessions', { user: f.child })).body.sessions.length, 0);
  assert.equal((await request(reportPath(f), { user: f.mother })).body.metrics.recordedDurationSeconds, 0);
});

test('malformed IDs, forged owner, future/reversed timestamps, unknown source and client claimed duration fail closed', async () => {
  const f = await fixture();
  assert.equal((await createSession(f, { id: 'broken' })).status, 400);
  assert.equal((await createSession(f, { childId: f.outsider.id })).status, 403);
  assert.equal((await createSession(f, { startedAt: iso(Date.now() + 3600000) })).status, 400);
  assert.equal((await createSession(f, { source: 'proof_of_study' })).status, 400);
  assert.equal((await createSession(f, { source: 'self_reported', startedAt: iso(Date.now() - 60000), endedAt: iso(Date.now() - 120000) })).status, 400);
  assert.equal((await createSession(f, { recordedDurationSeconds: 999999 })).status, 400);
  assert.equal((await request('/v1/study/sessions/not-a-uuid', { user: f.child })).status, 400);
  assert.equal((await request(`${reportPath(f)}?from=broken`, { user: f.mother })).status, 400);
  const expired = { ...f.child, token: jwt.sign({ sub: f.child.id, sid: f.child.sid, aud: 'lifemate-api' }, jwtSecret, { issuer: 'lifemate', expiresIn: -1 }) };
  assert.equal((await request('/v1/study/sessions', { user: expired })).status, 401);
});

test('guardian verification retries recheck current permission instead of replaying a revoked grant', async () => {
  const f = await fixture();
  const body = { mutationId: mutationId(), expectedVersion: 0, state: 'completed', source: 'self_reported', occurredAt: iso(Date.now() - 10000) };
  const completed = await request(`/v1/plan-items/${f.task.id}/activity-state`, { method: 'POST', user: f.child, body });
  assert.equal(completed.status, 200);
  const confirmBody = { mutationId: mutationId(), expectedVersion: completed.body.activity.version, state: 'verified', source: 'guardian_confirmation', occurredAt: iso(Date.now()), confirmation: 'Synthetic reviewed homework.' };
  const confirmed = await request(`/v1/plan-items/${f.task.id}/activity-state`, { method: 'POST', user: f.mother, body: confirmBody });
  assert.equal(confirmed.status, 200);
  await pool.query('update guardian_relationship set active=false where family_id=$1 and guardian_user_id=$2', [f.familyId, f.mother.id]);
  assert.equal((await request(`/v1/plan-items/${f.task.id}/activity-state`, { method: 'POST', user: f.mother, body: confirmBody })).status, 403);
});

test('report clips intervals at its boundaries and Tehran midnight and excludes outside-range time', async () => {
  const f = await fixture();
  const day = new Date(Date.now() - 2 * 86400000).toISOString().slice(0, 10);
  const t = new Date(`${day}T20:25:00.000Z`).getTime(); // 23:55 in Tehran
  const created = await createSession(f, { source: 'self_reported', startedAt: iso(t), endedAt: iso(t + 20 * 60000) });
  assert.equal(created.status, 201);
  const report = await request(`${reportPath(f)}?from=${encodeURIComponent(iso(t + 60000))}&to=${encodeURIComponent(iso(t + 16 * 60000))}`, { user: f.mother });
  assert.equal(report.status, 200);
  assert.equal(report.body.metrics.recordedDurationSeconds, 900);
  assert.deepEqual(report.body.daily.map((x) => x.recordedDurationSeconds), [240, 660]);
  assert.equal(report.body.daily.reduce((total, x) => total + x.recordedDurationSeconds, 0), 900);
});

test('owner can correct a self-reported session with version checks and overlap validation; parent cannot edit it', async () => {
  const f = await fixture();
  const t = Date.now() - 3600000;
  const created = await createSession(f, { source: 'self_reported', startedAt: iso(t), endedAt: iso(t + 600000) });
  assert.equal(created.status, 201);
  const body = { mutationId: mutationId(), expectedVersion: 1, startedAt: iso(t + 1000), endedAt: iso(t + 1201000) };
  assert.equal((await request(`/v1/study/sessions/${created.body.session.id}`, { method: 'PATCH', user: f.mother, body })).status, 404);
  const corrected = await request(`/v1/study/sessions/${created.body.session.id}`, { method: 'PATCH', user: f.child, body });
  assert.equal(corrected.status, 200);
  assert.equal(corrected.body.session.recordedDurationSeconds, 1200);
  assert.equal(corrected.body.session.version, 2);
  const stale = await request(`/v1/study/sessions/${created.body.session.id}`, { method: 'PATCH', user: f.child, body: { ...body, mutationId: mutationId() } });
  assert.equal(stale.status, 409);
  const other = await createSession(f, { source: 'self_reported', startedAt: iso(t + 1800000), endedAt: iso(t + 2100000) });
  assert.equal(other.status, 201);
  const overlap = await request(`/v1/study/sessions/${created.body.session.id}`, { method: 'PATCH', user: f.child,
    body: { ...body, mutationId: mutationId(), expectedVersion: 2, endedAt: iso(t + 1900000) } });
  assert.equal(overlap.status, 409);
  assert.equal(overlap.body.error, 'study_time_overlap');
  assert.equal((await request(`/v1/study/sessions/${created.body.session.id}`, { user: f.child })).body.session.recordedDurationSeconds, 1200);
});

test('owner and permitted guardian can read activity history but confirmation text and private records remain hidden', async () => {
  const f = await fixture();
  const completed = await request(`/v1/plan-items/${f.task.id}/activity-state`, { method: 'POST', user: f.child, body: {
    mutationId: mutationId(), expectedVersion: 0, state: 'completed', source: 'self_reported', occurredAt: iso(Date.now() - 1000),
  } });
  assert.equal(completed.status, 200);
  const confirmed = await request(`/v1/plan-items/${f.task.id}/activity-state`, { method: 'POST', user: f.mother, body: {
    mutationId: mutationId(), expectedVersion: completed.body.activity.version, state: 'verified', source: 'guardian_confirmation', occurredAt: iso(Date.now()), confirmation: 'PRIVATE-CONFIRMATION-CONTENT',
  } });
  assert.equal(confirmed.status, 200);
  const history = await request(`/v1/plan-items/${f.task.id}/activity-state`, { user: f.father });
  assert.equal(history.status, 200);
  assert.deepEqual(history.body.history.map((x) => x.state), ['completed', 'verified']);
  assert.equal(history.body.activity.state, 'verified');
  assert.ok(!JSON.stringify(history.body).includes('PRIVATE-CONFIRMATION-CONTENT'));
  assert.equal((await request(`/v1/plan-items/${f.task.id}/activity-state`, { user: f.outsider })).status, 403);
  await pool.query("update plan_item set visibility='private' where id=$1", [f.task.id]);
  assert.equal((await request(`/v1/plan-items/${f.task.id}/activity-state`, { user: f.father })).status, 403);
  assert.equal((await request(`/v1/plan-items/${f.task.id}/activity-state`, { user: f.child })).status, 200);
});

test('shared report preserves exact planned seconds rather than rounding through the legacy minutes column', async () => {
  const f = await fixture();
  const precise = await request('/v1/plan-items', { method: 'POST', user: f.child, body: {
    kind: 'assignment', title: 'زمان دقیق آزمایشی', familyId: f.familyId, visibility: 'parent_guardian', plannedDurationSeconds: 95,
  } });
  assert.equal(precise.status, 201);
  const report = await request(reportPath(f), { user: f.mother });
  assert.equal(report.status, 200);
  assert.equal(report.body.items.find((x) => x.id === precise.body.id).plannedDurationSeconds, 95);
  assert.equal(report.body.metrics.plannedDurationSeconds, 1895);
});
