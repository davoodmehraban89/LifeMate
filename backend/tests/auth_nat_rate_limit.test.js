import test, { after, before } from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import net from 'node:net';
import pg from 'pg';
import argon2 from 'argon2';
import jwt from 'jsonwebtoken';

const fixtureUrl = process.env.TEST_FIXTURE_DATABASE_URL ?? process.env.DATABASE_URL;
assert.ok(fixtureUrl, 'NAT acceptance requires migrated synthetic PostgreSQL');
const database = new URL(fixtureUrl);
assert.ok(['localhost', '127.0.0.1', '[::1]', '::1'].includes(database.hostname), 'Only loopback PostgreSQL allowed');
assert.ok(['/lifeguide_library_test', '/lifeguide_contentops_test', '/lifemate_ci'].includes(database.pathname) ||
  /^\/lifeguide_roles_source_[a-f0-9]{16}$/.test(database.pathname), 'Only synthetic test databases allowed');
const pool = new pg.Pool({ connectionString: fixtureUrl });
const users = [];
const password = `SyntheticNat-${crypto.randomUUID()}!`;
const secret = 'synthetic-nat-rate-limit-signing-secret-32-characters';
let child, base;

before(async () => {
  const hash = await argon2.hash(password, { type: argon2.argon2id });
  for (let index = 0; index < 3; index++) {
    const id = crypto.randomUUID(), email = `nat-${id}@example.test`;
    users.push({ id, email });
    await pool.query('insert into app_user(id,identity_subject,email_normalized,email_verified_at) values($1,$2,$3,now())', [id, `nat-fixture:${id}`, email]);
    await pool.query("insert into profile(user_id,display_name) values($1,'Synthetic NAT User')", [id]);
    await pool.query('insert into auth_credential(user_id,password_hash) values($1,$2)', [id, hash]);
  }
  // Use real wall time. Starting away from the fixed-window boundary avoids
  // a natural reset halfway through this bounded sequence, without a fake clock.
  const remaining = 60 - (Math.floor(Date.now() / 1000) % 60);
  if (remaining < 15) await new Promise(resolve => setTimeout(resolve, (remaining + 1) * 1000));
  const reservation = net.createServer().listen(0, '127.0.0.1');
  await once(reservation, 'listening'); const port = reservation.address().port;
  await new Promise(resolve => reservation.close(resolve));
  base = `http://127.0.0.1:${port}`;
  const env = { ...process.env, NODE_ENV: 'production', PORT: String(port), JWT_SECRET: secret,
    LOG_REQUESTS: 'false', TRUSTED_PROXY_CIDRS: '', CORS_ORIGINS: '', SMS_PROVIDER: 'disabled',
    SMS_PROVIDER_URL: '', SMS_PROVIDER_TOKEN: '', EMAIL_FROM: '', RESEND_API_KEY: '', SMTP_HOST: '',
    SMTP_USER: '', SMTP_PASSWORD: '', AI_API_KEY: '', AI_BASE_URL: '', AI_MODEL: '', OPENAI_API_KEY: '',
    ENABLE_SENSITIVE_FEATURES: 'false' };
  // Prove the shipping defaults even when the parent runner configures quotas.
  for (const key of Object.keys(env)) if (key.startsWith('RATE_LIMIT_')) delete env[key];
  delete env.TEST_FIXTURE_DATABASE_URL;
  child = spawn(process.execPath, ['src/entrypoint.js'], { cwd: new URL('../', import.meta.url), env,
    stdio: ['ignore', 'pipe', 'pipe'] });
  child.stderr.on('data', () => {});
  await new Promise((resolve, reject) => {
    let output = '';
    const timer = setTimeout(() => reject(new Error('NAT fixture startup timed out')), 10000);
    child.stdout.on('data', chunk => {
      output += chunk;
      if (output.includes('"type":"startup"')) { clearTimeout(timer); resolve(); }
    });
    child.once('error', () => { clearTimeout(timer); reject(new Error('NAT fixture process failed')); });
    child.once('exit', () => {
      if (!output.includes('"type":"startup"')) { clearTimeout(timer); reject(new Error('NAT fixture exited before startup')); }
    });
  });
});
after(async () => {
  if (child && child.exitCode === null && child.signalCode === null) {
    const closed = once(child, 'close'); child.kill('SIGTERM'); await closed;
  }
  try { await pool.query('delete from app_user where id=any($1::uuid[])', [users.map(user => user.id)]); }
  finally { await pool.end(); }
});
async function request(method, path, body, headers = {}) {
  const response = await fetch(base + path, { method,
    headers: { 'content-type': 'application/json', ...headers },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }) });
  const raw = await response.text();
  return { status: response.status, headers: response.headers,
    body: raw && response.headers.get('content-type')?.includes('application/json') ? JSON.parse(raw) : null };
}
const profile = user => request('GET', '/v1/profile', undefined, { authorization: `Bearer ${user.tokens.accessToken}` });
const digest = value => crypto.createHash('sha256').update(value).digest('hex');
function limited(response, limit, label) {
  assert.equal(response.status, 429, label);
  assert.equal(response.headers.get('RateLimit-Limit'), String(limit), label);
  assert.equal(response.headers.get('RateLimit-Remaining'), '0', label);
  const retry = Number(response.headers.get('Retry-After'));
  const windowSeconds = limit === 120 ? 60 : 600;
  assert.ok(Number.isInteger(retry) && retry > 0 && retry <= windowSeconds, `${label}: bounded real Retry-After`);
  const expectedRetry = windowSeconds - (Math.floor(Date.now() / 1000) % windowSeconds);
  assert.ok(Math.abs(retry - expectedRetry) <= 1, `${label}: actual default window expiry`);
  assert.equal(response.body?.error, 'rate_limited', label);
}

test('three users on one IP retain default strict login guards while capability discovery and rotating sessions have separate bounded budgets', async () => {
  const discoveryLimits = [];
  for (let index = 0; index < 12; index++) {
    const result = await request('GET', '/v1/auth/capabilities');
    assert.equal(result.status, 200, `Capability request ${index + 1} must not exhaust login`);
    discoveryLimits.push(result.headers.get('RateLimit-Limit'));
  }
  assert.ok(discoveryLimits.every(limit => limit === '120'), 'Discovery uses the bounded general quota');
  for (let index = 0; index < users.length; index++) {
    const user = users[index], login = await request('POST', '/v1/auth/login', { email: user.email, password });
    assert.equal(login.status, 200, `Independent user ${index + 1} can log in behind the same IP`);
    assert.equal(login.headers.get('RateLimit-Limit'), '10');
    user.tokens = login.body; user.initialTokens = login.body;
    const identity = jwt.verify(user.tokens.accessToken, secret, { audience: 'lifemate-api', issuer: 'lifemate' });
    assert.equal(identity.sub, user.id);
  }
  for (let index = 0; index < 7; index++) {
    const result = await request('POST', '/v1/auth/login', { email: users[index % 3].email, password: 'SyntheticInvalidPassword!' });
    assert.equal(result.status, 401); assert.equal(result.headers.get('RateLimit-Limit'), '10');
  }
  limited(await request('POST', '/v1/auth/login', { email: users[0].email, password }), 10, 'Strict auth request 11');
  const nearMatches = [
    ['HEAD', '/v1/auth/capabilities'], ['POST', '/v1/auth/capabilities'],
    ['GET', '/v1/auth/capabilities/'], ['GET', '/v1/auth/Capabilities'],
    ['GET', '/V1/AUTH/capabilities'], ['GET', '/v1/auth/refresh'],
    ['POST', '/v1/auth/refresh/'], ['POST', '/v1/auth/refreshing'],
    ['POST', '/v1/auth/logout/extra'], ['GET', '/v1/auth'],
  ];
  for (const [method, path] of nearMatches) {
    const result = await request(method, path);
    // HEAD deliberately has no response body.
    assert.equal(result.status, 429, `${method} ${path} remains strict`);
    assert.equal(result.headers.get('RateLimit-Limit'), '10');
    assert.ok(Number(result.headers.get('Retry-After')) > 0);
  }
  for (let index = 0; index < 3; index++) limited(await request('POST', '/v1/auth/login', {}, {
    'x-forwarded-for': `198.51.100.${index + 1}`, 'x-real-ip': `192.0.2.${index + 1}`,
    forwarded: `for=203.0.113.${index + 1}`,
  }), 10, 'Forged forwarding cannot acquire a new strict bucket');

  let sessionRequests = 0;
  async function session(path, body, headers) {
    const result = await request('POST', path, body, headers); sessionRequests++;
    assert.equal(result.headers.get('RateLimit-Limit'), '60');
    assert.equal(result.headers.get('RateLimit-Remaining'), String(Math.max(0, 60 - sessionRequests)));
    return result;
  }
  for (let index = 0; index < 12; index++) {
    const user = users[index % 3], previous = user.tokens, result = await session('/v1/auth/refresh', { refreshToken: previous.refreshToken });
    assert.equal(result.status, 200, `Refresh ${index + 1} succeeds after strict login bucket is exhausted`);
    assert.ok(result.body.refreshToken !== previous.refreshToken, 'Refresh proof must rotate');
    const oldIdentity = jwt.verify(previous.accessToken, secret, { audience: 'lifemate-api', issuer: 'lifemate' });
    assert.ok((await pool.query('select revoked_at from auth_session where id=$1 and user_id=$2', [oldIdentity.sid, user.id])).rows[0].revoked_at);
    user.tokens = result.body;
  }
  for (const user of users) {
    assert.equal((await profile(user)).status, 200);
    assert.equal((await request('GET', '/v1/profile', undefined, { authorization: `Bearer ${user.initialTokens.accessToken}` })).status, 401);
    const identity = jwt.verify(user.tokens.accessToken, secret, { audience: 'lifemate-api', issuer: 'lifemate' });
    const active = (await pool.query('select refresh_digest from auth_session where id=$1 and user_id=$2 and revoked_at is null and expires_at>now()', [identity.sid, user.id])).rows[0];
    assert.ok(active && active.refresh_digest === digest(user.tokens.refreshToken), 'Independent PostgreSQL confirms only hashed current refresh proof');
    assert.equal((await pool.query('select count(*)::int n from auth_session where user_id=$1 and revoked_at is null', [user.id])).rows[0].n, 1);
  }
  assert.equal((await session('/v1/auth/refresh', { refreshToken: users[0].initialTokens.refreshToken })).status, 401);
  assert.equal((await session('/v1/auth/logout', { refreshToken: users[0].tokens.refreshToken })).status, 204);
  assert.equal((await profile(users[0])).status, 401);
  for (const user of users.slice(1)) assert.equal((await profile(user)).status, 200, 'Another family account remains independently active');
  assert.equal((await session('/v1/auth/logout', {}, { authorization: `Bearer ${users[1].tokens.accessToken}` })).status, 204);
  assert.equal((await profile(users[1])).status, 401);
  const expiring = jwt.verify(users[2].tokens.accessToken, secret, { audience: 'lifemate-api', issuer: 'lifemate' });
  await pool.query("update auth_session set expires_at=statement_timestamp()-interval '1 second' where id=$1 and user_id=$2", [expiring.sid, users[2].id]);
  assert.equal((await profile(users[2])).status, 401);
  assert.equal((await session('/v1/auth/refresh', { refreshToken: users[2].tokens.refreshToken })).status, 401);
  assert.equal((await session('/v1/auth/logout', { refreshToken: users[2].tokens.refreshToken })).status, 204);
  while (sessionRequests < 60) assert.equal((await session('/v1/auth/logout', {})).status, 204);
  limited(await session('/v1/auth/refresh', { refreshToken: users[0].tokens.refreshToken }), 60, 'Session request 61');
  limited(await session('/v1/auth/logout', {}), 60, 'Logout shares the exhausted session bucket');

  let discovery = await request('GET', '/v1/auth/capabilities');
  assert.equal(discovery.status, 200, 'Strict and session exhaustion do not block discovery');
  const remaining = Number(discovery.headers.get('RateLimit-Remaining'));
  assert.ok(Number.isInteger(remaining) && remaining >= 0 && remaining < 120);
  for (let index = 0; index < remaining; index++) {
    discovery = await request('GET', '/v1/auth/capabilities'); assert.equal(discovery.status, 200);
  }
  assert.equal(discovery.headers.get('RateLimit-Remaining'), '0');
  limited(await request('GET', '/v1/auth/capabilities'), 120, 'Capabilities retain the bounded general budget');
});
