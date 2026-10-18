#!/usr/bin/env node
'use strict';
// Negative controls exercise the real DOM audit, not hand-written thresholds.
const {chromium}=require('playwright');
const assert=require('node:assert/strict');
const {auditLayout}=require('./check.cjs');
(async()=>{
  const browser=await chromium.launch({executablePath:process.env.CHROMIUM_PATH||'/usr/bin/chromium',args:['--no-sandbox']});
  try{
    const page=await browser.newPage({viewport:{width:320,height:740}});
    const fixtures=[
      ['valid','',null],
      ['font-small','.copy{font-size:11px}','font'],
      ['contrast-low','.copy{color:#aaa}','contrast'],
      ['touch-small','button{width:30px;height:30px;min-width:0;min-height:0;padding:0}','target'],
      ['overflow-horizontal','.copy{width:700px}','overflow'],
      ['clipped-text','.copy{height:8px;overflow:hidden}','clip']
    ];
    const results=[];
    for(const [name,change,expected] of fixtures){
      await page.setContent(`<html lang="fa" dir="rtl"><style>html{font-size:16px}body{margin:0;color:#203a32;background:#fff}.phone{width:300px}.prototype-label{font-size:12px}button{font-size:16px;width:80px;height:48px;color:#203a32;background:#fff}.copy{font-size:16px} ${change}</style><section class="phone" data-screen="fixture" data-state="normal" data-theme="calm"><div class="prototype-label">طرح تعاملی با داده ساختگی</div><main class="screen-content"><p class="copy">متن ساختگی برای بررسی واقعی.</p><button>نمونه</button></main></section></html>`);
      const result=await page.evaluate(auditLayout,{expectedScreen:'fixture',expectedState:'normal',expectedTheme:'calm',fontScale:1,requiredLabel:'طرح تعاملی با داده ساختگی'});
      if(expected){assert.ok(result.problems.some(p=>p.type.includes(expected)),`${name} did not fail for ${expected}`);}
      else assert.equal(result.problems.length,0,JSON.stringify(result.problems));
      results.push({name,expected:expected?'REJECT':'PASS',observedProblems:result.problems.map(p=>p.type),result:'PASS'});
    }
    console.log(JSON.stringify({status:'VERIFIED_CHECKER_NEGATIVE_CONTROLS',results},null,2));
  }finally{await browser.close();}
})().catch(error=>{console.error(error.message);process.exitCode=1;});
