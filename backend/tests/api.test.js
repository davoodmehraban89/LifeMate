import test, { after } from 'node:test';
import assert from 'node:assert/strict';
import { app, pool } from '../src/server.js';

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

test('identity + family vertical slice', async () => {
  const suffix = Date.now().toString(36);
  const parentEmail = `parent-${suffix}@example.test`;
  const teenEmail = `teen-${suffix}@example.test`;
  const initialPassword = 'StrongPass!123';
  const changedPassword = 'StrongerPass!456';

  const parentRegister = await request('/v1/auth/register', {
    method: 'POST',
    body: {
      displayName: 'Parent',
      email: parentEmail,
      password: initialPassword,
    },
  });
  assert.equal(parentRegister.status, 201);
  assert.ok(parentRegister.body.verificationToken);

  const parentVerify = await request('/v1/auth/verify-email', {
    method: 'POST',
    body: { token: parentRegister.body.verificationToken },
  });
  assert.equal(parentVerify.status, 204);

  const parentLogin = await request('/v1/auth/login', {
    method: 'POST',
    body: { email: parentEmail, password: initialPassword },
  });
  assert.equal(parentLogin.status, 200);
  assert.ok(parentLogin.body.accessToken);
  assert.ok(parentLogin.body.refreshToken);

  const refreshed = await request('/v1/auth/refresh', {
    method: 'POST',
    body: { refreshToken: parentLogin.body.refreshToken },
  });
  assert.equal(refreshed.status, 200);
  assert.ok(refreshed.body.accessToken);
  assert.notEqual(refreshed.body.refreshToken, parentLogin.body.refreshToken);

  const profile = await request('/v1/profile', {
    token: refreshed.body.accessToken,
  });
  assert.equal(profile.status, 200);
  assert.equal(profile.body.display_name, 'Parent');

  const profileUpdate = await request('/v1/profile', {
    method: 'PATCH',
    token: refreshed.body.accessToken,
    body: { themePreference: 'adult_blue' },
  });
  assert.equal(profileUpdate.status, 200);
  assert.equal(profileUpdate.body.theme_preference, 'adult_blue');

  const family = await request('/v1/families', {
    method: 'POST',
    token: refreshed.body.accessToken,
    body: { name: 'Test Family', role: 'parent_guardian' },
  });
  assert.equal(family.status, 201);
  assert.ok(family.body.id);

  const teenRegister = await request('/v1/auth/register', {
    method: 'POST',
    body: {
      displayName: 'Teen',
      email: teenEmail,
      password: initialPassword,
    },
  });
  assert.equal(teenRegister.status, 201);

  assert.equal(
    (await request('/v1/auth/verify-email', {
      method: 'POST',
      body: { token: teenRegister.body.verificationToken },
    })).status,
    204,
  );

  const teenLogin = await request('/v1/auth/login', {
    method: 'POST',
    body: { email: teenEmail, password: initialPassword },
  });
  assert.equal(teenLogin.status, 200);

  const unauthenticatedMembers = await request(`/v1/families/${family.body.id}/members`);
  assert.equal(unauthenticatedMembers.status, 401);

  const invite = await request(`/v1/families/${family.body.id}/invitations`, {
    method: 'POST',
    token: refreshed.body.accessToken,
    body: { email: teenEmail, role: 'teen_minor' },
  });
  assert.equal(invite.status, 201);
  assert.ok(invite.body.invitationToken);

  const accept = await request('/v1/invitations/accept', {
    method: 'POST',
    token: teenLogin.body.accessToken,
    body: { token: invite.body.invitationToken },
  });
  assert.equal(accept.status, 204);

  const members = await request(`/v1/families/${family.body.id}/members`, {
    token: refreshed.body.accessToken,
  });
  assert.equal(members.status, 200);
  assert.equal(members.body.members.length, 2);
  const parentMember = members.body.members.find((m) => m.display_name === 'Parent');
  const teenMember = members.body.members.find((m) => m.display_name === 'Teen');
  assert.equal(parentMember.role, 'parent_guardian');
  assert.equal(parentMember.is_admin, true);
  assert.equal(teenMember.role, 'teen_minor');
  assert.equal(teenMember.is_admin, false);

  const teenInviteAttempt = await request(`/v1/families/${family.body.id}/invitations`, {
    method: 'POST',
    token: teenLogin.body.accessToken,
    body: { email: 'blocked@example.test', role: 'adult_member' },
  });
  assert.equal(teenInviteAttempt.status, 403);

  const guardian = await request(`/v1/families/${family.body.id}/guardians`, {
    method: 'POST',
    token: refreshed.body.accessToken,
    body: {
      guardianUserId: parentMember.user_id,
      minorUserId: teenMember.user_id,
    },
  });
  assert.equal(guardian.status, 204);

  const teenGuardianAttempt = await request(`/v1/families/${family.body.id}/guardians`, {
    method: 'POST',
    token: teenLogin.body.accessToken,
    body: {
      guardianUserId: parentMember.user_id,
      minorUserId: teenMember.user_id,
    },
  });
  assert.equal(teenGuardianAttempt.status, 403);

  const forgot = await request('/v1/auth/forgot-password', {
    method: 'POST',
    body: { email: teenEmail },
  });
  assert.equal(forgot.status, 200);
  assert.equal(forgot.body.accepted, true);
  assert.ok(forgot.body.resetToken);

  const reset = await request('/v1/auth/reset-password', {
    method: 'POST',
    body: { token: forgot.body.resetToken, newPassword: changedPassword },
  });
  assert.equal(reset.status, 204);

  const oldLogin = await request('/v1/auth/login', {
    method: 'POST',
    body: { email: teenEmail, password: initialPassword },
  });
  assert.equal(oldLogin.status, 401);

  const newLogin = await request('/v1/auth/login', {
    method: 'POST',
    body: { email: teenEmail, password: changedPassword },
  });
  assert.equal(newLogin.status, 200);

  const changedAgain = await request('/v1/auth/change-password', {
    method: 'POST',
    token: newLogin.body.accessToken,
    body: { currentPassword: changedPassword, newPassword: initialPassword },
  });
  assert.equal(changedAgain.status, 204);

  const logout = await request('/v1/auth/logout', {
    method: 'POST',
    token: newLogin.body.accessToken,
  });
  assert.equal(logout.status, 204);

  const afterLogout = await request('/v1/profile', {
    token: newLogin.body.accessToken,
  });
  assert.equal(afterLogout.status, 401);
});

test('forgot-password response does not enumerate accounts', async () => {
  const response = await request('/v1/auth/forgot-password', {
    method: 'POST',
    body: { email: `missing-${Date.now()}@example.test` },
  });
  assert.equal(response.status, 200);
  assert.deepEqual(response.body, { accepted: true });
});
