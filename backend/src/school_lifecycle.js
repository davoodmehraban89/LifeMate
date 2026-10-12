import crypto from 'node:crypto';
import express from 'express';

const UUID = /^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$/i;
const TYPES = { contexts: 'life_context', years: 'academic_year', terms: 'academic_term' };
class InputError extends Error { constructor(status, code) { super(code); this.status = status; this.code = code; } }
const fail = (status, code) => { throw new InputError(status, code); };
const owns = (raw, key) => Object.hasOwn(raw, key);
const uuid = (raw) => { if (typeof raw !== 'string' || !UUID.test(raw)) fail(400, 'invalid_school_id'); return raw.toLowerCase(); };
const title = (raw) => { if (typeof raw !== 'string' || !raw.trim() || raw.trim().length > 120) fail(400, 'invalid_school_title'); return raw.trim(); };
function date(raw) {
  if (typeof raw !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(raw) || raw.startsWith('0000-')) fail(400, 'invalid_school_date');
  const parsed = new Date(`${raw}T00:00:00Z`);
  if (!Number.isFinite(parsed.getTime()) || parsed.toISOString().slice(0, 10) !== raw) fail(400, 'invalid_school_date');
  return raw;
}
export const schoolLifecycleError = (error) => {
  if (error instanceof InputError) return error;
  if (error.code === '23505') return new InputError(409, 'school_entity_conflict');
  if (error.code === '23514' && error.message.startsWith('school_')) {
    const code = error.message.split('\n')[0];
    return new InputError(code.includes('forbidden') ? 403 : code.includes('inactive') || code.includes('in_use') || code.includes('immutable') ? 409 : 400, code);
  }
  return error;
};
const route = (handler) => async (req, res, next) => {
  try { await handler(req, res); }
  catch (raw) { const error = schoolLifecycleError(raw); if (error instanceof InputError) return res.status(error.status).json({error: error.code}); next(error); }
};
export async function assertSchoolSession(client, identity) {
  const session = await client.query(`select 1 from auth_session s join app_user u on u.id=s.user_id
    where s.id=$1 and s.user_id=$2 and s.revoked_at is null
      and s.expires_at>statement_timestamp() and u.disabled_at is null for share of s`, [identity.sid, identity.sub]);
  // statement_timestamp() in the locking SELECT was sampled before any wait.
  // Sample again after the lock is acquired rather than accepting stale time.
  const current = session.rowCount && await client.query(`select 1 from auth_session s join app_user u on u.id=s.user_id
    where s.id=$1 and s.user_id=$2 and s.revoked_at is null
      and s.expires_at>statement_timestamp() and u.disabled_at is null`, [identity.sid, identity.sub]);
  if (!current?.rowCount || (identity.exp != null && identity.exp * 1000 <= Date.now())) fail(401, 'session_invalid');
}
async function transaction(pool, operation, identity, write = false) {
  const client = await pool.connect();
  try {
    await client.query('begin');
    const account = await client.query(`select 1 from app_user where id=$1 and disabled_at is null for ${write ? 'update' : 'share'}`, [identity.sub]);
    if (!account.rowCount) fail(401, 'session_invalid');
    await assertSchoolSession(client, identity);
    const result = await operation(client);
    await assertSchoolSession(client, identity);
    await client.query('commit'); return result;
  }
  catch (error) { await client.query('rollback').catch(() => {}); throw error; }
  finally { client.release(); }
}
function mutation(raw, type) {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw) || Object.keys(raw).some((key) => !['mutationId','entityId','operation','expectedVersion','data'].includes(key))) fail(400, 'invalid_school_mutation');
  const result = { mutationId: uuid(raw.mutationId), entityId: uuid(raw.entityId), operation: raw.operation, expectedVersion: raw.expectedVersion, data: {} };
  if (!['create','update','archive'].includes(result.operation) || !Number.isInteger(result.expectedVersion) || result.expectedVersion < 0 || result.expectedVersion > 2147483646 || (result.operation === 'create' ? result.expectedVersion !== 0 : result.expectedVersion < 1)) fail(400, 'invalid_school_mutation');
  const data = raw.data ?? {};
  if (!data || typeof data !== 'object' || Array.isArray(data)) fail(400, 'invalid_school_data');
  const allowed = result.operation === 'archive' ? [] : type === 'contexts' ? ['title','kind'] : ['title','startsOn','endsOn', ...(result.operation === 'create' ? [type === 'years' ? 'lifeContextId' : 'academicYearId'] : [])];
  if (Object.keys(data).some((key) => !allowed.includes(key))) fail(400, 'invalid_school_data');
  for (const key of allowed) if (owns(data, key)) {
    result.data[key] = key === 'title' ? title(data[key]) : key.endsWith('On') ? date(data[key]) : key.endsWith('Id') ? uuid(data[key]) : data[key];
  }
  if (owns(data, 'kind') && !['student','work','personal'].includes(data.kind)) fail(400, 'invalid_school_kind');
  if (result.operation === 'create' && allowed.some((key) => !owns(data, key))) fail(400, 'invalid_school_data');
  if (result.operation === 'update' && !Object.keys(data).length) fail(400, 'invalid_school_data');
  if (result.data.startsOn && result.data.endsOn && result.data.endsOn < result.data.startsOn) fail(400, 'invalid_school_date_range');
  return result;
}
const projection = (type, alias = 'e') => type === 'contexts' ? `${alias}.*` : `${alias}.*,${alias}.starts_on::text as starts_on,${alias}.ends_on::text as ends_on`;
async function owned(client, type, id, ownerId, lock = false) {
  const sql = type === 'contexts' ? `select ${projection(type)} from life_context e where e.id=$1 and e.user_id=$2` : type === 'years' ? `select ${projection(type)} from academic_year e where e.id=$1 and e.student_user_id=$2` : `select ${projection(type)} from academic_term e join academic_year y on y.id=e.academic_year_id join life_context l on l.id=y.life_context_id where e.id=$1 and y.student_user_id=$2 and l.user_id=$2`;
  return (await client.query(sql + (lock ? ' for update of e' : ''), [id, ownerId])).rows[0];
}
async function parent(client, type, data, ownerId) {
  if (type === 'contexts') return;
  const raw = await owned(client, type === 'years' ? 'contexts' : 'years', type === 'years' ? data.lifeContextId : data.academicYearId, ownerId);
  if (!raw) fail(403, 'school_parent_forbidden');
  if (!raw.active || (type === 'years' && raw.kind !== 'student')) fail(409, 'school_parent_inactive');
  if (type === 'terms') {
    const context = await owned(client, 'contexts', raw.life_context_id, ownerId);
    if (!context?.active || context.kind !== 'student') fail(409, 'school_parent_inactive');
    if (data.startsOn < raw.starts_on || data.endsOn > raw.ends_on) fail(400, 'school_dates_outside_parent');
  }
}
export function createSchoolLifecycleRouter({ pool, auth }) {
  const router = express.Router();
  router.get('/school/lifecycle', auth, route(async (req, res) => {
    const result = await transaction(pool, async (client) => {
      const contexts = (await client.query('select * from life_context where user_id=$1 order by created_at,id limit 501', [req.identity.sub])).rows;
      const years = (await client.query(`select ${projection('years')} from academic_year e join life_context l on l.id=e.life_context_id where e.student_user_id=$1 and l.user_id=$1 order by e.starts_on desc,e.id limit 501`, [req.identity.sub])).rows;
      const terms = (await client.query(`select ${projection('terms')} from academic_term e join academic_year y on y.id=e.academic_year_id join life_context l on l.id=y.life_context_id where y.student_user_id=$1 and l.user_id=$1 order by e.starts_on desc,e.id limit 501`, [req.identity.sub])).rows;
      if ([contexts, years, terms].some((rows) => rows.length > 500)) fail(422, 'school_list_limit_exceeded');
      const fetchedAt = (await client.query('select clock_timestamp() as now')).rows[0].now.toISOString();
      return { contexts, years, terms, fetchedAt };
    }, req.identity);
    res.json(result);
  }));
  router.post('/school/lifecycle/:type/mutations', auth, route(async (req, res) => {
    const type = req.params.type;
    if (!owns(TYPES, type)) fail(404, 'school_entity_type_not_found');
    const body = mutation(req.body, type);
    const requestHash = crypto.createHash('sha256').update(JSON.stringify({ type, ...body })).digest('hex');
    const result = await transaction(pool, async (client) => {
      const ledger = (await client.query('select * from school_lifecycle_mutation where owner_user_id=$1 and mutation_id=$2', [req.identity.sub, body.mutationId])).rows[0];
      if (ledger) {
        if (ledger.request_hash !== requestHash) fail(409, 'school_mutation_reused');
        const entity = await owned(client, type, body.entityId, req.identity.sub);
        if (!entity) fail(404, 'school_entity_not_found');
        return { entity, acknowledgement: { mutationId: body.mutationId, entityId: body.entityId, entityType: type, operation: body.operation, status: 'already_applied', appliedVersion: ledger.applied_version, acceptedAt: ledger.accepted_at.toISOString() } };
      }
      let entity;
      if (body.operation === 'create') {
        const counts = type === 'contexts' ? 'select count(*)::int as n from life_context where user_id=$1' : type === 'years' ? 'select count(*)::int as n from academic_year where student_user_id=$1' : 'select count(*)::int as n from academic_term t join academic_year y on y.id=t.academic_year_id where y.student_user_id=$1';
        if ((await client.query(counts, [req.identity.sub])).rows[0].n >= 500) fail(422, 'school_list_limit_exceeded');
        await parent(client, type, body.data, req.identity.sub);
        if (type === 'contexts') await client.query('insert into life_context(id,user_id,kind,title) values($1,$2,$3,$4)', [body.entityId, req.identity.sub, body.data.kind, body.data.title]);
        else if (type === 'years') await client.query('insert into academic_year(id,student_user_id,life_context_id,title,starts_on,ends_on) values($1,$2,$3,$4,$5,$6)', [body.entityId, req.identity.sub, body.data.lifeContextId, body.data.title, body.data.startsOn, body.data.endsOn]);
        else await client.query('insert into academic_term(id,academic_year_id,title,starts_on,ends_on) values($1,$2,$3,$4,$5)', [body.entityId, body.data.academicYearId, body.data.title, body.data.startsOn, body.data.endsOn]);
      } else {
        const current = await owned(client, type, body.entityId, req.identity.sub, true);
        if (!current) fail(404, 'school_entity_not_found');
        if (current.version !== body.expectedVersion) fail(409, 'school_version_conflict');
        if (!current.active) fail(409, 'school_entity_archived');
        if (body.operation === 'archive') await client.query(`update ${TYPES[type]} set active=false where id=$1`, [body.entityId]);
        else {
          const data = { title: current.title, ...(type === 'contexts' ? { kind: current.kind } : { startsOn: current.starts_on, endsOn: current.ends_on, ...(type === 'years' ? { lifeContextId: current.life_context_id } : { academicYearId: current.academic_year_id }) }), ...body.data };
          if (type !== 'contexts' && data.endsOn < data.startsOn) fail(400, 'invalid_school_date_range');
          await parent(client, type, data, req.identity.sub);
          if (type === 'contexts') await client.query('update life_context set title=$2,kind=$3 where id=$1', [body.entityId, data.title, data.kind]);
          else await client.query(`update ${TYPES[type]} set title=$2,starts_on=$3,ends_on=$4 where id=$1`, [body.entityId, data.title, data.startsOn, data.endsOn]);
        }
      }
      entity = await owned(client, type, body.entityId, req.identity.sub);
      const inserted = (await client.query('insert into school_lifecycle_mutation(owner_user_id,mutation_id,entity_type,entity_id,operation,request_hash,applied_version) values($1,$2,$3,$4,$5,$6,$7) returning accepted_at', [req.identity.sub, body.mutationId, type, body.entityId, body.operation, requestHash, entity.version])).rows[0];
      return { entity, acknowledgement: { mutationId: body.mutationId, entityId: body.entityId, entityType: type, operation: body.operation, status: 'accepted', appliedVersion: entity.version, acceptedAt: inserted.accepted_at.toISOString() } };
    }, req.identity, true);
    res.status(result.acknowledgement.status === 'accepted' && body.operation === 'create' ? 201 : 200).json(result);
  }));
  return router;
}
