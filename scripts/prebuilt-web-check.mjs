#!/usr/bin/env node
// This records build inputs only after the operator has actually run the build.
// It does not compile Flutter and must never be reported as a build itself.
import { readFile, readdir, writeFile } from 'node:fs/promises';
import { resolve, join, relative, basename, sep } from 'node:path';
import { createHash } from 'node:crypto';

const app = resolve(process.argv[2] ?? 'apps/lifemate');
const output = join(app, 'build/web');
const stamp = process.argv.includes('--stamp-after-build');
async function walk(directory) {
  const files = [];
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    const path = join(directory, entry.name);
    if (entry.isSymbolicLink()) throw new Error('Symlinks forbidden in web build inputs/artifact');
    if (entry.isDirectory()) files.push(...await walk(path));
    else if (entry.isFile()) files.push(path);
  }
  return files.sort();
}
function assert(condition, message) { if (!condition) throw new Error(message); }
const inputs = [join(app, 'pubspec.yaml'), join(app, 'pubspec.lock'), join(app, 'tool/self_host_web.mjs')];
for (const path of ['lib', 'assets', 'web']) inputs.push(...await walk(join(app, path)));
const hash = createHash('sha256');
for (const path of inputs.sort()) {
  hash.update(relative(app, path).split(sep).join('/')); hash.update('\0');
  hash.update(await readFile(path)); hash.update('\0');
}
const sourceDigest = hash.digest('hex');
const files = await walk(output);
for (const path of files.filter(path => /\.(js|json|html)$/.test(path))) {
  const text = await readFile(path, 'utf8');
  assert(!/https?:[^\s"'<>]*(?:gstatic\.com|googleapis\.com|up\.railway\.app)/i.test(text), `External runtime dependency: ${relative(output, path)}`);
}
for (const path of ['index.html', 'main.dart.js', 'flutter_bootstrap.js', 'lifeguide-sw.js', 'canvaskit/canvaskit.wasm']) {
  assert(files.includes(join(output, path)), `Missing built resource: ${path}`);
}
for (const name of ['LifeGuidePersian.ttf', 'LifeGuideLatin.ttf', 'LifeGuideEmoji.ttf']) {
  assert(files.some(path => basename(path) === name), `Missing local font: ${name}`);
}
const manifest = JSON.parse(await readFile(join(output, 'manifest.json'), 'utf8'));
assert(manifest.name.includes('LifeGuide') && manifest.short_name === 'لایف‌گاید' && manifest.display === 'standalone', 'LifeGuide standalone manifest required');
const config = JSON.parse(await readFile(join(output, 'config.json'), 'utf8'));
assert(config.apiBaseUrl === '/api', 'Prebuilt default API must use runtime same-origin /api');
const builtTitle = /<title>([^<]+)<\/title>/.exec(await readFile(join(output, 'index.html'), 'utf8'))?.[1];
const sourceTitle = /<title>([^<]+)<\/title>/.exec(await readFile(join(app, 'web/index.html'), 'utf8'))?.[1];
assert(builtTitle === sourceTitle && builtTitle?.includes('LifeGuide'), 'LifeGuide HTML title must match source');
for (const path of ['manifest.json', 'favicon.png', 'icons/Icon-192.png', 'icons/Icon-512.png', 'icons/Icon-maskable-192.png', 'icons/Icon-maskable-512.png']) {
  assert((await readFile(join(output, path))).equals(await readFile(join(app, 'web', path))), `Built branding differs from source: ${path}`);
}
const provenance = join(output, 'build-provenance.json');
const artifactHash = createHash('sha256');
for (const path of files.filter(path => path !== provenance)) {
  artifactHash.update(relative(output, path).split(sep).join('/')); artifactHash.update('\0');
  artifactHash.update(await readFile(path)); artifactHash.update('\0');
}
const artifactDigest = artifactHash.digest('hex');
if (stamp) {
  await writeFile(provenance, JSON.stringify({ sourceDigest, artifactDigest, inputFiles: inputs.length, recordedAt: new Date().toISOString(),
    requiredFlutterVersion: '3.47.6', requiredFlutterRevision: '5fc346839b5d0eef006ed8404392afb4dfae428d',
    command: 'flutter build web --release --no-web-resources-cdn --pwa-strategy=none; node tool/self_host_web.mjs build/web',
    limitation: 'Recorded only after a real build; this checker does not compile or prove device acceptance.' }, null, 2) + '\n');
} else {
  const recorded = JSON.parse(await readFile(provenance, 'utf8'));
  assert(recorded.sourceDigest === sourceDigest, 'Source changed after recorded build; rebuild and recheck web before packaging');
  assert(recorded.artifactDigest === artifactDigest, 'Built artifact changed after its recorded check');
}
console.log(`PASS prebuilt LifeGuide web: ${inputs.length} input files, local fonts/CanvasKit, same-origin runtime config, current branding and matching source digest.`);
