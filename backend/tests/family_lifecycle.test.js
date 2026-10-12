import test, { after, before, describe } from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import net from 'node:net';
import pg from 'pg';
import jwt from 'jsonwebtoken';

const uuid = () => crypto.randomUUID();

describe('family lifecycle real entrypoint and synthetic PostgreSQL', { concurrency: false }, () => {
  let pool, child, base;
  const users = [], families = [];
  const applicationName = `family-lifecycle-fixture-${uuid()}`;
  const secret = 'synthetic-family-lifecycle-signing-secret-not-for-production';

  async function start() {
    const listener = net.createServer().listen(0, '127.0.0.1');
    await once(listener, 'listening');
    const port = listener.address().port;
    await new Promise(resolve => listener.close(resolve));
    base = `http://127.0.0.1:${port}`;
    const env = { ...process.env, JWT_SECRET: secret, NODE_ENV: 'production', PORT: String(port), PGAPPNAME: applicationName,
      SMS_PROVIDER: 'disabled', SMS_PROVIDER_URL: '', SMS_PROVIDER_TOKEN: '', EMAIL_FROM: '', RESEND_API_KEY: '',
      SMTP_HOST: '', SMTP_USER: '', SMTP_PASSWORD: '', AI_API_KEY: '', AI_BASE_URL: '', AI_MODEL: '', OPENAI_API_KEY: '',
      CORS_ORIGINS: '', TRUSTED_PROXY_CIDRS: '', ENABLE_SENSITIVE_FEATURES: 'false',
      RATE_LIMIT_AUTH_MAX: '2000', RATE_LIMIT_GENERAL_MAX: '8000' };
    delete env.TEST_FIXTURE_DATABASE_URL;
    child = spawn(process.execPath, ['src/entrypoint.js'], { cwd: new URL('../', import.meta.url), env,
      stdio: ['ignore', 'pipe', 'pipe'] });
    let startup = '';
    // Do not print fixture HTTP telemetry, JWTs or database connection strings.
    child.stderr.on('data', () => {});
    await new Promise((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error('Family fixture startup timed out')), 10000);
      const ready = chunk => {
        startup += chunk;
        if (startup.includes('"type":"startup"')) {
          clearTimeout(timeout); child.stdout.off('data', ready); child.stdout.on('data', () => {}); resolve();
        }
      };
      child.stdout.on('data', ready);
      child.once('error', () => { clearTimeout(timeout); reject(new Error('Family fixture start failed')); });
      child.once('exit', () => {
        if (!startup.includes('"type":"startup"')) { clearTimeout(timeout); reject(new Error('Family fixture exited early')); }
      });
    });
  }
  async function stop() {
    if (child && child.exitCode === null && child.signalCode === null) {
      const ended = once(child, 'close'); child.kill('SIGTERM'); await ended;
    }
  }
  before(async () => {
    assert.ok(process.env.DATABASE_URL, 'Migrated synthetic PostgreSQL fixture required');
    const location = new URL(process.env.TEST_FIXTURE_DATABASE_URL ?? process.env.DATABASE_URL);
    assert.ok(['localhost', '127.0.0.1', '[::1]', '::1'].includes(location.hostname), 'Only loopback test PostgreSQL allowed');
    assert.ok(location.pathname.includes('test') || location.pathname === '/lifemate_ci' ||
      /^\/lifeguide_roles_source_[a-f0-9]{16}$/.test(location.pathname), 'Explicit synthetic database required');
    pool = new pg.Pool({ connectionString: process.env.TEST_FIXTURE_DATABASE_URL ?? process.env.DATABASE_URL });
    await start();
  });
  after(async () => {
    await stop(); if (!pool) return;
    try {
      await pool.query('delete from access_audit where family_id=any($1::uuid[]) or actor_user_id=any($2::uuid[])', [families, users]);
      await pool.query('delete from family_workspace where id=any($1::uuid[])', [families]);
      await pool.query('delete from app_user where id=any($1::uuid[])', [users]);
    } finally { await pool.end(); }
  });
  async function actor({ birthDate = null, category = 'adult', claims = {} } = {}) {
    const id = uuid(), sid = uuid(), email = `family-${id}@example.test`; users.push(id);
    await pool.query('insert into app_user(id,identity_subject,email_normalized,email_verified_at) values($1,$2,$3,now())',
      [id, `family-lifecycle:${id}`, email]);
    await pool.query("insert into profile(user_id,display_name,birth_date,profile_category,theme_preference) values($1,'Synthetic Family',$2,$3,'adult_blue')", [id, birthDate, category]);
    await pool.query("insert into auth_session(id,user_id,refresh_digest,expires_at) values($1,$2,$3,now()+interval '1 day')", [sid, id, uuid()]);
    return { id, sid, email, token: jwt.sign({ ...claims, sub: id, sid, aud: 'lifemate-api' }, secret,
      { issuer: 'lifemate', expiresIn: '15m' }) };
  }
  async function family(admin, members = []) {
    const id = uuid(); families.push(id);
    await pool.query("insert into family_workspace(id,name,created_by) values($1,'Synthetic Lifecycle Family',$2)", [id, admin.id]);
    await pool.query("insert into family_membership(family_id,user_id,role,is_admin) values($1,$2,'parent_guardian',true)", [id, admin.id]);
    for (const member of members) await pool.query('insert into family_membership(family_id,user_id,role,is_admin) values($1,$2,$3,$4)',
      [id, member.user.id, member.role ?? 'adult_member', member.admin ?? false]);
    return id;
  }
  async function request(user, method, path, body) {
    const response = await fetch(base + '/v1' + path, { method, headers: { 'content-type': 'application/json',
      ...(user ? { authorization: `Bearer ${user.token}` } : {}) }, body: body === undefined ? undefined : JSON.stringify(body) });
    const raw = await response.text();
    return { status: response.status, body: raw && response.headers.get('content-type')?.includes('application/json') ? JSON.parse(raw) : raw || null };
  }
  const members = (user, id) => request(user, 'GET', `/families/${id}/members`);
  const role = (user, id, target, body) => request(user, 'PATCH', `/families/${id}/members/${target.id}/role`, body);
  const transfer = (user, id, body) => request(user, 'POST', `/families/${id}/admin-transfer`, body);
  const invitations = (user, id, query = '') => request(user, 'GET', `/families/${id}/invitations${query}`);
  const revoke = (user, id, invitationId, body) => request(user, 'PATCH', `/families/${id}/invitations/${invitationId}`, body);
  const accept = (user, token) => request(user, 'POST', '/invitations/accept', { token });
  async function member(id, user) {
    return (await pool.query('select user_id,role,is_admin,version,ended_at from family_membership where family_id=$1 and user_id=$2', [id, user.id])).rows[0];
  }
  async function invite(admin, id, recipient, intendedRole = 'adult_member') {
    const result = await request(admin, 'POST', `/families/${id}/invitations`, { email: recipient.email, role: intendedRole });
    assert.equal(result.status, 201, JSON.stringify(result.body)); return result.body;
  }
  async function blockedOn(client, minimum = 1) {
    const pid = (await client.query('select pg_backend_pid() pid')).rows[0].pid, deadline = Date.now() + 5000;
    while (Date.now() < deadline) {
      const result = await pool.query(`with recursive waits as (
        select pid from pg_stat_activity where $2=any(pg_blocking_pids(pid))
        union select a.pid from pg_stat_activity a join waits w on w.pid=any(pg_blocking_pids(a.pid))
      ) select count(*)::int n from pg_stat_activity a join waits w on w.pid=a.pid
        where a.application_name=$1`, [applicationName, pid]);
      if (result.rows[0].n >= minimum) return;
      await new Promise(resolve => setTimeout(resolve, 15));
    }
    assert.fail('API did not reach the observed PostgreSQL lock wait');
  }
  async function withFamilyBlocked(id, action) {
    const blocker = await pool.connect();
    try {
      await blocker.query('begin'); await blocker.query('select id from family_workspace where id=$1 for update', [id]);
      await action(blocker);
    } finally { await blocker.query('rollback').catch(() => {}); blocker.release(); }
  }

  test('current explicit administrator, not family role, profile type or JWT claims, controls every lifecycle route', async () => {
    const owner = await actor(), parent = await actor({ claims: { is_admin: true, role: 'admin' } }),
      child = await actor({ category: 'adult' }), outsider = await actor();
    const id = await family(owner, [{ user: parent, role: 'parent_guardian' }, { user: child, role: 'teen_minor' }]);
    const foreign = await family(outsider), recipient = await actor(), invitation = await invite(owner, id, recipient);
    for (const unauthorized of [parent, child, outsider, null]) {
      const expected = unauthorized ? 403 : 401;
      assert.equal((await invitations(unauthorized, id)).status, expected);
      assert.equal((await role(unauthorized, id, parent, { mutationId: uuid(), expectedVersion: 1, role: 'adult_member' })).status, expected);
      assert.equal((await transfer(unauthorized, id, { mutationId: uuid(), targetUserId: parent.id, expectedVersion: 1, expectedActorVersion: 1 })).status, expected);
      assert.equal((await revoke(unauthorized, id, invitation.id, { mutationId: uuid(), expectedVersion: 1, action: 'revoke' })).status, expected);
    }
    assert.equal((await invitations(owner, foreign)).status, 403);
    for (const path of [`/families/${id}/invitations?limit=0`, `/families/${id}/invitations?limit=1.5`,
      `/families/${id}/invitations?limit=1&limit=2`, `/families/${id}/invitations?cursor=bad`, `/families/${id}/invitations?email=x`])
      assert.equal((await request(owner, 'GET', path)).status, 400);
    assert.equal((await role(owner, id, parent, { mutationId: uuid(), expectedVersion: 1, role: 'adult_member', isAdmin: true })).status, 400);
    assert.equal((await transfer(owner, id, { mutationId: uuid(), targetUserId: parent.id, expectedVersion: 1, expectedActorVersion: 1, ownerUserId: outsider.id })).status, 400);
    assert.equal((await revoke(owner, id, invitation.id, { mutationId: uuid(), expectedVersion: 1, action: 'accept' })).status, 400);
  });

  test('administrator invitation pagination masks contact and never leaks bearer token or digest', async () => {
    const owner = await actor(), id = await family(owner), recipients = await Promise.all([actor(), actor(), actor()]);
    const rows = [];
    for (const recipient of recipients) rows.push(await invite(owner, id, recipient));
    const listed = await invitations(owner, id, '?limit=2'); assert.equal(listed.status, 200);
    assert.equal(listed.body.total, 3); assert.equal(listed.body.invitations.length, 2); assert.ok(listed.body.nextCursor);
    const serialized = JSON.stringify(listed.body);
    for (const recipient of recipients) assert.ok(!serialized.includes(recipient.email));
    for (const row of rows) {
      assert.ok(!serialized.includes(row.invitationToken));
      assert.ok(!serialized.includes(crypto.createHash('sha256').update(row.invitationToken).digest('hex')));
    }
    const next = await invitations(owner, id, `?limit=2&cursor=${listed.body.nextCursor}`);
    assert.equal(next.body.invitations.length, 1); assert.equal(next.body.nextCursor, null);
    assert.equal(new Set([...listed.body.invitations, ...next.body.invitations].map(row => row.id)).size, 3);
    assert.ok(listed.body.invitations.every(row => row.version === 1 && row.recipientHint === '***@example.test'));
    assert.equal((await invitations(owner, id, `?cursor=${uuid()}`)).status, 404);
  });

  test('role CAS increments one version, stable receipt survives API restart and rejects changed intent', async () => {
    const owner = await actor(), target = await actor(), id = await family(owner, [{ user: target, role: 'parent_guardian' }]);
    assert.equal((await members(owner, id)).body.members.find(row => row.user_id === target.id).version, 1);
    const mutation = { mutationId: uuid(), expectedVersion: 1, role: 'adult_member' };
    const first = await role(owner, id, target, mutation);
    assert.equal(first.status, 200); assert.equal(first.body.members[0].version, 2); assert.equal(first.body.members[0].role, 'adult_member');
    assert.equal(first.body.acknowledgement.status, 'accepted');
    await stop(); await start();
    const replay = await role(owner, id, target, mutation); assert.equal(replay.status, 200);
    assert.equal(replay.body.acknowledgement.status, 'already_applied'); assert.equal(replay.body.members[0].version, 2);
    assert.equal((await role(owner, id, target, { ...mutation, role: 'teen_minor' })).status, 409);
    assert.equal((await role(owner, id, target, { mutationId: uuid(), expectedVersion: 1, role: 'parent_guardian' })).body.error, 'membership_version_conflict');
    const second = { mutationId: uuid(), expectedVersion: 2, role: 'parent_guardian' };
    assert.equal((await role(owner, id, target, second)).body.members[0].version, 3);
    assert.equal((await role(owner, id, target, mutation)).body.members[0].version, 3, 'Retry returns current state, not obsolete role');
    assert.equal((await member(id, target)).role, 'parent_guardian');
    assert.equal((await pool.query('select count(*)::int n from family_lifecycle_mutation where actor_user_id=$1 and family_id=$2', [owner.id, id])).rows[0].n, 2);
    assert.equal((await pool.query("select count(*)::int n from access_audit where actor_user_id=$1 and action='family.lifecycle.role'", [owner.id])).rows[0].n, 2);
  });

  test('known minors cannot take adult roles or administration; unknown legacy adult can receive explicit transfer', async () => {
    const owner = await actor(), teen = await actor({ category: 'adult' }),
      minorAdult = await actor({ birthDate: '2020-01-01', category: 'adult' }), adultTeen = await actor({ birthDate: '1990-01-01', category: 'girl_minor' }),
      legacyAdult = await actor({ category: 'boy_minor' });
    const id = await family(owner, [{ user: teen, role: 'teen_minor' }, { user: minorAdult },
      { user: adultTeen, role: 'teen_minor' }, { user: legacyAdult }]);
    assert.equal((await role(owner, id, teen, { mutationId: uuid(), expectedVersion: 1, role: 'adult_member' })).body.error, 'age_confirmation_required');
    assert.equal((await role(owner, id, minorAdult, { mutationId: uuid(), expectedVersion: 1, role: 'parent_guardian' })).body.error, 'minor_role_upgrade_forbidden');
    for (const target of [teen, minorAdult]) assert.equal((await transfer(owner, id, {
      mutationId: uuid(), targetUserId: target.id, expectedVersion: 1, expectedActorVersion: 1 })).body.error, 'minor_cannot_admin');
    assert.equal((await role(owner, id, adultTeen, { mutationId: uuid(), expectedVersion: 1, role: 'adult_member' })).status, 200);
    assert.equal((await role(owner, id, owner, { mutationId: uuid(), expectedVersion: 1, role: 'teen_minor' })).body.error, 'minor_cannot_admin');
    assert.equal((await transfer(owner, id, { mutationId: uuid(), targetUserId: legacyAdult.id, expectedVersion: 1, expectedActorVersion: 1 })).status, 200);
    assert.equal((await member(id, legacyAdult)).is_admin, true);
    assert.equal((await pool.query('select profile_category from profile where user_id=$1', [legacyAdult.id])).rows[0].profile_category, 'boy_minor', 'Profile category is not silently rewritten by family authority');
  });

  test('family creation denies known minors while profile category itself does not infer administrative age', async () => {
    const knownMinor = await actor({ birthDate: '2020-01-01', category: 'adult' });
    const rejected = await request(knownMinor, 'POST', '/families', { name: 'Synthetic denied family', role: 'parent_guardian' });
    assert.equal(rejected.status, 403); assert.equal(rejected.body.error, 'minor_cannot_admin');
    assert.equal((await pool.query('select count(*)::int n from family_workspace where created_by=$1', [knownMinor.id])).rows[0].n, 0);
    for (const options of [{ birthDate: '1990-01-01', category: 'girl_minor' }, { category: 'boy_minor' }]) {
      const creator = await actor(options), created = await request(creator, 'POST', '/families', { name: 'Synthetic allowed family', role: 'adult_member' });
      if (created.status === 201) families.push(created.body.id);
      assert.equal(created.status, 201, 'Explicit adult date or legacy unknown adult is not rejected by a UI profile category');
      assert.equal((await member(created.body.id, creator)).is_admin, true);
    }
  });

  test('new family creation cannot bypass unknown-age teen membership through an adult-looking profile', async () => {
    const owner = await actor(), teen = await actor({ category: 'adult' });
    await family(owner, [{ user: teen, role: 'teen_minor' }]);
    const rejected = await request(teen, 'POST', '/families', { name: 'Synthetic age bypass attempt', role: 'adult_member' });
    if (rejected.status === 201) families.push(rejected.body.id);
    assert.equal(rejected.status, 403); assert.equal(rejected.body.error, 'age_confirmation_required');
    assert.equal((await pool.query('select count(*)::int n from family_workspace where created_by=$1', [teen.id])).rows[0].n, 0);
  });

  test('new family admin age derives from locked fresh profile after account-row wait', async () => {
    const creator = await actor({ birthDate: '1990-01-01' }), blocker = await pool.connect(); let pending;
    try {
      await blocker.query('begin'); await blocker.query('select id from app_user where id=$1 for update', [creator.id]);
      await blocker.query('select user_id from profile where user_id=$1 for update', [creator.id]);
      pending = request(creator, 'POST', '/families', { name: 'Synthetic age correction race' });
      await blockedOn(blocker);
      await blocker.query("update profile set birth_date='2020-01-01' where user_id=$1", [creator.id]);
      await blocker.query('commit'); const response = await pending;
      if (response.status === 201) families.push(response.body.id);
      assert.equal(response.status, 403); assert.equal(response.body.error, 'minor_cannot_admin');
    } finally { await blocker.query('rollback').catch(() => {}); blocker.release(); if (pending) await pending.catch(() => {}); }
    assert.equal((await pool.query('select count(*)::int n from family_workspace where created_by=$1', [creator.id])).rows[0].n, 0);
  });

  test('invitation acceptance cannot assign known minors adult or guardian roles and leaves the invitation recoverable', async () => {
    const owner = await actor(), id = await family(owner);
    for (const intendedRole of ['adult_member', 'parent_guardian']) {
      const recipient = await actor({ birthDate: '2020-01-01', category: 'adult' }), invitation = await invite(owner, id, recipient, intendedRole);
      const rejected = await accept(recipient, invitation.invitationToken);
      assert.equal(rejected.status, 403); assert.equal(rejected.body.error, 'minor_role_upgrade_forbidden');
      assert.equal(await member(id, recipient), undefined);
      assert.equal((await pool.query('select status,accepted_by,version from family_invitation where id=$1', [invitation.id])).rows[0].status, 'pending');
      assert.equal((await pool.query("select count(*)::int n from access_audit where actor_user_id=$1 and action='invitation.accept'", [recipient.id])).rows[0].n, 0);
      assert.equal((await pool.query('select profile_category,theme_preference from profile where user_id=$1', [recipient.id])).rows[0].profile_category, 'adult');
      const correction = await invite(owner, id, recipient, 'teen_minor');
      assert.equal((await accept(recipient, correction.invitationToken)).status, 204);
      assert.equal((await member(id, recipient)).role, 'teen_minor');
      const activeConflict = await accept(recipient, invitation.invitationToken);
      assert.equal(activeConflict.status, 409); assert.equal(activeConflict.body.error, 'member_already_active');
      assert.equal((await member(id, recipient)).role, 'teen_minor');
      assert.equal((await pool.query('select status from family_invitation where id=$1', [invitation.id])).rows[0].status, 'pending');
    }
  });

  test('invitation adult role requires age confirmation for an active unknown-age teen in another family', async () => {
    const owner = await actor(), teen = await actor({ category: 'adult' }), existing = await family(owner, [{ user: teen, role: 'teen_minor' }]);
    const newOwner = await actor(), target = await family(newOwner);
    for (const intendedRole of ['adult_member', 'parent_guardian']) {
      const invitation = await invite(newOwner, target, teen, intendedRole), rejected = await accept(teen, invitation.invitationToken);
      assert.equal(rejected.status, 403); assert.equal(rejected.body.error, 'age_confirmation_required');
      assert.equal(await member(target, teen), undefined); assert.equal((await member(existing, teen)).role, 'teen_minor');
      assert.equal((await pool.query('select status from family_invitation where id=$1', [invitation.id])).rows[0].status, 'pending');
    }
    const correction = await invite(newOwner, target, teen, 'teen_minor');
    assert.equal((await accept(teen, correction.invitationToken)).status, 204);
    assert.equal((await member(target, teen)).role, 'teen_minor');
  });

  test('invitation age checks use birth date and current teen membership rather than profile category', async () => {
    const owner = await actor(), id = await family(owner);
    for (const options of [{ birthDate: '1990-01-01', category: 'girl_minor' }, { category: 'boy_minor' }]) {
      const recipient = await actor(options), invitation = await invite(owner, id, recipient, 'parent_guardian');
      assert.equal((await accept(recipient, invitation.invitationToken)).status, 204);
      assert.equal((await member(id, recipient)).role, 'parent_guardian');
      assert.equal((await pool.query('select profile_category from profile where user_id=$1', [recipient.id])).rows[0].profile_category, options.category);
    }
    const adultFormerTeen = await actor({ birthDate: '1990-01-01', category: 'girl_minor' });
    await family(owner, [{ user: adultFormerTeen, role: 'teen_minor' }]);
    const invitation = await invite(owner, id, adultFormerTeen, 'adult_member');
    assert.equal((await accept(adultFormerTeen, invitation.invitationToken)).status, 204);
    assert.equal((await member(id, adultFormerTeen)).role, 'adult_member');
  });

  test('invitation acceptance waits for editable birth date and rejects a newly known minor before membership', async () => {
    const owner = await actor(), recipient = await actor({ birthDate: '1990-01-01' }), id = await family(owner),
      invitation = await invite(owner, id, recipient, 'parent_guardian'), blocker = await pool.connect(); let pending;
    try {
      await blocker.query('begin'); await blocker.query('select user_id from profile where user_id=$1 for update', [recipient.id]);
      pending = accept(recipient, invitation.invitationToken); await blockedOn(blocker);
      await blocker.query("update profile set birth_date='2020-01-01' where user_id=$1", [recipient.id]);
      await blocker.query('commit'); const rejected = await pending;
      assert.equal(rejected.status, 403); assert.equal(rejected.body.error, 'minor_role_upgrade_forbidden');
    } finally { await blocker.query('rollback').catch(() => {}); blocker.release(); if (pending) await pending.catch(() => {}); }
    assert.equal(await member(id, recipient), undefined);
    assert.equal((await pool.query('select status from family_invitation where id=$1', [invitation.id])).rows[0].status, 'pending');
  });

  test('atomic transfer preserves administrator, revokes old pending invitations and only exact old retry bypasses new-admin check', async () => {
    const owner = await actor(), target = await actor(), recipient = await actor(), id = await family(owner, [{ user: target }]);
    const invitation = await invite(owner, id, recipient), mutation = { mutationId: uuid(), targetUserId: target.id, expectedVersion: 1, expectedActorVersion: 1 };
    const first = await transfer(owner, id, mutation); assert.equal(first.status, 200);
    assert.deepEqual(first.body.members.map(row => [row.userId, row.isAdmin, row.version]), [[owner.id, false, 2], [target.id, true, 2]]);
    assert.equal((await pool.query('select status,version from family_invitation where id=$1', [invitation.id])).rows[0].status, 'revoked');
    assert.equal((await accept(recipient, invitation.invitationToken)).status, 400);
    assert.equal((await invitations(owner, id)).status, 403);
    assert.equal((await role(owner, id, target, { mutationId: uuid(), expectedVersion: 2, role: 'parent_guardian' })).status, 403);
    const replay = await transfer(owner, id, mutation); assert.equal(replay.status, 200); assert.equal(replay.body.acknowledgement.status, 'already_applied');
    assert.equal((await transfer(owner, id, { ...mutation, expectedVersion: 2 })).body.error, 'mutation_id_reused');
    assert.equal((await transfer(target, id, { mutationId: uuid(), targetUserId: owner.id, expectedVersion: 2, expectedActorVersion: 2 })).status, 200);
    assert.equal((await accept(recipient, invitation.invitationToken)).status, 400, 'Transfer back must not revive old invitation');
    assert.equal((await transfer(owner, id, mutation)).body.members.find(row => row.userId === target.id).isAdmin, false, 'Exact old retry reports current authority');
    assert.equal((await request(owner, 'DELETE', `/families/${id}/members/${owner.id}`)).body.error, 'last_admin_required');
  });

  test('concurrent transfer/role CAS keeps one administrator and one accepted version', async () => {
    const owner = await actor(), first = await actor(), second = await actor(), id = await family(owner, [{ user: first }, { user: second }]);
    const results = await Promise.all([first, second].map(target => transfer(owner, id, {
      mutationId: uuid(), targetUserId: target.id, expectedVersion: 1, expectedActorVersion: 1 })));
    assert.deepEqual(results.map(result => result.status).sort(), [200, 403]);
    const active = (await pool.query('select user_id from family_membership where family_id=$1 and ended_at is null and is_admin', [id])).rows;
    assert.equal(active.length, 1); assert.notEqual(active[0].user_id, owner.id);
    const newAdmin = active[0].user_id === first.id ? first : second, target = newAdmin === first ? second : first;
    const writes = await Promise.all(['parent_guardian', 'teen_minor'].map(newRole => role(newAdmin, id, target, {
      mutationId: uuid(), expectedVersion: 1, role: newRole })));
    assert.deepEqual(writes.map(result => result.status).sort(), [200, 409]);
    assert.equal((await member(id, target)).version, 2);
  });

  test('role changes revoke affected guardian/selected sharing; reversal or removal/rejoin never resurrects access', async () => {
    const owner = await actor(), parent = await actor(), child = await actor({ birthDate: '1990-01-01', category: 'girl_minor' });
    const id = await family(owner, [{ user: parent, role: 'parent_guardian' }, { user: child, role: 'teen_minor' }]);
    await pool.query('insert into guardian_relationship(family_id,guardian_user_id,minor_user_id) values($1,$2,$3)', [id, parent.id, child.id]);
    const task = await request(child, 'POST', '/plan-items', { title: 'Synthetic selected task', kind: 'assignment', familyId: id,
      visibility: 'selected_members', selectedMemberIds: [parent.id], notes: 'SYNTHETIC-PRIVATE-NOTE' });
    assert.equal(task.status, 201, JSON.stringify(task.body));
    // Verify a real grant independently; some legacy clients omit the grant list.
    await pool.query("insert into sharing_grant(resource_type,resource_id,grantee_user_id,granted_by) values('plan_item',$1,$2,$3) on conflict do nothing", [task.body.id, parent.id, child.id]);
    assert.equal((await request(parent, 'GET', `/plan-items/${task.body.id}`)).status, 200);
    assert.equal((await role(owner, id, parent, { mutationId: uuid(), expectedVersion: 1, role: 'adult_member' })).status, 200);
    assert.equal((await pool.query('select active from guardian_relationship where family_id=$1 and guardian_user_id=$2', [id, parent.id])).rows[0].active, false);
    assert.equal((await pool.query('select count(*)::int n from sharing_grant where resource_id=$1', [task.body.id])).rows[0].n, 0);
    assert.equal((await role(owner, id, parent, { mutationId: uuid(), expectedVersion: 2, role: 'parent_guardian' })).status, 200);
    assert.equal((await request(parent, 'GET', `/plan-items/${task.body.id}`)).status, 404);
    await pool.query("insert into sharing_grant(resource_type,resource_id,grantee_user_id,granted_by) values('plan_item',$1,$2,$3)", [task.body.id, parent.id, child.id]);
    assert.equal((await request(owner, 'DELETE', `/families/${id}/members/${parent.id}`)).status, 204);
    const invitation = await invite(owner, id, parent, 'parent_guardian'); assert.equal((await accept(parent, invitation.invitationToken)).status, 204);
    assert.equal((await member(id, parent)).version, 5, 'Legacy end and rejoin revisions are tracked');
    assert.equal((await request(parent, 'GET', `/plan-items/${task.body.id}`)).status, 404);
    assert.equal((await pool.query('select active from guardian_relationship where family_id=$1 and guardian_user_id=$2', [id, parent.id])).rows[0].active, false);
    const progress = (await pool.query('select profile_category from profile where user_id=$1', [child.id])).rows[0];
    assert.equal(progress.profile_category, 'girl_minor');
  });

  test('inactive target, disabled target and archived family reject new mutations; removal prevents historical retry', async () => {
    const owner = await actor(), target = await actor(), id = await family(owner, [{ user: target }]);
    const mutation = { mutationId: uuid(), expectedVersion: 1, role: 'parent_guardian' };
    await pool.query('update app_user set disabled_at=now() where id=$1', [target.id]);
    assert.equal((await role(owner, id, target, mutation)).body.error, 'member_not_active');
    assert.equal((await transfer(owner, id, { mutationId: uuid(), targetUserId: target.id, expectedVersion: 1, expectedActorVersion: 1 })).body.error, 'member_not_active');
    await pool.query('update app_user set disabled_at=null where id=$1', [target.id]);
    assert.equal((await role(owner, id, target, mutation)).status, 200);
    assert.equal((await request(owner, 'DELETE', `/families/${id}/members/${target.id}`)).status, 204);
    assert.equal((await role(owner, id, target, { mutationId: uuid(), expectedVersion: 3, role: 'adult_member' })).body.error, 'member_not_active');
    assert.equal((await request(owner, 'DELETE', `/families/${id}`)).status, 204);
    assert.equal((await role(owner, id, target, mutation)).status, 403);
    assert.equal((await invitations(owner, id)).status, 403);
  });

  test('invitation revoke receipt persists, returns current state and rejects concurrent accept without contact/token disclosure', async () => {
    const owner = await actor(), recipient = await actor(), id = await family(owner), invitation = await invite(owner, id, recipient);
    const mutation = { mutationId: uuid(), expectedVersion: 1, action: 'revoke' };
    const result = await revoke(owner, id, invitation.id, mutation); assert.equal(result.status, 200);
    assert.equal(result.body.invitation.status, 'revoked'); assert.equal(result.body.invitation.version, 2);
    assert.ok(!JSON.stringify(result.body).includes(recipient.email)); assert.ok(!JSON.stringify(result.body).includes(invitation.invitationToken));
    assert.equal((await accept(recipient, invitation.invitationToken)).status, 400);
    await stop(); await start();
    const replay = await revoke(owner, id, invitation.id, mutation); assert.equal(replay.status, 200);
    assert.equal(replay.body.acknowledgement.status, 'already_applied'); assert.equal(replay.body.invitation.version, 2);
    assert.equal((await revoke(owner, id, invitation.id, { ...mutation, expectedVersion: 2 })).body.error, 'mutation_id_reused');
    assert.equal((await revoke(owner, id, invitation.id, { mutationId: uuid(), expectedVersion: 2, action: 'revoke' })).body.error, 'invitation_not_pending');
    assert.equal((await invitations(owner, id)).body.total, 0);
  });

  test('invitation expiry is rechecked after an observed family-row wait, not frozen transaction time', async () => {
    const owner = await actor(), recipient = await actor(), id = await family(owner), invitation = await invite(owner, id, recipient);
    await pool.query("update family_invitation set created_at=now()-interval '1 minute' where id=$1", [invitation.id]);
    await withFamilyBlocked(id, async blocker => {
      const pending = accept(recipient, invitation.invitationToken); await blockedOn(blocker);
      await blocker.query("update family_invitation set expires_at=statement_timestamp()-interval '1 millisecond' where id=$1", [invitation.id]);
      await blocker.query('commit');
      assert.equal((await pending).status, 400, 'Expired invitation must not commit membership after lock wait');
    });
    assert.equal((await pool.query('select count(*)::int n from family_membership where family_id=$1 and user_id=$2', [id, recipient.id])).rows[0].n, 0);
    assert.equal((await invitations(owner, id)).body.invitations[0].status, 'expired');
  });

  test('acceptance waiting behind revoke sees committed revocation and creates no membership', async () => {
    const owner = await actor(), recipient = await actor(), id = await family(owner), invitation = await invite(owner, id, recipient);
    await withFamilyBlocked(id, async blocker => {
      const pending = accept(recipient, invitation.invitationToken); await blockedOn(blocker);
      await blocker.query("update family_invitation set status='revoked' where id=$1", [invitation.id]);
      await blocker.query('commit'); assert.equal((await pending).status, 400);
    });
    assert.equal((await pool.query('select count(*)::int n from family_membership where family_id=$1 and user_id=$2', [id, recipient.id])).rows[0].n, 0);
  });

  test('role/transfer/revoke reject session expiry or revocation that occurs during an observed family lock wait', async () => {
    for (const operation of ['role', 'transfer', 'revoke']) {
      for (const invalidation of ['expiry', 'revocation']) {
        const owner = await actor(), target = await actor(), id = await family(owner, [{ user: target }]),
          invitation = operation === 'revoke' ? await invite(owner, id, await actor()) : null;
        await withFamilyBlocked(id, async blocker => {
          const pending = operation === 'role' ? role(owner, id, target, { mutationId: uuid(), expectedVersion: 1, role: 'parent_guardian' }) :
            operation === 'transfer' ? transfer(owner, id, { mutationId: uuid(), targetUserId: target.id, expectedVersion: 1, expectedActorVersion: 1 }) :
              revoke(owner, id, invitation.id, { mutationId: uuid(), expectedVersion: 1, action: 'revoke' });
          await blockedOn(blocker);
          await blocker.query(invalidation === 'expiry' ? "update auth_session set expires_at=statement_timestamp()-interval '1 millisecond' where id=$1" :
            'update auth_session set revoked_at=statement_timestamp() where id=$1', [owner.sid]);
          await blocker.query('commit'); assert.equal((await pending).status, 401, `${operation}/${invalidation}`);
        });
        assert.equal((await member(id, target)).version, 1);
        assert.equal((await pool.query('select count(*)::int n from family_lifecycle_mutation where actor_user_id=$1', [owner.id])).rows[0].n, 0);
        if (invitation) assert.equal((await pool.query('select status from family_invitation where id=$1', [invitation.id])).rows[0].status, 'pending');
      }
    }
  });

  test('legacy invitation acceptance and membership removal roll back session expiry during observed lock wait', async () => {
    for (const operation of ['accept', 'remove']) {
      const owner = await actor(), recipient = await actor(), id = await family(owner, operation === 'remove' ? [{ user: recipient }] : []);
      const invitation = operation === 'accept' ? await invite(owner, id, recipient) : null, acting = operation === 'accept' ? recipient : owner;
      await withFamilyBlocked(id, async blocker => {
        const pending = operation === 'accept' ? accept(recipient, invitation.invitationToken) : request(owner, 'DELETE', `/families/${id}/members/${recipient.id}`);
        await blockedOn(blocker);
        await blocker.query("update auth_session set expires_at=statement_timestamp()-interval '1 millisecond' where id=$1", [acting.sid]);
        await blocker.query('commit'); assert.equal((await pending).status, 401, `${operation}: expired session must not commit`);
      });
      const record = await member(id, recipient);
      assert.ok(operation === 'accept' ? !record : record.ended_at === null);
    }
  });

  test('JWT expiry during an observed family-row wait rolls back an otherwise active session', async () => {
    const owner = await actor(), target = await actor(), id = await family(owner, [{ user: target }]);
    const expiration = Math.floor(Date.now() / 1000) + 2;
    owner.token = jwt.sign({ sub: owner.id, sid: owner.sid, aud: 'lifemate-api', exp: expiration }, secret, { issuer: 'lifemate' });
    await withFamilyBlocked(id, async blocker => {
      const pending = role(owner, id, target, { mutationId: uuid(), expectedVersion: 1, role: 'parent_guardian' });
      await blockedOn(blocker);
      const deadline = Date.now() + 4000;
      while (Date.now() < deadline) {
        if ((await blocker.query('select statement_timestamp()>=to_timestamp($1) expired', [expiration])).rows[0].expired) break;
        await new Promise(resolve => setTimeout(resolve, 15));
      }
      assert.equal((await blocker.query('select statement_timestamp()>=to_timestamp($1) expired', [expiration])).rows[0].expired, true);
      await blocker.query('commit'); assert.equal((await pending).status, 401);
    });
    assert.equal((await member(id, target)).version, 1);
  });

  test('final session-row lock serializes logout and uses fresh time after a session-row wait', async () => {
    for (const invalidation of ['expiry', 'revocation']) {
      const owner = await actor(), target = await actor(), id = await family(owner, [{ user: target }]), blocker = await pool.connect();
      try {
        await blocker.query('begin'); await blocker.query('select id from auth_session where id=$1 for update', [owner.sid]);
        const pending = role(owner, id, target, { mutationId: uuid(), expectedVersion: 1, role: 'parent_guardian' });
        await blockedOn(blocker);
        await blocker.query(invalidation === 'expiry' ? "update auth_session set expires_at=statement_timestamp()-interval '1 millisecond' where id=$1" :
          'update auth_session set revoked_at=statement_timestamp() where id=$1', [owner.sid]);
        await blocker.query('commit'); assert.equal((await pending).status, 401);
      } finally { await blocker.query('rollback').catch(() => {}); blocker.release(); }
      assert.equal((await member(id, target)).version, 1, 'Even earlier writes must roll back at the final session gate');
      assert.equal((await pool.query('select count(*)::int n from family_lifecycle_mutation where actor_user_id=$1', [owner.id])).rows[0].n, 0);
    }
  });

  test('legacy family helper, invitation acceptance and family creation reject expiry after their final session-row wait', async () => {
    for (const operation of ['rename', 'accept', 'create']) {
      const owner = await actor(), recipient = await actor(), id = operation === 'create' ? null : await family(owner),
        invitation = operation === 'accept' ? await invite(owner, id, recipient) : null,
        acting = operation === 'accept' ? recipient : owner, blocker = await pool.connect();
      try {
        await blocker.query('begin'); await blocker.query('select id from auth_session where id=$1 for update', [acting.sid]);
        const pending = operation === 'rename' ? request(owner, 'PATCH', `/families/${id}`, { name: 'Expired mutation' }) :
          operation === 'accept' ? accept(recipient, invitation.invitationToken) : request(owner, 'POST', '/families', { name: 'Expired new family' });
        await blockedOn(blocker);
        await blocker.query("update auth_session set expires_at=statement_timestamp()-interval '1 millisecond' where id=$1", [acting.sid]);
        await blocker.query('commit'); const response = await pending;
        if (operation === 'create' && response.status === 201) families.push(response.body.id);
        assert.equal(response.status, 401, `${operation}: initial valid session must not authorize a write after final row wait expiry`);
      } finally { await blocker.query('rollback').catch(() => {}); blocker.release(); }
      if (operation === 'rename') assert.equal((await pool.query('select name from family_workspace where id=$1', [id])).rows[0].name, 'Synthetic Lifecycle Family');
      if (operation === 'accept') {
        assert.equal(await member(id, recipient), undefined);
        assert.equal((await pool.query('select status from family_invitation where id=$1', [invitation.id])).rows[0].status, 'pending');
      }
      if (operation === 'create') assert.equal((await pool.query('select count(*)::int n from family_workspace where created_by=$1', [owner.id])).rows[0].n, 0);
    }
  });

  test('admin transfer waits for concurrent editable birth date and denies newly known minor context', async () => {
    const owner = await actor(), target = await actor({ birthDate: '1990-01-01' }), id = await family(owner, [{ user: target }]), blocker = await pool.connect();
    try {
      await blocker.query('begin'); await blocker.query('select user_id from profile where user_id=$1 for update', [target.id]);
      const pending = transfer(owner, id, { mutationId: uuid(), targetUserId: target.id, expectedVersion: 1, expectedActorVersion: 1 });
      await blockedOn(blocker);
      await blocker.query("update profile set birth_date='2020-01-01' where user_id=$1", [target.id]);
      await blocker.query('commit'); assert.equal((await pending).body.error, 'minor_cannot_admin');
    } finally { await blocker.query('rollback').catch(() => {}); blocker.release(); }
    assert.equal((await member(id, owner)).is_admin, true); assert.equal((await member(id, target)).version, 1);
  });

  test('active admin authority is rechecked after an observed lock wait, and transfer/removal cannot remove the last admin', async () => {
    const owner = await actor(), successor = await actor(), target = await actor(), id = await family(owner, [{ user: successor, admin: true }, { user: target }]);
    await withFamilyBlocked(id, async blocker => {
      const pending = role(owner, id, target, { mutationId: uuid(), expectedVersion: 1, role: 'parent_guardian' }); await blockedOn(blocker);
      await blocker.query('update family_membership set is_admin=false where family_id=$1 and user_id=$2', [id, owner.id]);
      await blocker.query('commit'); assert.equal((await pending).status, 403);
    });
    const results = await Promise.all([
      transfer(successor, id, { mutationId: uuid(), targetUserId: target.id, expectedVersion: 1, expectedActorVersion: 1 }),
      request(successor, 'DELETE', `/families/${id}/members/${successor.id}`),
    ]);
    assert.equal(results[0].status, 200);
    assert.ok([403, 409].includes(results[1].status));
    assert.equal((await pool.query('select count(*)::int n from family_membership m join app_user u on u.id=m.user_id where m.family_id=$1 and m.is_admin and m.ended_at is null and u.disabled_at is null', [id])).rows[0].n, 1);
  });

  test('cross-family reciprocal writes lock participating accounts in a stable order without deadlock', async () => {
    const pair = (await Promise.all([actor(), actor()])).sort((a, b) => a.id.localeCompare(b.id));
    const [low, high] = pair;
    const first = await family(high, [{ user: low, role: 'parent_guardian', admin: true }]);
    const second = await family(low, [{ user: high, role: 'parent_guardian', admin: true }]);
    const blocker = await pool.connect(); let writes = [];
    try {
      await blocker.query('begin'); await blocker.query('select id from app_user where id=$1 for update', [low.id]);
      await blocker.query('savepoint high_lock'); await blocker.query('select id from app_user where id=$1 for update', [high.id]);
      writes = [role(high, first, low, { mutationId: uuid(), expectedVersion: 1, role: 'adult_member' }),
        role(low, second, high, { mutationId: uuid(), expectedVersion: 1, role: 'adult_member' })];
      await blockedOn(blocker, 2); await blocker.query('rollback to savepoint high_lock');
      await blockedOn(blocker, 2); // Both must now wait for low, without retaining a higher account lock.
      await blocker.query('commit');
      const result = await Promise.all(writes); assert.deepEqual(result.map(row => row.status), [200, 200]);
      assert.equal((await member(first, low)).version, 2); assert.equal((await member(second, high)).version, 2);
    } finally { await blocker.query('rollback').catch(() => {}); blocker.release(); await Promise.allSettled(writes); }
  });
});
