// No remote/live permission changes: this packet supports explicitly named,
// local synthetic fixtures only. No default admin, family role or HTTP grant.
import crypto from 'node:crypto';
import pg from 'pg';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const scopes=new Set(['feedback.read','feedback.review','brief.prepare']);
const uuid=value=>typeof value==='string'&&/^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(value);

export function normalizeCapabilityOperation(args) {
  const [action,userId,permission,expiresAt,...extra]=args;
  if(!['grant','revoke'].includes(action)||!uuid(userId)||!scopes.has(permission)||extra.length||
    (action==='revoke'&&expiresAt!==undefined)) return null;
  if(action==='grant') {
    if(typeof expiresAt!=='string'||!/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{3})?Z$/.test(expiresAt)||
      !Number.isFinite(Date.parse(expiresAt))||Date.parse(expiresAt)<=Date.now()) return null;
  }
  return {action,userId:userId.toLowerCase(),permission,expiresAt:expiresAt??null};
}

export function localSyntheticConnection(env) {
  if(!env.CONTENT_CAPABILITY_DATABASE_URL||env.CONTENT_CAPABILITY_SYNTHETIC_ONLY!=='true') {
    throw new Error('Set separate CONTENT_CAPABILITY_DATABASE_URL and CONTENT_CAPABILITY_SYNTHETIC_ONLY=true');
  }
  let location;
  try { location=new URL(env.CONTENT_CAPABILITY_DATABASE_URL); } catch { throw new Error('Invalid operator database configuration'); }
  if(!['postgres:','postgresql:'].includes(location.protocol)||
    !['localhost','127.0.0.1','[::1]','::1'].includes(location.hostname)||
    !(location.pathname.includes('test')||location.pathname==='/lifemate_ci'||
      /^\/lifeguide_roles_(?:source|target)_[a-f0-9]{16}$/.test(location.pathname))) {
    throw new Error('Capability operator refuses a nonlocal or non-test database');
  }
  return location.toString();
}

export async function manageCapability(client,operation) {
  await client.query('begin');
  try {
    const role=(await client.query(`select current_user,
      has_table_privilege(current_user,'content_capability_grant','INSERT') can_grant,
      has_table_privilege(current_user,'content_capability_grant','UPDATE') can_revoke`)).rows[0];
    if(['lifeguide_api','lifeguide_backup'].includes(role.current_user)||!role.can_grant||!role.can_revoke) {
      throw new Error('Use separate operator/migrator credentials, never runtime/backup credentials');
    }
    const actor=await client.query('select id from app_user where id=$1 and disabled_at is null for update',[operation.userId]);
    if(!actor.rowCount) throw new Error('Active synthetic account not found');
    if(operation.action==='grant') {
      if(Date.parse(operation.expiresAt)<=Date.now()) throw new Error('Grant expiry must be in the future');
      await client.query(`insert into content_capability_grant(user_id,permission,expires_at)
        values($1,$2,$3) on conflict(user_id,permission) do update set
        granted_at=statement_timestamp(),expires_at=excluded.expires_at,revoked_at=null`,
      [operation.userId,operation.permission,operation.expiresAt]);
    } else {
      await client.query(`update content_capability_grant set revoked_at=coalesce(revoked_at,statement_timestamp())
        where user_id=$1 and permission=$2`,[operation.userId,operation.permission]);
    }
    await client.query(`insert into content_capability_audit(id,target_user_id,permission,action,expires_at)
      values($1,$2,$3,$4,$5)`,[crypto.randomUUID(),operation.userId,operation.permission,operation.action,operation.expiresAt]);
    await client.query('commit');
    return {action:operation.action,permission:operation.permission,expiresAt:operation.expiresAt};
  } catch(error) { await client.query('rollback').catch(()=>{}); throw error; }
}

if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
  const operation=normalizeCapabilityOperation(process.argv.slice(2));
  if(!operation) {
    console.error('Usage: node scripts/manage-content-capabilities.js grant USER_UUID SCOPE ISO_UTC_EXPIRY | revoke USER_UUID SCOPE');
    process.exitCode=1;
  } else {
    let client;
    try {
      client=new pg.Client({connectionString:localSyntheticConnection(process.env)});
      await client.connect();
      console.log(JSON.stringify({type:'synthetic_content_capability',...(await manageCapability(client,operation))}));
    } catch {
      // Database URLs, account IDs, passwords and raw driver errors stay private.
      console.error('Capability operation rejected; check explicit synthetic configuration and separate operator privileges.');
      process.exitCode=1;
    } finally { if(client) await client.end().catch(()=>{}); }
  }
}
