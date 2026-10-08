import crypto from 'node:crypto';
import express from 'express';
import argon2 from 'argon2';
import jwt from 'jsonwebtoken';
import { normalizeEmail, normalizePhone, isEmail, validPassword } from './auth_contacts.js';
import { createEmailProvider, createSmsProvider, safelyDeliver } from './auth_delivery.js';

const sha256 = (value) => crypto.createHash('sha256').update(value).digest('hex');
const randomToken = () => crypto.randomBytes(32).toString('base64url');
const uuid = /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i;

async function transaction(pool, operation) {
  const client = await pool.connect();
  try {
    await client.query('begin');
    const result = await operation(client);
    await client.query('commit');
    return result;
  } catch (error) {
    await client.query('rollback').catch(() => {});
    throw error;
  } finally { client.release(); }
}

export function createAuthRouter({ pool, jwtSecret, auth, env = process.env,
  emailProvider = createEmailProvider({ env }), smsProvider = createSmsProvider() }) {
  const router = express.Router();
  const testMode = env.NODE_ENV === 'test';
  const publicApp = env.PUBLIC_APP_URL ?? 'https://app.lifeguide.invalid';
  const dummyHash = argon2.hash(randomToken(), { type: argon2.argon2id });
  const digest = (value) => crypto.createHmac('sha256', jwtSecret).update(value).digest('hex');

  async function oneTimeToken(client, userId, kind, minutes) {
    const raw = randomToken();
    await client.query(
      "insert into auth_token(user_id,kind,token_digest,expires_at) values($1,$2,$3,now()+($4 || ' minutes')::interval)",
      [userId, kind, sha256(raw), String(minutes)],
    );
    return raw;
  }

  async function usableToken(client, raw, kind) {
    const tokenDigest = sha256(raw);
    const owner = await client.query('select user_id from auth_token where token_digest=$1 and kind=$2', [tokenDigest, kind]);
    if (!owner.rowCount) return null;
    const active = await client.query('select 1 from app_user where id=$1 and disabled_at is null for update', [owner.rows[0].user_id]);
    if (!active.rowCount) return null;
    const token = await client.query('select user_id from auth_token where token_digest=$1 and kind=$2 and used_at is null and expires_at>now() for update', [tokenDigest, kind]);
    return token.rows[0] ?? null;
  }

  async function session(client, userId) {
    const refreshToken = randomToken();
    const result = await client.query(
      "insert into auth_session(user_id,refresh_digest,expires_at) values($1,$2,now()+interval '30 days') returning id",
      [userId, sha256(refreshToken)],
    );
    return {
      accessToken: jwt.sign({ sub: userId, sid: result.rows[0].id, aud: 'lifemate-api' }, jwtSecret, { expiresIn: '15m', issuer: 'lifemate' }),
      refreshToken,
    };
  }

  async function claimDelivery(client, recipient, purpose, userId = null) {
    // The same limit is claimed before account lookup for known and unknown contacts.
    const recipientDigest = digest(`delivery:${recipient}`);
    await client.query('select pg_advisory_xact_lock(hashtextextended($1,0))', [recipientDigest + ':' + purpose]);
    const recent = await client.query(
      `select count(*)::int as n,
         ceil(extract(epoch from (max(requested_at)+interval '60 seconds'-now()))) as cooldown,
         ceil(extract(epoch from (min(requested_at)+interval '1 hour'-now()))) as window_wait
       from auth_delivery_attempt where recipient_digest=$1 and purpose=$2
         and requested_at>now()-interval '1 hour'`, [recipientDigest, purpose],
    );
    const row = recent.rows[0];
    const wait = row.n >= 3 ? Number(row.window_wait) : Number(row.cooldown);
    if (wait > 0) return { retryAfter: Math.max(1, wait) };
    const inserted = await client.query(
      'insert into auth_delivery_attempt(recipient_digest,purpose,user_id) values($1,$2,$3) returning id',
      [recipientDigest, purpose, userId],
    );
    return { attemptId: inserted.rows[0].id };
  }

  function limited(res, result) {
    if (!result.retryAfter) return false;
    res.setHeader('Retry-After', String(result.retryAfter));
    res.status(429).json({ error: 'rate_limited' });
    return true;
  }

  async function emailDelivery(userEmail, raw, kind, attemptId) {
    const verify = kind === 'email_verification';
    return safelyDeliver(emailProvider, {
      to: userEmail,
      subject: verify ? 'تأیید حساب لایف‌گاید' : 'بازیابی رمز عبور لایف‌گاید',
      text: `${verify ? 'برای تأیید حساب LifeGuide / لایف‌گاید' : 'برای ساخت رمز جدید لایف‌گاید'} این لینک را باز کن: ${publicApp}/${verify ? 'verify-email' : 'reset-password'}?token=${encodeURIComponent(raw)}\nاین لینک ${verify ? '۲۴ ساعت' : '۳۰ دقیقه'} اعتبار دارد. اگر این درخواست را نداده‌ای، پیام را نادیده بگیر.`,
    }, { pool, attemptId, env });
  }

  router.get('/capabilities', (_req, res) => res.json({
    emailDeliveryAvailable: Boolean(emailProvider.configured),
    emailStatus: emailProvider.status ?? 'UNVERIFIED',
    smsAvailable: Boolean(smsProvider.configured),
    smsStatus: smsProvider.status ?? 'UNVERIFIED',
  }));

  router.post('/register', async (req, res) => {
    const email = normalizeEmail(req.body?.email);
    const phone = req.body?.phone == null ? null : normalizePhone(req.body.phone);
    const name = String(req.body?.displayName ?? '').trim();
    if (!name || name.length > 100 || !validPassword(req.body?.password) ||
        (email && phone) || (!email && !phone) || (email && !isEmail(email)) ||
        (req.body?.phone != null && !phone)) return res.status(400).json({ error: 'invalid_input' });
    if (phone && !smsProvider.configured) return res.status(503).json({ error: 'sms_unavailable' });
    // Always hash valid registration input, including duplicates; never replace credentials.
    const hash = await argon2.hash(req.body.password, { type: argon2.argon2id });
    const result = await transaction(pool, async (client) => {
      const rate = email ? await claimDelivery(client, email, 'email_verification') : {};
      const inserted = await client.query(
        'insert into app_user(identity_subject,email_normalized,phone_normalized) values($1,$2,$3) on conflict do nothing returning id',
        [`local:${crypto.randomUUID()}`, email || null, phone],
      );
      if (!inserted.rowCount) return { ...rate };
      const userId = inserted.rows[0].id;
      await client.query("insert into profile(user_id,display_name,theme_preference) values($1,$2,'adult_blue')", [userId, name]);
      await client.query('insert into auth_credential(user_id,password_hash) values($1,$2)', [userId, hash]);
      let verificationToken;
      if (email) verificationToken = await oneTimeToken(client, userId, 'email_verification', 1440);
      if (rate.attemptId) await client.query('update auth_delivery_attempt set user_id=$2 where id=$1', [rate.attemptId, userId]);
      return { ...rate, userId, verificationToken };
    });
    // The response is sent before provider I/O, which cannot change a committed account response.
    res.status(testMode ? 201 : 202).json(testMode
      ? { accepted: true, userId: result.userId, verificationToken: result.verificationToken }
      : { accepted: true });
    if (result.verificationToken && result.attemptId) await emailDelivery(email, result.verificationToken, 'email_verification', result.attemptId);
    else if (result.attemptId) await pool.query("update auth_delivery_attempt set status='not_needed' where id=$1", [result.attemptId]).catch(() => {});
  });

  router.post('/resend-verification', async (req, res) => {
    const email = normalizeEmail(req.body?.email);
    if (!isEmail(email)) return res.status(400).json({ error: 'invalid_input' });
    const result = await transaction(pool, async (client) => {
      const rate = await claimDelivery(client, email, 'email_verification');
      if (rate.retryAfter) return rate;
      const user = await client.query('select id from app_user where email_normalized=$1 and email_verified_at is null and disabled_at is null for update', [email]);
      if (!user.rowCount) return rate;
      const token = await oneTimeToken(client, user.rows[0].id, 'email_verification', 1440);
      await client.query('update auth_delivery_attempt set user_id=$2 where id=$1', [rate.attemptId, user.rows[0].id]);
      return { ...rate, token };
    });
    if (limited(res, result)) return;
    res.status(202).json({ accepted: true });
    if (result.token) await emailDelivery(email, result.token, 'email_verification', result.attemptId);
    else await pool.query("update auth_delivery_attempt set status='not_needed' where id=$1", [result.attemptId]).catch(() => {});
  });

  router.post('/verify-email', async (req, res) => {
    if (!validPassword(req.body?.newPassword)) return res.status(400).json({ error: 'invalid_password' });
    const ok = await transaction(pool, async (client) => {
      const token = await usableToken(client, String(req.body?.token ?? ''), 'email_verification');
      if (!token) return false;
      const hash = await argon2.hash(req.body.newPassword, { type: argon2.argon2id });
      await client.query('update auth_credential set password_hash=$2,password_changed_at=now() where user_id=$1', [token.user_id, hash]);
      await client.query('update auth_session set revoked_at=now() where user_id=$1 and revoked_at is null', [token.user_id]);
      await client.query("update auth_token set used_at=now() where user_id=$1 and kind='email_verification' and used_at is null", [token.user_id]);
      await client.query('update app_user set email_verified_at=coalesce(email_verified_at,now()) where id=$1', [token.user_id]);
      return true;
    });
    if (!ok) return res.status(400).json({ error: 'invalid_or_expired_token' });
    res.status(204).end();
  });

  router.post('/login', async (req, res) => {
    const identifier = String(req.body?.identifier ?? req.body?.email ?? req.body?.phone ?? '').trim();
    const email = identifier.includes('@') ? normalizeEmail(identifier) : null;
    const phone = email ? null : normalizePhone(identifier);
    const result = await pool.query(
      `select u.id,u.email_verified_at,u.phone_verified_at,c.password_hash from app_user u
       join auth_credential c on c.user_id=u.id where u.disabled_at is null
         and (($1::text is not null and u.email_normalized=$1) or ($2::text is not null and u.phone_normalized=$2))`, [email, phone],
    );
    const password = String(req.body?.password ?? '');
    const matched = await argon2.verify(result.rows[0]?.password_hash ?? await dummyHash, password.slice(0, 200));
    if (!result.rowCount || password.length > 200 || !matched) return res.status(401).json({ error: 'invalid_credentials' });
    if (email ? !result.rows[0].email_verified_at : !result.rows[0].phone_verified_at) {
      return res.status(403).json({ error: email ? 'email_not_verified' : 'phone_not_verified' });
    }
    const tokens = await transaction(pool, async (client) => {
      const active = await client.query('select 1 from app_user where id=$1 and disabled_at is null for update', [result.rows[0].id]);
      if (!active.rowCount) return null;
      const current = await client.query('select c.password_hash,u.email_verified_at,u.phone_verified_at from auth_credential c join app_user u on u.id=c.user_id where c.user_id=$1', [result.rows[0].id]);
      // Recovery may have committed while this request verified a previously read hash.
      if (!current.rowCount || current.rows[0].password_hash !== result.rows[0].password_hash ||
          (email ? !current.rows[0].email_verified_at : !current.rows[0].phone_verified_at)) return null;
      return session(client, result.rows[0].id);
    });
    if (!tokens) return res.status(401).json({ error: 'invalid_credentials' });
    res.json(tokens);
  });

  router.post('/refresh', async (req, res) => {
    const tokens = await transaction(pool, async (client) => {
      const preliminary = await client.query('select user_id from auth_session where refresh_digest=$1', [sha256(String(req.body?.refreshToken ?? ''))]);
      if (!preliminary.rowCount) return null;
      // Account-first locking is shared with password/OTP recovery.
      const active = await client.query('select 1 from app_user where id=$1 and disabled_at is null for update', [preliminary.rows[0].user_id]);
      if (!active.rowCount) return null;
      const current = await client.query('select id,user_id from auth_session where refresh_digest=$1 and revoked_at is null and expires_at>now() for update', [sha256(String(req.body?.refreshToken ?? ''))]);
      if (!current.rowCount) return null;
      await client.query('update auth_session set revoked_at=now() where id=$1', [current.rows[0].id]);
      return session(client, current.rows[0].user_id);
    });
    if (!tokens) return res.status(401).json({ error: 'invalid_refresh_token' });
    res.json(tokens);
  });

  router.post('/forgot-password', async (req, res) => {
    const email = normalizeEmail(req.body?.email);
    if (!isEmail(email)) return res.json({ accepted: true });
    const result = await transaction(pool, async (client) => {
      const rate = await claimDelivery(client, email, 'password_reset');
      if (rate.retryAfter) return rate;
      const user = await client.query('select id from app_user where email_normalized=$1 and disabled_at is null for update', [email]);
      if (!user.rowCount) return rate;
      const token = await oneTimeToken(client, user.rows[0].id, 'password_reset', 30);
      await client.query('update auth_delivery_attempt set user_id=$2 where id=$1', [rate.attemptId, user.rows[0].id]);
      return { ...rate, token };
    });
    if (limited(res, result)) return;
    res.json(testMode ? { accepted: true, resetToken: result.token } : { accepted: true });
    if (result.token) await emailDelivery(email, result.token, 'password_reset', result.attemptId);
    else await pool.query("update auth_delivery_attempt set status='not_needed' where id=$1", [result.attemptId]).catch(() => {});
  });

  router.post('/reset-password', async (req, res) => {
    if (!validPassword(req.body?.newPassword)) return res.status(400).json({ error: 'invalid_password' });
    const ok = await transaction(pool, async (client) => {
      const token = await usableToken(client, String(req.body?.token ?? ''), 'password_reset');
      if (!token) return false;
      const hash = await argon2.hash(req.body.newPassword, { type: argon2.argon2id });
      await client.query('update auth_credential set password_hash=$2,password_changed_at=now() where user_id=$1', [token.user_id, hash]);
      await client.query("update auth_token set used_at=now() where user_id=$1 and kind='password_reset' and used_at is null", [token.user_id]);
      await client.query('update auth_session set revoked_at=now() where user_id=$1 and revoked_at is null', [token.user_id]);
      return true;
    });
    if (!ok) return res.status(400).json({ error: 'invalid_or_expired_token' });
    res.status(204).end();
  });

  router.post('/change-password', auth, async (req, res) => {
    if (!validPassword(req.body?.newPassword)) return res.status(400).json({ error: 'invalid_password' });
    const ok = await transaction(pool, async (client) => {
      const active = await client.query('select 1 from app_user where id=$1 and disabled_at is null for update', [req.identity.sub]);
      if (!active.rowCount) return false;
      const credential = await client.query('select password_hash from auth_credential where user_id=$1 for update', [req.identity.sub]);
      if (!credential.rowCount || !(await argon2.verify(credential.rows[0].password_hash, String(req.body?.currentPassword ?? '')))) return false;
      const hash = await argon2.hash(req.body.newPassword, { type: argon2.argon2id });
      await client.query('update auth_credential set password_hash=$2,password_changed_at=now() where user_id=$1', [req.identity.sub, hash]);
      await client.query('update auth_session set revoked_at=now() where user_id=$1 and id<>$2 and revoked_at is null', [req.identity.sub, req.identity.sid]);
      return true;
    });
    if (!ok) return res.status(403).json({ error: 'invalid_current_password' });
    res.status(204).end();
  });

  router.post('/logout', async (req, res) => {
    const refresh = req.body?.refreshToken;
    if (typeof refresh === 'string') {
      await pool.query('update auth_session set revoked_at=coalesce(revoked_at,now()) where refresh_digest=$1', [sha256(refresh)]);
    } else {
      let identity;
      try {
        identity = jwt.verify(req.headers.authorization?.replace(/^Bearer\s+/i, ''), jwtSecret, { audience: 'lifemate-api', issuer: 'lifemate' });
      } catch { /* Uniform logout also accepts expired, missing or revoked proof. */ }
      if (identity?.sid && identity?.sub) await pool.query('update auth_session set revoked_at=coalesce(revoked_at,now()) where id=$1 and user_id=$2', [identity.sid, identity.sub]);
    }
    res.status(204).end();
  });

  router.post('/phone/request-otp', async (req, res) => {
    if (!smsProvider.configured) return res.status(503).json({ error: 'sms_unavailable' });
    const phone = normalizePhone(req.body?.phone);
    const purpose = req.body?.purpose ?? 'login';
    if (!phone || !['verify', 'login', 'recovery'].includes(purpose)) return res.status(400).json({ error: 'invalid_input' });
    const result = await transaction(pool, async (client) => {
      const rate = await claimDelivery(client, phone, 'phone_otp');
      if (rate.retryAfter) return rate;
      const user = await client.query('select id from app_user where phone_normalized=$1 and disabled_at is null', [phone]);
      const challengeId = crypto.randomUUID();
      const code = String(crypto.randomInt(0, 1000000)).padStart(6, '0');
      await client.query("insert into auth_phone_challenge(id,user_id,purpose,code_digest,expires_at) values($1,$2,$3,$4,now()+interval '5 minutes')", [challengeId, user.rows[0]?.id ?? null, purpose, digest(`otp:${challengeId}:${code}`)]);
      if (user.rowCount) await client.query('update auth_delivery_attempt set user_id=$2 where id=$1', [rate.attemptId, user.rows[0].id]);
      return { ...rate, challengeId, code, known: Boolean(user.rowCount) };
    });
    if (limited(res, result)) return;
    res.status(202).json({ accepted: true, challengeId: result.challengeId, expiresIn: 300 });
    if (result.known) await safelyDeliver({ configured: true, send: (message) => smsProvider.sendOtp(message) }, { phone, code: result.code, expiresIn: 300 }, { pool, attemptId: result.attemptId, env });
    else await pool.query("update auth_delivery_attempt set status='not_needed' where id=$1", [result.attemptId]).catch(() => {});
  });

  router.post('/phone/verify-otp', async (req, res) => {
    if (!smsProvider.configured) return res.status(503).json({ error: 'sms_unavailable' });
    const challengeId = String(req.body?.challengeId ?? '');
    const code = String(req.body?.code ?? '');
    if (!uuid.test(challengeId) || !/^\d{6}$/.test(code)) return res.status(401).json({ error: 'invalid_or_expired_otp' });
    const result = await transaction(pool, async (client) => {
      const owner = await client.query('select user_id from auth_phone_challenge where id=$1', [challengeId]);
      // Account-first locking also serializes two different challenges for one account.
      let user;
      if (owner.rows[0]?.user_id) {
        user = await client.query('select phone_verified_at from app_user where id=$1 and disabled_at is null for update', [owner.rows[0].user_id]);
        if (!user.rowCount) return null;
      }
      const challenge = await client.query('select * from auth_phone_challenge where id=$1 and used_at is null and expires_at>now() and attempts<5 for update', [challengeId]);
      if (!challenge.rowCount) return null;
      const row = challenge.rows[0];
      await client.query('update auth_phone_challenge set attempts=attempts+1 where id=$1', [challengeId]);
      const provided = Buffer.from(digest(`otp:${challengeId}:${code}`), 'hex');
      if (!crypto.timingSafeEqual(provided, Buffer.from(row.code_digest, 'hex')) || !row.user_id) return null;
      if (!user?.rowCount || (row.purpose === 'login' && !user.rows[0].phone_verified_at)) return null;
      if (row.purpose !== 'login') {
        if (!validPassword(req.body?.newPassword)) return { passwordRequired: true };
        const hash = await argon2.hash(req.body.newPassword, { type: argon2.argon2id });
        await client.query('update auth_credential set password_hash=$2,password_changed_at=now() where user_id=$1', [row.user_id, hash]);
        await client.query('update app_user set phone_verified_at=coalesce(phone_verified_at,now()) where id=$1', [row.user_id]);
        await client.query('update auth_session set revoked_at=now() where user_id=$1 and revoked_at is null', [row.user_id]);
      }
      await client.query('update auth_phone_challenge set used_at=now() where user_id=$1 and used_at is null', [row.user_id]);
      return session(client, row.user_id);
    });
    if (result?.passwordRequired) return res.status(400).json({ error: 'invalid_password' });
    if (!result) return res.status(401).json({ error: 'invalid_or_expired_otp' });
    res.json(result);
  });

  return router;
}
