# LifeGuide — Supabase Free isolated QA bootstrap (proposed / not deployed)

Status: **QA project DB provisioned; app integration not deployed**  
Prepared: 2026-10-15  
Repository: `davoodmehraban89/LifeMate`  
QA preparation branch: `infra/lifeguide-supabase-qa`  
Baseline: `fix/study-duration-display` (LifeGuide 0.7.1, source CI `d0b3446d736b67fdb4e0218282ad15f0e74fdb55`)

## CURRENT VERIFIED RESULT — 2026-10-15

**Gate 0 / Gate 1: DONE.** User selected shared organization **DM Studio**. Connected Supabase verifies org `unrlckipyubhegrpqgei` on Free; `get_cost(project)` returned **$0/month** and the connector completed cost confirmation. Provider created **LifeGuide-QA** (`iqkrwxeprxvdiubdfcrb`) in Frankfurt on PostgreSQL17.11; status `ACTIVE_HEALTHY`. Existing `Finora ERP – Production` remains `ACTIVE_HEALTHY` and was not modified.

**Private database probe: DONE.** One `lifeguide_qa.setup_probe` synthetic row created/read, `public` app tables 0, anon/authenticated grants false, RLS enabled+forced. Migration `20261014210221_lifeguide_qa_isolated_connectivity_baseline`, mirrored in source. INFO advisor `rls_enabled_no_policy` expected: no access is deliberately allowed to this probe.

**Edge runtime probe: DONE.** `lifeguide-qa-health` v1 deployed with `verify_jwt=true`; unauthenticated external GET **401**. Authenticated GET, real family account and permission checks, app API, Android/PWA, Iran no-VPN **NOT DONE**.

**Next milestone:** review managed Postgres roles against the 20 existing application migrations and decide how to host/adapt the Node/Express+native Argon2/JWT server. Do NOT run original db-role scripts unreviewed, do NOT enable client-direct access to old app tables or configure Flutter with the raw project URL. Only synthetic user data when implementing the small task/report flow.

**Authoritative receipt:** [2026-10-15 Supabase QA provisioning](../audits/2026-10-15-supabase-qa-provisioning.md).

The previous organization-creation instructions, pending statuses and first plan below are **historical**, superseded by the actual shared DM Studio choice and successful QA provisioning. They must not be re-executed.

## Objective and non-negotiables

Proof of an **online synthetic-data-only** vertical slice for one child and two authorized parents: Android/API create task → PostgreSQL persistence → authorized parent reads from PWA → study duration appears → closed-and-reopened sessions preserve data. A green Web/APK build or accessible public health URL alone is **not** proof.

- A new Supabase **organization named LifeGuide**, explicitly chosen by the owner, is separate from existing `Finora` organization.
- A new project **LifeGuide-QA** must be created only if the Supabase cost confirmation says **$0** and the account has a free project slot. Supabase Free's project limit is **account-wide across organizations**; inactive/paused project eligibility is to be verified with Supabase, not assumed.
- Existing `Finora`, `EasyFactor`, Railway, Neon, domains, and LiveGuide `main` are **out of scope**. No changes to them.
- Only synthetic accounts/records. No personal, educational, child health, real identity, production export, live DNS, or payment card information.
- The existing application uses Node/Express + native Argon2 + PostgreSQL. **Supabase provides managed Postgres/Auth/Edge Functions, not a drop-in always-on Express host**; do not switch Flutter URLs to Supabase until an API adapter is verified.
- The prior hosting decision `docs/decisions/0009-provider-neutral-hosting.md` remains the production baseline. This investigation proposes only a **QA exception**; it does not approve any production migration.
- No `service_role`, `secret`, Postgres password, JWT secret, API master key or signing key in Flutter, PWA, a public GitHub branch, comments, screenshots or chat. Supabase publishable/anon keys alone are not authorization.

## Updated owner direction — DM Studio shared organization, 2026-10-15

**This section supersedes the earlier requirement to create a second independent LifeGuide organization.** Owner confirmed the original Finora organization was renamed `LifeGuide`; the matching organization ID is expected and is not evidence of two organizations. Owner now authorizes renaming **only its display name** to the general-purpose **`DM Studio`**, with independent application projects (LifeGuide, Finora, EasyFactor, future projects). The connected Supabase tool **cannot rename an organization**, so this remains **PENDING** owner action in the dashboard.

After the owner renames it, verify its name and original ID via `list_organizations`/`get_organization`. Do not treat this display-name change as new organization creation, do not rename org slug or modify existing projects, do not restore/delete unrelated resources. Note the Free tier's **two active projects across owned organizations** limit remains.

The earlier Gate 0's independent-organization creation instructions and same-ID warning are now historical, not current action items. **Current Gate 0:** rename the existing organization's display name to DM Studio; verify the same ID. **Current Gate 1:** verify zero dollar recurring project cost, account-wide capacity and unrelated project state; ask for the required cost confirmation before creating `LifeGuide-QA`. All subsequent synthetic-data-only security/compatibility gates still apply.

## Provider re-check — 2026-10-15 (BLOCKED: organization identity ambiguity)

Read-only Supabase checks completed:
- `list_organizations` returned exactly one visible organization named `LifeGuide` with ID `kpbskbvjspggwzmgqyze`; `get_organization` confirmed **Free**.
- `get_cost(type=project, organization_id=kpbskbvjspggwzmgqyze)` returned **amount: 0; recurrence: monthly**. This is not proof that a separate organization/free slot is available.
- **Critical identity mismatch:** `kpbskbvjspggwzmgqyze` is the *same* organization ID previously observed as `Finora` (before owner action). Name alone does not establish independence; it may be a rename or an integration visibility issue.
- Current `list_projects` returned an empty list. Direct reads of previously visible `Finora`/`EasyFactor` project IDs returned **permission denied**. The projects' deletion, transfer or state must **not** be inferred from this result.
- **STOP before `confirm_cost` / `create_project`**. Ask the owner to confirm that **both Finora and LifeGuide are simultaneously visible as separate organizations** in the Supabase dashboard; request new LifeGuide organization ID/slug (non-secret) if it differs. Recheck with the connected account before proceeding.
- No database/project creation, schema write, migration, public deployment, payment or access change performed.

## Actual inventory at preparation time (not deployment)

- Supabase connector can list organizations/projects and create projects, but **cannot create organizations**.
- Existing organization `Finora` is on Supabase Free. Its projects `EasyFactor` (ACTIVE_HEALTHY) and `Finora` (INACTIVE) are unrelated. **Neither may be reused**.
- No independent `LifeGuide` organization or QA project has been created at the time of this document.
- The repo head is in stacked draft PRs #10 → #11 → #12 → #13. PR #13 includes 0.7.1 exact study-duration display. Do not modify their branches or merge them as part of this QA preflight.
- Prior CI `38223988983` passed Flutter/Backend/Security and built debug APK and web; **not** proof of internet deployment or physical Safari/Android behavior.
- Supabase Free can automatically pause a project after a period of insufficient activity, and has finite quota. There is no guaranteed perpetual availability or guaranteed Iran reachability.

## Gate 0 — owner action: create independent organization (not automatable with connected Supabase tool)

1. In a private browser, sign into the existing account at https://supabase.com/dashboard.
2. Open the **organization switcher** and select **New organization** (UI wording may vary).
3. Name: **LifeGuide**. Choose **Free** (never Pro, trial with payment card, add-ons, paid compute, or paid branching).
4. Complete organization setup **without** adding a payment card. Do not create an application project yet.
5. Return only the organization name, preferably its organization ID/slug (this is not a secret). **Never send login codes, access tokens, passwords or billing details**.

Acceptance: `list_organizations` returns **LifeGuide** alongside **Finora** with a distinct ID. `get_organization` confirms Free plan.

## Gate 1 — cost and capacity before project creation

- Call Supabase `get_cost({type:"project",organization_id:<LIFEGUIDE_ORG_ID>})`; disclose the returned price and recurrence verbatim. If nonzero, **STOP**.
- Check organization plan and the account-wide two-free-active-project limit. Existing inactive state is not enough alone to establish an empty slot.
- Ask owner to approve the **exact result of the $0 cost check** in the product's confirmation flow (`confirm_cost`), then create `LifeGuide-QA` in a region appropriate to the testing need and supported by the provider, preferably EU Central if available.
- No automatic premium upgrade, no subscription conversion, no card entry, no resource purchases. If creation is denied, stop and propose a safe alternative.

Acceptance: independent Supabase project ID and project status healthy, price explicitly $0, no unrelated projects changed.

## Gate 2 — read-only compatibility audit before any migration

Record a scoped technical assessment, not an assumed 'lift and shift':

1. Enumerate the 0.7.1 Postgres migrations, `pgcrypto` and DB privilege requirements, `public` schema ownership, `SECURITY DEFINER`, policy assumptions, and special roles from `docs/operations/DATABASE_ROLES.md`.
2. Check supported Supabase PG version/extensions and database resource constraints. Existing provisioning scripts require role/ownership assumptions that may be **incompatible with managed Supabase**; **never run full Compose provisioning scripts against Supabase unchanged**.
3. Check the backend runtime: Express/Node, Argon2 native dependency, JWT/session revocation, consent and guardian permissions, report SQL, idempotent mutation receipts, offline sync. Supabase Edge Functions run in a different runtime; reusing Express and native Argon2 without proving compatibility is not accepted.
4. Compare two safe options: (A) Supabase managed Postgres behind an independently-hosted compatible API; (B) a new limited Supabase Edge Function adapter retaining authorization semantics. Neither option may expose unrestricted tables to the client.
5. Check PWA static hosting separately; Supabase database is **not** itself a replacement for a PWA site host. Existing `config.json` / `/api` same-origin convention must be adapted and tested rather than faked.

Deliverable: migration compatibility table and chosen **smallest reversible QA spike**. No user data migration.

## Gate 3 — minimal synthetic vertical slice (after Gates 0–2)

- Fresh QA-only schema with migrations fully reviewed, reversible, and idempotent; synthetic UUID child/mother/father identities and an explicitly authorized family relationship.
- Enforce **server-side access** at every read and write. If Supabase Data API is used, enable RLS and write restrictive policies and negative-role tests first; never depend only on Flutter hiding UI.
- Use Edge Functions or a verified server-side adapter for account/session semantics as needed. **Do not introduce a second incompatible production identity system silently.**
- Task create/read/update/archive with stable mutation ID, version, owner ID, ACK/conflict and repeat-safe behavior; time intervals and accurate duration; authorized parent summary with freshness timestamp.
- Synthetic end-to-end checks: child writes task → SQL independent verification → authorized mother reads → authorized father reads → outsider 403/no data → duration 4 seconds displayed as 4 seconds → persisted on reopen → safe offline resend no duplicate.
- PWA served on HTTPS; browser reload and auth tested; mobile Safari/A2HS and actual Android install/upgrade require separate owner-device acceptance, not desktop inference.
- Test reachability from Iran **without VPN** before asserting real usability, and check legal/terms restrictions. Avoid claims of guaranteed availability.

## Exit gates and safety

- Gate A: $0 organization/project verified in the Supabase account.
- Gate B: Isolated DB and permission test pass; no tables in another project touched.
- Gate C: API+Postgres persistence from a synthetic account passes create/reopen/edit/read/archive, including unauthorized denial.
- Gate D: PWA installed in actual iPhone Safari and Android installed on actual device, both using same QA API; unverified tests remain marked unverified.
- Gate E: Backups/export and recovery proof with **synthetic** data, plus a safe teardown plan for QA-only resources (no teardown without approval).
- Gate F: Release/migration approval is separate. Do not merge stacked production PRs, change existing DNS, change signing, import real children records, or activate public rollout based only on this PoC.

## Execution ledger (current)

| Item | Verified outcome |
| --- | --- |
| DM Studio Free org `unrlckipyubhegrpqgei` | **PASS** |
| Exact project creation charge `$0/month`, user/provider confirmation | **PASS** |
| LifeGuide-QA `iqkrwxeprxvdiubdfcrb` in Frankfurt | **ACTIVE_HEALTHY** |
| Isolation from Finora ERP – Production | **NO WRITES** to existing project; existing status remains healthy |
| Supabase PostgreSQL17.11, `pgcrypto` present | **PASS** |
| Private `lifeguide_qa` migration, synthetic insert/read, anon/auth denied | **PASS** |
| Supabase JWT-gated Edge runtime `lifeguide-qa-health` | **ACTIVE**, unauthenticated GET **401** |
| Existing LifeGuide 20 application SQL migrations in Supabase | **NOT RUN**; compatibility gate |
| Real shared family API, RLS/guardian negative tests | **NOT RUN** |
| PWA/Android, Safari, Iran no VPN, backup restore | **UNVERIFIED** |
| Production DNS, real data, original projects, billing | **UNCHANGED** |

See [actual evidence](../audits/2026-10-15-supabase-qa-provisioning.md). No further owner action necessary for the completed provisioning step. Next code/data changes must retain distinct QA-only scope and pass compatibility/security checks.
