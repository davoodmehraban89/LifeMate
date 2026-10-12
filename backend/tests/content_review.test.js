import test, {describe,before,after} from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {spawn,spawnSync} from 'node:child_process';
import {once} from 'node:events';
import net from 'node:net';
import pg from 'pg';
import jwt from 'jsonwebtoken';
import {manageCapability,localSyntheticConnection,normalizeCapabilityOperation} from '../scripts/manage-content-capabilities.js';

const uuid=()=>crypto.randomUUID();
const privateMarker='SYNTHETIC-CHOSEN-SUMMARY-NEVER-IN-BRIEF';

test('operator CLI is explicit, separate, local-test-only and scope/expiry bounded',()=>{
  const expiry=new Date(Date.now()+60000).toISOString();
  assert.ok(normalizeCapabilityOperation(['grant',uuid(),'feedback.read',expiry]));
  assert.ok(normalizeCapabilityOperation(['revoke',uuid(),'brief.prepare']));
  for(const args of [['grant',uuid(),'admin',expiry],['grant',uuid(),'feedback.read','2020-01-01T00:00:00Z'],
    ['grant',uuid(),'feedback.read'],['revoke',uuid(),'feedback.read',expiry]]) assert.equal(normalizeCapabilityOperation(args),null);
  assert.throws(()=>localSyntheticConnection({DATABASE_URL:'postgresql://localhost/test'}));
  assert.throws(()=>localSyntheticConnection({CONTENT_CAPABILITY_DATABASE_URL:'postgresql://foreign.example/test',CONTENT_CAPABILITY_SYNTHETIC_ONLY:'true'}));
  assert.throws(()=>localSyntheticConnection({CONTENT_CAPABILITY_DATABASE_URL:'postgresql://localhost/production',CONTENT_CAPABILITY_SYNTHETIC_ONLY:'true'}));
  assert.ok(localSyntheticConnection({CONTENT_CAPABILITY_DATABASE_URL:'postgresql://localhost/lifeguide_library_test',CONTENT_CAPABILITY_SYNTHETIC_ONLY:'true'}));
});

describe('content operations real entrypoint HTTP and synthetic PostgreSQL', {concurrency:false},()=>{
  let pool,child,base;
  let output='',errors='';
  const users=[],families=[];
  const serviceEnv={...process.env};delete serviceEnv.TEST_FIXTURE_DATABASE_URL;
  const applicationName=`content-review-fixture-${uuid()}`;
  async function start() {
    const listener=net.createServer().listen(0,'127.0.0.1');await once(listener,'listening');
    const port=listener.address().port;await new Promise(resolve=>listener.close(resolve));
    base=`http://127.0.0.1:${port}`;
    let startup='';
    child=spawn(process.execPath,['src/entrypoint.js'],{env:{...serviceEnv,NODE_ENV:'production',PORT:String(port),PGAPPNAME:applicationName,
      SMS_PROVIDER:'disabled',SMS_PROVIDER_URL:'',SMS_PROVIDER_TOKEN:'',EMAIL_FROM:'',RESEND_API_KEY:'',
      SMTP_HOST:'',SMTP_USER:'',SMTP_PASSWORD:'',AI_API_KEY:'',AI_BASE_URL:'',AI_MODEL:'',OPENAI_API_KEY:'',
      CORS_ORIGINS:'',TRUSTED_PROXY_CIDRS:'',ENABLE_SENSITIVE_FEATURES:'false',
      RATE_LIMIT_AUTH_MAX:'2000',RATE_LIMIT_GENERAL_MAX:'8000'},stdio:['ignore','pipe','pipe']});
    child.stdout.on('data',chunk=>{output+=chunk;startup+=chunk;});child.stderr.on('data',chunk=>{errors+=chunk;});
    await new Promise((resolve,reject)=>{
      const timeout=setTimeout(()=>reject(new Error('Content fixture startup timed out')),10000);
      const ready=()=>{if(startup.includes('"type":"startup"')){clearTimeout(timeout);child.stdout.off('data',ready);resolve();}};
      child.stdout.on('data',ready);child.once('error',()=>{clearTimeout(timeout);reject(new Error('Content fixture start failed'));});
      child.once('exit',()=>{if(!startup.includes('"type":"startup"')){clearTimeout(timeout);reject(new Error('Content fixture exited early'));}});
    });
  }
  async function stop(){if(child&&child.exitCode===null&&child.signalCode===null){const ended=once(child,'close');child.kill('SIGTERM');await ended;}}
  before(async()=>{
    assert.ok(process.env.DATABASE_URL&&process.env.JWT_SECRET?.length>=32,'Migrated synthetic fixture required');
    const location=new URL(process.env.TEST_FIXTURE_DATABASE_URL??process.env.DATABASE_URL);
    assert.ok(['localhost','127.0.0.1','[::1]','::1'].includes(location.hostname),'Only loopback synthetic PostgreSQL is allowed');
    assert.ok(location.pathname.includes('test')||location.pathname==='/lifemate_ci'||
      /^\/lifeguide_roles_source_[a-f0-9]{16}$/.test(location.pathname),'Explicit test database required');
    pool=new pg.Pool({connectionString:process.env.TEST_FIXTURE_DATABASE_URL??process.env.DATABASE_URL});
    await start();
  });
  after(async()=>{
    await stop();if(!pool)return;
    try {
      await pool.query('delete from access_audit where family_id=any($1::uuid[]) or actor_user_id=any($2::uuid[])',[families,users]);
      await pool.query('delete from family_workspace where id=any($1::uuid[])',[families]);
      await pool.query('delete from app_user where id=any($1::uuid[])',[users]);
    } finally {await pool.end();}
  });
  async function actor(extraClaims={},expiresIn='15m'){
    const id=uuid(),sid=uuid();users.push(id);
    await pool.query('insert into app_user(id,identity_subject,email_normalized,email_verified_at) values($1,$2,$3,now())',
      [id,`content-review-fixture:${id}`,`content-review-${id}@example.test`]);
    await pool.query("insert into profile(user_id,display_name,theme_preference) values($1,'Synthetic Reviewer','adult_blue')",[id]);
    await pool.query("insert into auth_session(id,user_id,refresh_digest,expires_at) values($1,$2,$3,now()+interval '1 day')",[sid,id,crypto.randomBytes(32).toString('hex')]);
    return {id,sid,token:jwt.sign({...extraClaims,sub:id,sid,aud:'lifemate-api'},process.env.JWT_SECRET,{issuer:'lifemate',expiresIn})};
  }
  async function grant(user,scopes=['feedback.read','feedback.review','brief.prepare'],duration=3600000){
    const client=await pool.connect();
    try {for(const permission of scopes)await manageCapability(client,{action:'grant',userId:user.id,permission,
      expiresAt:new Date(Date.now()+duration).toISOString()});} finally {client.release();}
  }
  async function revoke(user,permission){const client=await pool.connect();try{await manageCapability(client,{action:'revoke',userId:user.id,permission,expiresAt:null});}finally{client.release();}}
  async function request(path,{method='GET',user,body}={}){
    const response=await fetch(base+path,{method,headers:{'content-type':'application/json',...(user?{authorization:`Bearer ${user.token}`}:{})},
      body:body===undefined?undefined:JSON.stringify(body)});
    const raw=await response.text();return {status:response.status,body:raw&&response.headers.get('content-type')?.includes('application/json')?JSON.parse(raw):raw||null};
  }
  async function feedback(user,{unitId=null,summary=privateMarker,category='topic_request'}={}){
    const created=await request('/v1/education/feedback',{method:'POST',user,body:{mutationId:uuid(),unitId,category,summary,shareWithContentTeam:true}});
    assert.equal(created.status,201);return created.body.feedback;
  }
  const list=(user,query='')=>request('/v1/content-review/feedback'+query,{user});
  const review=(user,row,status,mutationId=uuid())=>request(`/v1/content-review/feedback/${row.id}`,{method:'PATCH',user,
    body:{mutationId,expectedVersion:row.version,status}});
  const prepare=(user,rows,mutationId=uuid())=>request('/v1/content-review/briefs',{method:'POST',user,
    body:{mutationId,feedback:rows.map(row=>({id:row.id,expectedVersion:row.version}))}});
  const withdraw=(user,row)=>request(`/v1/me/education-feedback/${row.id}`,{method:'DELETE',user});
  async function planned(reviewer,row){
    const triaged=await review(reviewer,row,'triaged');assert.equal(triaged.status,200);
    const planned=await review(reviewer,triaged.body.feedback,'planned');assert.equal(planned.status,200);return planned.body.feedback;
  }
  async function blockedOn(client){
    const pid=(await client.query('select pg_backend_pid() pid')).rows[0].pid;
    const deadline=Date.now()+4000;
    while(Date.now()<deadline){
      const result=await pool.query(`select 1 from pg_stat_activity
        where application_name=$1 and $2=any(pg_blocking_pids(pid))`,[applicationName,pid]);
      if(result.rowCount)return;
      await new Promise(resolve=>setTimeout(resolve,20));
    }
    assert.fail('Real API request did not reach the expected PostgreSQL row-lock wait');
  }

  test('all capabilities default empty, family/admin/JWT claims do not authorize or grant',async()=>{
    const child=await actor(),parent=await actor({role:'admin',permissions:['feedback.read','feedback.review','brief.prepare']});
    const family=uuid();families.push(family);
    await pool.query("insert into family_workspace(id,name,created_by) values($1,'Synthetic Content Family',$2)",[family,parent.id]);
    await pool.query("insert into family_membership(family_id,user_id,role,is_admin) values($1,$2,'parent_guardian',true),($1,$3,'teen_minor',false)",[family,parent.id,child.id]);
    await pool.query('insert into guardian_relationship(family_id,guardian_user_id,minor_user_id) values($1,$2,$3)',[family,parent.id,child.id]);
    const row=await feedback(child);
    assert.deepEqual((await request('/v1/me/content-capabilities',{user:parent})).body,{permissions:[]});
    assert.equal((await list(parent)).status,403);
    assert.equal((await review(parent,row,'triaged')).status,403);
    assert.equal((await prepare(parent,[row])).status,403);
    assert.equal((await request(`/v1/content-review/briefs/${uuid()}`,{user:parent})).status,403);
    assert.equal((await request('/v1/me/content-capabilities')).status,401);
    assert.equal((await request('/v1/content-review/capabilities',{method:'POST',user:parent,body:{userId:parent.id,permission:'feedback.read'}})).status,404);
    assert.equal((await pool.query('select count(*)::int n from content_capability_grant where user_id=$1',[parent.id])).rows[0].n,0);
  });

  test('explicit permissions are independently scoped and revocation/expiry is checked on every route',async()=>{
    const owner=await actor(),reader=await actor();const row=await feedback(owner);
    await grant(reader,['feedback.read']);
    assert.deepEqual((await request('/v1/me/content-capabilities',{user:reader})).body,{permissions:['feedback.read']});
    assert.equal((await list(reader)).status,200);
    assert.equal((await review(reader,row,'triaged')).status,403);
    assert.equal((await prepare(reader,[row])).status,403);
    await grant(reader,['feedback.review','brief.prepare']);
    assert.equal((await review(reader,row,'triaged')).status,200);
    await revoke(reader,'feedback.read');
    for(const call of [()=>list(reader),()=>review(reader,row,'triaged'),()=>prepare(reader,[row]),
      ()=>request(`/v1/content-review/briefs/${uuid()}`,{user:reader})])assert.equal((await call()).status,403);
    await grant(reader,['feedback.read']);
    await pool.query("update content_capability_grant set granted_at=now()-interval '2 minutes',expires_at=now()-interval '1 minute' where user_id=$1",[reader.id]);
    assert.deepEqual((await request('/v1/me/content-capabilities',{user:reader})).body,{permissions:[]});
    assert.equal((await list(reader)).status,403);
  });

  test('standalone local synthetic operator CLI changes exact scopes without logging account or secrets',async()=>{
    const user=await actor();
    const env={...process.env,CONTENT_CAPABILITY_SYNTHETIC_ONLY:'true',
      CONTENT_CAPABILITY_DATABASE_URL:process.env.TEST_FIXTURE_DATABASE_URL??process.env.DATABASE_URL};
    const execute=args=>spawnSync(process.execPath,['scripts/manage-content-capabilities.js',...args],{env,encoding:'utf8'});
    const expiry=new Date(Date.now()+3600000).toISOString();
    const granted=execute(['grant',user.id,'feedback.read',expiry]);assert.equal(granted.status,0);
    const logged=JSON.parse(granted.stdout);assert.equal(logged.permission,'feedback.read');assert.equal(logged.action,'grant');
    assert.ok(!granted.stdout.includes(user.id));assert.ok(!granted.stdout.includes('postgres'));assert.equal(granted.stderr,'');
    assert.deepEqual((await request('/v1/me/content-capabilities',{user})).body,{permissions:['feedback.read']});
    const revoked=execute(['revoke',user.id,'feedback.read']);assert.equal(revoked.status,0);
    assert.deepEqual((await request('/v1/me/content-capabilities',{user})).body,{permissions:[]});
    assert.equal((await pool.query('select count(*)::int n from content_capability_audit where target_user_id=$1',[user.id])).rows[0].n,2);
    const rejected=spawnSync(process.execPath,['scripts/manage-content-capabilities.js','grant',user.id,'feedback.read',expiry],
      {env:{...env,CONTENT_CAPABILITY_DATABASE_URL:'postgresql://localhost/production'},encoding:'utf8'});
    assert.equal(rejected.status,1);assert.ok(!rejected.stderr.includes(user.id));assert.ok(!rejected.stderr.includes('postgresql://'));
  });

  test('review listing exposes only consented chosen summaries, strict projection, stable paging and count',async()=>{
    const owner=await actor(),reviewer=await actor();await grant(reviewer);
    const rows=[];for(let n=0;n<3;n++)rows.push(await feedback(owner,{category:'broken_video',summary:`Synthetic page ${n}`}));
    await withdraw(owner,rows[1]);
    const page=await list(reviewer,'?status=received&limit=1');assert.equal(page.status,200);
    const seen=new Set();let cursor=null,total=page.body.total;
    do{
      const next=await list(reviewer,`?status=received&limit=1${cursor?`&cursor=${cursor}`:''}`);assert.equal(next.status,200);
      for(const row of next.body.feedback){assert.ok(!seen.has(row.id));seen.add(row.id);
        assert.deepEqual(Object.keys(row).sort(),['id','unitId','category','summary','status','version','createdAt','updatedAt'].sort());}
      cursor=next.body.nextCursor;
    }while(cursor);
    assert.equal(seen.size,total);assert.ok(seen.has(rows[0].id)&&seen.has(rows[2].id));assert.ok(!seen.has(rows[1].id));
    assert.equal((await list(reviewer,`?cursor=${rows[1].id}`)).status,404);
    for(const query of ['?limit=0','?limit=101','?limit=2.2','?limit[]=1','?status=invalid','?ownerUserId='+owner.id,'?cursor=bad'])assert.equal((await list(reviewer,query)).status,400);
    await pool.query("insert into plan_item(owner_user_id,kind,title,notes) values($1,'task','Synthetic private','PRIVATE-NOTE-REVIEW-SENTINEL')",[owner.id]);
    await pool.query("insert into wellbeing_checkin(owner_user_id,mood,note) values($1,3,'PRIVATE-HEALTH-REVIEW-SENTINEL')",[owner.id]);
    const chat=(await pool.query("insert into ai_guide_session(owner_user_id,guide_kind) values($1,'study') returning id",[owner.id])).rows[0].id;
    await pool.query("insert into ai_guide_message(session_id,author,body) values($1,'user','PRIVATE-CHAT-REVIEW-SENTINEL')",[chat]);
    const visible=JSON.stringify((await list(reviewer)).body);
    for(const text of [owner.id,`content-review-${owner.id}@example.test`,'PRIVATE-NOTE-REVIEW-SENTINEL','PRIVATE-HEALTH-REVIEW-SENTINEL','PRIVATE-CHAT-REVIEW-SENTINEL']){
      assert.ok(!visible.includes(text));assert.ok(!output.includes(text));assert.ok(!errors.includes(text));}
  });

  test('CAS transitions, durable exact retry, concurrent duplicate, current-state replay and textless audit',async()=>{
    const owner=await actor(),reviewer=await actor();await grant(reviewer);
    const row=await feedback(owner),mutationId=uuid();
    const concurrent=await Promise.all(Array.from({length:4},()=>review(reviewer,row,'triaged',mutationId)));
    assert.ok(concurrent.every(result=>result.status===200));
    assert.equal(concurrent.filter(result=>result.body.acknowledgement.status==='accepted').length,1);
    assert.equal((await pool.query('select count(*)::int n from content_review_mutation where actor_user_id=$1 and mutation_id=$2',[reviewer.id,mutationId])).rows[0].n,1);
    const next=concurrent[0].body.feedback;
    assert.equal(next.version,2);assert.equal((await review(reviewer,row,'declined')).status,409);
    assert.equal((await review(reviewer,row,'declined',mutationId)).body.error,'mutation_id_reused');
    const plannedRow=(await review(reviewer,next,'planned')).body.feedback;
    await stop();await start();
    const replay=await review(reviewer,row,'triaged',mutationId);assert.equal(replay.status,200);
    assert.equal(replay.body.feedback.version,3);assert.equal(replay.body.feedback.status,'planned');
    assert.equal(replay.body.acknowledgement.status,'already_applied');
    assert.equal((await review(reviewer,plannedRow,'released')).status,400);
    const audit=(await pool.query('select * from content_review_audit where feedback_id=$1 order by occurred_at',[row.id])).rows;
    assert.equal(audit.length,2);assert.equal(audit[0].before_status,'received');assert.equal(audit[1].after_status,'planned');
    assert.ok(!JSON.stringify(audit).includes(privateMarker));
    assert.equal((await withdraw(owner,row)).status,204);
    const withdrawnRetry=await review(reviewer,row,'triaged',mutationId);assert.equal(withdrawnRetry.status,404);
    assert.ok(!JSON.stringify(withdrawnRetry).includes(privateMarker));
  });

  test('allowed transition matrix prevents release and concurrent competing versions update once',async()=>{
    const owner=await actor(),a=await actor(),b=await actor();await grant(a);await grant(b);
    const row=await feedback(owner);
    assert.equal((await review(a,row,'planned')).body.error,'feedback_transition_invalid');
    const results=await Promise.all([review(a,row,'triaged'),review(b,row,'declined')]);
    assert.deepEqual(results.map(result=>result.status).sort(),[200,409]);
    let current=results.find(result=>result.status===200).body.feedback;
    if(current.status==='declined')current=(await review(a,current,'triaged')).body.feedback;
    current=(await review(a,current,'planned')).body.feedback;
    current=(await review(a,current,'triaged')).body.feedback;
    current=(await review(a,current,'declined')).body.feedback;
    assert.equal((await review(a,current,'planned')).status,409);
    current=(await review(a,current,'triaged')).body.feedback;assert.equal(current.status,'triaged');
  });

  test('briefs contain only structural public context, persist/replay once, never chosen or private text',async()=>{
    const owner=await actor(),reviewer=await actor();await grant(reviewer);
    const unit=(await pool.query('select id from learning_unit order by id limit 1')).rows[0].id;
    const rows=[await planned(reviewer,await feedback(owner,{unitId:unit,summary:privateMarker})),
      await planned(reviewer,await feedback(owner,{category:'unclear',summary:'SYNTHETIC-SECOND-PRIVATE-SUMMARY'}))];
    const mutationId=uuid();
    const results=await Promise.all([prepare(reviewer,rows,mutationId),prepare(reviewer,[...rows].reverse(),mutationId)]);
    assert.deepEqual(results.map(result=>result.status).sort(),[200,201]);
    const brief=results[0].body.brief;assert.equal(brief.sourceCount,2);assert.equal(brief.units.length,1);
    assert.equal(brief.units[0].id,unit);assert.equal(brief.tasks.length,4);
    const serialized=JSON.stringify(brief);
    for(const privateText of [privateMarker,'SYNTHETIC-SECOND-PRIVATE-SUMMARY',owner.id,reviewer.id,...rows.map(row=>row.id)])assert.ok(!serialized.includes(privateText));
    assert.equal((await pool.query('select count(*)::int n from content_review_brief where actor_user_id=$1',[reviewer.id])).rows[0].n,1);
    await stop();await start();
    const replay=await prepare(reviewer,rows,mutationId);assert.equal(replay.status,200);assert.deepEqual(replay.body.brief,brief);
    assert.equal(replay.body.acknowledgement.status,'already_applied');
    assert.deepEqual((await request(`/v1/content-review/briefs/${brief.id}`,{user:reviewer})).body.brief,brief);
    assert.equal((await prepare(reviewer,[rows[0]],mutationId)).body.error,'mutation_id_reused');
  });

  test('brief preconditions and source withdrawal/review changes invalidate every GET and replay',async()=>{
    const owner=await actor(),reviewer=await actor();await grant(reviewer);
    const raw=await feedback(owner);
    assert.equal((await prepare(reviewer,[raw])).body.error,'brief_source_conflict');
    const row=await planned(reviewer,raw),mutationId=uuid();
    const created=await prepare(reviewer,[row],mutationId);assert.equal(created.status,201);
    const id=created.body.brief.id;
    const changed=await review(reviewer,row,'triaged');assert.equal(changed.status,200);
    for(const response of [await request(`/v1/content-review/briefs/${id}`,{user:reviewer}),await prepare(reviewer,[row],mutationId)]){
      assert.equal(response.status,409);assert.equal(response.body.error,'brief_invalidated');assert.ok(!JSON.stringify(response).includes(privateMarker));}
    const row2=await planned(reviewer,await feedback(owner)),mutation2=uuid();
    const created2=await prepare(reviewer,[row2],mutation2);assert.equal(created2.status,201);
    await withdraw(owner,row2);
    assert.equal((await request(`/v1/content-review/briefs/${created2.body.brief.id}`,{user:reviewer})).status,409);
    assert.equal((await prepare(reviewer,[row2],mutation2)).status,409);
    const db=(await pool.query('select summary,share_with_content_team from learning_content_feedback where id=$1',[row2.id])).rows[0];
    assert.equal(db.summary,null);assert.equal(db.share_with_content_team,false);
    await revoke(reviewer,'brief.prepare');
    assert.equal((await request(`/v1/content-review/briefs/${id}`,{user:reviewer})).status,403);
    assert.equal((await prepare(reviewer,[row],mutationId)).status,403);
  });

  test('source deletion invalidates a multiple-source brief instead of silently returning a partial old result',async()=>{
    const owner1=await actor(),owner2=await actor(),reviewer=await actor();await grant(reviewer);
    const row1=await planned(reviewer,await feedback(owner1)),row2=await planned(reviewer,await feedback(owner2));
    const created=await prepare(reviewer,[row1,row2]);assert.equal(created.status,201);
    await pool.query('delete from app_user where id=$1',[owner1.id]);
    assert.equal((await request(`/v1/content-review/briefs/${created.body.brief.id}`,{user:reviewer})).body.error,'brief_invalidated');
  });

  test('withdrawal wins races: blocked review retry and brief read cannot reveal an old consenting summary',async()=>{
    const owner=await actor(),reviewer=await actor();await grant(reviewer);
    const row=await planned(reviewer,await feedback(owner)),created=await prepare(reviewer,[row]);
    const blocker=await pool.connect();
    try{
      await blocker.query('begin');
      await blocker.query('select id from learning_content_feedback where id=$1 for update',[row.id]);
      const pending=request(`/v1/content-review/briefs/${created.body.brief.id}`,{user:reviewer});
      await blockedOn(blocker);
      await blocker.query(`update learning_content_feedback set summary=null,share_with_content_team=false,
        withdrawn_at=now(),updated_at=now(),version=version+1 where id=$1`,[row.id]);
      await blocker.query('commit');
      const response=await pending;assert.equal(response.status,409);assert.ok(!JSON.stringify(response).includes(privateMarker));
    }finally{await blocker.query('rollback').catch(()=>{});blocker.release();}
    assert.equal((await review(reviewer,row,'triaged')).status,404);
  });

  test('permission expiry while source-lock blocked rolls back a pending review write and audit',async()=>{
    const owner=await actor(),reviewer=await actor();await grant(reviewer,['feedback.read','feedback.review'],3000);
    const row=await feedback(owner),blocker=await pool.connect();
    try{
      await blocker.query('begin');await blocker.query('select id from learning_content_feedback where id=$1 for update',[row.id]);
      const pending=review(reviewer,row,'triaged');
      await blockedOn(blocker);
      // Separate operator simulation for expiry. No grant mutation is done by the API.
      await pool.query("update content_capability_grant set expires_at=statement_timestamp()+interval '150 milliseconds' where user_id=$1",[reviewer.id]);
      await new Promise(resolve=>setTimeout(resolve,220));await blocker.query('commit');
      assert.equal((await pending).status,403);
      assert.equal((await pool.query('select status,version from learning_content_feedback where id=$1',[row.id])).rows[0].status,'received');
      assert.equal((await pool.query('select count(*)::int n from content_review_audit where feedback_id=$1',[row.id])).rows[0].n,0);
    }finally{await blocker.query('rollback').catch(()=>{});blocker.release();}
  });

  test('direct concurrent capability revocation during a blocked write is rechecked before commit',async()=>{
    const owner=await actor(),reviewer=await actor();await grant(reviewer);
    const row=await feedback(owner),blocker=await pool.connect();
    try{
      await blocker.query('begin');await blocker.query('select id from learning_content_feedback where id=$1 for update',[row.id]);
      const pending=review(reviewer,row,'triaged');await blockedOn(blocker);
      await pool.query("update content_capability_grant set revoked_at=statement_timestamp() where user_id=$1 and permission='feedback.review'",[reviewer.id]);
      await blocker.query('commit');assert.equal((await pending).status,403);
      assert.equal((await pool.query('select version from learning_content_feedback where id=$1',[row.id])).rows[0].version,1);
      assert.equal((await pool.query('select count(*)::int n from content_review_mutation where actor_user_id=$1',[reviewer.id])).rows[0].n,0);
    }finally{await blocker.query('rollback').catch(()=>{});blocker.release();}
  });

  test('JWT expiry while waiting for a source row rolls back review and receipt',async()=>{
    const owner=await actor(),reviewer=await actor({},'2s');await grant(reviewer);
    const row=await feedback(owner),blocker=await pool.connect();
    try{
      await blocker.query('begin');await blocker.query('select id from learning_content_feedback where id=$1 for update',[row.id]);
      const pending=review(reviewer,row,'triaged');await blockedOn(blocker);
      const expiry=jwt.decode(reviewer.token).exp*1000;
      while(Date.now()<=expiry)await new Promise(resolve=>setTimeout(resolve,25));
      await blocker.query('commit');assert.equal((await pending).status,401);
      assert.equal((await pool.query('select version from learning_content_feedback where id=$1',[row.id])).rows[0].version,1);
      assert.equal((await pool.query('select count(*)::int n from content_review_mutation where actor_user_id=$1',[reviewer.id])).rows[0].n,0);
    }finally{await blocker.query('rollback').catch(()=>{});blocker.release();}
  });
});
