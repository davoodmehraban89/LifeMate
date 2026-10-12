import express from 'express';
import crypto from 'node:crypto';
import { createSessionAuth } from './session_auth.js';
import { validUuid } from './plan_mutations.js';
import { validSchoolYear } from './learning_catalog.js';
export function validTrackCode(grade,track){return grade<10?track==='common':['math','experimental','humanities'].includes(track);}
function officialUnitCitation(value){try{const u=new URL(value);return ['http:','https:'].includes(u.protocol)&&['chap.sch.ir','www.chap.sch.ir','medu.gov.ir','www.medu.gov.ir'].includes(u.hostname)&&!u.username&&!u.password?value:null;}catch{return null;}}
// Review approval belongs to a particular verified book edition and unit.
// Catalogue corrections can happen independently of a video-row update, so
// the publication trigger alone cannot establish eligibility at read time.
// Counts and resources share this predicate to avoid advertising stale media.
const published=`v.publication_status='published' and v.free_access is true
 and v.pedagogical_review='full_reviewed'
 and v.verification_status in ('metadata_verified','embed_verified')
 and t.edition_verification='verified' and s.school_year<>'unknown'
 and v.review_record->>'materialHash'=v.material_hash
 and v.review_record->>'bookCode'=t.book_code
 and v.review_record->>'schoolYear'=s.school_year
 and v.review_record->>'unitKey'=u.unit_key
 and v.review_record->>'bookEvidenceUrl'=t.source_evidence_url
 and v.review_record->>'unitEvidenceUrl'=u.source_evidence_url`;
const courseSelect=`select t.id,t.title_fa,s.national_grade,t.track_codes,s.school_year,t.book_code,t.variant,t.edition_verification,t.alignment_notes_fa,t.sequence_verification,t.source_evidence_url,
 (select count(*)::int from learning_unit u where u.textbook_id=t.id and u.active) unit_count,
 (select count(*)::int from learning_unit u where u.textbook_id=t.id and u.active and exists(select 1 from learning_video_resource v where v.unit_id=u.id and ${published})) video_unit_count,
 (select count(*)::int from learning_video_resource v join learning_unit u on u.id=v.unit_id where u.textbook_id=t.id and u.active and v.publication_status='draft') review_candidate_count
 from textbook_catalog t join curriculum_subject s on s.id=t.curriculum_subject_id`;
function course(row){return {id:row.id,titleFa:row.title_fa,grade:row.national_grade,trackCodes:row.track_codes,schoolYear:row.school_year==='unknown'?null:row.school_year,bookCode:row.book_code,variant:row.variant,editionVerification:row.edition_verification,alignmentNotesFa:row.alignment_notes_fa,sequenceVerification:row.sequence_verification,sourceEvidenceUrl:row.source_evidence_url,unitCount:row.unit_count,videoUnitCount:row.video_unit_count,reviewCandidateCount:row.review_candidate_count,coverage:{unitCount:row.unit_count,publishedVideoUnitCount:row.video_unit_count,unavailableUnitCount:row.unit_count-row.video_unit_count}};}
function progress(row){return {id:row.unit_id,unitId:row.unit_id,status:row.status,source:row.source,version:Number(row.version),updatedAt:row.updated_at};}
class LearningError extends Error{constructor(status,code,details={}){super(code);this.status=status;this.code=code;this.details=details;}}
const fail=(status,code,details)=>{throw new LearningError(status,code,details);};
export function createLearningLibraryRouter({pool,auth}){
 const router=express.Router(),requireAuth=auth??createSessionAuth({pool,jwtSecret:process.env.JWT_SECRET});
 router.get('/education/library',requireAuth,async(req,res)=>{
  const row=(await pool.query('select national_grade,track_code,school_year from education_profile where user_id=$1',[req.identity.sub])).rows[0];
  const education=row?{nationalGrade:row.national_grade,trackCode:row.track_code,schoolYear:row.school_year}:null;
  for(const key of ['grade','trackCode','schoolYear'])if(req.query[key]!==undefined&&typeof req.query[key]!=='string')return res.status(400).json({error:'invalid_'+key});
  const explicitGrade=req.query.grade!==undefined;
  if(explicitGrade&&!/^(?:[1-9]|1[0-2])$/.test(req.query.grade))return res.status(400).json({error:'invalid_grade'});
  const grade=explicitGrade?Number(req.query.grade):row?.national_grade;
  if(req.query.trackCode!==undefined&&!['common','math','experimental','humanities'].includes(req.query.trackCode))return res.status(400).json({error:'invalid_track'});
  if(req.query.schoolYear!==undefined&&!validSchoolYear(req.query.schoolYear))return res.status(400).json({error:'invalid_school_year'});
  if(!grade)return res.json({education,courses:[],fetchedAt:new Date().toISOString()});
  const track=req.query.trackCode??(grade<10?'common':grade===row?.national_grade?row.track_code:null);
  if(track==null&&!explicitGrade)return res.json({education,courses:[],fetchedAt:new Date().toISOString()});
  if(!validTrackCode(grade,track))return res.status(400).json({error:'invalid_track'});
  const year=req.query.schoolYear??row?.school_year??null;
  if(year!==null&&!validSchoolYear(year))return res.status(400).json({error:'invalid_school_year'});
  const r=await pool.query(courseSelect+` where t.stable_book_key is not null and s.national_grade=$1 and $2=any(t.track_codes) and ($3::text is null or s.school_year=$3 or s.school_year='unknown') order by s.name_fa,t.book_code,t.variant,s.school_year`,[grade,track,year]);
  res.json({education,courses:r.rows.map(course),fetchedAt:new Date().toISOString()});
 });
 router.get('/education/courses/:id',requireAuth,async(req,res)=>{
  if(!validUuid(req.params.id))return res.status(400).json({error:'invalid_course_id'});
  const r=await pool.query(courseSelect+' where t.id=$1 and t.stable_book_key is not null',[req.params.id]);if(!r.rowCount)return res.status(404).json({error:'not_found'});
  const units=(await pool.query(`select u.*,p.status,p.source,p.version,p.updated_at,(select count(*)::int from learning_video_resource v where v.unit_id=u.id and v.publication_status='draft') review_candidate_count from learning_unit u left join learning_progress p on p.unit_id=u.id and p.owner_user_id=$2 where u.textbook_id=$1 and u.active order by u.order_index,u.unit_key`,[req.params.id,req.identity.sub])).rows;
  const videos=(await pool.query(`select v.* from learning_video_resource v join learning_unit u on u.id=v.unit_id join textbook_catalog t on t.id=u.textbook_id join curriculum_subject s on s.id=t.curriculum_subject_id where u.textbook_id=$1 and u.active and ${published} order by v.title_fa,v.aparat_id`,[req.params.id])).rows;
  const mapped=units.map(u=>{const resources=videos.filter(v=>v.unit_id===u.id).map(v=>({aparatId:v.canonical_aparat_id??v.aparat_id,titleFa:v.title_fa,creatorName:v.creator_name,creatorUrl:v.creator_url,sourceEvidenceUrl:v.source_evidence_url,verificationStatus:v.verification_status,pedagogicalReview:v.pedagogical_review,freeAccess:v.free_access,durationSeconds:v.duration_seconds,checkedAt:v.checked_at,qualityNotesFa:v.quality_notes_fa}));return {id:u.id,titleFa:u.title_fa,orderIndex:u.order_index,indexKind:u.index_kind,unitKey:u.unit_key,sourceEvidenceUrl:officialUnitCitation(u.source_evidence_url),videos:resources,reviewCandidateCount:u.review_candidate_count,availability:resources.length?'available':'unavailable',progress:u.version==null?null:progress({...u,unit_id:u.id})};});
  res.json({...course(r.rows[0]),units:mapped,fetchedAt:new Date().toISOString()});
 });
 // Catalogue navigation only. This locator deliberately excludes learner
 // progress, attempt history, resource candidates and other account fields.
 router.get('/education/units/:unitId',requireAuth,async(req,res)=>{
  if(!validUuid(req.params.unitId))return res.status(400).json({error:'invalid_unit_id'});
  const result=await pool.query(`select u.id,u.title_fa,u.textbook_id from learning_unit u
   join textbook_catalog t on t.id=u.textbook_id join curriculum_subject s on s.id=t.curriculum_subject_id
   where u.id=$1 and u.active and t.stable_book_key is not null`,[req.params.unitId]);
  if(!result.rowCount)return res.status(404).json({error:'unit_not_found'});
  const unit=result.rows[0];
  res.json({unit:{id:unit.id,titleFa:unit.title_fa,courseId:unit.textbook_id},fetchedAt:new Date().toISOString()});
 });
 router.get('/me/learning-progress',requireAuth,async(req,res)=>{const r=await pool.query('select * from learning_progress where owner_user_id=$1 order by updated_at,unit_id',[req.identity.sub]);res.json({progress:r.rows.map(progress),fetchedAt:new Date().toISOString()});});
 router.put('/me/learning-progress/:unitId',requireAuth,async(req,res)=>{
  const body=req.body,allowed=['status','source','mutationId','expectedVersion'];
  if(!validUuid(req.params.unitId)||!body||typeof body!=='object'||Array.isArray(body)||Object.keys(body).some(k=>!allowed.includes(k))||!['not_started','in_progress','completed'].includes(body.status)||body.source!=='self_reported'||!validUuid(body.mutationId)||!Number.isSafeInteger(body.expectedVersion)||body.expectedVersion<0)return res.status(400).json({error:'invalid_learning_progress'});
  const owner=req.identity.sub,unit=req.params.unitId;
  const hash=crypto.createHash('sha256').update(JSON.stringify({unitId:unit,status:body.status,source:body.source,expectedVersion:body.expectedVersion})).digest('hex');
  const c=await pool.connect();try{
   await c.query('begin');await c.query('select pg_advisory_xact_lock(hashtextextended($1::text,0))',['learning-progress:'+owner]);
   if(!(await c.query('select 1 from app_user where id=$1 and disabled_at is null for share',[owner])).rowCount)fail(401,'unauthorized');
   if(!(await c.query('select 1 from learning_unit where id=$1 and active',[unit])).rowCount)fail(404,'unit_not_found');
   const previous=(await c.query('select request_hash,acknowledgement from learning_progress_mutation where owner_user_id=$1 and mutation_id=$2',[owner,body.mutationId])).rows[0];
   if(previous){if(previous.request_hash!==hash)fail(409,'mutation_id_reused');await c.query('commit');return res.json(previous.acknowledgement);}
   const current=(await c.query('select version from learning_progress where owner_user_id=$1 and unit_id=$2 for update',[owner,unit])).rows[0],version=Number(current?.version??0);
   if(version!==body.expectedVersion)fail(409,'version_conflict',{serverVersion:version});
   const updated=(await c.query(`insert into learning_progress(owner_user_id,unit_id,status,source,version) values($1,$2,$3,'self_reported',1) on conflict(owner_user_id,unit_id) do update set status=excluded.status,version=learning_progress.version+1,updated_at=now() returning *`,[owner,unit,body.status])).rows[0];
   const ack={mutationId:body.mutationId,...progress(updated),acceptedAt:updated.updated_at};
   await c.query('insert into learning_progress_mutation(owner_user_id,mutation_id,unit_id,request_hash,acknowledgement) values($1,$2,$3,$4,$5::jsonb)',[owner,body.mutationId,unit,hash,JSON.stringify(ack)]);await c.query('commit');res.json(ack);
  }catch(e){await c.query('rollback').catch(()=>{});if(e instanceof LearningError)return res.status(e.status).json({error:e.code,...e.details});throw e;}finally{c.release();}
 });return router;
}
