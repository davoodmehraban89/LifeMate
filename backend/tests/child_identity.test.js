// Synthetic accounts on loopback PostgreSQL only; never invokes SMS, email or AI.
import test, { after } from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import express from 'express';
import jwt from 'jsonwebtoken';
import pg from 'pg';
import { createSessionAuth } from '../src/session_auth.js';
import { createChildIdentityRouter } from '../src/child_identity.js';

const location = new URL(process.env.TEST_FIXTURE_DATABASE_URL ?? process.env.DATABASE_URL);
assert.ok(['127.0.0.1', 'localhost', '[::1]'].includes(location.hostname));
assert.match(location.pathname, /^\/(?:lifeguide_roles_source_[a-f0-9]{16}|lifemate_ci|lifeguide_\w*test\w*)$/);
const marker = 'child-sandbox-' + crypto.randomUUID();
const pool = new pg.Pool({ connectionString: location.href, application_name: marker });
const secret = 'synthetic-child-sandbox-signing-fixture-not-a-live-key';
const users = [], families = [], servers = [];
const consentVersion = 'sandbox-child-consent-v1-not-legal';
async function start(env = { NODE_ENV: 'test', ENABLE_CHILD_IDENTITY_SANDBOX: 'true' }) {
  const app = express(); app.use(express.json());
  app.use('/v1', createChildIdentityRouter({ pool, jwtSecret: secret,
    auth: createSessionAuth({ pool, jwtSecret: secret, env }), env }));
  app.use((_req, res) => res.status(404).json({ error: 'not_found' }));
  app.use((_error, _req, res, _next) => res.status(500).json({ error: 'test_unexpected_server_error' }));
  const server = app.listen(0, '127.0.0.1'); servers.push(server);
  await new Promise(resolve => server.once('listening', resolve));
  return 'http://127.0.0.1:' + server.address().port + '/v1';
}
const base = await start();
after(async () => {
  await Promise.all(servers.map(server => new Promise(resolve => server.close(resolve))));
  try {
    await pool.query('delete from access_audit where family_id=any($1::uuid[]) or actor_user_id=any($2::uuid[])', [families, users]);
    await pool.query('delete from family_workspace where id=any($1::uuid[])', [families]);
    await pool.query('delete from auth_session where user_id=any($1::uuid[])', [users]);
    await pool.query('delete from app_user where id=any($1::uuid[])', [users]);
  } finally { await pool.end(); }
});
async function actor({ birthDate = '1985-01-01' } = {}) {
  const id = crypto.randomUUID(), sid = crypto.randomUUID(); users.push(id);
  await pool.query('insert into app_user(id,identity_subject,email_normalized) values($1,$2,$3)',
    [id, marker + ':' + id, 'sandbox-' + id + '@example.test']);
  await pool.query("insert into profile(user_id,display_name,birth_date) values($1,'Synthetic Adult',$2)", [id, birthDate]);
  await pool.query("insert into auth_session(id,user_id,refresh_digest,expires_at) values($1,$2,$3,clock_timestamp()+interval '1 day')", [sid, id, crypto.randomUUID()]);
  return { id, sid, token: jwt.sign({ sub: id, sid, aud: 'lifemate-api' }, secret, { issuer: 'lifemate', expiresIn: '15m' }) };
}
async function family(owner, members = []) {
  const id = crypto.randomUUID(); families.push(id);
  await pool.query("insert into family_workspace(id,name,created_by) values($1,'Synthetic child sandbox',$2)", [id, owner.id]);
  await pool.query("insert into family_membership(family_id,user_id,role,is_admin) values($1,$2,'parent_guardian',true)", [id, owner.id]);
  for (const member of members) await pool.query('insert into family_membership(family_id,user_id,role,is_admin) values($1,$2,$3,$4)',
    [id, member.user.id, member.role ?? 'parent_guardian', member.admin ?? false]);
  return id;
}
async function request(who, method, path, body, origin = base) {
  const response = await fetch(origin + path, { method, headers: { 'content-type': 'application/json',
    ...(who ? { authorization: 'Bearer ' + who.token } : {}) }, body: body === undefined ? undefined : JSON.stringify(body), signal: AbortSignal.timeout(10000) });
  return { status: response.status, body: await response.json(), cache: response.headers.get('cache-control') };
}
const createBody = () => ({ displayName: 'Synthetic Child', birthDate: '2015-03-12', profileCategory: 'girl_minor',
  consentVersion, consentAccepted: true, synthetic: true });
async function child(owner, familyId) {
  const result = await request(owner, 'POST', `/families/${familyId}/children`, createBody());
  assert.equal(result.status, 201); users.push(result.body.child.userId); return result.body.child;
}
const issueDevice = (owner, familyId, childId) => request(owner, 'POST', `/families/${familyId}/children/${childId}/device-invitations`, { synthetic: true });
const acceptDevice = token => request(null, 'POST', '/child-devices/accept', { token });
const issueGuardian = (owner, familyId, childId, recipient) => request(owner, 'POST', `/families/${familyId}/children/${childId}/guardian-invitations`, { guardianUserId: recipient.id });
const acceptGuardian = (recipient, token) => request(recipient, 'POST', '/guardian-invitations/accept', { token });
async function observedWait() {
  for (let i = 0; i < 300; i++) {
    if ((await pool.query("select 1 from pg_stat_activity where application_name=$1 and wait_event_type='Lock'", [marker])).rowCount) return;
    await new Promise(resolve => setTimeout(resolve, 10));
  }
  assert.fail('Expected real PostgreSQL lock wait');
}
async function blockFamily(familyId, operation, mutation) {
  const blocker = await pool.connect();
  try {
    await blocker.query('begin'); await blocker.query('select id from family_workspace where id=$1 for update', [familyId]);
    const pending = operation(); await observedWait(); await mutation(blocker); await blocker.query('commit'); return await pending;
  } finally { await blocker.query('rollback'); blocker.release(); }
}

test('sandbox is disabled unless explicitly enabled in test/development; production cannot opt in', async () => {
  for (const env of [{ NODE_ENV: 'production', ENABLE_CHILD_IDENTITY_SANDBOX: 'true' }, { NODE_ENV: 'test' },
    { NODE_ENV: 'staging', ENABLE_CHILD_IDENTITY_SANDBOX: 'true' }]) {
    const origin = await start(env);
    const result = await request(null, 'POST', '/child-devices/accept', { token: 'synthetic' }, origin);
    assert.equal(result.status, 503); assert.equal(result.body.error, 'child_identity_sandbox_disabled');
  }
});

test('adult parent admin creates contactless child, initial guardian and versioned synthetic consent atomically', async () => {
  const owner = await actor(), id = await family(owner), created = await child(owner, id);
  const row = (await pool.query(`select u.email_normalized,u.phone_normalized,u.is_managed_child,p.birth_date::text,p.profile_category,
    m.role,m.is_admin,g.active,c.text_version,c.text_digest,mc.creator_user_id,
    exists(select 1 from auth_credential where user_id=u.id) has_credential
    from app_user u join profile p on p.user_id=u.id join family_membership m on m.user_id=u.id
    join managed_child mc on mc.user_id=u.id join child_consent c on c.child_user_id=u.id
    join guardian_relationship g on g.minor_user_id=u.id where u.id=$1`, [created.userId])).rows[0];
  assert.equal(row.email_normalized, null); assert.equal(row.phone_normalized, null); assert.equal(row.is_managed_child, true);
  assert.equal(row.birth_date, '2015-03-12'); assert.equal(row.profile_category, 'girl_minor'); assert.equal(row.role, 'teen_minor');
  assert.equal(row.is_admin, false); assert.equal(row.active, true); assert.equal(row.has_credential, false);
  assert.equal(row.creator_user_id, owner.id); assert.equal(row.text_version, consentVersion); assert.match(row.text_digest, /^[a-f0-9]{64}$/);
  assert.equal((await pool.query('select count(*)::int n from auth_session where user_id=$1', [created.userId])).rows[0].n, 0);
});

test('creation rejects malformed DOB/category/consent and unauthorized or age-unknown parent without rows', async () => {
  const owner = await actor(), unknown = await actor({ birthDate: null }), minor = await actor({ birthDate: '2015-01-01' }), outsider = await actor();
  const id = await family(owner, [{ user: unknown, admin: true }, { user: minor, admin: true }]);
  for (const patch of [{ birthDate: '2015-02-30' }, { birthDate: '2999-01-01' }, { birthDate: '1980-01-01' },
    { birthDate: null }, { profileCategory: 'adult' }, { consentAccepted: false }, { consentVersion: 'unapproved' }, { synthetic: false },
    { phone: '+000' }, { birthDate: ['2015-03-12'] }, { displayName: '\u0000' }]) {
    assert.equal((await request(owner, 'POST', `/families/${id}/children`, { ...createBody(), ...patch })).status, 400);
  }
  for (const candidate of [unknown, minor, outsider]) assert.equal((await request(candidate, 'POST', `/families/${id}/children`, createBody())).status, 403);
  assert.equal((await pool.query('select count(*)::int n from managed_child where family_id=$1', [id])).rows[0].n, 0);
});

test('device redemption stores only digest, is single-use under concurrency and mints education scope', async () => {
  const owner = await actor(), id = await family(owner), created = await child(owner, id), invitation = await issueDevice(owner, id, created.userId);
  assert.equal(invitation.status, 201); assert.equal(invitation.cache, 'no-store');
  assert.match(invitation.body.token, /^[A-Za-z0-9_-]{43}$/);
  const stored = (await pool.query('select token_digest from child_device_invitation where child_user_id=$1', [created.userId])).rows[0];
  assert.equal(stored.token_digest, crypto.createHash('sha256').update(invitation.body.token).digest('hex'));
  const responses = await Promise.all([acceptDevice(invitation.body.token), acceptDevice(invitation.body.token)]);
  assert.deepEqual(responses.map(r => r.status).sort(), [200, 400]);
  const accepted = responses.find(r => r.status === 200); assert.equal(accepted.cache, 'no-store');
  const claims = jwt.verify(accepted.body.accessToken, secret, { issuer: 'lifemate', audience: 'lifemate-api' });
  assert.equal(claims.sub, created.userId); assert.equal(claims.scope, 'child_education');
  const session = (await pool.query('select access_scope from auth_session where id=$1', [claims.sid])).rows[0];
  assert.equal(session.access_scope, 'child_education');
  const visibility = await request({ token: accepted.body.accessToken }, 'GET', '/child-visibility');
  assert.equal(visibility.status, 200); assert.equal(visibility.body.guardians[0].userId, owner.id);
  assert.equal(visibility.body.privateScopeGrantedByThisFlow, false);
  assert.equal((await request(owner, 'GET', '/child-visibility')).status, 403);
});

test('recovery issuance revokes all child sessions and old invitations before new code is returned', async () => {
  const owner = await actor(), id = await family(owner), created = await child(owner, id), first = await issueDevice(owner, id, created.userId);
  const accepted = await acceptDevice(first.body.token); assert.equal(accepted.status, 200);
  const pending = await issueDevice(owner, id, created.userId); assert.equal(pending.status, 201);
  assert.equal((await request({ token: accepted.body.accessToken }, 'GET', '/child-visibility')).status, 401);
  const last = await issueDevice(owner, id, created.userId); assert.equal((await acceptDevice(pending.body.token)).status, 400);
  const restored = await acceptDevice(last.body.token); assert.equal(restored.status, 200);
  assert.equal(jwt.decode(restored.body.accessToken).scope, 'child_education');
  assert.equal((await pool.query('select count(*)::int n from auth_session where user_id=$1 and revoked_at is null', [created.userId])).rows[0].n, 1);
});

test('creator confirmation plus recipient acceptance is required for second guardian; other admin cannot assign', async () => {
  const owner = await actor(), recipient = await actor(), admin = await actor(), outsider = await actor();
  const id = await family(owner, [{ user: recipient }, { user: admin, admin: true }]), created = await child(owner, id);
  assert.equal((await issueGuardian(admin, id, created.userId, recipient)).status, 403);
  assert.equal((await issueGuardian(owner, id, created.userId, outsider)).status, 403);
  const invitation = await issueGuardian(owner, id, created.userId, recipient); assert.equal(invitation.status, 201);
  assert.equal((await pool.query('select count(*)::int n from guardian_relationship where family_id=$1 and minor_user_id=$2', [id, created.userId])).rows[0].n, 1);
  assert.equal((await acceptGuardian(admin, invitation.body.token)).status, 400);
  assert.equal((await acceptGuardian(recipient, invitation.body.token)).status, 200);
  assert.equal((await acceptGuardian(recipient, invitation.body.token)).status, 400);
  assert.equal((await pool.query('select count(*)::int n from guardian_relationship where family_id=$1 and minor_user_id=$2 and active', [id, created.userId])).rows[0].n, 2);
  assert.equal((await issueDevice(recipient, id, created.userId)).status, 201);
});

test('consent revocation is creator-only and revokes sessions, relationships and every outstanding invitation', async () => {
  const owner = await actor(), recipient = await actor(), id = await family(owner, [{ user: recipient }]), created = await child(owner, id);
  const code = await issueDevice(owner, id, created.userId), accepted = await acceptDevice(code.body.token);
  const device = await issueDevice(owner, id, created.userId), guardian = await issueGuardian(owner, id, created.userId, recipient);
  assert.equal((await request(recipient, 'DELETE', `/families/${id}/children/${created.userId}/consent`)).status, 403);
  assert.equal((await request(owner, 'DELETE', `/families/${id}/children/${created.userId}/consent`)).status, 200);
  assert.equal((await acceptDevice(device.body.token)).status, 400); assert.equal((await acceptGuardian(recipient, guardian.body.token)).status, 400);
  assert.equal((await request({ token: accepted.body.accessToken }, 'GET', '/child-visibility')).status, 401);
  assert.equal((await issueDevice(owner, id, created.userId)).status, 403);
  assert.equal((await pool.query('select count(*)::int n from guardian_relationship where family_id=$1 and minor_user_id=$2 and active', [id, created.userId])).rows[0].n, 0);
});

test('device expiry and guardian revocation after actual lock waits prevent redemption without consuming tokens', async () => {
  const owner = await actor(), recipient = await actor(), id = await family(owner, [{ user: recipient }]), created = await child(owner, id);
  const device = await issueDevice(owner, id, created.userId);
  const expired = await blockFamily(id, () => acceptDevice(device.body.token), blocker => blocker.query('update child_device_invitation set expires_at=clock_timestamp() where child_user_id=$1', [created.userId]));
  assert.equal(expired.status, 400);
  assert.equal((await pool.query('select used_at from child_device_invitation where token_digest=$1', [crypto.createHash('sha256').update(device.body.token).digest('hex')])).rows[0].used_at, null);
  const guardian = await issueGuardian(owner, id, created.userId, recipient);
  const revoked = await blockFamily(id, () => acceptGuardian(recipient, guardian.body.token), blocker => blocker.query('update guardian_relationship set active=false where family_id=$1 and guardian_user_id=$2', [id, owner.id]));
  assert.equal(revoked.status, 400);
});

test('parent session expiry or authority change during family wait rolls back child creation', async () => {
  for (const invalidation of ['session', 'membership', 'birth_date']) {
    const owner = await actor(), id = await family(owner);
    const result = await blockFamily(id, () => request(owner, 'POST', `/families/${id}/children`, createBody()), blocker =>
      invalidation === 'session' ? blocker.query('update auth_session set expires_at=clock_timestamp() where id=$1', [owner.sid]) :
        invalidation === 'membership' ? blocker.query('update family_membership set is_admin=false where family_id=$1 and user_id=$2', [id, owner.id]) :
          blocker.query("update profile set birth_date='2015-01-01' where user_id=$1", [owner.id]));
    assert.equal(result.status, invalidation === 'session' ? 401 : 403);
    assert.equal((await pool.query('select count(*)::int n from managed_child where family_id=$1', [id])).rows[0].n, 0);
  }
});

test('strict route identifiers and token bodies return 400 without PostgreSQL cast errors', async () => {
  const owner = await actor(), id = await family(owner), created = await child(owner, id);
  assert.equal((await request(owner, 'POST', '/families/not-a-uuid/children', createBody())).status, 400);
  assert.equal((await request(owner, 'POST', `/families/${id}/children/not-a-uuid/device-invitations`, { synthetic: true })).status, 400);
  assert.equal((await request(owner, 'POST', `/families/${id}/children/${created.userId}/guardian-invitations`, { guardianUserId: ['invalid'] })).status, 400);
  for (const body of [{ token: null }, { token: [] }, { token: 'unknown' }, { token: 'a'.repeat(43), extra: true }]) {
    assert.equal((await request(null, 'POST', '/child-devices/accept', body)).status, 400);
  }
  assert.equal((await acceptDevice('a'.repeat(43))).body.error, 'invalid_or_expired_invitation');
});

test('cross-family child and inactive guardian cannot issue or redeem an existing device invitation', async () => {
  const owner = await actor(), outsider = await actor(), first = await family(owner), second = await family(outsider), created = await child(owner, first);
  assert.equal((await issueDevice(outsider, second, created.userId)).status, 403);
  assert.equal((await issueDevice(outsider, first, created.userId)).status, 403);
  const invitation = await issueDevice(owner, first, created.userId);
  await pool.query('update family_membership set ended_at=clock_timestamp() where family_id=$1 and user_id=$2', [first, owner.id]);
  assert.equal((await acceptDevice(invitation.body.token)).status, 400);
  assert.equal((await pool.query('select count(*)::int n from auth_session where user_id=$1', [created.userId])).rows[0].n, 0);
});

test('final parent session-row wait rechecks expiry and rolls back earlier creation writes and audit', async () => {
  const owner = await actor(), id = await family(owner), blocker = await pool.connect();
  try {
    await blocker.query('begin'); await blocker.query('select id from auth_session where id=$1 for update', [owner.sid]);
    const pending = request(owner, 'POST', `/families/${id}/children`, createBody()); await observedWait();
    await blocker.query('update auth_session set expires_at=clock_timestamp() where id=$1', [owner.sid]);
    await blocker.query('commit'); assert.equal((await pending).status, 401);
    assert.equal((await pool.query('select count(*)::int n from managed_child where family_id=$1', [id])).rows[0].n, 0);
    assert.equal((await pool.query('select count(*)::int n from access_audit where family_id=$1', [id])).rows[0].n, 0);
  } finally { await blocker.query('rollback'); blocker.release(); }
});

test('guardian token expiration during final recipient session-row wait is rechecked before consumption', async () => {
  const owner = await actor(), recipient = await actor(), id = await family(owner, [{ user: recipient }]), created = await child(owner, id);
  const invitation = await issueGuardian(owner, id, created.userId, recipient), blocker = await pool.connect();
  const tokenDigest = crypto.createHash('sha256').update(invitation.body.token).digest('hex');
  const deadline = (await pool.query("update guardian_invitation set expires_at=clock_timestamp()+interval '2 seconds' where token_digest=$1 returning expires_at", [tokenDigest])).rows[0].expires_at;
  try {
    await blocker.query('begin'); await blocker.query('select id from auth_session where id=$1 for update', [recipient.sid]);
    const pending = acceptGuardian(recipient, invitation.body.token); await observedWait();
    // Invitation row is held by the request. Observe the real DB wall clock
    // passing its deadline without trying to mutate the locked invitation.
    while (!(await blocker.query('select clock_timestamp()>=$1::timestamptz expired', [deadline])).rows[0].expired)
      await new Promise(resolve => setTimeout(resolve, 10));
    await blocker.query('commit'); assert.equal((await pending).status, 400);
    assert.equal((await pool.query('select used_at from guardian_invitation where token_digest=$1', [tokenDigest])).rows[0].used_at, null);
  } finally { await blocker.query('rollback'); blocker.release(); }
});

test('creator can revoke accepted second guardian and its issued devices; another admin cannot', async () => {
  const owner = await actor(), recipient = await actor(), admin = await actor(), id = await family(owner, [{ user: recipient }, { user: admin, admin: true }]);
  const created = await child(owner, id), invitation = await issueGuardian(owner, id, created.userId, recipient);
  assert.equal((await acceptGuardian(recipient, invitation.body.token)).status, 200);
  const device = await issueDevice(recipient, id, created.userId), accepted = await acceptDevice(device.body.token);
  assert.equal(accepted.status, 200);
  const pending = await issueDevice(recipient, id, created.userId);
  const revoke = who => request(who, 'DELETE', `/families/${id}/children/${created.userId}/guardians/${recipient.id}`);
  assert.equal((await revoke(admin)).status, 403);
  assert.equal((await request(owner, 'DELETE', `/families/${id}/children/${created.userId}/guardians/${owner.id}`)).status, 409);
  assert.equal((await revoke(owner)).status, 200);
  assert.equal((await pool.query('select active from guardian_relationship where family_id=$1 and guardian_user_id=$2 and minor_user_id=$3', [id, recipient.id, created.userId])).rows[0].active, false);
  assert.ok((await pool.query('select revoked_at from guardian_invitation where token_digest=$1', [crypto.createHash('sha256').update(invitation.body.token).digest('hex')])).rows[0].revoked_at);
  assert.equal((await acceptDevice(pending.body.token)).status, 400);
  assert.equal((await request({ token: accepted.body.accessToken }, 'GET', '/child-visibility')).status, 401);
  assert.equal((await issueDevice(recipient, id, created.userId)).status, 403);
});
