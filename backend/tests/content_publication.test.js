// Only public synthetic teaching fixtures; no real video is fetched or approved.
import test,{before,after} from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import pg from 'pg';
import {spawnSync} from 'node:child_process';
import {assessmentHash,assessmentContextHash} from '../src/learning_assessment.js';
import {inspectLearningContent,reviewLearningContent,videoMaterialHash,videoContextHash} from '../src/content_publication.js';

assert.ok(process.env.DATABASE_URL,'Use local synthetic PostgreSQL fixture credentials');
const source=new URL(process.env.TEST_FIXTURE_DATABASE_URL??process.env.DATABASE_URL);
assert.ok(['localhost','127.0.0.1','[::1]'].includes(source.hostname)&&(/test/.test(source.pathname)||source.pathname==='/lifemate_ci'),'Refuse nonlocal/nontest fixture');
const database='lifeguide_publication_test_'+crypto.randomBytes(6).toString('hex');
const admin=new pg.Client({connectionString:source.toString()});
const target=new URL(source);target.pathname='/'+database;
const env={CONTENT_REVIEW_DATABASE_URL:target.toString(),CONTENT_REVIEW_SYNTHETIC_ONLY:'true'};
const client=new pg.Client({connectionString:target.toString()});
const testRoles=['api','backup'].map(kind=>'lifeguide_publication_'+kind+'_test_'+crypto.randomBytes(6).toString('hex'));
const createdRoles=[];let databaseCreated=false,clientConnected=false;
before(async()=>{
  await admin.connect();await admin.query(`create database "${database}"`);databaseCreated=true;
  await client.connect();clientConnected=true;
  // CI runs this before DB-role provisioning. Unique NOLOGIN fixture roles
  // avoid any mutation of shared runtime/backup roles or their credentials.
  for(const role of testRoles) {
    await admin.query(`create role "${role}" nologin`);createdRoles.push(role);
  }
  // Stable foundation only. Do not migrate concurrently changing0016–0019 here.
  const names=(await fs.readdir(new URL('../migrations/',import.meta.url))).filter(name=>/^00(?:0\d|1[0-5])_/.test(name)).sort();
  for(const filename of [...names,'0020_content_publication_audit.sql']) {
    const sql=await fs.readFile(new URL('../migrations/'+filename,import.meta.url),'utf8');await client.query(sql);
  }
});
after(async()=>{
  if(clientConnected) await client.end();
  try {
    if(databaseCreated) await admin.query(`drop database "${database}"`);
    for(const role of createdRoles) await admin.query(`drop role "${role}"`);
  } finally {await admin.end();}
});
const q=[{id:'q1',objectiveId:'counting',promptFa:'SYNTHETIC counting prompt',choices:[{id:'a',textFa:'۲'},{id:'b',textFa:'۳'}],correctChoiceId:'a',explanationFa:'SYNTHETIC explanation',remediationFa:'SYNTHETIC remediation'}];
async function fixture() {
  const subject=crypto.randomUUID(),book=crypto.randomUUID(),unit=crypto.randomUUID(),video=crypto.randomUUID();
  await client.query("insert into curriculum_subject(id,school_year,national_grade,code,name_fa) values($1,'1405-1406',1,$2,'SYNTHETIC publication subject')",[subject,'synthetic-publication-'+subject]);
  await client.query("insert into textbook_catalog(id,curriculum_subject_id,title_fa,source_url,book_code,stable_book_key,edition_verification,source_evidence_url) values($1,$2,'SYNTHETIC publication textbook','https://chap.sch.ir/','999999',$3,'verified','https://chap.sch.ir/synthetic')",[book,subject,'synthetic-publication:'+book]);
  await client.query("insert into learning_unit(id,textbook_id,unit_key,title_fa,order_index,index_kind,source_evidence_url) values($1,$2,'synthetic-counting','SYNTHETIC counting unit',1,'lesson','https://chap.sch.ir/synthetic-unit')",[unit,book]);
  await client.query("insert into learning_video_resource(id,unit_id,aparat_id,title_fa,creator_name,creator_url,source_evidence_url,verification_status,duration_seconds,free_access,checked_at,quality_notes_fa,material_hash) values($1,$2,'SyN12','SYNTHETIC unobserved video','SYNTHETIC teacher','https://www.aparat.com/synthetic_teacher','https://www.aparat.com/v/SyN12','metadata_verified',60,true,'2026-10-01T00:00:00Z','SYNTHETIC only',$3)",[video,unit,'0'.repeat(64)]);
  const row=(await client.query(`select v.*,u.unit_key,u.title_fa unit_title_fa,u.order_index,u.index_kind,u.source_evidence_url unit_evidence_url,u.active,
    t.stable_book_key,t.title_fa book_title_fa,t.book_code,t.track_codes,t.variant,t.edition_verification,t.source_evidence_url book_evidence_url,s.school_year,s.national_grade
    from learning_video_resource v join learning_unit u on u.id=v.unit_id join textbook_catalog t on t.id=u.textbook_id join curriculum_subject s on s.id=t.curriculum_subject_id where v.id=$1`,[video])).rows[0];
  row.material_hash=videoMaterialHash(row);await client.query('update learning_video_resource set material_hash=$2 where id=$1',[video,row.material_hash]);
  return {subject,book,unit,video,row};
}
const videoReview=row=>({evidenceScope:'SYNTHETIC_TEST_ONLY',reviewerName:'SYNTHETIC TEST REVIEWER — not real approval',reviewedAt:'2026-10-01T00:00:00Z',
  bookCode:row.book_code,schoolYear:row.school_year,unitKey:row.unit_key,bookEvidenceUrl:row.book_evidence_url,unitEvidenceUrl:row.unit_evidence_url,
  materialHash:row.material_hash,watchedEntireVideo:true,editionAligned:true,accuracyApproved:true,suitabilityApproved:true,embedRightsApproved:true,
  questionCoverageReviewed:true,alignmentNotes:'SYNTHETIC alignment',accuracyNotes:'SYNTHETIC accuracy',suitabilityNotes:'SYNTHETIC suitability',
  embedRightsEvidence:'SYNTHETIC rights',questionCoverageNotes:'SYNTHETIC questions'});
const publishVideo=f=>({schemaVersion:1,mutationId:crypto.randomUUID(),entityType:'video',entityId:f.video,operation:'publish',expectedStatus:'draft',
  expectedContentHash:f.row.material_hash,expectedContextHash:videoContextHash(f.row),review:videoReview(f.row)});

test('inspection and complete synthetic dry-run perform zero persistent mutations',async()=>{
  const f=await fixture(),body=publishVideo(f);
  const inspected=await inspectLearningContent(client,'video',f.video,{env});assert.equal(inspected.publicationStatus,'draft');
  assert.equal(inspected.contentHash,f.row.material_hash);
  const before=(await client.query('select publication_status,pedagogical_review,review_record from learning_video_resource where id=$1',[f.video])).rows[0];
  const result=await reviewLearningContent(client,body,{env});assert.equal(result.mode,'dry-run');assert.equal(result.proposedStatus,'published');
  assert.deepEqual((await client.query('select publication_status,pedagogical_review,review_record from learning_video_resource where id=$1',[f.video])).rows[0],before);
  assert.equal((await client.query('select count(*)::int n from content_publication_audit')).rows[0].n,0);
});

test('full review, metadata, edition and current context gates reject missing or stale approval without writes',async()=>{
  const f=await fixture(),body=publishVideo(f);
  for(const field of ['watchedEntireVideo','editionAligned','accuracyApproved','suitabilityApproved','embedRightsApproved','questionCoverageReviewed']) {
    await assert.rejects(reviewLearningContent(client,{...body,review:{...body.review,[field]:false}},{env,apply:true}),e=>e.code==='incomplete_video_review');
  }
  await assert.rejects(reviewLearningContent(client,{...body,review:{...body.review,reviewedAt:'2026-02-30T00:00:00Z'}},{env,apply:true}));
  await assert.rejects(reviewLearningContent(client,{...body,expectedContentHash:'a'.repeat(64)},{env,apply:true}),e=>e.code==='content_conflict');
  await client.query("update textbook_catalog set edition_verification='unverified' where id=$1",[f.book]);
  await assert.rejects(reviewLearningContent(client,body,{env,apply:true}),e=>e.code==='context_conflict'||e.code==='verified_edition_required');
  await client.query("update textbook_catalog set edition_verification='verified' where id=$1",[f.book]);
  await client.query("update learning_video_resource set title_fa='SYNTHETIC changed without refreshed hash' where id=$1",[f.video]);
  await assert.rejects(reviewLearningContent(client,body,{env,apply:true}),e=>e.code==='material_hash_mismatch');
  assert.equal((await client.query('select count(*)::int n from content_publication_audit where entity_id=$1',[f.video])).rows[0].n,0);
});

test('stable publication receipt replays current withdrawn state, and changed UUID intent is rejected',async()=>{
  const f=await fixture(),body=publishVideo(f);
  const applied=await reviewLearningContent(client,body,{env,apply:true});assert.equal(applied.acknowledgement.status,'accepted');assert.equal(applied.current.publicationStatus,'published');
  const retry=await reviewLearningContent(client,body,{env,apply:true});assert.equal(retry.acknowledgement.status,'already_applied');
  await assert.rejects(reviewLearningContent(client,{...body,review:{...body.review,accuracyNotes:'Changed intent'}},{env,apply:true}),e=>e.code==='mutation_id_reused');
  const withdrawal={...body,mutationId:crypto.randomUUID(),operation:'withdraw',expectedStatus:'published'};delete withdrawal.review;
  assert.equal((await reviewLearningContent(client,withdrawal,{env,apply:true})).current.publicationStatus,'withdrawn');
  assert.equal((await reviewLearningContent(client,body,{env,apply:true})).current.publicationStatus,'withdrawn');
  assert.equal((await client.query('select count(*)::int n from content_publication_audit where entity_id=$1',[f.video])).rows[0].n,2);
  const columns=(await client.query("select column_name from information_schema.columns where table_name='content_publication_audit'")).rows.map(row=>row.column_name);
  for(const forbidden of ['summary','review_record','questions','note','feedback_id','owner_user_id','chat']) assert.ok(!columns.includes(forbidden));
});

test('synthetic apply cannot publish real catalogue records or pretend a human reviewed them',async()=>{
  const f=await fixture(),body=publishVideo(f);
  await assert.rejects(reviewLearningContent(client,{...body,review:{...body.review,evidenceScope:'HUMAN_REVIEW',reviewerName:'Real reviewer'}},{env,apply:true}),e=>e.code==='synthetic_receipt_required');
  await client.query("update textbook_catalog set stable_book_key=$2 where id=$1",[f.book,'IR-1-105-1405-1406-standard']);
  await assert.rejects(reviewLearningContent(client,body,{env,apply:true}),e=>e.code==='synthetic_material_required');
  assert.equal((await client.query('select publication_status from learning_video_resource where id=$1',[f.video])).rows[0].publication_status,'draft');
});

test('original assessment drafts are versioned, published definitions immutable, and old learner snapshots retained on revision',async()=>{
  const f=await fixture(),id=crypto.randomUUID();
  const draft={schemaVersion:1,mutationId:crypto.randomUUID(),entityType:'assessment',entityId:id,unitId:f.unit,operation:'draft_assessment',
    expectedStatus:'absent',expectedVersion:0,expectedContentHash:null,expectedContextHash:assessmentContextHash(f.row),questions:q};
  assert.equal((await reviewLearningContent(client,draft,{env})).mode,'dry-run');
  assert.equal((await client.query('select count(*)::int n from learning_assessment where id=$1',[id])).rows[0].n,0);
  const created=await reviewLearningContent(client,draft,{env,apply:true});assert.equal(created.current.version,1);assert.equal(created.current.contentHash,assessmentHash(q));
  assert.equal((await reviewLearningContent(client,draft,{env,apply:true})).acknowledgement.status,'already_applied');
  const review={evidenceScope:'SYNTHETIC_TEST_ONLY',reviewerName:'SYNTHETIC TEST REVIEWER',reviewedAt:'2026-10-01T00:00:00Z',accuracyApproved:true,suitabilityApproved:true,
    editionAligned:true,objectiveCoverageApproved:true,contentHash:assessmentHash(q),contextHash:assessmentContextHash(f.row),reviewNotes:'SYNTHETIC question approval',
    bookCode:f.row.book_code,schoolYear:f.row.school_year,unitKey:f.row.unit_key};
  const publish={schemaVersion:1,mutationId:crypto.randomUUID(),entityType:'assessment',entityId:id,operation:'publish',expectedStatus:'draft',expectedVersion:1,
    expectedContentHash:assessmentHash(q),expectedContextHash:assessmentContextHash(f.row),review};
  assert.equal((await reviewLearningContent(client,publish,{env,apply:true})).current.publicationStatus,'published');
  const owner=crypto.randomUUID();await client.query('insert into app_user(id,identity_subject,email_normalized) values($1,$2,$3)',[owner,'synthetic-publication:'+owner,'publication-'+owner+'@example.test']);
  await client.query("insert into learning_assessment_attempt(owner_user_id,mutation_id,assessment_id,unit_id,assessment_version,request_hash,answers,confidence,question_snapshot,acknowledgement) values($1,$2,$3,$4,1,$5,'[]','unsure',$6,'{}')",
    [owner,crypto.randomUUID(),id,f.unit,'a'.repeat(64),JSON.stringify(q)]);
  const revised=[{...q[0],promptFa:'SYNTHETIC revised original question'}];
  const revision={...draft,mutationId:crypto.randomUUID(),expectedStatus:'published',expectedVersion:1,expectedContentHash:assessmentHash(q),questions:revised};
  await assert.rejects(reviewLearningContent(client,revision,{env,apply:true}),e=>e.code==='published_definition_immutable');
  const withdrawal={...publish,mutationId:crypto.randomUUID(),operation:'withdraw',expectedStatus:'published'};delete withdrawal.review;
  await reviewLearningContent(client,withdrawal,{env,apply:true});
  const next=await reviewLearningContent(client,{...revision,mutationId:crypto.randomUUID(),expectedStatus:'withdrawn'},{env,apply:true});
  assert.equal(next.current.version,2);assert.equal(next.current.publicationStatus,'draft');assert.equal(next.current.contentHash,assessmentHash(revised));
  const stored=(await client.query('select questions,review_record from learning_assessment where id=$1',[id])).rows[0];assert.deepEqual(stored.questions,revised);assert.equal(stored.review_record,null);
  assert.deepEqual((await client.query('select question_snapshot from learning_assessment_attempt where assessment_id=$1',[id])).rows[0].question_snapshot,q);
  assert.equal((await reviewLearningContent(client,publish,{env,apply:true})).current.publicationStatus,'draft');
});

test('isolated runtime/backup permission fixtures cannot write teaching definitions or publication audit with SELECT-only grants',async()=>{
  const f=await fixture(),body=publishVideo(f);
  for(const role of testRoles) {
    await client.query(`grant connect on database "${database}" to "${role}"`);
    await client.query(`grant usage on schema public to "${role}"`);
    await client.query(`grant select on all tables in schema public to "${role}"`);
    await client.query(`set role "${role}"`);
    try {
      await assert.rejects(reviewLearningContent(client,body,{env,apply:true}),e=>e.code==='separate_operator_required');
      await assert.rejects(client.query('update learning_video_resource set publication_status=publication_status where id=$1',[f.video]),e=>e.code==='42501');
      await assert.rejects(client.query('delete from content_publication_audit'),e=>e.code==='42501');
    } finally {await client.query('reset role');}
  }
});

test('actual CLI inspection prints structural synthetic output, refuses remote env and hides driver secrets',async()=>{
  const f=await fixture();
  const inspected=spawnSync(process.execPath,['scripts/review-learning-content.js','inspect','video',f.video],{env:{...process.env,...env},encoding:'utf8'});
  assert.equal(inspected.status,0,inspected.stderr);assert.equal(JSON.parse(inspected.stdout).publicationStatus,'draft');
  const rejected=spawnSync(process.execPath,['scripts/review-learning-content.js','inspect','video',f.video],{env:{...process.env,...env,CONTENT_REVIEW_DATABASE_URL:'postgres://SECRET_PASSWORD@remote.example/lifeguide_test'},encoding:'utf8'});
  assert.equal(rejected.status,1);assert.ok(!rejected.stderr.includes('SECRET_PASSWORD'));assert.equal(rejected.stdout,'');
});

test('actual CLI dry-run, apply, replay and withdrawal retain exactly two receipts without printing reviewer text',async()=>{
  const f=await fixture(),body=publishVideo(f),directory=await fs.mkdtemp(path.join(os.tmpdir(),'lifeguide-publication-'));
  const filename=path.join(directory,'operation.json');
  const run=action=>spawnSync(process.execPath,['scripts/review-learning-content.js',action,filename],{env:{...process.env,...env},encoding:'utf8'});
  try {
    await fs.writeFile(filename,JSON.stringify(body),{mode:0o600});
    let result=run('dry-run');assert.equal(result.status,0,result.stderr);assert.equal(JSON.parse(result.stdout).mode,'dry-run');
    assert.equal((await client.query('select count(*)::int n from content_publication_audit where entity_id=$1',[f.video])).rows[0].n,0);
    result=run('apply');assert.equal(result.status,0,result.stderr);assert.equal(JSON.parse(result.stdout).current.eligibleForLearners,true);
    assert.equal(JSON.parse(result.stdout).acknowledgement.status,'accepted');assert.ok(!result.stdout.includes(body.review.reviewerName));
    result=run('apply');assert.equal(result.status,0,result.stderr);assert.equal(JSON.parse(result.stdout).acknowledgement.status,'already_applied');
    const withdrawal={...body,mutationId:crypto.randomUUID(),operation:'withdraw',expectedStatus:'published'};delete withdrawal.review;
    await fs.writeFile(filename,JSON.stringify(withdrawal));
    result=run('apply');assert.equal(result.status,0,result.stderr);assert.equal(JSON.parse(result.stdout).current.eligibleForLearners,false);
    assert.equal((await client.query('select count(*)::int n from content_publication_audit where entity_id=$1',[f.video])).rows[0].n,2);
    await fs.writeFile(filename,' '.repeat(1024*1024+1));
    result=run('apply');assert.equal(result.status,1);assert.equal(JSON.parse(result.stderr).code,'invalid_operation_file');
    assert.equal(result.stdout,'');
  } finally {await fs.rm(directory,{recursive:true});}
});

test('concurrent exact publication retries serialize and produce one journal receipt',async()=>{
  const f=await fixture(),body=publishVideo(f),other=new pg.Client({connectionString:target.toString()});
  await other.connect();
  try {
    const results=await Promise.all([reviewLearningContent(client,body,{env,apply:true}),reviewLearningContent(other,body,{env,apply:true})]);
    assert.deepEqual(results.map(result=>result.acknowledgement.status).sort(),['accepted','already_applied']);
    assert.equal((await client.query('select count(*)::int n from content_publication_audit where mutation_id=$1',[body.mutationId])).rows[0].n,1);
    assert.equal((await client.query('select publication_status from learning_video_resource where id=$1',[f.video])).rows[0].publication_status,'published');
  } finally {await other.end();}
});

test('a catalogue correction committed while review waits invalidates its original approval context',async()=>{
  const f=await fixture(),body=publishVideo(f),blocker=new pg.Client({connectionString:target.toString()});
  await blocker.connect();
  try {
    const pid=(await client.query('select pg_backend_pid() pid')).rows[0].pid;
    await blocker.query('begin');
    await blocker.query("update learning_unit set title_fa='SYNTHETIC corrected during review' where id=$1",[f.unit]);
    const pending=reviewLearningContent(client,body,{env,apply:true});
    const rejected=assert.rejects(pending,error=>error.code==='context_conflict');
    const deadline=Date.now()+3000;let observed=false;
    while(Date.now()<deadline) {
      if((await blocker.query('select cardinality(pg_blocking_pids($1))>0 blocked',[pid])).rows[0].blocked) {observed=true;break;}
      await new Promise(resolve=>setTimeout(resolve,10));
    }
    await blocker.query('commit');await rejected;assert.equal(observed,true,'Observe the actual row-lock wait');
    assert.equal((await client.query('select count(*)::int n from content_publication_audit where mutation_id=$1',[body.mutationId])).rows[0].n,0);
    assert.equal((await client.query('select publication_status from learning_video_resource where id=$1',[f.video])).rows[0].publication_status,'draft');
  } finally {await blocker.query('rollback').catch(()=>{});await blocker.end();}
});
