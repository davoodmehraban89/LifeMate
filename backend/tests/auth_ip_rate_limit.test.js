import test, { after } from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import net from 'node:net';
import pg from 'pg';
import { pruneExpiredAuthRateLimits } from '../src/auth_rate_limit.js';

const fixtureUrl = process.env.TEST_FIXTURE_DATABASE_URL ?? process.env.DATABASE_URL;
assert.ok(fixtureUrl, 'Auth IP tests require migrated synthetic PostgreSQL');
const database = new URL(fixtureUrl);
assert.ok(['localhost', '127.0.0.1', '[::1]', '::1'].includes(database.hostname), 'Only loopback PostgreSQL allowed');
assert.ok(['/lifeguide_library_test', '/lifeguide_contentops_test', '/lifemate_ci'].includes(database.pathname) ||
  /^\/lifeguide_roles_source_[a-f0-9]{16}$/.test(database.pathname), 'Only synthetic test databases allowed');
const pool = new pg.Pool({ connectionString: fixtureUrl });
const processes = new Set();
const secret = `synthetic-auth-ip-key-${crypto.randomUUID()}`;
const fixtureIps = new Set(['127.0.0.1']);

async function start({ trusted = '127.0.0.1/32', connectionString = fixtureUrl, quota = 3, sessionQuota = 5, windowSeconds = 600 } = {}) {
  const reservation = net.createServer().listen(0, '127.0.0.1');
  await once(reservation, 'listening');
  const port = reservation.address().port;
  await new Promise(resolve => reservation.close(resolve));
  const env = { ...process.env, DATABASE_URL: connectionString, NODE_ENV: 'production', PORT: String(port),
    JWT_SECRET: secret, LOG_REQUESTS: 'false', TRUSTED_PROXY_CIDRS: trusted, CORS_ORIGINS: '',
    RATE_LIMIT_AUTH_MAX: String(quota), RATE_LIMIT_AUTH_WINDOW_SECONDS: String(windowSeconds),
    RATE_LIMIT_SESSION_MAX: String(sessionQuota), RATE_LIMIT_SESSION_WINDOW_SECONDS: String(windowSeconds),
    RATE_LIMIT_GENERAL_MAX: '2000', SMS_PROVIDER: 'disabled', SMS_PROVIDER_URL: '', SMS_PROVIDER_TOKEN: '',
    KAVENEGAR_API_KEY: '', EMAIL_FROM: '', RESEND_API_KEY: '', SMTP_HOST: '', SMTP_USER: '', SMTP_PASSWORD: '',
    AI_API_KEY: '', AI_BASE_URL: '', AI_MODEL: '', OPENAI_API_KEY: '', ENABLE_SENSITIVE_FEATURES: 'false' };
  delete env.TEST_FIXTURE_DATABASE_URL;
  delete env.AUTH_RATE_LIMIT_KEY;
  const child = spawn(process.execPath, ['src/entrypoint.js'], { cwd: new URL('../', import.meta.url),
    env, stdio: ['ignore', 'pipe', 'pipe'] });
  processes.add(child);
  child.stderr.on('data', () => {});
  await new Promise((resolve, reject) => {
    let output = '';
    const timer = setTimeout(() => reject(new Error('Auth IP fixture startup timed out')), 10000);
    child.stdout.on('data', chunk => {
      output += chunk;
      if (output.includes('"type":"startup"')) { clearTimeout(timer); resolve(); }
    });
    child.once('error', () => { clearTimeout(timer); reject(new Error('Auth IP fixture process failed')); });
    child.once('exit', () => {
      if (!output.includes('"type":"startup"')) { clearTimeout(timer); reject(new Error('Auth IP fixture exited before startup')); }
    });
  });
  return { child, url: `http://127.0.0.1:${port}` };
}

async function stop(service) {
  const child = service.child;
  if (child.exitCode === null && child.signalCode === null) {
    const closed = once(child, 'close'); child.kill('SIGTERM'); await closed;
  }
  processes.delete(child);
}

async function request(service, path = '/v1/auth/login', { ip = '192.0.2.11', method = 'POST', headers = {} } = {}) {
  fixtureIps.add(ip);
  const response = await fetch(service.url + path, { method,
    headers: { 'content-type': 'application/json', 'x-forwarded-for': ip, ...headers },
    ...(['GET', 'HEAD', 'OPTIONS'].includes(method) ? {} : { body: '{}' }) });
  const raw = await response.text();
  return { status: response.status, headers: response.headers,
    body: raw && response.headers.get('content-type')?.includes('application/json') ? JSON.parse(raw) : null };
}

after(async () => {
  await Promise.all([...processes].map(child => stop({ child })));
  try {
    // These are test-owned HMACs only; never delete another test/API's bucket.
    const digests = [...fixtureIps].map(ip => crypto.createHmac('sha256', secret)
      .update('lifeguide:auth-ip:v1\0').update(ip).digest('hex'));
    await pool.query('delete from auth_ip_rate_limit where client_digest=any($1::text[])', [digests]);
  } catch (error) { if (error.code !== '42P01') throw error; }
  finally { await pool.end(); }
});

test('auth quota is shared atomically between API instances and survives process restart', async () => {
  const first = await start(), second = await start();
  // Syntactically valid forwarding data is accepted only from the explicitly
  // trusted loopback gateway. No real account/contact is involved.
  const results = await Promise.all(Array.from({ length: 8 }, (_, index) => request(index % 2 ? first : second)));
  assert.deepEqual(results.map(result => result.status).sort(), [401, 401, 401, 429, 429, 429, 429, 429],
    'Two processes must share one atomic quota, not each allow three requests');
  for (const result of results) assert.equal(result.headers.get('RateLimit-Limit'), '3');
  const limited = results.find(result => result.status === 429);
  assert.equal(limited.body.error, 'rate_limited');
  const retry = Number(limited.headers.get('Retry-After'));
  const clock = (await pool.query('select extract(epoch from statement_timestamp())::bigint n')).rows[0].n;
  const expected = 600 - (Number(clock) % 600);
  assert.ok(Number.isInteger(retry) && retry > 0 && retry <= 600 && Math.abs(retry - expected) <= 2);
  await stop(first); await stop(second);
  const restarted = await start();
  assert.equal((await request(restarted)).status, 429, 'Restart must not reset auth abuse protection');
  await stop(restarted);
});

test('strict and session budgets are separate, capability discovery and OPTIONS do not charge either', async () => {
  const service = await start({ quota: 2, sessionQuota: 2 });
  const options = { ip: '192.0.2.12' };
  for (let index = 0; index < 4; index++) {
    assert.equal((await request(service, '/v1/auth/capabilities', { ...options, method: 'GET' })).status, 200);
    assert.equal((await request(service, '/v1/auth/login', { ...options, method: 'OPTIONS' })).status, 204);
  }
  assert.equal((await request(service, '/v1/auth/login', options)).status, 401);
  assert.equal((await request(service, '/v1/auth/login', options)).status, 401);
  assert.equal((await request(service, '/v1/auth/login', options)).status, 429);
  assert.equal((await request(service, '/v1/auth/logout', options)).status, 204);
  assert.equal((await request(service, '/v1/auth/logout', options)).status, 204);
  assert.equal((await request(service, '/v1/auth/refresh', options)).status, 429);
  for (const [method, path] of [
    ['HEAD', '/v1/auth/capabilities'], ['POST', '/v1/auth/capabilities'],
    ['GET', '/v1/auth/capabilities/'], ['GET', '/v1/auth/Capabilities'],
    ['GET', '/V1/AUTH/capabilities'], ['POST', '/v1/auth/refresh/'], ['POST', '/v1/auth/refreshing'],
  ]) assert.equal((await request(service, path, { ...options, method })).status, 429, `${method} ${path} stays strict`);
  await stop(service);
});

test('untrusted forwarding headers cannot rotate a quota, and an explicitly pinned gateway separates clients', async () => {
  const standalone = await start({ trusted: '', quota: 2 });
  assert.equal((await request(standalone, '/v1/auth/login', { ip: '198.51.100.1' })).status, 401);
  assert.equal((await request(standalone, '/v1/auth/login', { ip: '198.51.100.2' })).status, 401);
  assert.equal((await request(standalone, '/v1/auth/login', { ip: '198.51.100.3', headers: {
    forwarded: 'for=203.0.113.123', 'x-real-ip': '203.0.113.123',
  } })).status, 429);
  await stop(standalone);
  const gateway = await start({ quota: 2 });
  assert.equal((await request(gateway, '/v1/auth/login', { ip: '192.0.2.13' })).status, 401);
  assert.equal((await request(gateway, '/v1/auth/login', { ip: '192.0.2.13' })).status, 401);
  assert.equal((await request(gateway, '/v1/auth/login', { ip: '203.0.113.123, 192.0.2.13' })).status, 429);
  assert.equal((await request(gateway, '/v1/auth/login', { ip: '192.0.2.14' })).status, 401);
  await stop(gateway);
});

test('database failure closes auth with generic 503 while public discovery remains available', async () => {
  const schema = `synthetic_auth_unavailable_${crypto.randomBytes(6).toString('hex')}`;
  await pool.query(`create schema ${schema}`);
  try {
    const isolated = new URL(fixtureUrl);
    isolated.searchParams.set('options', `-c search_path=${schema}`);
    const service = await start({ connectionString: isolated.href });
    const result = await request(service, '/v1/auth/login', { ip: '192.0.2.15' });
    assert.equal(result.status, 503);
    assert.deepEqual(result.body, { error: 'temporarily_unavailable' });
    assert.equal(result.headers.get('Retry-After'), '5');
    assert.equal((await request(service, '/v1/auth/capabilities', { method: 'GET' })).status, 200);
    assert.equal((await request(service, '/live', { method: 'GET' })).status, 200);
    await stop(service);
  } finally { await pool.query(`drop schema ${schema}`); }
});

test('persisted buckets contain only HMAC metadata and the server-clock window expires', async () => {
  const service = await start({ quota: 1, windowSeconds: 5 });
  const options = { ip: '192.0.2.16' };
  // Align against the actual PostgreSQL clock, not an injected fake clock.
  // Keep both immediate calls away from a natural fixed-window rollover.
  for (;;) {
    const now = Number((await pool.query('select extract(epoch from clock_timestamp()) n')).rows[0].n);
    if (now % 5 < 1) break;
    await new Promise(resolve => setTimeout(resolve, 100));
  }
  assert.equal((await request(service, '/v1/auth/window-probe', options)).status, 401);
  assert.equal((await request(service, '/v1/auth/window-probe', options)).status, 429);
  const columns = (await pool.query(`select column_name from information_schema.columns
    where table_schema=current_schema() and table_name='auth_ip_rate_limit' order by ordinal_position`)).rows.map(row => row.column_name);
  assert.deepEqual(columns, ['quota_profile', 'client_digest', 'window_start', 'window_end', 'request_count']);
  const rows = (await pool.query("select * from auth_ip_rate_limit where window_end-window_start=interval '5 seconds'")).rows;
  assert.ok(rows.length > 0);
  for (const row of rows) {
    assert.match(row.client_digest, /^[a-f0-9]{64}$/);
    assert.equal(JSON.stringify(row).includes(options.ip), false);
  }
  await new Promise(resolve => setTimeout(resolve, 5100));
  assert.equal((await request(service, '/v1/auth/window-probe', options)).status, 401, 'New server-clock window receives a new quota');
  await stop(service);
});

test('a request waiting for the shared lock samples its quota window after the wait', async () => {
  const ip = '192.0.2.17', options = { ip };
  // One second guarantees this controlled wait stays below the production
  // two-second lock timeout, even when the request starts near a boundary.
  const service = await start({ quota: 1, windowSeconds: 1 });
  const digest = crypto.createHmac('sha256', secret).update('lifeguide:auth-ip:v1\0').update(ip).digest('hex');
  assert.equal((await request(service, '/v1/auth/window-probe', options)).status, 401);
  const client = await pool.connect();
  let pending;
  try {
    await client.query('begin');
    const pid = Number((await client.query('select pg_backend_pid() pid')).rows[0].pid);
    await client.query("select pg_advisory_xact_lock(hashtextextended('lifeguide:auth-ip:auth:' || $1,0))", [digest]);
    pending = request(service, '/v1/auth/window-probe', options);
    let blocked = false;
    for (let index = 0; index < 100; index++) {
      blocked = (await pool.query('select exists(select 1 from pg_stat_activity where $1=any(pg_blocking_pids(pid))) blocked', [pid])).rows[0].blocked;
      if (blocked) break;
      await new Promise(resolve => setTimeout(resolve, 10));
    }
    assert.ok(blocked, 'Independent PostgreSQL confirms the API is waiting on the shared quota lock');
    const waitMs = Number((await pool.query(`select greatest(0,extract(epoch from max(window_end)-clock_timestamp())*1000)::integer ms
      from auth_ip_rate_limit where quota_profile='auth' and client_digest=$1`, [digest])).rows[0].ms);
    await new Promise(resolve => setTimeout(resolve, waitMs + 100));
    await client.query('commit');
    assert.equal((await pending).status, 401, 'Expired pre-wait window must not reject a new-window request');
    const windows = (await pool.query('select request_count from auth_ip_rate_limit where client_digest=$1 order by window_start', [digest])).rows;
    assert.equal(windows.length, 2);
    assert.ok(windows.every(row => Number(row.request_count) === 1));
  } finally {
    await client.query('rollback').catch(() => {});
    client.release();
    if (pending) await pending;
    await stop(service);
  }
});

test('explicit housekeeping is bounded and retains active quotas', async () => {
  const schema = `synthetic_auth_cleanup_${crypto.randomBytes(6).toString('hex')}`;
  await pool.query(`create schema ${schema}`);
  await pool.query(`create table ${schema}.auth_ip_rate_limit (like auth_ip_rate_limit including all)`);
  const isolated = new URL(fixtureUrl);
  isolated.searchParams.set('options', `-c search_path=${schema}`);
  const cleanupPool = new pg.Pool({ connectionString: isolated.href });
  try {
    await cleanupPool.query(`insert into auth_ip_rate_limit values
      ('auth',$1,now()-interval '2 hours',now()-interval '1 hour',1),
      ('session',$1,now()-interval '2 hours',now()-interval '1 hour',1),
      ('auth',$1,now(),now()+interval '1 hour',1)`, ['a'.repeat(64)]);
    assert.equal(await pruneExpiredAuthRateLimits(cleanupPool, 1), 1);
    assert.equal(Number((await cleanupPool.query('select count(*) n from auth_ip_rate_limit')).rows[0].n), 2);
    assert.equal(await pruneExpiredAuthRateLimits(cleanupPool, 1), 1);
    assert.equal(await pruneExpiredAuthRateLimits(cleanupPool, 1), 0);
    const remaining = (await cleanupPool.query('select window_end>statement_timestamp() active from auth_ip_rate_limit')).rows;
    assert.deepEqual(remaining, [{ active: true }]);
    await assert.rejects(pruneExpiredAuthRateLimits(cleanupPool, 501), /Invalid auth limiter cleanup batch/);
    await assert.rejects(pruneExpiredAuthRateLimits(cleanupPool, 0), /Invalid auth limiter cleanup batch/);
  } finally {
    await cleanupPool.end();
    await pool.query(`drop schema ${schema} cascade`);
  }
});
