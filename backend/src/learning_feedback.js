import crypto from 'node:crypto';
import express from 'express';

const uuid = value => typeof value === 'string' &&
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
const categories = new Set(['inaccurate', 'edition_mismatch', 'broken_video', 'unclear', 'topic_request']);
const submissionFields = new Set(['mutationId', 'unitId', 'category', 'summary', 'shareWithContentTeam']);

export function normalizeFeedbackSubmission(body) {
  if (!body || typeof body !== 'object' || Array.isArray(body) ||
      Object.keys(body).some(key => !submissionFields.has(key)) ||
      !uuid(body.mutationId) || (body.unitId != null && !uuid(body.unitId)) ||
      !categories.has(body.category) || body.shareWithContentTeam !== true ||
      typeof body.summary !== 'string' || Array.from(body.summary).length > 1000 ||
      !body.summary.trim() || body.summary.includes('\u0000')) return null;
  return {
    mutationId: body.mutationId.toLowerCase(),
    unitId: body.unitId?.toLowerCase() ?? null,
    category: body.category,
    summary: body.summary.trim(),
    shareWithContentTeam: true,
  };
}

async function transaction(pool, operation) {
  const client = await pool.connect();
  try {
    await client.query('begin');
    const result = await operation(client);
    await client.query('commit');
    return result;
  } catch (error) {
    await client.query('rollback').catch(() => {});
    throw error;
  } finally { client.release(); }
}

function feedbackBody(row) {
  return {
    id: row.id,
    mutationId: row.mutation_id,
    unitId: row.unit_id,
    category: row.category,
    summary: row.summary,
    shareWithContentTeam: row.share_with_content_team,
    status: row.status,
    version: row.version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    withdrawnAt: row.withdrawn_at,
  };
}

function acknowledgement(row, status) {
  return { feedback: feedbackBody(row),
    acknowledgement: { mutationId: row.mutation_id, feedbackId: row.id, status } };
}

async function activeOwnerLock(client, owner) {
  const result = await client.query(
    'select id from app_user where id=$1 and disabled_at is null for update', [owner]);
  return result.rowCount > 0;
}

export function createLearningFeedbackRouter({ pool, auth }) {
  const router = express.Router();

  router.post('/education/feedback', auth, async (req, res) => {
    const body = normalizeFeedbackSubmission(req.body);
    if (!body || Object.keys(req.query).length) return res.status(400).json({ error: 'invalid_feedback' });
    const owner = req.identity.sub;
    const digest = crypto.createHash('sha256').update(JSON.stringify(body)).digest('hex');
    const result = await transaction(pool, async client => {
      // One durable owner lock serializes duplicate claims and rolling quota.
      // No IP-based identity, in-memory counter or family/admin override exists.
      if (!await activeOwnerLock(client, owner)) return { status: 401, body: { error: 'session_invalid' } };
      const previous = await client.query(
        'select * from learning_content_feedback where owner_user_id=$1 and mutation_id=$2',
        [owner, body.mutationId]);
      if (previous.rowCount) {
        const row = previous.rows[0];
        if (row.request_hash !== digest) return { status: 409, body: { error: 'mutation_id_reused' } };
        // Serialize current state, not the original response: a withdrawn
        // summary/consent can never be restored or leaked by a valid retry.
        return { status: 200, body: acknowledgement(row, 'already_applied') };
      }
      if (body.unitId != null) {
        const unit = await client.query('select id from learning_unit where id=$1', [body.unitId]);
        if (!unit.rowCount) return { status: 404, body: { error: 'learning_unit_not_found' } };
      }
      const quota = (await client.query(
        `select count(*) filter(where created_at>now()-interval '1 hour')::int as hour_count,
           count(*)::int as day_count,
           ceil(extract(epoch from ((min(created_at) filter(where created_at>now()-interval '1 hour'))
             +interval '1 hour'-now())))::int as hour_wait,
           ceil(extract(epoch from (min(created_at)+interval '1 day'-now())))::int as day_wait
         from learning_content_feedback where owner_user_id=$1 and created_at>now()-interval '1 day'`,
        [owner])).rows[0];
      const wait = Math.max(quota.hour_count >= 5 ? quota.hour_wait : 0,
        quota.day_count >= 20 ? quota.day_wait : 0);
      if (wait > 0) return { status: 429, retryAfter: Math.max(1, wait), body: { error: 'feedback_rate_limited' } };
      const inserted = await client.query(
        `insert into learning_content_feedback(owner_user_id,mutation_id,request_hash,unit_id,category,summary,share_with_content_team)
         values($1,$2,$3,$4,$5,$6,true) returning *`,
        [owner, body.mutationId, digest, body.unitId, body.category, body.summary]);
      return { status: 201, body: acknowledgement(inserted.rows[0], 'accepted') };
    });
    if (result.retryAfter) res.setHeader('Retry-After', String(result.retryAfter));
    res.status(result.status).json(result.body);
  });

  router.get('/me/education-feedback', auth, async (req, res) => {
    const cursor = req.query.cursor ?? null;
    if (Object.keys(req.query).some(key => key !== 'cursor') ||
        (cursor !== null && !uuid(cursor))) return res.status(400).json({ error: 'invalid_feedback_query' });
    const owner = req.identity.sub;
    if (cursor !== null) {
      const known = await pool.query(
        'select id from learning_content_feedback where owner_user_id=$1 and id=$2', [owner, cursor]);
      if (!known.rowCount) return res.status(404).json({ error: 'feedback_not_found' });
    }
    // Compare PostgreSQL timestamps in PostgreSQL, preserving microseconds.
    // A parsed JavaScript Date cursor could skip rows from the same millisecond.
    const rows = (await pool.query(
      `select f.* from learning_content_feedback f where f.owner_user_id=$1
       and ($2::uuid is null or (f.created_at,f.id)<
         (select created_at,id from learning_content_feedback where owner_user_id=$1 and id=$2))
       order by f.created_at desc,f.id desc limit 101`, [owner, cursor])).rows;
    res.json({ feedback: rows.slice(0, 100).map(feedbackBody),
      nextCursor: rows.length > 100 ? rows[99].id : null });
  });

  router.delete('/me/education-feedback/:id', auth, async (req, res) => {
    if (!uuid(req.params.id) || Object.keys(req.query).length ||
        (req.body != null && (typeof req.body !== 'object' || Array.isArray(req.body) || Object.keys(req.body).length))) {
      return res.status(400).json({ error: 'invalid_feedback' });
    }
    const status = await transaction(pool, async client => {
      if (!await activeOwnerLock(client, req.identity.sub)) return 401;
      const found = await client.query(
        'select withdrawn_at from learning_content_feedback where owner_user_id=$1 and id=$2 for update',
        [req.identity.sub, req.params.id]);
      if (!found.rowCount) return 404;
      if (!found.rows[0].withdrawn_at) await client.query(
        `update learning_content_feedback set summary=null,share_with_content_team=false,
         withdrawn_at=now(),updated_at=now(),version=version+1 where owner_user_id=$1 and id=$2`,
        [req.identity.sub, req.params.id]);
      return 204;
    });
    if (status === 204) return res.status(204).end();
    res.status(status).json({ error: status === 401 ? 'session_invalid' : 'feedback_not_found' });
  });

  return router;
}
