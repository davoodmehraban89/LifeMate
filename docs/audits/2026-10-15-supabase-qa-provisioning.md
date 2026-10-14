# Supabase LifeGuide-QA provisioning and private probe — 2026-10-15

Status: **QA database provisioned; integration not deployed**. Evidence here comes from actual connected Supabase tool responses, not from a user/device test.

## Scope, authorization and cost

Owner chose a general-purpose Supabase organization **DM Studio**, with each software product as a separate project. Organization list after reconnect confirms:
- Organization `DM Studio`, ID `unrlckipyubhegrpqgei`, plan `free`.
- Existing project `Finora ERP – Production`, ID `hcsixhqbyuhpshfwqpjx`, reported `ACTIVE_HEALTHY`. No writes or changes to it.
- `get_cost(type=project, organization_id=unrlckipyubhegrpqgei)` returned `{"type":"project","recurrence":"monthly","amount":0}`. Zero-cost confirmation obtained in the connector; no card/purchase/upgrade was submitted. Free-tier project limit and pauses remain provider constraints. The provider successfully admitted the project.

Actual new project:
- Name: **LifeGuide-QA**
- Supabase project ID: `iqkrwxeprxvdiubdfcrb`
- Organization ID: `unrlckipyubhegrpqgei`
- Region: `eu-central-1` (Frankfurt)
- Status after provision: **ACTIVE_HEALTHY**
- PostgreSQL: **17.11**
- Project API base: `https://iqkrwxeprxvdiubdfcrb.supabase.co`. This is **NOT** the old LifeGuide Express REST API or the PWA address; Flutter must **not** be switched to this URL.

## Actual QA write and security verification

At first inspection:
- `public` application tables: **0**.
- Supabase migration list: empty; Edge Functions list: empty.
- PostgreSQL `pgcrypto` already installed in `extensions`.
- Initial Supabase security/performance advisors: no findings.

Applied **one additive migration** through the Supabase migration tool: `20261014210221_lifeguide_qa_isolated_connectivity_baseline`.
Source mirror: `supabase/migrations/20261014210221_lifeguide_qa_isolated_connectivity_baseline.sql`.

This migration created only:
- private schema `lifeguide_qa`
- table `lifeguide_qa.setup_probe`, containing a UUID, **synthetic-only** probe name, timestamp
- RLS enabled and forced; explicit **no `anon` or `authenticated` schema/table grants**, and no RLS policies (deliberately deny all).
- No public tables, no credentials, no parent/child identities, and no production content.

Database write performed:
```sql
insert into lifeguide_qa.setup_probe(probe_name)
values ('synthetic_backend_handshake')
on conflict (probe_name) do update set probe_name=excluded.probe_name
returning probe_name, created_at;
```
This returned exactly one synthetic record. A separate read-only SQL verification returned:

| Check | Observed |
| --- | --- |
| synthetic_receipts | 1 |
| public_app_tables | 0 |
| qa_tables | 1 |
| anon_schema_usage | false |
| authenticated_schema_usage | false |
| anon_table_select | false |
| authenticated_table_select | false |
| rls_enabled | true |
| rls_forced | true |

Post-migration security advisor: one **INFO** `rls_enabled_no_policy` finding for `lifeguide_qa.setup_probe`; this is **expected by design** because the private setup table has no policies and client access is intentionally denied. This is not a permission leak. If this table is ever repurposed as an application table, explicit restrictive policies and negative authorization tests become mandatory.

Remediation reference: https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy

## Compatibility conclusion and remaining gates

Existing LifeGuide v0.7.1:
- Backend is **Node >=22 / Express 5**, with native `argon2`, `pg`, bespoke JWT/session auth, rate limiting and backup/role scripts.
- Original 20 PostgreSQL migrations are intended for a self-hosted PostgreSQL 16 instance with distinct bootstrap, API, migrator and backup roles; provisioner expects schema ownership/role topology that must not be applied without adapting to Supabase Postgres 17 managed role model.
- Supabase PostgreSQL gives the right SQL family and `pgcrypto`, **but Supabase itself does not run the existing long-lived Express server**. Need an approved adapter strategy: independent Express host, or a scoped Edge Functions implementation with consent and permission parity. Calling the Supabase project URL the existing `/api` would be incorrect.
- There is **no** PWA/Android application integration, no `LifeGuide` application data schema, no 20 app migrations, no Auth/API adapter, no Edge Function and no public app deployment.
- Must confirm internet reachability and permitted usage from inside Iran without VPN. Free project inactivity pause, quotas and synthetic-data export/backup remain open.
- Required vertical slice: child task save/close/reopen → authorized mother/father report → unauthorized reader denied → correct duration in seconds → offline resend without duplicate.
- Existing `docs/decisions/0009-provider-neutral-hosting.md` remains production baseline. This isolated QA experiment **does not authorize** changing DNS, live deployments, real-data import, production DB roles, app signing or merging main/PR #10–13.

## Next implementation milestone

1. Prepare an explicit **backend+auth compatibility matrix** from source and managed DB role capabilities.
2. Choose one secure, reversible API strategy, keeping existing family-authorizations intact.
3. Only then apply reviewed **synthetic-only** application migrations and build an authenticated API vertical slice.
4. Validate real Android + PWA devices and no-VPN reachability independently. Do not report these as complete beforehand.

Owner action currently needed: **none** for the already provisioned QA database; no payment card needed.
