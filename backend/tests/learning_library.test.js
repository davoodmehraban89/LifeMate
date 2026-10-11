import test,{after} from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import net from 'node:net';
import {spawn} from 'node:child_process';
import pg from 'pg';
import jwt from 'jsonwebtoken';
import { importLearningCatalog } from '../src/learning_catalog.js';
if(!process.env.DATABASE_URL)throw new Error('learning tests require synthetic PostgreSQL');
// Optional migrator credentials belong exclusively to synthetic fixture setup.
// The real HTTP process retains DATABASE_URL's restricted runtime role.
const pool=new pg.Pool({connectionString:process.env.TEST_FIXTURE_DATABASE_URL??process.env.DATABASE_URL}),secret='synthetic-library-test-secret-at-least-32-characters';let child,base,log='';
async function start(){const n=net.createServer();await new Promise(r=>n.listen(0,'127.0.0.1',r));const port=n.address().port;await new Promise(r=>n.close(r));const serviceEnv={...process.env,PORT:String(port),JWT_SECRET:secret,NODE_ENV:'production',SMS_PROVIDER:'disabled',EMAIL_PROVIDER:'disabled',SMTP_HOST:'',SMTP_USER:'',SMTP_PASSWORD:'',RESEND_API_KEY:'',RATE_LIMIT_MAX:'1000'};delete serviceEnv.TEST_FIXTURE_DATABASE_URL;child=spawn(process.execPath,['src/entrypoint.js'],{cwd:new URL('../',import.meta.url),env:serviceEnv,stdio:['ignore','pipe','pipe']});child.stdout.on('data',b=>{log+=b;});child.stderr.on('data',b=>{log+=b;});base=`http://127.0.0.1:${port}`;for(let i=0;i<100;i++){try{if((await fetch(base+'/ready')).ok)return;}catch{}await new Promise(r=>setTimeout(r,25));}throw new Error('synthetic server start failed: '+log);}
async function stop(){if(child&&child.exitCode===null){const p=new Promise(r=>child.once('exit',r));child.kill('SIGTERM');await p;}}
after(async()=>{await stop();await pool.end();});
async function actor(){const id=crypto.randomUUID(),sid=crypto.randomUUID();await pool.query('insert into app_user(id,identity_subject,email_normalized,email_verified_at) values($1,$2,$3,now())',[id,`learning:${id}`,`${id}@example.test`]);await pool.query("insert into profile(user_id,display_name,theme_preference) values($1,'Synthetic Learning','adult_blue')",[id]);await pool.query("insert into auth_session(id,user_id,refresh_digest,expires_at) values($1,$2,$3,now()+interval '1 day')",[sid,id,crypto.randomUUID()]);return{id,token:jwt.sign({sub:id,sid,aud:'lifemate-api'},secret,{issuer:'lifemate',expiresIn:'15m'})};}
async function req(p,a,method='GET',body){const r=await fetch(base+p,{method,headers:{'content-type':'application/json',...(a?{authorization:`Bearer ${a.token}`}:{})},...(body===undefined?{}:{body:JSON.stringify(body)})});const t=await r.text();return{status:r.status,body:r.headers.get('content-type')?.includes('application/json')?JSON.parse(t):t};}
test('real entrypoint validates context and filters, hides drafts and retains owner-private progress across restart',async()=>{
 await start();const a=await actor(),b=await actor();
 await importLearningCatalog(pool,[{schemaVersion:1,sourcesReviewed:0,books:[{bookCode:'597',grade:5,subjectCode:'math',titleFa:'Synthetic HTTP fixture',trackCodes:['common'],schoolYear:'1405-1406',sourceUrl:'http://www.chap.sch.ir/',sourceEvidenceUrl:'http://www.chap.sch.ir/',variant:'standard',editionVerification:'verified',units:[{unitKey:'lesson-01',titleFa:'Synthetic HTTP lesson',orderIndex:1,indexKind:'lesson',sourceEvidenceUrl:'https://www.aparat.com/etc/api/video/videohash/Cd456',videos:[{aparatId:'Cd456',titleFa:'Synthetic draft',creatorName:'Synthetic Teacher',creatorUrl:'https://www.aparat.com/synthetic_teacher',sourceEvidenceUrl:'https://www.aparat.com/v/Cd456',verificationStatus:'metadata_verified',durationSeconds:60,freeAccess:true,checkedAt:'2026-10-09T10:00:00Z',qualityNotesFa:'No real reviewed teaching'}]}]}]}]);const empty=await req('/v1/education/library',a);assert.equal(empty.status,200);assert.equal(empty.body.education,null);assert.deepEqual(empty.body.courses,[]);assert.equal((await req('/v1/education/library')).status,401);
 for(const q of ['grade=13','grade=abc','grade=5.5','grade=5&trackCode=math','grade=11&trackCode=bogus','grade=5&schoolYear=1405-1408'])assert.equal((await req('/v1/education/library?'+q,a)).status,400,q);
 assert.equal((await req('/v1/me/education',a,'PUT',{nationalGrade:5,schoolYear:'1405-1406',trackCode:'common'})).status,200);
 const cat=await req('/v1/education/library',a);assert.equal(cat.body.education.nationalGrade,5);const course=cat.body.courses.find(x=>x.bookCode==='597');assert.ok(course);const detail=await req('/v1/education/courses/'+course.id,a);assert.equal(detail.status,200);assert.equal(detail.body.id,course.id);const u=detail.body.units[0];assert.equal(u.videos.length,0);assert.equal(u.reviewCandidateCount,1);assert.equal(u.availability,'unavailable');assert.ok(!JSON.stringify(detail.body).includes('Cd456'),'draft candidate hash must not escape through unit citation');assert.equal((await req('/v1/me/learning-progress?ownerUserId='+a.id+'&childId='+a.id,b)).body.progress.length,0);
 const resource=(await pool.query('select id,material_hash from learning_video_resource where unit_id=$1',[u.id])).rows[0];
 const review={reviewerName:'Synthetic local reviewer',reviewedAt:'2026-10-09T10:00:00Z',bookCode:'597',schoolYear:'1405-1406',unitKey:'lesson-01',bookEvidenceUrl:'http://www.chap.sch.ir/',unitEvidenceUrl:'https://www.aparat.com/etc/api/video/videohash/Cd456',materialHash:resource.material_hash,watchedEntireVideo:true,editionAligned:true,accuracyApproved:true,suitabilityApproved:true,embedRightsApproved:true,questionCoverageReviewed:true,alignmentNotes:'Synthetic alignment only',accuracyNotes:'Synthetic accuracy only',suitabilityNotes:'Synthetic suitability only',embedRightsEvidence:'Synthetic rights, no real teaching approval',questionCoverageNotes:'Synthetic question coverage only'};
 try {
  await pool.query("update learning_video_resource set publication_status='published',pedagogical_review='full_reviewed',review_record=$2 where id=$1",[resource.id,review]);
  const published=await req('/v1/education/courses/'+course.id,a);
  assert.equal(published.body.units[0].videos.length,1);
  assert.equal(published.body.units[0].videos[0].aparatId,'Cd456');
  assert.equal(published.body.videoUnitCount,1);
  const subject=(await pool.query('select curriculum_subject_id from textbook_catalog where id=$1',[course.id])).rows[0].curriculum_subject_id;
  // Synthetic operator corrections must invalidate publication at read time,
  // even when they did not go through the JSON catalogue importer.
  const corrections=[
   ['textbook_catalog','edition_verification',course.id,'unverified','verified'],
   ['textbook_catalog','book_code',course.id,'596','597'],
   ['textbook_catalog','source_evidence_url',course.id,'http://www.chap.sch.ir/corrected-book','http://www.chap.sch.ir/'],
   ['curriculum_subject','school_year',subject,'1404-1405','1405-1406'],
   ['learning_unit','unit_key',u.id,'lesson-02','lesson-01'],
   ['learning_unit','source_evidence_url',u.id,'http://www.chap.sch.ir/corrected-unit','https://www.aparat.com/etc/api/video/videohash/Cd456'],
  ];
  for(const [table,column,id,value,original] of corrections) {
   await pool.query(`update ${table} set ${column}=$2 where id=$1`,[id,value]);
   try {
    const changed=await req('/v1/education/courses/'+course.id,a);
    assert.equal(changed.body.units[0].videos.length,0,`${table}.${column}: stale reviewed video must be hidden`);
    assert.equal(changed.body.units[0].availability,'unavailable');
    assert.equal(changed.body.videoUnitCount,0);
    assert.equal(changed.body.coverage.publishedVideoUnitCount,0);
    assert.ok(!JSON.stringify(changed.body.units[0].videos).includes('Cd456'));
    const listing=await req('/v1/education/library?grade=5&trackCode=common',a);
    const listed=listing.body.courses.find(x=>x.id===course.id);
    if(listed) assert.equal(listed.videoUnitCount,0,`${table}.${column}: list count must use the same publication gate`);
   } finally {
    await pool.query(`update ${table} set ${column}=$2 where id=$1`,[id,original]);
   }
   assert.equal((await req('/v1/education/courses/'+course.id,a)).body.units[0].videos.length,1);
  }
  await pool.query("update learning_video_resource set publication_status='withdrawn' where id=$1",[resource.id]);
  assert.equal((await req('/v1/education/courses/'+course.id,a)).body.units[0].videos.length,0);
 } finally {
  await pool.query("update learning_video_resource set publication_status='draft',pedagogical_review='unverified',review_record=null where id=$1",[resource.id]);
 }
 const mutation={status:'in_progress',source:'self_reported',mutationId:crypto.randomUUID(),expectedVersion:0};assert.equal((await req('/v1/me/learning-progress/'+u.id,a,'PUT',{...mutation,ownerUserId:b.id})).status,400);const ack=await req('/v1/me/learning-progress/'+u.id,a,'PUT',mutation);assert.equal(ack.status,200);assert.equal(ack.body.version,1);assert.equal(ack.body.unitId,u.id);assert.equal((await req('/v1/me/learning-progress?ownerUserId='+a.id+'&childId='+a.id,b)).body.progress.length,0);const othersCourse=await req('/v1/education/courses/'+course.id,b);assert.equal(othersCourse.body.units[0].progress,null);assert.deepEqual((await req('/v1/me/learning-progress/'+u.id,a,'PUT',mutation)).body,ack.body);assert.equal((await req('/v1/me/learning-progress/'+u.id,a,'PUT',{...mutation,status:'completed'})).status,409);
 const concurrent=await Promise.all(['completed','not_started'].map(status=>req('/v1/me/learning-progress/'+u.id,a,'PUT',{...mutation,status,mutationId:crypto.randomUUID(),expectedVersion:1})));assert.deepEqual(concurrent.map(x=>x.status).sort(),[200,409]);assert.deepEqual((await req('/v1/me/learning-progress',b)).body.progress,[]);
 await stop();await start();const restored=await req('/v1/me/learning-progress',a);assert.equal(restored.body.progress.length,1);assert.equal(restored.body.progress[0].version,2);const db=(await pool.query('select owner_user_id,version from learning_progress where unit_id=$1 and owner_user_id=$2',[u.id,a.id])).rows[0];assert.equal(db.owner_user_id,a.id);assert.equal(Number(db.version),2);
 const plan=await req('/v1/plan-items',a,'POST',{title:'Synthetic lesson plan',learningUnitId:u.id});assert.equal(plan.status,201);assert.equal(plan.body.learning_unit_id,u.id);assert.equal((await req('/v1/plan-items',a,'POST',{title:'Invalid unit',learningUnitId:crypto.randomUUID()})).status,400);
 assert.equal((await req('/v1/me/education',a,'PUT',{nationalGrade:11,schoolYear:'1405-1406',trackCode:'humanities'})).status,200);assert.equal((await req('/v1/me/iran-profile',a)).body.track_code,'humanities');assert.equal((await req('/v1/me/education',a,'PUT',{nationalGrade:6,schoolYear:'1405-1406',trackCode:'common'})).status,200);assert.equal((await req('/v1/me/learning-progress',a)).body.progress.length,1);
});
