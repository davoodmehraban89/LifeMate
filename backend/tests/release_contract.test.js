import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const read = (path) => fs.readFileSync(new URL(`../../${path}`, import.meta.url), 'utf8');

test('release runbooks exist and preserve production approval gates', () => {
  for (const path of [
    'docs/operations/DEPLOYMENT.md',
    'docs/operations/ROLLBACK.md',
    'docs/operations/BACKUP_RESTORE.md',
    'docs/operations/INCIDENT_RESPONSE.md',
    'docs/operations/PRODUCTION_CHECKLIST.md',
    'CHANGELOG.md',
  ]) assert.ok(read(path).length > 100, `${path} must be substantive`);
  assert.match(read('docs/operations/DEPLOYMENT.md'), /staging/i);
  assert.match(read('docs/operations/DEPLOYMENT.md'), /explicit approval/i);
  assert.match(read('docs/operations/ROLLBACK.md'), /rollback/i);
  assert.match(read('docs/operations/BACKUP_RESTORE.md'), /pg_dump/);
  assert.match(read('docs/operations/BACKUP_RESTORE.md'), /pg_restore/);
  assert.match(read('docs/operations/INCIDENT_RESPONSE.md'), /minor-sensitive/i);
  assert.match(read('docs/operations/PRODUCTION_CHECKLIST.md'), /AI.*disabled|disabled.*AI/is);
});
