import test, { describe, before, after } from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import net from 'node:net';
import pg from 'pg';
import jwt from 'jsonwebtoken';
import { normalizeFeedbackSubmission } from '../src/learning_feedback.js';

const uuid = () => crypto.randomUUID();
const submission = (extra = {}) => ({ mutationId: uuid(), unitId: null,
  category: 'topic_request', summary: 'Synthetic content feedback, no private data.',
  shareWithContentTeam: true, ...extra });

test('feedback submission needs explicit consent and rejects private/owner attachments', () => {
  for (const consent of [undefined, null, false, 'true', 1]) {
    assert.equal(normalizeFeedbackSubmission(submission({ shareWithContentTeam: consent })), null);
  }
  for (const key of ['ownerUserId', 'childId', 'chat', 'conversationId', 'notes', 'health', 'status']) {
    assert.equal(normalizeFeedbackSubmission(submission({ [key]: 'not accepted' })), null, key);
  }
});

test('feedback summary is bounded plain text, with canonical owner-scoped UUID payload', () => {
  const mutationId = uuid(), unitId = uuid();
  const valid = normalizeFeedbackSubmission(submission({
    mutationId: mutationId.toUpperCase(), unitId: unitId.toUpperCase(), summary: '  توضیح انتخاب‌شده  '
  }));
  assert.equal(valid.mutationId, mutationId);
  assert.equal(valid.unitId, unitId);
  assert.equal(valid.summary, 'توضیح انتخاب‌شده');
  assert.equal(valid.shareWithContentTeam, true);
  assert.ok(normalizeFeedbackSubmission(submission({ summary: '🙂'.repeat(1000) })));
  for (const summary of ['', '  ', 123, null, 'a'.repeat(1001), '🙂'.repeat(1001), 'bad\u0000value']) {
    assert.equal(normalizeFeedbackSubmission(submission({ summary })), null);
  }
  for (const body of [null, [], { ...submission(), mutationId: 'bad' },
    { ...submission(), unitId: 'bad' }, { ...submission(), category: 'diagnosis' }]) {
    assert.equal(normalizeFeedbackSubmission(body), null);
  }
});

describe('learning feedback authenticated real HTTP and synthetic PostgreSQL', { concurrency: false }, () => {
  const serviceEnv = {...process.env}; delete serviceEnv.TEST_FIXTURE_DATABASE_URL;
  let pool, child, base;
  let output = '', errors = '';
  const users = [], families = [];

  async function start() {
    const reservation = net.createServer().listen(0, '127.0.0.1');
    await once(reservation, 'listening');
    const port = reservation.address().port;
    await new Promise(resolve => reservation.close(resolve));
    base = `http://127.0.0.1:${port}`;
    let startup = '';
    child = spawn(process.execPath, ['src/entrypoint.js'], {
      env: { ...serviceEnv, NODE_ENV: 'production', PORT: String(port),
        SMS_PROVIDER: 'disabled', SMS_PROVIDER_URL: '', SMS_PROVIDER_TOKEN: '',
        EMAIL_FROM: '', RESEND_API_KEY: '', SMTP_HOST: '', SMTP_USER: '', SMTP_PASSWORD: '',
        AI_API_KEY: '', AI_BASE_URL: '', AI_MODEL: '', OPENAI_API_KEY: '',
        CORS_ORIGINS: '', TRUSTED_PROXY_CIDRS: '', ENABLE_SENSITIVE_FEATURES: 'false',
        RATE_LIMIT_AUTH_MAX: '2000', RATE_LIMIT_GENERAL_MAX: '8000', RATE_LIMIT_AI_MAX: '2000' },
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    child.stdout.on('data', chunk => { output += chunk.toString(); startup += chunk.toString(); });
    child.stderr.on('data', chunk => { errors += chunk.toString(); });
    await new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('Feedback fixture startup timed out')), 10000);
      const onData = () => {
        if (!startup.includes('"type":"startup"')) return;
        clearTimeout(timer); child.stdout.off('data', onData); resolve();
      };
      child.stdout.on('data', onData);
      child.once('error', () => { clearTimeout(timer); reject(new Error('Feedback fixture start failed')); });
      child.once('exit', () => {
        if (!startup.includes('"type":"startup"')) {
          clearTimeout(timer); reject(new Error('Feedback fixture exited before startup'));
        }
      });
    });
  }

  async function stop() {
    if (child && child.exitCode === null && child.signalCode === null) {
      const closed = once(child, 'close'); child.kill('SIGTERM'); await closed;
    }
  }

  before(async () => {
    assert.ok(process.env.DATABASE_URL && process.env.JWT_SECRET?.length >= 32,
      'Feedback tests require a migrated synthetic PostgreSQL fixture and JWT secret');
    const location = new URL(process.env.TEST_FIXTURE_DATABASE_URL ?? process.env.DATABASE_URL);
    assert.ok(['localhost', '127.0.0.1', '[::1]', '::1'].includes(location.hostname),
      'Feedback tests refuse a nonlocal database');
    // Keep the local-host gate above. The workflow's existing synthetic database
    // has a protocol/history name; admitting that exact name does not admit arbitrary DBs.
    assert.ok(location.pathname.includes('test') || location.pathname === '/lifemate_ci' ||
      /^\/lifeguide_roles_source_[a-f0-9]{16}$/.test(location.pathname),
    'Feedback tests require an explicit synthetic test database');
    pool = new pg.Pool({ connectionString: process.env.TEST_FIXTURE_DATABASE_URL ?? process.env.DATABASE_URL });
    await start();
  });

  after(async () => {
    await stop();
    if (!pool) return;
    try {
      await pool.query('delete from access_audit where family_id=any($1::uuid[]) or actor_user_id=any($2::uuid[])', [families, users]);
      await pool.query('delete from family_workspace where id=any($1::uuid[])', [families]);
      await pool.query('delete from app_user where id=any($1::uuid[])', [users]);
    } finally { await pool.end(); }
  });

  async function actor() {
    const id = uuid(), sid = uuid();
    users.push(id);
    await pool.query('insert into app_user(id,identity_subject,email_normalized,email_verified_at) values($1,$2,$3,now())',
      [id, `feedback-fixture:${id}`, `feedback-${id}@example.test`]);
    await pool.query("insert into profile(user_id,display_name,theme_preference) values($1,'Synthetic Feedback User','adult_blue')", [id]);
    await pool.query("insert into auth_session(id,user_id,refresh_digest,expires_at) values($1,$2,$3,now()+interval '1 day')",
      [sid, id, crypto.randomBytes(32).toString('hex')]);
    return { id, sid, token: jwt.sign({ sub: id, sid, aud: 'lifemate-api' }, process.env.JWT_SECRET,
      { issuer: 'lifemate', expiresIn: '15m' }) };
  }

  async function request(path, { method = 'GET', user, body } = {}) {
    const response = await fetch(base + path, { method,
      headers: { 'content-type': 'application/json', ...(user ? { authorization: `Bearer ${user.token}` } : {}) },
      body: body === undefined ? undefined : JSON.stringify(body) });
    const text = await response.text();
    return { status: response.status,
      body: text && response.headers.get('content-type')?.includes('application/json') ? JSON.parse(text) : text || null,
      retryAfter: response.headers.get('retry-after') };
  }
  const post = (user, body) => request('/v1/education/feedback', { method: 'POST', user, body });
  const list = (user, query = '') => request('/v1/me/education-feedback' + query, { user });

  test('authentication, consent and strict request bounds reject without storing', async () => {
    const user = await actor();
    assert.equal((await post(undefined, submission())).status, 401);
    assert.equal((await list(undefined)).status, 401);
    assert.equal((await request(`/v1/me/education-feedback/${uuid()}`, { method: 'DELETE' })).status, 401);
    for (const body of [submission({ shareWithContentTeam: false }), submission({ summary: 'a'.repeat(1001) }),
      submission({ summary: 'bad\u0000text' }), submission({ ownerUserId: user.id }), submission({ childId: user.id }),
      submission({ chat: 'PRIVATE-CHAT-MUST-NOT-BE-ATTACHED' }), submission({ unitId: 'invalid' })]) {
      assert.equal((await post(user, body)).status, 400);
    }
    assert.equal((await post(user, submission({ unitId: uuid() }))).status, 404);
    assert.equal((await pool.query('select count(*)::int n from learning_content_feedback where owner_user_id=$1', [user.id])).rows[0].n, 0);
    await pool.query('update auth_session set revoked_at=now() where id=$1', [user.sid]);
    assert.equal((await post(user, submission())).status, 401);
  });

  test('real submission stores only chosen text and an existing draft unit can be referenced', async () => {
    const user = await actor();
    // The assessment suite creates ephemeral units concurrently. Selecting any
    // global minimum UUID may bind this feedback row to another suite's unit and
    // make that suite's fixture teardown fail with a foreign-key violation.
    // Use the deterministic checked public-catalogue row imported by CI.
    const units = await pool.query(`select u.id from learning_unit u
      join textbook_catalog t on t.id=u.textbook_id
      where t.book_code='101' and t.source_url='http://www.chap.sch.ir/books/14142'
      order by u.order_index,u.id limit 1`);
    assert.equal(units.rowCount, 1, 'Seeded primary catalogue unit must exist');
    const body = submission({ unitId: units.rows[0].id, category: 'unclear', summary: '<b>SYNTHETIC-CHOSEN-FEEDBACK</b>' });
    const created = await post(user, body);
    assert.equal(created.status, 201);
    assert.equal(created.body.feedback.summary, body.summary);
    assert.equal(created.body.feedback.unitId, body.unitId);
    assert.equal(created.body.feedback.status, 'received');
    assert.equal(created.body.feedback.version, 1);
    assert.deepEqual(created.body.acknowledgement,
      { mutationId: body.mutationId, feedbackId: created.body.feedback.id, status: 'accepted' });
    const stored = (await pool.query('select * from learning_content_feedback where id=$1', [created.body.feedback.id])).rows[0];
    assert.equal(stored.owner_user_id, user.id);
    assert.equal(stored.summary, body.summary);
    assert.equal(stored.request_hash.length, 64);
    const own = await list(user);
    assert.equal(own.status, 200);
    assert.equal(own.body.feedback.length, 1);
    assert.equal(own.body.feedback[0].id, stored.id);
    assert.ok(!JSON.stringify(own.body).includes(user.id));
    assert.ok(!JSON.stringify(own.body).includes('request_hash'));
  });

  test('concurrent stable mutations make one row; changed UUID reuse conflicts and another owner is isolated', async () => {
    const user = await actor(), other = await actor(), body = submission();
    const results = await Promise.all([post(user, body), post(user, body), post(user, body)]);
    assert.deepEqual(results.map(r => r.status).sort(), [200, 200, 201]);
    assert.equal(new Set(results.map(r => r.body.feedback.id)).size, 1);
    assert.equal((await post(user, { ...body, summary: 'Different chosen summary' })).status, 409);
    assert.equal((await pool.query('select count(*)::int n from learning_content_feedback where owner_user_id=$1 and mutation_id=$2', [user.id, body.mutationId])).rows[0].n, 1);
    const otherResult = await post(other, body);
    assert.equal(otherResult.status, 201);
    assert.notEqual(otherResult.body.feedback.id, results[0].body.feedback.id);
  });

  test('family admin/guardian and outsider cannot read or withdraw child feedback; private records never attach', async () => {
    const minor = await actor(), parent = await actor(), outsider = await actor();
    const family = uuid(); families.push(family);
    await pool.query("insert into family_workspace(id,name,created_by) values($1,'Synthetic Feedback Family',$2)", [family, parent.id]);
    await pool.query("insert into family_membership(family_id,user_id,role,is_admin) values($1,$2,'parent_guardian',true),($1,$3,'teen_minor',false)", [family, parent.id, minor.id]);
    await pool.query('insert into guardian_relationship(family_id,guardian_user_id,minor_user_id) values($1,$2,$3)', [family, parent.id, minor.id]);
    await pool.query("insert into plan_item(owner_user_id,kind,title,notes) values($1,'task','Private synthetic task','PRIVATE-NOTE-FEEDBACK-SENTINEL')", [minor.id]);
    await pool.query("insert into wellbeing_checkin(owner_user_id,mood,note) values($1,3,'PRIVATE-HEALTH-FEEDBACK-SENTINEL')", [minor.id]);
    const conversation = (await pool.query("insert into ai_guide_session(owner_user_id,guide_kind) values($1,'study') returning id", [minor.id])).rows[0].id;
    await pool.query("insert into ai_guide_message(session_id,author,body) values($1,'user','PRIVATE-CHAT-FEEDBACK-SENTINEL')", [conversation]);
    const created = await post(minor, submission());
    assert.equal(created.status, 201);
    for (const user of [parent, outsider]) {
      assert.deepEqual((await list(user)).body.feedback, []);
      assert.equal((await list(user, `?childId=${minor.id}`)).status, 400);
      assert.equal((await list(user, `?ownerUserId=${minor.id}`)).status, 400);
      assert.equal((await list(user, `?cursor=${created.body.feedback.id}`)).status, 404);
      assert.equal((await request(`/v1/me/education-feedback/${created.body.feedback.id}`, { method: 'DELETE', user })).status, 404);
    }
    assert.equal((await request('/v1/education/feedback', { user: parent })).status, 404);
    const visible = JSON.stringify((await list(minor)).body) + JSON.stringify(created.body);
    for (const sentinel of ['PRIVATE-NOTE-FEEDBACK-SENTINEL', 'PRIVATE-HEALTH-FEEDBACK-SENTINEL', 'PRIVATE-CHAT-FEEDBACK-SENTINEL']) {
      assert.ok(!visible.includes(sentinel));
      assert.ok(!output.includes(sentinel));
      assert.ok(!errors.includes(sentinel));
    }
  });

  test('withdrawal redacts the stored text; retries return tombstone and never restore consent', async () => {
    const user = await actor(), body = submission({ summary: 'SYNTHETIC-TO-WITHDRAW' });
    const created = await post(user, body), id = created.body.feedback.id;
    const original = (await pool.query('select request_hash from learning_content_feedback where id=$1', [id])).rows[0].request_hash;
    const path = `/v1/me/education-feedback/${id}`;
    assert.equal((await request(path, { method: 'DELETE', user })).status, 204);
    assert.equal((await request(path, { method: 'DELETE', user })).status, 204);
    const stored = (await pool.query('select * from learning_content_feedback where id=$1', [id])).rows[0];
    assert.equal(stored.summary, null); assert.equal(stored.share_with_content_team, false);
    assert.ok(stored.withdrawn_at); assert.equal(stored.version, 2); assert.equal(stored.request_hash, original);
    const replay = await post(user, body);
    assert.equal(replay.status, 200); assert.equal(replay.body.feedback.id, id);
    assert.equal(replay.body.feedback.summary, null); assert.equal(replay.body.feedback.shareWithContentTeam, false);
    assert.equal(replay.body.acknowledgement.status, 'already_applied');
    assert.ok(!JSON.stringify(replay.body).includes(body.summary));
    assert.equal((await post(user, { ...body, summary: 'New summary with old UUID' })).status, 409);
    assert.equal((await request(`/v1/me/education-feedback/${uuid()}`, { method: 'DELETE', user })).status, 404);
  });

  test('per-user hourly quota is atomic, survives process restart, and retries/withdrawal cannot bypass it', async () => {
    const user = await actor(), other = await actor();
    const bodies = Array.from({ length: 6 }, () => submission());
    const created = await Promise.all(bodies.map(body => post(user, body)));
    assert.equal(created.filter(r => r.status === 201).length, 5);
    assert.equal(created.filter(r => r.status === 429).length, 1);
    const limited = created.find(r => r.status === 429);
    assert.ok(Number(limited.retryAfter) > 0 && Number(limited.retryAfter) <= 3600);
    const index = created.findIndex(r => r.status === 201), original = created[index].body.feedback;
    await stop(); await start();
    const replay = await post(user, bodies[index]);
    assert.equal(replay.status, 200); assert.deepEqual(replay.body.feedback, original);
    assert.equal((await post(user, submission())).status, 429);
    assert.equal((await request(`/v1/me/education-feedback/${original.id}`, { method: 'DELETE', user })).status, 204);
    assert.equal((await post(user, submission())).status, 429);
    assert.equal((await post(other, submission())).status, 201);
    assert.equal((await pool.query('select count(*)::int n from learning_content_feedback where owner_user_id=$1', [user.id])).rows[0].n, 5);
  });

  test('rolling daily quota uses persisted rows even when hourly windows have expired', async () => {
    const user = await actor();
    for (let batch = 1; batch <= 4; batch++) {
      const ids = [];
      for (let n = 0; n < 5; n++) {
        const made = await post(user, submission({ summary: `Synthetic daily feedback ${batch}-${n}` }));
        assert.equal(made.status, 201); ids.push(made.body.feedback.id);
      }
      // Only synthetic fixture timestamps advance the window; no production clock override.
      await pool.query("update learning_content_feedback set created_at=now()-($1 || ' hours')::interval where id=any($2::uuid[])", [String(batch * 2), ids]);
    }
    const limited = await post(user, submission());
    assert.equal(limited.status, 429);
    assert.ok(Number(limited.retryAfter) > 3600 && Number(limited.retryAfter) <= 86400);
    assert.equal((await pool.query('select count(*)::int n from learning_content_feedback where owner_user_id=$1', [user.id])).rows[0].n, 20);
  });

  test('cursor paging stays in caller scope, bounds rows and preserves microsecond page boundaries', async () => {
    const user = await actor();
    const a = await post(user, submission()), b = await post(user, submission());
    assert.equal(a.status, 201); assert.equal(b.status, 201);
    const first = await list(user);
    assert.deepEqual(first.body.feedback.map(row => row.id), [b.body.feedback.id, a.body.feedback.id]);
    const second = await list(user, `?cursor=${b.body.feedback.id}`);
    assert.deepEqual(second.body.feedback.map(row => row.id), [a.body.feedback.id]);
    assert.equal(second.body.nextCursor, null);
    assert.equal((await list(user, '?cursor=bad')).status, 400);
    assert.equal((await list(user, '?includePrivateChat=true')).status, 400);
    // A bounded page must not round its cursor timestamp through JavaScript Date.
    // These older, synthetic records all occupy different microseconds of one millisecond.
    await pool.query(
      `insert into learning_content_feedback(owner_user_id,mutation_id,request_hash,category,summary,share_with_content_team,created_at)
       select $1,gen_random_uuid(),repeat('a',64),'topic_request','Synthetic pagination feedback',true,
         timestamptz '2000-01-01 00:00:00+00'+n*interval '1 microsecond'
       from generate_series(1,100) n`, [user.id]);
    const bounded = await list(user);
    assert.equal(bounded.body.feedback.length, 100);
    assert.ok(bounded.body.nextCursor);
    const tail = await list(user, `?cursor=${bounded.body.nextCursor}`);
    assert.equal(tail.body.feedback.length, 2);
    assert.equal(tail.body.nextCursor, null);
    assert.equal(new Set([...bounded.body.feedback, ...tail.body.feedback].map(row => row.id)).size, 102);
  });
});
