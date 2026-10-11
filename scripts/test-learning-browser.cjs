// Developer acceptance substitute: compiled PWA, real local HTTPS/API/Postgres.
// Requires a normally trusted public local CA and a NEW synthetic fixture.
// Does not intercept responses, disable TLS, publish lessons or play media.
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const path = require('node:path');
const os = require('node:os');
const https = require('node:https');
const {spawnSync} = require('node:child_process');
const {chromium} = require('../apps/lifemate/node_modules/playwright');

const root = path.resolve(__dirname, '..');
const origin = process.env.LEARNING_BROWSER_ORIGIN || 'https://127.0.0.1:8445';
const parsed = new URL(origin);
assert(parsed.protocol === 'https:' && parsed.hostname === '127.0.0.1' &&
  parsed.port === '8445' && parsed.pathname === '/' && !parsed.username &&
  !parsed.password && !parsed.search && !parsed.hash,
  'This test is restricted to the isolated local synthetic HTTPS stack on8445.');
const email = process.env.SMOKE_EMAIL || '';
const password = process.env.SMOKE_PASSWORD || '';
assert(/^learning-browser-[a-f0-9]+@example\.test$/.test(email) && password.length >= 10,
  'Provide the dedicated synthetic fixture through SMOKE_EMAIL/SMOKE_PASSWORD.');
assert(process.env.ROOT_CA && process.env.LEARNING_COMPOSE_ENV,
  'ROOT_CA and private LEARNING_COMPOSE_ENV paths are required.');
const receiptFile = path.resolve(process.argv[2] || path.join(root,
  'docs/audits/evidence/learning-browser-2026-10-11.json'));
const screenshotFile = receiptFile.replace(/\.json$/, '.png');
const uuid = /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i;
const escaped = value => value.replace(/[.*+?^${}()|[\]\\]/g,'\\$&');
const paths = [], errors = [], failures = [], auth = [], checks = [];
let stage = 'startup';
let ca;
const check = name => { checks.push({name, status:'PASS'}); console.log(`PASS ${name}`); };

function api(method, endpoint, body, accessToken) {
  return new Promise((resolve,reject) => {
    const serialized = body === undefined ? null : Buffer.from(JSON.stringify(body));
    const req = https.request(new URL('/api' + endpoint, origin), {
      method, ca, rejectUnauthorized:true,
      headers:{...(serialized ? {'content-type':'application/json','content-length':serialized.length} : {}),
        ...(accessToken ? {authorization:`Bearer ${accessToken}`} : {})}
    }, response => {
      assert(response.socket.authorized, 'Independent API socket must verify TLS.');
      let content = '';
      response.setEncoding('utf8'); response.on('data', part => content += part);
      response.on('end', () => {
        try {resolve({status:response.statusCode,json:content ? JSON.parse(content) : null});}
        catch {reject(new Error('Independent API returned non-JSON content'));}
      });
    });
    req.setTimeout(15000, () => req.destroy(new Error('Independent HTTPS API timed out')));
    req.on('error', reject); req.end(serialized);
  });
}

function dbJson(query) {
  const result = spawnSync('docker', ['compose','--env-file',process.env.LEARNING_COMPOSE_ENV,
    'exec','-T','postgres','sh','-c',
    'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -At -v ON_ERROR_STOP=1'],
    {cwd:root,input:query,encoding:'utf8',timeout:15000});
  assert.equal(result.status,0,'Independent synthetic DB assertion failed.');
  return JSON.parse(result.stdout.trim());
}

function observe(page) {
  page.on('request', request => {
    const url = new URL(request.url());
    paths.push({origin:url.origin,path:url.pathname.replace(/[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}/gi,':fixture-id'),method:request.method()});
  });
  page.on('requestfailed', request => failures.push({path:new URL(request.url()).pathname,
    failure:request.failure()?.errorText || 'network failure'}));
  page.on('pageerror', () => errors.push('Browser page error'));
  page.on('response', response => {
    const endpoint = new URL(response.url()).pathname;
    if (['/api/v1/auth/login','/api/v1/auth/refresh'].includes(endpoint))
      auth.push({path:endpoint,status:response.status()});
    if (response.status() >= 400) errors.push(`HTTP ${response.status()} ${endpoint.replace(/[a-f0-9-]{36}/gi,':fixture-id')}`);
  });
}

async function boot(context) {
  const page = context.pages()[0] || await context.newPage(); observe(page);
  const response = await page.goto(origin,{waitUntil:'networkidle',timeout:60000});
  assert.equal(response.status(),200);
  await page.waitForFunction(() => !document.getElementById('startup-status'),null,{timeout:60000});
  await page.locator('flt-glass-pane').waitFor({state:'attached'});
  const accessibility = page.locator('flt-semantics-placeholder');
  if (await accessibility.count()) await accessibility.evaluate(element => element.click());
  await page.waitForLoadState('networkidle');
  return page;
}

async function click(locator) {
  await locator.waitFor({state:'attached',timeout:20000});
  // Flutter RTL semantics nodes may have transformed DOM hit rectangles.
  // Activates the rendered semantic control; never injects API/state data.
  await locator.evaluate(element => element.click());
}
async function bodyIncludes(page, text) {
  await page.waitForFunction(needle => document.body.textContent.includes(needle) ||
    [...document.querySelectorAll('[aria-label]')].some(element =>
      element.getAttribute('aria-label').includes(needle)),text,{timeout:20000});
}
async function school(page) {
  await click(page.getByRole('button',{name:'مدرسه من',exact:true}));
  await bodyIncludes(page,'انتخاب پایه و رشته');
}
async function lesson(page, course, unit) {
  await page.getByLabel('جستجوی کتاب',{exact:true}).fill(course.titleFa);
  await click(page.getByRole('button',{name:new RegExp('^' + escaped(course.titleFa) + ' ')}));
  await bodyIncludes(page,'جستجوی درس یا صفحه');
  await page.getByLabel('جستجوی درس یا صفحه',{exact:true}).fill(unit.titleFa);
  await click(page.getByRole('button',{name:new RegExp('^' + escaped(unit.titleFa) + ' ')}));
  await bodyIncludes(page,'پیشرفت شخصی:');
}

(async () => {
  ca = await fs.readFile(process.env.ROOT_CA);
  const profile = await fs.mkdtemp(path.join(os.tmpdir(),'lifeguide-learning-browser-'));
  const launch = () => chromium.launchPersistentContext(profile,{headless:true,
    executablePath:process.env.LIFEGUIDE_TEST_CHROMIUM_PATH || '/usr/bin/chromium',
    ignoreHTTPSErrors:false,serviceWorkers:'allow',timezoneId:'Asia/Tehran',
    viewport:{width:1100,height:1050}});
  let context;
  try {
    stage = 'realTLS';
    assert.equal((await api('GET','/health')).status,200); check('independent verified HTTPS health');
    const loggedIn = await api('POST','/v1/auth/login',{email,password});
    assert.equal(loggedIn.status,200); const token = loggedIn.json.accessToken;
    const profileResult = await api('GET','/v1/profile',undefined,token);
    assert.equal(profileResult.status,200); const owner = profileResult.json.user_id;
    assert(uuid.test(owner));
    assert.equal((await api('GET','/v1/education/library',undefined,token)).json.education,null,
      'Use a new fixture with no preselected education.');

    context = await launch(); let page = await boot(context);
    stage = 'realLogin';
    await page.getByLabel('ایمیل یا شماره تلفن',{exact:true}).fill(email);
    await page.getByLabel('ایمیل یا شماره تلفن',{exact:true}).press('Tab');
    await page.getByLabel('رمز عبور',{exact:true}).fill(password);
    await page.getByLabel('رمز عبور',{exact:true}).press('Tab');
    const loginResponse = page.waitForResponse(response => response.url().endsWith('/api/v1/auth/login') && response.request().method() === 'POST');
    await click(page.getByRole('button',{name:'ورود',exact:true}));
    const browserLogin = await loginResponse;
    const entered = browserLogin.request().postDataJSON();
    assert(entered.password === password,'Synthetic browser password field was not committed.');
    assert((entered.email ?? entered.identifier) === email,'Synthetic browser contact field was not committed.');
    assert.equal(browserLogin.status(),200);
    await school(page); check('compiled PWA actual synthetic account login');

    stage = 'educationSelection';
    await click(page.getByRole('button',{name:'انتخاب پایه و رشته',exact:true}));
    // The dropdown is an actual Flutter semantic button, not a native select.
    await click(page.getByRole('button',{name:'پایه',exact:true}));
    await click(page.getByRole('menuitem',{name:'پایه 1',exact:true}));
    const educationResponse = page.waitForResponse(response => response.url().endsWith('/api/v1/me/education') && response.request().method() === 'PUT');
    await click(page.getByRole('button',{name:'ذخیره',exact:true}));
    assert.equal((await educationResponse).status(),200);
    const library = (await api('GET','/v1/education/library',undefined,token)).json;
    assert.deepEqual(library.education,{nationalGrade:1,trackCode:'common',schoolYear:'1405-1406'});
    const course = library.courses.find(item => item.unitCount > 0 && item.reviewCandidateCount > 0);
    assert(course); const detail = (await api('GET',`/v1/education/courses/${course.id}`,undefined,token)).json;
    const unit = detail.units.find(item => item.reviewCandidateCount > 0);
    assert(unit && uuid.test(unit.id),'A real draft resource must exist behind the publication gate.');
    assert(detail.units.every(item => item.videos.length === 0));
    assert.equal((await api('GET','/v1/me/learning-progress',undefined,token)).json.progress.length,0,
      'Browsing a library must not fabricate learning progress.');
    check('grade1 common1405-1406 saved through UI and read by independent API');

    stage = 'libraryLesson'; await lesson(page,course,unit);
    await bodyIncludes(page,'ویدیوی بازبینی‌شده و منتشرشده هنوز ثبت نشده');
    assert.equal(await page.locator('iframe').count(),0);
    assert.equal((await api('GET','/v1/me/learning-progress',undefined,token)).json.progress.length,0,
      'Opening a lesson must not automatically record learning progress.');
    check('actual imported lesson renders with draft videos unavailable, no iframe');

    stage = 'progress';
    const progressResponse = page.waitForResponse(response => response.url().includes('/api/v1/me/learning-progress/') && response.request().method() === 'PUT');
    await click(page.getByRole('button',{name:'در حال یادگیری',exact:true}));
    const ackResponse = await progressResponse; assert.equal(ackResponse.status(),200);
    const ack = await ackResponse.json(); assert.equal(ack.source,'self_reported');
    assert.equal(ack.unitId,unit.id); assert.equal(ack.status,'in_progress'); assert.equal(ack.version,1);
    const independent = (await api('GET','/v1/me/learning-progress',undefined,token)).json.progress;
    assert.equal(independent.length,1); assert.equal(independent[0].status,'in_progress');
    const stored = dbJson(`select json_build_object('count',count(*),'status',max(status),'source',max(source),'version',max(version)) from learning_progress where owner_user_id='${owner}' and unit_id='${unit.id}';`);
    assert.deepEqual(stored,{count:1,status:'in_progress',source:'self_reported',version:1});
    await page.waitForLoadState('networkidle');
    await fs.mkdir(path.dirname(receiptFile),{recursive:true});
    await page.screenshot({path:receiptFile.replace(/\.json$/, '-progress.png'),fullPage:false});
    check('UI progress acknowledgement independently verified through API and PostgreSQL');

    stage = 'quizGate';
    const quizResponse = page.waitForResponse(response => response.url().endsWith(`/api/v1/education/units/${unit.id}/assessment`));
    await click(page.getByRole('button',{name:'تمرین فهم درس و مرور',exact:true}));
    const quiz = await quizResponse; assert.equal(quiz.status(),200);
    assert.deepEqual(await quiz.json(),{assessment:null,reason:'review_pending'});
    await bodyIncludes(page,'آزمون این درس در انتظار بازبینی است');
    check('real draft assessment gate shows no invented question bank');
    await click(page.getByRole('button',{name:'برگشتن',exact:true}));

    stage = 'feedback';
    await click(page.getByRole('button',{name:'گزارش ایراد این درس',exact:true}));
    const syntheticSummary = 'SYNTHETIC_BROWSER_FEEDBACK_NO_PERSONAL_DATA';
    const summaryInput = page.getByLabel('خلاصه ایراد یا پیشنهاد',{exact:true});
    await summaryInput.pressSequentially(syntheticSummary,{delay:5});
    await summaryInput.press('Tab');
    const postsBefore = paths.filter(item => item.path === '/api/v1/education/feedback' && item.method === 'POST').length;
    await click(page.getByRole('button',{name:'ارسال بازخورد',exact:true}));
    await bodyIncludes(page,'خلاصه و رضایت ارسال را تکمیل کن.');
    assert.equal(paths.filter(item => item.path === '/api/v1/education/feedback' && item.method === 'POST').length,postsBefore);
    await click(page.getByRole('checkbox'));
    const feedbackResponse = page.waitForResponse(response => response.url().endsWith('/api/v1/education/feedback') && response.request().method() === 'POST');
    await click(page.getByRole('button',{name:'ارسال بازخورد',exact:true}));
    const sent = await feedbackResponse; assert.equal(sent.status(),201);
    const feedback = (await sent.json()).feedback; assert(uuid.test(feedback.id));
    await bodyIncludes(page,'بازخورد در سرور ثبت شد');
    assert.equal((await api('GET','/v1/me/education-feedback',undefined,token)).json.feedback[0].summary,syntheticSummary);
    check('feedback blocked without explicit consent then acknowledged by real server');
    const withdrawnResponse = page.waitForResponse(response => response.url().endsWith(`/api/v1/me/education-feedback/${feedback.id}`) && response.request().method() === 'DELETE');
    await click(page.getByRole('button',{name:'پس‌گرفتن رضایت',exact:true}));
    assert.equal((await withdrawnResponse).status(),204);
    await bodyIncludes(page,'رضایت ارسال پس گرفته شد');
    const withdrawn = (await api('GET','/v1/me/education-feedback',undefined,token)).json.feedback[0];
    assert.equal(withdrawn.summary,null); assert.equal(withdrawn.shareWithContentTeam,false); assert(withdrawn.withdrawnAt);
    const redacted = dbJson(`select json_build_object('count',count(*),'summaryRedacted',bool_and(summary is null),'consentWithdrawn',bool_and(not share_with_content_team),'withdrawn',bool_and(withdrawn_at is not null)) from learning_content_feedback where owner_user_id='${owner}' and id='${feedback.id}';`);
    assert.deepEqual(redacted,{count:1,summaryRedacted:true,consentWithdrawn:true,withdrawn:true});
    check('withdrawal redacts chosen text and consent in independent API and PostgreSQL');

    stage = 'restart';
    await page.goto('about:blank'); await context.close(); context = null;
    context = await launch(); page = await boot(context);
    await school(page); await lesson(page,course,unit);
    await page.waitForLoadState('networkidle');
    assert(auth.some(item => item.path === '/api/v1/auth/refresh' && item.status === 200));
    const afterRestart = (await api('GET','/v1/me/learning-progress',undefined,token)).json.progress;
    assert.equal(afterRestart.length,1); assert.equal(afterRestart[0].version,1);
    assert.equal(await page.locator('iframe').count(),0);
    check('closed and reopened Chromium refreshes persisted session; independent API retains one acknowledged progress record');

    stage = 'networkAudit';
    assert.equal(paths.filter(item => item.origin !== origin).length,0);
    assert.equal(errors.length,0); assert.equal(failures.length,0);
    assert(paths.some(item => item.path.includes('/canvaskit/') && item.path.endsWith('.wasm')));
    for (const font of ['LifeGuidePersian.ttf','LifeGuideLatin.ttf','LifeGuideEmoji.ttf'])
      assert(paths.some(item => item.path.endsWith(font)));
    check('real compiled runtime uses only local API, fonts and CanvasKit without errors');
    await fs.mkdir(path.dirname(receiptFile),{recursive:true});
    await page.screenshot({path:screenshotFile,fullPage:false});
    const receipt = {date:new Date().toISOString(),mode:'Actual isolated local Compose HTTPS; normal Node and Chromium CA trust; no network interception or TLS bypass',
      origin,browser:'Chromium',checks,fixture:'Dedicated synthetic account; no real family/private/media data',
      counts:{requests:paths.length,externalRequests:0,iframes:0,browserErrors:0,failedRequests:0},
      realApprovedVideoCount:0,realApprovedQuestionBankCount:0,
      visualEvidence:{progressScreenshot:path.basename(receiptFile.replace(/\.json$/, '-progress.png')),
        reopenedLessonScreenshot:path.basename(screenshotFile),
        automatedDynamicProgressSemantics:'UNVERIFIED: dynamic progress/timestamp text was absent from Chromium ARIA after updates; inspect rendered screenshots separately'},
      interactionMode:'Rendered Flutter semantic controls activated with DOM element.click because RTL hit rectangles are transformed; text entered through rendered fields and keyboard. No API or state injection. Physical touch/pointer/accessibility acceptance is UNVERIFIED.',
      authResponses:auth,fonts:[...new Set(paths.filter(item => /\.(ttf|otf|woff2)$/.test(item.path)).map(item => item.path))],
      limitations:['Real Android devices UNVERIFIED','Safari/Add to Home Screen UNVERIFIED','Video playback and teaching quality UNVERIFIED','Iran VPN-free reachability UNVERIFIED','Offline cold startup UNVERIFIED','Dynamic progress accessibility semantics after updates remain unverified; screenshots require separate visual review']};
    await fs.writeFile(receiptFile,JSON.stringify(receipt,null,2)+'\n');
    console.log(JSON.stringify(receipt,null,2));
  } catch (error) {
    if (process.env.LEARNING_BROWSER_DIAGNOSTICS && context && stage !== 'realLogin') {
      const page = context.pages()[0];
      const file = path.resolve(process.env.LEARNING_BROWSER_DIAGNOSTICS);
      assert(!file.startsWith(root + path.sep), 'Private diagnostics must stay outside the repo.');
      if (page) await fs.writeFile(file,(await page.locator('body').ariaSnapshot())
        .replaceAll(email,'[synthetic fixture]').replaceAll(password,'[redacted]'),{mode:0o600});
      if (page) await page.screenshot({path:file + '.png',fullPage:false});
    }
    console.error(`FAIL ${stage}: ${error.message.replaceAll(email,'[synthetic fixture]').replaceAll(password,'[redacted]')}`);
    throw new Error(`Local learning browser acceptance failed at ${stage}`);
  } finally {
    if(context) { for(const page of context.pages()) await page.goto('about:blank').catch(()=>{}); await context.close(); }
    await fs.rm(profile,{recursive:true,force:true});
  }
})().catch(error => {console.error(error.message);process.exitCode=1;});
