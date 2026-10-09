import test, { after, before } from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import net from 'node:net';
import pg from 'pg';
import express from 'express';
import argon2 from 'argon2';
import jwt from 'jsonwebtoken';
import { createAuthRouter } from '../src/auth_router.js';
import { createSessionAuth } from '../src/session_auth.js';
import { SmsProvider, createEmailProvider, safelyDeliver } from '../src/auth_delivery.js';
import { operationalErrorHandler } from '../src/operations.js';

assert.ok(process.env.DATABASE_URL, 'Auth delivery tests require a migrated synthetic PostgreSQL database');
assert.ok(process.env.JWT_SECRET?.length >= 32, 'Auth delivery tests require a synthetic JWT secret');
const suffix = crypto.randomUUID();
const applicationName = `auth-fixture-${suffix}`;
const pool = new pg.Pool({ connectionString: process.env.DATABASE_URL, application_name: applicationName });
const email = `delivery-${suffix}@example.test`;
let child;
let base;
let output = '';
let errors = '';
let smtp;
let providerServer;
let providerBase;
const mail = [];
const smsMessages = [];
const recipients = new Set([email]);
const userIds = new Set();
const familyIds = new Set();
const challengeIds = new Set();
const jwtSecret = process.env.JWT_SECRET;
const recipientDigest = (recipient) => crypto.createHmac('sha256', jwtSecret).update(`delivery:${recipient}`).digest('hex');
const tokenDigest = (token) => crypto.createHash('sha256').update(token).digest('hex');
const password = 'SyntheticPass123!';
const replacement = 'ReplacementSynthetic123!';

// Only the external delivery ports are fixtures: HTTP, identity, hashes and DB are real.
class CapturingSmsProvider extends SmsProvider {
  configured = true;
  status = 'TEST_ONLY';
  async sendOtp(message) { smsMessages.push(message); return { delivered: true }; }
}

before(async () => {
  // A rejecting local SMTP fixture: no message or credential is transmitted.
  smtp = net.createServer((socket) => socket.end('421 synthetic service unavailable\r\n'));
  smtp.listen(0, '127.0.0.1');
  await once(smtp, 'listening');
  const reservation = net.createServer();
  reservation.listen(0, '127.0.0.1');
  await once(reservation, 'listening');
  const port = reservation.address().port;
  await new Promise((resolve) => reservation.close(resolve));
  base = `http://127.0.0.1:${port}`;
  child = spawn(process.execPath, ['src/entrypoint.js'], {
    env: {
      ...process.env, NODE_ENV: 'production', PORT: String(port),
      SMS_PROVIDER: 'disabled', SMS_PROVIDER_URL: '', SMS_PROVIDER_TOKEN: '',
      EMAIL_FROM: 'LifeGuide Test <fixture@example.test>',
      SMTP_HOST: '127.0.0.1', SMTP_PORT: String(smtp.address().port),
      SMTP_SECURE: 'false', SMTP_USER: '', SMTP_PASSWORD: '', RESEND_API_KEY: '',
      PUBLIC_APP_URL: 'https://app.example.test', CORS_ORIGINS: '',
      RATE_LIMIT_AUTH_MAX: '2000', RATE_LIMIT_GENERAL_MAX: '2000',
    },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  child.stdout.on('data', (chunk) => { output += chunk.toString(); });
  child.stderr.on('data', (chunk) => { errors += chunk.toString(); });
  await new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('Auth fixture startup timed out')), 10000);
    const onData = () => {
      if (!output.includes('"type":"startup"')) return;
      clearTimeout(timer);
      child.stdout.off('data', onData);
      resolve();
    };
    child.stdout.on('data', onData);
    child.once('error', (error) => { clearTimeout(timer); reject(error); });
  });
  const fixtureApp = express();
  fixtureApp.use(express.json({ limit: '64kb' }));
  fixtureApp.use('/v1/auth', createAuthRouter({
    pool, jwtSecret, auth: createSessionAuth({ pool, jwtSecret }),
    env: { NODE_ENV: 'production', PUBLIC_APP_URL: 'https://app.example.test' },
    emailProvider: { configured: true, status: 'TEST_ONLY', async send(message) { mail.push(message); return { delivered: true }; } },
    smsProvider: new CapturingSmsProvider(),
  }));
  fixtureApp.use(operationalErrorHandler);
  providerServer = fixtureApp.listen(0, '127.0.0.1');
  await once(providerServer, 'listening');
  providerBase = `http://127.0.0.1:${providerServer.address().port}`;
});

after(async () => {
  if (child && child.exitCode === null && child.signalCode === null) {
    const closed = once(child, 'close');
    child.kill('SIGTERM');
    await closed;
  }
  if (smtp) await new Promise((resolve) => smtp.close(resolve));
  if (providerServer) await new Promise((resolve) => providerServer.close(resolve));
  await pool.query('delete from access_audit where actor_user_id=any($1::uuid[]) or family_id=any($2::uuid[])', [[...userIds], [...familyIds]]);
  await pool.query('delete from family_workspace where id=any($1::uuid[])', [[...familyIds]]);
  await pool.query('delete from auth_phone_challenge where id=any($1::uuid[])', [[...challengeIds]]);
  await pool.query('delete from auth_delivery_attempt where recipient_digest=any($1::text[])', [[...recipients].map(recipientDigest)]);
  await pool.query('delete from app_user where id=any($1::uuid[]) or email_normalized=$2', [[...userIds], email]);
  await pool.end();
});

async function request(path, body, { method = 'POST', token, origin = base } = {}) {
  const response = await fetch(origin + path, {
    method,
    headers: { 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}) },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await response.text();
  return { status: response.status, body: text ? JSON.parse(text) : null, headers: response.headers };
}

const providerRequest = (path, body, options = {}) => request(path, body, { ...options, origin: providerBase });
async function until(check) {
  for (let i = 0; i < 100; i++) {
    const value = await check();
    if (value) return value;
    await new Promise((resolve) => setTimeout(resolve, 20));
  }
  assert.fail('Synthetic delivery fixture did not complete');
}
async function identify(contact) {
  const row = await pool.query('select id from app_user where email_normalized=$1 or phone_normalized=$1', [contact]);
  assert.equal(row.rowCount, 1);
  userIds.add(row.rows[0].id);
  return row.rows[0].id;
}
async function resetCooldown(contact, purpose) {
  await pool.query("update auth_delivery_attempt set requested_at=now()-interval '2 hours' where recipient_digest=$1 and purpose=$2", [recipientDigest(contact), purpose]);
}
function freshEmail() { const value = `auth-${crypto.randomUUID()}@example.test`; recipients.add(value); return value; }
function freshPhone() { const value = `+1555${crypto.randomInt(100000000, 999999999)}`; recipients.add(value); return value; }
async function emailAccount() {
  const contact = freshEmail();
  assert.equal((await providerRequest('/v1/auth/register', { email: contact, displayName: 'Synthetic Email', password })).status, 202);
  const id = await identify(contact);
  const message = await until(() => mail.find((item) => item.to === contact));
  const token = new URL(message.text.match(/https:\/\/\S+/)[0]).searchParams.get('token');
  return { contact, id, token };
}
async function otp(contact, purpose = 'verify') {
  await resetCooldown(contact, 'phone_otp');
  const previous = smsMessages.length;
  const response = await providerRequest('/v1/auth/phone/request-otp', { phone: contact, purpose });
  assert.equal(response.status, 202);
  challengeIds.add(response.body.challengeId);
  assert.equal(response.body.expiresIn, 300);
  assert.equal(Object.hasOwn(response.body, 'code'), false);
  const message = await until(() => smsMessages.slice(previous).find((item) => item.phone === contact));
  return { challengeId: response.body.challengeId, code: message.code };
}
async function phoneAccount() {
  const contact = freshPhone();
  const registered = await providerRequest('/v1/auth/register', { phone: contact, displayName: 'Synthetic Phone', password });
  assert.equal(registered.status, 202);
  assert.deepEqual(registered.body, { accepted: true });
  return { contact, id: await identify(contact) };
}
async function familyFixture() {
  const parent = await emailAccount();
  assert.equal((await providerRequest('/v1/auth/verify-email', { token: parent.token, newPassword: password })).status, 204);
  const login = await request('/v1/auth/login', { email: parent.contact, password });
  assert.equal(login.status, 200);
  const child = await phoneAccount();
  const proof = await otp(child.contact);
  const verified = await providerRequest('/v1/auth/phone/verify-otp', { ...proof, newPassword: password });
  assert.equal(verified.status, 200);
  const family = await request('/v1/families', { name: 'Synthetic Management Family', role: 'parent_guardian' }, { token: login.body.accessToken });
  assert.equal(family.status, 201);
  familyIds.add(family.body.id);
  return { parent: { ...parent, accessToken: login.body.accessToken }, child: { ...child, accessToken: verified.body.accessToken }, familyId: family.body.id };
}
async function phoneInvitation(fixture, role = 'teen_minor') {
  const invitation = await request(`/v1/families/${fixture.familyId}/invitations`, { phone: fixture.child.contact, role }, { token: fixture.parent.accessToken });
  assert.equal(invitation.status, 201);
  return invitation.body;
}

test('registration remains recoverable and generic when email delivery fails after commit', async () => {
  const body = { email, displayName: 'Synthetic User', password: 'SyntheticPass123!' };
  const created = await request('/v1/auth/register', body);
  assert.equal(created.status, 202);
  assert.deepEqual(created.body, { accepted: true });
  const row = await pool.query('select u.id,c.password_hash from app_user u join auth_credential c on c.user_id=u.id where u.email_normalized=$1', [email]);
  assert.equal(row.rowCount, 1);
  assert.equal(row.rows[0].password_hash.startsWith('$argon2id$'), true);
  userIds.add(row.rows[0].id);
  await until(async () => (await pool.query("select 1 from auth_delivery_attempt where user_id=$1 and purpose='email_verification' and status='failed'", [row.rows[0].id])).rowCount);
  const duplicate = await request('/v1/auth/register', { ...body, displayName: 'Must Not Replace', password: 'OtherSyntheticPass123!' });
  assert.equal(duplicate.status, 202);
  assert.deepEqual(duplicate.body, created.body);
  assert.equal((await pool.query('select display_name from profile where user_id=$1', [row.rows[0].id])).rows[0].display_name, 'Synthetic User');
  assert.equal((await pool.query('select password_hash=$2 as unchanged from auth_credential where user_id=$1', [row.rows[0].id, row.rows[0].password_hash])).rows[0].unchanged, true);
});

test('forgot-password delivery failure keeps the generic response and stored recovery token', async () => {
  const known = await request('/v1/auth/forgot-password', { email });
  const unknown = await request('/v1/auth/forgot-password', { email: `missing-${suffix}@example.test` });
  recipients.add(`missing-${suffix}@example.test`);
  assert.equal(known.status, 200);
  assert.equal(unknown.status, 200);
  assert.deepEqual(known.body, { accepted: true });
  assert.deepEqual(unknown.body, known.body);
  assert.equal((await pool.query("select count(*)::int as n from auth_token t join app_user u on u.id=t.user_id where u.email_normalized=$1 and t.kind='password_reset'", [email])).rows[0].n, 1);
  assert.equal(errors.includes(email), false);
  assert.equal(errors.includes('SyntheticPass123!'), false);
});

test('unconfigured SMS returns the same recoverable failure before account creation or lookup', async () => {
  const contact = freshPhone();
  const caps = await request('/v1/auth/capabilities', undefined, { method: 'GET' });
  assert.equal(caps.status, 200);
  assert.equal(caps.body.smsAvailable, false);
  assert.equal(caps.body.smsStatus, 'UNVERIFIED');
  const rejected = await request('/v1/auth/register', { phone: contact, displayName: 'Synthetic Phone', password });
  assert.equal(rejected.status, 503);
  assert.deepEqual(rejected.body, { error: 'sms_unavailable' });
  assert.equal((await pool.query('select 1 from app_user where phone_normalized=$1', [contact])).rowCount, 0);
  const created = await phoneAccount();
  const known = await request('/v1/auth/phone/request-otp', { phone: created.contact });
  const unknown = await request('/v1/auth/phone/request-otp', { phone: contact });
  assert.equal(known.status, 503);
  assert.equal(unknown.status, known.status);
  assert.deepEqual(unknown.body, known.body);
  assert.equal((await pool.query('select 1 from auth_phone_challenge where user_id=$1', [created.id])).rowCount, 0);
});

test('resend verification is generic, rate limited for known and unknown contacts, and recoverable after provider failure', async () => {
  const unknown = freshEmail();
  await resetCooldown(email, 'email_verification');
  const known = await request('/v1/auth/resend-verification', { email });
  const absent = await request('/v1/auth/resend-verification', { email: unknown });
  assert.equal(known.status, 202);
  assert.equal(absent.status, 202);
  assert.deepEqual(known.body, absent.body);
  for (const contact of [email, unknown]) {
    const blocked = await request('/v1/auth/resend-verification', { email: contact });
    assert.equal(blocked.status, 429);
    assert.equal(Number(blocked.headers.get('Retry-After')) > 0, true);
    await pool.query("update auth_delivery_attempt set requested_at=now()-interval '61 seconds' where recipient_digest=$1 and purpose='email_verification' and requested_at>now()-interval '1 hour'", [recipientDigest(contact)]);
    assert.equal((await request('/v1/auth/resend-verification', { email: contact })).status, 202);
    await pool.query("update auth_delivery_attempt set requested_at=now()-interval '61 seconds' where recipient_digest=$1 and purpose='email_verification' and requested_at>now()-interval '1 hour'", [recipientDigest(contact)]);
    assert.equal((await request('/v1/auth/resend-verification', { email: contact })).status, 202);
    const hourlyLimit = await request('/v1/auth/resend-verification', { email: contact });
    assert.equal(hourlyLimit.status, 429);
    assert.equal(Number(hourlyLimit.headers.get('Retry-After')) > 60, true);
  }
  const stored = await pool.query("select count(*)::int as n from auth_token t join app_user u on u.id=t.user_id where u.email_normalized=$1 and t.kind='email_verification'", [email]);
  assert.equal(stored.rows[0].n >= 4, true);
});

test('email verification and reset tokens are hashed, expire and can be consumed only once', async () => {
  const account = await emailAccount();
  const stored = (await pool.query('select token_digest from auth_token where user_id=$1', [account.id])).rows[0].token_digest;
  assert.equal(stored === tokenDigest(account.token), true);
  assert.equal(stored === account.token, false);
  await pool.query("update auth_token set created_at=now()-interval '2 days',expires_at=now()-interval '1 day' where user_id=$1", [account.id]);
  assert.equal((await providerRequest('/v1/auth/verify-email', { token: account.token, newPassword: password })).status, 400);
  await resetCooldown(account.contact, 'email_verification');
  const previous = mail.length;
  assert.equal((await providerRequest('/v1/auth/resend-verification', { email: account.contact })).status, 202);
  const verification = await until(() => mail.slice(previous).find((item) => item.to === account.contact));
  const token = new URL(verification.text.match(/https:\/\/\S+/)[0]).searchParams.get('token');
  assert.equal((await providerRequest('/v1/auth/verify-email', { token, newPassword: password })).status, 204);
  assert.equal((await providerRequest('/v1/auth/verify-email', { token, newPassword: password })).status, 400);
  const login = await providerRequest('/v1/auth/login', { identifier: account.contact, password });
  assert.equal(login.status, 200);
  const before = mail.length;
  assert.equal((await providerRequest('/v1/auth/forgot-password', { email: account.contact })).status, 200);
  const resetMessage = await until(() => mail.slice(before).find((item) => item.to === account.contact));
  const expiredReset = new URL(resetMessage.text.match(/https:\/\/\S+/)[0]).searchParams.get('token');
  await pool.query("update auth_token set created_at=now()-interval '1 hour',expires_at=now()-interval '30 minutes' where token_digest=$1", [tokenDigest(expiredReset)]);
  assert.equal((await providerRequest('/v1/auth/reset-password', { token: expiredReset, newPassword: replacement })).status, 400);
  await resetCooldown(account.contact, 'password_reset');
  const resendStart = mail.length;
  assert.equal((await providerRequest('/v1/auth/forgot-password', { email: account.contact })).status, 200);
  const resentReset = await until(() => mail.slice(resendStart).find((item) => item.to === account.contact));
  const reset = new URL(resentReset.text.match(/https:\/\/\S+/)[0]).searchParams.get('token');
  assert.equal((await providerRequest('/v1/auth/reset-password', { token: reset, newPassword: replacement })).status, 204);
  assert.equal((await providerRequest('/v1/auth/reset-password', { token: reset, newPassword: password })).status, 400);
  assert.equal((await providerRequest('/v1/auth/refresh', { refreshToken: login.body.refreshToken })).status, 401);
  assert.equal((await providerRequest('/v1/auth/login', { email: account.contact, password })).status, 401);
  assert.equal((await providerRequest('/v1/auth/login', { email: account.contact, password: replacement })).status, 200);
});

test('phone-only ownership proof replaces pending credentials; OTP is hashed and single-use', async () => {
  const account = await phoneAccount();
  assert.equal((await providerRequest('/v1/auth/login', { phone: account.contact, password })).status, 403);
  const proof = await otp(account.contact);
  const stored = (await pool.query('select code_digest,expires_at-created_at as ttl from auth_phone_challenge where id=$1', [proof.challengeId])).rows[0];
  assert.equal(stored.code_digest.length, 64);
  assert.equal(stored.code_digest === crypto.createHmac('sha256', jwtSecret).update(`otp:${proof.challengeId}:${proof.code}`).digest('hex'), true);
  assert.equal(stored.code_digest === proof.code, false);
  assert.equal(stored.ttl.minutes, 5);
  assert.equal((await providerRequest('/v1/auth/phone/verify-otp', proof)).status, 400);
  assert.equal((await pool.query('select phone_verified_at from app_user where id=$1', [account.id])).rows[0].phone_verified_at, null);
  const verified = await providerRequest('/v1/auth/phone/verify-otp', { ...proof, newPassword: replacement });
  assert.equal(verified.status, 200);
  assert.ok(verified.body.refreshToken);
  assert.equal((await pool.query('select email_normalized,phone_verified_at from app_user where id=$1', [account.id])).rows[0].email_normalized, null);
  assert.equal((await providerRequest('/v1/auth/phone/verify-otp', { ...proof, newPassword: password })).status, 401);
  assert.equal((await providerRequest('/v1/auth/login', { identifier: account.contact, password })).status, 401);
  assert.equal((await providerRequest('/v1/auth/login', { identifier: account.contact, password: replacement })).status, 200);
});

test('phone OTP expiry, bounded guessing, unknown accounts and recovery enforce server policy', async () => {
  const account = await phoneAccount();
  const initial = await otp(account.contact);
  assert.equal((await providerRequest('/v1/auth/phone/verify-otp', { ...initial, newPassword: replacement })).status, 200);
  const authenticated = await providerRequest('/v1/auth/login', { phone: account.contact, password: replacement });
  const expired = await otp(account.contact, 'login');
  await pool.query("update auth_phone_challenge set created_at=now()-interval '10 minutes',expires_at=now()-interval '5 minutes' where id=$1", [expired.challengeId]);
  assert.equal((await providerRequest('/v1/auth/phone/verify-otp', expired)).status, 401);
  const bounded = await otp(account.contact, 'login');
  const wrong = bounded.code === '000000' ? '000001' : '000000';
  for (let i = 0; i < 5; i++) assert.equal((await providerRequest('/v1/auth/phone/verify-otp', { ...bounded, code: wrong })).status, 401);
  assert.equal((await providerRequest('/v1/auth/phone/verify-otp', bounded)).status, 401);
  assert.equal((await pool.query('select attempts from auth_phone_challenge where id=$1', [bounded.challengeId])).rows[0].attempts, 5);
  const missing = freshPhone();
  const before = smsMessages.length;
  const absent = await providerRequest('/v1/auth/phone/request-otp', { phone: missing, purpose: 'recovery' });
  assert.equal(absent.status, 202);
  challengeIds.add(absent.body.challengeId);
  assert.equal(smsMessages.length, before);
  assert.equal((await providerRequest('/v1/auth/phone/verify-otp', { challengeId: absent.body.challengeId, code: '000000', newPassword: password })).status, 401);
  const recovery = await otp(account.contact, 'recovery');
  const recovered = await providerRequest('/v1/auth/phone/verify-otp', { ...recovery, newPassword: password });
  assert.equal(recovered.status, 200);
  assert.equal((await providerRequest('/v1/auth/refresh', { refreshToken: authenticated.body.refreshToken })).status, 401);
  assert.equal((await providerRequest('/v1/auth/login', { phone: account.contact, password: replacement })).status, 401);
  assert.equal((await providerRequest('/v1/auth/login', { phone: account.contact, password })).status, 200);
  const disabledProof = await otp(account.contact, 'login');
  await pool.query('update app_user set disabled_at=now() where id=$1', [account.id]);
  assert.equal((await providerRequest('/v1/auth/phone/verify-otp', disabledProof)).status, 401);
  assert.equal((await providerRequest('/v1/auth/refresh', { refreshToken: recovered.body.refreshToken })).status, 401);
});

test('two phone challenges and competing refresh requests serialize without token reuse or deadlock', async () => {
  const account = await phoneAccount();
  const first = await otp(account.contact);
  const second = await otp(account.contact);
  const verified = await Promise.all([first, second].map((proof) => providerRequest('/v1/auth/phone/verify-otp', { ...proof, newPassword: password })));
  assert.deepEqual(verified.map((response) => response.status).sort(), [200, 401]);
  const tokens = verified.find((response) => response.status === 200).body;
  const refreshed = await Promise.all([1, 2].map(() => providerRequest('/v1/auth/refresh', { refreshToken: tokens.refreshToken })));
  assert.deepEqual(refreshed.map((response) => response.status).sort(), [200, 401]);
  const active = refreshed.find((response) => response.status === 200).body;
  assert.equal((await pool.query('select count(*)::int as n from auth_session where user_id=$1 and revoked_at is null', [account.id])).rows[0].n, 1);
  assert.equal((await request('/v1/profile', undefined, { method: 'GET', token: tokens.accessToken })).status, 401);
  assert.equal((await request('/v1/profile', undefined, { method: 'GET', token: active.accessToken })).status, 200);
  assert.equal((await providerRequest('/v1/auth/logout', { refreshToken: active.refreshToken })).status, 204);
  assert.equal((await providerRequest('/v1/auth/logout', { refreshToken: 'invalid-synthetic-proof' })).status, 204);
  assert.equal((await providerRequest('/v1/auth/refresh', { refreshToken: active.refreshToken })).status, 401);
});

test('refresh expiry and logout with expired access proof preserve opaque refresh revocation', async () => {
  const account = await phoneAccount();
  const proof = await otp(account.contact);
  const verified = await providerRequest('/v1/auth/phone/verify-otp', { ...proof, newPassword: password });
  assert.equal(verified.status, 200);
  const identity = jwt.verify(verified.body.accessToken, jwtSecret, { audience: 'lifemate-api', issuer: 'lifemate' });
  assert.equal(identity.exp - identity.iat, 900);
  await pool.query("update auth_session set created_at=now()-interval '31 days',expires_at=now()-interval '1 day' where id=$1", [identity.sid]);
  assert.equal((await providerRequest('/v1/auth/refresh', { refreshToken: verified.body.refreshToken })).status, 401);
  const login = await providerRequest('/v1/auth/login', { phone: account.contact, password });
  assert.equal(login.status, 200);
  const active = jwt.verify(login.body.accessToken, jwtSecret, { audience: 'lifemate-api', issuer: 'lifemate' });
  const expiredAccess = jwt.sign({ sub: active.sub, sid: active.sid, aud: 'lifemate-api' }, jwtSecret, { issuer: 'lifemate', expiresIn: -1 });
  assert.equal((await request('/v1/profile', undefined, { method: 'GET', token: expiredAccess })).status, 401);
  assert.equal((await request('/v1/auth/logout', { refreshToken: login.body.refreshToken }, { token: expiredAccess })).status, 204);
  assert.equal((await pool.query('select revoked_at from auth_session where id=$1', [active.sid])).rows[0].revoked_at instanceof Date, true);
  assert.equal((await providerRequest('/v1/auth/refresh', { refreshToken: login.body.refreshToken })).status, 401);
});

test('phone-only family invites require the matching verified contact and keep the inviter-selected role', async () => {
  const parent = await emailAccount();
  assert.equal((await providerRequest('/v1/auth/verify-email', { token: parent.token, newPassword: password })).status, 204);
  const parentLogin = await request('/v1/auth/login', { email: parent.contact, password });
  assert.equal(parentLogin.status, 200);
  const phone = await phoneAccount();
  const proof = await otp(phone.contact);
  const verified = await providerRequest('/v1/auth/phone/verify-otp', { ...proof, newPassword: password });
  assert.equal(verified.status, 200);
  const family = await request('/v1/families', { name: 'Synthetic Phone Family', role: 'parent_guardian' }, { token: parentLogin.body.accessToken });
  assert.equal(family.status, 201);
  familyIds.add(family.body.id);
  const invitation = await request(`/v1/families/${family.body.id}/invitations`, { phone: phone.contact, role: 'teen_minor' }, { token: parentLogin.body.accessToken });
  assert.equal(invitation.status, 201);
  assert.ok(invitation.body.invitationToken);
  assert.equal(invitation.body.invitationLink.startsWith('https://app.example.test/'), true);
  const stored = (await pool.query('select invited_email_normalized,invited_phone_normalized,token_digest from family_invitation where id=$1', [invitation.body.id])).rows[0];
  assert.equal(stored.invited_email_normalized, null);
  assert.equal(stored.invited_phone_normalized, phone.contact);
  assert.equal(stored.token_digest === tokenDigest(invitation.body.invitationToken), true);
  assert.equal((await request('/v1/invitations/accept', { token: invitation.body.invitationToken }, { token: parentLogin.body.accessToken })).status, 403);
  // Existing session remains active when the fixture removes the verification timestamp.
  await pool.query('update app_user set phone_verified_at=null where id=$1', [phone.id]);
  assert.equal((await request('/v1/invitations/accept', { token: invitation.body.invitationToken }, { token: verified.body.accessToken })).status, 403);
  await pool.query('update app_user set phone_verified_at=now() where id=$1', [phone.id]);
  assert.equal((await request('/v1/invitations/accept', { token: invitation.body.invitationToken, role: 'parent_guardian' }, { token: verified.body.accessToken })).status, 204);
  const member = (await pool.query('select role,is_admin from family_membership where family_id=$1 and user_id=$2', [family.body.id, phone.id])).rows[0];
  assert.equal(member.role, 'teen_minor');
  assert.equal(member.is_admin, false);
  assert.equal((await request(`/v1/families/${family.body.id}/invitations`, { phone: freshPhone(), role: 'parent_guardian' }, { token: verified.body.accessToken })).status, 403);
  const emailInvite = await request(`/v1/families/${family.body.id}/invitations`, { email: freshEmail(), role: 'adult_member' }, { token: parentLogin.body.accessToken });
  assert.equal(emailInvite.status, 201);
  assert.ok(emailInvite.body.invitationToken);
  await until(() => output.split('\n').some((line) => {
    try { const event = JSON.parse(line); return event.type === 'auth_delivery' && event.attemptId === emailInvite.body.id && event.status === 'failed'; }
    catch { return false; }
  }));
  assert.equal((await pool.query('select 1 from family_invitation where id=$1 and status=\'pending\'', [emailInvite.body.id])).rowCount, 1);
  assert.equal(errors.includes(invitation.body.invitationToken), false);
  assert.equal(output.includes(invitation.body.invitationToken), false);
  assert.equal(errors.includes(emailInvite.body.invitationToken), false);
  assert.equal(output.includes(emailInvite.body.invitationToken), false);
});

test('provider retry uses one idempotency key and never exposes a rejected provider payload', async () => {
  const attempts = [];
  const provider = createEmailProvider({
    env: { NODE_ENV: 'production', EMAIL_FROM: 'fixture@example.test', RESEND_API_KEY: 'synthetic-local-not-a-real-key' },
    async fetchImpl(_url, options) {
      attempts.push(options.headers['Idempotency-Key']);
      return { ok: attempts.length === 3, status: 503 };
    },
  });
  const result = await safelyDeliver(provider, { to: 'synthetic@example.test', subject: 'Synthetic', text: 'Synthetic fixture' }, { env: { NODE_ENV: 'test' } });
  assert.equal(result.delivered, true);
  assert.equal(attempts.length, 3);
  assert.equal(new Set(attempts).size, 1);
});

test('email ownership verification cannot enable a pre-registered attacker password', async () => {
  const account = await emailAccount();
  const duplicate = await providerRequest('/v1/auth/register', { email: account.contact, displayName: 'Real Owner', password: replacement });
  assert.equal(duplicate.status, 202);
  assert.deepEqual(duplicate.body, { accepted: true });
  const oldHash = (await pool.query('select password_hash from auth_credential where user_id=$1', [account.id])).rows[0].password_hash;
  assert.equal(await argon2.verify(oldHash, password), true);
  assert.equal((await providerRequest('/v1/auth/verify-email', { token: account.token })).status, 400);
  assert.equal((await pool.query('select email_verified_at from app_user where id=$1', [account.id])).rows[0].email_verified_at, null);
  assert.equal((await providerRequest('/v1/auth/verify-email', { token: account.token, newPassword: replacement })).status, 204);
  assert.equal((await providerRequest('/v1/auth/login', { email: account.contact, password })).status, 401);
  assert.equal((await providerRequest('/v1/auth/login', { email: account.contact, password: replacement })).status, 200);
});

test('login cannot issue a session using a stale password after concurrent recovery commits', async () => {
  const account = await emailAccount();
  assert.equal((await providerRequest('/v1/auth/verify-email', { token: account.token, newPassword: password })).status, 204);
  const before = mail.length;
  assert.equal((await providerRequest('/v1/auth/forgot-password', { email: account.contact })).status, 200);
  const resetMessage = await until(() => mail.slice(before).find((item) => item.to === account.contact));
  const reset = new URL(resetMessage.text.match(/https:\/\/\S+/)[0]).searchParams.get('token');
  const barrier = await pool.connect();
  let recovery;
  let staleLogin;
  try {
    await barrier.query('begin');
    await barrier.query('select id from app_user where id=$1 for update', [account.id]);
    const blocked = async (count) => (await pool.query(
      "select count(*)::int as n from pg_stat_activity where application_name=$1 and wait_event_type='Lock' and query='select 1 from app_user where id=$1 and disabled_at is null for update'", [applicationName],
    )).rows[0].n >= count;
    // Queue real recovery first, then let real login verify the old hash before it blocks.
    recovery = providerRequest('/v1/auth/reset-password', { token: reset, newPassword: replacement });
    await until(() => blocked(1));
    staleLogin = providerRequest('/v1/auth/login', { email: account.contact, password });
    await until(() => blocked(2));
    await barrier.query('commit');
    assert.equal((await recovery).status, 204);
    assert.equal((await staleLogin).status, 401);
  } finally {
    await barrier.query('rollback').catch(() => {});
    barrier.release();
    await Promise.allSettled([recovery, staleLogin].filter(Boolean));
  }
  assert.equal((await providerRequest('/v1/auth/login', { email: account.contact, password: replacement })).status, 200);
});

test('disabled SMS gates verification uniformly before reading or consuming a pending proof', async () => {
  const account = await phoneAccount();
  const proof = await otp(account.contact);
  const known = await request('/v1/auth/phone/verify-otp', { ...proof, newPassword: password });
  const malformed = await request('/v1/auth/phone/verify-otp', { challengeId: 'synthetic-invalid', code: 'bad' });
  assert.equal(known.status, 503);
  assert.equal(malformed.status, 503);
  assert.deepEqual(known.body, malformed.body);
  const stored = (await pool.query('select attempts,used_at from auth_phone_challenge where id=$1', [proof.challengeId])).rows[0];
  assert.equal(stored.attempts, 0);
  assert.equal(stored.used_at, null);
});

test('phone OTP cooldown applies equally to known and unknown contacts across purposes', async () => {
  const account = await phoneAccount();
  const unknown = freshPhone();
  for (const contact of [account.contact, unknown]) {
    const first = await providerRequest('/v1/auth/phone/request-otp', { phone: contact, purpose: 'verify' });
    assert.equal(first.status, 202);
    challengeIds.add(first.body.challengeId);
    const blocked = await providerRequest('/v1/auth/phone/request-otp', { phone: contact, purpose: 'recovery' });
    assert.equal(blocked.status, 429);
    assert.equal(Number(blocked.headers.get('Retry-After')) > 0, true);
  }
});

test('Persian and Iranian phone representations normalize consistently without binding a second unverified channel', async () => {
  const local = `0900${crypto.randomInt(1000000, 9999999)}`;
  const normalized = '+98' + local.slice(1);
  recipients.add(normalized);
  const persian = local.replace(/\d/g, (digit) => String.fromCharCode(0x6f0 + Number(digit)));
  assert.equal((await providerRequest('/v1/auth/register', { phone: persian, password, displayName: 'Synthetic Persian Phone' })).status, 202);
  const id = await identify(normalized);
  const duplicate = await providerRequest('/v1/auth/register', { phone: `00${normalized.slice(1)}`, password: replacement, displayName: 'Must Not Replace' });
  assert.equal(duplicate.status, 202);
  assert.equal((await pool.query('select count(*)::int as n from app_user where phone_normalized=$1', [normalized])).rows[0].n, 1);
  assert.equal((await providerRequest('/v1/auth/register', { email: freshEmail(), phone: normalized, password, displayName: 'Cannot Bind Second Contact' })).status, 400);
  assert.equal((await pool.query('select email_normalized from app_user where id=$1', [id])).rows[0].email_normalized, null);
});

test('archived families and revoked inviters cannot authorize outstanding invitations', async () => {
  for (const revoke of ['archive', 'admin', 'membership']) {
    const fixture = await familyFixture();
    const invitation = await phoneInvitation(fixture);
    if (revoke === 'archive') await pool.query('update family_workspace set archived_at=now() where id=$1', [fixture.familyId]);
    if (revoke === 'admin') await pool.query('update family_membership set is_admin=false where family_id=$1 and user_id=$2', [fixture.familyId, fixture.parent.id]);
    if (revoke === 'membership') await pool.query('update family_membership set ended_at=now() where family_id=$1 and user_id=$2', [fixture.familyId, fixture.parent.id]);
    const accepted = await request('/v1/invitations/accept', { token: invitation.invitationToken }, { token: fixture.child.accessToken });
    assert.equal(accepted.status, 400);
    assert.equal((await pool.query('select 1 from family_membership where family_id=$1 and user_id=$2', [fixture.familyId, fixture.child.id])).rowCount, 0);
    if (revoke === 'archive') {
      assert.equal((await request(`/v1/families/${fixture.familyId}/members`, undefined, { method: 'GET', token: fixture.parent.accessToken })).status, 403);
      assert.equal((await request(`/v1/families/${fixture.familyId}/invitations`, { phone: freshPhone(), role: 'teen_minor' }, { token: fixture.parent.accessToken })).status, 403);
    }
  }
});

test('a former admin rejoining as a child cannot resurrect admin powers or override an active role', async () => {
  const fixture = await familyFixture();
  await pool.query("insert into family_membership(family_id,user_id,role,is_admin,ended_at) values($1,$2,'adult_member',true,now())", [fixture.familyId, fixture.child.id]);
  const invitation = await phoneInvitation(fixture);
  assert.equal((await request('/v1/invitations/accept', { token: invitation.invitationToken }, { token: fixture.child.accessToken })).status, 204);
  const row = (await pool.query('select role,is_admin from family_membership where family_id=$1 and user_id=$2', [fixture.familyId, fixture.child.id])).rows[0];
  assert.equal(row.role, 'teen_minor');
  assert.equal(row.is_admin, false);
  assert.equal((await request(`/v1/families/${fixture.familyId}/invitations`, { phone: freshPhone(), role: 'parent_guardian' }, { token: fixture.child.accessToken })).status, 403);
  // An older pending alternative grant must not change an already-active membership.
  const alternateToken = crypto.randomBytes(32).toString('base64url');
  await pool.query("insert into family_invitation(family_id,invited_phone_normalized,intended_role,token_digest,invited_by,expires_at) values($1,$2,'parent_guardian',$3,$4,now()+interval '7 days')", [fixture.familyId, fixture.child.contact, tokenDigest(alternateToken), fixture.parent.id]);
  assert.equal((await request('/v1/invitations/accept', { token: alternateToken }, { token: fixture.child.accessToken })).status, 409);
  assert.equal((await pool.query('select role from family_membership where family_id=$1 and user_id=$2', [fixture.familyId, fixture.child.id])).rows[0].role, 'teen_minor');
});

test('family management persists edits and securely revokes guardians, membership and archived access', async () => {
  const fixture = await familyFixture();
  const invitation = await phoneInvitation(fixture);
  assert.equal((await request('/v1/invitations/accept', { token: invitation.invitationToken }, { token: fixture.child.accessToken })).status, 204);
  const path = `/v1/families/${fixture.familyId}`;
  assert.equal((await request(path, { name: 'Unauthorized Rename' }, { method: 'PATCH', token: fixture.child.accessToken })).status, 403);
  assert.equal((await request(path, { name: 'Renamed Synthetic Family' }, { method: 'PATCH', token: fixture.parent.accessToken })).status, 200);
  const found = await request(path, undefined, { method: 'GET', token: fixture.child.accessToken });
  assert.equal(found.status, 200);
  assert.equal(found.body.name, 'Renamed Synthetic Family');
  const relation = { guardianUserId: fixture.parent.id, minorUserId: fixture.child.id };
  assert.equal((await request(`${path}/guardians`, relation, { token: fixture.parent.accessToken })).status, 204);
  assert.equal((await request(`${path}/guardians`, relation, { method: 'DELETE', token: fixture.child.accessToken })).status, 403);
  assert.equal((await request(`${path}/guardians`, relation, { method: 'DELETE', token: fixture.parent.accessToken })).status, 204);
  assert.equal((await pool.query('select active from guardian_relationship where family_id=$1 and guardian_user_id=$2 and minor_user_id=$3', [fixture.familyId, fixture.parent.id, fixture.child.id])).rows[0].active, false);
  assert.equal((await request(`${path}/guardians`, relation, { token: fixture.parent.accessToken })).status, 204);
  assert.equal((await request(`${path}/members/${fixture.parent.id}`, undefined, { method: 'DELETE', token: fixture.parent.accessToken })).status, 409);
  assert.equal((await request(`${path}/members/${fixture.child.id}`, undefined, { method: 'DELETE', token: fixture.parent.accessToken })).status, 204);
  assert.equal((await request(path, undefined, { method: 'GET', token: fixture.child.accessToken })).status, 403);
  assert.equal((await pool.query('select active from guardian_relationship where family_id=$1 and guardian_user_id=$2 and minor_user_id=$3', [fixture.familyId, fixture.parent.id, fixture.child.id])).rows[0].active, false);
  const outstanding = await phoneInvitation(fixture);
  assert.equal((await request(path, undefined, { method: 'DELETE', token: fixture.parent.accessToken })).status, 204);
  assert.equal((await request(path, undefined, { method: 'GET', token: fixture.parent.accessToken })).status, 403);
  assert.equal((await request('/v1/invitations/accept', { token: outstanding.invitationToken }, { token: fixture.child.accessToken })).status, 400);
  const archived = (await pool.query('select archived_at from family_workspace where id=$1', [fixture.familyId])).rows[0];
  assert.ok(archived.archived_at);
});
