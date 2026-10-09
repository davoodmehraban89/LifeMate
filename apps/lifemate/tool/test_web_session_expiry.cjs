// Compiled-client regression adapted from the independent security probe.
// Synthetic held refresh + explicit pagehide + HTTP401; no live backend, TLS,
// true BFCache restoration or in-flight real renderer crash is claimed.
const assert = require('node:assert/strict');
const { readFile } = require('node:fs/promises');
const path = require('node:path');
const { chromium } = require('playwright');
const root = path.resolve(process.argv.find(arg => arg.startsWith('--artifact='))?.slice('--artifact='.length) || 'build/web');
const expectedPending = Number(process.argv.find(arg => arg.startsWith('--expected-pending='))?.slice('--expected-pending='.length) ?? 1);
assert([0,1].includes(expectedPending), 'Use --expected-pending=0 or 1');
const origin = 'https://review.example.test';
const userId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const sessionKey = 'lifeguide.refresh_session.v1';
const scope = origin + '/api|' + userId;
const offlineKey = 'lifeguide.offline.v2.' + Buffer.from(scope).toString('base64').replaceAll('+','-').replaceAll('/','_');
const access = 'synthetic.' + Buffer.from(JSON.stringify({ sub: userId })).toString('base64url') + '.synthetic';
const types = { '.html':'text/html', '.js':'application/javascript', '.json':'application/json', '.wasm':'application/wasm', '.ttf':'font/ttf', '.otf':'font/otf', '.png':'image/png' };
(async () => {
  const browser = await chromium.launch({ headless: true, ...(process.env.LIFEGUIDE_TEST_CHROMIUM_PATH ? {executablePath:process.env.LIFEGUIDE_TEST_CHROMIUM_PATH} : {}) });
  try {
    const ctx = await browser.newContext({ serviceWorkers:'block' });
    let refreshes = 0, releaseFirst, firstObserved;
    const observed = new Promise(resolve => firstObserved = resolve);
    const released = new Promise(resolve => releaseFirst = resolve);
    await ctx.route('**/*', async route => {
      const url = new URL(route.request().url());
      assert.equal(url.origin, origin, 'External requests are forbidden');
      const json = (body, status=200) => route.fulfill({ status, contentType:'application/json', body:JSON.stringify(body) });
      if (url.pathname === '/setup') return route.fulfill({ contentType:'text/html', body:'<!doctype html><title>Synthetic setup</title>' });
      if (url.pathname === '/config.json') return json({ apiBaseUrl:'/api', apiFallbackUrls:[] });
      if (url.pathname === '/api/v1/auth/refresh') {
        refreshes++;
        if (refreshes === 1) { firstObserved(); await released; return json({ accessToken:access, refreshToken:'synthetic-new-token-after-rotation' }); }
        return json({ error:'invalid_refresh' }, 401);
      }
      if (url.pathname.startsWith('/api/')) return json({ emailDeliveryAvailable:false, smsAvailable:false, smsStatus:'UNVERIFIED' });
      const file = path.resolve(root, '.' + (url.pathname === '/' ? '/index.html' : url.pathname));
      assert(file.startsWith(root + path.sep));
      try { return route.fulfill({ contentType:types[path.extname(file)] || 'application/octet-stream', body:await readFile(file) }); }
      catch { return route.fulfill({ status:404, body:'Missing synthetic resource' }); }
    });
    const page = await ctx.newPage();
    await page.goto(origin + '/setup');
    await page.evaluate(({sessionKey,userId,origin,offlineKey,scope}) => {
      localStorage.setItem(sessionKey, JSON.stringify({ endpoint:origin+'/api', userId, refreshToken:'synthetic-old-token' }));
      localStorage.setItem(offlineKey, JSON.stringify(JSON.stringify({ version:2, scope, caches:{}, queue:[{ id:'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',entityId:'cccccccc-cccc-4ccc-8ccc-cccccccccccc',payload:{title:'Synthetic unsent item'},queueStatus:'queued' }],lastSyncAt:null,lastAckAt:null })));
    }, {sessionKey,userId,origin,offlineKey,scope});
    const snapshot = () => page.evaluate(({sessionKey,offlineKey}) => {
      const raw = localStorage.getItem(offlineKey);
      return { sessionPresent:localStorage.getItem(sessionKey)!==null, pending:raw ? JSON.parse(JSON.parse(raw)).queue.length : null };
    }, {sessionKey,offlineKey});
    await page.goto(origin, {waitUntil:'domcontentloaded'});
    let observedTimeout;
    try { await Promise.race([observed, new Promise((_,reject) => { observedTimeout=setTimeout(() => reject(new Error('No first refresh within 30 seconds')),30000); })]); } finally { clearTimeout(observedTimeout); }
    const before = await snapshot();
    const originalCache = await page.evaluate(key => localStorage.getItem(key), offlineKey);
    await page.evaluate(() => window.dispatchEvent(new PageTransitionEvent('pagehide',{persisted:true})));
    assert.equal(await page.evaluate(() => window.lifeguideInstanceOwned), false);
    releaseFirst();
    await page.waitForLoadState('networkidle');
    const afterLateResponse = await snapshot();
    await page.reload({waitUntil:'networkidle'});
    await page.waitForFunction(() => !localStorage.getItem('lifeguide.refresh_session.v1'));
    // Network idle plus a bounded drain allows expiry's local async cleanup to finish.
    await page.waitForTimeout(1000);
    const afterReopen = await snapshot();
    assert.equal(before.pending,1);
    assert.equal(afterLateResponse.pending,1);
    assert.equal(refreshes,2);
    assert.equal(afterReopen.sessionPresent,false);
    assert.equal(afterReopen.pending,expectedPending,'Forced expiry must preserve unsent account-scoped mutations when expected-pending=1');
    if (expectedPending === 1) assert.equal(await page.evaluate(key => localStorage.getItem(key),offlineKey), originalCache, 'Forced expiry cannot rewrite any durable private payload');
    console.log(JSON.stringify({ evidence:'compiled current artifact; actual Chromium; synthetic intercepted refresh commit; explicit pagehide; no live server/TLS/Safari proof', before, afterLateResponse, afterReopen, refreshes }));
    await ctx.close();
  } finally { await browser.close(); }
})().catch(error => { console.error(error.stack); process.exitCode=1; });
