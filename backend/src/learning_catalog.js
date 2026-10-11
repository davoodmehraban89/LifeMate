import crypto from 'node:crypto';

const variants=new Set(['standard','experimental','religious_variant','gifted']);
const tracks=new Set(['common','math','experimental','humanities']);
export function validSchoolYear(value){if(typeof value!=='string'||!/^1[34]\d{2}-1[34]\d{2}$/.test(value))return false;const [a,b]=value.split('-').map(Number);return a>=1300&&a<=1499&&b===a+1;}
const text=(value,max=2000)=>typeof value==='string'&&value.trim().length>0&&value.length<=max;
function url(value){try{const u=new URL(value);return ['http:','https:'].includes(u.protocol)&&!u.username&&!u.password&&value.length<=3000;}catch{return false;}}
function official(value){try{const u=new URL(value);return url(value)&&['chap.sch.ir','www.chap.sch.ir','medu.gov.ir','www.medu.gov.ir'].includes(u.hostname);}catch{return false;}}
function creator(value){try{const u=new URL(value);return u.protocol==='https:'&&u.hostname==='www.aparat.com'&&!u.port&&!u.username&&!u.password&&!u.search&&!u.hash&&/^\/[A-Za-z0-9_.-]+$/.test(u.pathname);}catch{return false;}}
const hash=value=>typeof value==='string'&&/^[A-Za-z0-9]{5,64}$/.test(value);
function requireValue(ok,field){if(!ok)throw new Error(`invalid_catalog_${field}`);}
export function validateDataset(data){
 requireValue(data?.schemaVersion===1&&Array.isArray(data.books),'schema');
 const keys=new Set();let units=0,videos=0;
 for(const b of data.books){
  requireValue(Number.isInteger(b.grade)&&b.grade>=1&&b.grade<=12,'grade');requireValue(typeof b.bookCode==='string'&&/^\d{3,8}$/.test(b.bookCode),'book_code');requireValue(text(b.subjectCode,80)&&/^[a-z][a-z0-9_]*$/.test(b.subjectCode),'subject_code');requireValue(text(b.titleFa),'title');
  requireValue(Array.isArray(b.trackCodes)&&b.trackCodes.length>0&&b.trackCodes.every(t=>tracks.has(t))&&(b.grade<10?b.trackCodes.every(t=>t==='common'):b.trackCodes.every(t=>t!=='common')),'tracks');
  requireValue(b.schoolYear===null||validSchoolYear(b.schoolYear),'school_year');requireValue(official(b.sourceUrl)&&url(b.sourceEvidenceUrl),'source');requireValue(variants.has(b.variant),'variant');requireValue(['verified','unverified'].includes(b.editionVerification)&&!(b.editionVerification==='verified'&&b.schoolYear===null),'edition');requireValue(['official_toc','provider_index','unverified'].includes(b.sequenceVerification??'unverified'),'sequence');requireValue(Array.isArray(b.units),'units');
  const bookKey=stableBookKey(b);requireValue(!keys.has(bookKey),'duplicate_book');keys.add(bookKey);const unitKeys=new Set();
  for(const u of b.units){
   requireValue(typeof u.unitKey==='string'&&/^[a-z0-9][a-z0-9-]{0,79}$/.test(u.unitKey)&&!unitKeys.has(u.unitKey),'unit_key');unitKeys.add(u.unitKey);requireValue(text(u.titleFa)&&Number.isInteger(u.orderIndex)&&u.orderIndex>0&&['page','lesson','chapter'].includes(u.indexKind)&&url(u.sourceEvidenceUrl)&&Array.isArray(u.videos),'unit');units++;const ids=new Set();
   for(const v of u.videos){requireValue(hash(v.aparatId)&&!ids.has(v.aparatId)&&(!v.canonicalAparatId||hash(v.canonicalAparatId)),'aparat_hash');ids.add(v.aparatId);requireValue(text(v.titleFa)&&text(v.creatorName)&&creator(v.creatorUrl)&&url(v.sourceEvidenceUrl),'video_source');requireValue(['index_verified','metadata_verified','embed_verified'].includes(v.verificationStatus),'verification');requireValue(v.freeAccess===null||typeof v.freeAccess==='boolean','free_access');requireValue(v.durationSeconds===null||(Number.isInteger(v.durationSeconds)&&v.durationSeconds>0),'duration');requireValue(typeof v.checkedAt==='string'&&Number.isFinite(Date.parse(v.checkedAt))&&text(v.qualityNotesFa,12000),'video_evidence');videos++;}
  }
 }
 return {books:data.books.length,units,videos};
}
export function stableBookKey(book){return `IR-${book.grade}-${book.bookCode}-${book.schoolYear??'unknown'}-${book.variant}`;}
function stableUuid(key){const bytes=crypto.createHash('sha256').update('lifeguide-learning:'+key).digest().subarray(0,16);bytes[6]=(bytes[6]&15)|80;bytes[8]=(bytes[8]&63)|128;const h=bytes.toString('hex');return `${h.slice(0,8)}-${h.slice(8,12)}-${h.slice(12,16)}-${h.slice(16,20)}-${h.slice(20)}`;}
export async function importLearningCatalog(pool,datasets){
 const totals=datasets.map(validateDataset),all=new Set();for(const d of datasets)for(const b of d.books){const key=stableBookKey(b);requireValue(!all.has(key),'duplicate_book_across_files');all.add(key);}
 const c=await pool.connect();try{await c.query('begin');await c.query("select pg_advisory_xact_lock(hashtextextended('learning_catalog_import',0))");
 for(const d of datasets)for(const b of d.books){
  const key=stableBookKey(b),subjectId=stableUuid(key+':subject'),bookId=stableUuid(key+':book');
  await c.query(`insert into curriculum_subject(id,school_year,national_grade,code,subject_code,name_fa,sort_order) values($1,$2,$3,$4,$5,$6,0) on conflict(country_code,school_year,national_grade,code) do update set subject_code=excluded.subject_code,name_fa=excluded.name_fa`,[subjectId,b.schoolYear??'unknown',b.grade,key,b.subjectCode,b.titleFa]);
  // Legacy trusted HTTPS landing page is independent from the exact HTTP research citation.
  await c.query(`insert into textbook_catalog(id,curriculum_subject_id,title_fa,source_url,stable_book_key,book_code,track_codes,variant,edition_verification,sequence_verification,source_evidence_url,alignment_notes_fa) values($1,$2,$3,'https://chap.sch.ir/',$4,$5,$6,$7,$8,$9,$10,$11) on conflict(stable_book_key) do update set title_fa=excluded.title_fa,track_codes=excluded.track_codes,edition_verification=excluded.edition_verification,sequence_verification=excluded.sequence_verification,source_evidence_url=excluded.source_evidence_url,alignment_notes_fa=excluded.alignment_notes_fa`,[bookId,subjectId,b.titleFa,key,b.bookCode,[...new Set(b.trackCodes)].sort(),b.variant,b.editionVerification,b.sequenceVerification??'unverified',b.sourceEvidenceUrl,b.alignmentNotesFa??'انطباق چاپ و منابع تأیید نشده است.']);
  const keptUnits=[];
  for(const u of b.units){const unitId=stableUuid(key+':unit:'+u.unitKey);keptUnits.push(unitId);await c.query(`insert into learning_unit(id,textbook_id,unit_key,title_fa,order_index,index_kind,source_evidence_url) values($1,$2,$3,$4,$5,$6,$7) on conflict(textbook_id,unit_key) do update set title_fa=excluded.title_fa,order_index=excluded.order_index,index_kind=excluded.index_kind,source_evidence_url=excluded.source_evidence_url,active=true`,[unitId,bookId,u.unitKey,u.titleFa,u.orderIndex,u.indexKind,u.sourceEvidenceUrl]);
   const keptVideos=[];for(const v of u.videos){const videoId=stableUuid(key+':unit:'+u.unitKey+':video:'+v.aparatId);keptVideos.push(videoId);
    const materialHash=crypto.createHash('sha256').update(JSON.stringify({bookKey:key,bookTitle:b.titleFa,editionVerification:b.editionVerification,bookEvidence:b.sourceEvidenceUrl,unitKey:u.unitKey,unitTitle:u.titleFa,indexKind:u.indexKind,orderIndex:u.orderIndex,unitEvidence:u.sourceEvidenceUrl,aparatId:v.aparatId,canonicalAparatId:v.canonicalAparatId??null,title:v.titleFa,creatorName:v.creatorName,creatorUrl:v.creatorUrl,sourceEvidence:v.sourceEvidenceUrl,verification:v.verificationStatus,durationSeconds:v.durationSeconds,freeAccess:v.freeAccess,qualityNotes:v.qualityNotesFa})).digest('hex');
    const values=[videoId,unitId,v.aparatId,v.canonicalAparatId??null,v.titleFa,v.creatorName,v.creatorUrl,v.sourceEvidenceUrl,v.verificationStatus,v.durationSeconds,v.freeAccess,v.checkedAt,v.qualityNotesFa,materialHash];
    await c.query(`insert into learning_video_resource(id,unit_id,aparat_id,canonical_aparat_id,title_fa,creator_name,creator_url,source_evidence_url,verification_status,duration_seconds,free_access,checked_at,quality_notes_fa,material_hash) values($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14) on conflict(unit_id,aparat_id) do update set canonical_aparat_id=excluded.canonical_aparat_id,title_fa=excluded.title_fa,creator_name=excluded.creator_name,creator_url=excluded.creator_url,source_evidence_url=excluded.source_evidence_url,verification_status=excluded.verification_status,duration_seconds=excluded.duration_seconds,free_access=excluded.free_access,checked_at=excluded.checked_at,quality_notes_fa=excluded.quality_notes_fa,publication_status=case when learning_video_resource.material_hash=excluded.material_hash then learning_video_resource.publication_status else 'draft' end,pedagogical_review=case when learning_video_resource.material_hash=excluded.material_hash then learning_video_resource.pedagogical_review else 'unverified' end,review_record=case when learning_video_resource.material_hash=excluded.material_hash then learning_video_resource.review_record else null end,material_hash=excluded.material_hash`,values);
   }await c.query("update learning_video_resource set publication_status='withdrawn' where unit_id=$1 and not(id=any($2::uuid[]))",[unitId,keptVideos]);
  }await c.query('update learning_unit set active=false where textbook_id=$1 and not(id=any($2::uuid[]))',[bookId,keptUnits]);
 }
 await c.query('commit');return totals.reduce((a,b)=>({books:a.books+b.books,units:a.units+b.units,videos:a.videos+b.videos}),{books:0,units:0,videos:0});
 }catch(e){await c.query('rollback').catch(()=>{});throw e;}finally{c.release();}
}
