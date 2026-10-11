import test, { after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import pg from 'pg';
if (!process.env.DATABASE_URL) throw new Error('learning tests require synthetic PostgreSQL');
const pool = new pg.Pool({ connectionString: process.env.DATABASE_URL });
const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'lifeguide-catalog-'));
after(async () => { fs.rmSync(temp, { recursive: true, force: true }); await pool.end(); });
function dataset() { return { schemaVersion:1,sourcesReviewed:0,books:[{ bookCode:'599',grade:5,subjectCode:'math',titleFa:'کتاب آزمایشی مستقل',trackCodes:['common'],schoolYear:'1405-1406',sourceUrl:'http://www.chap.sch.ir/',sourceEvidenceUrl:'http://www.chap.sch.ir/',variant:'standard',editionVerification:'verified',sequenceVerification:'official_toc',alignmentNotesFa:'Synthetic fixture, no approved real teaching.',units:[{ unitKey:'lesson-01',titleFa:'درس آزمایشی',orderIndex:1,indexKind:'lesson',sourceEvidenceUrl:'http://www.chap.sch.ir/',videos:[{ aparatId:'Ab123',titleFa:'ویدیوی آزمایشی',creatorName:'Synthetic Teacher',creatorUrl:'https://www.aparat.com/synthetic_teacher',sourceEvidenceUrl:'https://www.aparat.com/v/Ab123',verificationStatus:'metadata_verified',pedagogicalReview:'unverified',durationSeconds:60,freeAccess:true,checkedAt:'2026-10-09T10:00:00Z',qualityNotesFa:'Synthetic metadata only.' }] }] }],providers:[],observations:[] }; }
function run(data) { const file=path.join(temp,'fixture.json');fs.writeFileSync(file,JSON.stringify(data));return spawnSync(process.execPath,['scripts/import-learning-catalog.js','--file',file],{cwd:new URL('../',import.meta.url),env:process.env,encoding:'utf8'}); }
test('offline importer keeps repeat IDs stable, HTTP evidence exact and metadata resources draft',async()=>{
 const data=dataset(),first=run(data);assert.equal(first.status,0,first.stderr);
 const read=async()=>(await pool.query("select t.id,t.source_evidence_url,u.id unit_id,v.id video_id,v.publication_status from textbook_catalog t join learning_unit u on u.textbook_id=t.id join learning_video_resource v on v.unit_id=u.id where t.book_code='599'")).rows;
 const rows=await read();assert.equal(rows.length,1);assert.equal(rows[0].source_evidence_url,'http://www.chap.sch.ir/');assert.equal(rows[0].publication_status,'draft');assert.equal(run(data).status,0);assert.deepEqual(await read(),rows);
});
test('invalid hashes and provider injection fail before catalogue mutation',async()=>{
 const before=(await pool.query('select count(*)::int n from textbook_catalog')).rows[0].n;
 for(const change of [v=>{v.aparatId='../bad?token=x';},v=>{v.creatorUrl='https://www.aparat.com.evil.test/teacher';}]){const data=dataset();data.books[0].bookCode='598';change(data.books[0].units[0].videos[0]);const result=run(data);assert.notEqual(result.status,0);assert.match(result.stderr,/invalid_catalog_(aparat_hash|video_source)/);}
 assert.equal((await pool.query('select count(*)::int n from textbook_catalog')).rows[0].n,before);
});
test('publication rejects incomplete pedagogical review despite free metadata',async()=>{await assert.rejects(pool.query("update learning_video_resource set publication_status='published',review_record='{}'::jsonb where aparat_id='Ab123'"),{code:'23514'});});
function fullReview(row){return {reviewerName:'Synthetic local reviewer',reviewedAt:'2026-10-09T10:00:00Z',bookCode:'599',schoolYear:'1405-1406',unitKey:'lesson-01',bookEvidenceUrl:'http://www.chap.sch.ir/',unitEvidenceUrl:'http://www.chap.sch.ir/',materialHash:row.material_hash,watchedEntireVideo:true,editionAligned:true,accuracyApproved:true,suitabilityApproved:true,embedRightsApproved:true,questionCoverageReviewed:true,alignmentNotes:'Synthetic alignment evidence',accuracyNotes:'Synthetic accuracy evidence',suitabilityNotes:'Synthetic age suitability',embedRightsEvidence:'Synthetic rights fixture, never a real permission',questionCoverageNotes:'Synthetic question coverage'};}
test('full review cannot publish null-free or mismatched material; unchanged import preserves review and changed content invalidates it',async()=>{
 const row=(await pool.query("select * from learning_video_resource where aparat_id='Ab123'")).rows[0];const record=fullReview(row);
 try{
  await assert.rejects(pool.query("update learning_video_resource set publication_status='published',pedagogical_review='full_reviewed',free_access=null,review_record=$2 where id=$1",[row.id,record]),{code:'23514'});
  for(const patch of [{watchedEntireVideo:false},{reviewerName:''},{schoolYear:'1404-1405'},{unitKey:'lesson-02'},{materialHash:'0'.repeat(64)},{reviewedAt:'2999-01-01T00:00:00Z'}])await assert.rejects(pool.query("update learning_video_resource set publication_status='published',pedagogical_review='full_reviewed',review_record=$2 where id=$1",[row.id,{...record,...patch}]),{code:'23514'});
  await pool.query("update learning_video_resource set publication_status='published',pedagogical_review='full_reviewed',review_record=$2 where id=$1",[row.id,record]);
  const same=dataset();same.books[0].units[0].videos[0].checkedAt='2026-10-09T10:01:00Z';assert.equal(run(same).status,0);
  assert.equal((await pool.query('select publication_status from learning_video_resource where id=$1',[row.id])).rows[0].publication_status,'published');
  same.books[0].units[0].titleFa='Changed unit teaching scope';assert.equal(run(same).status,0);
  const changed=(await pool.query('select publication_status,review_record from learning_video_resource where id=$1',[row.id])).rows[0];assert.equal(changed.publication_status,'draft');assert.equal(changed.review_record,null);
 }finally{run(dataset());}
});
