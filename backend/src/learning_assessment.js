import crypto from 'node:crypto';
import express from 'express';
import {createSessionAuth} from './session_auth.js';
import {validUuid} from './plan_mutations.js';

class AssessmentError extends Error {
 constructor(status,code){super(code);this.status=status;this.code=code;}
}
const fail=(status,code)=>{throw new AssessmentError(status,code);};
const text=(x,max=2000)=>typeof x==='string'&&x.trim().length>0&&x.length<=max&&!x.includes('\0');
const key=x=>typeof x==='string'&&/^[a-zA-Z0-9_-]{1,80}$/.test(x);
function canonical(x){if(Array.isArray(x))return x.map(canonical);if(x&&typeof x==='object')return Object.fromEntries(Object.keys(x).sort().map(k=>[k,canonical(x[k])]));return x;}
const digest=x=>crypto.createHash('sha256').update(JSON.stringify(canonical(x))).digest('hex');
export const assessmentHash=questions=>digest(questions);
export const assessmentContextHash=row=>digest({bookCode:row.book_code,schoolYear:row.school_year,
 bookEvidenceUrl:row.book_evidence_url,unitKey:row.unit_key,titleFa:row.unit_title_fa,unitEvidenceUrl:row.unit_evidence_url});
const assessmentSelect=`select a.*,t.book_code,t.edition_verification,s.school_year,t.source_evidence_url book_evidence_url,
 u.unit_key,u.title_fa unit_title_fa,u.source_evidence_url unit_evidence_url
 from learning_assessment a join learning_unit u on u.id=a.unit_id join textbook_catalog t on t.id=u.textbook_id
 join curriculum_subject s on s.id=t.curriculum_subject_id`;

export function validateAssessmentDefinition(questions){
 if(!Array.isArray(questions)||questions.length<1||questions.length>20)fail(400,'invalid_assessment_definition');
 const ids=new Set();
 for(const q of questions){
  if(!q||typeof q!=='object'||!key(q.id)||ids.has(q.id)||!key(q.objectiveId)||!text(q.promptFa)||!text(q.explanationFa)||!text(q.remediationFa)||!Array.isArray(q.choices)||q.choices.length<2||q.choices.length>6)fail(400,'invalid_assessment_definition');
  ids.add(q.id);const choices=new Set();
  for(const c of q.choices){if(!c||!key(c.id)||choices.has(c.id)||!text(c.textFa))fail(400,'invalid_assessment_definition');choices.add(c.id);}
  if(!choices.has(q.correctChoiceId))fail(400,'invalid_assessment_definition');
 }
 return questions;
}
export function gradeAssessment(questions,answers){
 validateAssessmentDefinition(questions);
 if(!Array.isArray(answers)||answers.length!==questions.length)fail(400,'invalid_answers');
 const map=new Map();
 for(const a of answers){if(!a||Object.keys(a).some(k=>!['questionId','choiceId'].includes(k))||!key(a.questionId)||!key(a.choiceId)||map.has(a.questionId))fail(400,'invalid_answers');map.set(a.questionId,a.choiceId);}
 const feedback=questions.map(q=>{
  const choice=map.get(q.id);
  if(!q.choices.some(c=>c.id===choice))fail(400,'invalid_answers');
  return {questionId:q.id,objectiveId:q.objectiveId,correct:choice===q.correctChoiceId,explanationFa:q.explanationFa,remediationFa:q.remediationFa};
 });
 const correctCount=feedback.filter(f=>f.correct).length;
 return {correctCount,total:questions.length,feedback,resultLabel:correctCount===questions.length?'answered_correctly':'needs_practice'};
}
function reviewed(row){
 try{validateAssessmentDefinition(row.questions);return row.publication_status==='published'
  &&row.edition_verification==='verified'&&row.school_year!=='unknown'
  &&row.content_hash===assessmentHash(row.questions)&&row.context_hash===assessmentContextHash(row);}catch{return false;}
}
export function createLearningAssessmentRouter({pool,auth}){
 const router=express.Router(),requireAuth=auth??createSessionAuth({pool,jwtSecret:process.env.JWT_SECRET});
 router.get('/education/units/:unitId/assessment',requireAuth,async(req,res)=>{
  if(!validUuid(req.params.unitId))return res.status(400).json({error:'invalid_unit_id'});
  const active=await pool.query('select 1 from learning_unit where id=$1 and active',[req.params.unitId]);
  if(!active.rowCount)return res.status(404).json({error:'not_found'});
  const row=(await pool.query(assessmentSelect+" where a.unit_id=$1 and a.publication_status='published' and u.active order by a.version desc,a.created_at desc,a.id limit 1",[req.params.unitId])).rows[0];
  if(!row||!reviewed(row))return res.json({assessment:null,reason:'review_pending'});
  const questions=row.questions.map(q=>({id:q.id,objectiveId:q.objectiveId,promptFa:q.promptFa,choices:q.choices.map(c=>({id:c.id,textFa:c.textFa}))}));
  res.json({assessment:{id:row.id,unitId:row.unit_id,version:row.version,questions}});
 });
 router.post('/me/learning-attempts',requireAuth,async(req,res)=>{
  const b=req.body,allowed=['mutationId','assessmentId','assessmentVersion','answers','confidence'];
  if(!b||typeof b!=='object'||Array.isArray(b)||Object.keys(b).some(k=>!allowed.includes(k))||!validUuid(b.mutationId)||!validUuid(b.assessmentId)||!Number.isSafeInteger(b.assessmentVersion)||b.assessmentVersion<1||!['unsure','somewhat','confident'].includes(b.confidence)||!Array.isArray(b.answers)||b.answers.length<1||b.answers.length>20)return res.status(400).json({error:'invalid_attempt'});
  const owner=req.identity.sub,requestHash=digest({assessmentId:b.assessmentId,assessmentVersion:b.assessmentVersion,answers:b.answers,confidence:b.confidence});
  const c=await pool.connect();try{
   await c.query('begin');await c.query('select pg_advisory_xact_lock(hashtextextended($1::text,0))',['learning-assessment:'+owner]);
   if(!(await c.query('select 1 from app_user where id=$1 and disabled_at is null for share',[owner])).rowCount)fail(401,'unauthorized');
   const prior=(await c.query('select request_hash,acknowledgement from learning_assessment_attempt where owner_user_id=$1 and mutation_id=$2',[owner,b.mutationId])).rows[0];
   if(prior){if(prior.request_hash!==requestHash)fail(409,'mutation_id_reused');await c.query('commit');return res.json(prior.acknowledgement);}
   // The runtime role can only read reviewed catalogue tables. This statement
   // reads one consistent definition/context; the accepted snapshot is retained
   // in the attempt even if a later curator revision withdraws this version.
   const a=(await c.query(assessmentSelect+" where a.id=$1 and u.active and a.publication_status='published'",[b.assessmentId])).rows[0];
   if(!a||!reviewed(a))fail(409,'assessment_not_available');
   if(a.version!==b.assessmentVersion)fail(409,'assessment_version_conflict');
   const graded=gradeAssessment(a.questions,b.answers);
   const recent=(await c.query("select count(*)::int n from learning_assessment_attempt where owner_user_id=$1 and created_at>now()-interval '1 hour'",[owner])).rows[0].n;
   if(recent>=100)fail(429,'assessment_rate_limited');
   const now=(await c.query('select now() at')).rows[0].at;
   const id=crypto.randomUUID(),nextReviewAt=new Date(now.getTime()+(graded.correctCount===graded.total?3:1)*86400000).toISOString();
   const ack={mutationId:b.mutationId,attemptId:id,unitId:a.unit_id,assessmentId:a.id,assessmentVersion:a.version,...graded,nextReviewAt,schedulePolicy:'pilot-1-or-3-days',source:'quiz_answers',acceptedAt:now.toISOString()};
   await c.query('insert into learning_assessment_attempt(id,owner_user_id,mutation_id,assessment_id,unit_id,assessment_version,request_hash,answers,confidence,question_snapshot,acknowledgement) values($1,$2,$3,$4,$5,$6,$7,$8::jsonb,$9,$10::jsonb,$11::jsonb)',[id,owner,b.mutationId,a.id,a.unit_id,a.version,requestHash,JSON.stringify(b.answers),b.confidence,JSON.stringify(a.questions),JSON.stringify(ack)]);
   await c.query('insert into learning_review_schedule(owner_user_id,unit_id,last_attempt_id,next_review_at) values($1,$2,$3,$4) on conflict(owner_user_id,unit_id) do update set last_attempt_id=excluded.last_attempt_id,next_review_at=excluded.next_review_at',[owner,a.unit_id,id,nextReviewAt]);
   await c.query('commit');res.status(201).json(ack);
  }catch(e){await c.query('rollback').catch(()=>{});if(e instanceof AssessmentError)return res.status(e.status).json({error:e.code});throw e;}finally{c.release();}
 });
 router.get('/me/learning-attempts',requireAuth,async(req,res)=>{
  const unit=req.query.unitId??null;
  if(unit!==null&&!validUuid(unit))return res.status(400).json({error:'invalid_unit_id'});
  const r=await pool.query('select acknowledgement,confidence from learning_assessment_attempt where owner_user_id=$1 and ($2::uuid is null or unit_id=$2) order by created_at desc,id desc limit 100',[req.identity.sub,unit]);
  res.json({attempts:r.rows.map(row=>({...row.acknowledgement,confidence:row.confidence})),fetchedAt:new Date().toISOString()});
 });
 router.get('/me/learning-reviews',requireAuth,async(req,res)=>{
  const r=await pool.query('select unit_id,next_review_at,schedule_policy from learning_review_schedule where owner_user_id=$1 order by next_review_at,unit_id limit 100',[req.identity.sub]);
  res.json({reviews:r.rows.map(row=>({unitId:row.unit_id,nextReviewAt:row.next_review_at,schedulePolicy:row.schedule_policy})),fetchedAt:new Date().toISOString()});
 });
 return router;
}
