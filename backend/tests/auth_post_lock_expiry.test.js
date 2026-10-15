// Only loopback PostgreSQL and synthetic identities; no delivery provider is called.
import test, { after } from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import express from 'express';
import pg from 'pg';
import { createAuthRouter } from '../src/auth_router.js';

const url = new URL(process.env.DATABASE_URL);
assert.ok(['127.0.0.1', 'localhost', '[::1]'].includes(url.hostname));
assert.match(url.pathname, /^\/(?:lifeguide_roles_source_[a-f0-9]{16}|lifemate_ci|lifeguide_\w*test\w*)$/);
const marker = 'auth-expiry-' + crypto.randomUUID();
const pool = new pg.Pool({ connectionString: url.href, application_name: marker });
const secret = 'synthetic-auth-expiry-fixture-not-a-live-key-2026';
const users = [];
const app = express();
app.use(express.json());
app.use('/auth', createAuthRouter({ pool, jwtSecret: secret, env: { NODE_ENV: 'test' },
  auth: (_req, _res, next) => next(),
  emailProvider: { configured: false },
  smsProvider: { configured: true, status: 'TEST_ONLY', async sendOtp() { assert.fail('No SMS should be sent'); } },
}));
const server = app.listen(0, '127.0.0.1');
await new Promise(resolve => server.once('listening', resolve));
const base = 'http://127.0.0.1:' + server.address().port + '/auth';
after(async () => {
  await new Promise(resolve => server.close(resolve));
  await pool.query('delete from app_user where id=any($1::uuid[])', [users]);
  await pool.end();
});

async function owner() {
  const id = crypto.randomUUID(); users.push(id);
  await pool.query("insert into app_user(id,identity_subject,email_normalized,phone_verified_at) values($1,$2,$3,now())",
    [id, 'synthetic-expiry:' + id, 'expiry-' + id + '@example.test']);
  return id;
}
async function request(path, body) {
  return fetch(base + path, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body), signal: AbortSignal.timeout(10000) });
}
async function observedWait() {
  for (let n = 0; n < 250; n++) {
    const r = await pool.query("select 1 from pg_stat_activity where application_name=$1 and wait_event_type='Lock'", [marker]);
    if (r.rowCount) return;
    await new Promise(resolve => setTimeout(resolve, 10));
  }
  assert.fail('Expected an actual PostgreSQL row-lock wait');
}
async function blockedRequest(userId, operation, expire) {
  const blocker = await pool.connect();
  try {
    await blocker.query('begin');
    await blocker.query('select 1 from app_user where id=$1 for update', [userId]);
    const response = operation();
    await observedWait();
    // Expire after the request transaction began, without a timing-sensitive sleep.
    await expire();
    await blocker.query('commit');
    return await response;
  } finally { await blocker.query('rollback'); blocker.release(); }
}

for (const kind of ['email_verification', 'password_reset']) {
  test(kind + ' expires during an observed account-row wait and cannot be consumed', async () => {
    const userId = await owner(), token = crypto.randomBytes(32).toString('base64url');
    await pool.query("insert into auth_token(user_id,kind,token_digest,expires_at) values($1,$2,$3,now()+interval '1 hour')",
      [userId, kind, crypto.createHash('sha256').update(token).digest('hex')]);
    const response = await blockedRequest(userId,
      () => request(kind === 'email_verification' ? '/verify-email' : '/reset-password', { token, newPassword: 'SyntheticReplacement123!' }),
      () => pool.query("update auth_token set expires_at=clock_timestamp() where user_id=$1", [userId]));
    assert.equal(response.status, 400);
    assert.equal((await response.json()).error, 'invalid_or_expired_token');
    assert.equal((await pool.query('select used_at from auth_token where user_id=$1', [userId])).rows[0].used_at, null);
  });
}

test('refresh expiry after an observed account-row wait cannot mint a replacement session', async () => {
  const userId = await owner(), raw = crypto.randomBytes(32).toString('base64url');
  await pool.query("insert into auth_session(user_id,refresh_digest,expires_at) values($1,$2,now()+interval '1 hour')",
    [userId, crypto.createHash('sha256').update(raw).digest('hex')]);
  const response = await blockedRequest(userId, () => request('/refresh', { refreshToken: raw }),
    () => pool.query("update auth_session set expires_at=clock_timestamp() where user_id=$1", [userId]));
  assert.equal(response.status, 401);
  const rows = await pool.query('select revoked_at from auth_session where user_id=$1', [userId]);
  assert.equal(rows.rowCount, 1);
  assert.equal(rows.rows[0].revoked_at, null);
});

test('OTP expiry after an observed account-row wait neither authenticates nor consumes the challenge', async () => {
  const userId = await owner(), id = crypto.randomUUID(), code = '123456';
  const digest = crypto.createHmac('sha256', secret).update(`otp:${id}:${code}`).digest('hex');
  await pool.query("insert into auth_phone_challenge(id,user_id,purpose,code_digest,expires_at) values($1,$2,'login',$3,now()+interval '5 minutes')", [id, userId, digest]);
  const response = await blockedRequest(userId, () => request('/phone/verify-otp', { challengeId: id, code }),
    () => pool.query("update auth_phone_challenge set expires_at=clock_timestamp() where id=$1", [id]));
  assert.equal(response.status, 401);
  const row = (await pool.query('select attempts,used_at from auth_phone_challenge where id=$1', [id])).rows[0];
  assert.equal(row.used_at, null);
  assert.equal(row.attempts, 0);
});
