import {readFile, writeFile, readdir} from 'node:fs/promises';
import {join} from 'node:path';

const root = process.argv[2] || 'build/web';
async function walk(path) {
  const files = [];
  for (const entry of await readdir(path, {withFileTypes: true})) {
    const location = join(path, entry.name);
    if (entry.isDirectory()) files.push(...await walk(location));
    else if (/\.(?:js|json|html)$/.test(entry.name)) files.push(location);
  }
  return files;
}
for (const file of await walk(root)) {
  let source = await readFile(file, 'utf8');
  // SDK defaults remain in generated JS despite the configured local loader.
  // Neutralize these exact known defaults; never rewrite an operator API URL.
  source = source.replaceAll('https://www.gstatic.com/flutter-canvaskit', 'canvaskit')
    .replaceAll('https://fonts.gstatic.com/s/', 'assets/fonts/fallback/');
  if (/https?:[^\s"'<>]*(?:gstatic\.com|googleapis\.com|up\.railway\.app)/i.test(source)) {
    throw new Error(`Unexpected external runtime URL in ${file}`);
  }
  await writeFile(file, source);
}
console.log('Web resources use local CanvasKit/font bases; external SDK/CDN defaults removed.');
