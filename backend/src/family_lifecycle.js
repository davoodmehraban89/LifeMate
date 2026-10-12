import crypto from 'node:crypto';
import express from 'express';

const uuid=value=>typeof value==='string'&&/^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$/i.test(value);
const version=value=>Number.isInteger(value)&&value>0&&value<2147483647;
const roles=new Set(['parent_guardian','teen_minor','adult_member']);
const exact=(body,fields)=>body&&typeof body==='object'&&!Array.isArray(body)&&Object.keys(body).every(key=>fields.includes(key));
const error=(status,name)=>({status,body:{error:name}});
const hash=body=>crypto.createHash('sha256').update(JSON.stringify(body)).digest('hex');
const memberColumns='m.user_id,m.role,m.is_admin,m.version,m.updated_at,m.ended_at';
const send=(res,result)=>res.status(result.status).json(result.body);

export function normalizeRoleMutation(body){
  if(!exact(body,['mutationId','expectedVersion','role'])||!uuid(body.mutationId)||!version(body.expectedVersion)||!roles.has(body.role))return null;
  return {mutationId:body.mutationId.toLowerCase(),expectedVersion:body.expectedVersion,role:body.role};
}
export function normalizeAdminTransfer(body){
  if(!exact(body,['mutationId','targetUserId','expectedVersion','expectedActorVersion'])||!uuid(body.mutationId)||!uuid(body.targetUserId)||
    !version(body.expectedVersion)||!version(body.expectedActorVersion))return null;
  return {mutationId:body.mutationId.toLowerCase(),targetUserId:body.targetUserId.toLowerCase(),
    expectedVersion:body.expectedVersion,expectedActorVersion:body.expectedActorVersion};
}
export function normalizeInvitationRevoke(body){
  if(!exact(body,['mutationId','expectedVersion','action'])||!uuid(body.mutationId)||!version(body.expectedVersion)||body.action!=='revoke')return null;
  return {mutationId:body.mutationId.toLowerCase(),expectedVersion:body.expectedVersion,action:'revoke'};
}
const memberBody=row=>({userId:row.user_id,role:row.role,isAdmin:row.is_admin,version:row.version,updatedAt:row.updated_at,endedAt:row.ended_at});
const invitationBody=row=>({id:row.id,status:row.status,version:row.version,createdAt:row.created_at,expiresAt:row.expires_at});
function hint(row){return row.invited_phone_normalized?`***${row.invited_phone_normalized.slice(-4)}`:
  row.invited_email_normalized?`***@${row.invited_email_normalized.split('@').at(-1)}`:null;}

async function sessionCurrent(client,identity,{lock=false}={}){
  // Logout does not lock app_user. Hold the session row only at the final gate,
  // then check fresh statement time after any session-row lock wait as well.
  if(lock)await client.query('select id from auth_session where id=$1 and user_id=$2 for share',[identity.sid,identity.sub]);
  return (await client.query(`select 1 from app_user u join auth_session s on s.user_id=u.id
    where u.id=$1 and u.disabled_at is null and s.id=$2 and s.revoked_at is null
      and s.expires_at>statement_timestamp()
      and ($3::double precision is null or to_timestamp($3)>statement_timestamp())`,[identity.sub,identity.sid,identity.exp??null])).rowCount>0;
}
async function transaction(pool,identity,operation){
  const client=await pool.connect();
  try{
    await client.query('begin');const result=await operation(client);
    if(!await sessionCurrent(client,identity,{lock:true})){await client.query('rollback');return error(401,'session_invalid');}
    await client.query('commit');return result;
  }catch(exception){await client.query('rollback').catch(()=>{});throw exception;}
  finally{client.release();}
}
async function familyMember(client,familyId,identity,targetId=null){
  const family=await client.query('select id from family_workspace where id=$1 and archived_at is null for update',[familyId]);
  if(!family.rowCount)return error(403,'forbidden');
  const participants=[...new Set([identity.sub,...(targetId?[targetId]:[])])].sort();
  // Multiple families may share these accounts. Lock all participating users in
  // UUID order before individual memberships, rather than actor then target.
  await client.query('select id from app_user where id=any($1::uuid[]) order by id for update',[participants]);
  // Birth dates are editable independently of the account row. Freeze the age
  // context until this explicit family change commits.
  await client.query('select user_id from profile where user_id=any($1::uuid[]) order by user_id for update',[participants]);
  await client.query('select user_id from family_membership where family_id=$1 and user_id=any($2::uuid[]) order by user_id for update',[familyId,participants]);
  const member=(await client.query(`select ${memberColumns} from family_membership m join app_user u on u.id=m.user_id
    where m.family_id=$1 and m.user_id=$2 and m.ended_at is null and u.disabled_at is null`,[familyId,identity.sub])).rows[0];
  if(!member)return error(403,'forbidden');
  if(!await sessionCurrent(client,identity))return error(401,'session_invalid');
  return member;
}
const admin=member=>member.is_admin&&member.role!=='teen_minor';
async function targetMember(client,familyId,id){
  return (await client.query(`select ${memberColumns},u.disabled_at,p.birth_date,
    (p.birth_date is not null and p.birth_date>(current_date-interval '18 years')::date) known_minor
    from family_membership m join app_user u on u.id=m.user_id left join profile p on p.user_id=m.user_id
    where m.family_id=$1 and m.user_id=$2`,[familyId,id])).rows[0];
}
async function receipt(client,identity,mutationId){
  return (await client.query('select * from family_lifecycle_mutation where actor_user_id=$1 and mutation_id=$2',[identity.sub,mutationId])).rows[0];
}
async function saveReceipt(client,identity,body,familyId,operation,targetId,digest){
  await client.query(`insert into family_lifecycle_mutation(actor_user_id,mutation_id,family_id,operation,target_id,request_hash)
    values($1,$2,$3,$4,$5,$6)`,[identity.sub,body.mutationId,familyId,operation,targetId,digest]);
}
function acknowledgement(body,familyId,targetId,operation,applied){return {mutationId:body.mutationId,familyId,targetId,operation,
  status:applied?'already_applied':'accepted'};}
async function audit(client,identity,familyId,operation,targetId){
  await client.query(`insert into access_audit(actor_user_id,family_id,action,target_type,target_id)
    values($1,$2,$3,$4,$5)`,[identity.sub,familyId,`family.lifecycle.${operation}`,
      operation==='invitation_revoke'?'invitation':'membership',targetId]);
}
async function invalidateRoleSharing(client,familyId,targetId){
  await client.query(`update guardian_relationship g set active=false
    where g.family_id=$1 and g.active and (g.guardian_user_id=$2 or g.minor_user_id=$2)
      and not exists(select 1 from family_membership gm join family_membership mm on mm.family_id=gm.family_id
        where gm.family_id=g.family_id and gm.user_id=g.guardian_user_id and gm.ended_at is null and gm.role='parent_guardian'
          and mm.user_id=g.minor_user_id and mm.ended_at is null and mm.role='teen_minor')`,[familyId,targetId]);
  // A role change is a new sharing context. Explicit selections must be chosen
  // again; reversing a role never silently restores previous selections.
  await client.query(`delete from sharing_grant sg using plan_item p where sg.resource_type='plan_item'
    and sg.resource_id=p.id and p.family_id=$1 and (p.owner_user_id=$2 or sg.grantee_user_id=$2)`,[familyId,targetId]);
}

export function createFamilyLifecycleRouter({pool,auth}){
  const router=express.Router();
  router.get('/families/:familyId/invitations',auth,async(req,res)=>{
    const cursor=req.query.cursor??null,limit=req.query.limit===undefined?100:Number(req.query.limit);
    if(!uuid(req.params.familyId)||Object.keys(req.query).some(key=>!['limit','cursor'].includes(key))||
      (cursor!==null&&!uuid(cursor))||!Number.isInteger(limit)||limit<1||limit>100||
      (req.query.limit!==undefined&&(typeof req.query.limit!=='string'||!/^\d+$/.test(req.query.limit))))return send(res,error(400,'invalid_invitation_query'));
    send(res,await transaction(pool,req.identity,async client=>{
      const actor=await familyMember(client,req.params.familyId,req.identity);if(actor.status)return actor;
      if(!admin(actor))return error(403,'forbidden');
      const result=(await client.query(`with pending as materialized (
        select id,intended_role,case when expires_at<=statement_timestamp() then 'expired' else 'pending' end status,
          invited_email_normalized,invited_phone_normalized,version,created_at,expires_at
        from family_invitation where family_id=$1 and status='pending'
      ),page as (select * from pending where $2::uuid is null or (created_at,id)<(select created_at,id from pending where id=$2)
        order by created_at desc,id desc limit $3)
      select (select count(*)::int from pending) total,exists(select 1 from pending where id=$2) cursor_exists,
        coalesce((select jsonb_agg(to_jsonb(page) order by created_at desc,id desc) from page),'[]'::jsonb) rows`,
      [req.params.familyId,cursor,limit+1])).rows[0];
      if(cursor&&!result.cursor_exists)return error(404,'invitation_not_found');
      return {status:200,body:{invitations:result.rows.slice(0,limit).map(row=>({...invitationBody(row),
        intendedRole:row.intended_role,recipientHint:hint(row)})),nextCursor:result.rows.length>limit?result.rows[limit-1].id:null,total:result.total}};
    }));
  });
  router.patch('/families/:familyId/invitations/:id',auth,async(req,res)=>{
    const body=normalizeInvitationRevoke(req.body),familyId=req.params.familyId,id=req.params.id;
    if(!uuid(familyId)||!uuid(id)||!body||Object.keys(req.query).length)return send(res,error(400,'invalid_invitation_mutation'));
    const digest=hash({familyId:familyId.toLowerCase(),id:id.toLowerCase(),operation:'invitation_revoke',...body});
    send(res,await transaction(pool,req.identity,async client=>{
      const actor=await familyMember(client,familyId,req.identity);if(actor.status)return actor;
      const previous=await receipt(client,req.identity,body.mutationId);
      if(previous&&previous.request_hash!==digest)return error(409,'mutation_id_reused');
      if(!previous&&!admin(actor))return error(403,'forbidden');
      const row=(await client.query('select id,status,version,created_at,expires_at from family_invitation where family_id=$1 and id=$2 for update',[familyId,id])).rows[0];
      if(!row)return error(404,'invitation_not_found');
      if(previous)return {status:200,body:{invitation:invitationBody(row),acknowledgement:acknowledgement(body,familyId,id,'invitation_revoke',true)}};
      if(row.version!==body.expectedVersion)return error(409,'invitation_version_conflict');
      if(row.status!=='pending')return error(409,'invitation_not_pending');
      const updated=(await client.query("update family_invitation set status='revoked' where id=$1 returning id,status,version,created_at,expires_at",[id])).rows[0];
      await saveReceipt(client,req.identity,body,familyId,'invitation_revoke',id,digest);await audit(client,req.identity,familyId,'invitation_revoke',id);
      return {status:200,body:{invitation:invitationBody(updated),acknowledgement:acknowledgement(body,familyId,id,'invitation_revoke',false)}};
    }));
  });
  router.patch('/families/:familyId/members/:userId/role',auth,async(req,res)=>{
    const body=normalizeRoleMutation(req.body),familyId=req.params.familyId,id=req.params.userId;
    if(!uuid(familyId)||!uuid(id)||!body||Object.keys(req.query).length)return send(res,error(400,'invalid_membership_mutation'));
    const digest=hash({familyId:familyId.toLowerCase(),id:id.toLowerCase(),operation:'role',...body});
    send(res,await transaction(pool,req.identity,async client=>{
      const actor=await familyMember(client,familyId,req.identity,id);if(actor.status)return actor;
      const previous=await receipt(client,req.identity,body.mutationId);
      if(previous&&previous.request_hash!==digest)return error(409,'mutation_id_reused');
      if(!previous&&!admin(actor))return error(403,'forbidden');
      const target=await targetMember(client,familyId,id);if(!target)return error(404,'membership_not_found');
      if(previous)return {status:200,body:{members:[memberBody(target)],acknowledgement:acknowledgement(body,familyId,id,'role',true)}};
      if(target.ended_at||target.disabled_at)return error(409,'member_not_active');
      if(target.version!==body.expectedVersion)return error(409,'membership_version_conflict');
      if(target.role===body.role)return error(409,'membership_change_not_required');
      if(body.role==='teen_minor'&&target.is_admin)return error(409,'minor_cannot_admin');
      if(body.role!=='teen_minor'&&target.known_minor)return error(409,'minor_role_upgrade_forbidden');
      if(target.role==='teen_minor'&&body.role!=='teen_minor'&&!target.birth_date)return error(409,'age_confirmation_required');
      const updated=(await client.query(`update family_membership m set role=$3
        where family_id=$1 and user_id=$2 returning ${memberColumns}`,[familyId,id,body.role])).rows[0];
      await invalidateRoleSharing(client,familyId,id);
      await saveReceipt(client,req.identity,body,familyId,'role',id,digest);await audit(client,req.identity,familyId,'role',id);
      return {status:200,body:{members:[memberBody(updated)],acknowledgement:acknowledgement(body,familyId,id,'role',false)}};
    }));
  });
  router.post('/families/:familyId/admin-transfer',auth,async(req,res)=>{
    const body=normalizeAdminTransfer(req.body),familyId=req.params.familyId;
    if(!uuid(familyId)||!body||Object.keys(req.query).length)return send(res,error(400,'invalid_admin_transfer'));
    const digest=hash({familyId:familyId.toLowerCase(),operation:'admin_transfer',...body});
    send(res,await transaction(pool,req.identity,async client=>{
      const actor=await familyMember(client,familyId,req.identity,body.targetUserId);if(actor.status)return actor;
      const previous=await receipt(client,req.identity,body.mutationId);
      if(previous&&previous.request_hash!==digest)return error(409,'mutation_id_reused');
      if(!previous&&!admin(actor))return error(403,'forbidden');
      const target=await targetMember(client,familyId,body.targetUserId);if(!target)return error(404,'membership_not_found');
      if(previous)return {status:200,body:{members:[memberBody(actor),memberBody(target)],
        acknowledgement:acknowledgement(body,familyId,body.targetUserId,'admin_transfer',true)}};
      if(target.user_id===actor.user_id)return error(409,'admin_target_invalid');
      if(target.ended_at||target.disabled_at)return error(409,'member_not_active');
      if(target.role==='teen_minor'||target.known_minor)return error(409,'minor_cannot_admin');
      if(actor.version!==body.expectedActorVersion||target.version!==body.expectedVersion)return error(409,'membership_version_conflict');
      if(target.is_admin)return error(409,'admin_target_already_admin');
      const promoted=(await client.query(`update family_membership m set is_admin=true where family_id=$1 and user_id=$2 returning ${memberColumns}`,
        [familyId,body.targetUserId])).rows[0];
      const demoted=(await client.query(`update family_membership m set is_admin=false where family_id=$1 and user_id=$2 returning ${memberColumns}`,
        [familyId,req.identity.sub])).rows[0];
      // Existing invitations require a currently active inviter-admin. Revoke
      // them on transfer; transferring back never revives an old bearer token.
      await client.query("update family_invitation set status='revoked' where family_id=$1 and invited_by=$2 and status='pending'",[familyId,req.identity.sub]);
      await saveReceipt(client,req.identity,body,familyId,'admin_transfer',body.targetUserId,digest);await audit(client,req.identity,familyId,'admin_transfer',body.targetUserId);
      return {status:200,body:{members:[memberBody(demoted),memberBody(promoted)],
        acknowledgement:acknowledgement(body,familyId,body.targetUserId,'admin_transfer',false)}};
    }));
  });
  return router;
}
