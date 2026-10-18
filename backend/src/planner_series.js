import crypto from 'node:crypto';
import express from 'express';
import { createPlanItem, updatePlanItem, planTransaction, serializePlanItem, validUuid, PlanMutationError } from './plan_mutations.js';

const DAY = 86400000;
const fail = (status, code) => { throw new PlanMutationError(status, code); };
const timePattern = /^(?:[01]\d|2[0-3]):[0-5]\d$/;
const stampPattern = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})$/;
const dayNumber = day => Date.parse(day + 'T00:00:00Z') / DAY;
const addDays = (day, count) => new Date((dayNumber(day) + count) * DAY).toISOString().slice(0,10);
function date(value) {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value) || value < '1900-01-01' || value > '2100-12-31'
    || !Number.isFinite(dayNumber(value)) || new Date(dayNumber(value) * DAY).toISOString().slice(0,10) !== value) fail(400,'invalid_series_date');
  return value;
}
function formatter(timezone) {
  if (typeof timezone !== 'string' || timezone.length > 100) fail(400,'invalid_series_timezone');
  try { return new Intl.DateTimeFormat('en-CA', { timeZone:timezone, calendar:'iso8601', numberingSystem:'latn',
    year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',second:'2-digit',hourCycle:'h23' }); }
  catch { fail(400,'invalid_series_timezone'); }
}
function wallParts(format, instant) {
  const p = Object.fromEntries(format.formatToParts(new Date(instant)).filter(part => part.type !== 'literal').map(part => [part.type,part.value]));
  return { day:`${p.year}-${p.month}-${p.day}`, time:`${p.hour}:${p.minute}`, second:p.second };
}
const todayIn = format => wallParts(format,Date.now()).day;
function boundedDay(value, today) {
  date(value); if (Math.abs(dayNumber(value) - dayNumber(today)) > 730) fail(400,'series_date_outside_horizon'); return value;
}
// Invert IANA wall time using surrounding offsets. A repeated clock time uses
// the earlier instant; a nonexistent clock time rejects the transaction.
function localInstant(format, day, time) {
  const naive = Date.parse(`${day}T${time}:00Z`), matches = new Set();
  for (const hours of [-36,-12,0,12,36]) {
    const sample = naive + hours * 3600000, p = wallParts(format,sample);
    const offset = Date.parse(`${p.day}T${p.time}:${p.second}Z`) - sample;
    const candidate = naive - offset, actual = wallParts(format,candidate);
    if (actual.day === day && actual.time === time && actual.second === '00') matches.add(candidate);
  }
  if (!matches.size) fail(400,'nonexistent_series_local_time');
  return new Date(Math.min(...matches));
}
function normalize(body) {
  const allowed = new Set(['id','title','kind','timezone','startsOn','untilOn','frequency','intervalDays','slots','reminderMinutes']);
  if (!body || typeof body !== 'object' || Array.isArray(body) || Object.keys(body).some(key => !allowed.has(key))) fail(400,'invalid_planner_series');
  if (!validUuid(body.id)) fail(400,'invalid_id');
  if (typeof body.title !== 'string' || !body.title.trim() || body.title.trim().length > 240) fail(400,'invalid_title');
  const kind = body.kind ?? 'routine'; if (!['task','event','routine'].includes(kind)) fail(400,'invalid_series_kind');
  const timezone = body.timezone ?? 'Asia/Tehran', format = formatter(timezone), today = todayIn(format);
  const startsOn = boundedDay(body.startsOn,today), untilOn = body.untilOn == null ? null : boundedDay(body.untilOn,today);
  if (untilOn && untilOn < startsOn) fail(400,'invalid_series_date_order');
  const frequency = body.frequency, intervalDays = body.intervalDays ?? 1;
  if (!['daily','weekly'].includes(frequency) || ![1,2].includes(intervalDays) || (frequency === 'weekly' && intervalDays !== 1)) fail(400,'invalid_series_frequency');
  if (!Array.isArray(body.slots) || !body.slots.length || body.slots.length > 7 || (frequency === 'daily' && body.slots.length !== 1)) fail(400,'invalid_series_slots');
  const weekdays = new Set();
  const slots = body.slots.map(slot => {
    if (!slot || typeof slot !== 'object' || Array.isArray(slot) || Object.keys(slot).some(key => !['weekday','start','end'].includes(key))
      || typeof slot.start !== 'string' || typeof slot.end !== 'string' || !timePattern.test(slot.start) || !timePattern.test(slot.end) || slot.end <= slot.start) fail(400,'invalid_series_slot');
    if (frequency === 'weekly') {
      if (!Number.isInteger(slot.weekday) || slot.weekday < 1 || slot.weekday > 7 || weekdays.has(slot.weekday)) fail(400,'invalid_series_weekday');
      weekdays.add(slot.weekday); return { weekday:slot.weekday,start:slot.start,end:slot.end };
    }
    if (slot.weekday !== undefined) fail(400,'daily_series_weekday_not_applicable');
    return { start:slot.start,end:slot.end };
  }).sort((a,b) => (a.weekday ?? 0) - (b.weekday ?? 0));
  const reminders = body.reminderMinutes ?? [];
  if (!Array.isArray(reminders) || reminders.length > 100 || reminders.some(value => !Number.isInteger(value) || value < 0 || value > 10080)) fail(400,'invalid_reminders');
  const config = { title:body.title.trim(),kind,timezone,startsOn,untilOn,frequency,intervalDays,slots,reminderMinutes:[...new Set(reminders)].sort((a,b) => a-b) };
  return { config,format,today,hash:crypto.createHash('sha256').update(JSON.stringify(config)).digest('hex') };
}
function serializeSeries(row) {
  const { request_hash, ...result } = row; return { ...result,version:Number(row.version) };
}
async function owned(client, owner, id) {
  if (!validUuid(id)) fail(400,'invalid_id');
  const row = (await client.query(`select *,starts_on::text as starts_on,until_on::text as until_on,
    materialized_through::text as materialized_through from planner_series where id=$1 and owner_user_id=$2 for update`,[id,owner])).rows[0];
  if (!row) fail(404,'not_found'); return row;
}
async function materialize(client, owner, series, from, to, format) {
  if (series.archived_at) fail(409,'series_archived');
  const today = todayIn(format); boundedDay(from,today); boundedDay(to,today);
  if (from > to || dayNumber(to) - dayNumber(from) >= 93) fail(400,'invalid_series_window');
  const first = from > series.starts_on ? from : series.starts_on;
  const last = series.until_on && series.until_on < to ? series.until_on : to;
  if (first > last) return { series,items:[],materializedRange:null };
  for (let current = first; current <= last; current = addDays(current,1)) {
    const weekday = new Date(current + 'T00:00:00Z').getUTCDay() || 7;
    const slot = series.frequency === 'weekly' ? series.slots.find(value => value.weekday === weekday)
      : (dayNumber(current) - dayNumber(series.starts_on)) % series.interval_days === 0 ? series.slots[0] : null;
    if (!slot || (await client.query('select 1 from plan_item where series_id=$1 and original_occurrence_date=$2',[series.id,current])).rowCount) continue;
    const startsAt = localInstant(format,current,slot.start), endsAt = localInstant(format,current,slot.end), seconds = (endsAt-startsAt)/1000;
    if (seconds <= 0 || seconds > 86400) fail(400,'invalid_series_duration');
    // Owner transaction lock serializes generation and ordinary edits. The
    // unique(series_id,original_occurrence_date) constraint guards the DB too.
    await createPlanItem(client,owner,{ kind:series.kind,title:series.title,visibility:'private',startsAt:startsAt.toISOString(),
      endsAt:endsAt.toISOString(),plannedDurationSeconds:seconds,reminderMinutesBefore:series.reminder_minutes },undefined,{ seriesId:series.id,date:current });
  }
  if (!series.materialized_through || last > series.materialized_through) {
    await client.query('update planner_series set materialized_through=$2,updated_at=now(),version=version+1 where id=$1',[series.id,last]);
    series = await owned(client,owner,series.id);
  }
  const items = (await client.query('select * from plan_item where series_id=$1 and original_occurrence_date between $2 and $3 order by original_occurrence_date',
    [series.id,first,last])).rows.map(row => serializePlanItem(row,owner));
  return { series,items,materializedRange:{ from:first,to:last } };
}
const route = handler => async (req,res,next) => {
  try { await handler(req,res); } catch (error) {
    if (error instanceof PlanMutationError) return res.status(error.status).json({ error:error.code,...error.details }); next(error);
  }
};
export function createPlannerSeriesRouter({ pool,auth }) {
  const router = express.Router();
  router.get('/planner-series',auth,route(async (req,res) => {
    const rows = (await pool.query(`select *,starts_on::text as starts_on,until_on::text as until_on,
      materialized_through::text as materialized_through from planner_series where owner_user_id=$1 and archived_at is null order by created_at`,[req.identity.sub])).rows;
    res.json({ series:rows.map(serializeSeries) });
  }));
  router.get('/planner-series/:id',auth,route(async (req,res) => {
    const series = await planTransaction(pool,req.identity.sub,client => owned(client,req.identity.sub,req.params.id)); res.json({ series:serializeSeries(series) });
  }));
  router.post('/planner-series',auth,route(async (req,res) => {
    const { config,format,today,hash } = normalize(req.body);
    const result = await planTransaction(pool,req.identity.sub,async client => {
      const previous = (await client.query('select owner_user_id,request_hash from planner_series where id=$1',[req.body.id])).rows[0];
      if (previous) {
        if (previous.owner_user_id !== req.identity.sub || previous.request_hash !== hash) fail(409,'series_id_reused');
        const series = await owned(client,req.identity.sub,req.body.id);
        const items = (await client.query('select * from plan_item where series_id=$1 order by original_occurrence_date',[series.id])).rows.map(row => serializePlanItem(row,req.identity.sub));
        return { series,items,replayed:true,materializedRange:null };
      }
      await client.query(`insert into planner_series(id,owner_user_id,title,kind,timezone,starts_on,until_on,frequency,interval_days,slots,reminder_minutes,request_hash)
        values($1,$2,$3,$4,$5,$6,$7,$8,$9,$10::jsonb,$11,$12)`,[req.body.id,req.identity.sub,config.title,config.kind,config.timezone,
        config.startsOn,config.untilOn,config.frequency,config.intervalDays,JSON.stringify(config.slots),config.reminderMinutes,hash]);
      const series = await owned(client,req.identity.sub,req.body.id), from = config.startsOn > today ? config.startsOn : today;
      if (config.untilOn && config.untilOn < from) return { series,items:[],replayed:false,materializedRange:null };
      const to = addDays(from,59), limit = addDays(today,730);
      return { ...await materialize(client,req.identity.sub,series,from,to > limit ? limit : to,format),replayed:false };
    });
    res.status(result.replayed ? 200 : 201).json({ ...result,series:serializeSeries(result.series) });
  }));
  router.post('/planner-series/:id/materialize',auth,route(async (req,res) => {
    const result = await planTransaction(pool,req.identity.sub,async client => {
      const series = await owned(client,req.identity.sub,req.params.id);
      return materialize(client,req.identity.sub,series,req.body?.from,req.body?.to,formatter(series.timezone));
    }); res.json({ ...result,series:serializeSeries(result.series) });
  }));
  router.delete('/planner-series/:id',auth,route(async (req,res) => {
    const series = await planTransaction(pool,req.identity.sub,async client => {
      let row = await owned(client,req.identity.sub,req.params.id);
      if (!Number.isSafeInteger(req.body?.expectedVersion)) fail(400,'expected_version_required');
      if (Number(row.version) !== req.body.expectedVersion) fail(409,'version_conflict');
      if (!row.archived_at) {
        const future = (await client.query("select id,version from plan_item where series_id=$1 and starts_at>=now() and status in ('planned','in_progress')",[row.id])).rows;
        for (const item of future) await updatePlanItem(client,req.identity.sub,item.id,{ status:'cancelled' },Number(item.version));
        await client.query('update planner_series set archived_at=now(),updated_at=now(),version=version+1 where id=$1',[row.id]); row = await owned(client,req.identity.sub,row.id);
      } return row;
    }); res.json({ series:serializeSeries(series) });
  }));
  router.get('/planner-reminders',auth,route(async (req,res) => {
    const from = req.query.from, to = req.query.to;
    if (typeof from !== 'string' || typeof to !== 'string' || !stampPattern.test(from) || !stampPattern.test(to)
      || !Number.isFinite(Date.parse(from)) || !Number.isFinite(Date.parse(to)) || Date.parse(to) <= Date.parse(from)
      || Date.parse(to)-Date.parse(from) > 2*DAY) fail(400,'invalid_reminder_window');
    const reminders = (await pool.query(`select r.id,r.plan_item_id,r.scheduled_for,r.owner_user_id from reminder r join plan_item p on p.id=r.plan_item_id
      where r.owner_user_id=$1 and p.owner_user_id=$1 and r.status='scheduled' and p.status in ('planned','in_progress')
      and r.scheduled_for>=$2 and r.scheduled_for<$3 order by r.scheduled_for,r.id`,[req.identity.sub,from,to])).rows;
    res.json({ reminders,asOf:new Date() });
  }));
  return router;
}
