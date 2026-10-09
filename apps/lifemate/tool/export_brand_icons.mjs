// Reuses the Android vector; requires local Playwright and Chromium tooling.
import {createRequire} from 'node:module';
import {readFile} from 'node:fs/promises';
import {execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {dirname, join} from 'node:path';

const root = dirname(dirname(fileURLToPath(import.meta.url)));
execFileSync('python3', [join(root, 'tool/export_brand_icons.py')], {stdio:'inherit'});
const {chromium} = createRequire(import.meta.url)('playwright');
const browser = await chromium.launch({executablePath:process.env.CHROMIUM_PATH || '/usr/bin/chromium', headless:true});
try {
  const page = await browser.newPage();
  for (const [name, svgName, sizes] of [
    ['Icon', 'lifeguide.svg', [192,512]],
    ['Icon-maskable', 'lifeguide-maskable.svg', [192,512]],
    ['favicon', 'lifeguide.svg', [32]],
  ]) {
    const source = (await readFile(join(root,'web/icons',svgName),'utf8'))
      .replace(/<\?xml[^>]*\?>/, '');
    for (const size of sizes) {
      await page.setViewportSize({width:size,height:size});
      await page.setContent('<style>html,body{margin:0;padding:0}</style>' + source);
      await page.locator('svg').evaluate((element, pixels) => {
        element.setAttribute('width', String(pixels));
        element.setAttribute('height', String(pixels));
        element.style.display = 'block';
      },size);
      const output = name === 'favicon' ? join(root,'web/favicon.png') : join(root,'web/icons',`${name}-${size}.png`);
      await page.locator('svg').screenshot({path:output,omitBackground:true});
    }
  }
} finally {
  await browser.close();
}
console.log('PWA icons and favicon rasterized from matching Android-vector SVG sources.');
