import test, { after } from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import jwt from 'jsonwebtoken';
import pg from 'pg';
import net from 'node:net';
import {spawn} from 'node:child_process';
import {once} from 'node:events';

assert.ok(process.env.DATABASE_URL && process.env.JWT_SECRET?.length >= 32,
  'Use a migrated synthetic PostgreSQL database and synthetic signing secret');
const pool=new pg.Pool({connectionString:process.env.DATABASE_URL});
const users = [], families = [];
let server, base;
async function restart() {
  if(server) { const closed=once(server,'close'); server.kill('SIGTERM'); await closed; }
  const reservation=net.createServer().listen(0,'127.0.0.1');
  await once(reservation,'listening'); const port=reservation.address().port;
  await new Promise(resolve=>reservation.close(resolve));
  base=`http://127.0.0.1:${port}`;
  server=spawn(process.execPath,['src/entrypoint.js'],{stdio:['ignore','pipe','pipe'],env:{...process.env,
    NODE_ENV:'production',PORT:String(port),SMS_PROVIDER:'disabled',SMS_PROVIDER_URL:'',SMS_PROVIDER_TOKEN:'',
    EMAIL_FROM:'',RESEND_API_KEY:'',SMTP_HOST:'',SMTP_PASSWORD:'',ENABLE_SENSITIVE_FEATURES:'false',
    CORS_ORIGINS:'',TRUSTED_PROXY_CIDRS:'',RATE_LIMIT_AUTH_MAX:'2000',RATE_LIMIT_GENERAL_MAX:'4000'}});
  await new Promise((resolve,reject)=>{
    let output=''; const timeout=setTimeout(()=>reject(new Error('Goal API process startup timed out')),10000);
    server.stdout.on('data',chunk=>{output+=chunk.toString();if(output.includes('"type":"startup"')) {clearTimeout(timeout);resolve();}});
    server.once('error',error=>{clearTimeout(timeout);reject(error);});
    server.once('exit',code=>{clearTimeout(timeout);reject(new Error(`Goal API process stopped before startup (${code})`));});
  });
}
await restart();
after(async () => {
  if(server && server.exitCode===null && server.signalCode===null) {
    const closed=once(server,'close'); server.kill('SIGTERM'); await closed;
  }
  try {
    if (families.length) await pool.query('delete from family_workspace where id=any($1::uuid[])', [families]);
    if (users.length) await pool.query('delete from app_user where id=any($1::uuid[])', [users]);
  } finally { await pool.end(); }
});
async function actor() {
  const id = crypto.randomUUID(), sid = crypto.randomUUID(); users.push(id);
  await pool.query('insert into app_user(id,identity_subject,email_normalized,email_verified_at) values($1,$2,$3,now())', [id, `goal-test:${id}`, `goal-${id}@example.test`]);
  await pool.query("insert into profile(user_id,display_name) values($1,'Synthetic Goal')", [id]);
  await pool.query("insert into auth_session(id,user_id,refresh_digest,expires_at) values($1,$2,$3,now()+interval '1 day')", [sid,id,crypto.randomUUID()]);
  return {id,sid, token: jwt.sign({sub:id,sid,aud:'lifemate-api'},process.env.JWT_SECRET,{issuer:'lifemate',expiresIn:'15m'})};
}
async function request(actor, method, path, body) {
  const response = await fetch(base+'/v1/learning/goals'+path,{method,
    headers:{'content-type':'application/json',...(actor?{authorization:`Bearer ${actor.token}`}:{})},
    ...(body===undefined?{}:{body:JSON.stringify(body)})});
  const raw = await response.text();
  return {status:response.status,body:raw?JSON.parse(raw):null};
}
const create = () => ({id:crypto.randomUUID(),mutationId:crypto.randomUUID(),expectedVersion:0,title:'هدف ساختگی',target:'Private synthetic target'});

test('modern goal creates one stable record, retries lost acknowledgement after real API process restart and retains archive tombstone/history',async()=>{
  const owner=await actor(), body=create();
  const first=await request(owner,'POST','',body);
  assert.equal(first.status,201); assert.ok(first.body.goal,'Canonical goal acknowledgement is required'); assert.equal(first.body.goal.id,body.id);
  assert.equal(first.body.goal.version,1); assert.equal(first.body.acknowledgement.mutationId,body.mutationId);
  const firstProcess=server.pid; await restart(); assert.notEqual(server.pid,firstProcess);
  const retry=await request(owner,'POST','',body); assert.equal(retry.status,200);
  assert.equal(retry.body.acknowledgement.status,'already_applied');
  assert.equal((await pool.query('select count(*)::int n from learning_goal where id=$1',[body.id])).rows[0].n,1);
  const checkin=(await pool.query('insert into learning_checkin(owner_user_id,learning_goal_id,confidence,note) values($1,$2,3,$3) returning id',[owner.id,body.id,'PRIVATE-SYNTHETIC-NOTE'])).rows[0];
  const edit={mutationId:crypto.randomUUID(),expectedVersion:1,title:'ویرایش ساختگی',target:null,status:'completed'};
  assert.equal((await request(owner,'PATCH','/'+body.id,edit)).body.goal.version,2);
  const archive={mutationId:crypto.randomUUID(),expectedVersion:2};
  const archived=await request(owner,'DELETE','/'+body.id,archive); assert.equal(archived.status,200); assert.equal(archived.body.goal.status,'archived');
  const oldCreate=await request(owner,'POST','',body); assert.equal(oldCreate.body.goal.status,'archived');
  assert.equal(oldCreate.body.goal.version,3); assert.equal(oldCreate.body.acknowledgement.appliedVersion,1);
  assert.equal((await request(owner,'DELETE','/'+body.id,archive)).body.goal.version,3);
  assert.equal((await request(owner,'GET','')).body.items.length,0);
  assert.equal((await request(owner,'GET','/'+body.id)).body.status,'archived');
  const retained=(await pool.query('select learning_goal_id,note from learning_checkin where id=$1',[checkin.id])).rows[0];
  assert.deepEqual(retained,{learning_goal_id:body.id,note:'PRIVATE-SYNTHETIC-NOTE'});
});

test('goal mutation hash and expected version reject reuse, concurrent stale edits and archived revival',async()=>{
  const owner=await actor(),body=create(); await request(owner,'POST','',body);
  assert.equal((await request(owner,'POST','',{...body,title:'Changed intent'})).status,409);
  const results=await Promise.all(['One','Two'].map(title=>request(owner,'PATCH','/'+body.id,{title,mutationId:crypto.randomUUID(),expectedVersion:1})));
  assert.deepEqual(results.map(x=>x.status).sort(),[200,409]);
  await request(owner,'DELETE','/'+body.id,{mutationId:crypto.randomUUID(),expectedVersion:2});
  assert.equal((await request(owner,'PATCH','/'+body.id,{status:'active',mutationId:crypto.randomUUID(),expectedVersion:3})).status,409);
  assert.equal((await pool.query('select count(*)::int n from learning_goal_mutation where owner_user_id=$1',[owner.id])).rows[0].n,3);
});

test('guardian and other family cannot read or mutate private goals, including request-owner injection',async()=>{
  const owner=await actor(),guardian=await actor(),other=await actor(),family=crypto.randomUUID(); families.push(family);
  await pool.query("insert into family_workspace(id,name,created_by) values($1,'Synthetic Goal Family',$2)",[family,guardian.id]);
  await pool.query("insert into family_membership(family_id,user_id,role) values($1,$2,'teen_minor'),($1,$3,'parent_guardian')",[family,owner.id,guardian.id]);
  await pool.query('insert into guardian_relationship(family_id,guardian_user_id,minor_user_id) values($1,$2,$3)',[family,guardian.id,owner.id]);
  const body=create(); await request(owner,'POST','',body);
  for(const viewer of [guardian,other]) {
    assert.equal((await request(viewer,'GET','/'+body.id)).status,404);
    assert.deepEqual((await request(viewer,'GET','')).body.items,[]);
    assert.equal((await request(viewer,'PATCH','/'+body.id,{title:'Forbidden',mutationId:crypto.randomUUID(),expectedVersion:1})).status,403);
    assert.equal((await request(viewer,'DELETE','/'+body.id,{mutationId:crypto.randomUUID(),expectedVersion:1})).status,403);
  }
  assert.equal((await request(owner,'POST','',{...create(),ownerUserId:other.id})).status,400);
  for(const method of ['GET','POST','PATCH','DELETE']) assert.equal((await request(null,method,method==='POST'?'':'/'+body.id,method==='GET'?undefined:{})).status,401);
});

async function schoolSubject(owner, {subjectOwner=owner,activeContext=true,activeYear=true,activeTerm=true,archived=false}={}) {
  const context=crypto.randomUUID(),year=crypto.randomUUID(),term=crypto.randomUUID(),subject=crypto.randomUUID();
  await pool.query("insert into life_context(id,user_id,kind,title) values($1,$2,'student','Synthetic Goal Context')",[context,subjectOwner.id]);
  await pool.query("insert into academic_year(id,student_user_id,life_context_id,title,starts_on,ends_on) values($1,$2,$3,'Synthetic Year','2026-09-23','2027-06-22')",[year,subjectOwner.id,context]);
  await pool.query("insert into academic_term(id,academic_year_id,title,starts_on,ends_on) values($1,$2,'Synthetic Term','2026-09-23','2027-01-22')",[term,year]);
  await pool.query("insert into subject(id,student_user_id,academic_term_id,name,archived_at) values($1,$2,$3,'Synthetic Math',case when $4 then now() else null end)",[subject,subjectOwner.id,term,archived]);
  if(!activeContext) await pool.query('update life_context set active=false where id=$1',[context]);
  if(!activeYear) await pool.query('update academic_year set active=false where id=$1',[year]);
  if(!activeTerm) await pool.query('update academic_term set active=false where id=$1',[term]);
  return {id:subject,context,year};
}

test('legacy and modern goals reject archived, inactive and foreign-owned school ancestry',async()=>{
  const owner=await actor(),other=await actor();
  const cases=[{archived:true},{activeContext:false},{activeYear:false},{activeTerm:false},{subjectOwner:other}];
  for(const scenario of cases) {
    const subject=await schoolSubject(owner,scenario);
    const legacy=await request(owner,'POST','',{title:'Forbidden ancestry',subjectId:subject.id});
    assert.equal(legacy.status,403,`legacy POST must reject ${Object.keys(scenario)[0]}`);
    const modern=await request(owner,'POST','',{...create(),subjectId:subject.id});
    assert.equal(modern.status,403,`modern POST must reject ${Object.keys(scenario)[0]}`);
    const goal=await request(owner,'POST','',create());
    assert.equal((await request(owner,'PATCH','/'+goal.body.goal.id,{subjectId:subject.id})).status,403);
    assert.equal((await request(owner,'PATCH','/'+goal.body.goal.id,{subjectId:subject.id,mutationId:crypto.randomUUID(),expectedVersion:1})).status,403);
    assert.equal((await request(owner,'GET','/'+goal.body.goal.id)).body.version,1);
  }
  const subject=await schoolSubject(owner);
  const linked=await request(owner,'POST','',{...create(),subjectId:subject.id});
  assert.equal(linked.status,201); assert.equal(linked.body.goal.subject_id,subject.id);
  // Historical goal text remains editable after its school parent is inactive;
  // only a new/reassigned subject link requires the currently active ancestry.
  await pool.query('update academic_year set active=false where id=$1',[subject.year]);
  const edited=await request(owner,'PATCH','/'+linked.body.goal.id,{mutationId:crypto.randomUUID(),expectedVersion:1,title:'Historical goal correction'});
  assert.equal(edited.status,200); assert.equal(edited.body.goal.subject_id,subject.id);
});

test('legacy response shapes retain CRUD while versions and archive timestamps remain consistent',async()=>{
  const owner=await actor();
  const created=await request(owner,'POST','',{title:'Legacy goal',target:'Legacy target'});
  assert.equal(created.status,201); assert.equal(created.body.version,1); assert.ok(created.body.id); assert.equal(created.body.goal,undefined);
  const edited=await request(owner,'PATCH','/'+created.body.id,{target:null,status:'completed'});
  assert.equal(edited.status,200); assert.equal(edited.body.version,2); assert.equal(edited.body.target,null); assert.equal(edited.body.archived_at,null);
  const archived=await request(owner,'PATCH','/'+created.body.id,{status:'archived'});
  assert.equal(archived.body.version,3); assert.ok(archived.body.archived_at);
  assert.equal((await request(owner,'DELETE','/'+created.body.id)).status,204);
  assert.equal((await request(owner,'DELETE','/'+created.body.id)).status,204);
  const tombstone=await request(owner,'GET','/'+created.body.id);
  assert.equal(tombstone.body.version,3); assert.equal(tombstone.body.archived_at,archived.body.archived_at);
  assert.equal((await request(owner,'PATCH','/'+created.body.id,{status:'active'})).status,409);
});

test('goals validate exact write fields, text types, status and bounded versions without silently applying them',async()=>{
  const owner=await actor(),goal=await request(owner,'POST','',create()),id=goal.body.goal.id;
  const invalidCreates=[null,[],{title:{text:'Coercion'}},{title:'Too long',target:'x'.repeat(1001)},
    {title:'Injected owner',ownerUserId:owner.id},{title:'Claimed verification',source:'verified'},
    {title:'Invalid status',status:'verified'},{title:'Nul\u0000byte'}];
  for(const body of invalidCreates) assert.equal((await request(owner,'POST','',body)).status,400);
  for(const body of [{},[],{source:'verified'},{ownerUserId:owner.id},{title:'Nul\u0000byte'},
    {status:'verified'},{title:'Valid',mutationId:crypto.randomUUID(),expectedVersion:0},
    {title:'Valid',mutationId:crypto.randomUUID(),expectedVersion:2147483647},
    {title:'Valid',mutationId:crypto.randomUUID(),expectedVersion:2147483648}]) {
    assert.equal((await request(owner,'PATCH','/'+id,body)).status,400);
  }
  assert.equal((await request(owner,'DELETE','/'+id,{source:'verified'})).status,400);
  assert.equal((await request(owner,'PATCH','/'+id+'?ownerUserId='+owner.id,{title:'Valid'})).status,400);
  assert.equal((await request(owner,'GET','/'+id)).body.version,1);
});

async function waitForBlockedRequest(blockerPid) {
  for(let tries=0;tries<100;tries++) {
    const blocked=await pool.query('select 1 from pg_stat_activity where $1::int=any(pg_blocking_pids(pid))',[blockerPid]);
    if(blocked.rowCount) return;
    await new Promise(resolve=>setTimeout(resolve,10));
  }
  assert.fail('The real HTTP write never reached the PostgreSQL lock wait');
}

test('legacy and modern goal writes recheck expired/revoked sessions and JWT after an actual account lock wait',async()=>{
  for(const modern of [false,true]) for(const reason of ['session_expiry','revocation','jwt_expiry']) {
    const owner=await actor(),body=modern?create():{title:'Blocked synthetic goal'};
    let expiresAt;
    if(reason==='jwt_expiry') {
      expiresAt=Math.floor(Date.now()/1000)+2;
      owner.token=jwt.sign({sub:owner.id,sid:owner.sid,aud:'lifemate-api',exp:expiresAt},process.env.JWT_SECRET,{issuer:'lifemate'});
    }
    const blocker=await pool.connect();
    let pending;
    try {
      await blocker.query('begin');
      const pid=(await blocker.query('select pg_backend_pid() pid')).rows[0].pid;
      await blocker.query('select id from app_user where id=$1 for update',[owner.id]);
      pending=request(owner,'POST','',body);
      await waitForBlockedRequest(pid);
      if(reason==='session_expiry') await pool.query("update auth_session set expires_at=statement_timestamp()-interval '1 second' where id=$1",[owner.sid]);
      if(reason==='revocation') await pool.query('update auth_session set revoked_at=statement_timestamp() where id=$1',[owner.sid]);
      if(reason==='jwt_expiry') await new Promise(resolve=>setTimeout(resolve,Math.max(0,expiresAt*1000-Date.now()+20)));
      await blocker.query('commit');
      const result=await pending;
      assert.equal(result.status,401,`${modern?'modern':'legacy'} ${reason} must rollback after waiting`);
      assert.equal((await pool.query('select count(*)::int n from learning_goal where owner_user_id=$1',[owner.id])).rows[0].n,0);
    } finally {
      await blocker.query('rollback'); blocker.release();
      if(pending) await pending;
    }
  }
});

test('goal final authorization rolls back a legacy or modern edit when JWT expires during the goal row wait',async()=>{
  for(const modern of [false,true]) {
    const owner=await actor(),created=await request(owner,'POST','',create());
    const id=created.body.goal.id,expiresAt=Math.floor(Date.now()/1000)+2;
    owner.token=jwt.sign({sub:owner.id,sid:owner.sid,aud:'lifemate-api',exp:expiresAt},process.env.JWT_SECRET,{issuer:'lifemate'});
    const blocker=await pool.connect(); let pending;
    try {
      await blocker.query('begin');
      const pid=(await blocker.query('select pg_backend_pid() pid')).rows[0].pid;
      await blocker.query('select id from learning_goal where id=$1 for update',[id]);
      pending=request(owner,'PATCH','/'+id,{title:'Must roll back',...(modern?{mutationId:crypto.randomUUID(),expectedVersion:1}:{})});
      await waitForBlockedRequest(pid);
      await new Promise(resolve=>setTimeout(resolve,Math.max(0,expiresAt*1000-Date.now()+20)));
      await blocker.query('commit');
      assert.equal((await pending).status,401);
      const stored=(await pool.query('select title,version from learning_goal where id=$1',[id])).rows[0];
      assert.deepEqual(stored,{title:'هدف ساختگی',version:1});
      assert.equal((await pool.query('select count(*)::int n from learning_goal_mutation where owner_user_id=$1',[owner.id])).rows[0].n,1);
    } finally {
      await blocker.query('rollback'); blocker.release();
      if(pending) await pending;
    }
  }
});

test('two owners concurrently using the same stable goal ID get one create and one denied conflict without a server error',async()=>{
  const first=await actor(),second=await actor(),id=crypto.randomUUID();
  const blocker=await pool.connect(); let pending;
  try {
    await blocker.query('begin'); await blocker.query('lock table learning_goal in share mode');
    const blockerPid=(await blocker.query('select pg_backend_pid() pid')).rows[0].pid;
    pending=Promise.all([first,second].map(owner=>request(owner,'POST','',{...create(),id})));
    // Without entity serialization both creates reach the blocked INSERT after
    // independently seeing no row. With serialization the second waits at the
    // advisory lock, and observes the first committed row after release.
    await waitForBlockedRequest(blockerPid);
    await new Promise(resolve=>setTimeout(resolve,50));
    await blocker.query('commit');
    const results=await pending;
    assert.deepEqual(results.map(result=>result.status).sort(),[201,403]);
    assert.equal((await pool.query('select count(*)::int n from learning_goal where id=$1',[id])).rows[0].n,1);
    const journal=await pool.query('select owner_user_id from learning_goal_mutation where goal_id=$1',[id]);
    const goal=(await pool.query('select owner_user_id from learning_goal where id=$1',[id])).rows[0];
    assert.deepEqual(journal.rows,[goal]);
    const denied=results.find(result=>result.status===403);
    assert.deepEqual(denied.body,{error:'goal_forbidden'});
  } finally {
    await blocker.query('rollback');blocker.release();if(pending) await pending;
  }
});
