import test from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import { once } from 'node:events';
import { configureTrustedProxy, rateLimit } from '../src/operations.js';

async function serve(trusted, run) {
  const app = express();
  configureTrustedProxy(app, trusted);
  app.use(rateLimit);
  app.get('/v1/auth/proxy-test', (req, res) => res.json({ ip: req.ip }));
  const server = app.listen(0, '127.0.0.1');
  await once(server, 'listening');
  try { await run(`http://127.0.0.1:${server.address().port}/v1/auth/proxy-test`); }
  finally { await new Promise(resolve => server.close(resolve)); }
}

test('untrusted clients cannot forge forwarded addresses', async () => {
  await serve('', async url => {
    const response = await fetch(url, { headers: {'x-forwarded-for': '192.0.2.1'} });
    assert.equal((await response.json()).ip, '127.0.0.1');
  });
});

test('trusted single gateway separates client rate buckets and ignores extra left hops', async () => {
  const previous = [process.env.NODE_ENV, process.env.RATE_LIMIT_AUTH_MAX];
  process.env.NODE_ENV = 'production';
  process.env.RATE_LIMIT_AUTH_MAX = '2';
  try {
    await serve('127.0.0.1/32', async url => {
      const first = {'x-forwarded-for': '192.0.2.100, 192.0.2.2'};
      assert.equal((await (await fetch(url, {headers: first})).json()).ip, '192.0.2.2');
      assert.equal((await fetch(url, {headers: first})).status, 200);
      assert.equal((await fetch(url, {headers: first})).status, 429);
      assert.equal((await fetch(url, {headers: {'x-forwarded-for': '192.0.2.3'}})).status, 200);
    });
  } finally {
    for (const [index, key] of ['NODE_ENV', 'RATE_LIMIT_AUTH_MAX'].entries()) {
      if (previous[index] === undefined) delete process.env[key]; else process.env[key] = previous[index];
    }
  }
});

test('blank defaults distrust proxy and invalid broad wildcard fails closed', () => {
  assert.throws(() => configureTrustedProxy(express(), '*'), /Invalid trusted proxy/);
});
