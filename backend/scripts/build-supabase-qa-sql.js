// Build a one-time, QA-only copy of the baseline plus reviewed additive DDL.
// Existing provider-applied 0001..0020 bundles remain historical and unchanged.
// This script outputs SQL, does NOT connect to a DB and cannot deploy by itself.
// Crucially, original migration files / Compose role-provisioning stay unchanged.
import { readdir, readFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';

const sourceRoot = new URL('../migrations/', import.meta.url);
const targetSchema = 'lifeguide_qa';
const digest = value => createHash('sha256').update(value, 'utf8').digest('hex');

function normalizeMigration(filename, source) {
  let sql = source.trim();
  const wrapped = /^begin\s*;/i.test(sql) && /commit\s*;$/i.test(sql);
  if (/^begin\s*;/i.test(sql) !== /commit\s*;$/i.test(sql)) {
    throw new Error(`unbalanced_migration_transaction:${filename}`);
  }
  if (wrapped) sql = sql.replace(/^begin\s*;/i, '').replace(/commit\s*;$/i, '');

  // The host already provides pgcrypto; never change global extensions in QA.
  const extension = /create\s+extension\s+if\s+not\s+exists\s+pgcrypto\s*;/ig;
  const extCount = [...sql.matchAll(extension)].length;
  if ((filename.startsWith('0001_') ? 1 : 0) !== extCount) {
    throw new Error(`unexpected_pgcrypto_statement:${filename}`);
  }
  sql = sql.replace(extension, '-- pgcrypto already installed by Supabase (unchanged).');

  // Original school guard functions pin public as search_path. Keep their SQL
  // behaviour but make their QA copies refer exclusively to the private schema.
  const oldFunctionPath = /set\s+search_path\s*=\s*public\s*,\s*pg_catalog/ig;
  const n = [...sql.matchAll(oldFunctionPath)].length;
  if (n !== (filename.startsWith('0019_') ? 5 : 0)) throw new Error(`unexpected_function_search_path:${filename}`);
  sql = sql.replace(oldFunctionPath, `set search_path=${targetSchema},pg_catalog`);

  // The additive auth migration removes PUBLIC access to its one metadata
  // table. The QA wrapper below already revokes ALL tables for every client
  // role. Allow only this exact restriction; arbitrary GRANT/REVOKE still fails.
  if (filename === '0023_auth_ip_rate_limit.sql') {
    sql = sql.replace(/^revoke all on auth_ip_rate_limit from public;$/m,
      '-- Auth metadata is included in the QA wrapper table-wide lockdown.');
  }
  if (filename === '0024_child_device_safety.sql') {
    sql = sql.replace(/^revoke all on managed_child,child_consent,child_device_invitation,guardian_invitation from public;$/m,
      '-- Child identity tables are included in the QA wrapper lockdown.');
  }

  // Fail closed if a future source migration changes its privilege/schema rules.
  if (/\b(?:public|auth|storage|realtime)\s*\./i.test(sql) ||
      /\b(?:create|alter|drop)\s+(?:role|database|schema|extension)\b/i.test(sql) ||
      /\bsecurity\s+definer\b/i.test(sql) ||
      /\b(?:grant|revoke|truncate)\s+(?:all|select|insert|update|delete|usage|execute|on|table|schema|function)\b/i.test(sql)) {
    throw new Error(`source_migration_outside_private_qa:${filename}`);
  }
  return sql;
}

export async function buildSupabaseQaSql({ migrationsDir = sourceRoot } = {}) {
  const entries = (await readdir(migrationsDir)).filter(name => /^\d{4}_[a-z0-9_]+\.sql$/.test(name)).sort();
  const expected = [...Array.from({length:20}, (_,i) => String(i+1).padStart(4,'0')), '0023', '0024', '0025'];
  if (entries.length !== expected.length ||
      entries.some((name, i) => name.slice(0,4) !== expected[i]) ||
      entries[20] !== '0023_auth_ip_rate_limit.sql' || entries[21] !== '0024_child_device_safety.sql' ||
      entries[22] !== '0025_managed_guardian_authority.sql') {
    throw new Error('expected_baseline_and_auth_migrations_in_order');
  }

  const parts = [`begin;
set local lock_timeout='5s';
set local statement_timeout='120s';
set local search_path=lifeguide_qa,extensions,pg_catalog;
do $qa_preflight$
begin
  if current_database() <> 'postgres'
     or to_regnamespace('lifeguide_qa') is null
     or to_regclass('lifeguide_qa.setup_probe') is null
     or not exists (select 1 from pg_extension where extname='pgcrypto')
     or has_schema_privilege('anon','lifeguide_qa','USAGE')
     or has_schema_privilege('authenticated','lifeguide_qa','USAGE') then
    raise exception 'lifeguide_qa_preflight_denied';
  end if;
end
$qa_preflight$;

create table if not exists lifeguide_qa.schema_migration (
 filename text primary key,
 sha256 text not null check (sha256 ~ '^[a-f0-9]{64}$'),
 applied_at timestamptz not null default now()
);`];
  const manifest = [];
  for (const filename of entries) {
    const raw = await readFile(new URL(filename, migrationsDir), 'utf8');
    const source = normalizeMigration(filename, raw);
    const sha256 = digest(raw);
    manifest.push({ filename, sha256 });
    // The only interpolated source is the fixed, validated migration files.
    parts.push(`-- Original migration ${filename}; source sha256 ${sha256}
${source}
insert into lifeguide_qa.schema_migration(filename,sha256)
values ('${filename}','${sha256}');`);
  }

  parts.push(`
-- Supabase Data API and JWT roles have no direct access to these tables.
revoke all on schema lifeguide_qa from public, anon, authenticated, service_role;
revoke all on all tables in schema lifeguide_qa from public, anon, authenticated, service_role;
revoke all on all sequences in schema lifeguide_qa from public, anon, authenticated, service_role;
revoke all on all functions in schema lifeguide_qa from public, anon, authenticated, service_role;
alter default privileges in schema lifeguide_qa revoke all on tables from public,anon,authenticated,service_role;
alter default privileges in schema lifeguide_qa revoke all on sequences from public,anon,authenticated,service_role;
alter default privileges in schema lifeguide_qa revoke execute on functions from public,anon,authenticated,service_role;
do $qa_lockdown$
declare obj record;
begin
  for obj in select c.relname
       from pg_class c join pg_namespace n on n.oid=c.relnamespace
       where n.nspname='lifeguide_qa' and c.relkind in ('r','p')
  loop
    execute format('alter table %I.%I enable row level security','lifeguide_qa',obj.relname);
    execute format('alter table %I.%I force row level security','lifeguide_qa',obj.relname);
  end loop;
end
$qa_lockdown$;
commit;`);

  return { sql: parts.join('\n'), manifest };
}

// Utility for local review only; stdout may contain DDL but never credentials.
if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  const result = await buildSupabaseQaSql();
  if (process.argv.includes('--manifest')) console.log(JSON.stringify(result.manifest,null,2));
  else if (process.argv.includes('--sql')) process.stdout.write(result.sql);
  else throw new Error('Specify --manifest or --sql; no database connection is ever made');
}
