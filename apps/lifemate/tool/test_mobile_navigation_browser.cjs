// Compiled Flutter + real local API/PostgreSQL acceptance substitute.
// Test fixture only. Never prints credentials, tokens, or request bodies.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const https = require('node:https');
const {chromium} = require('playwright');
const {Client} = require('../../../backend/node_modules/pg');
const origin = 'https://127.0.0.1:8447';
const fixture = JSON.parse(fs.readFileSync(process.env.LG_NAVIGATION_FIXTURE, 'utf8'));
assert(fixture.syntheticOnly && fixture.email.endsWith('@example.test'));
const database = new URL(process.env.LG_NAVIGATION_DATABASE_URL);
assert(database.hostname === '127.0.0.1' && database.port === '55439' &&
  database.pathname.startsWith('/lifeguide_navigation_'), 'Only the isolated local fixture DB is allowed.');
const out = path.resolve(process.argv[2] || '/tmp/lifeguide-navigation-browser-evidence');
fs.mkdirSync(out, {recursive:true});
const ca = fs.readFileSync(process.env.LG_TEST_CA_FILE);
const db = new Client({connectionString:database.href});
const checks = [], errors = [], origins = new Set();
let browser, currentPage, stage = 'startup';
const record = name => { checks.push({name,result:'PASS'}); console.log('PASS ' + name); };
function api(method, endpoint, body, token) {
  return new Promise((resolve,reject)=>{
    const serialized = body === undefined ? null : Buffer.from(JSON.stringify(body));
    const req = https.request(origin + '/api' + endpoint, {method,ca,rejectUnauthorized:true,
      headers:{...(serialized ? {'content-type':'application/json','content-length':serialized.length}:{}),
        ...(token ? {authorization:'Bearer '+token}:{})}},res=>{
      assert(res.socket.authorized);let data='';
      res.on('data',chunk=>data+=chunk);res.on('end',()=>{
        try {resolve({status:res.statusCode,body:JSON.parse(data)});}catch{reject(Error('Non-JSON API response'));}
      });
    });req.setTimeout(15000,()=>req.destroy(Error('API timeout')));req.on('error',reject);req.end(serialized);
  });
}
async function click(locator) {
  await locator.waitFor({state:'attached',timeout:20000});
  // Flutter RTL semantics activation; widget tests separately check hit targets.
  await locator.evaluate(e=>e.click());
}
async function text(page, value) {
  await page.waitForFunction(v=>document.body.textContent.includes(v) ||
    [...document.querySelectorAll('[aria-label]')].some(e=>e.getAttribute('aria-label').includes(v)),value,{timeout:20000});
}
(async()=>{
  await db.connect();
  const login = await api('POST','/v1/auth/login',{email:fixture.email,password:fixture.password});
  assert.equal(login.status,200);const token = login.body.accessToken;
  assert.equal(typeof token,'string');
  browser=await chromium.launch({executablePath:process.env.LIFEGUIDE_TEST_CHROMIUM_PATH || '/usr/bin/chromium',args:['--no-sandbox']});
  const context=await browser.newContext({viewport:{width:390,height:844},ignoreHTTPSErrors:false});
  const page=await context.newPage();currentPage=page;
  page.on('pageerror',()=>errors.push('JavaScript page error'));
  page.on('request',r=>{const u=new URL(r.url());if(/^https?:/.test(u.protocol))origins.add(u.origin);});
  const boot=async()=>{
    const res=await page.goto(origin,{waitUntil:'networkidle',timeout:60000});assert.equal(res.status(),200);
    await page.waitForFunction(()=>!document.getElementById('startup-status'),null,{timeout:60000});
    const sem=page.locator('flt-semantics-placeholder');if(await sem.count())await sem.evaluate(e=>e.click());
  };
  const btn=name=>page.getByRole('button',{name,exact:typeof name==='string'});
  stage='login';await boot();
  await page.getByLabel('ایمیل یا شماره تلفن',{exact:true}).fill(fixture.email);
  await page.getByLabel('رمز عبور',{exact:true}).fill(fixture.password);
  await click(btn('ورود'));
  await btn(/برنامه من/).waitFor({timeout:30000});
  await page.screenshot({path:path.join(out,'LifeGuide-Flutter-home.png')});
  record('HTTPS login and approved compact Flutter home');
  stage='create';await click(btn(/برنامه من/));await click(btn('جدید'));
  await page.getByLabel('عنوان',{exact:true}).waitFor({state:'attached'});
  const title='تکلیف ساختگی ناوبری '+Date.now().toString(36);
  await page.getByLabel('عنوان',{exact:true}).fill(title);
  await click(btn(/^نوع/));await click(page.getByRole('menuitem',{name:'تکلیف',exact:true}));
  await click(btn('ذخیره'));await text(page,title);
  let rows=await db.query('select id,kind,status,version from plan_item where owner_user_id=$1 and title=$2',[fixture.userId,title]);
  assert.equal(rows.rowCount,1);assert.equal(rows.rows[0].kind,'assignment');const id=rows.rows[0].id;
  const read=await api('GET','/v1/plan-items/'+id,undefined,token);assert.equal(read.status,200);assert.equal(read.body.title,title);
  record('UI homework create independently confirmed by API and PostgreSQL');
  stage='restart';await page.reload({waitUntil:'networkidle'});
  await page.waitForFunction(()=>!document.getElementById('startup-status'),null,{timeout:60000});
  const semanticsAfterRestart=page.locator('flt-semantics-placeholder');
  if(await semanticsAfterRestart.count())await semanticsAfterRestart.evaluate(e=>e.click());
  await btn(/برنامه من/).waitFor({timeout:30000});await click(btn(/برنامه من/));await text(page,title);
  record('page restart restores session and server-backed record');
  stage='edit';await click(btn(new RegExp('^'+title)));await text(page,'جزئیات تکلیف');
  await click(btn('ویرایش تکلیف'));await page.getByLabel('عنوان',{exact:true}).fill(title+' ویرایش');
  await click(btn('ذخیره'));await text(page,title+' ویرایش');await text(page,'توسط سرور تأیید شد');
  assert.equal((await api('GET','/v1/plan-items/'+id,undefined,token)).body.title,title+' ویرایش');
  await page.screenshot({path:path.join(out,'LifeGuide-Flutter-task.png')});
  record('selected detail edit persists with server acknowledgement');
  stage='study';await click(btn('شروع مطالعه این تکلیف'));await click(btn('شروع مطالعه'));
  await btn('مکث').waitFor({timeout:20000});await page.waitForTimeout(1200);await click(btn('مکث'));
  await click(btn('ادامه'));await page.waitForTimeout(1200);await click(btn('پایان'));
  await text(page,'جلسه پایان‌یافته');
  await click(btn('برگشتن').last());await text(page,'جزئیات تکلیف');
  await click(btn('انجام شد'));await text(page,'توسط سرور تأیید شد');
  assert.equal((await api('GET','/v1/plan-items/'+id,undefined,token)).body.status,'completed');
  const sessions=await db.query('select status,source,recorded_duration_seconds from study_session where plan_item_id=$1',[id]);
  assert.equal(sessions.rowCount,1);assert.equal(sessions.rows[0].status,'completed');
  record('real study start/pause/resume/stop then task completion uses refreshed version');
  stage='archive';await click(btn('بایگانی'));await text(page,'بایگانی مورد');await click(btn('بایگانی').last());
  await btn('جدید').waitFor({timeout:20000});
  assert.equal((await api('GET','/v1/plan-items/'+id,undefined,token)).body.status,'cancelled');
  assert.equal((await db.query('select status from plan_item where id=$1',[id])).rows[0].status,'cancelled');
  record('confirmed archive persists in PostgreSQL');
  assert.deepEqual(errors,[]);assert.deepEqual([...origins],[origin]);
  fs.writeFileSync(path.join(out,'verification.json'),JSON.stringify({status:'VERIFIED_LOCAL_SYNTHETIC_ONLY',browser:await browser.version(),
    tlsVerified:true,backend:'real local Node/PostgreSQL16; no intercepted API responses',checks,
    javascriptErrors:errors,externalRuntimeOrigins:[...origins].filter(o=>o!==origin),
    studySource:sessions.rows[0].source,recordedSeconds:sessions.rows[0].recorded_duration_seconds,
    unverified:['physical Android/iPhone/Safari','production hosting/deployment','managed-child legacy planner access','real OTP/video/alarms','multi-parent acceptance']},null,2));
})().catch(async e=>{console.error('FAIL '+stage+': '+e.message);if(currentPage)await currentPage.screenshot({path:path.join(out,'failure-diagnostic.png')});process.exitCode=1;}).finally(async()=>{
  if(browser)await browser.close();await db.end();
});
