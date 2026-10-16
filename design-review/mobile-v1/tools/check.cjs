const {chromium}=require('playwright');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const base=process.env.DESIGN_BASE_URL || 'http://127.0.0.1:8769/';
const receipt=process.env.DESIGN_RECEIPT || path.resolve(__dirname,'../exports/verification.json');
(async()=>{
 const b=await chromium.launch({executablePath:process.env.CHROMIUM_PATH || '/usr/bin/chromium',headless:true,args:['--no-sandbox']});
 const p=await b.newPage({viewport:{width:390,height:844}}),errors=[],external=[],checks=[];
 p.on('pageerror',e=>errors.push(e.message));p.on('request',r=>{if(/^https?:/.test(r.url())&&new URL(r.url()).origin!==new URL(base).origin)external.push(r.url())});
 const load=async(query='')=>{await p.goto(base+query);await p.locator('.phone').first().waitFor();await p.evaluate(()=>document.fonts.ready)};
 const at=async(name)=>assert.equal(await p.locator('.phone').getAttribute('data-screen'),name);
 for(const [width,height]of[[390,844],[320,740]]){
  await p.setViewportSize({width,height});await load();assert.equal(await p.locator('.screen-content').evaluate(e=>e.scrollHeight-e.clientHeight),0,'Home menus should fit without scrolling');
  for(const [i,r]of['plan','courses','focus','family','report','reminders'].entries()){
   await p.locator('.menu-card').nth(i).click();await at(r);await p.getByRole('button',{name:'برگشت',exact:true}).click();await at('home');
  }
  assert.ok(await p.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
  assert.ok(await p.locator('.bottom-nav').evaluate(e=>e.getBoundingClientRect().bottom<=innerHeight));
  checks.push({check:'six menu destinations, back, fixed navigation, no horizontal overflow',width,height,result:'PASS'});
 }
 await p.setViewportSize({width:390,height:844});await load('?screen=plan');
 await p.locator('.task-main').nth(1).click();await at('task');assert.match(await p.locator('.task-detail-head h2').textContent(),/خواندن یک متن کوتاه/);
 checks.push({check:'Persian task opens its own details rather than the mathematics task',result:'PASS'});
 await load('?screen=plan');await p.getByRole('button',{name:'یک کار تازه',exact:true}).click();await p.getByLabel('عنوان کار').fill('کار ساختگی آزمایشی');await p.getByLabel('زمان برنامه').fill('19:00');await p.getByRole('button',{name:'اعمال در پیش‌نمایش',exact:true}).click();
 assert.equal(await p.locator('.task-main').count(),4);await p.locator('.task-main').last().click();assert.equal(await p.locator('.task-detail-head h2').textContent(),'کار ساختگی آزمایشی');
 await p.getByRole('button',{name:'ویرایش زمان',exact:true}).click();await p.getByLabel('عنوان کار').fill('کار ساختگی ویرایش‌شده');await p.getByRole('button',{name:'اعمال در پیش‌نمایش',exact:true}).click();assert.equal(await p.locator('.task-detail-head h2').textContent(),'کار ساختگی ویرایش‌شده');
 checks.push({check:'add and edit a temporary design task with visible result',result:'PASS'});
 await load('?screen=lesson');await p.getByRole('button',{name:'تمام‌صفحه',exact:true}).click();assert.equal(await p.locator('.full-video').count(),1);await p.getByRole('button',{name:'بستن تمام‌صفحه',exact:true}).click();assert.equal(await p.locator('.full-video').count(),0);await at('lesson');
 checks.push({check:'player frame expands and closes inside same design; no external media loaded',result:'PASS'});
 await p.getByRole('button',{name:'شروع آزمونک · ۱۰ پرسش',exact:true}).click();
 for(const index of[0,1,2,3,1,0,2,3,1,0]){
  await p.locator('.answers button').nth(index).click();await p.getByRole('button',{name:'بررسی پاسخ',exact:true}).click();assert.equal(await p.locator('.answer-feedback').count(),1);await p.getByRole('button',{name:/^(پرسش بعدی|دیدن نتیجه)$/}).click();
 }
 assert.equal((await p.locator('.result-score').textContent()).trim(),'۱۰ از ۱۰ پاسخ درست');
 checks.push({check:'ten-question draft quiz with explanatory feedback and result',result:'PASS'});
 await load('?screen=focus');await p.getByRole('button',{name:'شروع نوبت',exact:true}).click();await p.waitForTimeout(1200);await p.getByRole('button',{name:'توقف موقت',exact:true}).click();const paused=await p.locator('.timer-ring strong').textContent();assert.notEqual(paused,'۲۵:۰۰');await p.waitForTimeout(1100);assert.equal(await p.locator('.timer-ring strong').textContent(),paused);await p.getByRole('button',{name:'استراحت ۵ دقیقه‌ای',exact:true}).click();assert.equal(await p.locator('.timer-ring strong').textContent(),'۰۵:۰۰');
 checks.push({check:'foreground timer starts, pauses and switches to five-minute break',result:'PASS'});
 await load('?screen=reminders');const sw=p.getByRole('switch').first();assert.equal(await sw.getAttribute('aria-checked'),'true');await sw.click();assert.equal(await sw.getAttribute('aria-checked'),'false');
 checks.push({check:'reminder switch toggles its explicit state; no device alarm',result:'PASS'});
 await p.getByRole('button',{name:'والد',exact:true}).click();assert.equal(await p.locator('.phone').getAttribute('data-role'),'parent');await p.locator('.child-card').click();await at('report');assert.match(await p.locator('.freshness').textContent(),/دادهٔ زنده نیست/);
 checks.push({check:'separate parent home and explicitly non-live sample report',result:'PASS'});
 await p.setViewportSize({width:2700,height:2600});await load('?board=1');assert.equal(await p.locator('.board-panel').count(),12);const overflow=await p.locator('.board-panel main').evaluateAll(es=>es.map(e=>e.scrollHeight-e.clientHeight));assert.ok(overflow.every(n=>n===0));
 checks.push({check:'all twelve board panels show their full initial content',overflow,result:'PASS'});
 assert.equal(errors.length,0);assert.equal(external.length,0);
 await p.context().setOffline(true);await p.getByRole('button',{name:'بازگشت به پیش‌نمایش',exact:true}).click();await p.locator('.menu-card').first().click();await at('plan');await p.context().setOffline(false);
 checks.push({check:'loaded self-contained design remains navigable while browser network is offline',result:'PASS'});
 const result={status:'VERIFIED_PROTOTYPE_ONLY',browser:await b.version(),checks,passed:checks.length,javascriptErrors:errors,externalRequests:external,localFileOpen:'UNVERIFIED: file:// opening blocked by execution environment policy',unverified:['Safari/iPhone device','actual backend data and permissions','real video playback','system alarms and widgets','production deployment']};
 fs.writeFileSync(receipt,JSON.stringify(result,null,2));console.log(JSON.stringify(result,null,2));await b.close();
})().catch(e=>{console.error(e.message);process.exit(1)});
