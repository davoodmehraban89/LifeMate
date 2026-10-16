import test from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import jwt from 'jsonwebtoken';
import { createSessionAuth } from '../src/session_auth.js';

// Unit boundary tests: the pool is a stub. PostgreSQL integration is separate.
const secret = 'synthetic-managed-scope-unit-fixture-not-live';
async function probe({ path = '/v1/today', method = 'GET', scope = 'child_education', managed = true,
  active = true, env = { NODE_ENV: 'test', ENABLE_CHILD_IDENTITY_SANDBOX: 'true' } } = {}) {
  const app = express();
  const pool = { async query() { return { rowCount: active ? 1 : 0,
    rows: active ? [{ access_scope: scope, is_managed_child: managed, child_issuer_user_id: '00000000-0000-4000-8000-000000000004' }] : [] }; } };
  app.use(createSessionAuth({ pool, jwtSecret: secret, env }));
  app.use((_req, res) => res.json({ reached: true }));
  const server = app.listen(0, '127.0.0.1');
  await new Promise(resolve => server.once('listening', resolve));
  const token = jwt.sign({ sub: '00000000-0000-4000-8000-000000000001', sid: '00000000-0000-4000-8000-000000000002' },
    secret, { issuer: 'lifemate', audience: 'lifemate-api', expiresIn: '1h' });
  try {
    const response = await fetch('http://127.0.0.1:' + server.address().port + path,
      { method, headers: { authorization: 'Bearer ' + token } });
    return { status: response.status, body: await response.json() };
  } finally { await new Promise(resolve => server.close(resolve)); }
}

test('managed child is fail-closed in production and without the sandbox flag', async () => {
  assert.equal((await probe({ env: { NODE_ENV: 'production', ENABLE_CHILD_IDENTITY_SANDBOX: 'true' } })).status, 503);
  assert.equal((await probe({ env: { NODE_ENV: 'test' } })).status, 503);
});
test('managed marker and stored restricted scope must agree', async () => {
  assert.equal((await probe({ scope: 'standard' })).status, 401);
  assert.equal((await probe({ managed: false })).status, 401);
});
test('restricted device cannot read legacy private records or change identity or membership', async () => {
  for (const path of ['/v1/today', '/v1/plan-items', '/v1/study/sessions', '/v1/me/learning-attempts',
    '/v1/education/library', '/v1/education/courses/00000000-0000-4000-8000-000000000003',
    '/v1/learning/goals', '/v1/learning/checkins', '/v1/me/iran-profile', '/v1/me/menstrual-cycles',
    '/v1/ai/sessions', '/v1/content-review', '/v1/profile/', '/V1/profile', '/v1/%70rofile']) {
    assert.equal((await probe({ path })).status, 403, path);
  }
  for (const path of ['/v1/profile', '/v1/families', '/v1/sync/mutations', '/v1/auth/change-password']) {
    assert.equal((await probe({ path, method: 'POST' })).status, 403, path);
  }
});
test('restricted device only reaches exact safe catalogue and projected identity reads', async () => {
  for (const path of ['/v1/profile', '/v1/families', '/v1/child-visibility', '/v1/education/catalog',
    '/v1/calendar/iran', '/v1/education/units/00000000-0000-4000-8000-000000000003',
    '/v1/education/units/00000000-0000-4000-8000-000000000003/assessment']) {
    assert.equal((await probe({ path })).status, 200, path);
  }
});
test('ordinary account retains legacy routes; stale managed access is rejected', async () => {
  assert.equal((await probe({ managed: false, scope: 'standard' })).status, 200);
  assert.equal((await probe({ active: false })).status, 401);
});
