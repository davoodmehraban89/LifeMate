import test, { after } from 'node:test';
import assert from 'node:assert/strict';
// Explicit synthetic opt-in; NODE_ENV=test never enables sensitive APIs itself.
process.env.ENABLE_SENSITIVE_FEATURES = 'true';
const { app, pool } = await import('../src/server.js');

const server = app.listen(0);
const address = server.address();
const base = `http://127.0.0.1:${address.port}`;

after(async () => {
  await new Promise((resolve) => server.close(resolve));
  await pool.end();
});

async function request(path, { method = 'GET', body, token } = {}) {
  const response = await fetch(base + path, {
    method,
    headers: {
      'content-type': 'application/json',
      ...(token ? { authorization: `Bearer ${token}` } : {}),
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await response.text();
  return {
    status: response.status,
    body: text ? JSON.parse(text) : null,
  };
}

async function registerVerified(email, displayName) {
  const password = 'Phase4Pass!123';
  const registration = await request('/v1/auth/register', {
    method: 'POST',
    body: { email, displayName, password },
  });
  assert.equal(registration.status, 201);
  assert.equal(
    (
      await request('/v1/auth/verify-email', {
        method: 'POST',
        body: { token: registration.body.verificationToken, newPassword: password },
      })
    ).status,
    204,
  );
  const login = await request('/v1/auth/login', {
    method: 'POST',
    body: { email, password },
  });
  assert.equal(login.status, 200);
  return { token: login.body.accessToken, userId: registration.body.userId };
}

test('phase 4 learning wellbeing and guardian safety boundaries', async () => {
  const suffix = Date.now().toString(36);
  const parentEmail = `p4-parent-${suffix}@example.test`;
  const teenEmail = `p4-teen-${suffix}@example.test`;
  const outsiderEmail = `p4-outsider-${suffix}@example.test`;

  const parent = await registerVerified(parentEmail, 'Phase4 Parent');
  const teen = await registerVerified(teenEmail, 'Phase4 Teen');
  const outsider = await registerVerified(outsiderEmail, 'Phase4 Outsider');

  const family = await request('/v1/families', {
    method: 'POST',
    token: parent.token,
    body: { name: 'Phase4 Family', role: 'parent_guardian' },
  });
  assert.equal(family.status, 201);

  const invitation = await request(`/v1/families/${family.body.id}/invitations`, {
    method: 'POST',
    token: parent.token,
    body: {
      email: teenEmail,
      role: 'teen_minor',
      themePreference: 'girl_pink',
    },
  });
  assert.equal(invitation.status, 201);

  assert.equal(
    (
      await request('/v1/invitations/accept', {
        method: 'POST',
        token: teen.token,
        body: { token: invitation.body.invitationToken },
      })
    ).status,
    204,
  );

  assert.equal(
    (
      await request(`/v1/families/${family.body.id}/guardians`, {
        method: 'POST',
        token: parent.token,
        body: {
          guardianUserId: parent.userId,
          minorUserId: teen.userId,
        },
      })
    ).status,
    204,
  );

  const goal = await request('/v1/learning/goals', {
    method: 'POST',
    token: teen.token,
    body: { title: 'تسلط روی جبر', target: 'حل تمرین‌های فصل اول' },
  });
  assert.equal(goal.status, 201);

  const learningCheckin = await request('/v1/learning/checkins', {
    method: 'POST',
    token: teen.token,
    body: {
      learningGoalId: goal.body.id,
      confidence: 3,
      difficulty: 4,
      note: 'تمرین بیشتری لازم دارم',
    },
  });
  assert.equal(learningCheckin.status, 201);

  const privateCheckin = await request('/v1/wellbeing/checkins', {
    method: 'POST',
    token: teen.token,
    body: {
      mood: 3,
      energy: 2,
      stress: 4,
      note: 'این متن خصوصی است',
      visibility: 'private',
    },
  });
  assert.equal(privateCheckin.status, 201);
  assert.equal(Object.hasOwn(privateCheckin.body, 'note'), false);

  const sharedCheckin = await request('/v1/wellbeing/checkins', {
    method: 'POST',
    token: teen.token,
    body: {
      mood: 4,
      energy: 3,
      stress: 2,
      note: 'این متن هم نباید به والد برگردد',
      visibility: 'guardian_summary',
    },
  });
  assert.equal(sharedCheckin.status, 201);
  assert.equal(Object.hasOwn(sharedCheckin.body, 'note'), false);

  const ownCheckins = await request('/v1/wellbeing/checkins', {
    token: teen.token,
  });
  assert.equal(ownCheckins.status, 200);
  assert.equal(ownCheckins.body.items.length >= 2, true);
  assert.equal(
    ownCheckins.body.items.some((item) => Object.hasOwn(item, 'note')),
    false,
  );

  const guardianSummary = await request(
    `/v1/families/${family.body.id}/children/${teen.userId}/wellbeing-summary`,
    { token: parent.token },
  );
  assert.equal(guardianSummary.status, 200);
  assert.equal(guardianSummary.body.summary.checkin_count, 1);
  assert.equal(guardianSummary.body.rawNotesIncluded, false);
  assert.equal(guardianSummary.body.rawConversationIncluded, false);

  const outsiderSummary = await request(
    `/v1/families/${family.body.id}/children/${teen.userId}/wellbeing-summary`,
    { token: outsider.token },
  );
  assert.equal(outsiderSummary.status, 403);

  const familyGuidance = await request(
    `/v1/families/${family.body.id}/children/${teen.userId}/family-guidance`,
    {
      method: 'POST',
      token: parent.token,
      body: { question: 'چطور بدون فشار حمایتش کنم؟' },
    },
  );
  assert.equal(familyGuidance.status, 200);
  assert.equal(familyGuidance.body.advisory, true);
  assert.equal(familyGuidance.body.medicalDiagnosis, false);
  assert.equal(familyGuidance.body.rawNotesIncluded, false);
  assert.equal(familyGuidance.body.rawConversationIncluded, false);

  const outsiderGuidance = await request(
    `/v1/families/${family.body.id}/children/${teen.userId}/family-guidance`,
    {
      method: 'POST',
      token: outsider.token,
      body: { question: 'وضعیت چیست؟' },
    },
  );
  assert.equal(outsiderGuidance.status, 403);

  const session = await request('/v1/ai/sessions', {
    method: 'POST',
    token: teen.token,
    body: { kind: 'wellbeing' },
  });
  assert.equal(session.status, 201);

  const ordinary = await request(`/v1/ai/sessions/${session.body.id}/messages`, {
    method: 'POST',
    token: teen.token,
    body: { message: 'امروز کمی استرس دارم' },
  });
  assert.equal(ordinary.status, 200);
  assert.equal(ordinary.body.advisory, true);
  assert.equal(ordinary.body.medicalDiagnosis, false);
  assert.equal(ordinary.body.automaticAction, false);

  const urgent = await request(`/v1/ai/sessions/${session.body.id}/messages`, {
    method: 'POST',
    token: teen.token,
    body: { message: 'به خودکشی فکر می‌کنم' },
  });
  assert.equal(urgent.status, 200);
  assert.equal(urgent.body.safety_class, 'urgent_review');

  const safetySummary = await request(
    `/v1/families/${family.body.id}/children/${teen.userId}/wellbeing-summary`,
    { token: parent.token },
  );
  assert.equal(safetySummary.status, 200);
  assert.equal(safetySummary.body.safety.open_urgent_count >= 1, true);
});
