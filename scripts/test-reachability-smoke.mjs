#!/usr/bin/env node
// Real loopback HTTPS only. Temporary CA/private keys are removed after the suite.
import assert from 'node:assert/strict';
import { spawn, execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import https from 'node:https';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { after, before, test } from 'node:test';

const runFile = promisify(execFile);
const smoke = fileURLToPath(new URL('./reachability-smoke.mjs', import.meta.url));
let directory;
let caFile;
const certificates = {};

before(async () => {
  directory = await mkdtemp(join(tmpdir(), 'lifeguide-smoke-tls-'));
  try {
    caFile = join(directory, 'ca.pem');
    const caKey = join(directory, 'ca-key.pem');
    await runFile('openssl', ['req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '1',
      '-keyout', caKey, '-out', caFile, '-subj', '/CN=LifeGuide local regression CA',
      '-addext', 'basicConstraints=critical,CA:TRUE']);
    for (const [name, san] of [['matching', 'IP:127.0.0.1'], ['mismatch', 'DNS:wrong.invalid']]) {
      const keyFile = join(directory, `${name}-key.pem`);
      const requestFile = join(directory, `${name}.csr`);
      const certFile = join(directory, `${name}.pem`);
      const extensionsFile = join(directory, `${name}.ext`);
      await writeFile(extensionsFile, `subjectAltName=${san}\nextendedKeyUsage=serverAuth\n`);
      await runFile('openssl', ['req', '-new', '-newkey', 'rsa:2048', '-nodes',
        '-keyout', keyFile, '-out', requestFile, '-subj', '/CN=LifeGuide loopback fixture']);
      await runFile('openssl', ['x509', '-req', '-in', requestFile, '-CA', caFile,
        '-CAkey', caKey, '-CAcreateserial', '-days', '1', '-out', certFile,
        '-extfile', extensionsFile]);
      certificates[name] = { key: await readFile(keyFile), cert: await readFile(certFile) };
    }
  } catch (error) {
    await rm(directory, { recursive: true, force: true });
    throw error;
  }
});

after(async () => {
  if (directory) await rm(directory, { recursive: true, force: true });
});

async function exercise({ certificate = 'matching', trustCa = false, disableTls = false, allowWrite = false } = {}) {
  const requests = [];
  const sockets = new Set();
  const server = https.createServer(certificates[certificate], (req, res) => {
    requests.push({ method: req.method, path: req.url, authorization: Boolean(req.headers.authorization) });
    res.setHeader('Content-Type', 'application/json');
    if (req.url === '/health') res.end(JSON.stringify({ status: 'ok' }));
    else if (req.url === '/') {
      res.setHeader('Content-Type', 'text/html');
      res.end('<!doctype html><title>LifeGuide local fixture</title>');
    } else if (req.url === '/manifest.json') res.end(JSON.stringify({ display: 'standalone' }));
    else if (req.url === '/config.json') {
      res.setHeader('Cache-Control', 'no-store');
      res.end(JSON.stringify({ apiBaseUrl: '/api' }));
    } else {
      res.statusCode = 401;
      res.end(JSON.stringify({ error: 'authentication_required' }));
    }
  });
  server.on('connection', socket => {
    sockets.add(socket);
    socket.on('close', () => sockets.delete(socket));
  });
  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', resolve);
  });
  try {
    const env = { PATH: process.env.PATH };
    if (trustCa) env.ROOT_CA_FILE = caFile;
    // Adversarial inherited setting: never used for the trusted acceptance case.
    if (disableTls) env.NODE_TLS_REJECT_UNAUTHORIZED = '0';
    if (allowWrite) {
      env.SMOKE_ALLOW_SYNTHETIC_WRITE = 'yes';
      env.SMOKE_EMAIL = 'loopback-fixture@lifeguide.test';
      env.SMOKE_PASSWORD = 'local-synthetic-fixture-password';
    }
    const child = spawn(process.execPath, [smoke, `https://127.0.0.1:${server.address().port}`], {
      env, stdio: ['ignore', 'pipe', 'pipe'],
    });
    let stdout = '';
    let stderr = '';
    child.stdout.on('data', chunk => { stdout += chunk; });
    child.stderr.on('data', chunk => { stderr += chunk; });
    const timer = setTimeout(() => child.kill('SIGKILL'), 20000);
    let code;
    try {
      code = await new Promise((resolve, reject) => {
        child.once('error', reject);
        child.once('close', resolve);
      });
    } finally {
      clearTimeout(timer);
    }
    assert.notEqual(code, null, 'Loopback smoke timed out');
    return { code, report: JSON.parse(stdout), stderr, requests };
  } finally {
    for (const socket of sockets) socket.destroy();
    await new Promise(resolve => server.close(resolve));
  }
}

function assertTlsFailure(outcome) {
  assert.equal(outcome.code, 1, 'Unverified TLS must fail the smoke process');
  assert.equal(outcome.report.results.some(result => result.name === 'TLS' && result.status === 'PASS'), false,
    'Unverified TLS must never be reported as PASS');
  assert.equal(outcome.report.results[0]?.status, 'FAIL');
  assert.equal(outcome.requests.some(request => request.authorization || request.method !== 'GET'
    || request.path.startsWith('/api/v1/auth/')), false, 'TLS failure must precede auth and writes');
}

test('trusted local CA and matching hostname pass read-only smoke without TLS-disable', async () => {
  const outcome = await exercise({ trustCa: true });
  assert.equal(outcome.code, 0);
  assert.equal(outcome.report.results.find(result => result.name === 'TLS')?.status, 'PASS');
  assert.equal(outcome.report.results.some(result => result.status === 'FAIL'), false);
  assert.equal(outcome.report.results.find(result => result.name === 'API round-trip')?.status, 'UNVERIFIED');
  assert.deepEqual(outcome.requests.map(request => request.path),
    ['/health', '/', '/manifest.json', '/config.json', '/api/v1/plan-items']);
  assert.equal(outcome.requests.some(request => request.authorization || request.method !== 'GET'), false);
  assert.equal(outcome.stderr, '');
});

test('untrusted CA fails before opted-in synthetic auth or writes', async () => {
  const outcome = await exercise({ allowWrite: true });
  assertTlsFailure(outcome);
  assert.equal(outcome.requests.length, 0);
});

test('inherited NODE_TLS_REJECT_UNAUTHORIZED=0 cannot produce a false TLS PASS', async t => {
  const outcome = await exercise({ disableTls: true });
  t.diagnostic(`Local untrusted fixture: exit=${outcome.code}, TLS=${outcome.report.results.find(result => result.name === 'TLS')?.status ?? 'not recorded'}`);
  assertTlsFailure(outcome);
  assert.equal(outcome.requests.length, 0);
});

test('inherited TLS-disable cannot reach opted-in synthetic auth or writes', async () => {
  const outcome = await exercise({ disableTls: true, allowWrite: true });
  assertTlsFailure(outcome);
  assert.equal(outcome.requests.length, 0);
});

test('trusted CA with hostname mismatch fails before opted-in synthetic auth or writes', async () => {
  const outcome = await exercise({ certificate: 'mismatch', trustCa: true, allowWrite: true });
  assertTlsFailure(outcome);
  assert.equal(outcome.requests.length, 0);
});
