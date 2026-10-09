// Tests the actual compiled artifact at an intercepted synthetic HTTPS origin.
// This does not validate real TLS, an installed PWA, Safari or an Android device.
const assert = require('node:assert/strict');
const {readFile} = require('node:fs/promises');
const path = require('node:path');
const {chromium} = require('playwright');

const artifactRoot = path.resolve(process.argv[2] || 'build/web');
const testUrl = new URL(process.env.LIFEGUIDE_WEB_TEST_ORIGIN || 'https://family.example.test');
assert(testUrl.protocol === 'https:' && !testUrl.username && !testUrl.password &&
  testUrl.pathname === '/' && !testUrl.search && !testUrl.hash,
  'The synthetic test origin must be a plain HTTPS origin.');
const origin = testUrl.origin;
const screenshotIndex = process.argv.indexOf('--screenshot');
const screenshotPath = screenshotIndex < 0 ? null : process.argv[screenshotIndex + 1];
if (screenshotIndex >= 0) assert(screenshotPath, '--screenshot requires a file path');
const mime = {'.html':'text/html', '.js':'application/javascript', '.json':'application/json',
  '.wasm':'application/wasm', '.ttf':'font/ttf', '.otf':'font/otf', '.woff2':'font/woff2',
  '.png':'image/png', '.svg':'image/svg+xml'};
const csp = "default-src 'self'; script-src 'self' 'wasm-unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; font-src 'self'; connect-src 'self'; worker-src 'self' blob:; object-src 'none'; base-uri 'self'; frame-ancestors 'none'; form-action 'self'";

(async () => {
  const executablePath = process.env.LIFEGUIDE_TEST_CHROMIUM_PATH;
  const browser = await chromium.launch({headless:true,
    ...(executablePath ? {executablePath} : {})});
  try {
    const context = await browser.newContext({viewport:{width:390,height:844},
      ignoreHTTPSErrors:false, serviceWorkers:'block'});
    const requested = [], missingAssets = [], errors = [];
    await context.route('**/*', async route => {
      const url = new URL(route.request().url());
      requested.push(url.href);
      if (url.origin !== origin) {
        errors.push(`Unexpected external request: ${url.origin}`);
        await route.abort();
        return;
      }
      if (url.pathname === '/api/v1/auth/capabilities') {
        await route.fulfill({contentType:'application/json', body:JSON.stringify({
          emailDeliveryAvailable:false,smsAvailable:false,smsStatus:'UNVERIFIED'})});
        return;
      }
      const local = path.resolve(artifactRoot,
        '.' + (url.pathname === '/' ? '/index.html' : decodeURIComponent(url.pathname)));
      assert(local.startsWith(artifactRoot + path.sep), 'Artifact requests cannot escape the output directory');
      try {
        await route.fulfill({contentType:mime[path.extname(local)] || 'application/octet-stream',
          headers:{'content-security-policy':csp,'cache-control':'no-store'}, body:await readFile(local)});
      } catch {
        missingAssets.push(url.pathname);
        await route.fulfill({status:404,body:'Missing synthetic artifact resource'});
      }
    });
    const page = await context.newPage();
    page.on('pageerror', error => errors.push(error.message));
    page.on('console', message => {
      if (message.type() === 'error') errors.push(message.text());
    });
    await page.goto(origin, {waitUntil:'networkidle',timeout:60000});
    await page.waitForFunction(() => !document.getElementById('startup-status'), null, {timeout:60000});
    await page.waitForLoadState('networkidle');
    assert((await page.title()).includes('LifeGuide'), 'Built page must use the LifeGuide identity');
    assert.equal(await page.locator('flt-glass-pane').count(),1,'Flutter engine must start');
    if (screenshotPath) {
      const enable = page.locator('flt-semantics-placeholder');
      if (await enable.count()) await enable.evaluate(element => element.click());
      await page.screenshot({path:screenshotPath,fullPage:true});
    }
    assert(requested.some(url => url.includes('/canvaskit/') && url.endsWith('.wasm')),
      'CanvasKit WASM must load locally');
    for (const font of ['LifeGuidePersian.ttf','LifeGuideLatin.ttf','LifeGuideEmoji.ttf']) {
      assert(requested.some(url => url.endsWith(font)), `${font} must load locally`);
    }
    assert(!requested.some(url => /(?:gstatic\.com|googleapis\.com)/i.test(url)),
      'Runtime requests cannot use Google font or CanvasKit hosts');
    assert.equal(missingAssets.length,0,JSON.stringify(missingAssets));
    assert.equal(errors.length,0,JSON.stringify(errors));
    console.log(JSON.stringify({mode:'Synthetic HTTPS origin; intercepted compiled artifact responses; real TLS and service worker acceptance unverified',
      requests:requested.length, fontRequests:requested.filter(url => /\.(?:ttf|otf|woff2)$/.test(url)).map(url => new URL(url).pathname),
      canvasKitRequests:requested.filter(url => url.includes('/canvaskit/')).map(url => new URL(url).pathname),
      externalRequests:requested.filter(url => new URL(url).origin !== origin),missingAssets,errors},null,2));
  } finally {
    await browser.close();
  }
})().catch(error => {console.error(error.message);process.exitCode=1;});
