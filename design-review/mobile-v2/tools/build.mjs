import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const [css,js,font,tokens]=await Promise.all([
  fs.readFile(path.join(root,'src/design.css'),'utf8'),fs.readFile(path.join(root,'src/app.js'),'utf8'),
  fs.readFile(path.join(root,'assets/persian.ttf')),fs.readFile(path.join(root,'design-tokens.json'),'utf8')]);
const inlineCss=css.replace("url('../assets/persian.ttf')",`url('data:font/ttf;base64,${font.toString('base64')}')`);
const html=`<!doctype html><html lang="fa" dir="rtl"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; font-src data:; img-src data:; connect-src 'none'; form-action 'none'; base-uri 'none'"><title>LifeGuide · طرح تعاملی ۰۲</title><style>${inlineCss}</style></head><body><div id="app"></div><script>window.DESIGN_TOKENS=${tokens};\n${js.replaceAll('</script','<\\/script')}</script></body></html>`;
await fs.mkdir(path.join(root,'exports'),{recursive:true});
await fs.writeFile(path.join(root,'exports/LifeGuide-preview.html'),html);
console.log(JSON.stringify({status:'BUILT_DESIGN_ONLY',screensSource:'src/app.js',output:'exports/LifeGuide-preview.html',bytes:Buffer.byteLength(html),externalDependencies:0}));
