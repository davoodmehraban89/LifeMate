#!/usr/bin/env node
// Regression for a checked CI artifact on a Windows-style Git checkout.
// Requires a real, already built/postprocessed/stamped artifact. Never builds
// Flutter, restamps the artifact, changes repository inputs or touches Docker.
import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { cp, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, relative, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const app = resolve(process.argv[2] ?? fileURLToPath(new URL('../apps/lifemate/', import.meta.url)));
const root = execFileSync('git', ['rev-parse', '--show-toplevel'], { cwd: app, encoding: 'utf8' }).trim();
const appRelative = relative(root, app).split(sep).join('/');
assert(appRelative && !appRelative.startsWith('../') && !appRelative.startsWith('/'), 'Application must be inside the repository');
const checker = join(root, 'scripts/prebuilt-web-check.mjs');
const shellScripts = ['backend/scripts/backup.sh', 'backend/scripts/restore.sh', 'scripts/local-deploy.sh'];
const tracked = execFileSync('git', ['ls-files', '-z', '--', appRelative, ...shellScripts], { cwd: root });
assert(tracked.length > 0, 'Application has no indexed source files');
const binaryInputs = tracked.toString('utf8').split('\0').filter(path => /\.(ttf|otf|woff2?|png|jpe?g|ico|webp)$/i.test(path));

function check(target, label, expectedError) {
  const result = spawnSync(process.execPath, [checker, target], { cwd: root, encoding: 'utf8' });
  if (expectedError) {
    assert(result.status !== 0 && result.stderr.includes(expectedError), `${label}: expected rejection\n${result.stdout}\n${result.stderr}`);
  } else {
    assert.equal(result.status, 0, `${label}: checker failed\n${result.stdout}\n${result.stderr}`);
  }
  console.log(`PASS ${label}`);
}

check(app, 'original checked artifact');
const temporary = await mkdtemp(join(tmpdir(), 'lifeguide-checkout-regression-'));
try {
  for (const [name, autocrlf] of [['lf', 'false'], ['windows', 'true']]) {
    const checkout = join(temporary, name);
    // Git consumes a slash-terminated checkout prefix, including on Windows.
    const prefix = `${checkout.split(sep).join('/')}/`;
    execFileSync('git', ['-c', `core.autocrlf=${autocrlf}`, 'checkout-index', '-z', '--stdin', `--prefix=${prefix}`], { cwd: root, input: tracked });
    const checkedApp = join(checkout, appRelative);
    await cp(join(app, 'build/web'), join(checkedApp, 'build/web'), { recursive: true });
    check(checkedApp, `actual Git checkout core.autocrlf=${autocrlf}`);
    for (const path of shellScripts) {
      const contents = await readFile(join(checkout, path));
      assert(!contents.includes(Buffer.from('\r\n')), `${path} must retain LF for Linux container execution`);
    }
    for (const path of binaryInputs) {
      assert((await readFile(join(checkout, path))).equals(await readFile(join(root, path))), `${path} binary bytes changed during checkout`);
    }
    console.log(`PASS core.autocrlf=${autocrlf}: three shell scripts retain LF; ${binaryInputs.length} font/icon binaries are byte-identical`);
    if (name === 'windows') {
      const source = join(checkedApp, 'lib/main.dart');
      const originalSource = await readFile(source);
      await writeFile(source, Buffer.concat([originalSource, Buffer.from('\n// synthetic source integrity probe\n')]));
      check(checkedApp, 'source change is still rejected', 'Source changed after recorded build');
      await writeFile(source, originalSource);
      const artifact = join(checkedApp, 'build/web/main.dart.js');
      await writeFile(artifact, Buffer.concat([await readFile(artifact), Buffer.from('\n// synthetic artifact integrity probe\n')]));
      check(checkedApp, 'artifact change is still rejected', 'Built artifact changed after its recorded check');
    }
  }
  console.log('PASS prebuilt checkout regression: provenance, Windows checkout, shell endings, binary preservation and tamper rejection; no build or restamp performed.');
} finally {
  await rm(temporary, { recursive: true, force: true });
}
