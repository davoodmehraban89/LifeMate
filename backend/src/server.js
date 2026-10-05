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
const issueAccess = (userId) => jwt.sign({ sub: userId, aud: 'lifemate-api' }, jwtSecret, { expiresIn: '15m', issuer: 'lifemate' });

async function auth(req, res, next) {
  const raw = req.headers.authorization?.replace(/^Bearer\s+/i, '');
  try { req.identity = jwt.verify(raw, jwtSecret, { audience: 'lifemate-api', issuer: 'lifemate' }); next(); }
  catch { res.status(401).json({ error: 'unauthorized' }); }
}

async function createOneTimeToken(client, userId, kind, minutes) {
  const raw = randomToken();
  await client.query('insert into auth_token(user_id,kind,token_digest,expires_at) values($1,$2,$3,now()+($4 || \' minutes\')::interval)', [userId, kind, sha256(raw), String(minutes)]);
  return raw;
}

app.get('/health', async (_req, res) => {
  const r = await pool.query('select 1 as ok');
  res.json({ status: r.rows[0].ok === 1 ? 'ok' : 'degraded' });
});

app.post('/v1/auth/register', async (req, res) => {
  const email = normalizeEmail(req.body.email); const password = req.body.password; const name = String(req.body.displayName ?? '').trim();
  if (!email.includes('@') || !validPassword(password) || !name) return res.status(400).json({ error: 'invalid_input' });
  const client = await pool.connect();
  try {
    await client.query('begin');
    const hash = await argon2.hash(password, { type: argon2.argon2id });
    const u = await client.query('insert into app_user(identity_subject,email_normalized) values($1,$2) returning id', [`local:${crypto.randomUUID()}`, email]);
    await client.query('insert into profile(user_id,display_name) values($1,$2)', [u.rows[0].id, name]);
    await client.query('insert into auth_credential(user_id,password_hash) values($1,$2)', [u.rows[0].id, hash]);
    const verificationToken = await createOneTimeToken(client, u.rows[0].id, 'email_verification', 60 * 24);
    await client.query('commit');
    res.status(201).json({ userId: u.rows[0].id, verificationToken: process.env.NODE_ENV === 'test' ? verificationToken : undefined });
  } catch (e) {
    await client.query('rollback');
    if (e.code === '23505') return res.status(409).json({ error: 'account_exists' });
    throw e;
  } finally { client.release(); }
});

app.post('/v1/auth/verify-email', async (req, res) => {
  const digest = sha256(String(req.body.token ?? ''));
  const r = await pool.query("update auth_token t set used_at=now() from app_user u where t.user_id=u.id and t.kind='email_verification' and t.token_digest=$1 and t.used_at is null and t.expires_at>now() returning u.id", [digest]);
  if (!r.rowCount) return res.status(400).json({ error: 'invalid_or_expired_token' });
  await pool.query('update app_user set email_verified_at=coalesce(email_verified_at,now()) where id=$1', [r.rows[0].id]);
  res.status(204).end();
});

app.post('/v1/auth/login', async (req, res) => {
  const email = normalizeEmail(req.body.email); const password = String(req.body.password ?? '');
  const r = await pool.query('select u.id,u.email_verified_at,c.password_hash from app_user u join auth_credential c on c.user_id=u.id where u.email_normalized=$1 and u.disabled_at is null', [email]);
  if (!r.rowCount || !(await argon2.verify(r.rows[0].password_hash, password))) return res.status(401).json({ error: 'invalid_credentials' });
  if (!r.rows[0].email_verified_at) return res.status(403).json({ error: 'email_not_verified' });
  res.json({ accessToken: issueAccess(r.rows[0].id) });
});

app.post('/v1/auth/forgot-password', async (req, res) => {
  const email = normalizeEmail(req.body.email);
  const r = await pool.query('select id from app_user where email_normalized=$1 and disabled_at is null', [email]);
  let resetToken;
  if (r.rowCount) { const c = await pool.connect(); try { resetToken = await createOneTimeToken(c, r.rows[0].id, 'password_reset', 30); } finally { c.release(); } }
  res.json({ accepted: true, resetToken: process.env.NODE_ENV === 'test' ? resetToken : undefined });
});

app.post('/v1/auth/reset-password', async (req, res) => {
  if (!validPassword(req.body.newPassword)) return res.status(400).json({ error: 'invalid_password' });
  const digest = sha256(String(req.body.token ?? '')); const client = await pool.connect();
  try {
    await client.query('begin');
    const r = await client.query("update auth_token set used_at=now() where kind='password_reset' and token_digest=$1 and used_at is null and expires_at>now() returning user_id", [digest]);
    if (!r.rowCount) { await client.query('rollback'); return res.status(400).json({ error: 'invalid_or_expired_token' }); }
    const hash = await argon2.hash(req.body.newPassword, { type: argon2.argon2id });
    await client.query('update auth_credential set password_hash=$1,password_changed_at=now() where user_id=$2', [hash, r.rows[0].user_id]);
    await client.query('update auth_session set revoked_at=now() where user_id=$1 and revoked_at is null', [r.rows[0].user_id]);
    await client.query('commit'); res.status(204).end();
  } finally { client.release(); }
});

app.post('/v1/auth/change-password', auth, async (req, res) => {
  if (!validPassword(req.body.newPassword)) return res.status(400).json({ error: 'invalid_password' });
  const r = await pool.query('select password_hash from auth_credential where user_id=$1', [req.identity.sub]);
  if (!r.rowCount || !(await argon2.verify(r.rows[0].password_hash, String(req.body.currentPassword ?? '')))) return res.status(403).json({ error: 'invalid_current_password' });
  const hash = await argon2.hash(req.body.newPassword, { type: argon2.argon2id });
  await pool.query('update auth_credential set password_hash=$1,password_changed_at=now() where user_id=$2', [hash, req.identity.sub]);
  res.status(204).end();
});

app.get('/v1/profile', auth, async (req, res) => {
  const r = await pool.query('select p.display_name,p.birth_date,p.theme_preference,u.email_normalized,u.email_verified_at from profile p join app_user u on u.id=p.user_id where p.user_id=$1', [req.identity.sub]);
  res.json(r.rows[0]);
});

app.post('/v1/families', auth, async (req, res) => {
  const name = String(req.body.name ?? '').trim(); if (!name) return res.status(400).json({ error: 'invalid_name' });
  const c = await pool.connect(); try { await c.query('begin'); const f = await c.query('insert into family_workspace(name,created_by) values($1,$2) returning id,name', [name, req.identity.sub]); await c.query("insert into family_membership(family_id,user_id,role) values($1,$2,'owner_admin')", [f.rows[0].id, req.identity.sub]); await c.query('commit'); res.status(201).json(f.rows[0]); } catch(e) { await c.query('rollback'); throw e; } finally { c.release(); }
});

app.post('/v1/families/:familyId/invitations', auth, async (req, res) => {
  const allowed = await pool.query("select 1 from family_membership where family_id=$1 and user_id=$2 and ended_at is null and role in ('owner_admin','parent_guardian')", [req.params.familyId, req.identity.sub]);
  if (!allowed.rowCount) return res.status(403).json({ error: 'forbidden' });
  const email = normalizeEmail(req.body.email); const role = req.body.role; const token = randomToken();
  const r = await pool.query("insert into family_invitation(family_id,invited_email_normalized,intended_role,token_digest,invited_by,expires_at) values($1,$2,$3,$4,$5,now()+interval '7 days') returning id,expires_at", [req.params.familyId,email,role,sha256(token),req.identity.sub]);
  res.status(201).json({ ...r.rows[0], invitationToken: process.env.NODE_ENV === 'test' ? token : undefined });
});

app.use((err, _req, res, _next) => { console.error(err); res.status(500).json({ error: 'internal_error' }); });

const port = Number(process.env.PORT ?? 8080);
if (process.env.NODE_ENV !== 'test') app.listen(port, () => console.log(`LifeMate API listening on ${port}`));
export default app;
