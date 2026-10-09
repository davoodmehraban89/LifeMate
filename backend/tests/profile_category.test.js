import test, { after } from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import jwt from 'jsonwebtoken';
import pg from 'pg';

assert.ok(process.env.DATABASE_URL, 'Use a migrated synthetic PostgreSQL database');
assert.ok(process.env.JWT_SECRET?.length >= 32, 'Use a synthetic JWT secret');
const { app, pool } = await import('../src/server.js');
const users = [];
const families = [];
let server = app.listen(0, '127.0.0.1');
await new Promise((resolve) => server.once('listening', resolve));
let base = `http://127.0.0.1:${server.address().port}`;

after(async () => {
  await new Promise((resolve) => server.close(resolve));
  try {
    if (families.length) {
      await pool.query('delete from access_audit where family_id=any($1::uuid[])', [families]);
      await pool.query('delete from family_workspace where id=any($1::uuid[])', [families]);
    }
    if (users.length) await pool.query('delete from app_user where id=any($1::uuid[])', [users]);
  } finally { await pool.end(); }
});

async function user() {
  const id = crypto.randomUUID(), sid = crypto.randomUUID();
  await pool.query('insert into app_user(id,identity_subject,email_normalized,email_verified_at) values($1,$2,$3,now())', [id, `profile-test:${id}`, `profile-${id}@example.test`]);
  users.push(id);
  await pool.query("insert into profile(user_id,display_name,theme_preference) values($1,'Synthetic Profile','adult_blue')", [id]);
  await pool.query("insert into auth_session(id,user_id,refresh_digest,expires_at) values($1,$2,$3,now()+interval '1 day')", [sid, id, crypto.randomBytes(32).toString('hex')]);
  return { id, token: jwt.sign({ sub: id, sid, aud: 'lifemate-api' }, process.env.JWT_SECRET, { issuer: 'lifemate', expiresIn: '15m' }) };
}

async function fixture() {
  const [child, parent, outsider] = await Promise.all([user(), user(), user()]);
  const familyId = crypto.randomUUID();
  await pool.query("insert into family_workspace(id,name,created_by) values($1,'Synthetic Profile Family',$2)", [familyId, parent.id]);
  families.push(familyId);
  await pool.query("insert into family_membership(family_id,user_id,role) values($1,$2,'teen_minor'),($1,$3,'parent_guardian')", [familyId, child.id, parent.id]);
  await pool.query('insert into guardian_relationship(family_id,guardian_user_id,minor_user_id) values($1,$2,$3)', [familyId, parent.id, child.id]);
  return { child, parent, outsider, familyId };
}

async function request(path, { method = 'GET', actor, body } = {}) {
  const response = await fetch(base + path, { method, headers: { 'content-type': 'application/json', ...(actor ? { authorization: `Bearer ${actor.token}` } : {}) }, body: body === undefined ? undefined : JSON.stringify(body) });
  const text = await response.text();
  return { status: response.status, body: text && response.headers.get('content-type')?.includes('application/json') ? JSON.parse(text) : text };
}

test('profile category has an explicit adult default and edits never change family roles or theme', async () => {
  const f = await fixture();
  const initial = await request('/v1/profile', { actor: f.child });
  assert.equal(initial.status, 200);
  assert.equal(initial.body.profile_category, 'adult');
  const updated = await request('/v1/profile', { method: 'PATCH', actor: f.parent, body: { displayName: 'ویرایش ساختگی', profileCategory: 'girl_minor' } });
  assert.equal(updated.status, 200);
  assert.equal(updated.body.profile_category, 'girl_minor');
  assert.equal(updated.body.theme_preference, 'adult_blue');
  assert.equal((await pool.query('select role from family_membership where family_id=$1 and user_id=$2', [f.familyId, f.parent.id])).rows[0].role, 'parent_guardian');
  const changedTheme = await request('/v1/profile', { method: 'PATCH', actor: f.parent, body: { themePreference: 'boy_blue' } });
  assert.equal(changedTheme.body.profile_category, 'girl_minor');
  assert.equal(changedTheme.body.display_name, 'ویرایش ساختگی');
  await pool.query("update family_membership set role='adult_member',ended_at=now() where family_id=$1 and user_id=$2", [f.familyId, f.parent.id]);
  const read = await request('/v1/profile', { actor: f.parent });
  assert.equal(read.body.profile_category, 'girl_minor');
  assert.equal(read.body.theme_preference, 'boy_blue');
});

test('profile validation returns 400 for invalid real calendar dates and categories without partial writes', async () => {
  const actor = await user();
  for (const birthDate of ['not-a-date', '2026-02-30', '2026-13-01', '2008-02-29T00:00:00Z', 20080229]) {
    const bad = await request('/v1/profile', { method: 'PATCH', actor, body: { displayName: 'Must Not Save', birthDate } });
    assert.equal(bad.status, 400, String(birthDate));
    assert.equal(bad.body.error, 'invalid_birth_date');
  }
  assert.equal((await request('/v1/profile', { method: 'PATCH', actor, body: { profileCategory: 'parent_guardian' } })).status, 400);
  assert.equal((await request('/v1/profile', { method: 'PATCH', actor, body: { displayName: '' } })).status, 400);
  assert.equal((await request('/v1/profile', { method: 'PATCH', actor, body: { themePreference: 'unknown' } })).status, 400);
  assert.equal((await request('/v1/profile', { actor })).body.display_name, 'Synthetic Profile');
  const valid = await request('/v1/profile', { method: 'PATCH', actor, body: { birthDate: '2008-02-29', profileCategory: 'boy_minor', themePreference: 'custom' } });
  assert.equal(valid.status, 200);
  const saved = (await pool.query('select birth_date::text,profile_category,theme_preference from profile where user_id=$1', [actor.id])).rows[0];
  assert.deepEqual(saved, { birth_date: '2008-02-29', profile_category: 'boy_minor', theme_preference: 'custom' });
});

test('both profile date aliases reject invalid dates and retain the previous calendar day', async () => {
  const actor = await user();
  await pool.query("update profile set birth_date='2008-02-29' where user_id=$1", [actor.id]);
  for (const path of ['/v1/profile', '/v1/me/iran-profile']) {
    for (const birthDate of ['2026-02-30', 'invalid-private-birthday', '2026-13-01']) {
      const result = await request(path, { method: 'PATCH', actor, body: { birthDate } });
      assert.equal(result.status, 400, path);
      assert.equal(result.body.error, 'invalid_birth_date');
    }
  }
  assert.equal((await pool.query('select birth_date::text from profile where user_id=$1', [actor.id])).rows[0].birth_date, '2008-02-29');
});

test('profile and learning CRUD reject missing sessions and cannot target another profile', async () => {
  const f = await fixture();
  const id = crypto.randomUUID();
  for (const [method, path] of [['GET', '/v1/profile'], ['PATCH', '/v1/profile'], ['GET', '/v1/learning/goals'], ['POST', '/v1/learning/goals'], ['GET', `/v1/learning/goals/${id}`], ['PATCH', `/v1/learning/goals/${id}`], ['DELETE', `/v1/learning/goals/${id}`]]) {
    assert.equal((await request(path, { method, body: method === 'GET' ? undefined : {} })).status, 401, path);
  }
  const forged = await request('/v1/profile', { method: 'PATCH', actor: f.child, body: { userId: f.parent.id, displayName: 'Owned Change', profileCategory: 'boy_minor' } });
  assert.equal(forged.status, 200);
  assert.equal((await request('/v1/profile', { actor: f.parent })).body.display_name, 'Synthetic Profile');
  assert.equal((await request('/v1/profile', { actor: f.child })).body.display_name, 'Owned Change');
});

test('learning goals create, read, edit and safely archive under the same owner and stable ID', async () => {
  const f = await fixture();
  const created = await request('/v1/learning/goals', { method: 'POST', actor: f.child, body: { title: 'هدف ساختگی', target: 'Private synthetic target' } });
  assert.equal(created.status, 201);
  const path = `/v1/learning/goals/${created.body.id}`;
  const read = await request(path, { actor: f.child });
  assert.equal(read.status, 200);
  assert.equal(read.body.target, 'Private synthetic target');
  for (const viewer of [f.parent, f.outsider]) {
    assert.equal((await request(path, { actor: viewer })).status, 404);
    assert.equal((await request(path, { method: 'PATCH', actor: viewer, body: { title: 'Forbidden' } })).status, 404);
    assert.equal((await request(path, { method: 'DELETE', actor: viewer })).status, 404);
    assert.equal((await request('/v1/learning/goals', { actor: viewer })).body.items.length, 0);
  }
  const checkin = await request('/v1/learning/checkins', { method: 'POST', actor: f.child, body: { learningGoalId: created.body.id, confidence: 3, difficulty: 3, note: 'Private synthetic note' } });
  assert.equal(checkin.status, 201);
  const edited = await request(path, { method: 'PATCH', actor: f.child, body: { title: 'ویرایش هدف', target: null, status: 'completed' } });
  assert.equal(edited.status, 200);
  assert.equal(edited.body.id, created.body.id);
  assert.equal(edited.body.title, 'ویرایش هدف');
  assert.equal(edited.body.target, null);
  await new Promise((resolve) => server.close(resolve));
  server = app.listen(0, '127.0.0.1');
  await new Promise((resolve) => server.once('listening', resolve));
  base = `http://127.0.0.1:${server.address().port}`;
  assert.equal((await request(path, { actor: f.child })).body.status, 'completed');
  for (let attempt = 0; attempt < 2; attempt++) assert.equal((await request(path, { method: 'DELETE', actor: f.child })).status, 204);
  assert.equal((await request('/v1/learning/goals', { actor: f.child })).body.items.length, 0);
  assert.equal((await request(path, { actor: f.child })).body.status, 'archived');
  assert.equal((await request(path, { method: 'PATCH', actor: f.child, body: { status: 'active' } })).status, 409);
  const retained = (await pool.query('select learning_goal_id,note from learning_checkin where id=$1', [checkin.body.id])).rows[0];
  assert.deepEqual(retained, { learning_goal_id: created.body.id, note: 'Private synthetic note' });
});

test('learning goal edits validate ownership of subjects, IDs and allowed statuses', async () => {
  const f = await fixture();
  const invalidCreate = await request('/v1/learning/goals', { method: 'POST', actor: f.child, body: { title: 'Synthetic goal', subjectId: 'not-a-uuid' } });
  assert.equal(invalidCreate.status, 400);
  assert.equal(invalidCreate.body.error, 'invalid_subject_id');
  const created = await request('/v1/learning/goals', { method: 'POST', actor: f.child, body: { title: 'Synthetic goal' } });
  const path = `/v1/learning/goals/${created.body.id}`;
  const context = await pool.query("insert into life_context(user_id,kind,title) values($1,'student','Synthetic class') returning id", [f.outsider.id]);
  const year = await pool.query("insert into academic_year(student_user_id,life_context_id,title,starts_on,ends_on) values($1,$2,'Synthetic year','2026-09-01','2027-06-01') returning id", [f.outsider.id, context.rows[0].id]);
  const term = await pool.query("insert into academic_term(academic_year_id,title,starts_on,ends_on) values($1,'Synthetic term','2026-09-01','2026-12-01') returning id", [year.rows[0].id]);
  const subject = await pool.query("insert into subject(student_user_id,academic_term_id,name) values($1,$2,'Synthetic math') returning id", [f.outsider.id, term.rows[0].id]);
  assert.equal((await request(path, { method: 'PATCH', actor: f.child, body: { subjectId: subject.rows[0].id } })).status, 403);
  assert.equal((await request(path, { method: 'PATCH', actor: f.child, body: { status: 'achieved' } })).status, 400);
  assert.equal((await request(path, { method: 'PATCH', actor: f.child, body: { title: '' } })).status, 400);
  assert.equal((await request('/v1/learning/goals/not-a-uuid', { method: 'PATCH', actor: f.child, body: { title: 'Valid' } })).status, 400);
  assert.equal((await request(path, { actor: f.child })).body.title, 'Synthetic goal');
});

test('profile migration derives legacy categories from themes only and new records default to adult', async () => {
  // A real PostgreSQL session with a temporary legacy table exercises the exact
  // migration without changing the already-migrated shared test schema.
  const client = new pg.Client({ connectionString: process.env.DATABASE_URL });
  await client.connect();
  try {
    await client.query('create temporary table profile(user_id uuid primary key,theme_preference text)');
    await client.query('create temporary table family_membership(user_id uuid,role text)');
    const legacy = [['girl_pink', 'girl_minor', 'adult_member'], ['boy_blue', 'boy_minor', 'parent_guardian'], ['adult_blue', 'adult', 'teen_minor'], ['custom', 'adult', 'teen_minor'], [null, 'adult', 'parent_guardian']];
    for (const [theme, , role] of legacy) {
      const id = crypto.randomUUID();
      await client.query('insert into profile(user_id,theme_preference) values($1,$2)', [id, theme]);
      await client.query('insert into family_membership(user_id,role) values($1,$2)', [id, role]);
    }
    await client.query(await fs.readFile(new URL('../migrations/0011_profile_category.sql', import.meta.url), 'utf8'));
    const rows = await client.query('select theme_preference,profile_category from profile');
    for (const [theme, expected] of legacy) assert.equal(rows.rows.find((row) => row.theme_preference === theme).profile_category, expected);
    const created = await client.query("insert into profile(user_id,theme_preference) values($1,'girl_pink') returning profile_category", [crypto.randomUUID()]);
    assert.equal(created.rows[0].profile_category, 'adult');
    await assert.rejects(client.query("insert into profile(user_id,profile_category) values($1,'parent_guardian')", [crypto.randomUUID()]), (error) => error.code === '23514');
  } finally { await client.end(); }
});
