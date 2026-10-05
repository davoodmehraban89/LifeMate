import express from 'express';

const clampText = (value, max = 4000) =>
  String(value ?? '').trim().slice(0, max);

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
  if (klass === 'urgent_review') return localGuide(kind, text, klass);

  const apiKey = process.env.AI_API_KEY;
  const baseUrl = process.env.AI_BASE_URL;
  const model = process.env.AI_MODEL;
  if (!apiKey || !baseUrl || !model) {
    return localGuide(kind, text, klass);
  }

  const system = [
    'You are LifeMate, an age-appropriate Persian companion.',
    'You are advisory, not a doctor, therapist, diagnostician, or emergency service.',
    'For study, guide step-by-step and avoid simply giving final homework answers.',
    'For planning, propose realistic options and preserve user agency.',
    'For wellbeing, be calm, supportive, non-clinical, and encourage trusted human support when appropriate.',
    'Never claim to know hidden mental state. Never expose private content to parents.',
    `Guide mode: ${kind}`,
  ].join(' ');

  const response = await fetch(`${baseUrl.replace(/\/$/, '')}/chat/completions`, {
    method: 'POST',
    headers: {
      authorization: `Bearer ${apiKey}`,
      'content-type': 'application/json',
    },
    body: JSON.stringify({
      model,
      temperature: 0.4,
      messages: [
        { role: 'system', content: system },
        { role: 'user', content: text },
      ],
    }),
  });

  if (!response.ok) return localGuide(kind, text, klass);
  const body = await response.json();
  const content = body?.choices?.[0]?.message?.content;
  return clampText(content, 6000) || localGuide(kind, text, klass);
}

async function guardianRelationship(pool, familyId, guardianUserId, minorUserId) {
  const result = await pool.query(
    `select 1
       from guardian_relationship g
       join family_membership gm
         on gm.family_id=g.family_id
        and gm.user_id=g.guardian_user_id
        and gm.ended_at is null
       join family_membership mm
         on mm.family_id=g.family_id
        and mm.user_id=g.minor_user_id
        and mm.ended_at is null
      where g.family_id=$1
        and g.guardian_user_id=$2
        and g.minor_user_id=$3
        and g.active=true`,
    [familyId, guardianUserId, minorUserId],
  );
  return result.rowCount > 0;
}

export function createPhase4Router({ pool, auth }) {
  const router = express.Router();
  router.use(auth);

  router.post('/learning/goals', async (req, res) => {
    const title = clampText(req.body.title, 240);
    if (!title) return res.status(400).json({ error: 'invalid_input' });
    const result = await pool.query(
      'insert into learning_goal(owner_user_id,subject_id,title,target) values($1,$2,$3,$4) returning *',
      [
        req.identity.sub,
        req.body.subjectId || null,
        title,
        clampText(req.body.target, 1000) || null,
      ],
    );
    res.status(201).json(result.rows[0]);
  });

  router.get('/learning/goals', async (req, res) => {
    const result = await pool.query(
      "select * from learning_goal where owner_user_id=$1 and status<>'archived' order by created_at desc",
      [req.identity.sub],
    );
    res.json({ items: result.rows });
  });

  router.post('/learning/checkins', async (req, res) => {
    const confidence = Number(req.body.confidence);
    const difficulty = Number(req.body.difficulty);
    if (
      !Number.isInteger(confidence) ||
      confidence < 1 ||
      confidence > 5 ||
      !Number.isInteger(difficulty) ||
      difficulty < 1 ||
      difficulty > 5
    ) {
      return res.status(400).json({ error: 'invalid_input' });
    }
    const result = await pool.query(
      'insert into learning_checkin(owner_user_id,learning_goal_id,confidence,difficulty,note) values($1,$2,$3,$4,$5) returning *',
      [
        req.identity.sub,
        req.body.learningGoalId || null,
        confidence,
        difficulty,
        clampText(req.body.note, 2000) || null,
      ],
    );
    res.status(201).json(result.rows[0]);
  });

  router.post('/wellbeing/checkins', async (req, res) => {
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

  router.get('/wellbeing/checkins', async (req, res) => {
    const result = await pool.query(
      'select id,mood,energy,stress,visibility,created_at from wellbeing_checkin where owner_user_id=$1 order by created_at desc limit 30',
      [req.identity.sub],
    );
    res.json({ items: result.rows });
  });

  router.get('/families/:familyId/children/:minorUserId/wellbeing-summary', async (req, res) => {
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

  router.post('/ai/sessions', async (req, res) => {
    const kind = ['study', 'planner', 'wellbeing'].includes(req.body.kind)
      ? req.body.kind
      : null;
    if (!kind) return res.status(400).json({ error: 'invalid_kind' });
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

    const klass = safetyClass(text);
    await pool.query(
      "insert into ai_guide_message(session_id,author,body,safety_class) values($1,'user',$2,$3)",
      [req.params.id, text, klass],
    );
    if (klass === 'urgent_review') {
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
      providerMode: process.env.AI_API_KEY ? 'configured' : 'local_fallback',
    });
  });

  router.post('/ai/proposals', async (req, res) => {
    const title = clampText(req.body.title, 240);
    if (!title || !req.body.proposal || typeof req.body.proposal !== 'object') {
      return res.status(400).json({ error: 'invalid_input' });
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
    const result = await pool.query(
      "update ai_plan_proposal set status=$3,decided_at=now() where id=$1 and owner_user_id=$2 and status='proposed' returning *",
      [req.params.id, req.identity.sub, status],
    );
    if (!result.rowCount) return res.status(404).json({ error: 'proposal_not_found' });
    res.json(result.rows[0]);
  });

  return router;
}
