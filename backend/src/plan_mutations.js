import crypto from 'node:crypto';

const kinds = new Set(['task', 'event', 'routine', 'goal', 'assignment', 'exam', 'study_session']);
const statuses = new Set(['planned', 'in_progress', 'completed', 'cancelled']);
const priorities = new Set(['low', 'normal', 'high', 'urgent']);
const scopes = new Set(['private', 'selected_members', 'parent_guardian', 'family']);
export const validUuid = (x) => typeof x === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(x);
export class PlanMutationError extends Error {
  constructor(status, code, details = {}) { super(code); this.status = status; this.code = code; this.details = details; }
}
const fail = (status, code, details) => { throw new PlanMutationError(status, code, details); };
export function serializePlanItem(item, viewer) {
  const result = { ...item, version: Number(item.version), activity_version: Number(item.activity_version) };
  if (item.owner_user_id !== viewer) delete result.notes;
  return result;
}
function canonical(value) {
  if (Array.isArray(value)) return value.map(canonical);
  if (value && typeof value === 'object') return Object.fromEntries(Object.keys(value).sort().map((key) => [key, canonical(value[key])]));
  return value;
}
function date(value, field) {
  if (value === null) return null;
  if (typeof value !== 'string' || !/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{1,6})?(?:Z|[+-]\d\d:\d\d)$/.test(value)) fail(400, `invalid_${field}`);
  const parsed = new Date(value);
  if (!Number.isFinite(parsed.getTime())) fail(400, `invalid_${field}`);
  return parsed;
}
function text(value, field, max, nullable = false) {
  if (nullable && value === null) return null;
  if (typeof value !== 'string' || value.length > max || (!nullable && !value.trim())) fail(400, `invalid_${field}`);
  return nullable ? value : value.trim();
}
function id(value, field) {
  if (value === null) return null;
  if (!validUuid(value)) fail(400, `invalid_${field}`);
  return value;
}
function integer(value, field, min, max) {
  if (value === null) return null;
  if (!Number.isSafeInteger(value) || value < min || value > max) fail(400, `invalid_${field}`);
  return value;
}
function normalize(payload, existing = null) {
  if (!payload || typeof payload !== 'object' || Array.isArray(payload)) fail(400, 'invalid_plan_item');
  for (const key of ['ownerUserId', 'owner_user_id', 'version', 'activity_version', 'created_at', 'updated_at', 'completed_at']) if (key in payload) fail(400, 'server_owned_field');
  const fields = {};
  const isCreate = !existing;
  const defaults = { kind: 'task', title: '', priority: 'normal', visibility: 'private', familyId: null, subjectId: null,
    notes: null, startsAt: null, dueAt: null, durationMinutes: null, plannedDurationSeconds: null,
    recurrenceRule: null, parentItemId: null };
  const values = isCreate ? { ...defaults, ...payload } : payload;
  const pick = (key, column, validation) => { if (values[key] !== undefined) fields[column] = validation(values[key]); };
  pick('kind', 'kind', (x) => { if (!kinds.has(x)) fail(400, 'invalid_kind'); return x; });
  pick('title', 'title', (x) => text(x, 'title', 240));
  pick('notes', 'notes', (x) => text(x, 'notes', 10000, true));
  pick('priority', 'priority', (x) => { if (!priorities.has(x)) fail(400, 'invalid_priority'); return x; });
  pick('visibility', 'visibility', (x) => { if (!scopes.has(x)) fail(400, 'invalid_visibility'); return x; });
  pick('status', 'status', (x) => { if (!statuses.has(x) || (isCreate && x !== 'planned')) fail(400, 'invalid_status'); return x; });
  pick('familyId', 'family_id', (x) => id(x, 'family_id'));
  pick('subjectId', 'subject_id', (x) => id(x, 'subject_id'));
  pick('parentItemId', 'parent_item_id', (x) => id(x, 'parent_item_id'));
  pick('startsAt', 'starts_at', (x) => date(x, 'starts_at'));
  pick('dueAt', 'due_at', (x) => date(x, 'due_at'));
  pick('recurrenceRule', 'recurrence_rule', (x) => text(x, 'recurrence_rule', 1000, true));
  pick('durationMinutes', 'duration_minutes', (x) => integer(x, 'duration_minutes', 1, 1440));
  pick('plannedDurationSeconds', 'planned_duration_seconds', (x) => integer(x, 'planned_duration_seconds', 0, 86400));
  for (const [key, column] of [['gradePoints', 'grade_points'], ['gradeOutOf', 'grade_out_of']]) pick(key, column, (x) => {
    if (x === null) return null;
    if (typeof x !== 'number' || !Number.isFinite(x) || x < 0 || x > 999999.99) fail(400, 'invalid_grade');
    return x;
  });
  if (payload.plannedDurationSeconds !== undefined) fields.duration_minutes = payload.plannedDurationSeconds == null || payload.plannedDurationSeconds === 0 ? null : Math.ceil(payload.plannedDurationSeconds / 60);
  else if (payload.durationMinutes !== undefined) fields.planned_duration_seconds = payload.durationMinutes == null ? null : payload.durationMinutes * 60;
  const merged = { ...existing, ...fields };
  if (fields.grade_points !== undefined || fields.grade_out_of !== undefined) {
    if (!['assignment', 'exam'].includes(merged.kind)) fail(400, 'grade_not_applicable');
    if (!(merged.grade_points == null && merged.grade_out_of == null)
      && (merged.grade_points == null || merged.grade_out_of == null || Number(merged.grade_out_of) <= 0 || Number(merged.grade_points) > Number(merged.grade_out_of))) fail(400, 'invalid_grade');
  }
  if (merged.starts_at && merged.due_at && new Date(merged.due_at) < new Date(merged.starts_at)) fail(400, 'invalid_date_order');
  if (['family', 'parent_guardian', 'selected_members'].includes(merged.visibility) && !merged.family_id) fail(400, 'family_required_for_visibility');
  return { fields, merged };
}
export async function planOwnerLock(client, userId) {
  await client.query('select pg_advisory_xact_lock(hashtextextended($1::text,0))', [userId]);
}
async function authorize(client, userId, item) {
  if (!(await client.query('select 1 from app_user where id=$1 and disabled_at is null', [userId])).rowCount) fail(401, 'unauthorized');
  if (item && item.owner_user_id !== userId) fail(403, 'forbidden');
  if (item?.family_id && !(await client.query('select 1 where is_active_family_member($1,$2)', [item.family_id, userId])).rowCount) fail(403, 'family_membership_required');
}
async function relations(client, userId, item, payload, existing = null) {
  await authorize(client, userId, item);
  if (item.subject_id && !(await client.query('select 1 from subject where id=$1 and student_user_id=$2', [item.subject_id, userId])).rowCount) fail(403, 'subject_forbidden');
  if (item.parent_item_id && !(await client.query('select 1 from plan_item where id=$1 and owner_user_id=$2', [item.parent_item_id, userId])).rowCount) fail(403, 'parent_item_forbidden');
  if (payload.selectedMemberIds !== undefined && (!Array.isArray(payload.selectedMemberIds) || payload.selectedMemberIds.length > 100)) fail(400, 'invalid_selected_members');
  const selected = payload.selectedMemberIds === undefined ? null : [...new Set(payload.selectedMemberIds)];
  if (item.visibility === 'selected_members' && (!existing || existing.visibility !== 'selected_members' || existing.family_id !== item.family_id) && (!selected || !selected.length)) fail(400, 'selected_members_required');
  if (selected) for (const member of selected) {
    if (!validUuid(member) || !(await client.query('select 1 where is_active_family_member($1,$2)', [item.family_id, member])).rowCount) fail(400, 'selected_member_not_in_family');
  }
  return selected;
}
async function grants(client, item, selected) {
  if (selected !== null || item.visibility !== 'selected_members') await client.query("delete from sharing_grant where resource_type='plan_item' and resource_id=$1", [item.id]);
  if (item.visibility === 'selected_members' && selected) for (const member of selected) await client.query(
    "insert into sharing_grant(resource_type,resource_id,grantee_user_id,granted_by) values('plan_item',$1,$2,$3)", [item.id, member, item.owner_user_id],
  );
}
async function reminders(client, item, payload) {
  if (payload.reminderMinutesBefore !== undefined) {
    if (!Array.isArray(payload.reminderMinutesBefore) || payload.reminderMinutesBefore.length > 100 || payload.reminderMinutesBefore.some((x) => !Number.isSafeInteger(x) || x < 0 || x > 10080)) fail(400, 'invalid_reminders');
    await client.query('delete from reminder where plan_item_id=$1', [item.id]);
    const base = item.starts_at ?? item.due_at;
    if (base) for (const minutes of new Set(payload.reminderMinutesBefore)) await client.query(
      'insert into reminder(plan_item_id,owner_user_id,minutes_before,scheduled_for) values($1,$2,$3,$4::timestamptz-make_interval(mins=>$3))', [item.id, item.owner_user_id, minutes, base],
    );
  }
  if (['completed', 'cancelled'].includes(item.status)) await client.query("update reminder set status='cancelled' where plan_item_id=$1 and status in ('scheduled','claimed')", [item.id]);
  else await client.query('select recompute_reminder_schedule($1)', [item.id]);
}
export async function createPlanItem(client, userId, payload, itemId = crypto.randomUUID()) {
  if (!validUuid(itemId)) fail(400, 'invalid_id');
  const { fields } = normalize(payload);
  const selected = await relations(client, userId, { ...fields, owner_user_id: userId }, payload);
  const columns = ['id', 'owner_user_id', ...Object.keys(fields)];
  const values = [itemId, userId, ...Object.values(fields)];
  const row = (await client.query(`insert into plan_item(${columns.join(',')}) values(${values.map((_, i) => `$${i + 1}`).join(',')}) returning *`, values)).rows[0];
  await grants(client, row, selected);
  await reminders(client, row, payload);
  return row;
}
export async function updatePlanItem(client, userId, itemId, payload, expectedVersion) {
  if (!validUuid(itemId)) fail(400, 'invalid_id');
  const current = (await client.query('select * from plan_item where id=$1 for update', [itemId])).rows[0];
  if (!current) fail(404, 'not_found');
  await authorize(client, userId, current);
  if (!Number.isSafeInteger(expectedVersion) || expectedVersion < 0) fail(400, 'expected_version_required');
  if (expectedVersion !== Number(current.version)) fail(409, 'version_conflict', { serverVersion: Number(current.version) });
  const { fields, merged } = normalize(payload, current);
  if (!Object.keys(fields).length && payload.selectedMemberIds === undefined && payload.reminderMinutesBefore === undefined) fail(400, 'no_changes');
  const selected = await relations(client, userId, merged, payload, current);
  if (fields.status !== undefined) fields.completed_at = fields.status === 'completed' ? current.completed_at ?? new Date() : null;
  const values = [itemId, ...Object.values(fields)];
  const update = [...Object.keys(fields).map((key, i) => `${key}=$${i + 2}`), 'updated_at=now()'];
  const item = (await client.query(`update plan_item set ${update.join(',')} where id=$1 returning *`, values)).rows[0];
  await grants(client, item, selected);
  await reminders(client, item, payload);
  return item;
}
export async function planTransaction(pool, userId, execute) {
  const client = await pool.connect();
  try { await client.query('begin'); await planOwnerLock(client, userId); const result = await execute(client); await client.query('commit'); return result; }
  catch (error) { await client.query('rollback').catch(() => {}); if (error.code === '23505') fail(409, 'plan_item_exists'); throw error; }
  finally { client.release(); }
}
export async function applyPlanMutation(pool, userId, mutation) {
  const idValue = mutation?.id;
  try {
    if (!validUuid(idValue) || mutation.entityType !== 'plan_item' || !validUuid(mutation.entityId)
      || !['create', 'update', 'complete', 'reschedule', 'archive'].includes(mutation.operation)
      || !mutation.payload || typeof mutation.payload !== 'object' || Array.isArray(mutation.payload)) fail(400, 'invalid_mutation');
    const hash = crypto.createHash('sha256').update(JSON.stringify(canonical({ entityType: mutation.entityType, entityId: mutation.entityId, operation: mutation.operation, expectedVersion: mutation.expectedVersion ?? null, payload: mutation.payload }))).digest('hex');
    return await planTransaction(pool, userId, async (client) => {
      const previous = (await client.query('select * from sync_mutation where user_id=$1 and id=$2', [userId, idValue])).rows[0];
      if (previous) {
        const current = (await client.query('select * from plan_item where id=$1', [previous.entity_id])).rows[0];
        if (!current) fail(404, 'not_found');
        await authorize(client, userId, current);
        if (previous.request_hash !== hash || !previous.canonical_item) fail(409, 'mutation_id_reused', { serverVersion: Number(current.version) });
        return { id: idValue, entityId: previous.entity_id, status: 'already_applied', acceptedAt: previous.accepted_at, item: previous.canonical_item };
      }
      let item;
      if (mutation.operation === 'create') {
        if (mutation.expectedVersion !== undefined && mutation.expectedVersion !== 0) fail(400, 'create_expected_version_zero');
        if (mutation.payload.id !== undefined && mutation.payload.id !== mutation.entityId) fail(400, 'entity_id_mismatch');
        item = await createPlanItem(client, userId, mutation.payload, mutation.entityId);
      } else {
        const payload = { ...mutation.payload };
        if (mutation.operation === 'complete') payload.status = 'completed';
        if (mutation.operation === 'archive') payload.status = 'cancelled';
        if (mutation.operation === 'reschedule' && payload.dueAt === undefined && payload.startsAt === undefined) fail(400, 'invalid_reschedule');
        item = await updatePlanItem(client, userId, mutation.entityId, payload, mutation.expectedVersion);
      }
      const canonicalItem = serializePlanItem(item, userId);
      const accepted = (await client.query(
        `insert into sync_mutation(id,user_id,entity_type,entity_id,operation,client_updated_at,payload,request_hash,canonical_item)
         values($1,$2,'plan_item',$3,$4,now(),$5::jsonb,$6,$7::jsonb) returning accepted_at`,
        [idValue, userId, item.id, mutation.operation, JSON.stringify(mutation.payload), hash, JSON.stringify(canonicalItem)],
      )).rows[0].accepted_at;
      return { id: idValue, entityId: item.id, status: 'accepted', acceptedAt: accepted, item: canonicalItem };
    });
  } catch (error) {
    if (!(error instanceof PlanMutationError)) throw error;
    return { id: idValue ?? null, entityId: mutation?.entityId ?? null,
      status: error.status === 409 ? 'conflict' : 'rejected', error: error.code, httpStatus: error.status, ...error.details };
  }
}
