#!/usr/bin/env node
// Node >=22. TLS verification always remains enabled. Never logs credentials.
import https from 'node:https';
import fs from 'node:fs';
import crypto from 'node:crypto';

const origin = new URL(process.argv[2] ?? process.env.SMOKE_ORIGIN ?? '');
if (origin.protocol !== 'https:' || origin.username || origin.password || origin.search || origin.hash || origin.pathname !== '/') {
  throw new Error('Pass one HTTPS origin without credentials, path, query or fragment');
}
const ca = process.env.ROOT_CA_FILE ? fs.readFileSync(process.env.ROOT_CA_FILE) : undefined;
const results = [];
let currentCheck = 'TLS/connection';
const record = (name, status, detail) => results.push({ name, status, detail });
async function request(path, { method = 'GET', json, token } = {}) {
  const url = new URL(path, origin);
  if (url.origin !== origin.origin) throw new Error('Cross-origin request refused');
  const body = json === undefined ? undefined : JSON.stringify(json);
  return await new Promise((resolve, reject) => {
    const req = https.request(url, { method, ca, timeout: 15000, headers: {
      ...(body ? { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(body) } : {}),
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    } }, res => {
      const chunks = []; let size = 0;
      res.on('data', chunk => { size += chunk.length; if (size > 4 * 1024 * 1024) req.destroy(new Error('Oversize response')); else chunks.push(chunk); });
      res.on('end', () => resolve({ status: res.statusCode, text: Buffer.concat(chunks).toString('utf8'), headers: res.headers, tls: res.socket?.authorized }));
    });
    req.on('timeout', () => req.destroy(new Error('Timeout')));
    req.on('error', reject);
    if (body) req.write(body);
    req.end();
  });
}
function assert(condition, message) { if (!condition) throw new Error(message); }
try {
  const health = await request('/health');
  record('TLS', 'PASS', 'Certificate chain and hostname verified by Node TLS');
  currentCheck = '/health';
  assert(health.status === 200 && JSON.parse(health.text).status === 'ok', `health HTTP ${health.status}`);
  record('/health', 'PASS', 'HTTP 200 and database-backed status ok');
  currentCheck = 'PWA';
  const pwa = await request('/');
  assert(pwa.status === 200 && /LifeGuide|لایف‌گاید/.test(pwa.text), 'PWA title/content missing');
  const manifest = await request('/manifest.json');
  assert(manifest.status === 200 && JSON.parse(manifest.text).display === 'standalone', 'PWA manifest missing standalone');
  record('PWA', 'PASS', 'HTTPS HTML and standalone manifest loaded; Safari installation UNVERIFIED');
  currentCheck = 'runtime config';
  const config = await request('/config.json');
  assert(config.status === 200 && JSON.parse(config.text).apiBaseUrl === '/api', 'Same-origin runtime API config missing');
  assert(String(config.headers['cache-control']).includes('no-store'), 'Runtime config can become stale');
  record('runtime config', 'PASS', 'Same-origin /api; no-store');
  currentCheck = 'API auth boundary';
  const denied = await request('/api/v1/plan-items');
  assert(denied.status === 401, `Anonymous planner unexpectedly returned HTTP ${denied.status}`);
  record('API auth boundary', 'PASS', 'Anonymous planner request rejected with 401');
  if (process.env.SMOKE_ALLOW_SYNTHETIC_WRITE !== 'yes') {
    record('API round-trip', 'UNVERIFIED', 'Set SMOKE_ALLOW_SYNTHETIC_WRITE=yes and synthetic SMOKE_EMAIL/SMOKE_PASSWORD to run');
  } else {
    currentCheck = 'API round-trip';
    assert(process.env.SMOKE_EMAIL && process.env.SMOKE_PASSWORD, 'Synthetic account credentials required');
    const login = await request('/api/v1/auth/login', { method: 'POST', json: { email: process.env.SMOKE_EMAIL, password: process.env.SMOKE_PASSWORD } });
    assert(login.status === 200, `Login HTTP ${login.status}`);
    const token = JSON.parse(login.text).accessToken;
    assert(token, 'Access token missing');
    const title = `LifeGuide synthetic reachability ${crypto.randomUUID()}`;
    const created = await request('/api/v1/plan-items', { method: 'POST', token, json: { kind: 'assignment', title, visibility: 'private', priority: 'normal' } });
    assert(created.status === 201, `Create HTTP ${created.status}`);
    const createdItem = JSON.parse(created.text);
    const id = createdItem.id;
    assert(id, 'Created record ID missing');
    const read = await request('/api/v1/plan-items?kind=assignment', { token });
    assert(read.status === 200 && JSON.parse(read.text).items.some(item => item.id === id && item.title === title), 'Independent read did not return created task');
    const archived = await request(`/api/v1/plan-items/${id}`, { method: 'PATCH', token, json: { status: 'cancelled', expectedVersion: createdItem.version } });
    assert(archived.status === 200 && JSON.parse(archived.text).status === 'cancelled', 'Safe archive failed');
    const logout = await request('/api/v1/auth/logout', { method: 'POST', token, json: { refreshToken: JSON.parse(login.text).refreshToken } });
    assert(logout.status === 204, 'Synthetic session logout failed');
    const revoked = await request('/api/v1/plan-items', { token });
    assert(revoked.status === 401, 'Logged-out session remains usable');
    record('API round-trip', 'PASS', 'Synthetic private homework created, independently read, and archived on server');
    record('session cleanup', 'PASS', 'Logout acknowledged; old access token rejected');
  }
} catch (error) {
  record(currentCheck, 'FAIL', `${error.code ?? 'CHECK_FAILED'}: ${String(error.message).slice(0, 240)}`);
  process.exitCode = 1;
}
console.log(JSON.stringify({ origin: origin.origin, at: new Date().toISOString(), results }, null, 2));
