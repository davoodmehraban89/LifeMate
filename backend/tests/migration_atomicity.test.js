import test from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import { mkdtemp, mkdir, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import pg from 'pg';

test('migration schema and ledger remain atomic when ledger insert fails', async () => {
  const base = new URL(process.env.DATABASE_URL);
  const name = `lifeguide_migration_${crypto.randomUUID().replaceAll('-', '')}`;
  const admin = new pg.Client({connectionString: base.toString()});
  await admin.connect();
  const folder = await mkdtemp(path.join(tmpdir(), 'lifeguide-migration-'));
  let database;
  try {
    await admin.query(`create database ${name}`);
    const target = new URL(base); target.pathname = `/${name}`;
    database = new pg.Client({connectionString: target.toString()});
    await database.connect();
    await database.query("create table schema_migration(filename text primary key check(filename <> '9999_atomic.sql'), applied_at timestamptz not null default now())");
    await mkdir(path.join(folder, 'migrations'));
    await writeFile(path.join(folder, 'migrations', '9999_atomic.sql'), 'begin;\ncreate table atomic_marker(id integer);\ncommit;\n');
    const result = spawnSync(process.execPath, [fileURLToPath(new URL('../scripts/migrate.js', import.meta.url))], {cwd: folder, env: {...process.env, DATABASE_URL: target.toString()}, encoding: 'utf8'});
    assert.notEqual(result.status, 0, 'deliberate ledger constraint failure must fail');
    assert.equal((await database.query("select to_regclass('atomic_marker') as marker")).rows[0].marker, null, 'schema must roll back together with failed ledger');
  } finally {
    if (database) { await database.end(); await admin.query(`drop database ${name}`); }
    await admin.end();
    await rm(folder, {recursive: true, force: true});
  }
});
