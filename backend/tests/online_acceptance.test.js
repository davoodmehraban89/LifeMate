import test from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import net from 'node:net';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import pg from 'pg';

// Real API/DB acceptance substitutes. These do not claim Flutter rendering,
// Android lifecycle, iPhone/Safari installation or reachability from Iran.
const databaseUrl = process.env.DATABASE_URL;
assert.ok(databaseUrl, 'Configure a separate synthetic PostgreSQL database');
const pool = new pg.Pool({ connectionString: databaseUrl });
const backendDir = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const secret = 'synthetic-online-acceptance-secret-32-characters';
const uuid = () => crypto.randomUUID();
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const iso = (ms) => new Date(ms).toISOString();
let apiProcess, base, port, output = '';

async function startApi() {
  const reservation = net.createServer();
  await new Promise((resolve, reject) => { reservation.once('error', reject); reservation.listen(0, '127.0.0.1', resolve); });
  port = reservation.address().port;
  await new Promise((resolve) => reservation.close(resolve));
  base = `http://127.0.0.1:${port}`;
  output = '';
  apiProcess = spawn(process.execPath, ['src/entrypoint.js'], {
    cwd: backendDir,
    env: { ...process.env, NODE_ENV: 'test', DATABASE_URL: databaseUrl, JWT_SECRET: secret, PORT: String(port),
      RATE_LIMIT_GENERAL_MAX: '2000', RATE_LIMIT_AUTH_MAX: '2000', ENABLE_SENSITIVE_FEATURES: 'false',
      EMAIL_FROM: '', SMTP_HOST: '', SMTP_PORT: '', RESEND_API_KEY: '',
      SMS_PROVIDER: 'disabled', SMS_PROVIDER_URL: '', SMS_PROVIDER_TOKEN: '', AI_API_KEY: '', AI_BASE_URL: '', AI_MODEL: '' },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  apiProcess.stdout.on('data', (chunk) => { output += chunk.toString(); });
  apiProcess.stderr.on('data', (chunk) => { output += chunk.toString(); });
  for (let attempt = 0; attempt < 100; attempt++) {
    if (apiProcess.exitCode !== null) throw new Error(`Synthetic API failed to start: ${output}`);
    try {
      const ready = await fetch(`${base}/ready`, { signal: AbortSignal.timeout(500) });
      if (ready.status === 200) return;
    } catch { /* Poll only the loopback test process. */ }
    await sleep(50);
  }
  throw new Error('Synthetic API readiness timed out');
}
async function stopApi() {
  if (!apiProcess || apiProcess.exitCode !== null) return;
  const current = apiProcess;
  const exited = once(current, 'exit');
  current.kill('SIGTERM');
  const killer = setTimeout(() => current.kill('SIGKILL'), 3000);
  await exited;
  clearTimeout(killer);
  apiProcess = null;
}
async function request(route, { method = 'GET', body, actor, token = actor?.accessToken } = {}) {
  const response = await fetch(base + route, { method, headers: { 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}) },
    body: body === undefined ? undefined : JSON.stringify(body), signal: AbortSignal.timeout(5000) });
  const raw = await response.text();
  return { status: response.status, body: raw ? JSON.parse(raw) : null };
}
async function register(displayName) {
  const email = `acceptance-${uuid()}@example.test`, password = 'SyntheticOnlinePass!123';
  const created = await request('/v1/auth/register', { method: 'POST', body: { displayName, email, password } });
  // Test-only delivery hook provides proof tokens. Real email/SMS delivery is
  // deliberately unconfigured and remains UNVERIFIED by this acceptance test.
  assert.equal(created.status, 201);
  assert.equal((await request('/v1/auth/verify-email', { method: 'POST', body: { token: created.body.verificationToken, newPassword: password } })).status, 204);
  const login = await request('/v1/auth/login', { method: 'POST', body: { email, password } });
  assert.equal(login.status, 200);
  const profile = await request('/v1/profile', { token: login.body.accessToken });
  assert.equal(profile.status, 200);
  return { id: profile.body.user_id, email, ...login.body };
}
async function refresh(actor) {
  const previous = actor.refreshToken;
  const response = await request('/v1/auth/refresh', { method: 'POST', body: { refreshToken: previous } });
  assert.equal(response.status, 200);
  assert.notEqual(response.body.refreshToken, previous);
  Object.assign(actor, response.body);
}
async function invite(mother, member, familyId, role) {
  const invitation = await request(`/v1/families/${familyId}/invitations`, { method: 'POST', actor: mother, body: { email: member.email, role } });
  assert.equal(invitation.status, 201);
  assert.equal((await request('/v1/invitations/accept', { method: 'POST', actor: member, body: { token: invitation.body.invitationToken } })).status, 204);
}
const reportRoute = (familyId, childId) => `/v1/families/${familyId}/children/${childId}/learning-report`;
async function sync(actor, mutation) {
  return request('/v1/sync/mutations', { method: 'POST', actor, body: { mutations: [mutation] } });
}

test('online eight-step family scenario: real entrypoint, independent HTTP clients and PostgreSQL; device/Safari UNVERIFIED', async (t) => {
  try {
    await startApi();
    const [child, mother, father, outsider] = await Promise.all(['فرزند آزمایشی', 'مادر آزمایشی', 'پدر آزمایشی', 'خانواده دیگر آزمایشی'].map(register));
    const createdFamily = await request('/v1/families', { method: 'POST', actor: mother, body: { name: 'خانواده مصنوعی پذیرش', role: 'parent_guardian' } });
    assert.equal(createdFamily.status, 201);
    const familyId = createdFamily.body.id;
    await invite(mother, child, familyId, 'teen_minor');
    await invite(mother, father, familyId, 'parent_guardian');
    for (const parent of [mother, father]) assert.equal((await request(`/v1/families/${familyId}/guardians`, {
      method: 'POST', actor: mother, body: { guardianUserId: parent.id, minorUserId: child.id },
    })).status, 204);
    const otherFamily = await request('/v1/families', { method: 'POST', actor: outsider, body: { name: 'خانواده مستقل مصنوعی', role: 'parent_guardian' } });
    assert.equal(otherFamily.status, 201);
    const taskId = uuid(), createBody = { id: uuid(), entityType: 'plan_item', entityId: taskId, operation: 'create', expectedVersion: 0, payload: {
      kind: 'assignment', title: 'تمرین ریاضی — فقط داده آزمایشی', notes: 'OWNER-PRIVATE-ACCEPTANCE-NOTE',
      familyId, visibility: 'parent_guardian', plannedDurationSeconds: 1800, dueAt: iso(Date.now() + 3600000),
    } };
    const reportPath = reportRoute(familyId, child.id);

    await t.test('A / step 1: child homework creation independently verified by API and PostgreSQL', async () => {
      const created = await sync(child, createBody);
      assert.equal(created.status, 200);
      assert.equal(created.body.results[0].status, 'accepted');
      assert.equal(created.body.results[0].item.id, taskId);
      const independentRead = await request(`/v1/plan-items/${taskId}`, { actor: child });
      assert.equal(independentRead.status, 200);
      assert.equal(independentRead.body.notes, 'OWNER-PRIVATE-ACCEPTANCE-NOTE');
      const database = await pool.query('select id,owner_user_id,title,version from plan_item where id=$1', [taskId]);
      assert.equal(database.rowCount, 1);
      assert.equal(database.rows[0].owner_user_id, child.id);
      assert.equal(Number(database.rows[0].version), 1);
    });
    await t.test('B / step 2: mother receives permitted report with freshness; PWA rendering UNVERIFIED', async () => {
      const report = await request(reportPath, { actor: mother });
      assert.equal(report.status, 200);
      assert.ok(report.body.items.some((item) => item.id === taskId));
      assert.ok(Number.isFinite(Date.parse(report.body.asOf)));
      assert.ok(Number.isFinite(Date.parse(report.body.lastSyncAt)));
      assert.ok(report.body.sourceVersion);
      assert.ok(!JSON.stringify(report.body).includes('OWNER-PRIVATE-ACCEPTANCE-NOTE'));
    });
    const t0 = Date.now() - 3600000, startBody = { id: uuid(), mutationId: uuid(), planItemId: taskId, source: 'timer', startedAt: iso(t0) };
    let session;
    await t.test('G / steps 3–4: timer pause survives full API process restart, resumes and stops without double counting', async () => {
      const started = await request('/v1/study/sessions', { method: 'POST', actor: child, body: startBody });
      assert.equal(started.status, 201); session = started.body.session;
      const overlap = await request('/v1/study/sessions', { method: 'POST', actor: child, body: { ...startBody, id: uuid(), mutationId: uuid(), startedAt: iso(t0 + 1000) } });
      assert.equal(overlap.status, 409); assert.equal(overlap.body.error, 'study_time_overlap');
      const paused = await request(`/v1/study/sessions/${session.id}/events`, { method: 'POST', actor: child,
        body: { mutationId: uuid(), expectedVersion: session.version, action: 'pause', occurredAt: iso(t0 + 5 * 60000) } });
      assert.equal(paused.status, 200); session = paused.body.session;
      await stopApi(); await startApi();
      for (const actor of [child, mother, father]) await refresh(actor);
      const restored = await request(`/v1/study/sessions/${session.id}`, { actor: child });
      assert.equal(restored.status, 200); assert.equal(restored.body.session.status, 'paused');
      assert.equal(restored.body.session.recordedDurationSeconds, 300);
      const resumed = await request(`/v1/study/sessions/${session.id}/events`, { method: 'POST', actor: child,
        body: { mutationId: uuid(), expectedVersion: restored.body.session.version, action: 'resume', occurredAt: iso(t0 + 15 * 60000) } });
      assert.equal(resumed.status, 200);
      const stopBody = { mutationId: uuid(), expectedVersion: resumed.body.session.version, action: 'stop', occurredAt: iso(t0 + 35 * 60000) };
      const stopped = await request(`/v1/study/sessions/${session.id}/events`, { method: 'POST', actor: child, body: stopBody });
      assert.equal(stopped.status, 200); session = stopped.body.session;
      assert.equal(session.recordedDurationSeconds, 1500); assert.equal(session.isEvidenceOfStudy, false);
      const replay = await request(`/v1/study/sessions/${session.id}/events`, { method: 'POST', actor: child, body: stopBody });
      assert.equal(replay.body.acknowledgement.status, 'already_applied');
      assert.equal(replay.body.session.recordedDurationSeconds, 1500);
      const durations = await pool.query('select count(*)::int n,sum(extract(epoch from ends_at-starts_at))::int seconds from study_interval where session_id=$1', [session.id]);
      assert.deepEqual(durations.rows[0], { n: 2, seconds: 1500 });
      t.diagnostic('G substitute: actual Node API process restart and timer HTTP replay; Flutter timer app exit/re-sync remains UNVERIFIED.');
    });
    await t.test('step 5: recorded duration appears only in permitted parent report and is not proof of study', async () => {
      const report = await request(reportPath, { actor: mother });
      assert.equal(report.status, 200);
      assert.equal(report.body.items.find((item) => item.id === taskId).recordedDurationSeconds, 1500);
      assert.equal(report.body.items.find((item) => item.id === taskId).plannedDurationSeconds, 1800);
      assert.equal(report.body.isEvidenceOfStudy, false);
      assert.equal(report.body.recordingDisclaimerKey, 'recorded_time_is_not_proof_of_study');
    });
    await t.test('C / steps 6–7: child completion is observed by father through an independent authenticated API poll', async () => {
      const current = await request(`/v1/plan-items/${taskId}`, { actor: child });
      const complete = await sync(child, { id: uuid(), entityType: 'plan_item', entityId: taskId, operation: 'complete', expectedVersion: Number(current.body.version), payload: {} });
      assert.equal(complete.body.results[0].status, 'accepted');
      const fatherReport = await request(reportPath, { actor: father });
      const task = fatherReport.body.items.find((item) => item.id === taskId);
      assert.equal(task.status, 'completed'); assert.equal(task.activityState, 'completed');
      assert.equal(task.activitySource, 'self_reported');
      assert.equal(task.recordedDurationSeconds, 1500);
    });
    await t.test('D / step 8: API process restart preserves all three accounts, refresh sessions and shared PostgreSQL records', async () => {
      await stopApi(); await startApi();
      for (const actor of [child, mother, father]) {
        await refresh(actor);
        assert.equal((await request('/v1/profile', { actor })).status, 200);
        const read = await request(`/v1/plan-items/${taskId}`, { actor });
        assert.equal(read.status, 200); assert.equal(read.body.status, 'completed');
      }
      assert.equal((await pool.query('select status,recorded_duration_seconds from study_session where id=$1', [session.id])).rows[0].recorded_duration_seconds, 1500);
      t.diagnostic('D substitute: actual API process restart and DB-backed refresh. Closing/reopening Android and installed iPhone PWA remains UNVERIFIED.');
    });
    await t.test('E: disconnected HTTP request stays queued and later identical replay creates exactly one durable task', async () => {
      const offline = { id: uuid(), entityType: 'plan_item', entityId: uuid(), operation: 'create', expectedVersion: 0, payload: {
        kind: 'assignment', title: 'تکلیف آفلاین مصنوعی', familyId, visibility: 'parent_guardian', plannedDurationSeconds: 600,
      } };
      const retainedJournal = JSON.stringify(offline);
      await stopApi();
      await assert.rejects(sync(child, JSON.parse(retainedJournal)), TypeError);
      await startApi();
      const first = await sync(child, JSON.parse(retainedJournal)), second = await sync(child, JSON.parse(retainedJournal));
      assert.equal(first.body.results[0].status, 'accepted');
      assert.equal(second.body.results[0].status, 'already_applied');
      assert.deepEqual(second.body.results[0].item, first.body.results[0].item);
      assert.equal((await pool.query('select count(*)::int n from plan_item where id=$1', [offline.entityId])).rows[0].n, 1);
      t.diagnostic('E substitute: real HTTP disconnection and retained JSON mutation replay; Flutter persistent offline queue requires separate evidence, device offline acceptance UNVERIFIED.');
    });
    await t.test('F: other-family parent cannot read/write shared child data; private tasks/notes stay owner-only', async () => {
      assert.equal((await request(reportPath, { actor: outsider })).status, 403);
      assert.equal((await request(`/v1/plan-items/${taskId}`, { actor: outsider })).status, 404);
      const current = await request(`/v1/plan-items/${taskId}`, { actor: child });
      assert.equal((await request(`/v1/plan-items/${taskId}`, { method: 'PATCH', actor: outsider, body: { title: 'Forbidden', expectedVersion: Number(current.body.version) } })).status, 403);
      const privateTask = await request('/v1/plan-items', { method: 'POST', actor: child, body: {
        kind: 'task', title: 'PRIVATE-TASK-ACCEPTANCE-TITLE', notes: 'PRIVATE-TASK-ACCEPTANCE-NOTE', visibility: 'private',
      } });
      assert.equal(privateTask.status, 201);
      for (const parent of [mother, father, outsider]) assert.equal((await request(`/v1/plan-items/${privateTask.body.id}`, { actor: parent })).status, 404);
      for (const parent of [mother, father]) {
        const calendar = await request(`/v1/families/${familyId}/calendar`, { actor: parent });
        const content = JSON.stringify(calendar.body);
        assert.ok(!content.includes('OWNER-PRIVATE-ACCEPTANCE-NOTE'));
        assert.ok(!content.includes('PRIVATE-TASK-ACCEPTANCE'));
      }
      assert.equal((await request(`/v1/study/sessions/${session.id}`, { actor: mother })).status, 404);
      assert.equal((await request(`/v1/study/sessions/${session.id}`)).status, 401);
    });
    t.diagnostic('H/Safari install, Android devices, PWA UI/session lifecycle, no-VPN Iran reachability, real SMS/email delivery: UNVERIFIED. Only synthetic data and loopback/local PostgreSQL were used.');
  } finally { await stopApi(); await pool.end(); }
});
