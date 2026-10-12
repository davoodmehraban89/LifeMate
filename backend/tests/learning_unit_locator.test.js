import test, { before, after } from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import net from 'node:net';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import pg from 'pg';
import jwt from 'jsonwebtoken';

// Real HTTP/SQL against a local synthetic test DB; no teaching approval.
const fixtureUrl = process.env.TEST_FIXTURE_DATABASE_URL ?? process.env.DATABASE_URL;
assert.ok(fixtureUrl, 'Locator tests require a migrated synthetic PostgreSQL fixture');
const location = new URL(fixtureUrl);
assert.ok(['127.0.0.1', 'localhost', '[::1]', '::1'].includes(location.hostname));
assert.ok(location.pathname.includes('test') || location.pathname === '/lifemate_ci' ||
  /^\/lifeguide_roles_source_[a-f0-9]{16}$/.test(location.pathname), 'Synthetic test database required');
const pool = new pg.Pool({ connectionString: fixtureUrl });
const secret = 'synthetic-unit-locator-secret-at-least-32-characters';
const ids = { subject: crypto.randomUUID(), course: crypto.randomUUID(), unit: crypto.randomUUID() };
const actors = [];
let child, base;

before(async () => {
  const reservation = net.createServer();
  reservation.listen(0, '127.0.0.1'); await once(reservation, 'listening');
  const port = reservation.address().port;
  await new Promise(resolve => reservation.close(resolve));
  const env = { ...process.env, PORT: String(port), JWT_SECRET: secret, NODE_ENV: 'production',
    SMS_PROVIDER: 'disabled', EMAIL_PROVIDER: 'disabled', ENABLE_SENSITIVE_FEATURES: 'false' };
  delete env.TEST_FIXTURE_DATABASE_URL;
  for (const key of ['SMS_PROVIDER_URL', 'SMS_PROVIDER_TOKEN', 'EMAIL_FROM', 'RESEND_API_KEY',
    'SMTP_HOST', 'SMTP_USER', 'SMTP_PASSWORD', 'AI_API_KEY', 'AI_BASE_URL', 'AI_MODEL', 'OPENAI_API_KEY']) env[key] = '';
  child = spawn(process.execPath, ['src/entrypoint.js'], {
    cwd: new URL('../', import.meta.url), env, stdio: ['ignore', 'pipe', 'pipe'],
  });
  let ready = false;
  child.stdout.on('data', chunk => { if (chunk.toString().includes('"type":"startup"')) ready = true; });
  child.stderr.on('data', () => {});
  for (let retry = 0; retry < 200 && !ready; retry++) await new Promise(resolve => setTimeout(resolve, 25));
  assert.ok(ready, 'Synthetic API must start'); base = `http://127.0.0.1:${port}`;
  await pool.query(`insert into curriculum_subject(id,school_year,national_grade,code,name_fa)
    values($1,'1405-1406',5,$2,'Synthetic locator subject')`, [ids.subject, `locator-${ids.subject}`]);
  await pool.query(`insert into textbook_catalog(id,curriculum_subject_id,title_fa,source_url,stable_book_key)
    values($1,$2,'Synthetic locator course','https://chap.sch.ir/',$3)`, [ids.course, ids.subject, `locator:${ids.course}`]);
  await pool.query(`insert into learning_unit(id,textbook_id,unit_key,title_fa,order_index,index_kind,source_evidence_url)
    values($1,$2,'locator-unit','درس صرفاً آزمایشی',1,'lesson','https://chap.sch.ir/')`, [ids.unit, ids.course]);
  for (let index = 0; index < 2; index++) {
    const id = crypto.randomUUID(), sid = crypto.randomUUID(); actors.push({ id, sid });
    await pool.query(`insert into app_user(id,identity_subject,email_normalized,email_verified_at)
      values($1,$2,$3,now())`, [id, `locator:${id}`, `${id}@example.test`]);
    await pool.query(`insert into profile(user_id,display_name,theme_preference)
      values($1,'Synthetic locator learner','adult_blue')`, [id]);
    await pool.query(`insert into auth_session(id,user_id,refresh_digest,expires_at)
      values($1,$2,$3,now()+interval '1 day')`, [sid, id, crypto.randomUUID()]);
    actors[index].token = jwt.sign({ sub: id, sid, aud: 'lifemate-api' }, secret,
      { issuer: 'lifemate', expiresIn: '15m' });
  }
  await pool.query(`insert into learning_progress(owner_user_id,unit_id,status,source,version)
    values($1,$2,'in_progress','self_reported',1)`, [actors[0].id, ids.unit]);
});

after(async () => {
  if (child && child.exitCode === null) { const closed = once(child, 'close'); child.kill('SIGTERM'); await closed; }
  try {
    await pool.query('delete from app_user where id=any($1::uuid[])', [actors.map(actor => actor.id)]);
    await pool.query('delete from learning_unit where id=$1', [ids.unit]);
    await pool.query('delete from textbook_catalog where id=$1', [ids.course]);
    await pool.query('delete from curriculum_subject where id=$1', [ids.subject]);
  } finally { await pool.end(); }
});

async function get(unit, actor, query = '') {
  const response = await fetch(`${base}/v1/education/units/${unit}${query}`, {
    headers: actor ? { authorization: `Bearer ${actor.token}` } : {},
  });
  return { status: response.status, body: response.headers.get('content-type')?.includes('application/json')
    ? await response.json() : null };
}

test('locator gives authenticated catalogue navigation without owner or progress data', async () => {
  const expected = { id: ids.unit, titleFa: 'درس صرفاً آزمایشی', courseId: ids.course };
  for (const actor of actors) {
    const result = await get(ids.unit, actor, `?ownerUserId=${actors[0].id}`);
    assert.equal(result.status, 200); assert.deepEqual(result.body.unit, expected);
    assert.deepEqual(Object.keys(result.body).sort(), ['fetchedAt', 'unit']);
    assert.ok(Number.isFinite(Date.parse(result.body.fetchedAt)));
    assert.equal(JSON.stringify(result.body).includes(actors[0].id), false);
    assert.equal(JSON.stringify(result.body).includes('in_progress'), false);
  }
});

test('locator requires current session and bounds UUID and absent catalogue items', async () => {
  assert.equal((await get(ids.unit)).status, 401);
  assert.equal((await get('not-a-uuid', actors[0])).status, 400);
  assert.equal((await get(crypto.randomUUID(), actors[0])).status, 404);
});

test('inactive units and non-library legacy books cannot be located', async () => {
  await pool.query('update learning_unit set active=false where id=$1', [ids.unit]);
  try { assert.equal((await get(ids.unit, actors[0])).status, 404); }
  finally { await pool.query('update learning_unit set active=true where id=$1', [ids.unit]); }
  await pool.query('update textbook_catalog set stable_book_key=null where id=$1', [ids.course]);
  try { assert.equal((await get(ids.unit, actors[0])).status, 404); }
  finally { await pool.query('update textbook_catalog set stable_book_key=$2 where id=$1', [ids.course, `locator:${ids.course}`]); }
});

test('locator reflects current public title but neither private progress nor injected owner context', async () => {
  const original = await get(ids.unit, actors[1]);
  await pool.query("update learning_progress set status='completed',version=version+1,updated_at=now() where owner_user_id=$1 and unit_id=$2", [actors[0].id, ids.unit]);
  const afterProgress = await get(ids.unit, actors[1], `?ownerUserId=${actors[0].id}&childId=${actors[0].id}&role=parent_guardian`);
  assert.equal(afterProgress.status, 200); assert.deepEqual(afterProgress.body.unit, original.body.unit);
  assert.deepEqual(Object.keys(afterProgress.body).sort(), ['fetchedAt', 'unit']);
  assert.equal(JSON.stringify(afterProgress.body).includes('completed'), false);
  assert.equal(JSON.stringify(afterProgress.body).includes(actors[0].id), false);
  await pool.query('update learning_unit set title_fa=$2 where id=$1', [ids.unit, 'عنوان عمومی اصلاح‌شده']);
  try {
    const changed = await get(ids.unit, actors[1]);
    assert.equal(changed.status, 200);
    assert.deepEqual(changed.body.unit, { ...original.body.unit, titleFa: 'عنوان عمومی اصلاح‌شده' });
  } finally { await pool.query('update learning_unit set title_fa=$2 where id=$1', [ids.unit, original.body.unit.titleFa]); }
});

test('locator rechecks token expiry, session expiry and disabled account state on each read', async () => {
  const actor = actors[0];
  const expired = { ...actor, token: jwt.sign({ sub: actor.id, sid: actor.sid, aud: 'lifemate-api' }, secret, { issuer: 'lifemate', expiresIn: -1 }) };
  const expiredResult = await get(ids.unit, expired);
  assert.equal(expiredResult.status, 401); assert.deepEqual(Object.keys(expiredResult.body), ['error']);
  await pool.query("update auth_session set expires_at=now()-interval '1 second' where id=$1", [actor.sid]);
  try { assert.equal((await get(ids.unit, actor)).status, 401); }
  finally { await pool.query("update auth_session set expires_at=now()+interval '1 day' where id=$1", [actor.sid]); }
  await pool.query('update app_user set disabled_at=now() where id=$1', [actor.id]);
  try {
    const disabled = await get(ids.unit, actor);
    assert.equal(disabled.status, 401); assert.deepEqual(Object.keys(disabled.body), ['error']);
  } finally { await pool.query('update app_user set disabled_at=null where id=$1', [actor.id]); }
  assert.equal((await get(ids.unit, actor)).status, 200);
});

test('revoked session cannot resolve lesson metadata', async () => {
  await pool.query('update auth_session set revoked_at=now() where id=$1', [actors[1].sid]);
  assert.equal((await get(ids.unit, actors[1])).status, 401);
});
