// Compiled Flutter, verified local TLS, real HTTP/PostgreSQL. Synthetic only.
// Credentials stay in the private fixture file; API responses are never mocked.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const https = require('node:https');
const crypto = require('node:crypto');
const {execFileSync} = require('node:child_process');
const {chromium} = require('playwright');
const {Client} = require('../../../backend/node_modules/pg');

const fixture = JSON.parse(fs.readFileSync(process.env.LG_WEEKLY_FIXTURE || '/tmp/lifeguide-weekly-browser-qa/fixture.json','utf8'));
assert(fixture.syntheticOnly === true && fixture.email.endsWith('@example.test'));
const database = new URL(fixture.databaseUrl);
assert(database.hostname === '127.0.0.1' && database.port === '55449' &&
  /^\/lifeguide_weekly_browser_test_[a-f0-9]{16}$/.test(database.pathname), 'Disposable loopback fixture only');
const origin = process.env.LG_WEEKLY_ORIGIN || 'https://127.0.0.1:8449';
assert.equal(new URL(origin).hostname,'127.0.0.1');
assert.equal(new URL(origin).protocol,'https:');
const ca = fs.readFileSync(process.env.LG_TEST_CA_FILE || '/tmp/lifeguide-weekly-browser-qa/ca.crt');
const out = path.resolve(process.argv[2] || '/tmp/lifeguide-weekly-browser-evidence');
fs.mkdirSync(out,{recursive:true});
const root = path.resolve(__dirname,'../../..');
const main = path.join(root,'apps/lifemate/build/web/main.dart.js');
const compiledHash = () => crypto.createHash('sha256').update(fs.readFileSync(main)).digest('hex');
const mainAtStart = compiledHash();
const db = new Client({connectionString:database.href});
const checks = [], errors = [], origins = new Set();
let browser, page, stage = 'startup';
const record = name => { checks.push({name,result:'PASS'}); console.log('PASS ' + name); };
const weekdayNames = {1:'دوشنبه',2:'سه‌شنبه',3:'چهارشنبه',4:'پنجشنبه',5:'جمعه',6:'شنبه',7:'یکشنبه'};
const localDay = new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Tehran',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());
const firstWeekday = new Date(localDay + 'T00:00:00Z').getUTCDay() || 7;
const secondWeekday = (firstWeekday + 1) % 7 + 1;
function api(method,endpoint,body,token) {
  return new Promise((resolve,reject) => {
    const data = body === undefined ? null : Buffer.from(JSON.stringify(body));
    const req = https.request(origin + '/api' + endpoint,{method,ca,rejectUnauthorized:true,
      headers:{...(data ? {'content-type':'application/json','content-length':data.length} : {}),
        ...(token ? {authorization:'Bearer ' + token} : {})}},res => {
      assert(res.socket.authorized); let text = '';
      res.on('data',chunk => text += chunk); res.on('end',() => {
        try { resolve({status:res.statusCode,body:JSON.parse(text)}); } catch { reject(Error('Non-JSON API response')); }
      });
    }); req.setTimeout(15000,() => req.destroy(Error('Local API timeout'))); req.on('error',reject); req.end(data);
  });
}
async function click(locator) {
  await locator.waitFor({state:'attached',timeout:20000});
  // Flutter semantics activation; physical hit targets are checked separately.
  await locator.evaluate(element => element.click());
}
const button = name => page.getByRole('button',{name,exact:typeof name === 'string'});
async function enter(locator,value) {
  await locator.focus();
  await locator.press('ControlOrMeta+A');
  await locator.press('Backspace');
  // Real keyboard input keeps Flutter's controller and native semantics input
  // in agreement across rebuilds; setting textarea.value alone is insufficient.
  await locator.pressSequentially(value);
}
async function text(value) {
  await page.waitForFunction(value => document.body.textContent.includes(value) ||
    [...document.querySelectorAll('[aria-label]')].some(e => e.getAttribute('aria-label').includes(value)),value,{timeout:25000});
}
async function semantics() {
  await page.waitForFunction(() => !document.getElementById('startup-status'),null,{timeout:60000});
  const placeholder = page.locator('flt-semantics-placeholder');
  if (await placeholder.count()) await placeholder.evaluate(e => e.click());
}
async function timeInput(locator,hour,minute) {
  await click(locator);
  await page.getByLabel('ساعت',{exact:true}).waitFor({state:'attached'});
  await enter(page.getByLabel('ساعت',{exact:true}),String(hour).padStart(2,'0'));
  await enter(page.getByLabel('دقیقه',{exact:true}),String(minute).padStart(2,'0'));
  await click(button(/^(تأیید|تایید|OK)$/));
  await page.getByLabel('ساعت',{exact:true}).waitFor({state:'detached'});
}
async function waitForDatabaseTitle(id,title) {
  for (let i=0;i<60;i++) {
    const row = (await db.query('select title from plan_item where id=$1',[id])).rows[0];
    if (row?.title === title) return;
    await new Promise(resolve => setTimeout(resolve,500));
  }
  throw Error('Server did not acknowledge offline occurrence edit');
}
(async () => {
  await db.connect();
  const owner = (await db.query('select identity_subject,is_managed_child from app_user where id=$1',[fixture.userId])).rows[0];
  assert(owner?.identity_subject.startsWith('weekly-browser:') && owner.is_managed_child === false);
  // The dedicated, verified fixture contains no user data. Make reruns isolated.
  await db.query('delete from planner_series where owner_user_id=$1',[fixture.userId]);
  const login = await api('POST','/v1/auth/login',{email:fixture.email,password:fixture.password});
  assert.equal(login.status,200); const token = login.body.accessToken; assert.equal(typeof token,'string');
  browser = await chromium.launch({executablePath:process.env.LIFEGUIDE_TEST_CHROMIUM_PATH || '/usr/bin/chromium',args:['--no-sandbox']});
  const context = await browser.newContext({viewport:{width:390,height:844},timezoneId:'Asia/Tehran',ignoreHTTPSErrors:false});
  page = await context.newPage();
  page.on('pageerror',() => errors.push('JavaScript page error'));
  page.on('request',request => { const u=new URL(request.url()); if (/^https?:/.test(u.protocol)) origins.add(u.origin); });
  stage='login';
  const response = await page.goto(origin,{waitUntil:'networkidle',timeout:60000}); assert.equal(response.status(),200); await semantics();
  await page.getByLabel('ایمیل یا شماره تلفن',{exact:true}).fill(fixture.email);
  await page.getByLabel('رمز عبور',{exact:true}).fill(fixture.password);
  await click(button('ورود'));
  await page.getByRole('tab',{name:'برنامه',exact:true}).waitFor({timeout:30000});
  await text('قدم بعدی');
  await page.screenshot({path:path.join(out,'LifeGuide-weekly-home.png')});
  record('verified HTTPS login to compiled Flutter with synthetic standard minor account');

  stage='weekly create';
  await click(page.getByRole('tab',{name:'برنامه',exact:true}));
  await click(button('برنامهٔ تکراری'));
  const title = 'مدرسهٔ ساختگی هفتگی ' + Date.now().toString(36);
  await enter(page.getByLabel('عنوان',{exact:true}),title);
  await click(button(/^نوع/)); await click(page.getByRole('menuitem',{name:'رویداد',exact:true}));
  await click(page.getByRole('checkbox',{name:weekdayNames[secondWeekday],exact:true}));
  const firstGroup = page.getByRole('group',{name:weekdayNames[firstWeekday],exact:true});
  const secondGroup = page.getByRole('group',{name:weekdayNames[secondWeekday],exact:true});
  await timeInput(firstGroup.getByRole('button',{name:/^پایان:/}),12,0);
  await timeInput(secondGroup.getByRole('button',{name:/^شروع:/}),10,0);
  await timeInput(secondGroup.getByRole('button',{name:/^پایان:/}),14,0);
  await click(button(/^یادآوری هر نوبت/)); await click(page.getByRole('menuitem',{name:'۵ دقیقه پیش از شروع',exact:true}));
  await page.screenshot({path:path.join(out,'LifeGuide-weekly-editor.png')});
  await click(button('ثبت برنامه')); await text(title);
  const series = (await db.query('select id,frequency,slots,timezone from planner_series where owner_user_id=$1 and title=$2',[fixture.userId,title])).rows;
  assert.equal(series.length,1); const seriesId=series[0].id;
  assert.equal(series[0].frequency,'weekly'); assert.equal(series[0].timezone,'Asia/Tehran');
  assert.deepEqual(series[0].slots,[{weekday:firstWeekday,start:'08:00',end:'12:00'},{weekday:secondWeekday,start:'10:00',end:'14:00'}].sort((a,b) => a.weekday-b.weekday));
  const items = (await db.query('select p.*,p.original_occurrence_date::text as day from plan_item p where p.series_id=$1 order by p.original_occurrence_date',[seriesId])).rows;
  let expectedCount=0;
  for(let n=0;n<60;n++){const d=new Date(Date.parse(localDay+'T00:00:00Z')+n*86400000);if([firstWeekday,secondWeekday].includes(d.getUTCDay()||7))expectedCount++;}
  assert.equal(items.length,expectedCount);
  assert(items.every(i => i.owner_user_id===fixture.userId && i.visibility==='private' && i.family_id===null));
  const occurrence=items.find(i=>i.day===localDay); assert(occurrence);
  const read=await api('GET','/v1/plan-items/'+occurrence.id,undefined,token);
  assert.equal(read.status,200);assert.equal(read.body.series_id,seriesId);assert.equal(read.body.ends_at,occurrence.ends_at.toISOString());
  assert.equal((await db.query('select count(*)::int n from reminder r join plan_item p on p.id=r.plan_item_id where p.series_id=$1',[seriesId])).rows[0].n,expectedCount);
  await text('میلادی');
  await text('تا 12:00');
  await page.screenshot({path:path.join(out,'LifeGuide-weekly-schedule.png')});
  record('UI creates weekly school with different weekday hours; actual REST and PostgreSQL confirm private unique occurrences');

  stage='complete one';await click(button('انجام شد'));await button('برگرداندن به برنامه').waitFor({timeout:20000});
  assert.equal((await api('GET','/v1/plan-items/'+occurrence.id,undefined,token)).body.status,'completed');
  assert.equal((await db.query("select count(*)::int n from plan_item where series_id=$1 and status='completed'",[seriesId])).rows[0].n,1);
  record('ticking one occurrence leaves every other occurrence independently planned');

  stage='restart';await page.reload({waitUntil:'networkidle'});await semantics();
  await click(page.getByRole('tab',{name:'برنامه',exact:true}));await text(title);await button('برگرداندن به برنامه').waitFor();
  record('page restart restores authenticated server-backed weekly record and completion');

  stage='offline edit';
  // ListTile navigation is a pointer target on Flutter's canvas; activate its
  // visible center rather than dispatching a synthetic DOM click to its label.
  await button(new RegExp('^'+title)).click({force:true});await text('جزئیات تکلیف');
  await click(button('ویرایش تکلیف'));const edited=title+' ویرایش آفلاین';await enter(page.getByLabel('عنوان',{exact:true}),edited);
  await context.setOffline(true);await click(button('ذخیره'));await text('در انتظار تأیید سرور');
  assert.equal((await db.query('select title from plan_item where id=$1',[occurrence.id])).rows[0].title,title);
  record('offline occurrence edit is durably pending while PostgreSQL remains unchanged');
  await context.setOffline(false);await click(button('برگشتن').last());await waitForDatabaseTitle(occurrence.id,edited);
  const fresh=await api('GET','/v1/plan-items/'+occurrence.id,undefined,token);assert.equal(fresh.body.title,edited);
  assert.equal(fresh.body.status,'completed');assert.equal(fresh.body.series_id,seriesId);
  const finalRows=(await db.query('select id,title,status,original_occurrence_date::text as day from plan_item where series_id=$1',[seriesId])).rows;
  assert.equal(finalRows.length,expectedCount);assert.equal(new Set(finalRows.map(i=>i.day)).size,expectedCount);
  assert.equal(finalRows.filter(i=>i.title===edited).length,1);assert.equal(finalRows.filter(i=>i.status==='completed').length,1);
  await page.reload({waitUntil:'networkidle'});await semantics();await click(page.getByRole('tab',{name:'برنامه',exact:true}));await text(edited);
  await page.screenshot({path:path.join(out,'LifeGuide-weekly-reopened.png')});
  record('reconnect and subsequent restart retain one edited occurrence without duplicate generation');
  assert.deepEqual(errors,[]);assert.deepEqual([...origins].filter(o=>o!==origin),[]);
  assert.equal(compiledHash(),mainAtStart,'Compiled assets changed during acceptance; rerun the final build');
  fs.writeFileSync(path.join(out,'verification.json'),JSON.stringify({status:'VERIFIED_LOCAL_SYNTHETIC_ONLY',
    sourceHead:execFileSync('git',['rev-parse','HEAD'],{cwd:root,encoding:'utf8'}).trim(),
    compiledMainSha256:mainAtStart,
    browser:await browser.version(),tlsVerified:true,apiResponsesIntercepted:false,checks,
    recurrence:{frequency:'weekly',timezone:'Asia/Tehran',slots:series[0].slots,occurrenceCount:expectedCount,completedCount:1},
    offlineEditFields:['title'],javascriptErrors:errors,externalRuntimeOrigins:[],
    unverified:['physical Android/iPhone/Safari','background OS alarms','managed-child private planner authorization','offline cold start','production deployment']},null,2));
})().catch(async error => {
  const message=String(error.message).replaceAll(fixture.password,'[fixture credential]');
  console.error('FAIL '+stage+': '+message);
  if(page) await page.screenshot({path:path.join(out,'failure-diagnostic.png')}).catch(()=>{});
  if(page) fs.writeFileSync(path.join(out,'failure-semantics.json'),JSON.stringify(await page.locator('[role],[aria-label]').evaluateAll(es => es.map(e => ({role:e.getAttribute('role'),label:e.getAttribute('aria-label'),text:e.textContent}))),null,2));
  fs.writeFileSync(path.join(out,'failure.json'),JSON.stringify({status:'FAILED_LOCAL_SYNTHETIC',stage,message,checks},null,2));
  process.exitCode=1;
}).finally(async()=>{if(browser)await browser.close();await db.end();});
