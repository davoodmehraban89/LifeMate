// Explicitly synthetic fixture; not a registration/email-verification bypass.
// Never call this against a live database. Compose runbook uses local Docker.
import crypto from 'node:crypto';
import argon2 from 'argon2';
import pg from 'pg';
if (process.env.ALLOW_SYNTHETIC_SEED !== 'yes') throw new Error('ALLOW_SYNTHETIC_SEED=yes is required');
const password = process.env.SYNTHETIC_PASSWORD;
if (typeof password !== 'string' || password.length < 10) throw new Error('Provide a synthetic password of at least 10 characters');
const pool = new pg.Pool();
const client = await pool.connect();
try {
  await client.query('begin');
  const email = 'compose-smoke@lifeguide.test';
  const existing = await client.query('select id,identity_subject from app_user where email_normalized=$1 for update', [email]);
  let id;
  if (existing.rowCount) {
    if (!existing.rows[0].identity_subject.startsWith('compose-synthetic:')) throw new Error('Refusing to replace an existing non-fixture account');
    id = existing.rows[0].id;
  } else {
    const user = await client.query('insert into app_user(identity_subject,email_normalized,email_verified_at) values($1,$2,now()) returning id', [`compose-synthetic:${crypto.randomUUID()}`, email]);
    id = user.rows[0].id;
    await client.query("insert into profile(user_id,display_name,theme_preference) values($1,'LifeGuide Synthetic Smoke','adult_blue')", [id]);
  }
  await client.query('insert into auth_credential(user_id,password_hash) values($1,$2) on conflict(user_id) do update set password_hash=excluded.password_hash', [id, await argon2.hash(password, { type: argon2.argon2id })]);
  await client.query('commit');
  console.log('Synthetic local fixture ready: compose-smoke@lifeguide.test (password not logged)');
} catch (error) {
  await client.query('rollback');
  throw error;
} finally {
  client.release();
  await pool.end();
}
