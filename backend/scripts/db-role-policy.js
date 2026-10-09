// Operations-only policy. Keep application object names stable; these are not
// product labels. No REASSIGN OWNED, catalog writes or broad ownership transfer.
import crypto from 'node:crypto';
import fs from 'node:fs/promises';

export const applicationTables = [
  'academic_term', 'academic_year', 'access_audit', 'activity_state_event',
  'ai_guide_message', 'ai_guide_session', 'ai_plan_proposal', 'app_user',
  'auth_credential', 'auth_delivery_attempt', 'auth_phone_challenge', 'auth_session',
  'auth_token', 'class_session', 'curriculum_subject', 'education_profile',
  'family_invitation', 'family_membership', 'family_workspace', 'guardian_relationship',
  'iran_calendar_event', 'learning_checkin', 'learning_goal', 'life_context',
  'menstrual_cycle_entry', 'notification_outbox', 'notification_preference',
  'plan_item', 'profile', 'reminder', 'schema_migration', 'sharing_grant',
  'study_interval', 'study_mutation', 'study_session', 'subject', 'sync_mutation',
  'textbook_catalog', 'wellbeing_checkin', 'wellbeing_safety_event',
];
export const applicationTypes = ['member_role', 'invitation_status', 'visibility_scope',
  'auth_token_kind', 'life_context_kind', 'plan_item_kind', 'plan_item_status',
  'plan_priority', 'sharing_scope', 'reminder_status'];
export const applicationSequences = ['access_audit_id_seq', 'notification_outbox_id_seq',
  'study_interval_id_seq', 'activity_state_event_id_seq'];
export const applicationFunctions = [
  'is_active_family_member(uuid, uuid)', 'is_family_admin(uuid, uuid)',
  'is_active_guardian(uuid, uuid, uuid)', 'can_view_student_academic(uuid, uuid)',
  'can_view_plan_item(uuid, uuid)', 'recompute_reminder_schedule(uuid)',
  'plan_item_revision()', 'revoke_changed_plan_item_grants()',
  'revoke_ended_membership_grants()', 'plan_item_legacy_activity()',
];
export const roleNames = Object.freeze({ api: 'lifeguide_api', migrator: 'lifeguide_migrator', backup: 'lifeguide_backup' });
const ident = (value) => `"${String(value).replaceAll('"', '""')}"`;
export function validateRoles(env) {
  const configured = { api: env.API_DB_USER ?? roleNames.api, migrator: env.MIGRATOR_DB_USER ?? roleNames.migrator, backup: env.BACKUP_DB_USER ?? roleNames.backup };
  for (const kind of Object.keys(roleNames)) {
    if (configured[kind] !== roleNames[kind]) throw new Error('Use the three canonical, distinct application role names');
  }
  return configured;
}

async function grantUuidDefault(client,roles) {
  // Existing table DEFAULT expressions bind to pgcrypto's public UUID function,
  // even when the runtime search_path prefers the equivalent pg_catalog one.
  // Allow only this value-generating extension function, never backup execution.
  const uuid = await client.query(`SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    JOIN pg_depend d ON d.classid='pg_proc'::regclass AND d.objid=p.oid AND d.deptype='e'
    JOIN pg_extension e ON e.oid=d.refobjid
    WHERE n.nspname='public' AND p.proname='gen_random_uuid' AND p.pronargs=0 AND e.extname='pgcrypto'`);
  if(uuid.rowCount) await client.query(`GRANT EXECUTE ON FUNCTION public.gen_random_uuid() TO ${ident(roles.api)},${ident(roles.migrator)}`);
}

async function inventory(client) {
  const tables = await client.query(`SELECT c.relname name,c.relkind kind,pg_get_userbyid(c.relowner) owner
    FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='public' AND c.relkind IN ('r','p','S','v','m','f')
      AND NOT EXISTS(SELECT 1 FROM pg_depend d WHERE d.classid='pg_class'::regclass AND d.objid=c.oid AND d.deptype='e')`);
  const types = await client.query(`SELECT t.typname name,pg_get_userbyid(t.typowner) owner FROM pg_type t
    JOIN pg_namespace n ON n.oid=t.typnamespace WHERE n.nspname='public' AND t.typtype IN ('e','d')
      AND NOT EXISTS(SELECT 1 FROM pg_depend d WHERE d.classid='pg_type'::regclass AND d.objid=t.oid AND d.deptype='e')`);
  const functions = await client.query(`SELECT p.proname||'('||oidvectortypes(p.proargtypes)||')' name,
    pg_get_userbyid(p.proowner) owner,p.prosecdef security_definer FROM pg_proc p
    JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public'
      AND NOT EXISTS(SELECT 1 FROM pg_depend d WHERE d.classid='pg_proc'::regclass AND d.objid=p.oid AND d.deptype='e')`);
  return { tables: tables.rows, types: types.rows, functions: functions.rows };
}

function isKnown(object, category) {
  if (category === 'tables') return (object.kind === 'S' ? applicationSequences : applicationTables).includes(object.name);
  if (category === 'types') return applicationTypes.includes(object.name);
  return applicationFunctions.includes(object.name);
}

export async function prepareRoles(client, { env = process.env, adoptOwner, backupFile } = {}) {
  const roles = validateRoles(env);
  const passwords = { api: env.API_DB_PASSWORD, migrator: env.MIGRATOR_DB_PASSWORD, backup: env.BACKUP_DB_PASSWORD };
  const values = Object.values(passwords);
  if (values.some((v) => typeof v !== 'string' || v.length < 32 || v.startsWith('CHANGE_ME')) || new Set(values).size !== 3 || values.includes(env.PGPASSWORD)) {
    throw new Error('Three independent non-placeholder role passwords of at least32 characters are required');
  }
  let backupDigest;
  let backupManifest;
  if (adoptOwner) {
    if (!/^[a-z_][a-z0-9_]{0,62}$/.test(adoptOwner) || Object.values(roles).includes(adoptOwner)) throw new Error('Invalid expected previous owner');
    if (!backupFile) throw new Error('Existing ownership adoption requires an explicit verified backup file');
    const content = await fs.readFile(backupFile);
    if (content.length < 6 || content.subarray(0,5).toString() !== 'PGDMP') throw new Error('Adoption backup must be a PostgreSQL custom-format archive');
    backupDigest = crypto.createHash('sha256').update(content).digest('hex');
    backupManifest=JSON.parse(await fs.readFile(`${backupFile}.validated.json`,'utf8'));
    if(backupManifest.format!=='LifeGuide-adoption-backup-v1' || backupManifest.sha256!==backupDigest || backupManifest.pgRestoreList!==true ||
      !Number.isFinite(Date.parse(backupManifest.validatedAt)) || Date.now()-Date.parse(backupManifest.validatedAt)>15*60*1000 || Date.parse(backupManifest.validatedAt)>Date.now()+60000) {
      throw new Error('Run the local adoption helper to validate this exact backup first');
    }
  }
  await client.query('BEGIN');
  try {
    await client.query("SELECT pg_advisory_xact_lock(hashtextextended('lifeguide_role_provision',0))");
    await client.query("SET LOCAL lock_timeout='5s'");
    const session = (await client.query(`SELECT current_user, current_database() database,
      (SELECT rolsuper FROM pg_roles WHERE rolname=current_user) superuser`)).rows[0];
    if (!session.superuser || Object.values(roles).includes(session.current_user)) throw new Error('Provisioning requires the separate bootstrap administrator');
    if(backupManifest && backupManifest.database!==session.database) throw new Error('Adoption backup belongs to another database');
    const restricted=[roles.api,roles.backup];
    const databaseOwnership=await client.query(`SELECT EXISTS(SELECT 1 FROM pg_database
      WHERE datdba IN (SELECT oid FROM pg_roles WHERE rolname=ANY($1::text[]))) owned`,[Object.values(roles)]);
    if(databaseOwnership.rows[0].owned) throw new Error('Application roles must not own any database; operator must resolve unexpected ownership explicitly');
    const unexpectedOwnership=await client.query(`SELECT EXISTS(
      SELECT 1 FROM pg_namespace WHERE nspowner IN (SELECT oid FROM pg_roles WHERE rolname=ANY($1::text[]))
      UNION ALL SELECT 1 FROM pg_class WHERE relowner IN (SELECT oid FROM pg_roles WHERE rolname=ANY($1::text[]))
      UNION ALL SELECT 1 FROM pg_proc WHERE proowner IN (SELECT oid FROM pg_roles WHERE rolname=ANY($1::text[]))
      UNION ALL SELECT 1 FROM pg_type WHERE typowner IN (SELECT oid FROM pg_roles WHERE rolname=ANY($1::text[]))
      UNION ALL SELECT 1 FROM pg_extension WHERE extowner IN (SELECT oid FROM pg_roles WHERE rolname=ANY($1::text[]))) owned`,[restricted]);
    if(unexpectedOwnership.rows[0].owned) throw new Error('Runtime/backup ownership outside granted application data access is forbidden; operator must resolve it explicitly');
    const unknownSchema=await client.query(`SELECT EXISTS(SELECT 1 FROM pg_namespace
      WHERE nspname<>'public' AND nspname<>'information_schema' AND nspname !~ '^pg_') present`);
    // A dedicated app DB has only public plus PostgreSQL system schemas.
    // Refuse auxiliary namespaces: inherited CREATE, TRIGGER or executable
    // SECURITY DEFINER there could undo this policy. Never rewrite their ACLs.
    if(unknownSchema.rows[0].present) throw new Error('Unknown non-system schema in dedicated application DB; operator must isolate or explicitly resolve it');
    const objects = await inventory(client);
    for (const [category, list] of Object.entries(objects)) for (const object of list) {
      if (object.security_definer) throw new Error('Application SECURITY DEFINER is outside the approved role policy');
      if (object.owner !== roles.migrator && (!adoptOwner || object.owner !== adoptOwner || !isKnown(object, category))) {
        throw new Error('Existing ownership differs. Stop writers, verify backup, then explicitly adopt the known application owner');
      }
    }
    for (const [kind, name] of Object.entries(roles)) {
      const existing = (await client.query(`SELECT rolsuper,rolcreatedb,rolcreaterole,rolreplication,rolbypassrls,rolinherit,
        EXISTS(SELECT 1 FROM pg_auth_members WHERE member=pg_roles.oid) memberships
        FROM pg_roles WHERE rolname=$1`, [name])).rows[0];
      if (existing && Object.values(existing).some(Boolean)) throw new Error('Existing application role has unexpected privileges or memberships; refusing to change it');
      // Parameterized session settings keep password values out of SQL text and
      // error statements. The exception handler deliberately removes context
      // containing the dynamically constructed CREATE/ALTER ROLE password.
      await client.query("SELECT set_config('lifeguide_provision.role_name',$1,true),set_config('lifeguide_provision.role_password',$2,true)", [name,passwords[kind]]);
      await client.query(`DO $$ BEGIN
        IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname=current_setting('lifeguide_provision.role_name')) THEN
          EXECUTE format('CREATE ROLE %I LOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS',current_setting('lifeguide_provision.role_name'));
        END IF;
        EXECUTE format('ALTER ROLE %I PASSWORD %L',current_setting('lifeguide_provision.role_name'),current_setting('lifeguide_provision.role_password'));
      EXCEPTION WHEN OTHERS THEN RAISE EXCEPTION 'Role credential provisioning failed' USING ERRCODE='P0001'; END $$`);
    }
    const db = ident(session.database);
    await client.query(`REVOKE ALL ON DATABASE ${db} FROM PUBLIC`);
    for (const name of Object.values(roles)) await client.query(`REVOKE ALL ON DATABASE ${db} FROM ${ident(name)}`);
    await client.query(`GRANT CONNECT ON DATABASE ${db} TO ${Object.values(roles).map(ident).join(',')}`);
    // pgcrypto is a trusted PG16 extension. CREATE applies only to this DB,
    // never CREATEDB/CREATEROLE. Migrator owns the extension on a fresh restore.
    await client.query(`GRANT CREATE ON DATABASE ${db} TO ${ident(roles.migrator)}`);
    await client.query(`ALTER SCHEMA public OWNER TO ${ident(roles.migrator)}`);
    await client.query('REVOKE ALL ON SCHEMA public FROM PUBLIC');
    await client.query(`REVOKE ALL ON SCHEMA public FROM ${ident(roles.api)},${ident(roles.backup)}`);
    await client.query(`GRANT USAGE ON SCHEMA public TO ${ident(roles.api)},${ident(roles.backup)}`);
    for (const object of objects.tables) if (object.kind !== 'S' && object.owner !== roles.migrator) {
      // ALTER TABLE also transfers its identity/serial sequences. PostgreSQL
      // rejects independent OWNER changes on those linked sequences.
      await client.query(`ALTER TABLE public.${ident(object.name)} OWNER TO ${ident(roles.migrator)}`);
    }
    for(const object of objects.tables) if(object.kind==='S') {
      const current=(await client.query("SELECT pg_get_userbyid(relowner) owner FROM pg_class WHERE oid=$1::regclass",[`public.${object.name}`])).rows[0];
      if(current.owner!==roles.migrator) throw new Error('Sequence ownership did not follow its application table; refusing automatic repair');
    }
    for (const object of objects.types) if (object.owner !== roles.migrator) await client.query(`ALTER TYPE public.${ident(object.name)} OWNER TO ${ident(roles.migrator)}`);
    for (const object of objects.functions) if (object.owner !== roles.migrator) await client.query(`ALTER FUNCTION public.${object.name} OWNER TO ${ident(roles.migrator)}`);
    await client.query(`ALTER ROLE ${ident(roles.api)} IN DATABASE ${db} SET search_path=pg_catalog,public,pg_temp`);
    await client.query(`ALTER ROLE ${ident(roles.backup)} IN DATABASE ${db} SET search_path=pg_catalog,public,pg_temp`);
    await client.query(`ALTER ROLE ${ident(roles.migrator)} IN DATABASE ${db} SET search_path=public,pg_catalog,pg_temp`);
    // Global per-creator revocation removes PostgreSQL's default PUBLIC EXECUTE;
    // a per-schema REVOKE alone cannot override that global default.
    await client.query(`ALTER DEFAULT PRIVILEGES FOR ROLE ${ident(roles.migrator)} REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC`);
    await client.query(`ALTER DEFAULT PRIVILEGES FOR ROLE ${ident(roles.migrator)} IN SCHEMA public GRANT SELECT,INSERT,UPDATE,DELETE ON TABLES TO ${ident(roles.api)}`);
    await client.query(`ALTER DEFAULT PRIVILEGES FOR ROLE ${ident(roles.migrator)} IN SCHEMA public GRANT SELECT ON TABLES TO ${ident(roles.backup)}`);
    await client.query(`ALTER DEFAULT PRIVILEGES FOR ROLE ${ident(roles.migrator)} IN SCHEMA public GRANT USAGE,SELECT ON SEQUENCES TO ${ident(roles.api)}`);
    await client.query(`ALTER DEFAULT PRIVILEGES FOR ROLE ${ident(roles.migrator)} IN SCHEMA public GRANT SELECT ON SEQUENCES TO ${ident(roles.backup)}`);
    await grantUuidDefault(client,roles);
    await client.query('COMMIT');
    return { database: session.database, adopted: Boolean(adoptOwner), backupDigest };
  } catch (error) { await client.query('ROLLBACK'); throw error; }
}

export async function reconcileGrants(client, env = process.env) {
  const roles = validateRoles(env);
  await client.query('BEGIN');
  try {
    await client.query("SELECT pg_advisory_xact_lock(hashtextextended('lifeguide_role_provision',0))");
    const objects = await inventory(client);
    if (Object.values(objects).flat().some((object) => object.owner !== roles.migrator || object.security_definer)) throw new Error('Grant reconciliation refuses non-migrator application ownership');
    // Bootstrap runs this short-lived step so legacy pgcrypto PUBLIC grants are
    // revoked as well, without modifying extension ownership or member objects.
    await client.query('REVOKE ALL ON ALL TABLES IN SCHEMA public FROM PUBLIC');
    await client.query('REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM PUBLIC');
    await client.query('REVOKE ALL ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC');
    for (const role of [roles.api,roles.backup]) {
      await client.query(`REVOKE ALL ON ALL TABLES IN SCHEMA public FROM ${ident(role)}`);
      await client.query(`REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM ${ident(role)}`);
      await client.query(`REVOKE ALL ON ALL FUNCTIONS IN SCHEMA public FROM ${ident(role)}`);
    }
    for (const object of objects.tables) {
      const relation = `public.${ident(object.name)}`;
      if (object.kind === 'S') {
        await client.query(`GRANT USAGE,SELECT ON SEQUENCE ${relation} TO ${ident(roles.api)}`);
        await client.query(`GRANT SELECT ON SEQUENCE ${relation} TO ${ident(roles.backup)}`);
      } else {
        if (object.name !== 'schema_migration') await client.query(`GRANT SELECT,INSERT,UPDATE,DELETE ON TABLE ${relation} TO ${ident(roles.api)}`);
        await client.query(`GRANT SELECT ON TABLE ${relation} TO ${ident(roles.backup)}`);
      }
    }
    for (const object of objects.functions) if (applicationFunctions.includes(object.name)) await client.query(`GRANT EXECUTE ON FUNCTION public.${object.name} TO ${ident(roles.api)}`);
    await grantUuidDefault(client,roles);
    await client.query('COMMIT');
  } catch (error) { await client.query('ROLLBACK'); throw error; }
}
