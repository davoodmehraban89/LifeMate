import test, { after, before } from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import http from 'node:http';
import express from 'express';
import jwt from 'jsonwebtoken';
import pg from 'pg';
import { createPhase4Router } from '../src/phase4.js';
import { createPhase6Router } from '../src/phase6.js';
import { createSessionAuth } from '../src/session_auth.js';
import { operationalErrorHandler } from '../src/operations.js';

assert.ok(process.env.DATABASE_URL, 'Configure a separate synthetic PostgreSQL test database');
const pool = new pg.Pool({ connectionString: process.env.DATABASE_URL });
const secret = 'synthetic-privacy-test-secret-at-least-32-characters';
const users = [];
const families = [];
const servers = [];
let defaultBase;
let enabledBase;

async function serve(options) {
  const app = express();
  app.use(express.json({ limit: '64kb' }));
  const auth = createSessionAuth({ pool, jwtSecret: secret });
  app.use('/v1', createPhase4Router({ pool, auth, ...options }));
  app.use('/v1', createPhase6Router({ pool, auth, ...options }));
  app.use(operationalErrorHandler);
  const server = app.listen(0, '127.0.0.1');
  await new Promise((resolve) => server.once('listening', resolve));
  servers.push(server);
  return `http://127.0.0.1:${server.address().port}`;
}

before(async () => {
  delete process.env.ENABLE_SENSITIVE_FEATURES;
  defaultBase = await serve({});
  enabledBase = await serve({ sensitiveFeaturesEnabled: true });
});

after(async () => {
  for (const server of servers) await new Promise((resolve) => server.close(resolve));
  try {
    if (families.length) {
      await pool.query('delete from access_audit where family_id=any($1::uuid[])', [families]);
      await pool.query('delete from family_workspace where id=any($1::uuid[])', [families]);
    }
    if (users.length) await pool.query('delete from app_user where id=any($1::uuid[])', [users]);
  } finally {
    await pool.end();
  }
});

async function user() {
  const id = crypto.randomUUID();
  const sid = crypto.randomUUID();
  await pool.query(
    'insert into app_user(id,identity_subject,email_normalized,email_verified_at) values($1,$2,$3,now())',
    [id, `privacy-test:${id}`, `privacy-test-${id}@example.test`],
  );
  users.push(id);
  await pool.query("insert into profile(user_id,display_name,theme_preference) values($1,'Synthetic Privacy','adult_blue')", [id]);
  await pool.query(
    "insert into auth_session(id,user_id,refresh_digest,expires_at) values($1,$2,$3,now()+interval '1 day')",
    [sid, id, crypto.randomBytes(32).toString('hex')],
  );
  return { id, token: jwt.sign({ sub: id, sid, aud: 'lifemate-api' }, secret, { issuer: 'lifemate', expiresIn: '15m' }) };
}

async function fixture() {
  const [child, parent, selected, outsider] = await Promise.all([user(), user(), user(), user()]);
  const familyId = crypto.randomUUID();
  await pool.query('insert into family_workspace(id,name,created_by) values($1,$2,$3)', [familyId, 'Synthetic Privacy Family', parent.id]);
  families.push(familyId);
  for (const [member, role] of [[child, 'teen_minor'], [parent, 'parent_guardian'], [selected, 'adult_member']]) {
    await pool.query('insert into family_membership(family_id,user_id,role) values($1,$2,$3)', [familyId, member.id, role]);
  }
  await pool.query('insert into guardian_relationship(family_id,guardian_user_id,minor_user_id) values($1,$2,$3)', [familyId, parent.id, child.id]);
  return { child, parent, selected, outsider, familyId };
}

async function plan(f, visibility, { kind = 'assignment', status = 'planned', minutes = null } = {}) {
  const row = await pool.query(
    `insert into plan_item(owner_user_id,family_id,kind,title,visibility,status,duration_minutes,due_at,completed_at)
     values($1,$2,$3,'Synthetic private title',$4,$5::plan_item_status,$6,now()-interval '1 day',case when $5::plan_item_status='completed' then now() end) returning id`,
    [f.child.id, f.familyId, kind, visibility, status, minutes],
  );
  return row.rows[0].id;
}

async function grant(f, itemId, viewer = f.selected) {
  await pool.query("insert into sharing_grant(resource_type,resource_id,grantee_user_id,granted_by) values('plan_item',$1,$2,$3)", [itemId, viewer.id, f.child.id]);
}

async function canView(viewer, itemId) {
  return (await pool.query('select can_view_plan_item($1,$2) as allowed', [viewer.id, itemId])).rows[0].allowed;
}

async function academic(viewer, student) {
  return (await pool.query('select can_view_student_academic($1,$2) as allowed', [viewer.id, student.id])).rows[0].allowed;
}

async function request(base, path, { method = 'GET', actor, body } = {}) {
  const response = await fetch(base + path, {
    method,
    headers: { 'content-type': 'application/json', ...(actor ? { authorization: `Bearer ${actor.token}` } : {}) },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await response.text();
  return { status: response.status, body: text ? JSON.parse(text) : null };
}

test('privatizing a selected item revokes its grant and does not resurrect it when selected again', async () => {
  const f = await fixture();
  const item = await plan(f, 'selected_members');
  await grant(f, item);
  assert.equal(await canView(f.selected, item), true);
  await pool.query("update plan_item set visibility='private' where id=$1", [item]);
  assert.equal(await canView(f.selected, item), false);
  assert.equal((await pool.query('select 1 from sharing_grant where resource_id=$1', [item])).rowCount, 0);
  await pool.query("update plan_item set visibility='selected_members' where id=$1", [item]);
  assert.equal(await canView(f.selected, item), false);
  assert.equal(await canView(f.child, item), true);
});

for (const side of ['owner', 'viewer']) {
  test(`ending the selected item ${side}'s membership revokes the grant even after rejoining`, async () => {
    const f = await fixture();
    const item = await plan(f, 'selected_members');
    await grant(f, item);
    const member = side === 'owner' ? f.child : f.selected;
    await pool.query('update family_membership set ended_at=now() where family_id=$1 and user_id=$2', [f.familyId, member.id]);
    assert.equal(await canView(f.selected, item), false);
    assert.equal((await pool.query('select 1 from sharing_grant where resource_id=$1', [item])).rowCount, 0);
    await pool.query('update family_membership set ended_at=null where family_id=$1 and user_id=$2', [f.familyId, member.id]);
    assert.equal(await canView(f.selected, item), false);
  });
}

test('family sharing requires both the item owner and viewer to remain active members', async () => {
  const f = await fixture();
  const item = await plan(f, 'family');
  assert.equal(await canView(f.parent, item), true);
  await pool.query('update family_membership set ended_at=now() where family_id=$1 and user_id=$2', [f.familyId, f.child.id]);
  assert.equal(await canView(f.parent, item), false);
  assert.equal(await canView(f.child, item), true);
});

test('a direct selected grant cannot authorize someone outside the current item family', async () => {
  const f = await fixture();
  const item = await plan(f, 'selected_members');
  await grant(f, item, f.outsider);
  assert.equal(await canView(f.outsider, item), false);
});

for (const side of ['guardian', 'minor']) {
  test(`academic authorization ends when the ${side}'s current role changes`, async () => {
    const f = await fixture();
    assert.equal(await academic(f.parent, f.child), true);
    const member = side === 'guardian' ? f.parent : f.child;
    await pool.query("update family_membership set role='adult_member' where family_id=$1 and user_id=$2", [f.familyId, member.id]);
    assert.equal(await academic(f.parent, f.child), false);
    assert.equal(await academic(f.child, f.child), true);
  });
}

test('private plan items remain owner-only for both guardians and outsiders', async () => {
  const f = await fixture();
  const item = await plan(f, 'private');
  assert.equal(await canView(f.child, item), true);
  assert.equal(await canView(f.parent, item), false);
  assert.equal(await canView(f.outsider, item), false);
});

test('sensitive wellbeing and cycle reads and writes are closed by default, including test mode', async () => {
  const f = await fixture();
  const paths = [
    ['GET', '/v1/wellbeing/checkins'],
    ['POST', '/v1/wellbeing/checkins', { mood: 3, energy: 3, stress: 3 }],
    ['GET', `/v1/families/${f.familyId}/children/${f.child.id}/wellbeing-summary`],
    ['POST', `/v1/families/${f.familyId}/children/${f.child.id}/family-guidance`, { question: 'Synthetic support question' }],
    ['GET', '/v1/me/menstrual-cycles'],
    ['POST', '/v1/me/menstrual-cycles', { startsOn: '2026-10-01' }],
    ['DELETE', `/v1/me/menstrual-cycles/${crypto.randomUUID()}`],
    ['POST', '/v1/ai/sessions', { kind: 'wellbeing' }],
  ];
  for (const [method, path, body] of paths) {
    const result = await request(defaultBase, path, { method, actor: f.parent, body });
    assert.equal(result.status, 503, `${method} ${path} must stay gated`);
    assert.equal(result.body.error, 'sensitive_features_disabled');
  }
  assert.equal((await pool.query('select 1 from wellbeing_checkin where owner_user_id=$1', [f.parent.id])).rowCount, 0);
  assert.equal((await pool.query('select 1 from menstrual_cycle_entry where owner_user_id=$1', [f.parent.id])).rowCount, 0);
});

test('every Phase 4/6 read and write requires a verified server session before gate or data access', async () => {
  const f = await fixture();
  const routes = [
    ['GET', '/v1/learning/goals'], ['POST', '/v1/learning/goals'], ['POST', '/v1/learning/checkins'],
    ['GET', '/v1/wellbeing/checkins'], ['POST', '/v1/wellbeing/checkins'],
    ['GET', `/v1/families/${f.familyId}/children/${f.child.id}/wellbeing-summary`],
    ['POST', `/v1/families/${f.familyId}/children/${f.child.id}/family-guidance`],
    ['POST', '/v1/ai/sessions'], ['POST', `/v1/ai/sessions/${crypto.randomUUID()}/messages`],
    ['POST', '/v1/ai/proposals'], ['PATCH', `/v1/ai/proposals/${crypto.randomUUID()}`],
    ['GET', '/v1/me/iran-profile'], ['PATCH', '/v1/me/iran-profile'], ['PUT', '/v1/me/education'],
    ['GET', '/v1/education/catalog'], ['GET', '/v1/calendar/iran'],
    ['GET', '/v1/me/notification-preferences'], ['PATCH', '/v1/me/notification-preferences'],
    ['GET', '/v1/me/menstrual-cycles'], ['POST', '/v1/me/menstrual-cycles'],
    ['DELETE', `/v1/me/menstrual-cycles/${crypto.randomUUID()}`],
  ];
  for (const [method, path] of routes) {
    assert.equal((await request(defaultBase, path, { method, body: method === 'GET' ? undefined : {} })).status, 401, path);
  }
});

test('explicit synthetic opt-in preserves owner-only cycle records', async () => {
  const f = await fixture();
  const written = await request(enabledBase, '/v1/me/menstrual-cycles', { method: 'POST', actor: f.child, body: { startsOn: '2026-10-01', notes: 'Synthetic private cycle' } });
  assert.equal(written.status, 201);
  const item = written.body.id;
  assert.equal((await request(enabledBase, '/v1/me/menstrual-cycles', { actor: f.parent })).body.entries.length, 0);
  assert.equal((await request(enabledBase, `/v1/me/menstrual-cycles/${item}`, { method: 'DELETE', actor: f.parent })).status, 204);
  assert.equal((await pool.query('select 1 from menstrual_cycle_entry where id=$1', [item])).rowCount, 1);
  assert.equal((await request(enabledBase, '/v1/me/menstrual-cycles', { actor: f.child })).body.entries[0].notes, 'Synthetic private cycle');
  assert.equal((await request(enabledBase, `/v1/me/menstrual-cycles/${item}`, { method: 'DELETE', actor: f.child })).status, 204);
});

test('Phase 4 guardian summaries reject a stale guardian role after synthetic opt-in', async () => {
  const f = await fixture();
  const path = `/v1/families/${f.familyId}/children/${f.child.id}/wellbeing-summary`;
  assert.equal((await request(enabledBase, path, { actor: f.parent })).status, 200);
  await pool.query("update family_membership set role='adult_member' where family_id=$1 and user_id=$2", [f.familyId, f.parent.id]);
  assert.equal((await request(enabledBase, path, { actor: f.parent })).status, 403);
});

test('family guidance academic aggregates include only plan items visible to that guardian', async () => {
  const f = await fixture();
  await plan(f, 'private', { kind: 'study_session', status: 'completed', minutes: 90 });
  await plan(f, 'parent_guardian', { kind: 'study_session', status: 'completed', minutes: 15 });
  const result = await request(enabledBase, `/v1/families/${f.familyId}/children/${f.child.id}/family-guidance`, { method: 'POST', actor: f.parent, body: { question: 'Synthetic guidance' } });
  assert.equal(result.status, 200);
  assert.equal(result.body.summary.academic.completed_last_7_days, 1);
  assert.equal(result.body.summary.academic.study_minutes_last_7_days, 15);
});

test('configured AI credentials cannot trigger a provider request in this work package', async () => {
  const f = await fixture();
  let calls = 0;
  const provider = http.createServer((_req, res) => {
    calls += 1;
    res.setHeader('content-type', 'application/json');
    res.end(JSON.stringify({ choices: [{ message: { content: 'Synthetic provider reply' } }] }));
  });
  provider.listen(0, '127.0.0.1');
  await new Promise((resolve) => provider.once('listening', resolve));
  const previous = Object.fromEntries(['AI_API_KEY', 'AI_BASE_URL', 'AI_MODEL'].map((key) => [key, process.env[key]]));
  Object.assign(process.env, { AI_API_KEY: 'synthetic-disabled-key', AI_BASE_URL: `http://127.0.0.1:${provider.address().port}`, AI_MODEL: 'synthetic-disabled-model' });
  try {
    const session = await request(defaultBase, '/v1/ai/sessions', { method: 'POST', actor: f.child, body: { kind: 'study' } });
    assert.equal(session.status, 201);
    const reply = await request(defaultBase, `/v1/ai/sessions/${session.body.id}/messages`, { method: 'POST', actor: f.child, body: { message: 'Synthetic math question' } });
    assert.equal(reply.status, 200);
    assert.equal(calls, 0);
    assert.equal(reply.body.providerMode, 'local_fallback');
    assert.notEqual(reply.body.body, 'Synthetic provider reply');
  } finally {
    for (const [key, value] of Object.entries(previous)) {
      if (value === undefined) delete process.env[key]; else process.env[key] = value;
    }
    await new Promise((resolve) => provider.close(resolve));
  }
});

test('an existing wellbeing guide cannot receive messages while sensitive features are disabled', async () => {
  const f = await fixture();
  const session = await request(enabledBase, '/v1/ai/sessions', { method: 'POST', actor: f.child, body: { kind: 'wellbeing' } });
  assert.equal(session.status, 201);
  const reply = await request(defaultBase, `/v1/ai/sessions/${session.body.id}/messages`, { method: 'POST', actor: f.child, body: { message: 'Synthetic private reflection' } });
  assert.equal(reply.status, 503);
  assert.equal((await pool.query('select 1 from ai_guide_message where session_id=$1', [session.body.id])).rowCount, 0);
});

test('learning checkins cannot reference another owner\'s goal', async () => {
  const f = await fixture();
  const goal = await request(defaultBase, '/v1/learning/goals', { method: 'POST', actor: f.child, body: { title: 'Synthetic goal' } });
  assert.equal(goal.status, 201);
  assert.equal((await request(defaultBase, '/v1/learning/checkins', { method: 'POST', actor: f.outsider, body: { learningGoalId: goal.body.id, confidence: 3, difficulty: 3 } })).status, 403);
});

test('AI proposals cannot reference another owner\'s guide session', async () => {
  const f = await fixture();
  const session = await request(defaultBase, '/v1/ai/sessions', { method: 'POST', actor: f.child, body: { kind: 'study' } });
  assert.equal(session.status, 201);
  assert.equal((await request(defaultBase, '/v1/ai/proposals', { method: 'POST', actor: f.outsider, body: { sessionId: session.body.id, title: 'Synthetic proposal', proposal: { steps: [] } } })).status, 403);
});

test('changing a selected item to another family revokes the previous grants', async () => {
  const f = await fixture();
  const other = await fixture();
  const item = await plan(f, 'selected_members');
  await grant(f, item);
  await pool.query('update plan_item set family_id=$2 where id=$1', [item, other.familyId]);
  assert.equal(await canView(f.selected, item), false);
  assert.equal((await pool.query('select 1 from sharing_grant where resource_id=$1', [item])).rowCount, 0);
});

test('production with no sensitive flag remains closed', async () => {
  const f = await fixture();
  const previous = process.env.NODE_ENV;
  process.env.NODE_ENV = 'production';
  try {
    const base = await serve({});
    const result = await request(base, '/v1/me/menstrual-cycles', { actor: f.child });
    assert.equal(result.status, 503);
    assert.equal(result.body.error, 'sensitive_features_disabled');
  } finally {
    if (previous === undefined) delete process.env.NODE_ENV; else process.env.NODE_ENV = previous;
  }
});

test('deleting and recreating a selected member cannot revive a previous grant', async () => {
  const f = await fixture();
  const item = await plan(f, 'selected_members');
  await grant(f, item);
  await pool.query('delete from family_membership where family_id=$1 and user_id=$2', [f.familyId, f.selected.id]);
  assert.equal(await canView(f.selected, item), false);
  await pool.query("insert into family_membership(family_id,user_id,role) values($1,$2,'adult_member')", [f.familyId, f.selected.id]);
  assert.equal(await canView(f.selected, item), false);
});

test('learning goals cannot reference another student\'s subject', async () => {
  const f = await fixture();
  const context = await pool.query("insert into life_context(user_id,kind,title) values($1,'student','Synthetic class') returning id", [f.child.id]);
  const year = await pool.query("insert into academic_year(student_user_id,life_context_id,title,starts_on,ends_on) values($1,$2,'Synthetic year','2026-09-01','2027-06-01') returning id", [f.child.id, context.rows[0].id]);
  const term = await pool.query("insert into academic_term(academic_year_id,title,starts_on,ends_on) values($1,'Synthetic term','2026-09-01','2026-12-01') returning id", [year.rows[0].id]);
  const subject = await pool.query("insert into subject(student_user_id,academic_term_id,name) values($1,$2,'Synthetic math') returning id", [f.child.id, term.rows[0].id]);
  const result = await request(defaultBase, '/v1/learning/goals', { method: 'POST', actor: f.outsider, body: { title: 'Synthetic foreign goal', subjectId: subject.rows[0].id } });
  assert.equal(result.status, 403);
  assert.equal((await pool.query('select 1 from learning_goal where owner_user_id=$1', [f.outsider.id])).rowCount, 0);
});

test('wellbeing-linked proposals cannot be created or accepted while sensitive features are disabled', async () => {
  const f = await fixture();
  const session = await request(enabledBase, '/v1/ai/sessions', { method: 'POST', actor: f.child, body: { kind: 'wellbeing' } });
  const body = { sessionId: session.body.id, title: 'Synthetic reflection proposal', proposal: { steps: [] } };
  assert.equal((await request(defaultBase, '/v1/ai/proposals', { method: 'POST', actor: f.child, body })).status, 503);
  const proposal = await request(enabledBase, '/v1/ai/proposals', { method: 'POST', actor: f.child, body });
  assert.equal(proposal.status, 201);
  assert.equal((await request(defaultBase, `/v1/ai/proposals/${proposal.body.id}`, { method: 'PATCH', actor: f.child, body: { status: 'accepted' } })).status, 503);
  assert.equal((await pool.query('select status from ai_plan_proposal where id=$1', [proposal.body.id])).rows[0].status, 'proposed');
});

test('study guidance does not create sensitive wellbeing events while the feature is disabled', async () => {
  const f = await fixture();
  const session = await request(defaultBase, '/v1/ai/sessions', { method: 'POST', actor: f.child, body: { kind: 'study' } });
  assert.equal(session.status, 201);
  const reply = await request(defaultBase, `/v1/ai/sessions/${session.body.id}/messages`, { method: 'POST', actor: f.child, body: { message: 'Synthetic safety regression: self-harm' } });
  assert.equal(reply.status, 200);
  assert.match(reply.body.body, /کمک فوری/);
  assert.equal((await pool.query('select 1 from wellbeing_safety_event where owner_user_id=$1', [f.child.id])).rowCount, 0);
});
