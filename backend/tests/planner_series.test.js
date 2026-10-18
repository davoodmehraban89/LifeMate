// Real HTTP and disposable loopback PostgreSQL; invented accounts only.
import test, { after } from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import express from 'express';
import jwt from 'jsonwebtoken';
import pg from 'pg';
import { createSessionAuth } from '../src/session_auth.js';
import { createPhase3Router } from '../src/phase3.js';

const location = new URL(process.env.DATABASE_URL);
assert.ok(['127.0.0.1','localhost','[::1]'].includes(location.hostname), 'Loopback fixture only');
const pool = new pg.Pool({ connectionString: location.href });
const secret = 'synthetic-planner-recurrence-secret-not-for-live-use';
const app = express(); app.use(express.json());
app.use('/v1', createPhase3Router({ pool, auth: createSessionAuth({ pool, jwtSecret: secret,
  env: { NODE_ENV: 'test', ENABLE_CHILD_IDENTITY_SANDBOX: 'true' } }) }));
app.use((error, _req, res, _next) => res.status(error.status ?? 500).json({ error: error.code ?? 'internal_error' }));
const server = app.listen(0, '127.0.0.1'); await new Promise(resolve => server.once('listening', resolve));
const base = `http://127.0.0.1:${server.address().port}/v1`;
after(async () => { await new Promise(resolve => server.close(resolve)); await pool.end(); });
const uuid = () => crypto.randomUUID();
const today = new Date().toISOString().slice(0,10);
const day = (n, from = today) => new Date(Date.parse(from + 'T00:00:00Z') + n * 86400000).toISOString().slice(0,10);
async function user() {
  const id = uuid(), sid = uuid();
  await pool.query('insert into app_user(id,identity_subject,email_normalized) values($1,$2,$3)', [id, 'recurrence:' + id, id + '@example.test']);
  await pool.query("insert into profile(user_id,display_name,birth_date) values($1,'Synthetic planner','1985-01-01')", [id]);
  await pool.query("insert into auth_session(id,user_id,refresh_digest,expires_at) values($1,$2,$3,now()+interval '1 day')", [sid,id,uuid()]);
  return { id, token: jwt.sign({ sub:id,sid,aud:'lifemate-api' },secret,{ issuer:'lifemate',expiresIn:'15m' }) };
}
async function request(actor, method, path, body) {
  const r = await fetch(base + path, { method, headers: { 'content-type':'application/json', ...(actor ? { authorization:'Bearer ' + actor.token } : {}) },
    body: body === undefined ? undefined : JSON.stringify(body) });
  const text = await r.text();
  return { status:r.status, body:r.headers.get('content-type')?.includes('application/json') ? JSON.parse(text) : text };
}
const config = (extra = {}) => ({ id:uuid(), title:'برنامهٔ ساختگی', kind:'routine', timezone:'UTC', startsOn:day(2), frequency:'daily',
  intervalDays:1, slots:[{ start:'09:00',end:'09:30' }], reminderMinutes:[10,0,10], ...extra });
const rows = async id => (await pool.query('select p.*,p.original_occurrence_date::text as original_occurrence_date from plan_item p where p.series_id=$1 order by p.original_occurrence_date', [id])).rows;

test('daily series materializes 60 private independent occurrences with Tehran wall times, ends and real reminders', async () => {
  const actor = await user(), body = config({ timezone:'Asia/Tehran' });
  const r = await request(actor,'POST','/planner-series',body); assert.equal(r.status,201); assert.equal(r.body.items.length,60);
  const items = await rows(body.id); assert.equal(items.length,60);
  assert.equal(items[0].starts_at.toISOString(),body.startsOn + 'T05:30:00.000Z');
  assert.equal(items[0].ends_at.toISOString(),body.startsOn + 'T06:00:00.000Z');
  assert.equal(items[0].planned_duration_seconds,1800); assert.equal(items[0].version,'1');
  assert.ok(items.every(i => i.visibility === 'private' && i.family_id === null && i.owner_user_id === actor.id));
  assert.equal((await pool.query('select count(*)::int n from reminder where plan_item_id=any($1::uuid[])',[items.map(i => i.id)])).rows[0].n,120);
  assert.equal(r.body.series.materialized_through,day(59,body.startsOn));
});
test('same-id retry and simultaneous materialization do not duplicate occurrences; changed request conflicts', async () => {
  const actor = await user(), body = config({ untilOn:day(5) });
  const replies = await Promise.all([request(actor,'POST','/planner-series',body),request(actor,'POST','/planner-series',body)]);
  assert.deepEqual(replies.map(r => r.status).sort(),[200,201]); assert.equal((await rows(body.id)).length,4);
  assert.equal((await request(actor,'POST','/planner-series',{ ...body,title:'Changed' })).status,409);
  for (const r of await Promise.all([1,2].map(() => request(actor,'POST',`/planner-series/${body.id}/materialize`,{ from:day(2),to:day(5) })))) assert.equal(r.status,200);
  assert.equal((await rows(body.id)).length,4);
});
test('alternate days keep original start anchor when initial materialization begins today', async () => {
  const actor = await user(), body = config({ startsOn:day(-7),untilOn:day(5),intervalDays:2 });
  assert.equal((await request(actor,'POST','/planner-series',body)).status,201);
  assert.deepEqual((await rows(body.id)).map(i => i.original_occurrence_date),[1,3,5].map(n => day(n)));
  assert.equal((await request(actor,'POST',`/planner-series/${body.id}/materialize`,{ from:day(-7),to:day(-1) })).status,200);
  assert.deepEqual((await rows(body.id)).map(i => i.original_occurrence_date),[-7,-5,-3,-1,1,3,5].map(n => day(n)));
});
test('weekday slots vary and completion, moved dates and cancelled exceptions survive regeneration', async () => {
  const actor = await user(), body = config({ startsOn:day(2),untilOn:day(15),frequency:'weekly',
    slots:[{ weekday:1,start:'08:00',end:'09:00' },{ weekday:4,start:'16:15',end:'17:00' }] });
  assert.equal((await request(actor,'POST','/planner-series',body)).status,201);
  const items = await rows(body.id); assert.equal(items.length,4);
  for (const i of items) assert.equal(i.starts_at.toISOString().slice(11,16),new Date(i.original_occurrence_date).getUTCDay() === 1 ? '08:00' : '16:15');
  assert.equal((await request(actor,'PATCH',`/plan-items/${items[0].id}`,{ expectedVersion:1,status:'completed' })).status,200);
  assert.equal((await request(actor,'PATCH',`/plan-items/${items[1].id}`,{ expectedVersion:1,startsAt:day(50) + 'T10:00:00Z',endsAt:day(50) + 'T11:00:00Z' })).status,200);
  assert.equal((await request(actor,'DELETE',`/plan-items/${items[2].id}`,{ expectedVersion:1 })).status,200);
  assert.equal((await request(actor,'POST',`/planner-series/${body.id}/materialize`,{ from:body.startsOn,to:body.untilOn })).status,200);
  const after = await rows(body.id); assert.equal(after.length,4); assert.equal(after[0].status,'completed');
  assert.equal(after[1].starts_at.toISOString(),day(50) + 'T10:00:00.000Z'); assert.equal(after[1].original_occurrence_date,items[1].original_occurrence_date);
  assert.equal(after[2].status,'cancelled'); assert.equal(after[3].version,'1');
});
test('invalid date, timezone, slots, sharing and oversized materialization windows reject atomically', async () => {
  const actor = await user();
  for (const invalid of [{ startsOn:'2026-02-30' },{ startsOn:'0000-01-01' },{ startsOn:day(731) },{ untilOn:day(-1) },{ timezone:'Mars/Olympus' },
    { intervalDays:3 },{ frequency:'monthly' },{ slots:[] },{ slots:[{ start:'25:00',end:'26:00' }] },{ slots:[{ start:'10:00',end:'10:00' }] },
    { slots:[{ start:['09:00'],end:['10:00'] }] },{ frequency:'weekly',slots:[{ weekday:0,start:'08:00',end:'09:00' }] },
    { frequency:'weekly',slots:[{ weekday:1,start:'08:00',end:'09:00' },{ weekday:1,start:'11:00',end:'12:00' }] },{ reminderMinutes:[-1] },
    { visibility:'family' },{ ownerUserId:uuid() }]) {
    const body = config(invalid); assert.equal((await request(actor,'POST','/planner-series',body)).status,400,JSON.stringify(invalid));
    assert.equal((await pool.query('select count(*)::int n from plan_item where series_id=$1',[body.id])).rows[0].n,0);
  }
  const body = config(); assert.equal((await request(actor,'POST','/planner-series',body)).status,201);
  for (const window of [{ from:day(1),to:day(94) },{ from:day(5),to:day(4) },{ from:'2026-02-30',to:day(4) },{ from:day(731),to:day(732) }])
    assert.equal((await request(actor,'POST',`/planner-series/${body.id}/materialize`,window)).status,400);
});
test('only owner can read, extend or archive a series; generic edits cannot publish its private occurrences', async () => {
  const actor = await user(), outsider = await user(), body = config({ untilOn:day(2) });
  assert.equal((await request(null,'GET','/planner-series')).status,401);
  assert.equal((await request(actor,'POST','/planner-series',body)).status,201);
  assert.equal((await request(actor,'GET','/planner-series')).body.series.length,1);
  assert.equal((await request(outsider,'GET',`/planner-series/${body.id}`)).status,404);
  assert.equal((await request(outsider,'DELETE',`/planner-series/${body.id}`,{ expectedVersion:1 })).status,404);
  assert.equal((await request(outsider,'POST',`/planner-series/${body.id}/materialize`,{ from:day(2),to:day(3) })).status,404);
  const i = (await rows(body.id))[0]; assert.equal((await request(outsider,'GET',`/plan-items/${i.id}`)).status,404);
  assert.equal((await request(actor,'PATCH',`/plan-items/${i.id}`,{ expectedVersion:1,visibility:'family',familyId:uuid() })).status,400);
});
test('archive requires latest series version and preserves historical and completed occurrences', async () => {
  const actor = await user(), body = config({ startsOn:day(-2),untilOn:day(4) });
  assert.equal((await request(actor,'POST','/planner-series',body)).status,201);
  assert.equal((await request(actor,'POST',`/planner-series/${body.id}/materialize`,{ from:day(-2),to:day(4) })).status,200);
  const completed = (await rows(body.id)).find(i => i.original_occurrence_date === day(3));
  assert.equal((await request(actor,'PATCH',`/plan-items/${completed.id}`,{ expectedVersion:1,status:'completed' })).status,200);
  const version = (await request(actor,'GET',`/planner-series/${body.id}`)).body.series.version;
  assert.equal((await request(actor,'DELETE',`/planner-series/${body.id}`,{})).status,400);
  assert.equal((await request(actor,'DELETE',`/planner-series/${body.id}`,{ expectedVersion:version - 1 })).status,409);
  assert.equal((await request(actor,'DELETE',`/planner-series/${body.id}`,{ expectedVersion:version })).status,200);
  const after = await rows(body.id); assert.ok(after.filter(i => i.original_occurrence_date < today).every(i => i.status === 'planned'));
  assert.equal(after.find(i => i.id === completed.id).status,'completed');
  assert.ok(after.filter(i => i.original_occurrence_date > today && i.id !== completed.id).every(i => i.status === 'cancelled'));
  assert.equal((await request(actor,'POST',`/planner-series/${body.id}/materialize`,{ from:day(5),to:day(6) })).status,409);
});
test('endsAt validates partial updates against stored starts and ends while legacy due-only payloads work', async () => {
  const actor = await user(), start = day(2) + 'T10:00:00Z', end = day(2) + 'T11:00:00Z';
  const r = await request(actor,'POST','/plan-items',{ kind:'event',title:'Synthetic range',startsAt:start,endsAt:end }); assert.equal(r.status,201);
  assert.equal(r.body.ends_at,day(2) + 'T11:00:00.000Z');
  assert.equal((await request(actor,'PATCH',`/plan-items/${r.body.id}`,{ expectedVersion:1,startsAt:day(2) + 'T12:00:00Z' })).status,400);
  assert.equal((await request(actor,'PATCH',`/plan-items/${r.body.id}`,{ expectedVersion:1,endsAt:start })).status,400);
  assert.equal((await request(actor,'POST','/plan-items',{ kind:'event',title:'Bad date',startsAt:'2026-02-28T10:00:00Z',endsAt:'2026-02-30T11:00:00Z' })).status,400);
  assert.equal((await request(actor,'POST','/plan-items',{ kind:'task',title:'Legacy due only',dueAt:end })).status,201);
});
test('canonical reminder windows are owner-only, bounded48h and exclude completed or cancelled items', async () => {
  const actor = await user(), outsider = await user(), body = config({ startsOn:today,untilOn:day(1) });
  assert.equal((await request(actor,'POST','/planner-series',body)).status,201);
  const path = `/planner-reminders?from=${today}T00:00:00Z&to=${day(2)}T00:00:00Z`;
  const r = await request(actor,'GET',path); assert.equal(r.status,200); assert.equal(r.body.reminders.length,4);
  assert.deepEqual(Object.keys(r.body.reminders[0]).sort(),['id','owner_user_id','plan_item_id','scheduled_for']);
  assert.equal((await request(outsider,'GET',path)).body.reminders.length,0); assert.equal((await request(null,'GET',path)).status,401);
  assert.equal((await request(actor,'GET',`/planner-reminders?from=${today}T00:00:00Z&to=${day(3)}T00:00:00Z`)).status,400);
  assert.equal((await request(actor,'GET','/planner-reminders?from=2026-02-30T09:00:00Z&to=2026-03-02T10:00:00Z')).status,400);
  const items = await rows(body.id);
  assert.equal((await request(actor,'PATCH',`/plan-items/${items[0].id}`,{ expectedVersion:1,status:'completed' })).status,200);
  assert.equal((await request(actor,'DELETE',`/plan-items/${items[1].id}`,{ expectedVersion:1 })).status,200);
  assert.equal((await request(actor,'GET',path)).body.reminders.length,0);
});
test('managed-child education sessions cannot read or write personal series or upcoming reminders', async () => {
  const guardian = await user(), child = await user(), family = uuid();
  await pool.query('update app_user set is_managed_child=true,email_normalized=null where id=$1',[child.id]);
  await pool.query("update profile set birth_date='2015-03-12' where user_id=$1",[child.id]);
  await pool.query("insert into family_workspace(id,name,created_by) values($1,'Synthetic family',$2)",[family,guardian.id]);
  await pool.query("insert into family_membership(family_id,user_id,role) values($1,$2,'parent_guardian'),($1,$3,'teen_minor')",[family,guardian.id,child.id]);
  await pool.query('insert into guardian_relationship(family_id,guardian_user_id,minor_user_id) values($1,$2,$3)',[family,guardian.id,child.id]);
  await pool.query('insert into managed_child(user_id,family_id,creator_user_id) values($1,$2,$3)',[child.id,family,guardian.id]);
  await pool.query("insert into child_consent(child_user_id,actor_user_id,text_version,text_digest) values($1,$2,'sandbox-child-consent-v1-not-legal','5dbf640a23b538800c82791620c3a43947b7346d7eff179e6f7d5afe5a55b387')",[child.id,guardian.id]);
  await pool.query("update auth_session set access_scope='child_education',child_issuer_user_id=$2 where user_id=$1",[child.id,guardian.id]);
  for (const [method,path,body] of [['GET','/planner-series'],['POST','/planner-series',config()],['GET',`/planner-series/${uuid()}`],
    ['POST',`/planner-series/${uuid()}/materialize`,{ from:today,to:day(1) }],['DELETE',`/planner-series/${uuid()}`,{ expectedVersion:1 }],
    ['GET',`/planner-reminders?from=${today}T00:00:00Z&to=${day(1)}T00:00:00Z`]]) {
    const r = await request(child,method,path,body); assert.equal(r.status,403,path); assert.equal(r.body.error,'child_session_scope_denied');
  }
});
