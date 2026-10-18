import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { buildSupabaseQaSql } from '../scripts/build-supabase-qa-sql.js';

test('QA bundle retains original checksums plus additive identity and planner migrations and keeps private lockdown', async () => {
  const { sql, manifest } = await buildSupabaseQaSql();
  assert.equal(manifest.length, 24);
  assert.ok(manifest.slice(0,20).every((x,i) => x.filename.startsWith(String(i+1).padStart(4,'0')+'_')));
  assert.equal(manifest[20].filename, '0023_auth_ip_rate_limit.sql');
  assert.equal(manifest[21].filename, '0024_child_device_safety.sql');
  assert.equal(manifest[22].filename, '0025_managed_guardian_authority.sql');
  assert.equal(manifest[23].filename, '0026_personal_planner_series.sql');
  assert.match(sql, /create table planner_series/);
  assert.match(sql, /plan_item_series_private/);
  assert.match(sql, /create table auth_ip_rate_limit/);
  assert.ok(manifest.every(x => /^[a-f0-9]{64}$/.test(x.sha256)));
  assert.match(sql, /set local search_path=lifeguide_qa,extensions,pg_catalog/);
  assert.equal((sql.match(/set search_path=lifeguide_qa,pg_catalog/gi) ?? []).length, 5);
  assert.equal((sql.match(/set search_path=public,pg_catalog/gi) ?? []).length, 0);
  assert.match(sql, /create table if not exists lifeguide_qa.schema_migration/);
  assert.match(sql, /force row level security/);
  assert.match(sql, /revoke all on schema lifeguide_qa from public, anon, authenticated, service_role/);
  assert.doesNotMatch(sql, /create extension if not exists pgcrypto/i);
  assert.doesNotMatch(sql, /alter schema public owner/i);
  assert.doesNotMatch(sql, /reassign owned/i);
  assert.doesNotMatch(sql, /create role/i);
  assert.equal((sql.match(/^begin;/gm) ?? []).length, 1);
  assert.equal((sql.match(/^commit;/gm) ?? []).length, 1);
});

test('QA bundle generation fails closed if source migration count is incomplete', async () => {
  const dir = await mkdtemp(join(tmpdir(),'lifeguide-qa-missing-'));
  try {
    await writeFile(join(dir,'0001_identity_family.sql'),'select 1;');
    await assert.rejects(buildSupabaseQaSql({ migrationsDir:pathToFileURL(dir+'/') }),/expected_baseline_and_auth_migrations_in_order/);
  } finally { await rm(dir,{recursive:true,force:true}); }
});

test('QA bundle generation rejects drift adding production schema privileges', async () => {
  const dir = await mkdtemp(join(tmpdir(),'lifeguide-qa-drift-'));
  try {
    for (let n=1;n<=20;n++) {
      const id=String(n).padStart(4,'0');
      const sql=n===1?'create extension if not exists pgcrypto;\nselect 1;':n===19?
        Array(5).fill('create function test_fn() returns int language sql set search_path=public,pg_catalog as $$select 1$$;').join('\n'):
        'select 1;';
      await writeFile(join(dir,`${id}_test.sql`),sql);
    }
    await writeFile(join(dir,'0023_auth_ip_rate_limit.sql'), 'select 1;');
    await writeFile(join(dir,'0024_child_device_safety.sql'), 'select 1;');
    await writeFile(join(dir,'0025_managed_guardian_authority.sql'), 'select 1;');
    await writeFile(join(dir,'0026_personal_planner_series.sql'), 'select 1;');
    await writeFile(join(dir,'0004_test.sql'),'create table public.account(id int);');
    await assert.rejects(buildSupabaseQaSql({ migrationsDir:pathToFileURL(dir+'/') }),/source_migration_outside_private_qa:0004_test.sql/);
  } finally { await rm(dir,{recursive:true,force:true}); }
});
