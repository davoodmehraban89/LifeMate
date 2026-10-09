import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
let checked = 0;
for (const directory of ['src', 'scripts', 'tests']) {
  function walk(folder) {
    for (const entry of fs.readdirSync(folder, {withFileTypes: true})) {
      const file = path.join(folder, entry.name);
      if (entry.isDirectory()) walk(file);
      else if (/\.(js|mjs)$/.test(file)) {
        const result = spawnSync(process.execPath, ['--check', file], {stdio: 'inherit'});
        if (result.status !== 0) process.exit(result.status ?? 1);
        checked++;
      }
    }
  }
  walk(directory);
}
console.log(`Syntax checked ${checked} source/script/test files.`);
