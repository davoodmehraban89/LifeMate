import express from 'express';
import crypto from 'node:crypto';

const clampText = (value, max = 4000) =>
  String(value ?? '').trim().slice(0, max);
const isUuid = (value) => typeof value === 'string' && /^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$/i.test(value);

const modernGoalRequest = body => body && ['mutationId','expectedVersion','id'].some(key=>Object.hasOwn(body,key));
function normalizeGoalMutation(operation, id, body, legacy = false) {
  const fields = new Set([...(legacy?[]:['mutationId','expectedVersion',...(operation==='create'?['id']:[])]),
    ...(operation==='archive'?[]:['title','target','subjectId','status'])]);
  if (!body || typeof body !== 'object' || Array.isArray(body) || Object.keys(body).some(key=>!fields.has(key)) ||
      (!legacy && (!isUuid(body.mutationId) || !Number.isSafeInteger(body.expectedVersion) || body.expectedVersion<0 ||
        body.expectedVersion>=2147483647 || (operation==='create' ? (!isUuid(body.id) || body.expectedVersion!==0) : body.expectedVersion===0))) ||
      !isUuid(id)) return null;
  const normalized = {operation,id:id.toLowerCase(),...(legacy?{}:{mutationId:body.mutationId.toLowerCase(),expectedVersion:body.expectedVersion})};
  for (const field of ['title','target']) {
    if (!Object.hasOwn(body,field)) continue;
    if (field==='target' && body[field]===null) { normalized[field]=null; continue; }
    if (typeof body[field]!=='string' || body[field].includes('\u0000') ||
        body[field].trim().length>(field==='title'?240:1000) || (field==='title' && !body[field].trim())) return null;
    normalized[field]=body[field].trim() || null;
  }
  if (operation==='create' && !normalized.title) return null;
  if (Object.hasOwn(body,'subjectId')) {
    if (body.subjectId!==null && !isUuid(body.subjectId)) return null;
    normalized.subjectId=body.subjectId?.toLowerCase()??null;
  }
  if (Object.hasOwn(body,'status')) {
    if (!['active','completed','archived'].includes(body.status) || (operation==='create' && body.status==='archived')) return null;
    normalized.status=body.status;
  }
  if(operation==='update' && !['title','target','subjectId','status'].some(key=>Object.hasOwn(normalized,key))) return null;
  return normalized;
}

function legacyGoalInputError(body) {
  if(body && typeof body==='object' && !Array.isArray(body)) {
    if(body.subjectId!=null && !isUuid(body.subjectId)) return 'invalid_subject_id';
    if(Object.hasOwn(body,'status') && !['active','completed','archived'].includes(body.status)) return 'invalid_status';
  }
  return 'invalid_input';
}

async function goalSessionCurrent(client, identity) {
  // Lock the session through commit so logout/revocation cannot race the final
  // authorization decision. JWT expiry must also be checked after lock waits.
  const session=await client.query(`select 1 from auth_session s join app_user u on u.id=s.user_id
    where s.id=$1 and s.user_id=$2 and s.revoked_at is null
      and s.expires_at>statement_timestamp() and u.disabled_at is null for share of s`,[identity.sid,identity.sub]);
  return session.rowCount>0 && (identity.exp==null || identity.exp*1000>Date.now());
}

async function activeGoalSubject(client, id, owner) {
  const subject=await client.query(`select s.id from subject s
    join academic_term t on t.id=s.academic_term_id
    join academic_year y on y.id=t.academic_year_id
    join life_context l on l.id=y.life_context_id
    where s.id=$1 and s.student_user_id=$2 and y.student_user_id=$2 and l.user_id=$2
      and s.archived_at is null and t.active and y.active and l.active and l.kind='student'
    for share of s,t,y,l`,[id,owner]);
  return subject.rowCount>0;
}

async function legacyGoalWrite(pool, identity, operation) {
  const client=await pool.connect();
  try {
    await client.query('begin');
    const account=await client.query('select id from app_user where id=$1 and disabled_at is null for update',[identity.sub]);
    if(!account.rowCount || !await goalSessionCurrent(client,identity)) {
      await client.query('rollback'); return {status:401,body:{error:'session_invalid'}};
    }
    const result=await operation(client);
    if(!await goalSessionCurrent(client,identity)) {
      await client.query('rollback'); return {status:401,body:{error:'session_invalid'}};
    }
    await client.query('commit'); return result;
  } catch(error) { await client.query('rollback').catch(()=>{}); throw error; }
  finally { client.release(); }
}

async function mutateLearningGoal(pool, identity, operation, id, raw) {
  const owner=identity.sub;
  const body=normalizeGoalMutation(operation,id,raw);
  if(!body) return {status:400,body:{error:'invalid_goal_mutation'}};
  const hash=crypto.createHash('sha256').update(JSON.stringify(body)).digest('hex');
  const client=await pool.connect();
  const failure=(status,error)=>({status,body:{error}});
  try {
    await client.query('begin');
    const active=await client.query('select id from app_user where id=$1 and disabled_at is null for update',[owner]);
    if(!active.rowCount || !await goalSessionCurrent(client,identity)) { await client.query('rollback'); return failure(401,'session_invalid'); }
    // Owner locks alone do not serialize two independent accounts that supply
    // the same stable UUID. Lock that entity before checking/inserting it, then
    // return the ordinary forbidden response instead of leaking a PK/500 race.
    await client.query("select pg_advisory_xact_lock(hashtextextended('lifeguide:learning-goal:'||$1,0))",[body.id]);
    const previous=(await client.query('select * from learning_goal_mutation where owner_user_id=$1 and mutation_id=$2',[owner,body.mutationId])).rows[0];
    if(previous && previous.request_hash!==hash) { await client.query('rollback'); return failure(409,'mutation_id_reused'); }
    let goal=(await client.query('select * from learning_goal where id=$1 and owner_user_id=$2 for update',[body.id,owner])).rows[0];
    const acknowledgement = (row,ledger,status) => ({goal:row,acknowledgement:{mutationId:body.mutationId,
      goalId:body.id,operation,appliedVersion:ledger.applied_version,acceptedAt:ledger.accepted_at,status}});
    if(previous) {
      // Return the current tombstone/current version, never resurrect an older response.
      if(!goal) throw new Error('learning_goal_ledger_invariant');
      if(!await goalSessionCurrent(client,identity)) { await client.query('rollback'); return failure(401,'session_invalid'); }
      await client.query('commit');
      return {status:200,body:acknowledgement(goal,previous,'already_applied')};
    }
    if(!goal) {
      const foreign=await client.query('select 1 from learning_goal where id=$1',[body.id]);
      if(foreign.rowCount || operation!=='create') { await client.query('rollback'); return failure(foreign.rowCount?403:404,foreign.rowCount?'goal_forbidden':'goal_not_found'); }
    } else if(operation==='create') { await client.query('rollback'); return failure(409,'goal_id_exists'); }
    if(goal && goal.status==='archived') { await client.query('rollback'); return failure(409,'goal_archived'); }
    if(goal && goal.version!==body.expectedVersion) { await client.query('rollback'); return failure(409,'version_conflict'); }
    if(body.subjectId!=null) {
      if(!await activeGoalSubject(client,body.subjectId,owner)) { await client.query('rollback'); return failure(403,'subject_forbidden'); }
    }
    if(operation==='create') {
      goal=(await client.query('insert into learning_goal(id,owner_user_id,subject_id,title,target,status) values($1,$2,$3,$4,$5,$6) returning *',
        [body.id,owner,body.subjectId??null,body.title,body.target??null,body.status??'active'])).rows[0];
    } else {
      const status=operation==='archive'?'archived':body.status??goal.status;
      goal=(await client.query(`update learning_goal set title=$3,target=$4,subject_id=$5,status=$6,
        version=version+1,updated_at=now(),archived_at=case when $6='archived' then now() else null end
        where id=$1 and owner_user_id=$2 returning *`,[body.id,owner,body.title??goal.title,
        Object.hasOwn(body,'target')?body.target:goal.target,Object.hasOwn(body,'subjectId')?body.subjectId:goal.subject_id,status])).rows[0];
    }
    const ledger=(await client.query('insert into learning_goal_mutation(owner_user_id,mutation_id,goal_id,operation,request_hash,applied_version) values($1,$2,$3,$4,$5,$6) returning *',
      [owner,body.mutationId,body.id,operation,hash,goal.version])).rows[0];
    if(!await goalSessionCurrent(client,identity)) { await client.query('rollback'); return failure(401,'session_invalid'); }
    await client.query('commit');
    return {status:operation==='create'?201:200,body:acknowledgement(goal,ledger,'accepted')};
  } catch(error) { await client.query('rollback').catch(()=>{}); throw error; }
  finally { client.release(); }
}

function safetyClass(text) {
  const value = text.toLowerCase();
  if (/(خودکشی|خودم را بکشم|آسیب به خود|self[- ]?harm|suicide|kill myself)/i.test(value)) {
    return 'urgent_review';
  }
  if (/(غمگین|اضطراب|استرس|نگران|sad|anxious|stress|worried)/i.test(value)) {
    return 'supportive';
  }
  return 'ordinary';
}

function localGuide(kind, text, klass) {
  if (klass === 'urgent_review') {
    return 'من جای کمک فوری یا متخصص را نمی‌گیرم. اگر خطر فوری وجود دارد، همین حالا با یک فرد قابل اعتماد در نزدیکی خود یا خدمات اضطراری محلی تماس بگیر. می‌توانیم فقط روی قدم امن بعدی تمرکز کنیم.';
  }
  if (kind === 'study') {
    return `پیشنهاد مطالعه: هدف را به یک بخش ۲۵ دقیقه‌ای کوچک تبدیل کن، بعد ۵ دقیقه استراحت و در پایان سه نکته را بدون نگاه‌کردن مرور کن. موضوع فعلی: ${text.slice(0, 180)}`;
  }
  if (kind === 'planner') {
    return 'پیشنهاد برنامه‌ریزی: فقط سه اولویت امروز را انتخاب کن؛ کار سخت‌تر را به کوچک‌ترین اقدام قابل شروع بشکن و برای استراحت زمان واقعی نگه دار.';
  }
  return 'می‌توانم برای خودبازتابی، ارتباط سالم و عادت‌های حمایتی کمک کنم، نه تشخیص پزشکی. احساس را نام‌گذاری کن، شدت آن را بسنج و یک اقدام کوچک مثل آب، استراحت، حرکت کوتاه یا صحبت با فرد قابل اعتماد انتخاب کن.';
}

async function providerGuide(kind, text, klass) {
  // External AI/voice is not authorized in this package, even if keys exist.
  return localGuide(kind, text, klass);
}

async function guardianRelationship(pool, familyId, guardianUserId, minorUserId) {
  const result = await pool.query(
    'select is_active_guardian($1,$2,$3) as allowed',
    [familyId, guardianUserId, minorUserId],
  );
  return result.rows[0]?.allowed === true;
}

export function createPhase4Router({ pool, auth, sensitiveFeaturesEnabled = process.env.ENABLE_SENSITIVE_FEATURES === 'true' }) {
  const router = express.Router();
  const sensitiveEnabled = sensitiveFeaturesEnabled === true;
  const requireSensitive = (_req, res, next) => {
    if (!sensitiveEnabled) return res.status(503).json({ error: 'sensitive_features_disabled' });
    return next();
  };
  router.use(auth);

  router.post('/learning/goals', async (req, res) => {
    if(Object.keys(req.query).length) return res.status(400).json({error:'invalid_goal_mutation'});
    if(modernGoalRequest(req.body)) {
      const result=await mutateLearningGoal(pool,req.identity,'create',req.body.id,req.body);
      return res.status(result.status).json(result.body);
    }
    const body=normalizeGoalMutation('create',crypto.randomUUID(),req.body,true);
    if(!body) return res.status(400).json({error:legacyGoalInputError(req.body)});
    const result=await legacyGoalWrite(pool,req.identity,async client=>{
      if(body.subjectId!=null && !await activeGoalSubject(client,body.subjectId,req.identity.sub)) {
        return {status:403,body:{error:'subject_forbidden'}};
      }
      const created=await client.query('insert into learning_goal(owner_user_id,subject_id,title,target,status) values($1,$2,$3,$4,$5) returning *',
        [req.identity.sub,body.subjectId??null,body.title,body.target??null,body.status??'active']);
      return {status:201,body:created.rows[0]};
    });
    res.status(result.status).json(result.body);
  });

  router.get('/learning/goals', async (req, res) => {
    const result = await pool.query(
      "select * from learning_goal where owner_user_id=$1 and status<>'archived' order by created_at desc",
      [req.identity.sub],
    );
    res.json({ items: result.rows, fetchedAt: new Date().toISOString() });
  });

  router.get('/learning/goals/:id', async (req, res) => {
    if (!isUuid(req.params.id)) return res.status(400).json({ error: 'invalid_goal_id' });
    const result = await pool.query('select * from learning_goal where id=$1 and owner_user_id=$2', [req.params.id, req.identity.sub]);
    if (!result.rowCount) return res.status(404).json({ error: 'goal_not_found' });
    res.json(result.rows[0]);
  });

  router.patch('/learning/goals/:id', async (req, res) => {
    if (!isUuid(req.params.id)) return res.status(400).json({ error: 'invalid_goal_id' });
    if(Object.keys(req.query).length) return res.status(400).json({error:'invalid_goal_mutation'});
    if(modernGoalRequest(req.body)) {
      const result=await mutateLearningGoal(pool,req.identity,'update',req.params.id,req.body);
      return res.status(result.status).json(result.body);
    }
    const body=normalizeGoalMutation('update',req.params.id,req.body,true);
    if(!body) return res.status(400).json({error:legacyGoalInputError(req.body)});
    const has = (field) => Object.hasOwn(body, field);
    const result=await legacyGoalWrite(pool,req.identity,async client=>{
      const goal = await client.query('select status from learning_goal where id=$1 and owner_user_id=$2 for update', [req.params.id, req.identity.sub]);
      if (!goal.rowCount || goal.rows[0].status === 'archived') {
        return {status:goal.rowCount?409:404,body:{error:goal.rowCount?'goal_archived':'goal_not_found'}};
      }
      if (body.subjectId != null) {
        if(!await activeGoalSubject(client,body.subjectId,req.identity.sub)) return {status:403,body:{error:'subject_forbidden'}};
      }
      const updated = await client.query(
        `update learning_goal set title=case when $3 then $4 else title end,
                target=case when $5 then $6 else target end,
                subject_id=case when $7 then $8::uuid else subject_id end,
                status=coalesce($9,status),updated_at=now(),version=version+1,
                archived_at=case when $9='archived' then now() else null end
         where id=$1 and owner_user_id=$2 returning *`,
        [req.params.id, req.identity.sub, has('title'), has('title') ? body.title.trim() : null,
          has('target'), body.target?.trim() || null, has('subjectId'), body.subjectId ?? null, body.status ?? null],
      );
      return {status:200,body:updated.rows[0]};
    });
    res.status(result.status).json(result.body);
  });

  router.delete('/learning/goals/:id', async (req, res) => {
    if (!isUuid(req.params.id)) return res.status(400).json({ error: 'invalid_goal_id' });
    if(Object.keys(req.query).length) return res.status(400).json({error:'invalid_goal_mutation'});
    if(modernGoalRequest(req.body)) {
      const result=await mutateLearningGoal(pool,req.identity,'archive',req.params.id,req.body);
      return res.status(result.status).json(result.body);
    }
    if(!normalizeGoalMutation('archive',req.params.id,req.body??{},true)) return res.status(400).json({error:'invalid_input'});
    const result=await legacyGoalWrite(pool,req.identity,async client=>{
      const archived = await client.query(
      `update learning_goal set status='archived',
              archived_at=coalesce(archived_at,now()),
              version=case when status='archived' then version else version+1 end,
              updated_at=case when status='archived' then updated_at else now() end
       where id=$1 and owner_user_id=$2 returning id`,
      [req.params.id, req.identity.sub],
      );
      return archived.rowCount?{status:204}:{status:404,body:{error:'goal_not_found'}};
    });
    if(result.body===undefined) return res.status(result.status).end();
    res.status(result.status).json(result.body);
  });

  router.post('/wellbeing/checkins', requireSensitive, async (req, res) => {
    const mood = Number(req.body.mood);
    const energy = Number(req.body.energy);
    const stress = Number(req.body.stress);
    if (![mood, energy, stress].every((x) => Number.isInteger(x) && x >= 1 && x <= 5)) {
      return res.status(400).json({ error: 'invalid_input' });
    }
    const visibility =
      req.body.visibility === 'guardian_summary' ? 'guardian_summary' : 'private';
    const result = await pool.query(
      'insert into wellbeing_checkin(owner_user_id,mood,energy,stress,note,visibility) values($1,$2,$3,$4,$5,$6) returning id,mood,energy,stress,visibility,created_at',
      [
        req.identity.sub,
        mood,
        energy,
        stress,
        clampText(req.body.note, 2000) || null,
        visibility,
      ],
    );
    res.status(201).json(result.rows[0]);
  });

  router.get('/wellbeing/checkins', requireSensitive, async (req, res) => {
    const result = await pool.query(
      'select id,mood,energy,stress,visibility,created_at from wellbeing_checkin where owner_user_id=$1 order by created_at desc limit 30',
      [req.identity.sub],
    );
    res.json({ items: result.rows });
  });

  router.get('/families/:familyId/children/:minorUserId/wellbeing-summary', requireSensitive, async (req, res) => {
    const allowed = await guardianRelationship(
      pool,
      req.params.familyId,
      req.identity.sub,
      req.params.minorUserId,
    );
    if (!allowed) return res.status(403).json({ error: 'forbidden' });

    const summary = await pool.query(
      `select
         count(*)::int as checkin_count,
         round(avg(mood)::numeric,2) as mood_average,
         round(avg(energy)::numeric,2) as energy_average,
         round(avg(stress)::numeric,2) as stress_average,
         min(created_at) as window_start,
         max(created_at) as window_end
       from wellbeing_checkin
       where owner_user_id=$1
         and visibility='guardian_summary'
         and created_at >= now()-interval '14 days'`,
      [req.params.minorUserId],
    );
    const safety = await pool.query(
      `select count(*)::int as open_urgent_count,max(created_at) as latest_urgent_at
         from wellbeing_safety_event
        where owner_user_id=$1 and status='open'`,
      [req.params.minorUserId],
    );
    res.json({
      summary: summary.rows[0],
      safety: safety.rows[0],
      rawNotesIncluded: false,
      rawConversationIncluded: false,
      medicalDiagnosis: false,
    });
  });

  router.post('/families/:familyId/children/:minorUserId/family-guidance', requireSensitive, async (req, res) => {
    const allowed = await guardianRelationship(
      pool,
      req.params.familyId,
      req.identity.sub,
      req.params.minorUserId,
    );
    if (!allowed) return res.status(403).json({ error: 'forbidden' });

    const question = clampText(req.body.question, 2000);
    if (!question) return res.status(400).json({ error: 'invalid_input' });

    const [academic, wellbeing, safety] = await Promise.all([
      pool.query(
        `select
           count(*) filter (
             where kind in ('assignment','study_session')
               and status not in ('completed','cancelled')
               and due_at < now()
           )::int as overdue,
           count(*) filter (
             where kind in ('assignment','study_session')
               and status='completed'
               and completed_at >= now()-interval '7 days'
           )::int as completed_last_7_days,
           coalesce(sum(duration_minutes) filter (
             where kind='study_session'
               and status='completed'
               and completed_at >= now()-interval '7 days'
           ),0)::int as study_minutes_last_7_days,
           case when sum(grade_out_of) filter (
             where grade_points is not null and grade_out_of is not null
           ) > 0 then
             round(
               sum(grade_points) filter (where grade_points is not null and grade_out_of is not null)
               /
               sum(grade_out_of) filter (where grade_points is not null and grade_out_of is not null)
               * 100,
               1
             )
           end as grade_percent
         from plan_item
        where owner_user_id=$1 and can_view_plan_item($2,id)`,
        [req.params.minorUserId, req.identity.sub],
      ),
      pool.query(
        `select
           count(*)::int as checkin_count,
           round(avg(mood)::numeric,2) as mood_average,
           round(avg(energy)::numeric,2) as energy_average,
           round(avg(stress)::numeric,2) as stress_average
         from wellbeing_checkin
        where owner_user_id=$1
          and visibility='guardian_summary'
          and created_at >= now()-interval '14 days'`,
        [req.params.minorUserId],
      ),
      pool.query(
        `select count(*)::int as open_urgent_count
           from wellbeing_safety_event
          where owner_user_id=$1 and status='open'`,
        [req.params.minorUserId],
      ),
    ]);

    const context = {
      academic: academic.rows[0],
      wellbeing: wellbeing.rows[0],
      safety: safety.rows[0],
      privacy: {
        rawNotesIncluded: false,
        rawConversationIncluded: false,
      },
    };
    const prompt = [
      'You are advising a parent/guardian using only authorized aggregate data.',
      'Do not diagnose the child and do not infer hidden mental state.',
      'Give concrete, low-pressure family support ideas and questions the parent can ask.',
      'If safety.open_urgent_count is above zero, prioritize immediate trusted-human support and local emergency resources.',
      `Authorized summary: ${JSON.stringify(context)}`,
      `Parent question: ${question}`,
    ].join('\n');

    const klass =
      Number(context.safety.open_urgent_count ?? 0) > 0
        ? 'urgent_review'
        : safetyClass(question);
    const advice = await providerGuide('wellbeing', prompt, klass);

    await pool.query(
      `insert into access_audit(actor_user_id,family_id,action,target_type,target_id,metadata)
       values($1,$2,'parent.family_guidance.request','student',$3,$4::jsonb)`,
      [
        req.identity.sub,
        req.params.familyId,
        req.params.minorUserId,
        JSON.stringify({ rawNotesIncluded: false, rawConversationIncluded: false }),
      ],
    );

    res.json({
      advice,
      summary: context,
      advisory: true,
      medicalDiagnosis: false,
      rawNotesIncluded: false,
      rawConversationIncluded: false,
    });
  });

  router.post('/ai/sessions', async (req, res) => {
    const kind = ['study', 'planner', 'wellbeing'].includes(req.body.kind)
      ? req.body.kind
      : null;
    if (!kind) return res.status(400).json({ error: 'invalid_kind' });
    if (kind === 'wellbeing' && !sensitiveEnabled) return res.status(503).json({ error: 'sensitive_features_disabled' });
    const result = await pool.query(
      'insert into ai_guide_session(owner_user_id,guide_kind) values($1,$2) returning *',
      [req.identity.sub, kind],
    );
    res.status(201).json(result.rows[0]);
  });

  router.post('/ai/sessions/:id/messages', async (req, res) => {
    const text = clampText(req.body.message);
    if (!text) return res.status(400).json({ error: 'invalid_input' });
    const session = await pool.query(
      "select * from ai_guide_session where id=$1 and owner_user_id=$2 and status='active'",
      [req.params.id, req.identity.sub],
    );
    if (!session.rowCount) return res.status(404).json({ error: 'session_not_found' });
    if (session.rows[0].guide_kind === 'wellbeing' && !sensitiveEnabled) return res.status(503).json({ error: 'sensitive_features_disabled' });

    const klass = safetyClass(text);
    await pool.query(
      "insert into ai_guide_message(session_id,author,body,safety_class) values($1,'user',$2,$3)",
      [req.params.id, text, klass],
    );
    if (klass === 'urgent_review' && sensitiveEnabled) {
      await pool.query(
        "insert into wellbeing_safety_event(owner_user_id,source_session_id,severity) values($1,$2,'urgent_review')",
        [req.identity.sub, req.params.id],
      );
    }

    const reply = await providerGuide(session.rows[0].guide_kind, text, klass);
    const result = await pool.query(
      "insert into ai_guide_message(session_id,author,body,safety_class) values($1,'assistant',$2,$3) returning id,body,safety_class,created_at",
      [req.params.id, reply, klass],
    );
    res.json({
      ...result.rows[0],
      advisory: true,
      medicalDiagnosis: false,
      automaticAction: false,
      providerMode: 'local_fallback',
    });
  });

  router.post('/ai/proposals', async (req, res) => {
    const title = clampText(req.body.title, 240);
    if (!title || !req.body.proposal || typeof req.body.proposal !== 'object') {
      return res.status(400).json({ error: 'invalid_input' });
    }
    if (req.body.sessionId) {
      const session = await pool.query('select guide_kind from ai_guide_session where id=$1 and owner_user_id=$2', [req.body.sessionId, req.identity.sub]);
      if (!session.rowCount) return res.status(403).json({ error: 'session_forbidden' });
      if (session.rows[0].guide_kind === 'wellbeing' && !sensitiveEnabled) return res.status(503).json({ error: 'sensitive_features_disabled' });
    }
    const result = await pool.query(
      'insert into ai_plan_proposal(owner_user_id,session_id,title,proposal) values($1,$2,$3,$4) returning *',
      [req.identity.sub, req.body.sessionId || null, title, req.body.proposal],
    );
    res.status(201).json(result.rows[0]);
  });

  router.patch('/ai/proposals/:id', async (req, res) => {
    const status = ['accepted', 'rejected'].includes(req.body.status)
      ? req.body.status
      : null;
    if (!status) return res.status(400).json({ error: 'invalid_status' });
    const proposal = await pool.query(
      `select s.guide_kind from ai_plan_proposal p
       left join ai_guide_session s on s.id=p.session_id
       where p.id=$1 and p.owner_user_id=$2 and p.status='proposed'`,
      [req.params.id, req.identity.sub],
    );
    if (!proposal.rowCount) return res.status(404).json({ error: 'proposal_not_found' });
    if (proposal.rows[0].guide_kind === 'wellbeing' && !sensitiveEnabled) return res.status(503).json({ error: 'sensitive_features_disabled' });
    const result = await pool.query(
      "update ai_plan_proposal set status=$3,decided_at=now() where id=$1 and owner_user_id=$2 and status='proposed' returning *",
      [req.params.id, req.identity.sub, status],
    );
    if (!result.rowCount) return res.status(404).json({ error: 'proposal_not_found' });
    res.json(result.rows[0]);
  });

  return router;
}
