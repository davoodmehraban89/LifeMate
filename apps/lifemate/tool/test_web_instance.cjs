// Real Chromium Web Locks at intercepted synthetic HTTPS origins. Fixture mode
// uses the production bootstrap; compiled mode additionally runs Flutter itself.
// This does not establish real TLS, installed-PWA, Safari or device acceptance.
const assert = require('node:assert/strict');
const {readFile} = require('node:fs/promises');
const path = require('node:path');
const {chromium} = require('playwright');

const compiled = process.argv.includes('--compiled');
const artifactRoot = path.resolve(process.argv[process.argv.indexOf('--compiled') + 1] || 'build/web');
const origin = 'https://family.example.test';
const otherOrigin = 'https://independent.example.test';
const sessionKey = 'lifeguide.refresh_session.v1';
const userId = '11111111-1111-4111-8111-111111111111';
const accessToken = 'synthetic.' + Buffer.from(JSON.stringify({sub:userId})).toString('base64url') + '.synthetic';
const mime = {'.html':'text/html','.js':'application/javascript','.json':'application/json',
  '.wasm':'application/wasm','.ttf':'font/ttf','.otf':'font/otf','.woff2':'font/woff2',
  '.png':'image/png','.svg':'image/svg+xml'};
const csp = "default-src 'self'; script-src 'self' 'wasm-unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; font-src 'self'; connect-src 'self'; worker-src 'self' blob:; object-src 'none'; base-uri 'self'; frame-ancestors 'none'; form-action 'self'";

async function main() {
  const bootstrap = (await readFile(path.resolve('web/flutter_bootstrap.js'),'utf8'))
    .replace('{{flutter_js}}','').replace('{{flutter_build_config}}','');
  const browser = await chromium.launch({headless:true,
    // Playwright otherwise disables BFCache, which would weaken the history check.
    ignoreDefaultArgs:['--disable-back-forward-cache'],
    ...(process.env.LIFEGUIDE_TEST_CHROMIUM_PATH ? {executablePath:process.env.LIFEGUIDE_TEST_CHROMIUM_PATH} : {})});
  const checks = [];
  let historyEvidence;
  try {
    async function context({unsupported=false}={}) {
      const ctx = await browser.newContext({serviceWorkers:'block',ignoreHTTPSErrors:false});
      const restoredPages = new Set();
      await ctx.exposeBinding('instanceRestorationObserved',({page},persisted) => {
        if (persisted) restoredPages.add(page);
      });
      await ctx.addInitScript(({sessionKey,unsupported}) => {
        window.instanceProbe = {reads:0,writes:0,removes:0,starts:0};
        window.addEventListener('pageshow',event =>
          window.instanceRestorationObserved(event.persisted).catch(() => {}));
        for (const [method,counter] of [['getItem','reads'],['setItem','writes'],['removeItem','removes']]) {
          const original = Storage.prototype[method];
          Storage.prototype[method] = function(key,...rest) {
            if (key === sessionKey || String(key).includes('lifeguide.offline')) window.instanceProbe[counter]++;
            return original.call(this,key,...rest);
          };
        }
        if (unsupported) Object.defineProperty(navigator,'locks',{value:undefined});
      },{sessionKey,unsupported});
      const requests = new Map();
      await ctx.route('**/*',async route => {
        const request = route.request(), url = new URL(request.url());
        assert([origin,otherOrigin].includes(url.origin),'No external requests are permitted');
        let page;
        try { page = request.frame().page(); } catch {}
        if (page && (url.pathname.startsWith('/api/') || url.pathname === '/config.json')) {
          const counts = requests.get(page) || {api:0,refresh:0,config:0};
          if (url.pathname === '/config.json') counts.config++;
          else { counts.api++; if (url.pathname.endsWith('/auth/refresh')) counts.refresh++; }
          requests.set(page,counts);
        }
        const respond = body => route.fulfill({contentType:'application/json',body:JSON.stringify(body)});
        if (url.pathname === '/setup') return route.fulfill({contentType:'text/html',body:'<!doctype html><title>Synthetic setup</title>'});
        if (url.pathname === '/config.json') return respond({apiBaseUrl:'/api',apiFallbackUrls:[]});
        if (url.pathname.endsWith('/auth/refresh')) return respond({accessToken,refreshToken:'synthetic-rotated-refresh'});
        if (url.pathname.endsWith('/auth/capabilities')) return respond({emailDeliveryAvailable:false,smsAvailable:false,smsStatus:'UNVERIFIED'});
        if (url.pathname === '/api/v1/profile') return respond({user_id:userId,display_name:'آزمون ساختگی',theme_preference:'neutral',profile_category:'adult'});
        if (url.pathname.startsWith('/api/')) {
          if (url.pathname.includes('/families')) return respond({families:[]});
          if (url.pathname.includes('/plan-items')) return respond({items:[]});
          if (url.pathname.includes('/life-contexts')) return respond({contexts:[]});
          if (url.pathname.includes('/notifications')) return respond({notifications:[]});
          return respond({});
        }
        if (!compiled) {
          if (url.pathname === '/flutter_bootstrap.js') return route.fulfill({contentType:'application/javascript',body:bootstrap});
          if (url.pathname === '/fixture-loader.js') return route.fulfill({contentType:'application/javascript',body:`
            window._flutter={loader:{async load(options){
              window.instanceProbe.starts++;
              localStorage.getItem('${sessionKey}');
              await fetch('/api/v1/auth/refresh',{method:'POST'});
              localStorage.setItem('${sessionKey}','synthetic-fixture-session');
              await options.onEntrypointLoaded({async initializeEngine(){return {async runApp(){
                document.body.appendChild(document.createElement('flt-glass-pane'));
              }}}});
            }}};`});
          return route.fulfill({contentType:'text/html',headers:{'content-security-policy':csp},body:
            '<!doctype html><html lang="fa" dir="rtl"><head><meta charset="utf-8"><title>LifeGuide fixture</title></head><body><p id="startup-status" role="status">در حال بارگذاری</p><script src="/fixture-loader.js"></script><script src="/flutter_bootstrap.js"></script></body></html>'});
        }
        const local = path.resolve(artifactRoot,'.' + (url.pathname === '/' ? '/index.html' : decodeURIComponent(url.pathname)));
        assert(local.startsWith(artifactRoot + path.sep),'Artifact path must remain in the output directory');
        try { return await route.fulfill({contentType:mime[path.extname(local)] || 'application/octet-stream',headers:{'content-security-policy':csp,'cache-control':'no-store'},body:await readFile(local)}); }
        catch { return route.fulfill({status:404,body:'Missing synthetic artifact resource'}); }
      });
      // Seed only once through an explicit setup document, never from tab init.
      const setup = await ctx.newPage();
      await setup.goto(origin + '/setup');
      await setup.evaluate(({sessionKey,userId,origin}) => localStorage.setItem(sessionKey,
        JSON.stringify({endpoint:origin + '/api',refreshToken:'synthetic-refresh',userId})),{sessionKey,userId,origin});
      await setup.close();
      return {ctx,requests,restoredPages};
    }
    const counts = (fixture,page) => fixture.requests.get(page) || {api:0,refresh:0,config:0};
    async function settle(page) {
      await page.waitForFunction(() => document.querySelector('flt-glass-pane') ||
        document.querySelector('#startup-retry'),null,{timeout:60000});
      await page.waitForLoadState('networkidle');
    }
    async function open(fixture,url=origin) {
      const page = await fixture.ctx.newPage();
      await page.goto(url,{timeout:60000});
      await settle(page);
      return page;
    }
    async function owner(fixture,page) {
      assert.equal(await page.locator('flt-glass-pane').count(),1,'The owner must start Flutter');
      assert.equal(await page.evaluate(() => window.lifeguideInstanceOwned),true,'Only an acquired lock grants ownership');
      if (new URL(page.url()).origin === origin) {
        // Engine DOM appears before RuntimeController's asynchronous restore.
        // In particular, retry starts in a document already marked network-idle.
        try {
          await page.waitForFunction(() => window.instanceProbe.reads >= 1 &&
            window.instanceProbe.writes >= 1,null,{timeout:60000});
        } catch (error) {
          const diagnostics = await page.evaluate(sessionKey => ({
            owned:window.lifeguideInstanceOwned,probe:{...window.instanceProbe},
            sessionPresent:localStorage.getItem(sessionKey) !== null,
            engineCount:document.querySelectorAll('flt-glass-pane').length,
            startupStatusPresent:!!document.querySelector('#startup-status'),
          }),sessionKey);
          throw new Error('Session restore did not complete: ' + JSON.stringify({
            requests:counts(fixture,page),...diagnostics,reason:error.name}));
        }
        assert.equal(counts(fixture,page).refresh,1,'The owner restores and rotates the synthetic session exactly once');
        const probe = await page.evaluate(() => window.instanceProbe);
        assert(probe.reads >= 1 && probe.writes >= 1,'Owner session store is exercised');
      }
    }
    async function blocked(fixture,page,unsupported=false) {
      assert.equal(await page.locator('flt-glass-pane').count(),0,'A blocked instance must never start Flutter');
      assert.equal(await page.evaluate(() => window.lifeguideInstanceOwned),false);
      assert.deepEqual(counts(fixture,page),{api:0,refresh:0,config:0},'Blocked tabs make no runtime/API/auth requests');
      assert.deepEqual(await page.evaluate(() => window.instanceProbe),{reads:0,writes:0,removes:0,starts:0},'Blocked tabs do not read, write or erase personal storage');
      assert.match(await page.locator('#startup-status').textContent(),unsupported ? /مرورگر/ : /پنجره/);
      assert(await page.locator('#startup-retry').isVisible(),'Blocked user can retry');
    }

    const sequential = await context();
    const first = await open(sequential);
    const second = await open(sequential);
    // This assertion deliberately fails against the pre-gate production bootstrap.
    assert.equal(await second.locator('flt-glass-pane').count(),0,'Second same-origin tab must not initialize Flutter');
    await owner(sequential,first); await blocked(sequential,second);
    await first.bringToFront(); await second.bringToFront();
    await second.locator('#startup-retry').click(); await settle(second);
    await blocked(sequential,second);
    checks.push('same-origin contention + background ownership + retry denied');
    await first.close();
    await second.locator('#startup-retry').click(); await settle(second);
    await owner(sequential,second);
    checks.push('owner close then blocked-tab retry acquires without erasure');
    const separateOrigin = await open(sequential,otherOrigin);
    assert.equal(await separateOrigin.evaluate(() => window.lifeguideInstanceOwned),true,'Independent origins acquire their own lock');
    await sequential.ctx.close();
    checks.push('independent origin unaffected');

    const racing = await context();
    const [raceA,raceB] = await Promise.all([open(racing),open(racing)]);
    const ownsA = await raceA.evaluate(() => window.lifeguideInstanceOwned);
    assert.notEqual(ownsA,await raceB.evaluate(() => window.lifeguideInstanceOwned),'Simultaneous opens have exactly one owner');
    await owner(racing,ownsA ? raceA : raceB);
    await blocked(racing,ownsA ? raceB : raceA);
    const independent = await context();
    await owner(independent,await open(independent));
    await independent.ctx.close(); await racing.ctx.close();
    checks.push('simultaneous race has one owner; separate browser profile unaffected');

    const missing = await context({unsupported:true});
    await blocked(missing,await open(missing),true);
    await missing.ctx.close();
    checks.push('unsupported Web Locks fails closed');

    const crashed = await context();
    const crashOwner = await open(crashed); await owner(crashed,crashOwner);
    const cdp = await crashed.ctx.newCDPSession(crashOwner);
    const observedCrash = new Promise(resolve => crashOwner.once('crash',resolve));
    // A crashed renderer need not answer the CDP command. Observe its actual
    // crash event, then acquire from a new document before closing the old tab.
    cdp.send('Page.crash').catch(() => {});
    let crashTimeout;
    try {
      await Promise.race([observedCrash,new Promise((_,reject) => {
        crashTimeout = setTimeout(() => reject(new Error('Renderer crash was not observed')),15000);
      })]);
    } finally { clearTimeout(crashTimeout); }
    await owner(crashed,await open(crashed));
    await crashed.ctx.close();
    checks.push('actual renderer crash releases lock for a fresh tab');

    const history = await context();
    const historyOwner = await open(history); await owner(history,historyOwner);
    await historyOwner.goto(otherOrigin + '/setup');
    const replacement = await open(history); await owner(history,replacement);
    history.requests.delete(historyOwner);
    await historyOwner.goBack(); await settle(historyOwner);
    await blocked(history,historyOwner);
    historyEvidence = await historyOwner.evaluate(() => {
      const navigation = performance.getEntriesByType('navigation')[0];
      return {navigationType:navigation?.type,notRestoredReasons:navigation?.notRestoredReasons?.toJSON?.() || null};
    });
    historyEvidence.persistedPageshowObserved = history.restoredPages.has(historyOwner);
    historyEvidence.restoration = historyEvidence.persistedPageshowObserved
      ? 'actual persisted restoration followed by guarded rebootstrap'
      : 'ordinary history rebootstrap; actual BFCache restoration UNVERIFIED';
    await history.ctx.close();
    checks.push('history navigation cannot restore an owner while another tab owns');

    const restoration = await context();
    const stale = await open(restoration); await owner(restoration,stale);
    await stale.evaluate(() => window.dispatchEvent(new PageTransitionEvent('pagehide',{persisted:true})));
    assert.equal(await stale.evaluate(() => window.lifeguideInstanceOwned),false,'A suspended document immediately loses its ownership assertion');
    const suspendedContender = await open(restoration); await blocked(restoration,suspendedContender);
    // Explicitly exercise the persisted event as a separate synthetic lifecycle
    // case; the history test above uses actual browser navigation.
    restoration.requests.delete(stale);
    await Promise.all([
      stale.waitForEvent('framenavigated',{predicate:frame => frame === stale.mainFrame()}),
      stale.evaluate(() => window.dispatchEvent(new PageTransitionEvent('pageshow',{persisted:true}))).catch(error => {
        if (!/context was destroyed|navigation/i.test(error.message)) throw error;
      }),
    ]);
    await settle(stale); await owner(restoration,stale);
    await blocked(restoration,suspendedContender);
    await restoration.ctx.close();
    checks.push('synthetic persisted pagehide invalidates; pageshow replaces old engine before re-entry');
    console.log(JSON.stringify({mode:compiled ? 'compiled Flutter artifact' : 'production bootstrap with instrumented loader',
      browser:'real Chromium; synthetic intercepted HTTPS; TLS/PWA/Safari/device UNVERIFIED',checks,historyEvidence},null,2));
  } finally { await browser.close(); }
}
main().catch(error => {console.error(error.stack);process.exitCode=1;});
