import crypto from 'node:crypto';
import express from 'express';

const uuid=value=>typeof value==='string'&&/^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(value);
const statuses=new Set(['received','triaged','planned','declined','released']);
const reviewStatuses=new Set(['triaged','planned','declined']);
const transitions={received:new Set(['triaged','declined']),triaged:new Set(['planned','declined']),
  planned:new Set(['triaged','declined']),declined:new Set(['triaged'])};
const exact=(value,keys)=>value&&typeof value==='object'&&!Array.isArray(value)&&
  Object.keys(value).every(key=>keys.includes(key));
const version=value=>Number.isSafeInteger(value)&&value>0&&value<=2147483647;
const error=(status,name)=>({status,body:{error:name}});
const digest=value=>crypto.createHash('sha256').update(JSON.stringify(value)).digest('hex');
const feedbackFields=`id,unit_id,category,summary,status,version,created_at,updated_at`;
const visible=`withdrawn_at is null and share_with_content_team=true and summary is not null`;

export function normalizeReviewMutation(body) {
  if(!exact(body,['mutationId','expectedVersion','status'])||!uuid(body.mutationId)||
    !version(body.expectedVersion)||!reviewStatuses.has(body.status)) return null;
  return {mutationId:body.mutationId.toLowerCase(),expectedVersion:body.expectedVersion,status:body.status};
}
export function normalizeBriefRequest(body) {
  if(!exact(body,['mutationId','feedback'])||!uuid(body.mutationId)||!Array.isArray(body.feedback)||
    body.feedback.length<1||body.feedback.length>20||body.feedback.some(source=>
      !exact(source,['id','expectedVersion'])||!uuid(source.id)||!version(source.expectedVersion))) return null;
  const feedback=body.feedback.map(source=>({id:source.id.toLowerCase(),expectedVersion:source.expectedVersion}));
  if(new Set(feedback.map(source=>source.id)).size!==feedback.length) return null;
  feedback.sort((a,b)=>a.id.localeCompare(b.id));
  return {mutationId:body.mutationId.toLowerCase(),feedback};
}

function feedbackBody(row) {
  return {id:row.id,unitId:row.unit_id,category:row.category,summary:row.summary,status:row.status,
    version:row.version,createdAt:row.created_at,updatedAt:row.updated_at};
}
async function transaction(pool,operation,authorization) {
  const client=await pool.connect();
  try {
    await client.query('begin');
    const result=await operation(client);
    // A capability/session may expire while waiting for a source row lock.
    // Refuse the response and rollback writes if it is no longer current.
    if(authorization) {
      const current=await permissions(client,authorization.identity,authorization.required);
      if(current.status) { await client.query('rollback'); return current; }
      if(Array.isArray(result.body?.permissions)) result.body.permissions=current.permissions;
    }
    await client.query('commit');
    return result;
  } catch(exception) { await client.query('rollback').catch(()=>{}); throw exception; }
  finally { client.release(); }
}
function send(res,result) { res.status(result.status).json(result.body); }

async function permissions(client,identity,required=[]) {
  if(identity.exp!=null&&identity.exp*1000<=Date.now()) return error(401,'session_invalid');
  // The offline operator uses this same account lock before grant/revoke. Runtime
  // needs SELECT only on capability tables; no role claims or parent shortcuts.
  const user=await client.query('select id from app_user where id=$1 and disabled_at is null for update',[identity.sub]);
  const session=await client.query(`select 1 from auth_session where id=$1 and user_id=$2
    and revoked_at is null and expires_at>statement_timestamp() for share`,[identity.sid,identity.sub]);
  if(!user.rowCount||!session.rowCount) return error(401,'session_invalid');
  const rows=await client.query(`select permission from content_capability_grant where user_id=$1
    and revoked_at is null and expires_at>statement_timestamp() order by permission`,[identity.sub]);
  const allowed=rows.rows.map(row=>row.permission);
  if(required.some(permission=>!allowed.includes(permission))) return error(403,'content_permission_required');
  return {permissions:allowed};
}
async function mutation(client,actor,id) {
  return (await client.query(`select operation,request_hash,feedback_id,brief_id
    from content_review_mutation where actor_user_id=$1 and mutation_id=$2`,[actor,id])).rows[0];
}
async function lockFeedback(client,id) {
  return (await client.query(`select ${feedbackFields} from learning_content_feedback
    where id=$1 and ${visible} for update`,[id])).rows[0];
}

const tasks=Object.freeze([
  'نسخه رسمی کتاب و هدف یادگیری این درس را بررسی کنید.',
  'محتوای پیشنهادی و سؤال‌های تمرینی را به‌طور کامل بازبینی کنید.',
  'برای تغییر پیشنهادی معیار پذیرش، آزمون و PR مستقل تهیه کنید.',
  'انتشار محتوا و استقرار فقط پس از بازبینی و مجوز جداگانه انجام شود.'
]);
async function briefBody(client,id) {
  const brief=(await client.query('select id,created_at,source_count from content_review_brief where id=$1',[id])).rows[0];
  if(!brief) return error(404,'brief_not_found');
  // Sorted row locks share the same serialization boundary as owner withdrawal
  // and review updates. No summaries are stored/copied in this brief.
  const sources=(await client.query(`select f.id,f.version,f.status,f.withdrawn_at,
    f.share_with_content_team,f.category,f.unit_id,s.feedback_version
    from content_review_brief_source s join learning_content_feedback f on f.id=s.feedback_id
    where s.brief_id=$1 order by f.id for update of f`,[id])).rows;
  if(sources.length!==brief.source_count||sources.some(source=>source.withdrawn_at||!source.share_with_content_team||
    source.status!=='planned'||source.version!==source.feedback_version)) return error(409,'brief_invalidated');
  const categories=new Map();
  for(const source of sources) categories.set(source.category,(categories.get(source.category)??0)+1);
  const unitIds=[...new Set(sources.map(source=>source.unit_id).filter(Boolean))];
  const units=(await client.query(`select u.id,u.title_fa,t.book_code,t.title_fa book_title,
    t.track_codes,t.edition_verification,s.school_year,s.national_grade
    from learning_unit u join textbook_catalog t on t.id=u.textbook_id
    join curriculum_subject s on s.id=t.curriculum_subject_id where u.id=any($1::uuid[]) order by u.id`,[unitIds])).rows;
  return {status:200,body:{brief:{id:brief.id,title:'پیشنهاد بررسی و توسعه محتوای آموزشی',createdAt:brief.created_at,
    sourceCount:sources.length,categories:[...categories].sort(([a],[b])=>a.localeCompare(b)).map(([category,count])=>({category,count})),
    units:units.map(unit=>({id:unit.id,title:unit.title_fa,bookCode:unit.book_code,bookTitle:unit.book_title,
      gradeLevel:unit.national_grade,trackCode:unit.track_codes,editionYear:unit.school_year==='unknown'?null:unit.school_year,
      editionStatus:unit.edition_verification})),tasks:[...tasks],
    notice:'این پیشنهاد ساختاری فاقد متن بازخورد و اطلاعات خصوصی است؛ تأیید محتوا یا دستور انتشار نیست.'}}};
}

export function createContentReviewRouter({pool,auth}) {
  const router=express.Router();
  router.get('/me/content-capabilities',auth,async(req,res)=>{
    if(Object.keys(req.query).length) return send(res,error(400,'invalid_content_query'));
    send(res,await transaction(pool,async client=>{
      const grant=await permissions(client,req.identity);
      return grant.status?grant:{status:200,body:grant};
    },{identity:req.identity,required:[]}));
  });
  router.get('/content-review/feedback',auth,async(req,res)=>{
    const cursor=req.query.cursor??null,status=req.query.status??null;
    const limit=req.query.limit===undefined?50:Number(req.query.limit);
    if(Object.keys(req.query).some(key=>!['cursor','status','limit'].includes(key))||
      (cursor!==null&&!uuid(cursor))||(status!==null&&!statuses.has(status))||
      (req.query.limit!==undefined&&(typeof req.query.limit!=='string'||!/^\d+$/.test(req.query.limit)))||
      !Number.isInteger(limit)||limit<1||limit>100) return send(res,error(400,'invalid_content_query'));
    send(res,await transaction(pool,async client=>{
      const grant=await permissions(client,req.identity,['feedback.read']); if(grant.status) return grant;
      // Lock the consenting set once. Paging and count derive from the same
      // statement snapshot; microseconds remain in PostgreSQL cursor comparisons.
      const result=await client.query(`with consenting as materialized (
        select ${feedbackFields} from learning_content_feedback where ${visible}
        and ($2::text is null or status=$2) order by id for share
      ), page as (
        select * from consenting where $1::uuid is null or (created_at,id)<
          (select created_at,id from consenting where id=$1)
        order by created_at desc,id desc limit $3
      ) select (select count(*)::int from consenting) total,
        exists(select 1 from consenting where id=$1) cursor_exists,
        coalesce((select jsonb_agg(to_jsonb(page) order by created_at desc,id desc) from page),'[]'::jsonb) rows`,
      [cursor,status,limit+1]);
      const row=result.rows[0];
      if(cursor&&!row.cursor_exists) return error(404,'feedback_not_found');
      return {status:200,body:{feedback:row.rows.slice(0,limit).map(feedbackBody),
        nextCursor:row.rows.length>limit?row.rows[limit-1].id:null,total:row.total}};
    },{identity:req.identity,required:['feedback.read']}));
  });
  router.patch('/content-review/feedback/:id',auth,async(req,res)=>{
    const body=normalizeReviewMutation(req.body);
    if(!uuid(req.params.id)||!body||Object.keys(req.query).length) return send(res,error(400,'invalid_review_mutation'));
    const hash=digest({feedbackId:req.params.id.toLowerCase(),...body});
    send(res,await transaction(pool,async client=>{
      const grant=await permissions(client,req.identity,['feedback.read','feedback.review']); if(grant.status) return grant;
      const previous=await mutation(client,req.identity.sub,body.mutationId);
      if(previous&&(previous.operation!=='review'||previous.request_hash!==hash)) return error(409,'mutation_id_reused');
      const row=await lockFeedback(client,req.params.id); if(!row) return error(404,'feedback_not_found');
      if(previous) return {status:200,body:{feedback:feedbackBody(row),acknowledgement:{mutationId:body.mutationId,
        feedbackId:row.id,status:'already_applied'}}};
      if(row.version!==body.expectedVersion) return error(409,'feedback_version_conflict');
      if(!transitions[row.status]?.has(body.status)) return error(409,'feedback_transition_invalid');
      const updated=(await client.query(`update learning_content_feedback set status=$2,version=version+1,
        updated_at=statement_timestamp() where id=$1 returning ${feedbackFields}`,[row.id,body.status])).rows[0];
      await client.query(`insert into content_review_audit(actor_user_id,feedback_id,before_status,after_status,before_version,after_version)
        values($1,$2,$3,$4,$5,$6)`,[req.identity.sub,row.id,row.status,updated.status,row.version,updated.version]);
      await client.query(`insert into content_review_mutation(actor_user_id,mutation_id,operation,request_hash,feedback_id)
        values($1,$2,'review',$3,$4)`,[req.identity.sub,body.mutationId,hash,row.id]);
      return {status:200,body:{feedback:feedbackBody(updated),acknowledgement:{mutationId:body.mutationId,
        feedbackId:row.id,status:'accepted'}}};
    },{identity:req.identity,required:['feedback.read','feedback.review']}));
  });
  router.post('/content-review/briefs',auth,async(req,res)=>{
    const body=normalizeBriefRequest(req.body);
    if(!body||Object.keys(req.query).length) return send(res,error(400,'invalid_brief_request'));
    const hash=digest(body);
    send(res,await transaction(pool,async client=>{
      const grant=await permissions(client,req.identity,['feedback.read','brief.prepare']); if(grant.status) return grant;
      const previous=await mutation(client,req.identity.sub,body.mutationId);
      if(previous&&(previous.operation!=='brief'||previous.request_hash!==hash)) return error(409,'mutation_id_reused');
      if(previous) {
        const existing=await briefBody(client,previous.brief_id);
        if(existing.status!==200) return existing;
        existing.body.acknowledgement={mutationId:body.mutationId,briefId:previous.brief_id,status:'already_applied'};
        return existing;
      }
      for(const source of body.feedback) {
        const row=await lockFeedback(client,source.id); if(!row) return error(404,'feedback_not_found');
        if(row.status!=='planned'||row.version!==source.expectedVersion) return error(409,'brief_source_conflict');
      }
      const brief=(await client.query('insert into content_review_brief(actor_user_id,source_count) values($1,$2) returning id',
        [req.identity.sub,body.feedback.length])).rows[0];
      for(const source of body.feedback) await client.query(`insert into content_review_brief_source(brief_id,feedback_id,feedback_version)
        values($1,$2,$3)`,[brief.id,source.id,source.expectedVersion]);
      await client.query(`insert into content_review_mutation(actor_user_id,mutation_id,operation,request_hash,brief_id)
        values($1,$2,'brief',$3,$4)`,[req.identity.sub,body.mutationId,hash,brief.id]);
      const result=await briefBody(client,brief.id);
      result.status=201;
      result.body.acknowledgement={mutationId:body.mutationId,briefId:brief.id,status:'accepted'};
      return result;
    },{identity:req.identity,required:['feedback.read','brief.prepare']}));
  });
  router.get('/content-review/briefs/:id',auth,async(req,res)=>{
    if(!uuid(req.params.id)||Object.keys(req.query).length) return send(res,error(400,'invalid_brief_query'));
    send(res,await transaction(pool,async client=>{
      const grant=await permissions(client,req.identity,['feedback.read','brief.prepare']); if(grant.status) return grant;
      return briefBody(client,req.params.id);
    },{identity:req.identity,required:['feedback.read','brief.prepare']}));
  });
  return router;
}
