#!/usr/bin/env node
'use strict';
const {chromium}=require('playwright');
const fs=require('node:fs/promises'),path=require('node:path'),crypto=require('node:crypto');
const root=path.resolve(__dirname,'..'),out=path.join(root,'exports');
const base=new URL(process.env.DESIGN_BASE_URL || 'http://127.0.0.1:8772/LifeGuide-preview.html');
(async()=>{
  if(!['127.0.0.1','localhost','[::1]'].includes(base.hostname))throw Error('Only a local design server is allowed');
  await fs.mkdir(path.join(out,'screenshots'),{recursive:true});
  const b=await chromium.launch({executablePath:process.env.CHROMIUM_PATH||'/usr/bin/chromium',args:['--no-sandbox']});
  try{
    const p=await b.newPage({viewport:{width:2200,height:1200},deviceScaleFactor:1});
    await p.goto(base.href);await p.evaluate(()=>document.fonts.ready);
    const {screens,boardFrames}=await p.evaluate(()=>({screens:window.LifeGuideDesign.screens,boardFrames:window.LifeGuideDesign.boardFrames}));
    const images=[];
    for(const frame of boardFrames){
      const url=new URL(base);url.searchParams.set('board','1');url.searchParams.set('frame',frame.id);
      await p.goto(url.href);await p.evaluate(()=>document.fonts.ready);
      const file=`screenshots/${frame.id}.png`;
      await p.locator('.board-panel').screenshot({path:path.join(out,file)});
      images.push({...frame,file});
    }
    for(const theme of ['calm','bright']){
      const url=new URL(base);url.searchParams.set('board','1');url.searchParams.set('direction',theme);
      await p.goto(url.href);await p.evaluate(()=>document.fonts.ready);
      await p.addStyleTag({content:'.board-grid{grid-template-columns:repeat(3,390px)}'});
      await p.screenshot({path:path.join(out,`LifeGuide-${theme}-three-screens.png`),fullPage:true});
    }
    const boardURL=new URL(base);boardURL.searchParams.set('board','1');
    await p.goto(boardURL.href);await p.evaluate(()=>document.fonts.ready);
    const boardSize=await p.locator('.board-mode').boundingBox();
    await p.screenshot({path:path.join(out,'LifeGuide-overview.png'),fullPage:true});
    // PDF keeps searchable vector text. The oversized sheet is intentional:
    // it is a zoomable board, not a document printed on A4.
    await p.pdf({path:path.join(out,'LifeGuide-overview.pdf'),width:`${Math.ceil(boardSize.width)}px`,height:`${Math.ceil(boardSize.height)+16}px`,printBackground:true,margin:{top:'0',right:'0',bottom:'0',left:'0'}});
    const tiles=images.map(i=>`<a href="${i.file}" aria-label="${i.title}"><img src="${i.file}" loading="lazy" alt="${i.title}؛ طرح تعاملی با داده ساختگی"><span>${i.title}</span></a>`).join('');
    await fs.writeFile(path.join(out,'gallery.html'),`<!doctype html><html lang="fa" dir="rtl"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>LifeGuide · گالری طراحی v2</title><style>body{font:16px/1.8 sans-serif;margin:24px;background:#f2f5f0;color:#203a32}h1{font-size:26px}main{display:grid;grid-template-columns:repeat(auto-fit,minmax(240px,1fr));gap:24px}a{color:#245c4c;background:white;padding:12px;border:1px solid #788b80;border-radius:16px;display:block;text-decoration:none}img{width:100%;height:420px;object-fit:contain;object-position:top}span{display:block;padding:12px}</style><h1>LifeGuide · گالری طراحی v2</h1><p>همهٔ داده‌ها ساختگی‌اند. تصویرها برای بزرگ‌نمایی باز می‌شوند؛ این گالری برنامهٔ عملیاتی نیست.</p><main>${tiles}</main></html>`);
    // Actual browser view at mobile size, in addition to full-content board frames.
    await p.setViewportSize({width:390,height:844});
    for(const name of ['home','lesson','parent-home']){
      const url=new URL(base);url.searchParams.set('screen',name);
      await p.goto(url.href);await p.evaluate(()=>document.fonts.ready);
      await p.screenshot({path:path.join(out,`screenshots/viewport-${name}-390.png`),fullPage:true});
    }
    const source=await fs.readFile(path.join(out,'LifeGuide-preview.html'));
    const manifest={status:'VERIFIED_EXPORTS_ONLY',createdAt:new Date().toISOString(),browser:await b.version(),screenCount:screens.length,boardFrameCount:images.length,sourceSha256:crypto.createHash('sha256').update(source).digest('hex'),boardSize,images,unverified:['Safari','physical devices','Iran reachability','real video','student usability test']};
    await fs.writeFile(path.join(out,'export-manifest.json'),JSON.stringify(manifest,null,2)+'\n');
    console.log(JSON.stringify({status:manifest.status,screenCount:screens.length,boardFrameCount:images.length,boardSize,htmlSha256:manifest.sourceSha256}));
  }finally{await b.close();}
})().catch(e=>{console.error(e.message);process.exitCode=1;});
