// Operations acceptance against freshly generated synthetic databases only.
// Run separately from the maintainer suite: its API uses runtime credentials.
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import pg from 'pg';
import {prepareRoles,reconcileGrants,roleNames} from './db-role-policy.js';

const mode=process.argv[2];
assert.ok(['--synthetic-only','--verify-restored','--cleanup'].includes(mode),'Use an explicit synthetic test phase');
assert.equal(process.argv.length,3,'No database identifiers may be passed on the command line');
assert.ok(['postgres','localhost','127.0.0.1','::1'].includes(process.env.PGHOST ?? 'localhost'),'Only the local test PostgreSQL host is allowed');
assert.ok(process.env.ROLE_TEST_STATE_FILE,'Set a private local ROLE_TEST_STATE_FILE');
const backend=path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const expectedMigrations=(await fs.readdir(path.join(backend,'migrations'))).filter(name=>name.endsWith('.sql')).sort();
const adminConfig={host:process.env.PGHOST ?? 'localhost',port:Number(process.env.PGPORT ?? 5432),user:process.env.PGUSER,password:process.env.PGPASSWORD,database:process.env.PGDATABASE};
const admin=new pg.Client(adminConfig);
const statePath=process.env.ROLE_TEST_STATE_FILE;
const ident=(name)=>`"${name.replaceAll('"','""')}"`;
const clientFor=(database,kind)=>new pg.Client({...adminConfig,database,user:roleNames[kind],password:process.env[`${{api:'API',migrator:'MIGRATOR',backup:'BACKUP'}[kind]}_DB_PASSWORD`]});
let state;
async function readState() {
  const value=JSON.parse(await fs.readFile(statePath,'utf8'));
  assert.match(value.run,/^[a-f0-9]{16}$/);
  assert.equal(value.source_db,`lifeguide_roles_source_${value.run}`);
  assert.equal(value.target_db,`lifeguide_roles_target_${value.run}`);
  return value;
}
async function taggedDatabase(database) {
  const result=await admin.query(`SELECT pg_get_userbyid(datdba) owner,shobj_description(oid,'pg_database') marker FROM pg_database WHERE datname=$1`,[database]);
  if(!result.rowCount) return false;
  assert.equal(result.rows[0].owner,(await admin.query('SELECT current_user')).rows[0].current_user,'Refusing another owner database');
  assert.equal(result.rows[0].marker,`LifeGuide synthetic role acceptance ${state.run}`,'Refusing an untagged database');
  return true;
}
async function denied(client,sql,label) {
  try { await client.query(sql); assert.fail(`${label} unexpectedly succeeded`); }
  catch(error) { assert.equal(error.code,'42501',`${label} must be denied by PostgreSQL permissions`); }
  console.log(`PASS denied: ${label}`);
}
async function checkPolicy(database) {
  const runtime=clientFor(database,'api'), backup=clientFor(database,'backup'), migrator=clientFor(database,'migrator');
  await Promise.all([runtime.connect(),backup.connect(),migrator.connect()]);
  try {
    for(const [kind,client] of [['api',runtime],['backup',backup],['migrator',migrator]]) {
      const row=(await client.query(`SELECT current_user,rolsuper,rolcreatedb,rolcreaterole,rolreplication,rolbypassrls,rolinherit
        FROM pg_roles WHERE rolname=current_user`)).rows[0];
      assert.equal(row.current_user,roleNames[kind]);
      for(const flag of ['rolsuper','rolcreatedb','rolcreaterole','rolreplication','rolbypassrls','rolinherit']) assert.equal(row[flag],false,`${kind}.${flag}`);
      assert.equal((await client.query("SELECT EXISTS(SELECT 1 FROM pg_auth_members m JOIN pg_roles r ON r.oid=m.member WHERE r.rolname=current_user) value")).rows[0].value,false);
    }
    const capabilities=(await runtime.query(`SELECT has_database_privilege(current_user,current_database(),'CREATE') db_create,
      has_database_privilege(current_user,current_database(),'TEMP') db_temp,has_schema_privilege(current_user,'public','CREATE') schema_create,
      pg_has_role(current_user,'lifeguide_migrator','MEMBER') migrator_member,
      EXISTS(SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relowner=(SELECT oid FROM pg_roles WHERE rolname=current_user)) owns_objects`)).rows[0];
    assert.ok(Object.values(capabilities).every(value=>value===false));
    assert.equal((await migrator.query("SELECT pg_get_userbyid(nspowner) owner FROM pg_namespace WHERE nspname='public'")).rows[0].owner,roleNames.migrator);
    assert.equal((await migrator.query("SELECT count(*)::int n FROM schema_migration WHERE sha256 IS NOT NULL")).rows[0].n,expectedMigrations.length);
    await denied(runtime,'CREATE TABLE public.forbidden_runtime_table(id integer)','runtime CREATE TABLE');
    await denied(runtime,'CREATE TEMP TABLE forbidden_runtime_temp(id integer)','runtime TEMP');
    await denied(runtime,'ALTER TABLE public.plan_item ADD COLUMN forbidden_runtime_column integer','runtime ALTER TABLE');
    await denied(runtime,"ALTER ROLE lifeguide_migrator PASSWORD 'synthetic-forbidden-only'",'runtime ALTER other ROLE');
    await denied(runtime,'ALTER ROLE lifeguide_api SUPERUSER','runtime privilege escalation');
    await denied(runtime,'SET ROLE lifeguide_migrator','runtime SET ROLE migrator');
    await denied(runtime,"INSERT INTO public.schema_migration(filename) VALUES('forbidden-role-test')",'runtime ledger INSERT');
    await denied(runtime,"UPDATE public.schema_migration SET sha256='forbidden'",'runtime ledger UPDATE');
    await denied(runtime,'DELETE FROM public.schema_migration','runtime ledger DELETE');
    await denied(runtime,'SELECT * FROM public.schema_migration','runtime ledger SELECT unnecessary');
    await denied(runtime,'TRUNCATE public.plan_item','runtime TRUNCATE');
    for(const table of ['curriculum_subject','textbook_catalog','learning_unit','learning_video_resource','learning_assessment',
      'content_capability_grant','content_capability_audit','content_publication_audit']) {
      assert.equal((await runtime.query(`SELECT count(*)::int n FROM public.${ident(table)}`)).rows.length,1);
      await denied(runtime,`INSERT INTO public.${ident(table)} DEFAULT VALUES`,`${table}: runtime catalog INSERT`);
      const field=table==='content_capability_grant'?'user_id':table==='content_publication_audit'?'mutation_id':'id';
      await denied(runtime,`UPDATE public.${ident(table)} SET ${field}=${field}`,`${table}: runtime catalog UPDATE/publication`);
      await denied(runtime,`DELETE FROM public.${ident(table)}`,`${table}: runtime catalog DELETE`);
    }
    for(const table of ['content_review_audit','content_review_mutation','content_review_brief','content_review_brief_source',
      'learning_goal_mutation','family_lifecycle_mutation','school_lifecycle_mutation']) {
      const field=['learning_goal_mutation','school_lifecycle_mutation'].includes(table)?'owner_user_id':
        ['content_review_mutation','family_lifecycle_mutation'].includes(table)?'actor_user_id':
        table==='content_review_brief_source'?'brief_id':'id';
      assert.equal((await runtime.query(`SELECT count(*)::int n FROM public.${ident(table)}`)).rows.length,1);
      await denied(runtime,`UPDATE public.${ident(table)} SET ${field}=${field}`,`${table}: runtime immutable receipt UPDATE`);
      await denied(runtime,`DELETE FROM public.${ident(table)}`,`${table}: runtime immutable receipt DELETE`);
    }
    await denied(backup,'UPDATE public.app_user SET id=id','backup UPDATE');
    await denied(backup,'CREATE TABLE public.forbidden_backup_table(id integer)','backup CREATE TABLE');
    await denied(backup,'CREATE TEMP TABLE forbidden_backup_temp(id integer)','backup TEMP');
    await denied(backup,'SELECT public.recompute_reminder_schedule(NULL)','backup side-effect application function');
    await denied(backup,"SELECT setval('public.access_audit_id_seq',999)",'backup sequence setval');
    assert.equal((await backup.query('SELECT count(*)::int n FROM public.schema_migration')).rows[0].n,expectedMigrations.length);
    console.log('PASS runtime/migrator/backup flags, ownership, memberships and backup ledger read');
    await migrator.query('CREATE TABLE public.future_role_probe(id integer PRIMARY KEY,value text)');
    try {
      await migrator.query("INSERT INTO public.future_role_probe VALUES(1,'synthetic-only')");
      assert.equal((await runtime.query('SELECT value FROM public.future_role_probe WHERE id=1')).rows[0].value,'synthetic-only');
      await migrator.query("UPDATE public.future_role_probe SET value='updated-synthetic' WHERE id=1");
      assert.equal((await backup.query('SELECT value FROM public.future_role_probe WHERE id=1')).rows[0].value,'updated-synthetic');
      await denied(runtime,"INSERT INTO public.future_role_probe VALUES(2,'forbidden')",'future-table runtime INSERT failclosed');
      await denied(runtime,'UPDATE public.future_role_probe SET id=id','future-table runtime UPDATE failclosed');
      await denied(runtime,'DELETE FROM public.future_role_probe','future-table runtime DELETE failclosed');
      await denied(runtime,'ALTER TABLE public.future_role_probe ADD COLUMN forbidden integer','future-table ownership retained by migrator');
      console.log('PASS future migrator-created table: default runtime/backup SELECT, write/DDL denied');
    } finally { await migrator.query('DROP TABLE public.future_role_probe'); }
  } finally { await Promise.all([runtime.end(),backup.end(),migrator.end()]); }
}
async function migrate(database) {
  const env={...process.env,PGDATABASE:database,PGUSER:roleNames.migrator,PGPASSWORD:process.env.MIGRATOR_DB_PASSWORD};
  delete env.DATABASE_URL;
  const result=spawnSync(process.execPath,['scripts/migrate.js'],{cwd:backend,env,stdio:'inherit'});
  assert.equal(result.status,0,'Non-superuser migration failed');
  const imported=spawnSync(process.execPath,['scripts/import-learning-catalog.js'],{cwd:backend,env,stdio:'inherit'});
  assert.equal(imported.status,0,'Non-superuser catalogue import failed');
}
try {
  await admin.connect();
  if(mode==='--synthetic-only') {
    state={run:crypto.randomBytes(8).toString('hex')};
    state.source_db=`lifeguide_roles_source_${state.run}`;
    state.target_db=`lifeguide_roles_target_${state.run}`;
    state.created=[];
    await fs.writeFile(statePath,JSON.stringify(state),{mode:0o600,flag:'wx'});
    for(const database of [state.source_db,state.target_db]) {
      await admin.query(`CREATE DATABASE ${ident(database)}`);
      state.created.push(database);
      await fs.writeFile(statePath,JSON.stringify(state),{mode:0o600});
      await admin.query(`COMMENT ON DATABASE ${ident(database)} IS 'LifeGuide synthetic role acceptance ${state.run}'`);
      const db=new pg.Client({...adminConfig,database}); await db.connect();
      try {
        if(database===state.target_db) {
          await admin.query(`ALTER DATABASE ${ident(database)} OWNER TO lifeguide_api`);
          try {
            await assert.rejects(prepareRoles(db),/must not own any database/);
            // Also verify an API-owned OTHER database blocks source provisioning.
            const other=new pg.Client({...adminConfig,database:state.source_db}); await other.connect();
            try { await assert.rejects(prepareRoles(other),/must not own any database/); } finally { await other.end(); }
            assert.equal((await admin.query('SELECT pg_get_userbyid(datdba) owner FROM pg_database WHERE datname=$1',[database])).rows[0].owner,roleNames.api);
          } finally { await admin.query(`ALTER DATABASE ${ident(database)} OWNER TO ${ident(adminConfig.user)}`); }
          await admin.query(`ALTER DATABASE ${ident(database)} OWNER TO lifeguide_migrator`);
          try { await assert.rejects(prepareRoles(db),/must not own any database/); }
          finally { await admin.query(`ALTER DATABASE ${ident(database)} OWNER TO ${ident(adminConfig.user)}`); }
          await db.query('CREATE SCHEMA runtime_owned_probe AUTHORIZATION lifeguide_api');
          try { await assert.rejects(prepareRoles(db),/ownership outside granted application data access is forbidden/); }
          finally { await db.query('DROP SCHEMA runtime_owned_probe'); }
          await db.query('CREATE SCHEMA backup_object_probe');
          await db.query('CREATE TABLE backup_object_probe.fixture(id integer)');
          await db.query('ALTER TABLE backup_object_probe.fixture OWNER TO lifeguide_backup');
          try { await assert.rejects(prepareRoles(db),/ownership outside granted application data access is forbidden/); }
          finally { await db.query('DROP TABLE backup_object_probe.fixture'); await db.query('DROP SCHEMA backup_object_probe'); }
          await db.query('CREATE SCHEMA pgfixture_probe');
          try {
            await db.query('GRANT CREATE ON SCHEMA pgfixture_probe TO PUBLIC');
            await assert.rejects(prepareRoles(db),/Unknown non-system schema/);
            await db.query('REVOKE CREATE ON SCHEMA pgfixture_probe FROM PUBLIC');
            await db.query('GRANT CREATE ON SCHEMA pgfixture_probe TO lifeguide_api');
            await assert.rejects(prepareRoles(db),/Unknown non-system schema/);
            await db.query('REVOKE CREATE ON SCHEMA pgfixture_probe FROM lifeguide_api');
            await db.query('GRANT USAGE ON SCHEMA pgfixture_probe TO PUBLIC');
            await db.query("CREATE FUNCTION pgfixture_probe.privileged_probe() RETURNS integer LANGUAGE SQL SECURITY DEFINER AS 'SELECT 1'");
            await assert.rejects(prepareRoles(db),/Unknown non-system schema/);
            await db.query('DROP FUNCTION pgfixture_probe.privileged_probe()');
          } finally { await db.query('DROP SCHEMA pgfixture_probe'); }
          console.log('PASS failclosed preflight: current/other API-owned DB, migrator-owned DB, non-public API-owned schema, backup-owned relation, PUBLIC/direct schema CREATE and auxiliary SECURITY DEFINER; no automatic ownership or unrelated ACL repair');
        }
        await prepareRoles(db);
      } finally { await db.end(); }
    }
    await migrate(state.source_db); await migrate(state.source_db);
    const source=new pg.Client({...adminConfig,database:state.source_db}); await source.connect();
    try {
      await reconcileGrants(source);
      await source.query(await fs.readFile(new URL('./restore-smoke.sql',import.meta.url),'utf8').then(text=>text.replace(/^\\set.*$/gm,'')));
      const fixture=process.env.DB_ROLE_RESTORE_FIXTURE ?? fileURLToPath(new URL('../../deployment/restore-fixture.sql',import.meta.url));
      await source.query(await fs.readFile(fixture,'utf8').then(text=>text.replace(/^\\set.*$/gm,'')));
    } finally { await source.end(); }
    await checkPolicy(state.source_db);
    const url=new URL('postgresql://localhost'); url.hostname=adminConfig.host; url.port=String(adminConfig.port);
    url.pathname=`/${state.source_db}`; url.username=roleNames.api; url.password=process.env.API_DB_PASSWORD;
    const fixtureUrl=new URL(url); fixtureUrl.username=roleNames.migrator; fixtureUrl.password=process.env.MIGRATOR_DB_PASSWORD;
    const env={...process.env,TEST_FIXTURE_DATABASE_URL:fixtureUrl.toString(),DATABASE_URL:url.toString(),PGUSER:roleNames.api,PGPASSWORD:process.env.API_DB_PASSWORD,PGDATABASE:state.source_db,
      JWT_SECRET:'synthetic-runtime-route-secret-at-least-32-characters',
      SMS_PROVIDER:'disabled',EMAIL_PROVIDER:'disabled',ENABLE_SENSITIVE_FEATURES:'false'};
    for(const key of ['SMS_PROVIDER_URL','SMS_PROVIDER_TOKEN','EMAIL_FROM','RESEND_API_KEY','SMTP_HOST','SMTP_USER','SMTP_PASSWORD',
      'AI_API_KEY','AI_BASE_URL','AI_MODEL','OPENAI_API_KEY']) env[key]='';
    for(const key of ['API_DB_PASSWORD','MIGRATOR_DB_PASSWORD','BACKUP_DB_PASSWORD','POSTGRES_PASSWORD']) delete env[key];
    const familyEnv={...env};delete familyEnv.TEST_FIXTURE_DATABASE_URL;
    // These new identity tests must use the runtime role directly. The broader
    // catalog suite below uses a separate migrator only for fixture setup.
    const family=spawnSync(process.execPath,['--test','--test-concurrency=1','tests/online_acceptance.test.js',
      'tests/child_identity.test.js','tests/managed_child_server.test.js','tests/planner_series.test.js'],{cwd:backend,env:familyEnv,stdio:'inherit'});
    assert.equal(family.status,0,'Runtime-role family HTTP/DB acceptance failed');
    const acceptance=spawnSync(process.execPath,['--test',
      'tests/learning_library.test.js','tests/learning_feedback.test.js','tests/learning_assessment.test.js',
      'tests/content_review.test.js','tests/content_review_validation.test.js',
      'tests/learning_goal_mutations.test.js','tests/family_lifecycle.test.js','tests/family_lifecycle_validation.test.js',
      'tests/school_lifecycle.test.js','tests/report_periods.test.js','tests/learning_unit_locator.test.js'],{cwd:backend,env,stdio:'inherit'});
    assert.equal(acceptance.status,0,'Real family/learning HTTP/DB acceptance with runtime role failed');
    console.log('PASS role acceptance source: fresh checksum migrations + repeat, restrictive SQL capabilities and runtime family/learning/goals/school/report/locator HTTP scenarios');
    console.log(`Synthetic restore state saved; source=${state.source_db}; target=${state.target_db}`);
  } else {
    state=await readState();
    if(mode==='--verify-restored') {
      assert.ok(await taggedDatabase(state.target_db));
      const target=new pg.Client({...adminConfig,database:state.target_db}); await target.connect();
      try {
        await reconcileGrants(target);
        assert.equal((await target.query("SELECT count(*)::int n FROM schema_migration WHERE sha256 IS NOT NULL")).rows[0].n,expectedMigrations.length);
        assert.equal((await target.query("SELECT recorded_duration_seconds FROM study_session WHERE id='00000000-0000-4000-8000-000000000005'")).rows[0].recorded_duration_seconds,600);
        assert.equal((await target.query("SELECT pg_get_userbyid(extowner) owner FROM pg_extension WHERE extname='pgcrypto'")).rows[0].owner,roleNames.migrator);
      } finally { await target.end(); }
      await migrate(state.target_db); await checkPolicy(state.target_db);
      const runtime=clientFor(state.target_db,'api'); await runtime.connect();
      try {
        assert.equal((await runtime.query("SELECT count(*)::int n FROM app_user WHERE identity_subject='restore-smoke'")).rows[0].n,1);
        assert.equal((await runtime.query("SELECT count(*)::int n FROM profile WHERE display_name='Restore Smoke'")).rows[0].n,1);
        assert.equal((await runtime.query("SELECT can_view_plan_item('00000000-0000-4000-8000-000000000005','00000000-0000-4000-8000-000000000005') allowed")).rows[0].allowed,true);
        assert.equal((await runtime.query("SELECT can_view_plan_item('00000000-0000-4000-8000-000000000005','00000000-0000-4000-8000-000000000006') allowed")).rows[0].allowed,false);
        assert.equal((await runtime.query("SELECT can_view_plan_item('00000000-0000-4000-8000-000000000007','00000000-0000-4000-8000-000000000005') allowed")).rows[0].allowed,false);
      } finally { await runtime.end(); }
      console.log('PASS restored checksum ledger entries, migrator ownership/repeat, runtime denial matrix, guardian/private policy and paused-study600seconds');
    } else {
      for(const database of state.created ?? []) {
        assert.ok([state.source_db,state.target_db].includes(database),'Refusing unrelated cleanup');
        if(await taggedDatabase(database)) {
          await admin.query(`DROP DATABASE ${ident(database)}`);
        }
      }
      console.log('PASS cleanup: only tagged newly-created role-test databases dropped; application DB preserved');
    }
  }
} finally { await admin.end(); }
