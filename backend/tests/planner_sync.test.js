import test, { after } from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import express from 'express';
import jwt from 'jsonwebtoken';
import pg from 'pg';
import { createSessionAuth } from '../src/session_auth.js';
import { createPhase3Router } from '../src/phase3.js';

if (!process.env.DATABASE_URL) throw new Error('planner sync tests require synthetic PostgreSQL');
const pool = new pg.Pool({ connectionString: process.env.DATABASE_URL });
const secret = 'synthetic-planner-sync-secret-32-characters';
const app = express();
app.use(express.json({ limit: '64kb' }));
app.use('/v1', createPhase3Router({ pool, auth: createSessionAuth({ pool, jwtSecret: secret }) }));
app.use((error, _req, res, _next) => { console.error(error); res.status(500).json({ error: 'internal_error' }); });
let server = app.listen(0);
let base = `http://127.0.0.1:${server.address().port}`;
after(async () => { await new Promise((resolve) => server.close(resolve)); await pool.end(); });
const uuid = () => crypto.randomUUID();
async function user() {
  const id = uuid(), sid = uuid();
  await pool.query('insert into app_user(id,identity_subject,email_normalized,email_verified_at) values($1,$2,$3,now())', [id, `planner-test:${id}`, `${id}@example.test`]);
  await pool.query("insert into profile(user_id,display_name,theme_preference) values($1,'Synthetic Planner','adult_blue')", [id]);
  await pool.query("insert into auth_session(id,user_id,refresh_digest,expires_at) values($1,$2,$3,now()+interval '1 day')", [sid, id, uuid()]);
  return { id, token: jwt.sign({ sub: id, sid, aud: 'lifemate-api' }, secret, { issuer: 'lifemate', expiresIn: '15m' }) };
}
async function fixture() {
  const child = await user(), parent = await user(), outsider = await user(), familyId = uuid();
  await pool.query("insert into family_workspace(id,name,created_by) values($1,'Synthetic Planner Family',$2)", [familyId, parent.id]);
  await pool.query("insert into family_membership(family_id,user_id,role) values($1,$2,'teen_minor'),($1,$3,'parent_guardian')", [familyId, child.id, parent.id]);
  await pool.query('insert into guardian_relationship(family_id,guardian_user_id,minor_user_id) values($1,$2,$3)', [familyId, parent.id, child.id]);
  return { child, parent, outsider, familyId };
}
async function request(path, actor, { method = 'GET', body } = {}) {
  const response = await fetch(base + path, { method, headers: { 'content-type': 'application/json', ...(actor ? { authorization: `Bearer ${actor.token}` } : {}) }, body: body === undefined ? undefined : JSON.stringify(body) });
  const text = await response.text();
  return { status: response.status, body: response.headers.get('content-type')?.includes('application/json') ? JSON.parse(text) : text };
}
async function sync(actor, mutations) { return request('/v1/sync/mutations', actor, { method: 'POST', body: { mutations } }); }
const create = (f, payload = {}) => ({ id: uuid(), entityType: 'plan_item', entityId: uuid(), operation: 'create', expectedVersion: 0,
  payload: { kind: 'assignment', title: 'تکلیف ریاضی آزمایشی', familyId: f.familyId, visibility: 'parent_guardian', dueAt: new Date(Date.now() + 3600000).toISOString(), plannedDurationSeconds: 1500, ...payload } });

test('offline stable create/retry/update/complete/archive have canonical acknowledgements and PostgreSQL survives HTTP restart', async () => {
  const f = await fixture();
  const mutation = create(f);
  const created = await sync(f.child, [mutation]);
  assert.equal(created.status, 200);
  const a = created.body.results[0];
  assert.equal(a.status, 'accepted');
  assert.equal(a.item.id, mutation.entityId);
  assert.equal(Number(a.item.version), 1);
  assert.equal(a.item.planned_duration_seconds, 1500);
  assert.ok(Number.isFinite(Date.parse(a.acceptedAt)));
  const duplicate = await sync(f.child, [mutation]);
  assert.equal(duplicate.body.results[0].status, 'already_applied');
  assert.deepEqual(duplicate.body.results[0].item, a.item);
  assert.equal((await pool.query('select count(*)::int n from plan_item where id=$1', [mutation.entityId])).rows[0].n, 1);
  const update = { id: uuid(), entityType: 'plan_item', entityId: mutation.entityId, operation: 'update', expectedVersion: 1, payload: { title: 'ویرایش تکلیف', plannedDurationSeconds: 600 } };
  const updated = await sync(f.child, [update]);
  assert.equal(updated.body.results[0].status, 'accepted');
  assert.equal(Number(updated.body.results[0].item.version), 2);
  const complete = await sync(f.child, [{ ...update, id: uuid(), operation: 'complete', expectedVersion: 2, payload: {} }]);
  assert.equal(complete.body.results[0].item.status, 'completed');
  assert.equal(Number(complete.body.results[0].item.version), 3);
  const event = (await pool.query('select state,source from activity_state_event where plan_item_id=$1 order by version desc limit 1', [mutation.entityId])).rows[0];
  assert.deepEqual(event, { state: 'completed', source: 'self_reported' });
  await new Promise((resolve) => server.close(resolve)); server = app.listen(0); base = `http://127.0.0.1:${server.address().port}`;
  const read = await request(`/v1/plan-items/${mutation.entityId}`, f.child);
  assert.equal(read.status, 200);
  assert.equal(read.body.title, 'ویرایش تکلیف');
  const archive = await sync(f.child, [{ ...update, id: uuid(), operation: 'archive', expectedVersion: 3, payload: {} }]);
  assert.equal(archive.body.results[0].item.status, 'cancelled');
  assert.equal((await pool.query('select status from plan_item where id=$1', [mutation.entityId])).rows[0].status, 'cancelled');
});

test('server versions defeat future client clocks; concurrent updates and changed mutation reuse are explicit conflicts', async () => {
  const f = await fixture(), mutation = create(f);
  assert.equal((await sync(f.child, [mutation])).body.results[0].status, 'accepted');
  const reused = await sync(f.child, [{ ...mutation, payload: { ...mutation.payload, title: 'Changed duplicate' } }]);
  assert.equal(reused.body.results[0].status, 'conflict');
  assert.equal(reused.body.results[0].error, 'mutation_id_reused');
  assert.equal(reused.body.results[0].httpStatus, 409);
  const stale = { id: uuid(), entityType: 'plan_item', entityId: mutation.entityId, operation: 'update', expectedVersion: 0, clientUpdatedAt: '2999-01-01T00:00:00Z', payload: { title: 'Wrong stale update' } };
  assert.equal((await sync(f.child, [stale])).body.results[0].error, 'version_conflict');
  const [a, b] = await Promise.all([sync(f.child, [{ ...stale, id: uuid(), expectedVersion: 1 }]), sync(f.child, [{ ...stale, id: uuid(), expectedVersion: 1, payload: { title: 'Other writer' } }])]);
  assert.deepEqual([a.body.results[0].status, b.body.results[0].status].sort(), ['accepted', 'conflict']);
  assert.equal((await pool.query('select version from plan_item where id=$1', [mutation.entityId])).rows[0].version, '2');
});

test('direct planner writes require expectedVersion, reject malformed data and return compatible version-one creates', async () => {
  const f = await fixture();
  const created = await request('/v1/plan-items', f.child, { method: 'POST', body: create(f).payload });
  assert.equal(created.status, 201); assert.equal(Number(created.body.version), 1);
  assert.equal((await request(`/v1/plan-items/${created.body.id}`, f.child, { method: 'PATCH', body: { title: 'No version' } })).status, 400);
  assert.equal((await request(`/v1/plan-items/${created.body.id}`, f.child, { method: 'PATCH', body: { expectedVersion: 0, title: 'Stale' } })).status, 409);
  assert.equal((await request(`/v1/plan-items/${created.body.id}`, f.child, { method: 'PATCH', body: { expectedVersion: 1, plannedDurationSeconds: 86401 } })).status, 400);
  assert.equal((await request(`/v1/plan-items/${created.body.id}`, f.child, { method: 'PATCH', body: { expectedVersion: 1, dueAt: 'not-a-date' } })).status, 400);
  const updated = await request(`/v1/plan-items/${created.body.id}`, f.child, { method: 'PATCH', body: { expectedVersion: 1, plannedDurationSeconds: 0 } });
  assert.equal(updated.status, 200); assert.equal(updated.body.planned_duration_seconds, 0);
  assert.equal((await request(`/v1/plan-items/${created.body.id}`, f.parent, { method: 'PATCH', body: { expectedVersion: 2, title: 'Parent overwrite' } })).status, 403);
});

test('duplicate sync mutation rechecks ownership and current family membership; archived families close all helpers and reads', async () => {
  const f = await fixture(), mutation = create(f);
  assert.equal((await sync(f.child, [mutation])).body.results[0].status, 'accepted');
  const forged = await sync(f.outsider, [{ ...mutation, id: uuid(), operation: 'update', expectedVersion: 1, payload: { title: 'Forbidden' } }]);
  assert.equal(forged.body.results[0].status, 'rejected');
  await pool.query('update family_membership set ended_at=now() where family_id=$1 and user_id=$2', [f.familyId, f.child.id]);
  assert.equal((await sync(f.child, [mutation])).body.results[0].status, 'rejected');
  await pool.query('update family_membership set ended_at=null where family_id=$1 and user_id=$2', [f.familyId, f.child.id]);
  await pool.query('update family_workspace set archived_at=now() where id=$1', [f.familyId]);
  assert.equal((await request(`/v1/families/${f.familyId}/calendar`, f.parent)).status, 403);
  assert.equal((await request(`/v1/school/${f.child.id}/overview`, f.parent)).status, 403);
  assert.deepEqual((await pool.query('select is_active_family_member($1,$2) member,is_active_guardian($1,$3,$2) guardian', [f.familyId, f.child.id, f.parent.id])).rows[0], { member: false, guardian: false });
});

test('every parent planner read strips owner notes and every school/support aggregate excludes private plans', async () => {
  const f = await fixture();
  const publicPlan = await request('/v1/plan-items', f.child, { method: 'POST', body: create(f, { notes: 'PRIVATE-NOTES-SECRET' }).payload });
  const privatePlan = await request('/v1/plan-items', f.child, { method: 'POST', body: create(f, { visibility: 'private', title: 'PRIVATE-TITLE-SECRET', notes: 'PRIVATE-NOTES-SECRET' }).payload });
  await pool.query('update plan_item set grade_points=18,grade_out_of=20 where id=$1', [publicPlan.body.id]);
  await pool.query("update plan_item set status='completed',completed_at=now(),grade_points=100,grade_out_of=100 where id=$1", [privatePlan.body.id]);
  for (const path of ['/v1/today', '/v1/plan-items', `/v1/plan-items/${publicPlan.body.id}`, `/v1/families/${f.familyId}/calendar`, `/v1/school/${f.child.id}/overview`, `/v1/families/${f.familyId}/children/${f.child.id}/support-summary`]) {
    const result = await request(path, f.parent);
    assert.equal(result.status, 200, path);
    assert.ok(!JSON.stringify(result.body).includes('PRIVATE-NOTES-SECRET'), path);
    assert.ok(!JSON.stringify(result.body).includes('PRIVATE-TITLE-SECRET'), path);
  }
  const owner = await request(`/v1/plan-items/${publicPlan.body.id}`, f.child);
  assert.equal(owner.body.notes, 'PRIVATE-NOTES-SECRET');
  const support = await request(`/v1/families/${f.familyId}/children/${f.child.id}/support-summary`, f.parent);
  assert.equal(support.body.metrics.gradePercent, 90);
  assert.equal(support.body.metrics.completedLast7Days, 0);
  const overview = await request(`/v1/school/${f.child.id}/overview`, f.parent);
  assert.equal(overview.body.grades.length, 1);
});

test('mutation IDs are scoped to accounts and a malformed/unauthorized mutation never aborts accepted siblings', async () => {
  const a = await fixture(), b = await fixture(), first = create(a), second = { ...create(b), id: first.id };
  assert.equal((await sync(a.child, [first])).body.results[0].status, 'accepted');
  assert.equal((await sync(b.child, [second])).body.results[0].status, 'accepted');
  const bad = { ...create(a), entityId: 'not-a-uuid' }, valid = create(a);
  const batch = await sync(a.child, [bad, valid]);
  assert.equal(batch.status, 200);
  assert.deepEqual(batch.body.results.map((x) => x.status), ['rejected', 'accepted']);
  assert.equal((await pool.query('select count(*)::int n from sync_mutation where id=$1', [first.id])).rows[0].n, 2);
});

test('reschedule, selected-member grants and private-note edits share validation without publishing notes', async () => {
  const f = await fixture(), mutation = create(f, { visibility: 'selected_members', selectedMemberIds: [f.parent.id], notes: 'OWN-NOTE-SECRET' });
  const created = await sync(f.child, [mutation]);
  assert.equal(created.body.results[0].status, 'accepted');
  assert.equal((await request(`/v1/plan-items/${mutation.entityId}`, f.parent)).status, 200);
  const reschedule = { id: uuid(), entityType: 'plan_item', entityId: mutation.entityId, operation: 'reschedule', expectedVersion: 1, payload: { dueAt: new Date(Date.now() + 7200000).toISOString() } };
  assert.equal((await sync(f.child, [reschedule])).body.results[0].status, 'accepted');
  const madePrivate = await sync(f.child, [{ ...reschedule, id: uuid(), operation: 'update', expectedVersion: 2, payload: { visibility: 'private', notes: 'EDITED-OWN-NOTE-SECRET' } }]);
  assert.equal(madePrivate.body.results[0].status, 'accepted');
  assert.equal((await request(`/v1/plan-items/${mutation.entityId}`, f.parent)).status, 404);
  const owner = await request(`/v1/plan-items/${mutation.entityId}`, f.child);
  assert.equal(owner.body.notes, 'EDITED-OWN-NOTE-SECRET');
  assert.equal((await pool.query("select count(*)::int n from sharing_grant where resource_type='plan_item' and resource_id=$1", [mutation.entityId])).rows[0].n, 0);
});

test('grade updates require the latest owner version and support time counts only visible recorded intervals', async () => {
  const f = await fixture(), a = create(f), b = create(f, { visibility: 'private' });
  const created = await sync(f.child, [a, b]);
  assert.ok(created.body.results.every((x) => x.status === 'accepted'));
  const path = `/v1/school/plan-items/${a.entityId}/grade`;
  assert.equal((await request(path, f.child, { method: 'PATCH', body: { points: 18, outOf: 20 } })).status, 400);
  const grade = await request(path, f.child, { method: 'PATCH', body: { points: 18, outOf: 20, expectedVersion: 1 } });
  assert.equal(grade.status, 200);
  assert.equal(Number(grade.body.version), 2);
  assert.equal((await request(path, f.child, { method: 'PATCH', body: { points: 19, outOf: 20, expectedVersion: 1 } })).status, 409);
  const t = Date.now() - 3600000;
  for (const [planId, offset, seconds] of [[a.entityId, 0, 300], [b.entityId, 600000, 600]]) {
    const sessionId = uuid(), start = new Date(t + offset), end = new Date(t + offset + seconds * 1000);
    await pool.query("insert into study_session(id,child_user_id,plan_item_id,source,status,started_at,ended_at,last_event_at,recorded_duration_seconds) values($1,$2,$3,'self_reported','completed',$4,$5,$5,$6)", [sessionId, f.child.id, planId, start, end, seconds]);
    await pool.query('insert into study_interval(session_id,starts_at,ends_at) values($1,$2,$3)', [sessionId, start, end]);
  }
  const report = await request(`/v1/families/${f.familyId}/children/${f.child.id}/support-summary`, f.parent);
  assert.equal(report.status, 200);
  assert.equal(report.body.metrics.recordedStudySecondsLast7Days, 300);
  assert.equal(report.body.metrics.studyMinutesLast7Days, 5);
  assert.equal(report.body.metrics.recordedTimeIsProofOfStudy, false);
});
