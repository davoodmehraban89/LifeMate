# LifeGuide QA: Supabase PG17 private schema + family authorization receipt

Date: **2026-10-15**  
Scope: **LifeGuide-QA only**, org **DM Studio**; no live user records or public application deployment.  
Supabase project ref: `iqkrwxeprxvdiubdfcrb` (`ACTIVE_HEALTHY`, Frankfurt).  
Existing unrelated `Finora ERP – Production`: verified separately still `ACTIVE_HEALTHY`; no writes.

## What was actually applied

**Two additive, transaction-wrapped Supabase migrations**, preserving the original application SQL source semantics within a dedicated schema:
- Provider migration `20261014215436_lifeguide_qa_app_schema_0001_0010` (source: `supabase/migrations/202610150001_lifeguide_qa_app_schema_0001_0010.sql`).
- Provider migration `20261014215539_lifeguide_qa_app_schema_0011_0020` (source: `supabase/migrations/202610150002_lifeguide_qa_app_schema_0011_0020.sql`).
- Existing earlier `20261014210221_lifeguide_qa_isolated_connectivity_baseline` is unchanged.

Both application batches **succeeded** using Supabase `apply_migration`. They retain a `lifeguide_qa.schema_migration` ledger of **all 20 original LifeGuide SQL migration filenames with PostgreSQL pgcrypto SHA256 of the original source bytes**, not substituted QA SQL hashes. No original migration source was modified in place.

Compatibility adjustments confined to copies:
- Original `create extension if not exists pgcrypto` removed from the QA copy because Supabase already installs it globally in `extensions`.
- Only the **five** explicitly pinned school guard `SET search_path=public,pg_catalog` statements from migration 0019 were redirected to `lifeguide_qa,pg_catalog`. All other unqualified application DDL was executed with transaction-local search path `lifeguide_qa,extensions,pg_catalog`.
- **No** original Compose `provision-db-roles.js`, role ownership transfer, global Supabase Auth schema or public schema modification.
- After each batch: revoke all usage/DML/function access for `public`, `anon`, `authenticated`, `service_role` on private schema and app objects. Enable and force RLS on every application table; no client RLS policies are granted. The table schema is **inaccessible to client roles by design** until a reviewed authenticated server adapter exists.
- QA generator/script and synthetic checks in `backend/scripts/build-supabase-qa-sql.js`, `backend/tests/supabase_qa_bundle.test.js`. The committed two SQL manifests are the **exact applied provider source**; generator is for a new empty QA, not to re-apply to this live QA database.

## Actual post-migration, read-only SQL verification

| Check | Value |
| --- | --- |
| Original migration ledger | **20** |
| Private `lifeguide_qa` ordinary tables | **59** (includes synthetic setup/ledger) |
| Private functions | **19** |
| Public application tables | **0** |
| Functions with unwanted explicit `public` search path | **0** |
| QA `SECURITY DEFINER` functions | **0** |
| All QA ordinary tables RLS enabled + forced | **true** |
| QA schema USAGE for `anon` | **false** |
| QA schema USAGE for `authenticated` | **false** |
| QA schema USAGE for `service_role` | **false** |
| Direct `anon` app_user SELECT | **false** |
| Direct `authenticated` family SELECT | **false** |
| Invalid source hash entries | **0** |

Supabase security advisor reports `INFO: rls_enabled_no_policy` on 59 tables. This is an **intentional fail-closed QA state** and not an unauthorized-access permission: no RLS policies are created and all schema USAGE is explicitly revoked. These tables cannot yet serve the application over the Supabase Data API. Reference: https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy

## Live SQL fixture: mother, father, child, outsider

Executed the actual SQL in Supabase project LifeGuide-QA via `execute_sql`, in a transaction that ended with **ROLLBACK**:
- 4 uniquely-generated synthetic test identities (mother, father, child, unrelated outsider); no real emails, phone numbers or OTPs.
- 1 family, two active guardian relations and child membership.
- A `parent_guardian` assignment and a `private` child task.
- One completed `study_session` with exactly **4 recorded seconds**.
- Verified `is_active_guardian`, `can_view_student_academic`, `can_view_plan_item` for both authorized parents, outsider, private item, and **revocation** of the father's active guardian relationship while preserving mother's access. Every assertion succeeded, otherwise the transaction would raise and fail.
- Source: `backend/tests/supabase_qa_guardian_acceptance.sql`. This exercises database predicates only; it is NOT HTTP/JWT/PWA proof.

After the rollback, an independent read confirmed **0** app users, **0** family workspaces, **0** plan items and **0** study sessions. No fixture or actual child/parent record persists in the QA database.

## Remaining blockers (do not overclaim)

- Existing LifeGuide 0.7.1 **Node/Express + native Argon2 + custom JWT/session auth** is NOT deployed to Supabase Edge. A managed PostgreSQL DB is **not** a Node app server. The Express runtime needs a compatible free host or reviewed Edge adapter with authentication equivalence; do NOT silently substitute Supabase Auth for the existing identities.
- The forced RLS/no grant configuration is intentionally closed. An API deployment must first establish a dedicated least-privileged server role or demonstrably secure alternative, guard all family/guardian access on the server, and separately pass HTTP negative tests. Never put Postgres/password/service_role in Flutter, PWA or client-side code.
- No existing endpoint `https://app.lifeguide.ir/api` or Android APK has been switched to this QA database; no live DNS, reverse proxy, PWA install or iOS Safari run was changed/tested.
- Kavenegar template `lifeguideotp` was created by owner and remains **under provider review** per screenshots; dedicated Node SMS delivery adapter has passing synthetic tests in CI snapshot but no real provider call, credentials or SMS delivery.
- Iran without VPN, real SMS, confirmed template, full family end-to-end, independent backup/restore and permanent free-host operations **NOT VERIFIED**.
- The project is on Supabase Free, with provider quotas, idle auto-pause and no perpetual guaranteed availability. No billing card or paid service was used.

## Next implementation gate

Build and validate an **independently hosted, existing Express-compatible HTTPS API** for QA, linked to managed PG with credentials only in the server's private secrets; preserve current session/JWT and family permission model. Prefer smallest reversible deployment and no DNS cutover until real iPhone Safari / Android acceptance. If that is infeasible without billing, research serverless adaptation as a separate explicit architecture decision rather than presenting the database migration as the finished online app.
