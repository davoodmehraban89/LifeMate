import crypto from 'node:crypto';
import express from 'express';
import argon2 from 'argon2';
import jwt from 'jsonwebtoken';
import pg from 'pg';

const { Pool } = pg;
const app = express();
app.use(express.json({ limit: '64kb' }));

const pool = new Pool({ connectionString: process.env.DATABASE_URL });
const jwtSecret = process.env.JWT_SECRET;
if (!jwtSecret || jwtSecret.length < 32) throw new Error('JWT_SECRET must be at least 32 characters');

const sha256 = (value) => crypto.createHash('sha256').update(value).digest('hex');
const randomToken = () => crypto.randomBytes(32).toString('base64url');
const normalizeEmail = (email) => String(email ?? '').trim().toLowerCase();
const validPassword = (p) => typeof p === 'string' && p.length >= 10 && p.length <= 200;
const isEmail = (value) => /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value);
const testMode = process.env.NODE_ENV === 'test';

async function sendTransactionalEmail({ to, subject, text }) {
  if (testMode) return { delivered: false, testMode: true };
  const apiKey = process.env.RESEND_API_KEY;
  const from = process.env.EMAIL_FROM;
  if (!apiKey || !from) return { delivered: false, reason: 'provider_not_configured' };

  const response = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ from, to: [to], subject, text }),
  });
  if (!response.ok) throw new Error(`email_delivery_failed:${response.status}`);
  return { delivered: true };
}

const issueAccess = (userId, sessionId) =>
  jwt.sign(
    { sub: userId, sid: sessionId, aud: 'lifemate-api' },
    jwtSecret,
    { expiresIn: '15m', issuer: 'lifemate' },
  );

async function auth(req, res, next) {
  const raw = req.headers.authorization?.replace(/^Bearer\s+/i, '');
  try {
    const identity = jwt.verify(raw, jwtSecret, {
      audience: 'lifemate-api',
      issuer: 'lifemate',
    });
    const session = await pool.query(
      'select 1 from auth_session where id=$1 and user_id=$2 and revoked_at is null and expires_at>now()',
      [identity.sid, identity.sub],
    );
    if (!session.rowCount) return res.status(401).json({ error: 'session_invalid' });
    req.identity = identity;
    next();
  } catch {
    res.status(401).json({ error: 'unauthorized' });
  }
}

async function createOneTimeToken(client, userId, kind, minutes) {
  const raw = randomToken();
  await client.query(
    "insert into auth_token(user_id,kind,token_digest,expires_at) values($1,$2,$3,now()+($4 || ' minutes')::interval)",
    [userId, kind, sha256(raw), String(minutes)],
  );
  return raw;
}

async function createSession(client, userId) {
  const refreshToken = randomToken();
  const r = await client.query(
    "insert into auth_session(user_id,refresh_digest,expires_at) values($1,$2,now()+interval '30 days') returning id",
    [userId, sha256(refreshToken)],
  );
  return {
    accessToken: issueAccess(userId, r.rows[0].id),
    refreshToken,
  };
}

async function familyAccess(familyId, userId, { roles = [], admin = false } = {}) {
  const r = await pool.query(
    'select role,is_admin from family_membership where family_id=$1 and user_id=$2 and ended_at is null',
    [familyId, userId],
  );
  if (!r.rowCount) return false;
  return (admin && r.rows[0].is_admin) || roles.includes(r.rows[0].role);
}

app.get('/health', async (_req, res) => {
  const r = await pool.query('select 1 as ok');
  res.json({
    status: r.rows[0].ok === 1 ? 'ok' : 'degraded',
    emailProviderConfigured: Boolean(process.env.RESEND_API_KEY && process.env.EMAIL_FROM),
  });
});

app.post('/v1/auth/register', async (req, res) => {
  const email = normalizeEmail(req.body.email);
  const password = req.body.password;
  const name = String(req.body.displayName ?? '').trim();
  if (!isEmail(email) || !validPassword(password) || !name) {
    return res.status(400).json({ error: 'invalid_input' });
  }

  const client = await pool.connect();
  try {
    await client.query('begin');
    const hash = await argon2.hash(password, { type: argon2.argon2id });
    const u = await client.query(
      'insert into app_user(identity_subject,email_normalized) values($1,$2) returning id',
      [`local:${crypto.randomUUID()}`, email],
    );
    await client.query(
      "insert into profile(user_id,display_name,theme_preference) values($1,$2,'adult_blue')",
      [u.rows[0].id, name],
    );
    await client.query(
      'insert into auth_credential(user_id,password_hash) values($1,$2)',
      [u.rows[0].id, hash],
    );
    const verificationToken = await createOneTimeToken(
      client,
      u.rows[0].id,
      'email_verification',
      60 * 24,
    );
    await client.query('commit');

    const baseUrl = process.env.PUBLIC_APP_URL ?? 'https://app.lifemate.invalid';
    const delivery = await sendTransactionalEmail({
      to: email,
      subject: 'تأیید حساب LifeMate',
      text: `برای تأیید حساب LifeMate این لینک را باز کنید: ${baseUrl}/verify-email?token=${encodeURIComponent(verificationToken)}`,
    });

    res.status(201).json({
      userId: u.rows[0].id,
      verificationToken: testMode ? verificationToken : undefined,
      emailDelivery: delivery.delivered ? 'sent' : 'pending_configuration',
    });
  } catch (e) {
    await client.query('rollback').catch(() => {});
    if (e.code === '23505') return res.status(409).json({ error: 'account_exists' });
    throw e;
  } finally {
    client.release();
  }
});

app.post('/v1/auth/verify-email', async (req, res) => {
  const digest = sha256(String(req.body.token ?? ''));
  const client = await pool.connect();
  try {
    await client.query('begin');
    const r = await client.query(
      "select user_id from auth_token where kind='email_verification' and token_digest=$1 and used_at is null and expires_at>now() for update",
      [digest],
    );
    if (!r.rowCount) {
      await client.query('rollback');
      return res.status(400).json({ error: 'invalid_or_expired_token' });
    }
    await client.query('update auth_token set used_at=now() where token_digest=$1', [digest]);
    await client.query(
      'update app_user set email_verified_at=coalesce(email_verified_at,now()) where id=$1',
      [r.rows[0].user_id],
    );
    await client.query('commit');
    res.status(204).end();
  } finally {
    client.release();
  }
});

app.post('/v1/auth/login', async (req, res) => {
  const email = normalizeEmail(req.body.email);
  const password = String(req.body.password ?? '');
  const r = await pool.query(
    'select u.id,u.email_verified_at,c.password_hash from app_user u join auth_credential c on c.user_id=u.id where u.email_normalized=$1 and u.disabled_at is null',
    [email],
  );
  if (!r.rowCount || !(await argon2.verify(r.rows[0].password_hash, password))) {
    return res.status(401).json({ error: 'invalid_credentials' });
  }
  if (!r.rows[0].email_verified_at) {
    return res.status(403).json({ error: 'email_not_verified' });
  }

  const client = await pool.connect();
  try {
    const tokens = await createSession(client, r.rows[0].id);
    res.json(tokens);
  } finally {
    client.release();
  }
});

app.post('/v1/auth/refresh', async (req, res) => {
  const digest = sha256(String(req.body.refreshToken ?? ''));
  const client = await pool.connect();
  try {
    await client.query('begin');
    const r = await client.query(
      'select id,user_id from auth_session where refresh_digest=$1 and revoked_at is null and expires_at>now() for update',
      [digest],
    );
    if (!r.rowCount) {
      await client.query('rollback');
      return res.status(401).json({ error: 'invalid_refresh_token' });
    }

    await client.query('update auth_session set revoked_at=now() where id=$1', [r.rows[0].id]);
    const tokens = await createSession(client, r.rows[0].user_id);
    await client.query('commit');
    res.json(tokens);
  } finally {
    client.release();
  }
});

app.post('/v1/auth/forgot-password', async (req, res) => {
  const email = normalizeEmail(req.body.email);
  const r = await pool.query(
    'select id from app_user where email_normalized=$1 and disabled_at is null',
    [email],
  );

  let resetToken;
  if (r.rowCount) {
    const c = await pool.connect();
    try {
      resetToken = await createOneTimeToken(c, r.rows[0].id, 'password_reset', 30);
    } finally {
      c.release();
    }
    const baseUrl = process.env.PUBLIC_APP_URL ?? 'https://app.lifemate.invalid';
    await sendTransactionalEmail({
      to: email,
      subject: 'بازیابی رمز عبور LifeMate',
      text: `برای ساخت رمز جدید این لینک را باز کنید: ${baseUrl}/reset-password?token=${encodeURIComponent(resetToken)}`,
    });
  }

  res.json({
    accepted: true,
    resetToken: testMode ? resetToken : undefined,
  });
});

app.post('/v1/auth/reset-password', async (req, res) => {
  if (!validPassword(req.body.newPassword)) {
    return res.status(400).json({ error: 'invalid_password' });
  }

  const digest = sha256(String(req.body.token ?? ''));
  const client = await pool.connect();
  try {
    await client.query('begin');
    const r = await client.query(
      "select user_id from auth_token where kind='password_reset' and token_digest=$1 and used_at is null and expires_at>now() for update",
      [digest],
    );
    if (!r.rowCount) {
      await client.query('rollback');
      return res.status(400).json({ error: 'invalid_or_expired_token' });
    }

    await client.query('update auth_token set used_at=now() where token_digest=$1', [digest]);
    const hash = await argon2.hash(req.body.newPassword, { type: argon2.argon2id });
    await client.query(
      'update auth_credential set password_hash=$1,password_changed_at=now() where user_id=$2',
      [hash, r.rows[0].user_id],
    );
    await client.query(
      'update auth_session set revoked_at=now() where user_id=$1 and revoked_at is null',
      [r.rows[0].user_id],
    );
    await client.query('commit');
    res.status(204).end();
  } finally {
    client.release();
  }
});

app.post('/v1/auth/change-password', auth, async (req, res) => {
  if (!validPassword(req.body.newPassword)) {
    return res.status(400).json({ error: 'invalid_password' });
  }

  const r = await pool.query(
    'select password_hash from auth_credential where user_id=$1',
    [req.identity.sub],
  );
  if (
    !r.rowCount ||
    !(await argon2.verify(r.rows[0].password_hash, String(req.body.currentPassword ?? '')))
  ) {
    return res.status(403).json({ error: 'invalid_current_password' });
  }

  const hash = await argon2.hash(req.body.newPassword, { type: argon2.argon2id });
  const client = await pool.connect();
  try {
    await client.query('begin');
    await client.query(
      'update auth_credential set password_hash=$1,password_changed_at=now() where user_id=$2',
      [hash, req.identity.sub],
    );
    await client.query(
      'update auth_session set revoked_at=now() where user_id=$1 and id<>$2 and revoked_at is null',
      [req.identity.sub, req.identity.sid],
    );
    await client.query('commit');
    res.status(204).end();
  } finally {
    client.release();
  }
});

app.post('/v1/auth/logout', auth, async (req, res) => {
  await pool.query('update auth_session set revoked_at=now() where id=$1', [req.identity.sid]);
  res.status(204).end();
});

app.get('/v1/profile', auth, async (req, res) => {
  const r = await pool.query(
    'select p.display_name,p.birth_date,p.theme_preference,u.email_normalized,u.email_verified_at from profile p join app_user u on u.id=p.user_id where p.user_id=$1',
    [req.identity.sub],
  );
  if (!r.rowCount) return res.status(404).json({ error: 'profile_not_found' });
  res.json(r.rows[0]);
});

app.patch('/v1/profile', auth, async (req, res) => {
  const name = req.body.displayName == null ? null : String(req.body.displayName).trim();
  const theme = req.body.themePreference == null ? null : String(req.body.themePreference);
  const allowedThemes = ['girl_pink', 'boy_blue', 'adult_blue', 'custom'];
  if (name != null && (!name || name.length > 100)) {
    return res.status(400).json({ error: 'invalid_display_name' });
  }
  if (theme != null && !allowedThemes.includes(theme)) {
    return res.status(400).json({ error: 'invalid_theme' });
  }

  const r = await pool.query(
    `update profile
       set display_name=coalesce($2,display_name),
           birth_date=coalesce($3::date,birth_date),
           theme_preference=coalesce($4,theme_preference),
           updated_at=now()
     where user_id=$1
     returning display_name,birth_date,theme_preference`,
    [req.identity.sub, name, req.body.birthDate ?? null, theme],
  );
  res.json(r.rows[0]);
});

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
  if (!name) return res.status(400).json({ error: 'invalid_name' });

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

app.get('/v1/families/:familyId/members', auth, async (req, res) => {
  const allowed = await familyAccess(req.params.familyId, req.identity.sub, {
    roles: ['parent_guardian', 'teen_minor', 'adult_member'],
  });
  if (!allowed) return res.status(403).json({ error: 'forbidden' });

  const r = await pool.query(
    `select m.user_id,m.role,m.is_admin,p.display_name,p.theme_preference
       from family_membership m
       join profile p on p.user_id=m.user_id
      where m.family_id=$1 and m.ended_at is null
      order by m.joined_at`,
    [req.params.familyId],
  );
  res.json({ members: r.rows });
});

app.post('/v1/families/:familyId/invitations', auth, async (req, res) => {
  const allowed = await familyAccess(req.params.familyId, req.identity.sub, {
    roles: ['parent_guardian'],
    admin: true,
  });
  if (!allowed) return res.status(403).json({ error: 'forbidden' });

  const email = normalizeEmail(req.body.email);
  const role = String(req.body.role ?? '');
  const themePreference = String(req.body.themePreference ?? '');
  const allowedRoles = ['parent_guardian', 'teen_minor', 'adult_member'];
  const allowedThemes = ['girl_pink', 'boy_blue', 'adult_blue', 'custom'];
  const resolvedTheme = allowedThemes.includes(themePreference)
      ? themePreference
      : role === 'teen_minor'
          ? 'girl_pink'
          : 'adult_blue';
  if (!isEmail(email) || !allowedRoles.includes(role)) {
    return res.status(400).json({ error: 'invalid_invitation' });
  }

  const token = randomToken();
  const r = await pool.query(
    "insert into family_invitation(family_id,invited_email_normalized,intended_role,intended_theme,token_digest,invited_by,expires_at) values($1,$2,$3,$4,$5,$6,now()+interval '7 days') returning id,expires_at",
    [req.params.familyId, email, role, resolvedTheme, sha256(token), req.identity.sub],
  );

  const baseUrl = process.env.PUBLIC_APP_URL ?? 'https://app.lifemate.invalid';
  await sendTransactionalEmail({
    to: email,
    subject: 'دعوت به خانواده در LifeMate',
    text: `برای پیوستن به خانواده این لینک را باز کنید: ${baseUrl}/accept-invitation?token=${encodeURIComponent(token)}`,
  });

  res.status(201).json({
    ...r.rows[0],
    invitationToken: testMode ? token : undefined,
  });
});

app.post('/v1/invitations/accept', auth, async (req, res) => {
  const digest = sha256(String(req.body.token ?? ''));
  const client = await pool.connect();
  try {
    await client.query('begin');
    const invitation = await client.query(
      `select i.id,i.family_id,i.intended_role,i.intended_theme,i.invited_email_normalized,u.email_normalized
         from family_invitation i
         join app_user u on u.id=$2
        where i.token_digest=$1
          and i.status='pending'
          and i.expires_at>now()
        for update`,
      [digest, req.identity.sub],
    );
    if (!invitation.rowCount) {
      await client.query('rollback');
      return res.status(400).json({ error: 'invalid_or_expired_invitation' });
    }
    const row = invitation.rows[0];
    if (row.invited_email_normalized !== row.email_normalized) {
      await client.query('rollback');
      return res.status(403).json({ error: 'invitation_email_mismatch' });
    }

    await client.query(
      `insert into family_membership(family_id,user_id,role)
       values($1,$2,$3)
       on conflict(family_id,user_id)
       do update set role=excluded.role,ended_at=null`,
      [row.family_id, req.identity.sub, row.intended_role],
    );
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
  } finally {
    client.release();
  }
});

app.post('/v1/families/:familyId/guardians', auth, async (req, res) => {
  const allowed = await familyAccess(req.params.familyId, req.identity.sub, {
    admin: true,
  });
  if (!allowed) return res.status(403).json({ error: 'forbidden' });

  const guardianUserId = String(req.body.guardianUserId ?? '');
  const minorUserId = String(req.body.minorUserId ?? '');

  const roles = await pool.query(
    'select user_id,role from family_membership where family_id=$1 and user_id in ($2,$3) and ended_at is null',
    [req.params.familyId, guardianUserId, minorUserId],
  );
  const map = new Map(roles.rows.map((row) => [row.user_id, row.role]));
  if (map.get(guardianUserId) !== 'parent_guardian' || map.get(minorUserId) !== 'teen_minor') {
    return res.status(400).json({ error: 'invalid_guardian_relationship' });
  }

  await pool.query(
    `insert into guardian_relationship(family_id,guardian_user_id,minor_user_id,active)
     values($1,$2,$3,true)
     on conflict(family_id,guardian_user_id,minor_user_id)
     do update set active=true`,
    [req.params.familyId, guardianUserId, minorUserId],
  );
  await pool.query(
    "insert into access_audit(actor_user_id,family_id,action,target_type,target_id,metadata) values($1,$2,'guardian.activate','guardian_relationship',$3,jsonb_build_object('minorUserId',$4::text))",
    [req.identity.sub, req.params.familyId, guardianUserId, minorUserId],
  );
  res.status(204).end();
});

app.use((err, _req, res, _next) => {
  console.error(err);
  res.status(500).json({ error: 'internal_error' });
});

const port = Number(process.env.PORT ?? 8080);
if (!testMode) {
  app.listen(port, () => console.log(`LifeMate API listening on ${port}`));
}

export { app, pool };
export default app;
