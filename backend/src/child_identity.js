import crypto from 'node:crypto';
import express from 'express';
import jwt from 'jsonwebtoken';

export const SANDBOX_CONSENT_VERSION = 'sandbox-child-consent-v1-not-legal';
export const SANDBOX_CONSENT_TEXT = 'SYNTHETIC TEST ONLY: I confirm these are invented test identities. This is not legal consent and authorizes no real child data, deployment or private-data access.';
export const SANDBOX_CONSENT_DIGEST = crypto.createHash('sha256').update(SANDBOX_CONSENT_TEXT).digest('hex');
const digest = value => crypto.createHash('sha256').update(value).digest('hex');
const token = () => crypto.randomBytes(32).toString('base64url');
const uuid = value => typeof value === 'string' && /^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/i.test(value);
const exact = (body, fields) => body && typeof body === 'object' && !Array.isArray(body) && Object.keys(body).every(key => fields.includes(key));
const bodyToken = body => exact(body, ['token']) && typeof body.token === 'string' && /^[A-Za-z0-9_-]{43}$/.test(body.token);
const failure = (status, error) => ({ status, body: { error } });
const invalidInvitation = () => failure(400, 'invalid_or_expired_invitation');
const send = (res, result) => res.status(result.status).json(result.body);
const date = value => typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value) &&
  Number(value.slice(0, 4)) >= 1900 && Number.isFinite(Date.parse(value + 'T00:00:00.000Z')) &&
  new Date(value + 'T00:00:00.000Z').toISOString().slice(0, 10) === value;

async function sessionCurrent(client, identity, lock = false) {
  if (lock) await client.query('select id from auth_session where id=$1 and user_id=$2 for share', [identity.sid, identity.sub]);
  return (await client.query(`select 1 from auth_session s join app_user u on u.id=s.user_id
    where s.id=$1 and s.user_id=$2 and s.revoked_at is null and s.expires_at>clock_timestamp()
      and u.disabled_at is null and to_timestamp($3)>clock_timestamp()`, [identity.sid, identity.sub, identity.exp])).rowCount > 0;
}
async function transact(pool, identity, operation) {
  const client = await pool.connect();
  try {
    await client.query('begin');
    await client.query("set local lock_timeout='4s'");
    await client.query("set local statement_timeout='6s'");
    const result = await operation(client);
    if (identity && !await sessionCurrent(client, identity, true)) {
      await client.query('rollback'); return failure(401, 'session_invalid');
    }
    if (result.status >= 400) await client.query('rollback');
    else await client.query('commit');
    return result;
  } catch (error) {
    await client.query('rollback').catch(() => {});
    // SQL/constraint details may contain profile information. Never return them.
    if (['55P03', '57014', '40P01'].includes(error.code)) return failure(503, 'child_identity_busy');
    throw error;
  } finally { client.release(); }
}

async function context(client, familyId, participants) {
  const family = await client.query('select id from family_workspace where id=$1 and archived_at is null for update', [familyId]);
  if (!family.rowCount) return false;
  const ids = [...new Set(participants)].sort();
  // Stable order shared with family lifecycle: family, users, profiles,
  // memberships, managed child, consent, invitation, final actor session.
  await client.query('select id from app_user where id=any($1::uuid[]) order by id for update', [ids]);
  await client.query('select user_id from profile where user_id=any($1::uuid[]) order by user_id for update', [ids]);
  await client.query('select user_id from family_membership where family_id=$1 and user_id=any($2::uuid[]) order by user_id for update', [familyId, ids]);
  return true;
}
async function adultParent(client, familyId, userId, { admin = false } = {}) {
  return (await client.query(`select 1 from family_membership m join app_user u on u.id=m.user_id
    join profile p on p.user_id=m.user_id where m.family_id=$1 and m.user_id=$2
      and m.ended_at is null and m.role='parent_guardian' and (not $3::boolean or m.is_admin)
      and u.disabled_at is null and not u.is_managed_child and p.birth_date is not null
      and p.birth_date<=(current_date-interval '18 years')::date`, [familyId, userId, admin])).rowCount > 0;
}
async function activeChild(client, familyId, childId) {
  await client.query('select user_id from managed_child where family_id=$1 and user_id=$2 for update', [familyId, childId]);
  await client.query('select child_user_id from child_consent where child_user_id=$1 for update', [childId]);
  return (await client.query(`select mc.* from managed_child mc join app_user u on u.id=mc.user_id
    join profile p on p.user_id=mc.user_id join child_consent c on c.child_user_id=mc.user_id
    join family_membership m on m.family_id=mc.family_id and m.user_id=mc.user_id
    where mc.family_id=$1 and mc.user_id=$2 and u.is_managed_child and u.disabled_at is null
      and m.role='teen_minor' and not m.is_admin and m.ended_at is null and c.revoked_at is null
      and p.birth_date is not null and p.birth_date<=current_date
      and p.birth_date>(current_date-interval '18 years')::date
      and c.text_version=$3 and c.text_digest=$4`, [familyId, childId, SANDBOX_CONSENT_VERSION, SANDBOX_CONSENT_DIGEST])).rows[0];
}
async function guardian(client, familyId, guardianId, childId) {
  return await adultParent(client, familyId, guardianId) &&
    (await client.query('select is_active_guardian($1,$2,$3) active', [familyId, guardianId, childId])).rows[0].active;
}
async function audit(client, familyId, actorId, childId, action) {
  await client.query(`insert into access_audit(actor_user_id,family_id,action,target_type,target_id,metadata)
    values($1,$2,$3,'managed_child',$4,'{"synthetic":true}'::jsonb)`, [actorId, familyId, 'child.sandbox.' + action, childId]);
}
const validPath = req => uuid(req.params.familyId) && uuid(req.params.childId) && Object.keys(req.query).length === 0;

export function createChildIdentityRouter({ pool, auth, jwtSecret, env = process.env }) {
  const router = express.Router();
  // This router is mounted ahead of legacy /v1 routes. A use('/') gate would
  // disable unrelated APIs; gate only these explicit identity paths.
  const gate = (_req, res, next) => {
    res.set('Cache-Control', 'no-store');
    if (!['test', 'development'].includes(env.NODE_ENV) || env.ENABLE_CHILD_IDENTITY_SANDBOX !== 'true')
      return send(res, failure(503, 'child_identity_sandbox_disabled'));
    next();
  };
  router.post('/families/:familyId/children', gate, auth, async (req, res) => {
    const body = req.body;
    if (!uuid(req.params.familyId) || Object.keys(req.query).length || !exact(body,
      ['displayName', 'birthDate', 'profileCategory', 'consentVersion', 'consentAccepted', 'synthetic']) ||
      typeof body.displayName !== 'string' || body.displayName.trim().length < 1 || body.displayName.trim().length > 100 ||
      body.displayName.includes('\u0000') ||
      !date(body.birthDate) || !['girl_minor', 'boy_minor'].includes(body.profileCategory) || body.consentVersion !== SANDBOX_CONSENT_VERSION ||
      body.consentAccepted !== true || body.synthetic !== true) return send(res, failure(400, 'invalid_child_profile'));
    send(res, await transact(pool, req.identity, async client => {
      const age = (await client.query("select $1::date<=current_date and $1::date>(current_date-interval '18 years')::date valid", [body.birthDate])).rows[0].valid;
      if (!age) return failure(400, 'invalid_child_profile');
      if (!await context(client, req.params.familyId, [req.identity.sub])) return failure(403, 'forbidden');
      if (!await adultParent(client, req.params.familyId, req.identity.sub, { admin: true })) return failure(403, 'forbidden');
      const childId = crypto.randomUUID();
      await client.query('insert into app_user(id,identity_subject,is_managed_child) values($1,$2,true)', [childId, 'managed-child:' + childId]);
      await client.query('insert into profile(user_id,display_name,birth_date,profile_category,theme_preference) values($1,$2,$3,$4,$5)',
        [childId, body.displayName.trim(), body.birthDate, body.profileCategory, body.profileCategory === 'girl_minor' ? 'girl_pink' : 'boy_blue']);
      await client.query("insert into family_membership(family_id,user_id,role) values($1,$2,'teen_minor')", [req.params.familyId, childId]);
      await client.query('insert into managed_child(user_id,family_id,creator_user_id) values($1,$2,$3)', [childId, req.params.familyId, req.identity.sub]);
      await client.query('insert into child_consent(child_user_id,actor_user_id,text_version,text_digest) values($1,$2,$3,$4)',
        [childId, req.identity.sub, SANDBOX_CONSENT_VERSION, SANDBOX_CONSENT_DIGEST]);
      await client.query('insert into guardian_relationship(family_id,guardian_user_id,minor_user_id) values($1,$2,$3)', [req.params.familyId, req.identity.sub, childId]);
      await audit(client, req.params.familyId, req.identity.sub, childId, 'create');
      return { status: 201, body: { child: { userId: childId, familyId: req.params.familyId, displayName: body.displayName.trim(), profileCategory: body.profileCategory },
        consent: { version: SANDBOX_CONSENT_VERSION, digest: SANDBOX_CONSENT_DIGEST, synthetic: true } } };
    }));
  });

  router.post('/families/:familyId/children/:childId/device-invitations', gate, auth, async (req, res) => {
    if (!validPath(req) || !exact(req.body, ['synthetic']) || req.body.synthetic !== true) return send(res, failure(400, 'invalid_device_invitation'));
    const { familyId, childId } = req.params;
    send(res, await transact(pool, req.identity, async client => {
      if (!await context(client, familyId, [req.identity.sub, childId])) return failure(403, 'forbidden');
      if (!await activeChild(client, familyId, childId) || !await guardian(client, familyId, req.identity.sub, childId)) return failure(403, 'forbidden');
      // Every parent-issued device is recovery-capable. Retire all prior devices
      // before creating a replacement, even when this is the first issuance.
      await client.query('update auth_session set revoked_at=clock_timestamp() where user_id=$1 and revoked_at is null', [childId]);
      await client.query('update child_device_invitation set revoked_at=clock_timestamp() where child_user_id=$1 and used_at is null and revoked_at is null', [childId]);
      const raw = token();
      const row = (await client.query(`insert into child_device_invitation(family_id,child_user_id,issuer_user_id,token_digest,expires_at)
        values($1,$2,$3,$4,clock_timestamp()+interval '10 minutes') returning expires_at`, [familyId, childId, req.identity.sub, digest(raw)])).rows[0];
      await audit(client, familyId, req.identity.sub, childId, 'device_issue');
      return { status: 201, body: { token: raw, expiresAt: row.expires_at, accessScope: 'child_education', synthetic: true } };
    }));
  });

  router.post('/child-devices/accept', gate, async (req, res) => {
    if (!bodyToken(req.body) || Object.keys(req.query).length) return send(res, invalidInvitation());
    const key = digest(req.body.token);
    send(res, await transact(pool, null, async client => {
      const preliminary = (await client.query('select family_id,child_user_id,issuer_user_id from child_device_invitation where token_digest=$1', [key])).rows[0];
      if (!preliminary || !await context(client, preliminary.family_id, [preliminary.child_user_id, preliminary.issuer_user_id])) return invalidInvitation();
      if (!await activeChild(client, preliminary.family_id, preliminary.child_user_id) ||
        !await guardian(client, preliminary.family_id, preliminary.issuer_user_id, preliminary.child_user_id)) return invalidInvitation();
      await client.query('select id from child_device_invitation where token_digest=$1 for update', [key]);
      // Fresh SQL AFTER every lock: a token expiring while blocked is unusable.
      const invitation = (await client.query(`select id from child_device_invitation where token_digest=$1
        and used_at is null and revoked_at is null and expires_at>clock_timestamp()`, [key])).rows[0];
      if (!invitation) return invalidInvitation();
      await client.query('update child_device_invitation set used_at=clock_timestamp() where id=$1', [invitation.id]);
      const refreshToken = token();
      const session = (await client.query(`insert into auth_session(user_id,refresh_digest,expires_at,access_scope,child_issuer_user_id)
        values($1,$2,clock_timestamp()+interval '30 days','child_education',$3) returning id`, [preliminary.child_user_id, digest(refreshToken), preliminary.issuer_user_id])).rows[0];
      await audit(client, preliminary.family_id, preliminary.child_user_id, preliminary.child_user_id, 'device_accept');
      return { status: 200, body: { accessToken: jwt.sign({ sub: preliminary.child_user_id, sid: session.id, scope: 'child_education', aud: 'lifemate-api' },
        jwtSecret, { issuer: 'lifemate', expiresIn: '15m' }), refreshToken, accessScope: 'child_education', synthetic: true } };
    }));
  });

  router.post('/families/:familyId/children/:childId/guardian-invitations', gate, auth, async (req, res) => {
    if (!validPath(req) || !exact(req.body, ['guardianUserId']) || !uuid(req.body.guardianUserId)) return send(res, failure(400, 'invalid_guardian_invitation'));
    const { familyId, childId } = req.params, recipient = req.body.guardianUserId;
    send(res, await transact(pool, req.identity, async client => {
      if (!await context(client, familyId, [req.identity.sub, childId, recipient])) return failure(403, 'forbidden');
      const child = await activeChild(client, familyId, childId);
      if (!child || child.creator_user_id !== req.identity.sub || !await guardian(client, familyId, req.identity.sub, childId) ||
        recipient === req.identity.sub || !await adultParent(client, familyId, recipient)) return failure(403, 'forbidden');
      const raw = token();
      await client.query('update guardian_invitation set revoked_at=clock_timestamp() where child_user_id=$1 and guardian_user_id=$2 and used_at is null and revoked_at is null', [childId, recipient]);
      const row = (await client.query(`insert into guardian_invitation(family_id,child_user_id,issuer_user_id,guardian_user_id,token_digest,expires_at)
        values($1,$2,$3,$4,$5,clock_timestamp()+interval '10 minutes') returning expires_at`, [familyId, childId, req.identity.sub, recipient, digest(raw)])).rows[0];
      await audit(client, familyId, req.identity.sub, childId, 'guardian_invite');
      return { status: 201, body: { token: raw, expiresAt: row.expires_at, synthetic: true } };
    }));
  });

  router.post('/guardian-invitations/accept', gate, auth, async (req, res) => {
    if (!bodyToken(req.body) || Object.keys(req.query).length) return send(res, invalidInvitation());
    const key = digest(req.body.token);
    send(res, await transact(pool, req.identity, async client => {
      const preliminary = (await client.query('select * from guardian_invitation where token_digest=$1', [key])).rows[0];
      if (!preliminary || preliminary.guardian_user_id !== req.identity.sub ||
        !await context(client, preliminary.family_id, [preliminary.child_user_id, preliminary.issuer_user_id, req.identity.sub])) return invalidInvitation();
      const child = await activeChild(client, preliminary.family_id, preliminary.child_user_id);
      if (!child || child.creator_user_id !== preliminary.issuer_user_id ||
        !await guardian(client, preliminary.family_id, preliminary.issuer_user_id, preliminary.child_user_id) ||
        !await adultParent(client, preliminary.family_id, req.identity.sub)) return invalidInvitation();
      await client.query('select id from guardian_invitation where token_digest=$1 for update', [key]);
      // Freeze logout before the last expiry gate. A session-row lock wait must
      // not allow an invitation that expired during that wait to be consumed.
      if (!await sessionCurrent(client, req.identity, true)) return failure(401, 'session_invalid');
      const current = (await client.query(`select id from guardian_invitation where token_digest=$1
        and used_at is null and revoked_at is null and expires_at>clock_timestamp()`, [key])).rows[0];
      if (!current) return invalidInvitation();
      await client.query('insert into guardian_relationship(family_id,guardian_user_id,minor_user_id) values($1,$2,$3) on conflict(family_id,guardian_user_id,minor_user_id) do update set active=true',
        [preliminary.family_id, req.identity.sub, preliminary.child_user_id]);
      await client.query('update guardian_invitation set used_at=clock_timestamp() where id=$1', [current.id]);
      await audit(client, preliminary.family_id, req.identity.sub, preliminary.child_user_id, 'guardian_accept');
      return { status: 200, body: { accepted: true, synthetic: true } };
    }));
  });

  router.delete('/families/:familyId/children/:childId/consent', gate, auth, async (req, res) => {
    if (!validPath(req) || (req.body !== undefined && !exact(req.body, []))) return send(res, failure(400, 'invalid_consent_revocation'));
    const { familyId, childId } = req.params;
    send(res, await transact(pool, req.identity, async client => {
      if (!await context(client, familyId, [req.identity.sub, childId])) return failure(403, 'forbidden');
      const child = await activeChild(client, familyId, childId);
      if (!child || child.creator_user_id !== req.identity.sub || !await adultParent(client, familyId, req.identity.sub)) return failure(403, 'forbidden');
      await client.query('update child_consent set revoked_at=clock_timestamp() where child_user_id=$1', [childId]);
      await client.query('update auth_session set revoked_at=clock_timestamp() where user_id=$1 and revoked_at is null', [childId]);
      await client.query('update child_device_invitation set revoked_at=clock_timestamp() where child_user_id=$1 and used_at is null and revoked_at is null', [childId]);
      await client.query('update guardian_invitation set revoked_at=clock_timestamp() where child_user_id=$1 and used_at is null and revoked_at is null', [childId]);
      await client.query('update guardian_relationship set active=false where family_id=$1 and minor_user_id=$2', [familyId, childId]);
      await audit(client, familyId, req.identity.sub, childId, 'consent_revoke');
      return { status: 200, body: { revoked: true, synthetic: true } };
    }));
  });

  router.delete('/families/:familyId/children/:childId/guardians/:guardianId', gate, auth, async (req, res) => {
    if (!validPath(req) || !uuid(req.params.guardianId) || (req.body !== undefined && !exact(req.body, [])))
      return send(res, failure(400, 'invalid_guardian_revocation'));
    const { familyId, childId, guardianId } = req.params;
    send(res, await transact(pool, req.identity, async client => {
      if (!await context(client, familyId, [req.identity.sub, childId, guardianId])) return failure(403, 'forbidden');
      const child = await activeChild(client, familyId, childId);
      if (!child || child.creator_user_id !== req.identity.sub || !await guardian(client, familyId, req.identity.sub, childId))
        return failure(403, 'forbidden');
      if (guardianId === child.creator_user_id) return failure(409, 'creator_requires_consent_revocation');
      const relationship = await client.query(`update guardian_relationship set active=false
        where family_id=$1 and guardian_user_id=$2 and minor_user_id=$3 returning guardian_user_id`, [familyId, guardianId, childId]);
      if (!relationship.rowCount) return failure(403, 'forbidden');
      // Accepted invitation evidence must also be retired, preventing legacy
      // relation reactivation from silently restoring a revoked grant.
      await client.query('update guardian_invitation set revoked_at=clock_timestamp() where child_user_id=$1 and guardian_user_id=$2 and revoked_at is null', [childId, guardianId]);
      await client.query('update auth_session set revoked_at=clock_timestamp() where user_id=$1 and child_issuer_user_id=$2 and revoked_at is null', [childId, guardianId]);
      await client.query('update child_device_invitation set revoked_at=clock_timestamp() where child_user_id=$1 and issuer_user_id=$2 and used_at is null and revoked_at is null', [childId, guardianId]);
      await audit(client, familyId, req.identity.sub, childId, 'guardian_revoke');
      return { status: 200, body: { revoked: true, synthetic: true } };
    }));
  });

  router.get('/child-visibility', gate, auth, async (req, res) => {
    if (Object.keys(req.query).length) return send(res, failure(400, 'invalid_visibility_query'));
    send(res, await transact(pool, req.identity, async client => {
      const preliminary = (await client.query('select family_id from managed_child where user_id=$1', [req.identity.sub])).rows[0];
      if (!preliminary) return failure(403, 'forbidden');
      const guardianIds = (await client.query('select guardian_user_id from guardian_relationship where family_id=$1 and minor_user_id=$2', [preliminary.family_id, req.identity.sub])).rows.map(row => row.guardian_user_id);
      if (!await context(client, preliminary.family_id, [req.identity.sub, ...guardianIds]) || !await activeChild(client, preliminary.family_id, req.identity.sub)) return failure(403, 'forbidden');
      const guardians = (await client.query(`select g.guardian_user_id "userId",p.display_name "displayName" from guardian_relationship g
        join family_membership m on m.family_id=g.family_id and m.user_id=g.guardian_user_id
        join profile p on p.user_id=g.guardian_user_id join app_user u on u.id=g.guardian_user_id
        where g.family_id=$1 and g.minor_user_id=$2 and is_active_guardian(g.family_id,g.guardian_user_id,g.minor_user_id)
          and m.ended_at is null and m.role='parent_guardian'
          and u.disabled_at is null and p.birth_date<=(current_date-interval '18 years')::date
        order by g.guardian_user_id`, [preliminary.family_id, req.identity.sub])).rows;
      await audit(client, preliminary.family_id, req.identity.sub, req.identity.sub, 'visibility_read');
      return { status: 200, body: { guardians, accessScope: 'child_education', privateScopeGrantedByThisFlow: false,
        guardianVisibility: ['explicitly_shared_academic_summary'], excluded: ['private_notes', 'private_chat', 'health', 'cycle'],
        synthetic: true, notice: 'این محیط فقط برای هویت ساختگی آزمایشی است؛ دستگاه صادرشده توسط سرپرست به فضای خصوصی دسترسی ندارد.' } };
    }));
  });
  return router;
}
