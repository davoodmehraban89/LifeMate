// Synthetic question banks/reviewer receipts only. No real school content is
// approved by this test, and no provider video is fetched or played.
import test,{before,after} from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {spawn} from 'node:child_process';
import {once} from 'node:events';
import net from 'node:net';
import pg from 'pg';
import jwt from 'jsonwebtoken';
import {assessmentHash,assessmentContextHash} from '../src/learning_assessment.js';

assert.ok(process.env.DATABASE_URL&&process.env.JWT_SECRET?.length>=32,'Use a migrated local synthetic PostgreSQL');
const pool=new pg.Pool({connectionString:process.env.TEST_FIXTURE_DATABASE_URL??process.env.DATABASE_URL});
const serviceEnv={...process.env};delete serviceEnv.TEST_FIXTURE_DATABASE_URL;
const users=[],books=[],subjects=[],units=[],assessments=[];
let child,base;
async function start(){
 const reservation=net.createServer().listen(0,'127.0.0.1');await once(reservation,'listening');const port=reservation.address().port;
 await new Promise(resolve=>reservation.close(resolve));base=`http://127.0.0.1:${port}`;
 child=spawn(process.execPath,['src/entrypoint.js'],{env:{...serviceEnv,NODE_ENV:'production',PORT:String(port),SMS_PROVIDER:'disabled',SMS_PROVIDER_URL:'',SMS_PROVIDER_TOKEN:'',EMAIL_FROM:'',RESEND_API_KEY:'',SMTP_HOST:'',ENABLE_SENSITIVE_FEATURES:'false',CORS_ORIGINS:'',RATE_LIMIT_AUTH_MAX:'2000',RATE_LIMIT_GENERAL_MAX:'4000'},stdio:['ignore','pipe','pipe']});
 let output='';await new Promise((resolve,reject)=>{const timer=setTimeout(()=>reject(new Error('Synthetic assessment startup timeout')),10000);child.stdout.on('data',chunk=>{output+=chunk.toString();if(output.includes('"type":"startup"')){clearTimeout(timer);resolve();}});child.once('error',e=>{clearTimeout(timer);reject(e);});child.stderr.on('data',()=>{});});
}
async function stop(){if(child&&child.exitCode===null&&child.signalCode===null){const done=once(child,'close');child.kill('SIGTERM');await done;}}
before(start);
after(async()=>{await stop();try{
 await pool.query('delete from learning_review_schedule where owner_user_id=any($1::uuid[])',[users]);
 await pool.query('delete from learning_assessment_attempt where owner_user_id=any($1::uuid[])',[users]);
 await pool.query('delete from learning_assessment where id=any($1::uuid[])',[assessments]);
 await pool.query('delete from learning_unit where id=any($1::uuid[])',[units]);
 await pool.query('delete from textbook_catalog where id=any($1::uuid[])',[books]);
 await pool.query('delete from curriculum_subject where id=any($1::uuid[])',[subjects]);
 await pool.query('delete from app_user where id=any($1::uuid[])',[users]);
}finally{await pool.end();}});
async function user(){const id=crypto.randomUUID(),sid=crypto.randomUUID();users.push(id);
 await pool.query('insert into app_user(id,identity_subject,email_normalized,email_verified_at) values($1,$2,$3,now())',[id,'assessment-fixture:'+id,'assessment-'+id+'@example.test']);
 await pool.query("insert into profile(user_id,display_name) values($1,'Synthetic Assessment Learner')",[id]);
 await pool.query("insert into auth_session(id,user_id,refresh_digest,expires_at) values($1,$2,$3,now()+interval '1 day')",[sid,id,crypto.randomBytes(32).toString('hex')]);
 return{id,token:jwt.sign({sub:id,sid,aud:'lifemate-api'},process.env.JWT_SECRET,{issuer:'lifemate',expiresIn:'15m'})};}
async function request(path,{method='GET',actor,body}={}){const r=await fetch(base+path,{method,headers:{'content-type':'application/json',...(actor?{authorization:'Bearer '+actor.token}:{})},body:body===undefined?undefined:JSON.stringify(body)});return {status:r.status,body:await r.json()};}
const questions=[{id:'q1',objectiveId:'counting',promptFa:'پرسش ساختگی: چند مهره داریم؟',choices:[{id:'a',textFa:'۲'},{id:'b',textFa:'۳'}],correctChoiceId:'a',explanationFa:'دو مهره را یکی‌یکی می‌شماریم.',remediationFa:'با دو مهره مستقل دوباره تمرین کن.'}];
async function fixture(){
 const actor=await user(),parent=await user();const subject=crypto.randomUUID(),book=crypto.randomUUID(),unit=crypto.randomUUID(),assessment=crypto.randomUUID();
 subjects.push(subject);books.push(book);units.push(unit);assessments.push(assessment);
 await pool.query("insert into curriculum_subject(id,school_year,national_grade,code,name_fa) values($1,'1405-1406',1,$2,'Synthetic reviewed book')",[subject,'synthetic-assessment-'+subject]);
 await pool.query("insert into textbook_catalog(id,curriculum_subject_id,title_fa,source_url,book_code,stable_book_key,edition_verification,source_evidence_url) values($1,$2,'Synthetic Assessment Textbook','https://chap.sch.ir/','999999',$3,'verified','http://www.chap.sch.ir/school-books')",[book,subject,'synthetic-assessment:'+book]);
 await pool.query("insert into learning_unit(id,textbook_id,unit_key,title_fa,order_index,index_kind,source_evidence_url) values($1,$2,'lesson-01','Synthetic counting objective',1,'lesson','http://www.chap.sch.ir/school-books')",[unit,book]);
 const context=(await pool.query('select t.book_code,s.school_year,t.source_evidence_url book_evidence_url,u.unit_key,u.title_fa unit_title_fa,u.source_evidence_url unit_evidence_url from learning_unit u join textbook_catalog t on t.id=u.textbook_id join curriculum_subject s on s.id=t.curriculum_subject_id where u.id=$1',[unit])).rows[0];
 await pool.query('insert into learning_assessment(id,unit_id,questions,content_hash,context_hash) values($1,$2,$3,$4,$5)',[assessment,unit,JSON.stringify(questions),assessmentHash(questions),assessmentContextHash(context)]);
 return{actor,parent,unit,assessment,context};
}
async function publishSynthetic(f){const review={reviewerName:'SYNTHETIC TEST REVIEWER — not real content approval',reviewedAt:'2026-10-01T00:00:00Z',accuracyApproved:true,suitabilityApproved:true,editionAligned:true,objectiveCoverageApproved:true,contentHash:assessmentHash(questions),contextHash:assessmentContextHash(f.context),reviewNotes:'Synthetic test evidence only',bookCode:f.context.book_code,schoolYear:f.context.school_year,unitKey:f.context.unit_key};
 await pool.query("update learning_assessment set publication_status='published',review_record=$2 where id=$1",[f.assessment,JSON.stringify(review)]);
}
const answerBody=f=>({mutationId:crypto.randomUUID(),assessmentId:f.assessment,assessmentVersion:1,answers:[{questionId:'q1',choiceId:'b'}],confidence:'unsure'});

test('draft publication gate hides questions; published synthetic questions exclude answer keys and remediation',async()=>{
 const f=await fixture(),path=`/v1/education/units/${f.unit}/assessment`;
 assert.equal((await request(path)).status,401);
 const draft=await request(path,{actor:f.actor});assert.equal(draft.body.assessment,null);
 await assert.rejects(pool.query("update learning_assessment set publication_status='published' where id=$1",[f.assessment]),e=>e.code==='23514');
 await publishSynthetic(f);const actual=await request(path,{actor:f.actor});assert.equal(actual.status,200);assert.equal(actual.body.assessment.questions.length,1);
 const raw=JSON.stringify(actual.body);for(const privateKey of ['correctChoiceId','explanationFa','remediationFa','review_record'])assert.equal(raw.includes(privateKey),false);
});
test('real graded attempt, independent SQL, idempotent retry, restart and owner-private review persist',async()=>{
 const f=await fixture();await publishSynthetic(f);const body=answerBody(f);
 const submitted=await request('/v1/me/learning-attempts',{method:'POST',actor:f.actor,body});assert.equal(submitted.status,201);assert.equal(submitted.body.correctCount,0);assert.equal(submitted.body.total,1);assert.equal(submitted.body.resultLabel,'needs_practice');assert.ok(submitted.body.feedback[0].explanationFa);assert.ok(submitted.body.feedback[0].remediationFa);
 const stored=(await pool.query('select assessment_version,confidence,answers,acknowledgement from learning_assessment_attempt where id=$1 and owner_user_id=$2',[submitted.body.attemptId,f.actor.id])).rows[0];assert.deepEqual(stored.answers,body.answers);assert.deepEqual(stored.acknowledgement,submitted.body);assert.equal(stored.confidence,'unsure');
 assert.deepEqual((await request('/v1/me/learning-attempts',{method:'POST',actor:f.actor,body})).body,submitted.body);
 assert.equal((await request('/v1/me/learning-attempts',{method:'POST',actor:f.actor,body:{...body,confidence:'confident'}})).status,409);
 await stop();await start();assert.deepEqual((await request('/v1/me/learning-attempts',{actor:f.actor})).body.attempts[0].attemptId,submitted.body.attemptId);
 const reviews=(await request('/v1/me/learning-reviews',{actor:f.actor})).body.reviews;assert.equal(reviews[0].unitId,f.unit);assert.equal(reviews[0].nextReviewAt,submitted.body.nextReviewAt);
 assert.deepEqual((await request(`/v1/me/learning-attempts?unitId=${f.unit}&ownerUserId=${f.actor.id}`,{actor:f.parent})).body.attempts,[]);
 assert.deepEqual((await request('/v1/me/learning-reviews',{actor:f.parent})).body.reviews,[]);
 assert.equal((await pool.query('select count(*)::int n from learning_assessment_attempt where owner_user_id=$1',[f.actor.id])).rows[0].n,1);
});
test('forged score, missing/duplicate answers, stale definition and unreviewed material cannot create attempts',async()=>{
 const f=await fixture();await publishSynthetic(f);
 for(const bad of [{...answerBody(f),score:100},{...answerBody(f),ownerUserId:f.parent.id},{...answerBody(f),answers:[]},{...answerBody(f),answers:[{questionId:'q1',choiceId:'unknown'}]}])assert.equal((await request('/v1/me/learning-attempts',{method:'POST',actor:f.actor,body:bad})).status,400);
 assert.equal((await request('/v1/me/learning-attempts',{method:'POST',actor:f.actor,body:{...answerBody(f),assessmentVersion:2}})).status,409);
 await pool.query("update learning_unit set title_fa='Changed objective needs review' where id=$1",[f.unit]);
 assert.equal((await request(`/v1/education/units/${f.unit}/assessment`,{actor:f.actor})).body.assessment,null);
 assert.equal((await request('/v1/me/learning-attempts',{method:'POST',actor:f.actor,body:answerBody(f)})).status,409);
 assert.equal((await pool.query('select count(*)::int n from learning_assessment_attempt where owner_user_id=$1',[f.actor.id])).rows[0].n,0);
});
test('concurrent attempts enforce owner quota while accepted replay remains idempotent',async()=>{
 const f=await fixture();await publishSynthetic(f);const bodies=Array.from({length:105},()=>answerBody(f));
 const responses=await Promise.all(bodies.map(body=>request('/v1/me/learning-attempts',{method:'POST',actor:f.actor,body})));
 assert.equal(responses.filter(r=>r.status===201).length,100);assert.equal(responses.filter(r=>r.status===429).length,5);
 const index=responses.findIndex(r=>r.status===201);
 assert.deepEqual((await request('/v1/me/learning-attempts',{method:'POST',actor:f.actor,body:bodies[index]})).body,responses[index].body);
 assert.equal((await request('/v1/me/learning-attempts',{method:'POST',actor:f.parent,body:answerBody(f)})).status,201);
 assert.equal((await pool.query('select count(*)::int n from learning_assessment_attempt where owner_user_id=$1',[f.actor.id])).rows[0].n,100);
});
