import test, { after, before } from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import net from 'node:net';
import http from 'node:http';
import jwt from 'jsonwebtoken';
import pg from 'pg';

// Real production entrypoint, HTTP, sessions and PostgreSQL; no skipped tests or mocks.
assert.ok(process.env.DATABASE_URL, 'DATABASE_URL is required for request safety tests');
assert.ok(process.env.JWT_SECRET?.length >= 32, 'JWT_SECRET must be configured for tests');
const pool = new pg.Pool({ connectionString: process.env.DATABASE_URL });
const allowedOrigin = 'https://client.example.test';
const users = [];
let child;
let base;
let output = '';
let errors = '';

before(async () => {
  const reservation = net.createServer();
  reservation.listen(0, '127.0.0.1');
  await once(reservation, 'listening');
  const port = reservation.address().port;
  await new Promise((resolve) => reservation.close(resolve));
  base = `http://127.0.0.1:${port}`;
  child = spawn(process.execPath, ['src/entrypoint.js'], {
    cwd: new URL('..', import.meta.url),
    env: {
      ...process.env,
      PORT: String(port),
      NODE_ENV: 'production',
      ENABLE_SENSITIVE_FEATURES: 'true', // Explicit synthetic cycle/error fixtures only.
      CORS_ORIGINS: allowedOrigin,
      RATE_LIMIT_AUTH_MAX: '2000',
      RATE_LIMIT_GENERAL_MAX: '2000',
    },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  child.stdout.on('data', (chunk) => { output += chunk.toString(); });
  child.stderr.on('data', (chunk) => { errors += chunk.toString(); });
  await new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('Production entrypoint startup timed out')), 10000);
    const onData = () => {
      if (!output.includes('"type":"startup"')) return;
      clearTimeout(timer);
      child.stdout.off('data', onData);
      resolve();
    };
    child.stdout.on('data', onData);
    child.once('error', (error) => { clearTimeout(timer); reject(error); });
    child.once('exit', () => { clearTimeout(timer); reject(new Error('Production entrypoint exited before readiness')); });
  });
  assert.equal((await request('/ready')).status, 200);
});

after(async () => {
  if (child && child.exitCode === null) {
    const exited = once(child, 'exit');
    child.kill('SIGTERM');
    await exited;
  }
  if (users.length) await pool.query('delete from app_user where id=any($1::uuid[])', [users]);
  await pool.end();
});

async function request(path, { method = 'GET', body, rawBody, token, origin = allowedOrigin, headers = {} } = {}) {
  const response = await fetch(base + path, {
    method,
    headers: {
      'content-type': 'application/json',
      origin,
      ...(token ? { authorization: `Bearer ${token}` } : {}),
      ...headers,
    },
    body: rawBody ?? (body === undefined ? undefined : JSON.stringify(body)),
  });
  const text = await response.text();
  return { status: response.status, body: text ? JSON.parse(text) : null, headers: response.headers };
}

async function fixture() {
  const id = crypto.randomUUID();
  const sessionId = crypto.randomUUID();
  const refreshToken = crypto.randomBytes(32).toString('base64url');
  await pool.query(
    'insert into app_user(id,identity_subject,email_normalized,email_verified_at) values($1,$2,$3,now())',
    [id, `request-safety:${id}`, `request-safety-${id}@example.test`],
  );
  users.push(id);
  await pool.query("insert into profile(user_id,display_name,theme_preference) values($1,'Request Safety','adult_blue')", [id]);
  await pool.query(
    "insert into auth_session(id,user_id,refresh_digest,expires_at) values($1,$2,$3,now()+interval '1 day')",
    [sessionId, id, crypto.createHash('sha256').update(refreshToken).digest('hex')],
  );
  const token = jwt.sign({ sub: id, sid: sessionId, aud: 'lifemate-api' }, process.env.JWT_SECRET, { expiresIn: '15m', issuer: 'lifemate' });
  return { id, sessionId, token, refreshToken };
}

async function errorEvent(requestId, { errorProcess = child, readErrors = () => errors, eventType = 'http_error' } = {}) {
  const find = () => readErrors().split('\n').flatMap((line) => {
    try { return [JSON.parse(line)]; } catch { return []; }
  }).find((event) => event.type === eventType && event.requestId === requestId);
  if (find()) return find();
  return new Promise((resolve, reject) => {
    const cleanup = () => { clearTimeout(timer); errorProcess.stderr.off('data', onData); };
    const onData = () => {
      const event = find();
      if (!event) return;
      cleanup();
      resolve(event);
    };
    const timer = setTimeout(() => { cleanup(); reject(new Error('Correlated sanitized error event was not emitted')); }, 2000);
    errorProcess.stderr.on('data', onData);
  });
}

test('importing the shared app in production does not leave a second listener open', async () => {
  const imported = spawn(process.execPath, ['--input-type=module', '-e', 'const { pool } = await import("./src/server.js"); await pool.end();'], {
    cwd: new URL('..', import.meta.url),
    env: { ...process.env, NODE_ENV: 'production', PORT: '0' },
    stdio: 'ignore',
  });
  let timedOut = false;
  const timer = setTimeout(() => { timedOut = true; imported.kill('SIGKILL'); }, 5000);
  const [code] = await once(imported, 'exit');
  clearTimeout(timer);
  assert.equal(timedOut, false, 'Import must not keep a network listener alive');
  assert.equal(code, 0);
});

test('production Phase 6 PATCH persists Iran profile through the shared JSON pipeline', async () => {
  const user = await fixture();
  const changed = await request('/v1/me/iran-profile', {
    method: 'PATCH', token: user.token, body: { householdPersona: 'adult', sex: 'unspecified', birthDate: '1990-01-02' },
  });
  assert.equal(changed.status, 204);
  const read = await request('/v1/me/iran-profile', { token: user.token });
  assert.equal(read.status, 200);
  assert.equal(read.body.household_persona, 'adult');
  assert.equal(read.body.birth_date.slice(0, 10), '1990-01-02');
  assert.equal((await pool.query('select household_persona from profile where user_id=$1', [user.id])).rows[0].household_persona, 'adult');
});

test('production Phase 6 PUT persists education and reads it again', async () => {
  const user = await fixture();
  const write = await request('/v1/me/education', {
    method: 'PUT', token: user.token, body: { nationalGrade: 7, schoolName: 'Synthetic School', schoolYear: '1405-1406' },
  });
  assert.equal(write.status, 200);
  assert.equal(write.body.stage, 'secondary_1');
  const read = await request('/v1/me/iran-profile', { token: user.token });
  assert.equal(read.body.national_grade, 7);
  assert.equal(read.body.school_name, 'Synthetic School');
});

test('production Phase 6 PATCH persists notification preferences', async () => {
  const user = await fixture();
  const changed = await request('/v1/me/notification-preferences', {
    method: 'PATCH', token: user.token, body: { pushEnabled: false, plannerReminders: false },
  });
  assert.equal(changed.status, 200);
  const read = await request('/v1/me/notification-preferences', { token: user.token });
  assert.equal(read.body.push_enabled, false);
  assert.equal(read.body.planner_reminders, false);
});

test('production Phase 6 POST/read/DELETE uses real owner-private storage', async () => {
  const user = await fixture();
  const other = await fixture();
  const write = await request('/v1/me/menstrual-cycles', {
    method: 'POST', token: user.token, body: { startsOn: '2026-10-01', endsOn: '2026-10-04', notes: 'Synthetic owner-private note' },
  });
  assert.equal(write.status, 201);
  const read = await request('/v1/me/menstrual-cycles', { token: user.token });
  assert.equal(read.body.entries[0].id, write.body.id);
  assert.equal(read.body.entries[0].notes, 'Synthetic owner-private note');
  assert.equal((await request('/v1/me/menstrual-cycles', { token: other.token })).body.entries.length, 0);
  assert.equal((await request(`/v1/me/menstrual-cycles/${write.body.id}`, { method: 'DELETE', token: other.token })).status, 204);
  assert.equal((await pool.query('select 1 from menstrual_cycle_entry where id=$1', [write.body.id])).rowCount, 1);
  assert.equal((await request(`/v1/me/menstrual-cycles/${write.body.id}`, { method: 'DELETE', token: user.token })).status, 204);
  assert.equal((await request('/v1/me/menstrual-cycles', { token: user.token })).body.entries.length, 0);
  assert.equal((await pool.query('select 1 from menstrual_cycle_entry where id=$1', [write.body.id])).rowCount, 0);
});

test('production standard and Phase 6 responses share allowed-origin CORS', async () => {
  const user = await fixture();
  for (const path of ['/v1/profile', '/v1/me/iran-profile', '/v1/me/menstrual-cycles']) {
    const response = await request(path, { token: user.token });
    assert.equal(response.status, 200);
    assert.equal(response.headers.get('access-control-allow-origin'), allowedOrigin);
  }
});

test('production CORS preflight supports PATCH, PUT, POST and DELETE before authentication', async () => {
  for (const [method, path] of [
    ['PATCH', '/v1/me/iran-profile'], ['PUT', '/v1/me/education'],
    ['POST', '/v1/me/menstrual-cycles'], ['DELETE', '/v1/me/menstrual-cycles/unused'],
  ]) {
    const response = await fetch(base + path, {
      method: 'OPTIONS', headers: { origin: allowedOrigin, 'access-control-request-method': method, 'access-control-request-headers': 'authorization,content-type' },
    });
    assert.equal(response.status, 204);
    assert.equal(response.headers.get('access-control-allow-origin'), allowedOrigin);
    assert.ok(response.headers.get('access-control-allow-methods').split(',').includes(method));
  }
});

test('production rejects unapproved origins consistently in standard and Phase 6 routes', async () => {
  const user = await fixture();
  for (const path of ['/v1/profile', '/v1/me/iran-profile']) {
    const response = await request(path, { token: user.token, origin: 'https://denied.example.test' });
    assert.equal(response.status, 403);
    assert.equal(response.headers.get('access-control-allow-origin'), null);
    assert.equal(response.body.error, 'cors_origin_denied');
  }
});

test('malformed JSON returns correlated 400 in either route', async () => {
  const user = await fixture();
  for (const [method, path] of [['POST', '/v1/auth/login'], ['PATCH', '/v1/me/iran-profile']]) {
    const response = await request(path, { method, token: user.token, rawBody: '{"password":"synthetic",' });
    await errorEvent(response.headers.get('x-request-id'));
    assert.equal(response.status, 400);
    assert.equal(response.body.error, 'invalid_json');
    assert.equal(response.body.requestId, response.headers.get('x-request-id'));
  }
});

test('malformed sensitive request bodies never enter production logs', async () => {
  const user = await fixture();
  const marker = `synthetic-sensitive-${crypto.randomUUID()}`;
  for (const [method, path] of [['POST', '/v1/auth/login'], ['PATCH', '/v1/me/iran-profile']]) {
    const response = await request(path, { method, token: user.token, rawBody: `{"password":"${marker}",` });
    const event = await errorEvent(response.headers.get('x-request-id'));
    assert.deepEqual(Object.keys(event).sort(), ['errorClass', 'method', 'path', 'requestId', 'type']);
  }
  assert.equal(errors.includes(marker), false, 'Sensitive request body must not enter stderr');
  assert.equal(output.includes(marker), false, 'Sensitive request body must not enter stdout');
});

test('production body limit returns 413 consistently before either router writes', async () => {
  const user = await fixture();
  for (const [method, path] of [['POST', '/v1/auth/login'], ['PATCH', '/v1/me/iran-profile']]) {
    const response = await request(path, { method, token: user.token, body: { notes: 'x'.repeat(66000) } });
    assert.equal(response.status, 413);
    assert.equal(response.body.error, 'request_body_too_large');
  }
});

test('unexpected database errors use sanitized correlated logs and responses', async () => {
  const user = await fixture();
  const marker = `synthetic-private-note-${crypto.randomUUID()}`;
  const errorStart = errors.length;
  const response = await request('/v1/me/menstrual-cycles', {
    method: 'POST', token: user.token, body: { startsOn: '2026-10-04', endsOn: '2026-10-01', notes: marker },
  });
  await errorEvent(response.headers.get('x-request-id'));
  assert.equal(response.status, 500);
  assert.deepEqual(Object.keys(response.body).sort(), ['error', 'requestId']);
  assert.equal(response.body.error, 'internal_error');
  assert.equal(errors.includes(marker), false, 'Database row detail must not enter stderr');
  const lines = errors.slice(errorStart).trim().split('\n').filter(Boolean);
  assert.ok(lines.every((line) => { try { JSON.parse(line); return true; } catch { return false; } }), 'Error logs must contain only sanitized JSON events');
  const events = lines.map((line) => JSON.parse(line));
  assert.ok(events.some((event) => event.type === 'http_error' && event.requestId === response.body.requestId));
  assert.ok(events.some((event) => event.errorClass !== 'TypeError'), 'The write must reach PostgreSQL rather than fail before body parsing');
});

test('errors after a partial HTTP response terminate the stream without leaking the raw error', { timeout: 10000 }, async () => {
  const marker = `synthetic-stream-secret-${crypto.randomUUID()}`;
  let fixtureOutput = '';
  let fixtureErrors = '';
  const streamServer = spawn(process.execPath, ['tests/fixtures/partial_error_server.js'], {
    cwd: new URL('..', import.meta.url),
    env: { ...process.env, NODE_ENV: 'production', STREAM_ERROR_MARKER: marker },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  streamServer.stdout.on('data', (chunk) => { fixtureOutput += chunk.toString(); });
  streamServer.stderr.on('data', (chunk) => { fixtureErrors += chunk.toString(); });
  try {
    const port = await new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('Streaming HTTP fixture startup timed out')), 5000);
      const onData = () => {
        const line = fixtureOutput.split('\n').find((value) => value.includes('"stream_fixture_ready"'));
        if (!line) return;
        clearTimeout(timer);
        streamServer.stdout.off('data', onData);
        resolve(JSON.parse(line).port);
      };
      streamServer.stdout.on('data', onData);
      streamServer.once('error', (error) => { clearTimeout(timer); reject(error); });
    });
    const fixtureBase = `http://127.0.0.1:${port}`;
    const response = await new Promise((resolve, reject) => {
      http.get(fixtureBase + '/partial-error', resolve).once('error', reject);
    });
    const terminated = new Promise((resolve) => {
      response.once('aborted', () => resolve(true));
      response.once('end', () => resolve(false));
      response.on('error', () => {});
    });
    const [chunk] = await once(response, 'data');
    assert.equal(chunk.toString(), 'started');
    assert.equal((await fetch(fixtureBase + '/trigger-error', { method: 'POST' })).status, 204);
    assert.equal(await terminated, true, 'Partially written response must be terminated');
    const event = await errorEvent(response.headers['x-request-id'], { errorProcess: streamServer, readErrors: () => fixtureErrors });
    assert.deepEqual(Object.keys(event).sort(), ['errorClass', 'method', 'path', 'requestId', 'type']);
    // Wait for a callback queued after Express's deferred logging, then drain.
    await errorEvent(response.headers['x-request-id'], {
      errorProcess: streamServer, readErrors: () => fixtureErrors, eventType: 'stream_error_drained',
    });
    const closed = once(streamServer, 'close');
    streamServer.kill('SIGTERM');
    await closed;
    assert.equal(fixtureErrors.includes(marker), false, 'Raw error message or stack must never enter stderr');
    assert.equal(fixtureOutput.includes(marker), false, 'Raw error message or stack must never enter stdout');
  } finally {
    if (streamServer.exitCode === null && streamServer.signalCode === null) {
      const exited = once(streamServer, 'close');
      streamServer.kill('SIGTERM');
      await exited;
    }
  }
});

for (const path of ['/v1/profile', '/v1/me/iran-profile']) {
  test(`disabled account immediately rejects its existing session at ${path}`, async () => {
    const user = await fixture();
    assert.equal((await request(path, { token: user.token })).status, 200);
    await pool.query('update app_user set disabled_at=now() where id=$1', [user.id]);
    const response = await request(path, { token: user.token });
    assert.equal(response.status, 401);
    assert.equal(response.body.error, 'session_invalid');
  });
}

test('disabled account cannot rotate a valid refresh token or create a new session', async () => {
  const user = await fixture();
  const first = await request('/v1/auth/refresh', { method: 'POST', body: { refreshToken: user.refreshToken } });
  assert.equal(first.status, 200);
  await pool.query('update app_user set disabled_at=now() where id=$1', [user.id]);
  const beforeCount = (await pool.query('select count(*)::int as n from auth_session where user_id=$1', [user.id])).rows[0].n;
  const response = await request('/v1/auth/refresh', { method: 'POST', body: { refreshToken: first.body.refreshToken } });
  assert.equal(response.status, 401);
  assert.equal(response.body.error, 'invalid_refresh_token');
  assert.equal((await pool.query('select count(*)::int as n from auth_session where user_id=$1', [user.id])).rows[0].n, beforeCount);
});

test('disabled account cannot mutate a Phase 6 record with its existing session', async () => {
  const user = await fixture();
  assert.equal((await request('/v1/me/education', {
    method: 'PUT', token: user.token, body: { nationalGrade: 7, schoolName: 'Before Disable' },
  })).status, 200);
  await pool.query('update app_user set disabled_at=now() where id=$1', [user.id]);
  const blocked = await request('/v1/me/education', {
    method: 'PUT', token: user.token, body: { nationalGrade: 8, schoolName: 'Must Not Persist' },
  });
  assert.equal(blocked.status, 401);
  const row = (await pool.query('select national_grade,school_name from education_profile where user_id=$1', [user.id])).rows[0];
  assert.equal(row.national_grade, 7);
  assert.equal(row.school_name, 'Before Disable');
});

test('revoked and expired sessions are rejected consistently across both routers', async () => {
  for (const reason of ['revoked', 'expired']) {
    const user = await fixture();
    if (reason === 'revoked') await pool.query('update auth_session set revoked_at=now() where id=$1', [user.sessionId]);
    else await pool.query("update auth_session set expires_at=now()-interval '1 minute' where id=$1", [user.sessionId]);
    for (const path of ['/v1/profile', '/v1/me/iran-profile']) {
      assert.equal((await request(path, { token: user.token })).status, 401);
    }
  }
});
