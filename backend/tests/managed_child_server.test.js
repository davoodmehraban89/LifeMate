// Real app/HTTP/PostgreSQL integration; only invented identities on loopback.
import test, { after } from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import jwt from 'jsonwebtoken';
import pg from 'pg';
import { rateLimitProfile } from '../src/operations.js';

const location = new URL(process.env.TEST_FIXTURE_DATABASE_URL ?? process.env.DATABASE_URL);
assert.ok(['127.0.0.1', 'localhost', '[::1]'].includes(location.hostname), 'Loopback database only');
assert.match(location.pathname, /^\/(?:lifeguide_roles_source_[a-f0-9]{16}|lifemate_ci|lifeguide_\w*test\w*)$/);
const marker = 'managed-child-http-' + crypto.randomUUID();
const secret = 'synthetic-managed-child-http-fixture-not-a-live-signing-key';
process.env.DATABASE_URL = location.href;
process.env.JWT_SECRET = secret;
process.env.PGAPPNAME = marker;
process.env.NODE_ENV = 'test';
process.env.ENABLE_CHILD_IDENTITY_SANDBOX = 'true';
process.env.ENABLE_SENSITIVE_FEATURES = 'false';
process.env.SMS_PROVIDER = 'disabled';
for (const name of ['SMS_PROVIDER_URL', 'SMS_PROVIDER_TOKEN', 'KAVENEGAR_API_KEY', 'EMAIL_FROM', 'RESEND_API_KEY',
  'SMTP_HOST', 'SMTP_USER', 'SMTP_PASSWORD', 'AI_API_KEY', 'AI_BASE_URL', 'AI_MODEL', 'OPENAI_API_KEY']) process.env[name] = '';
const { app, pool } = await import('../src/server.js');
const observer = new pg.Pool({ connectionString: location.href, application_name: marker + '-observer' });
const server = app.listen(0, '127.0.0.1');
await new Promise(resolve => server.once('listening', resolve));
const base = 'http://127.0.0.1:' + server.address().port + '/v1';
const users = [], families = [];
const hash = raw => crypto.createHash('sha256').update(raw).digest('hex');
const claims = (id, sid, extra = {}) => jwt.sign({ ...extra, sub: id, sid, aud: 'lifemate-api' }, secret, { issuer: 'lifemate', expiresIn: '15m' });
after(async () => {
  await new Promise(resolve => server.close(resolve));
  try {
    await pool.query('delete from access_audit where family_id=any($1::uuid[]) or actor_user_id=any($2::uuid[])', [families, users]);
    await pool.query('delete from family_workspace where id=any($1::uuid[])', [families]);
    await pool.query('delete from auth_session where user_id=any($1::uuid[])', [users]);
    await pool.query('delete from app_user where id=any($1::uuid[])', [users]);
  } finally { await pool.end(); await observer.end(); }
});
async function request(who, method, path, body) {
  const response = await fetch(base + path, { method, headers: { 'content-type': 'application/json',
    ...(who ? { authorization: 'Bearer ' + who.accessToken } : {}) },
    body: body === undefined ? undefined : JSON.stringify(body), signal: AbortSignal.timeout(10000) });
  const text = await response.text();
  return { status: response.status, body: text ? JSON.parse(text) : null, cache: response.headers.get('cache-control') };
}
async function adult() {
  const id = crypto.randomUUID(), sid = crypto.randomUUID(); users.push(id);
  await pool.query('insert into app_user(id,identity_subject,email_normalized,email_verified_at) values($1,$2,$3,clock_timestamp())',
    [id, marker + ':' + id, 'synthetic-' + id + '@example.test']);
  await pool.query("insert into profile(user_id,display_name,birth_date) values($1,'Synthetic Adult','1985-01-01')", [id]);
  await pool.query("insert into auth_session(id,user_id,refresh_digest,expires_at) values($1,$2,$3,clock_timestamp()+interval '1 day')", [sid, id, crypto.randomUUID()]);
  return { id, sid, accessToken: claims(id, sid) };
}
async function fixture() {
  const owner = await adult(), other = await adult(), familyId = crypto.randomUUID(); families.push(familyId);
  await pool.query("insert into family_workspace(id,name,created_by) values($1,'Synthetic server fixture',$2)", [familyId, owner.id]);
  for (const member of [owner, other]) await pool.query("insert into family_membership(family_id,user_id,role,is_admin) values($1,$2,'parent_guardian',true)", [familyId, member.id]);
  const result = await request(owner, 'POST', `/families/${familyId}/children`, {
    displayName: 'Synthetic Child', birthDate: '2015-03-12', profileCategory: 'girl_minor',
    consentVersion: 'sandbox-child-consent-v1-not-legal', consentAccepted: true, synthetic: true });
  assert.equal(result.status, 201, 'Real app child creation');
  const childId = result.body.child.userId; users.push(childId);
  const issued = await request(owner, 'POST', `/families/${familyId}/children/${childId}/device-invitations`, { synthetic: true });
  assert.equal(issued.status, 201);
  const accepted = await request(null, 'POST', '/child-devices/accept', { token: issued.body.token });
  assert.equal(accepted.status, 200);
  return { owner, other, familyId, childId, child: accepted.body };
}
const refresh = child => request(null, 'POST', '/auth/refresh', { refreshToken: child.refreshToken });
async function privateDenied(child, planId) {
  for (const [method, path, body] of [
    ['GET', '/today'], ['GET', '/plan-items'], ['GET', '/plan-items/' + planId], ['GET', '/study/sessions'],
    ['GET', '/me/learning-attempts'], ['GET', '/me/iran-profile'], ['GET', '/me/menstrual-cycles'],
    ['POST', '/ai/sessions', {}], ['POST', '/plan-items', { title: 'Synthetic', kind: 'task' }],
  ]) {
    const result = await request(child, method, path, body);
    assert.equal(result.status, 403, 'Managed device denied ' + method + ' ' + path);
    assert.equal(result.body.error, 'child_session_scope_denied');
    assert.equal(result.cache, 'no-store');
  }
}
async function privatePlan(f) {
  return (await pool.query(`insert into plan_item(owner_user_id,family_id,kind,title,notes,visibility)
    values($1,$2,'task','Synthetic private task','SYNTHETIC-PRIVATE-MARKER','private') returning id`, [f.childId, f.familyId])).rows[0].id;
}

test('real app child device reads only minimal profile/families; legacy privileges and private APIs remain denied', async () => {
  const f = await fixture(), planId = await privatePlan(f);
  const profile = await request(f.child, 'GET', '/profile'); assert.equal(profile.status, 200); assert.equal(profile.cache, 'no-store');
  assert.deepEqual(Object.keys(profile.body).sort(), ['accessScope', 'display_name', 'profile_category', 'theme_preference', 'user_id'].sort());
  assert.equal(profile.body.user_id, f.childId);
  const familiesResult = await request(f.child, 'GET', '/families'); assert.equal(familiesResult.status, 200); assert.equal(familiesResult.cache, 'no-store');
  await privateDenied(f.child, planId);
  for (const who of [f.owner, f.other]) for (const method of ['POST', 'DELETE'])
    assert.equal((await request(who, method, `/families/${f.familyId}/guardians`, { guardianUserId: f.other.id, minorUserId: f.childId })).status, 403);
  assert.equal((await request(f.owner, 'PATCH', `/families/${f.familyId}/members/${f.childId}/role`, {
    mutationId: crypto.randomUUID(), expectedVersion: 1, role: 'adult_member' })).status, 403);
  assert.equal((await request(f.owner, 'POST', `/families/${f.familyId}/admin-transfer`, {
    mutationId: crypto.randomUUID(), targetUserId: f.childId, expectedVersion: 1, expectedActorVersion: 1 })).status, 403);
  for (const path of ['/profile', '/me/iran-profile']) assert.equal((await request(f.child, 'PATCH', path, { birthDate: '1980-01-01', profileCategory: 'adult' })).status, 403);
  const unchanged = (await pool.query('select birth_date::text,profile_category from profile where user_id=$1', [f.childId])).rows[0];
  assert.deepEqual(unchanged, { birth_date: '2015-03-12', profile_category: 'girl_minor' });
  const identity = jwt.decode(f.child.accessToken);
  await privateDenied({ accessToken: claims(f.childId, identity.sid, { scope: 'standard', accessScope: 'standard', managedChild: false }) }, planId);
});

test('real refresh rotates once under concurrency, retains DB scope/issuer and rejects standard managed-child sessions', async () => {
  const f = await fixture(), planId = await privatePlan(f);
  const results = await Promise.all([refresh(f.child), refresh(f.child)]);
  assert.deepEqual(results.map(r => r.status).sort(), [200, 401]);
  for (const result of results) assert.equal(result.cache, 'no-store');
  const replacement = results.find(r => r.status === 200).body;
  const sid = jwt.decode(replacement.accessToken).sid;
  const row = (await pool.query('select access_scope,child_issuer_user_id from auth_session where id=$1', [sid])).rows[0];
  assert.deepEqual(row, { access_scope: 'child_education', child_issuer_user_id: f.owner.id });
  assert.equal((await refresh(f.child)).status, 401); await privateDenied(replacement, planId);
  const injectedSid = crypto.randomUUID(), raw = crypto.randomBytes(32).toString('base64url');
  await pool.query("insert into auth_session(id,user_id,refresh_digest,expires_at,access_scope) values($1,$2,$3,clock_timestamp()+interval '1 day','standard')", [injectedSid, f.childId, hash(raw)]);
  assert.equal((await request({ accessToken: claims(f.childId, injectedSid, { scope: 'standard' }) }, 'GET', '/profile')).status, 401);
  assert.equal((await refresh({ refreshToken: raw })).status, 401);
});

test('forged guardian relationship without creator invitation acceptance cannot read summary or issue child devices', async () => {
  const f = await fixture();
  await pool.query('insert into guardian_relationship(family_id,guardian_user_id,minor_user_id) values($1,$2,$3)', [f.familyId, f.other.id, f.childId]);
  assert.equal((await pool.query('select is_active_guardian($1,$2,$3) active', [f.familyId, f.other.id, f.childId])).rows[0].active, false);
  assert.equal((await request(f.other, 'GET', `/families/${f.familyId}/children/${f.childId}/support-summary`)).status, 403);
  assert.equal((await request(f.other, 'POST', `/families/${f.familyId}/children/${f.childId}/device-invitations`, { synthetic: true })).status, 403);
  const visibility = await request(f.child, 'GET', '/child-visibility'); assert.equal(visibility.status, 200);
  assert.deepEqual(visibility.body.guardians.map(g => g.userId), [f.owner.id]);
});

test('issuer role/relation removal, tampered consent digest and archived family invalidate next access and refresh', async () => {
  for (const change of ['role', 'relationship', 'consent_digest', 'archive']) {
    const f = await fixture();
    if (change === 'role') await pool.query("update family_membership set role='adult_member' where family_id=$1 and user_id=$2", [f.familyId, f.owner.id]);
    if (change === 'relationship') await pool.query('update guardian_relationship set active=false where family_id=$1 and guardian_user_id=$2', [f.familyId, f.owner.id]);
    if (change === 'consent_digest') await pool.query('update child_consent set text_digest=$2 where child_user_id=$1', [f.childId, '0'.repeat(64)]);
    if (change === 'archive') await pool.query('update family_workspace set archived_at=clock_timestamp() where id=$1', [f.familyId]);
    assert.equal((await request(f.child, 'GET', '/profile')).status, 401, change + ' invalidates access');
    assert.equal((await refresh(f.child)).status, 401, change + ' invalidates refresh');
    assert.equal((await pool.query('select count(*)::int n from auth_session where user_id=$1', [f.childId])).rows[0].n, 1);
  }
});

async function observedLock() {
  for (let i = 0; i < 300; i++) {
    if ((await observer.query("select 1 from pg_stat_activity where application_name=$1 and wait_event_type='Lock'", [marker])).rowCount) return;
    await new Promise(resolve => setTimeout(resolve, 10));
  }
  assert.fail('Expected actual refresh PostgreSQL lock wait');
}
test('refresh waiting on family lock rechecks guardian/session revocation and cannot mint a replacement', async () => {
  for (const change of ['relationship', 'session']) {
    const f = await fixture(), blocker = await observer.connect();
    try {
      await blocker.query('begin'); await blocker.query('select id from family_workspace where id=$1 for update', [f.familyId]);
      const pending = refresh(f.child); await observedLock();
      if (change === 'relationship') await blocker.query('update guardian_relationship set active=false where family_id=$1 and guardian_user_id=$2', [f.familyId, f.owner.id]);
      else await blocker.query('update auth_session set revoked_at=clock_timestamp() where id=$1', [jwt.decode(f.child.accessToken).sid]);
      await blocker.query('commit'); assert.equal((await pending).status, 401);
      assert.equal((await pool.query('select count(*)::int n from auth_session where user_id=$1', [f.childId])).rows[0].n, 1);
    } finally { await blocker.query('rollback'); blocker.release(); }
  }
});

test('creator revokes second guardian through real app; its child device and refresh immediately stop working', async () => {
  const f = await fixture();
  const invitation = await request(f.owner, 'POST', `/families/${f.familyId}/children/${f.childId}/guardian-invitations`, { guardianUserId: f.other.id });
  assert.equal(invitation.status, 201);
  assert.equal((await request(f.other, 'POST', '/guardian-invitations/accept', { token: invitation.body.token })).status, 200);
  const code = await request(f.other, 'POST', `/families/${f.familyId}/children/${f.childId}/device-invitations`, { synthetic: true });
  const accepted = await request(null, 'POST', '/child-devices/accept', { token: code.body.token }); assert.equal(accepted.status, 200);
  assert.equal((await request(f.owner, 'DELETE', `/families/${f.familyId}/children/${f.childId}/guardians/${f.other.id}`)).status, 200);
  assert.equal((await request(accepted.body, 'GET', '/profile')).status, 401); assert.equal((await refresh(accepted.body)).status, 401);
});

test('device acceptance exact and Express case/slash variants retain strict authentication quota profile', () => {
  for (const path of ['/v1/child-devices/accept', '/V1/CHILD-DEVICES/ACCEPT', '/v1/child-devices/accept/', '/V1/child-devices/Accept/']) {
    for (const method of ['POST', 'GET', 'PUT']) assert.equal(rateLimitProfile({ path, method }, {}).name, 'auth');
  }
});
