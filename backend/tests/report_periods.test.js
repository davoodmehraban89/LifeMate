import test, { after } from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import express from 'express';
import jwt from 'jsonwebtoken';
import pg from 'pg';
import { createSessionAuth } from '../src/session_auth.js';
import { createPhase3Router } from '../src/phase3.js';
import { createStudySessionsRouter } from '../src/study_sessions.js';

assert.ok(process.env.DATABASE_URL, 'Report-period tests require synthetic PostgreSQL');
const database = new URL(process.env.DATABASE_URL);
assert.ok(['localhost', '127.0.0.1', '::1'].includes(database.hostname), 'Report tests refuse a nonlocal database');
assert.match(database.pathname, /^\/(?:lifeguide_[a-z_]*test[a-z_]*|lifemate_ci|lifeguide_roles_source_[a-f0-9]{16})$/);
const pool = new pg.Pool({ connectionString: process.env.DATABASE_URL });
const secret = 'synthetic-report-period-secret-32-characters';
const auth = createSessionAuth({ pool, jwtSecret: secret });
const app = express();
app.use(express.json());
app.use('/v1', createPhase3Router({ pool, auth }));
app.use('/v1', createStudySessionsRouter({ pool, auth }));
app.use((error, _req, res, _next) => { console.error(error); res.status(500).json({ error: 'internal_error' }); });
const server = app.listen(0, '127.0.0.1');
await new Promise((resolve) => server.on('listening', resolve));
const base = `http://127.0.0.1:${server.address().port}`;
const users = [], families = [];
after(async () => {
  await new Promise((resolve) => server.close(resolve));
  try {
    await pool.query('delete from access_audit where family_id=any($1::uuid[]) or actor_user_id=any($2::uuid[])', [families, users]);
    await pool.query('delete from family_workspace where id=any($1::uuid[])', [families]);
    await pool.query('delete from app_user where id=any($1::uuid[])', [users]);
  } finally { await pool.end(); }
});
const iso = (ms) => new Date(ms).toISOString();
const day = 86400000;
function range() {
  const local = new Date(Date.now() + 210 * 60000);
  const to = Date.UTC(local.getUTCFullYear(), local.getUTCMonth(), local.getUTCDate()) - 210 * 60000;
  return { from: to - 7 * day, to };
}
async function user() {
  const id = crypto.randomUUID(), sid = crypto.randomUUID(); users.push(id);
  await pool.query('insert into app_user(id,identity_subject,email_normalized,email_verified_at) values($1,$2,$3,now())', [id, `report-period:${id}`, `report-period-${id}@example.test`]);
  await pool.query("insert into profile(user_id,display_name,theme_preference) values($1,'Synthetic report account','adult_blue')", [id]);
  await pool.query("insert into auth_session(id,user_id,refresh_digest,expires_at) values($1,$2,$3,now()+interval '1 day')", [sid, id, crypto.randomUUID()]);
  return { id, sid, token: jwt.sign({ sub: id, sid, aud: 'lifemate-api' }, secret, { issuer: 'lifemate', expiresIn: '15m' }) };
}
async function fixture() {
  const child = await user(), mother = await user(), father = await user(), outsider = await user();
  const familyId = crypto.randomUUID(); families.push(familyId);
  await pool.query("insert into family_workspace(id,name,created_by) values($1,'Synthetic report family',$2)", [familyId, mother.id]);
  for (const [actor, role] of [[child, 'teen_minor'], [mother, 'parent_guardian'], [father, 'parent_guardian']]) {
    await pool.query('insert into family_membership(family_id,user_id,role,is_admin) values($1,$2,$3,$4)', [familyId, actor.id, role, actor === mother]);
  }
  for (const actor of [mother, father]) await pool.query('insert into guardian_relationship(family_id,guardian_user_id,minor_user_id) values($1,$2,$3)', [familyId, actor.id, child.id]);
  return { child, mother, father, outsider, familyId };
}
async function request(path, actor, method = 'GET', body) {
  const response = await fetch(base + path, { method, headers: { 'content-type': 'application/json', ...(actor ? { authorization: `Bearer ${actor.token}` } : {}) }, body: body === undefined ? undefined : JSON.stringify(body) });
  return { status: response.status, body: await response.json() };
}
async function task(f, fields = {}) {
  const { status, ...createFields } = fields;
  const response = await request('/v1/plan-items', f.child, 'POST', { kind: 'assignment', title: 'Synthetic period assignment', familyId: f.familyId, visibility: 'parent_guardian', plannedDurationSeconds: 600, notes: 'PRIVATE-REPORT-DETAIL', ...createFields });
  assert.equal(response.status, 201, JSON.stringify(response.body));
  if (status === 'completed') {
    const completed = await request(`/v1/plan-items/${response.body.id}/activity-state`, f.child, 'POST', { mutationId: crypto.randomUUID(), expectedVersion: 0, state: 'completed', source: 'self_reported', occurredAt: iso(Date.now() - 1000) });
    assert.equal(completed.status, 200, JSON.stringify(completed.body));
  }
  return response.body;
}
async function report(f, actor = f.mother, window = range()) {
  return request(`/v1/families/${f.familyId}/children/${f.child.id}/learning-report?from=${encodeURIComponent(iso(window.from))}&to=${encodeURIComponent(iso(window.to))}`, actor);
}
async function subject(f, name = 'Same-named subject') {
  const context = await request('/v1/life-contexts', f.child, 'POST', { kind: 'student', title: 'Synthetic report school' });
  assert.equal(context.status, 201);
  const year = await request('/v1/school/years', f.child, 'POST', { lifeContextId: context.body.id, title: 'Synthetic year', startsOn: '2026-01-01', endsOn: '2026-12-31' });
  assert.equal(year.status, 201);
  const term = await request(`/v1/school/years/${year.body.id}/terms`, f.child, 'POST', { title: 'Synthetic term', startsOn: '2026-01-01', endsOn: '2026-12-31' });
  assert.equal(term.status, 201);
  const result = await request(`/v1/school/terms/${term.body.id}/subjects`, f.child, 'POST', { name });
  assert.equal(result.status, 201); return result.body.id;
}
async function recorded(f, taskId, start, end) {
  const result = await request('/v1/study/sessions', f.child, 'POST', { id: crypto.randomUUID(), mutationId: crypto.randomUUID(), planItemId: taskId, source: 'self_reported', startedAt: iso(start), endedAt: iso(end) });
  assert.equal(result.status, 201, JSON.stringify(result.body));
  return result.body.session;
}

test('period task cohort uses inclusive due/start boundaries, excludes undated and keeps explicit historical totals', async () => {
  const f = await fixture(), window = range();
  const atStart = await task(f, { dueAt: iso(window.from), status: 'completed', plannedDurationSeconds: 120 });
  const startOnly = await task(f, { startsAt: iso(window.from + day), plannedDurationSeconds: 180 });
  const old = await task(f, { dueAt: iso(window.from - 1), status: 'completed', plannedDurationSeconds: 900 });
  const atEnd = await task(f, { dueAt: iso(window.to), plannedDurationSeconds: 300 });
  const differentDates = await task(f, { startsAt: iso(window.from + day), dueAt: iso(window.to + day), plannedDurationSeconds: 360 });
  const undated = await task(f, { plannedDurationSeconds: 420 });
  const result = await report(f, f.mother, window);
  assert.equal(result.status, 200);
  assert.deepEqual(result.body.periodMetrics, {
    totalTasks: 2, completedTasks: 1, completionPercent: 50, overdueTasks: 0,
    plannedDurationSeconds: 300, recordedDurationSeconds: 0,
    examCount: 0, gradedExamCount: 0, gradePercent: null,
  });
  assert.equal(result.body.allTimeTaskMetrics.totalTasks, 6);
  assert.equal(result.body.allTimeTaskMetrics.completedTasks, 2);
  assert.equal(result.body.metrics.totalTasks, 6, 'legacy field remains historical');
  assert.equal(result.body.metrics.plannedInRangeDurationSeconds, 300);
  assert.equal(result.body.taskDatePolicy, 'due_at_then_starts_at');
  assert.equal(result.body.rangeConvention, 'inclusive_from_exclusive_to');
  assert.equal(result.body.completionBasis, 'current_status_of_period_tasks');
  assert.equal(result.body.timezone, 'Asia/Tehran');
  assert.ok(Number.isFinite(Date.parse(result.body.asOf)));
  const included = result.body.items.filter((row) => row.taskInRange).map((row) => row.id).sort();
  assert.deepEqual(included, [atStart.id, startOnly.id].sort());
  assert.ok([old, atEnd, differentDates, undated].every((row) => !result.body.items.find((item) => item.id === row.id).taskInRange));
  assert.equal(JSON.stringify(result.body).includes('PRIVATE-REPORT-DETAIL'), false);
});

test('period time clips Tehran midnight even for older tasks and subject/exam aggregates only include authorized items once', async () => {
  const f = await fixture(), window = range();
  const firstSubject = await subject(f), secondSubject = await subject(f);
  const firstExam = await task(f, { kind: 'exam', title: 'Allowed exam one', subjectId: firstSubject, dueAt: iso(window.from + day), gradePoints: 15, gradeOutOf: 20 });
  const secondExam = await task(f, { kind: 'exam', title: 'Allowed exam two', subjectId: secondSubject, dueAt: iso(window.from + 2 * day), gradePoints: 30, gradeOutOf: 40 });
  const older = await task(f, { subjectId: firstSubject, dueAt: iso(window.from - day) });
  const privateExam = await task(f, { kind: 'exam', title: 'PRIVATE-EXAM-NOT-SHARED', subjectId: firstSubject, dueAt: iso(window.from + day), gradePoints: 0, gradeOutOf: 100, visibility: 'private' });
  const selected = await task(f, { kind: 'exam', title: 'Mother-only exam', subjectId: firstSubject, dueAt: iso(window.from + 2 * day), gradePoints: 10, gradeOutOf: 10, visibility: 'selected_members', selectedMemberIds: [f.mother.id] });
  await recorded(f, older.id, window.from - 5 * 60000, window.from + 10 * 60000);
  await recorded(f, firstExam.id, window.from + 2 * day - 5 * 60000, window.from + 2 * day + 5 * 60000);
  await recorded(f, secondExam.id, window.to - 5 * 60000, window.to + 5 * 60000);
  await recorded(f, privateExam.id, window.from + 3 * day, window.from + 3 * day + 20 * 60000);
  const mother = await report(f, f.mother, window);
  assert.equal(mother.status, 200);
  assert.equal(mother.body.periodMetrics.totalTasks, 3);
  assert.equal(mother.body.periodMetrics.recordedDurationSeconds, 1500);
  assert.equal(mother.body.periodMetrics.examCount, 3);
  assert.equal(mother.body.periodMetrics.gradedExamCount, 3);
  assert.equal(mother.body.periodMetrics.gradePercent, 78.57);
  assert.deepEqual(mother.body.periodExams.map((row) => row.id).sort(), [firstExam.id, secondExam.id, selected.id].sort());
  assert.equal(mother.body.periodSubjects.length, 2, 'same labels do not merge distinct subjects');
  const first = mother.body.periodSubjects.find((row) => row.subjectId === firstSubject);
  const second = mother.body.periodSubjects.find((row) => row.subjectId === secondSubject);
  assert.equal(first.totalTasks, 2); assert.equal(first.recordedDurationSeconds, 1200); assert.equal(first.gradePercent, 83.33);
  assert.equal(second.totalTasks, 1); assert.equal(second.recordedDurationSeconds, 300); assert.equal(second.gradePercent, 75);
  assert.equal(mother.body.daily.reduce((sum, row) => sum + row.recordedDurationSeconds, 0), 1500);
  assert.equal(mother.body.isEvidenceOfStudy, false);
  assert.equal(mother.body.recordingDisclaimerKey, 'recorded_time_is_not_proof_of_study');
  const father = await report(f, f.father, window);
  assert.equal(father.body.periodMetrics.totalTasks, 2); assert.equal(father.body.periodMetrics.gradePercent, 75);
  assert.equal(father.body.periodExams.length, 2);
  assert.equal(JSON.stringify(mother.body).includes('PRIVATE-EXAM-NOT-SHARED'), false);
  assert.equal(JSON.stringify(mother.body).includes('PRIVATE-REPORT-DETAIL'), false);
  assert.equal(JSON.stringify(father.body).includes('Mother-only exam'), false);
  assert.equal((await report(f, f.outsider, window)).status, 403);
});

test('period fields recheck current membership, guardian relationship, family state and sharing on every read', async () => {
  const f = await fixture(), window = range();
  const otherFamily = await fixture();
  assert.equal((await report(f, otherFamily.mother, window)).status, 403, 'a guardian of another family cannot read this child');
  const shared = await task(f, { dueAt: iso(window.from + day) });
  assert.equal((await report(f, f.mother, window)).body.periodMetrics.totalTasks, 1);
  await pool.query("update plan_item set visibility='private' where id=$1", [shared.id]);
  const hidden = await report(f, f.mother, window);
  assert.equal(hidden.body.periodMetrics.totalTasks, 0);
  assert.deepEqual(hidden.body.periodExams, []); assert.deepEqual(hidden.body.periodSubjects, []);
  await pool.query("update plan_item set visibility='parent_guardian' where id=$1", [shared.id]);
  await pool.query('update guardian_relationship set active=false where family_id=$1 and guardian_user_id=$2', [f.familyId, f.mother.id]);
  assert.equal((await report(f, f.mother, window)).status, 403);
  await pool.query('update guardian_relationship set active=true where family_id=$1 and guardian_user_id=$2', [f.familyId, f.mother.id]);
  await pool.query('update family_membership set ended_at=now() where family_id=$1 and user_id=$2', [f.familyId, f.child.id]);
  assert.equal((await report(f, f.mother, window)).status, 403);
  await pool.query('update family_membership set ended_at=null where family_id=$1 and user_id=$2', [f.familyId, f.child.id]);
  await pool.query('update family_workspace set archived_at=now() where id=$1', [f.familyId]);
  assert.equal((await report(f, f.mother, window)).status, 403);
});

test('report version reflects the period and authorized subject label rather than only task timestamps', async () => {
  const f = await fixture(), window = range();
  const subjectId = await subject(f, 'Original report label');
  await task(f, { subjectId, dueAt: iso(window.from + day) });
  const original = await report(f, f.mother, window);
  const changedRange = await report(f, f.mother, { ...window, from: window.from + 2 * day });
  assert.notEqual(original.body.sourceVersion, changedRange.body.sourceVersion);
  await pool.query('update subject set name=$2 where id=$1', [subjectId, 'Renamed report label']);
  const renamed = await report(f, f.mother, window);
  assert.equal(renamed.body.periodSubjects[0].subjectName, 'Renamed report label');
  assert.notEqual(original.body.sourceVersion, renamed.body.sourceVersion);
});

test('period reports reject expired credentials, database sessions and disabled accounts before returning data', async () => {
  const f = await fixture(), window = range();
  await task(f, { title: 'SESSION-PRIVATE-REPORT-TITLE', dueAt: iso(window.from + day) });
  const expired = { ...f.mother, token: jwt.sign({ sub: f.mother.id, sid: f.mother.sid, aud: 'lifemate-api' }, secret, { issuer: 'lifemate', expiresIn: -1 }) };
  for (const actor of [null, expired]) {
    const result = await report(f, actor, window);
    assert.equal(result.status, 401); assert.deepEqual(Object.keys(result.body), ['error']);
  }
  await pool.query("update auth_session set expires_at=now()-interval '1 second' where id=$1", [f.mother.sid]);
  assert.equal((await report(f, f.mother, window)).status, 401);
  await pool.query("update auth_session set expires_at=now()+interval '1 day',revoked_at=now() where id=$1", [f.mother.sid]);
  assert.equal((await report(f, f.mother, window)).status, 401);
  await pool.query('update auth_session set revoked_at=null where id=$1', [f.mother.sid]);
  await pool.query('update app_user set disabled_at=now() where id=$1', [f.mother.id]);
  const disabled = await report(f, f.mother, window);
  assert.equal(disabled.status, 401); assert.deepEqual(Object.keys(disabled.body), ['error']);
  assert.equal(JSON.stringify(disabled.body).includes('SESSION-PRIVATE-REPORT-TITLE'), false);
});

test('report requests validate UTC ranges, duration bounds, defaults and repeated parameters', async () => {
  const f = await fixture(), window = range();
  const path = `/v1/families/${f.familyId}/children/${f.child.id}/learning-report`;
  const query = (from, to) => `${path}?from=${encodeURIComponent(from)}&to=${encodeURIComponent(to)}`;
  for (const [from, to] of [
    ['broken', iso(window.to)], [iso(window.from), 'broken'],
    [iso(window.from), iso(window.from)], [iso(window.to), iso(window.from)],
    [iso(window.to - 367 * day), iso(window.to)],
    ['2026-02-30T00:00:00Z', '2026-03-01T00:00:00Z'],
    ['2026-01-01T00:00:00+03:30', '2026-01-02T00:00:00Z'],
  ]) {
    const invalid = await request(query(from, to), f.mother);
    assert.equal(invalid.status, 400, `${from} → ${to}`);
    assert.deepEqual(invalid.body, { error: 'invalid_report_range' });
  }
  const duplicate = await request(`${query(iso(window.from), iso(window.to))}&from=${encodeURIComponent(iso(window.from))}`, f.mother);
  assert.equal(duplicate.status, 400);
  const maximum = await request(query(iso(window.to - 366 * day), iso(window.to)), f.mother);
  assert.equal(maximum.status, 200); assert.equal(Date.parse(maximum.body.to) - Date.parse(maximum.body.from), 366 * day);
  const onlyTo = await request(`${path}?to=${encodeURIComponent(iso(window.to))}`, f.mother);
  assert.equal(onlyTo.status, 200); assert.equal(Date.parse(onlyTo.body.to) - Date.parse(onlyTo.body.from), 30 * day);
  const before = Date.now(), defaults = await request(path, f.mother), after = Date.now();
  assert.equal(defaults.status, 200);
  assert.equal(Date.parse(defaults.body.to) - Date.parse(defaults.body.from), 30 * day);
  assert.ok(Date.parse(defaults.body.to) >= before && Date.parse(defaults.body.to) <= after);
});

test('report fingerprints change only for current visible source data and preserve no private mutation signal', async () => {
  const f = await fixture(), window = range();
  const shared = await task(f, { title: 'Visible source', dueAt: iso(window.from + day) });
  const hidden = await task(f, { title: 'PRIVATE-HIDDEN-SOURCE', visibility: 'private', dueAt: iso(window.from + day) });
  const original = await report(f, f.mother, window), repeated = await report(f, f.mother, window);
  assert.match(original.body.sourceVersion, /^[a-f0-9]{64}$/);
  assert.equal(repeated.body.sourceVersion, original.body.sourceVersion);
  await pool.query('update plan_item set title=$2,version=version+1,updated_at=now() where id=$1', [hidden.id, 'PRIVATE-HIDDEN-CHANGED']);
  const hiddenChanged = await report(f, f.mother, window);
  assert.equal(hiddenChanged.body.sourceVersion, original.body.sourceVersion);
  assert.equal(hiddenChanged.body.lastSyncAt, original.body.lastSyncAt);
  assert.equal(JSON.stringify(hiddenChanged.body).includes('PRIVATE-HIDDEN-CHANGED'), false);
  await pool.query('update plan_item set title=$2,version=version+1,updated_at=now() where id=$1', [shared.id, 'Visible source changed']);
  const visibleChanged = await report(f, f.mother, window);
  assert.notEqual(visibleChanged.body.sourceVersion, original.body.sourceVersion);
  await pool.query("update plan_item set visibility='private' where id=$1", [shared.id]);
  const revoked = await report(f, f.mother, window);
  assert.equal(revoked.body.periodMetrics.totalTasks, 0); assert.deepEqual(revoked.body.items, []);
  assert.notEqual(revoked.body.sourceVersion, visibleChanged.body.sourceVersion);
  assert.equal(revoked.body.lastSyncAt, null);
  await pool.query("update family_membership set role='adult_member' where family_id=$1 and user_id=$2", [f.familyId, f.mother.id]);
  assert.equal((await report(f, f.mother, window)).status, 403, 'family administration is not guardian authority');
});

test('report fingerprint is stable when only fixture interval physical row order changes', async () => {
  const f = await fixture(), window = range();
  const shared = await task(f, { dueAt: iso(window.from + day) });
  const first = await recorded(f, shared.id, window.from + day, window.from + day + 5 * 60000);
  await recorded(f, shared.id, window.from + 2 * day, window.from + 2 * day + 7 * 60000);
  const original = await report(f, f.mother, window);
  // A no-op SQL update changes the physical heap position without changing
  // any logical report input. Only this randomized fixture's row is touched.
  await pool.query('update study_interval set starts_at=starts_at where session_id=$1', [first.id]);
  const reordered = await report(f, f.mother, window);
  assert.deepEqual(reordered.body.items, original.body.items);
  assert.deepEqual(reordered.body.periodMetrics, original.body.periodMetrics);
  assert.deepEqual(reordered.body.daily, original.body.daily);
  assert.equal(reordered.body.sourceVersion, original.body.sourceVersion);
});
