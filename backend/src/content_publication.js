// Operator-only local tooling. This module is never mounted on an HTTP router.
import crypto from 'node:crypto';
import {assessmentHash,assessmentContextHash,validateAssessmentDefinition} from './learning_assessment.js';

const uuid=value=>typeof value==='string'&&/^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$/i.test(value);
const hash=value=>typeof value==='string'&&/^[a-f0-9]{64}$/.test(value);
const exact=(value,fields)=>value&&typeof value==='object'&&!Array.isArray(value)&&Object.keys(value).every(field=>fields.includes(field));
const text=(value,max=12000)=>typeof value==='string'&&value.trim().length>0&&value.length<=max&&!value.includes('\u0000');
function canonical(value){if(Array.isArray(value))return value.map(canonical);if(value&&typeof value==='object')return Object.fromEntries(Object.keys(value).sort().map(key=>[key,canonical(value[key])]));return value;}
const digest=value=>crypto.createHash('sha256').update(JSON.stringify(canonical(value))).digest('hex');
export class ContentPublicationError extends Error {constructor(code){super(code);this.code=code;}}
const fail=code=>{throw new ContentPublicationError(code);};

export function localContentReviewConnection(env) {
  if(env.CONTENT_REVIEW_SYNTHETIC_ONLY!=='true'||!env.CONTENT_REVIEW_DATABASE_URL) fail('synthetic_configuration_required');
  let url;try{url=new URL(env.CONTENT_REVIEW_DATABASE_URL);}catch{fail('invalid_operator_configuration');}
  // pg connection-string query parameters can override host/database/user or
  // load TLS files. The checked URL is the only accepted connection source.
  if(url.search||url.hash||!['postgres:','postgresql:'].includes(url.protocol)||!['localhost','127.0.0.1','[::1]'].includes(url.hostname)||
    !/^\/(?:lifeguide_[a-z0-9_]*test(?:_[a-z0-9]+)*|lifemate_ci|lifeguide_roles_(?:source|target)_[a-f0-9]{16})$/.test(url.pathname)) fail('local_test_database_required');
  return url.toString();
}

const videoReviewFields=['evidenceScope','reviewerName','reviewedAt','bookCode','schoolYear','unitKey','bookEvidenceUrl','unitEvidenceUrl','materialHash',
  'watchedEntireVideo','editionAligned','accuracyApproved','suitabilityApproved','embedRightsApproved','questionCoverageReviewed',
  'alignmentNotes','accuracyNotes','suitabilityNotes','embedRightsEvidence','questionCoverageNotes'];
const assessmentReviewFields=['evidenceScope','reviewerName','reviewedAt','bookCode','schoolYear','unitKey','contentHash','contextHash',
  'accuracyApproved','suitabilityApproved','editionAligned','objectiveCoverageApproved','reviewNotes'];

export function normalizePublicationOperation(body) {
  const assessment=body?.entityType==='assessment',draft=body?.operation==='draft_assessment';
  const fields=['schemaVersion','mutationId','entityType','entityId','operation','expectedStatus','expectedContentHash','expectedContextHash',
    ...(assessment?['expectedVersion']:[]),...(draft?['unitId','questions']:[]),...(body?.operation==='publish'?['review']:[])];
  if(!exact(body,fields)||body.schemaVersion!==1||!uuid(body.mutationId)||!uuid(body.entityId)||!['video','assessment'].includes(body.entityType)||
    !['publish','withdraw','draft_assessment'].includes(body.operation)||(!assessment&&draft)||
    !['absent','draft','published','withdrawn'].includes(body.expectedStatus)||!hash(body.expectedContextHash)||
    (body.expectedStatus==='absent'?(!draft||body.expectedContentHash!==null):!hash(body.expectedContentHash))||
    (assessment&&(!Number.isSafeInteger(body.expectedVersion)||body.expectedVersion<0||body.expectedVersion>=2147483647||
      (body.expectedStatus==='absent'?body.expectedVersion!==0:body.expectedVersion===0)))) fail('invalid_publication_operation');
  if(draft) {
    if(!uuid(body.unitId)) fail('invalid_publication_operation');
    try {
      validateAssessmentDefinition(body.questions);
      for(const question of body.questions) {
        if(!exact(question,['id','objectiveId','promptFa','choices','correctChoiceId','explanationFa','remediationFa'])||
          question.choices.some(choice=>!exact(choice,['id','textFa']))) fail('invalid_assessment_definition');
      }
    } catch { fail('invalid_assessment_definition'); }
  }
  if(body.operation==='publish'&&!exact(body.review,assessment?assessmentReviewFields:videoReviewFields)) fail('invalid_review_record');
  return canonical({...body,mutationId:body.mutationId.toLowerCase(),entityId:body.entityId.toLowerCase(),...(draft?{unitId:body.unitId.toLowerCase()}:{} )});
}

// Same metadata fingerprint as the existing catalogue importer. This is not a
// cryptographic fingerprint of provider-hosted video bytes or proof of viewing.
export function videoMaterialHash(row) {
  return crypto.createHash('sha256').update(JSON.stringify({bookKey:row.stable_book_key,bookTitle:row.book_title_fa,
    editionVerification:row.edition_verification,bookEvidence:row.book_evidence_url,unitKey:row.unit_key,unitTitle:row.unit_title_fa,
    indexKind:row.index_kind,orderIndex:row.order_index,unitEvidence:row.unit_evidence_url,aparatId:row.aparat_id,
    canonicalAparatId:row.canonical_aparat_id??null,title:row.title_fa,creatorName:row.creator_name,creatorUrl:row.creator_url,
    sourceEvidence:row.source_evidence_url,verification:row.verification_status,durationSeconds:row.duration_seconds,
    freeAccess:row.free_access,qualityNotes:row.quality_notes_fa})).digest('hex');
}
export function videoContextHash(row) {
  return digest({bookKey:row.stable_book_key,bookTitle:row.book_title_fa,bookCode:row.book_code,schoolYear:row.school_year,
    bookEvidenceUrl:row.book_evidence_url,editionVerification:row.edition_verification,grade:row.national_grade,tracks:row.track_codes,
    variant:row.variant,unitKey:row.unit_key,titleFa:row.unit_title_fa,indexKind:row.index_kind,orderIndex:row.order_index,
    unitEvidenceUrl:row.unit_evidence_url,active:row.active});
}

async function operator(client,env,apply=false) {
  const url=new URL(localContentReviewConnection(env));
  const row=(await client.query(`select current_database() database,current_user role,
    has_table_privilege(current_user,'learning_video_resource','UPDATE') video_write,
    (has_table_privilege(current_user,'learning_assessment','INSERT') and
      has_table_privilege(current_user,'learning_assessment','UPDATE')) assessment_write,
    has_table_privilege(current_user,'content_publication_audit','INSERT') audit_write`)).rows[0];
  if(row.database!==decodeURIComponent(url.pathname.slice(1))) fail('operator_database_mismatch');
  if(['lifeguide_api','lifeguide_backup'].includes(row.role)||(apply&&(!row.video_write||!row.assessment_write||!row.audit_write))) fail('separate_operator_required');
  return row.role;
}
const contextSelect=`select u.id unit_id,u.unit_key,u.title_fa unit_title_fa,u.order_index,u.index_kind,u.source_evidence_url unit_evidence_url,u.active,
  t.id book_id,t.stable_book_key,t.title_fa book_title_fa,t.book_code,t.track_codes,t.variant,t.edition_verification,t.source_evidence_url book_evidence_url,
  s.school_year,s.national_grade from learning_unit u join textbook_catalog t on t.id=u.textbook_id join curriculum_subject s on s.id=t.curriculum_subject_id`;
async function load(client,type,id,{apply=false,unitId=null}={}) {
  const table=type==='video'?'learning_video_resource':'learning_assessment';
  const raw=(await client.query(`select * from ${table} where id=$1`,[id])).rows[0];
  if(raw&&unitId&&raw.unit_id!==unitId) fail('assessment_unit_immutable');
  const unit=raw?.unit_id??unitId;if(!unit) fail('material_not_found');
  const context=(await client.query(contextSelect+' where u.id=$1'+(apply?' for share of u,t,s':''),[unit])).rows[0];
  if(!context) fail('unit_not_found');
  // The import lock serializes importer and operator; row locks additionally
  // serialize direct catalogue corrections against approval snapshots.
  const locked=apply?(await client.query(`select * from ${table} where id=$1 for update`,[id])).rows[0]:raw;
  if(locked&&locked.unit_id!==unit) fail('assessment_unit_immutable');
  return {...context,...locked,id,exists:Boolean(locked)};
}
function current(row,type) {
  const contentHash=row.exists?(type==='video'?row.material_hash:row.content_hash):null;
  const computedContentHash=row.exists?(type==='video'?videoMaterialHash(row):assessmentHash(row.questions)):null;
  const contextHash=type==='video'?videoContextHash(row):assessmentContextHash(row);
  let eligible=false;
  try { if(row.publication_status==='published') { validateReview(row,type,row.review_record,false);eligible=contentHash===computedContentHash&&(type==='video'||row.context_hash===contextHash); } } catch {}
  return {entityType:type,entityId:row.id,unitId:row.unit_id,publicationStatus:row.exists?row.publication_status:'absent',
    version:type==='assessment'?(row.version??0):null,contentHash,computedContentHash,contextHash,
    contextVerified:row.active&&row.edition_verification==='verified'&&row.school_year!=='unknown',eligibleForLearners:eligible};
}
function reviewTimestamp(value) {
  if(typeof value!=='string'||!/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{3})?Z$/.test(value)) return false;
  const date=new Date(value);return Number.isFinite(date.getTime())&&date.toISOString().slice(0,19)===value.slice(0,19)&&date.getTime()<=Date.now();
}
function validateReview(row,type,review,synthetic) {
  if(!row.active||row.edition_verification!=='verified'||row.school_year==='unknown') fail('verified_edition_required');
  if(synthetic&&(review?.evidenceScope!=='SYNTHETIC_TEST_ONLY'||!review?.reviewerName?.startsWith('SYNTHETIC'))) fail('synthetic_receipt_required');
  if(!text(review?.reviewerName,240)||!reviewTimestamp(review?.reviewedAt)||review.bookCode!==row.book_code||
    review.schoolYear!==row.school_year||review.unitKey!==row.unit_key) fail('review_context_mismatch');
  if(type==='video') {
    const flags=['watchedEntireVideo','editionAligned','accuracyApproved','suitabilityApproved','embedRightsApproved','questionCoverageReviewed'];
    const notes=['alignmentNotes','accuracyNotes','suitabilityNotes','embedRightsEvidence','questionCoverageNotes'];
    if(flags.some(field=>review[field]!==true)||notes.some(field=>!text(review[field]))||row.free_access!==true||
      !['metadata_verified','embed_verified'].includes(row.verification_status)) fail('incomplete_video_review');
    if(review.materialHash!==row.material_hash||review.bookEvidenceUrl!==row.book_evidence_url||review.unitEvidenceUrl!==row.unit_evidence_url) fail('review_context_mismatch');
    if(videoMaterialHash(row)!==row.material_hash) fail('material_hash_mismatch');
  } else {
    if(['accuracyApproved','suitabilityApproved','editionAligned','objectiveCoverageApproved'].some(field=>review[field]!==true)||!text(review.reviewNotes)) fail('incomplete_assessment_review');
    validateAssessmentDefinition(row.questions);
    if(review.contentHash!==row.content_hash||review.contextHash!==row.context_hash||row.content_hash!==assessmentHash(row.questions)||
      row.context_hash!==assessmentContextHash(row)) fail('assessment_hash_mismatch');
  }
}

export async function inspectLearningContent(client,type,id,{env=process.env}={}) {
  if(!['video','assessment'].includes(type)||!uuid(id)) fail('invalid_inspection');
  await operator(client,env);
  await client.query('begin isolation level repeatable read read only');
  try {const state=current(await load(client,type,id),type);await client.query('rollback');return state;}
  catch(error){await client.query('rollback').catch(()=>{});throw error;}
}

export async function reviewLearningContent(client,raw,{env=process.env,apply=false}={}) {
  const body=normalizePublicationOperation(raw),requestHash=digest(body);
  const role=await operator(client,env,apply);
  await client.query(apply?'begin':'begin isolation level repeatable read read only');
  try {
    if(apply) await client.query("select pg_advisory_xact_lock(hashtextextended('learning_catalog_import',0))");
    const previous=(await client.query('select * from content_publication_audit where mutation_id=$1',[body.mutationId])).rows[0];
    if(previous&&previous.request_hash!==requestHash) fail('mutation_id_reused');
    let row=await load(client,body.entityType,body.entityId,{apply,unitId:body.unitId});
    if(apply&&!row.stable_book_key?.startsWith('synthetic-publication:')) fail('synthetic_material_required');
    if(previous) {
      const result={mode:apply?'synthetic-apply':'dry-run',current:current(row,body.entityType),acknowledgement:{mutationId:body.mutationId,
        entityId:body.entityId,status:'already_applied',appliedStatus:previous.applied_status,appliedVersion:previous.applied_version,acceptedAt:previous.accepted_at}};
      await client.query(apply?'commit':'rollback');return result;
    }
    const state=current(row,body.entityType);
    if(state.publicationStatus!==body.expectedStatus) fail('publication_status_conflict');
    if(state.contentHash!==body.expectedContentHash) fail('content_conflict');
    if(state.contextHash!==body.expectedContextHash) fail('context_conflict');
    if(body.entityType==='assessment'&&state.version!==body.expectedVersion) fail('assessment_version_conflict');
    if(body.operation==='draft_assessment') {
      if(row.publication_status==='published') fail('published_definition_immutable');
      if(!row.active) fail('unit_inactive');
      if(row.exists&&assessmentHash(body.questions)===row.content_hash&&assessmentContextHash(row)===row.context_hash) fail('definition_change_not_required');
    } else {
      if(!row.exists) fail('material_not_found');
      if(body.operation==='publish') {
        if(row.publication_status==='published') fail('publication_change_not_required');
        validateReview(row,body.entityType,body.review,apply);
      }
    }
    const proposedStatus=body.operation==='publish'?'published':body.operation==='withdraw'?'withdrawn':'draft';
    if(!apply) {await client.query('rollback');return {mode:'dry-run',current:state,proposedStatus,proposedVersion:body.operation==='draft_assessment'?body.expectedVersion+1:state.version};}
    if(body.operation==='draft_assessment') {
      const values=[body.entityId,row.unit_id,body.expectedVersion+1,JSON.stringify(body.questions),assessmentHash(body.questions),assessmentContextHash(row)];
      if(row.exists) await client.query("update learning_assessment set version=$3,questions=$4,content_hash=$5,context_hash=$6,publication_status='draft',review_record=null where id=$1 and unit_id=$2",values);
      else await client.query('insert into learning_assessment(id,unit_id,version,questions,content_hash,context_hash) values($1,$2,$3,$4,$5,$6)',values);
    } else {
      const table=body.entityType==='video'?'learning_video_resource':'learning_assessment';
      if(body.operation==='publish') await client.query(`update ${table} set publication_status='published',review_record=$2${body.entityType==='video'?",pedagogical_review='full_reviewed'":''} where id=$1`,[body.entityId,JSON.stringify(body.review)]);
      else await client.query(`update ${table} set publication_status='withdrawn' where id=$1`,[body.entityId]);
    }
    row=await load(client,body.entityType,body.entityId,{apply});
    const updated=current(row,body.entityType);
    const receipt=(await client.query(`insert into content_publication_audit(mutation_id,entity_type,entity_id,operation,request_hash,
      applied_content_hash,applied_context_hash,applied_version,applied_status,operator_role) values($1,$2,$3,$4,$5,$6,$7,$8,$9,$10) returning accepted_at`,
      [body.mutationId,body.entityType,body.entityId,body.operation,requestHash,updated.contentHash,updated.contextHash,updated.version,updated.publicationStatus,role])).rows[0];
    await client.query('commit');return {mode:'synthetic-apply',current:updated,acknowledgement:{mutationId:body.mutationId,entityId:body.entityId,
      status:'accepted',appliedStatus:updated.publicationStatus,appliedVersion:updated.version,acceptedAt:receipt.accepted_at}};
  } catch(error) {await client.query('rollback').catch(()=>{});throw error;}
}
