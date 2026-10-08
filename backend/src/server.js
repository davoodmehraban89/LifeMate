import crypto from 'node:crypto';
import { pathToFileURL } from 'node:url';
import express from 'express';
import pg from 'pg';
import cors from 'cors';
import { createPhase3Router } from './phase3.js';
import { createPhase4Router } from './phase4.js';
import { createPhase6Router } from './phase6.js';
import { configureTrustedProxy, operationalErrorHandler } from './operations.js';
import { createSessionAuth } from './session_auth.js';
import { createAuthRouter } from './auth_router.js';
import { createStudySessionsRouter } from './study_sessions.js';
import { createProfileRouter } from './profile_router.js';
import { createSchoolCrudRouter } from './school_crud_router.js';
import { normalizeEmail, normalizePhone, isEmail } from './auth_contacts.js';
import { createEmailProvider, safelyDeliver } from './auth_delivery.js';

const { Pool } = pg;
const app = express();
configureTrustedProxy(app);
const allowedOrigins = (process.env.CORS_ORIGINS ?? '')
  .split(',')
  .map((value) => value.trim())
  .filter(Boolean);
app.use(
  cors({
    origin(origin, callback) {
      if (!origin || testMode || allowedOrigins.includes(origin)) {
        return callback(null, true);
      }
      const error = new Error('cors_origin_denied');
      error.code = 'CORS_ORIGIN_DENIED';
      return callback(error);
    },
    methods: ['GET', 'POST', 'PATCH', 'PUT', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization'],
    maxAge: 86400,
  }),
);
app.use(express.json({ limit: '64kb' }));

const pool = new Pool({ connectionString: process.env.DATABASE_URL });
const jwtSecret = process.env.JWT_SECRET;
if (!jwtSecret || jwtSecret.length < 32) throw new Error('JWT_SECRET must be at least 32 characters');

const sha256 = (value) => crypto.createHash('sha256').update(value).digest('hex');
const randomToken = () => crypto.randomBytes(32).toString('base64url');
const testMode = process.env.NODE_ENV === 'test';
const emailProvider = createEmailProvider();
const auth = createSessionAuth({ pool, jwtSecret });
const uuid = (value) => typeof value === 'string' && /^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$/i.test(value);

async function familyAccess(familyId, userId, { roles = [], admin = false } = {}) {
  if (!uuid(familyId)) return false;
  const r = await pool.query(
    `select m.role,m.is_admin from family_membership m
     join family_workspace f on f.id=m.family_id
     where m.family_id=$1 and m.user_id=$2 and m.ended_at is null and f.archived_at is null`,
    [familyId, userId],
  );
  if (!r.rowCount) return false;
  return (admin && r.rows[0].is_admin) || roles.includes(r.rows[0].role);
}

async function familyAdminTransaction(familyId, userId, operation) {
  if (!uuid(familyId)) return { status: 403, body: { error: 'forbidden' } };
  const client = await pool.connect();
  try {
    await client.query('begin');
    const family = await client.query('select id from family_workspace where id=$1 and archived_at is null for update', [familyId]);
    const membership = family.rowCount ? await client.query(
      `select 1 from family_membership m join app_user u on u.id=m.user_id
       where m.family_id=$1 and m.user_id=$2 and m.ended_at is null
         and m.is_admin and u.disabled_at is null for update of m,u`, [familyId, userId],
    ) : { rowCount: 0 };
    const result = membership.rowCount ? await operation(client) : { status: 403, body: { error: 'forbidden' } };
    await client.query('commit');
    return result;
  } catch (error) {
    await client.query('rollback').catch(() => {});
    throw error;
  } finally { client.release(); }
}
function familyResponse(res, result) {
  return result.body === undefined ? res.status(result.status).end() : res.status(result.status).json(result.body);
}
async function familyAudit(client, familyId, userId, action, targetType, targetId) {
  await client.query('insert into access_audit(actor_user_id,family_id,action,target_type,target_id) values($1,$2,$3,$4,$5)', [userId, familyId, action, targetType, targetId]);
}

app.get('/health', async (_req, res) => {
  const r = await pool.query('select 1 as ok');
  res.json({
    status: r.rows[0].ok === 1 ? 'ok' : 'degraded',
    emailProviderConfigured: emailProvider.configured,
  });
});

app.use('/v1/auth', createAuthRouter({ pool, jwtSecret, auth, emailProvider }));

app.use('/v1/profile', createProfileRouter({ pool, auth }));

app.get('/v1/families', auth, async (req, res) => {
  const r = await pool.query(
    `select f.id,f.name,m.role,m.is_admin
       from family_membership m
       join family_workspace f on f.id=m.family_id
      where m.user_id=$1 and m.ended_at is null and f.archived_at is null
      order by f.created_at`,
    [req.identity.sub],
  );
  res.json({ families: r.rows });
});

app.post('/v1/families', auth, async (req, res) => {
  const name = String(req.body.name ?? '').trim();
  if (!name || name.length > 120) return res.status(400).json({ error: 'invalid_name' });

  const creatorRole = ['parent_guardian', 'adult_member'].includes(req.body.role)
    ? req.body.role
    : 'adult_member';
  const c = await pool.connect();
  try {
    await c.query('begin');
    const f = await c.query(
      'insert into family_workspace(name,created_by) values($1,$2) returning id,name',
      [name, req.identity.sub],
    );
    await c.query(
      'insert into family_membership(family_id,user_id,role,is_admin) values($1,$2,$3,true)',
      [f.rows[0].id, req.identity.sub, creatorRole],
    );
    await c.query(
      "insert into access_audit(actor_user_id,family_id,action,target_type,target_id) values($1,$2,'family.create','family',$3)",
      [req.identity.sub, f.rows[0].id, String(f.rows[0].id)],
    );
    await c.query('commit');
    res.status(201).json(f.rows[0]);
  } catch (e) {
    await c.query('rollback');
    throw e;
  } finally {
    c.release();
  }
});

app.get('/v1/families/:familyId', auth, async (req, res) => {
  if (!await familyAccess(req.params.familyId, req.identity.sub, { roles: ['parent_guardian', 'teen_minor', 'adult_member'] })) return res.status(403).json({ error: 'forbidden' });
  const result = await pool.query(`select f.id,f.name,m.role,m.is_admin from family_workspace f
    join family_membership m on m.family_id=f.id where f.id=$1 and f.archived_at is null
      and m.user_id=$2 and m.ended_at is null`, [req.params.familyId, req.identity.sub]);
  if (!result.rowCount) return res.status(403).json({ error: 'forbidden' });
  res.json(result.rows[0]);
});

app.patch('/v1/families/:familyId', auth, async (req, res) => {
  const name = String(req.body?.name ?? '').trim();
  if (!name || name.length > 120) return res.status(400).json({ error: 'invalid_name' });
  const result = await familyAdminTransaction(req.params.familyId, req.identity.sub, async (client) => {
    const updated = await client.query('update family_workspace set name=$2 where id=$1 returning id,name', [req.params.familyId, name]);
    await familyAudit(client, req.params.familyId, req.identity.sub, 'family.rename', 'family', req.params.familyId);
    return { status: 200, body: updated.rows[0] };
  });
  familyResponse(res, result);
});

app.delete('/v1/families/:familyId', auth, async (req, res) => {
  const result = await familyAdminTransaction(req.params.familyId, req.identity.sub, async (client) => {
    await client.query('update family_workspace set archived_at=now() where id=$1', [req.params.familyId]);
    await client.query("update family_invitation set status='revoked' where family_id=$1 and status='pending'", [req.params.familyId]);
    await client.query('update guardian_relationship set active=false where family_id=$1', [req.params.familyId]);
    await familyAudit(client, req.params.familyId, req.identity.sub, 'family.archive', 'family', req.params.familyId);
    return { status: 204 };
  });
  familyResponse(res, result);
});

app.delete('/v1/families/:familyId/members/:userId', auth, async (req, res) => {
  if (!uuid(req.params.userId)) return res.status(400).json({ error: 'invalid_member' });
  const result = await familyAdminTransaction(req.params.familyId, req.identity.sub, async (client) => {
    const target = await client.query('select m.is_admin,u.disabled_at from family_membership m join app_user u on u.id=m.user_id where m.family_id=$1 and m.user_id=$2 and m.ended_at is null for update of m', [req.params.familyId, req.params.userId]);
    if (!target.rowCount) return { status: 204 };
    if (target.rows[0].is_admin && !target.rows[0].disabled_at) {
      const count = await client.query('select count(*)::int as n from family_membership m join app_user u on u.id=m.user_id where m.family_id=$1 and m.ended_at is null and m.is_admin and u.disabled_at is null', [req.params.familyId]);
      if (count.rows[0].n <= 1) return { status: 409, body: { error: 'last_admin_required' } };
    }
    await client.query('update family_membership set ended_at=now(),is_admin=false where family_id=$1 and user_id=$2', [req.params.familyId, req.params.userId]);
    await client.query('update guardian_relationship set active=false where family_id=$1 and (guardian_user_id=$2 or minor_user_id=$2)', [req.params.familyId, req.params.userId]);
    await client.query(`update family_invitation i set status='revoked' from app_user u where u.id=$2
      and i.family_id=$1 and i.status='pending' and (i.invited_by=u.id
      or i.invited_email_normalized=u.email_normalized or i.invited_phone_normalized=u.phone_normalized)`, [req.params.familyId, req.params.userId]);
    await familyAudit(client, req.params.familyId, req.identity.sub, 'membership.end', 'membership', req.params.userId);
    return { status: 204 };
  });
  familyResponse(res, result);
});

app.get('/v1/families/:familyId/members', auth, async (req, res) => {
  const allowed = await familyAccess(req.params.familyId, req.identity.sub, {
    roles: ['parent_guardian', 'teen_minor', 'adult_member'],
  });
  if (!allowed) return res.status(403).json({ error: 'forbidden' });

  const r = await pool.query(
    `select m.user_id,m.role,m.is_admin,p.display_name,p.theme_preference
       from family_membership m
       join profile p on p.user_id=m.user_id
       join family_workspace f on f.id=m.family_id
      where m.family_id=$1 and m.ended_at is null and f.archived_at is null
        and exists(select 1 from family_membership viewer where viewer.family_id=m.family_id and viewer.user_id=$2 and viewer.ended_at is null)
      order by m.joined_at`,
    [req.params.familyId, req.identity.sub],
  );
  res.json({ members: r.rows });
});

app.post('/v1/families/:familyId/invitations', auth, async (req, res) => {
  const allowed = await familyAccess(req.params.familyId, req.identity.sub, {
    admin: true,
  });
  if (!allowed) return res.status(403).json({ error: 'forbidden' });

  const email = normalizeEmail(req.body.email);
  const phone = req.body.phone == null ? null : normalizePhone(req.body.phone);
  const role = String(req.body.role ?? '');
  const themePreference = String(req.body.themePreference ?? '');
  const allowedRoles = ['parent_guardian', 'teen_minor', 'adult_member'];
  const allowedThemes = ['girl_pink', 'boy_blue', 'adult_blue', 'custom'];
  const resolvedTheme = allowedThemes.includes(themePreference)
      ? themePreference
      : role === 'teen_minor'
          ? 'girl_pink'
          : 'adult_blue';
  if ((email && phone) || (!email && !phone) || (email && !isEmail(email)) ||
      (req.body.phone != null && !phone) || !allowedRoles.includes(role)) {
    return res.status(400).json({ error: 'invalid_invitation' });
  }

  const token = randomToken();
  const result = await familyAdminTransaction(req.params.familyId, req.identity.sub, async (client) => {
    const activeMember = await client.query(
      `select 1
         from family_membership m
         join app_user u on u.id=m.user_id
        where m.family_id=$1
          and m.ended_at is null
          and ((u.email_normalized=$2 and $2::text is not null)
            or (u.phone_normalized=$3 and $3::text is not null))`,
      [req.params.familyId, email || null, phone],
    );
    if (activeMember.rowCount) {
      return { status: 409, body: { error: 'member_already_active' } };
    }

    const r = await client.query(
      "insert into family_invitation(family_id,invited_email_normalized,invited_phone_normalized,intended_role,intended_theme,token_digest,invited_by,expires_at) values($1,$2,$3,$4,$5,$6,$7,now()+interval '7 days') returning id,expires_at",
      [req.params.familyId, email || null, phone, role, resolvedTheme, sha256(token), req.identity.sub],
    );
    await familyAudit(client, req.params.familyId, req.identity.sub, 'invitation.create', 'invitation', r.rows[0].id);
    return { status: 201, body: r.rows[0] };
  });
  if (result.status !== 201) return familyResponse(res, result);

  const baseUrl = process.env.PUBLIC_APP_URL ?? 'https://app.lifeguide.invalid';
  const invitationLink = `${baseUrl}/accept-invitation?token=${encodeURIComponent(token)}`;
  // The authenticated family administrator can copy the link even without a provider.
  res.status(201).json({
    ...result.body,
    invitationToken: token,
    invitationLink,
  });
  if (email) await safelyDeliver(emailProvider, {
    to: email,
    subject: 'دعوت به خانواده در لایف‌گاید',
    text: `برای پیوستن به خانواده در LifeGuide / لایف‌گاید این لینک را باز کن: ${invitationLink}\nاین لینک ۷ روز اعتبار دارد.`,
  }, { attemptId: result.body.id });
});

app.post('/v1/invitations/accept', auth, async (req, res) => {
  const digest = sha256(String(req.body.token ?? ''));
  const client = await pool.connect();
  try {
    await client.query('begin');
    const preliminary = await client.query('select family_id,invited_by from family_invitation where token_digest=$1', [digest]);
    const family = preliminary.rowCount ? await client.query('select 1 from family_workspace where id=$1 and archived_at is null for update', [preliminary.rows[0].family_id]) : { rowCount: 0 };
    const inviter = family.rowCount ? await client.query(`select 1 from family_membership m
      join app_user u on u.id=m.user_id where m.family_id=$1 and m.user_id=$2
        and m.ended_at is null and m.is_admin and u.disabled_at is null for update of m`, [preliminary.rows[0].family_id, preliminary.rows[0].invited_by]) : { rowCount: 0 };
    if (!inviter.rowCount) {
      await client.query('rollback');
      return res.status(400).json({ error: 'invalid_or_expired_invitation' });
    }
    await client.query('select id from app_user where id=$1 for update', [req.identity.sub]);
    const invitation = await client.query(
      `select i.id,i.family_id,i.intended_role,i.intended_theme,
              i.invited_email_normalized,i.invited_phone_normalized,
              u.email_normalized,u.email_verified_at,u.phone_normalized,u.phone_verified_at
         from family_invitation i
         join app_user u on u.id=$2
        where i.token_digest=$1
          and i.status='pending'
          and i.expires_at>now()
          and u.disabled_at is null
        for update of i`,
      [digest, req.identity.sub],
    );
    if (!invitation.rowCount) {
      await client.query('rollback');
      return res.status(400).json({ error: 'invalid_or_expired_invitation' });
    }
    const row = invitation.rows[0];
    const matchesEmail = row.invited_email_normalized && row.email_verified_at &&
      row.invited_email_normalized === row.email_normalized;
    const matchesPhone = row.invited_phone_normalized && row.phone_verified_at &&
      row.invited_phone_normalized === row.phone_normalized;
    if (!matchesEmail && !matchesPhone) {
      await client.query('rollback');
      return res.status(403).json({ error: 'invitation_contact_mismatch' });
    }

    const membership = await client.query(
      `insert into family_membership(family_id,user_id,role)
       values($1,$2,$3)
       on conflict(family_id,user_id)
       do update set role=excluded.role,ended_at=null,is_admin=false,joined_at=now()
       where family_membership.ended_at is not null returning user_id`,
      [row.family_id, req.identity.sub, row.intended_role],
    );
    if (!membership.rowCount) {
      await client.query('rollback');
      return res.status(409).json({ error: 'member_already_active' });
    }
    await client.query(
      "update family_invitation set status='accepted',accepted_by=$2,accepted_at=now() where id=$1",
      [row.id, req.identity.sub],
    );
    if (row.intended_theme) {
      await client.query(
        'update profile set theme_preference=$2,updated_at=now() where user_id=$1',
        [req.identity.sub, row.intended_theme],
      );
    }
    await client.query(
      "insert into access_audit(actor_user_id,family_id,action,target_type,target_id) values($1,$2,'invitation.accept','membership',$3)",
      [req.identity.sub, row.family_id, String(req.identity.sub)],
    );
    await client.query('commit');
    res.status(204).end();
  } catch (error) {
    await client.query('rollback').catch(() => {});
    throw error;
  } finally {
    client.release();
  }
});

app.post('/v1/families/:familyId/guardians', auth, async (req, res) => {
  const guardianUserId = String(req.body?.guardianUserId ?? '');
  const minorUserId = String(req.body?.minorUserId ?? '');
  if (!uuid(guardianUserId) || !uuid(minorUserId)) return res.status(400).json({ error: 'invalid_guardian_relationship' });
  const result = await familyAdminTransaction(req.params.familyId, req.identity.sub, async (client) => {
    const roles = await client.query(`select m.user_id,m.role from family_membership m
      join app_user u on u.id=m.user_id where m.family_id=$1 and m.user_id in ($2,$3)
        and m.ended_at is null and u.disabled_at is null for update of m`, [req.params.familyId, guardianUserId, minorUserId]);
    const map = new Map(roles.rows.map((row) => [row.user_id, row.role]));
    if (map.get(guardianUserId) !== 'parent_guardian' || map.get(minorUserId) !== 'teen_minor') return { status: 400, body: { error: 'invalid_guardian_relationship' } };
    await client.query(`insert into guardian_relationship(family_id,guardian_user_id,minor_user_id,active)
      values($1,$2,$3,true) on conflict(family_id,guardian_user_id,minor_user_id) do update set active=true`, [req.params.familyId, guardianUserId, minorUserId]);
    await familyAudit(client, req.params.familyId, req.identity.sub, 'guardian.activate', 'guardian_relationship', guardianUserId);
    return { status: 204 };
  });
  familyResponse(res, result);
});

app.delete('/v1/families/:familyId/guardians', auth, async (req, res) => {
  const guardianUserId = String(req.body?.guardianUserId ?? '');
  const minorUserId = String(req.body?.minorUserId ?? '');
  if (!uuid(guardianUserId) || !uuid(minorUserId)) return res.status(400).json({ error: 'invalid_guardian_relationship' });
  const result = await familyAdminTransaction(req.params.familyId, req.identity.sub, async (client) => {
    await client.query('update guardian_relationship set active=false where family_id=$1 and guardian_user_id=$2 and minor_user_id=$3', [req.params.familyId, guardianUserId, minorUserId]);
    await familyAudit(client, req.params.familyId, req.identity.sub, 'guardian.deactivate', 'guardian_relationship', guardianUserId);
    return { status: 204 };
  });
  familyResponse(res, result);
});

app.use('/v1', createSchoolCrudRouter({ pool, auth }));
app.use('/v1', createPhase3Router({ pool, auth }));
app.use('/v1', createPhase4Router({ pool, auth }));
app.use('/v1', createPhase6Router({ pool, auth }));
app.use('/v1', createStudySessionsRouter({ pool, auth }));

app.use(operationalErrorHandler);

const port = Number(process.env.PORT ?? 8080);
const invokedDirectly = process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href;
if (!testMode && invokedDirectly) {
  app.listen(port, () => console.log(`LifeGuide API listening on ${port}`));
}

export { app, pool };
export default app;
