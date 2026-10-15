# ADR 0013 — LifeGuide: GitHub + Cloudflare Pages + Supabase PostgreSQL + Kavenegar

Date: 2026-10-15
Status: **OWNER DIRECTED, QA PREPARATION — public production cutover NOT approved**

## User decision

Owner explicitly directs **remove Railway from the active LifeGuide deployment architecture** due to inaccessible regional connectivity and 504 at `app.lifeguide.ir`. Focus active development and operations on **GitHub, Supabase, Cloudflare, Kavenegar OTP**. This supersedes the prior self-hosted-only active provider selection of ADR 0009 *for online QA exploration*, without deleting historical decisions or changing the Node/Express security contract.

## Existing verified inventory

- Main repository: `davoodmehraban89/LifeMate`, product **LifeGuide**.
- App v0.7.1 development baseline and connected Supabase QA branch: `infra/lifeguide-supabase-qa`; related draft PR #14. No merge into `main`.
- Supabase Free organization `DM Studio`, isolated `LifeGuide-QA` database `iqkrwxeprxvdiubdfcrb`, Frankfurt, PG17.11; 20 original application SQL migrations succeeded in locked-down **private `lifeguide_qa` schema**. DB fixture verified two parents, one child, an outsider, private data, revocation and 4 seconds duration, all ROLLED BACK. No client DB grants; browser must **never** connect directly with a privileged key.
- Existing Cloudflare account `ace6f7219be1e7d9ac5bacd59c05fbe2` has a previously-created GitHub-integrated Pages project `lifemate-staging.pages.dev`, production branch `deployment-static`. Its latest successful production deploy dates to Oct 6 and contains an older static Flutter build; NOT the integrated QA 0.7.1 app.
- `app.lifeguide.ir` returned Arvan 504 on owner LTE. Authoritative DNS for `lifeguide.ir` is **Arvan DNS** (`d.ns.arvancdn.ir`). `app` A answers currently resolve Arvan network addresses. Connected Cloudflare account does **NOT** contain the `lifeguide.ir` zone. No DNS change executed.
- Kavenegar OTP `lifeguideotp` pattern submitted but **rejected**; support ticket says application link unreachable. Existing opt-in Node adapter has synthetic tests, no API secret added, no real/paid SMS sent.

## Chosen QA layout

1. **GitHub**: source of truth, build/quality gates, independent reviewable PRs; immutable build evidence. Do not overwrite live `main` or stale `deployment-static`.
2. **Cloudflare Pages**: host QA Flutter PWA as **static assets**, without Railway. Existing Pages project stays unchanged. Use isolated `lifeguide-qa` Pages site sourced from dedicated QA branch, with no domain attached pending real functional acceptance. QA build script pinned to Flutter 3.47.6, no external CanvasKit CDN.
3. **Supabase**: managed PostgreSQL and server-side Edge Functions for supported **bounded server logic**, but not as an automatic drop-in replacement for Express5/native Argon2/custom JWTs. Preserve authorization semantics before activating user-facing API. No service-role/DB secret in PWA/Android, API responses, logs or Git.
4. **Kavenegar**: server-side OTP transport using approved `lifeguideotp` template. Pattern rejected because app domain 504; resubmit/support after independent reachable application URL is demonstrably functional and user agrees. No paid SMS without approval.
5. **QA safety**: Until authenticated task APIs are ready, Cloudflare Pages `/api` and `/api/*` return **503 JSON** (fail closed), `/ready` returns degraded, `/health` confirms gateway only. Do NOT count a static 200 as healthy family sync.

## Domain strategy without transferring DNS zone

Per https://developers.cloudflare.com/pages/configuration/custom-domains/ **Cloudflare Pages can attach a custom subdomain even when the apex DNS remains at an external provider**: *first* add `app.lifeguide.ir` in the Pages **Custom Domains** page, *then* add a CNAME for `app` to the assigned `<pages-project>.pages.dev` within **Arvan DNS**, and review any Arvan CDN/proxy and certificates. Do **NOT** simply point CNAME without Pages ownership setup (Cloudflare says it may return HTTP 522). This is a user-visible switch and requires separate approval and access; **none is performed in this QA workstream**. Back up existing DNS records and use validated rollback.

## Non-negotiable acceptance gates

- Static PWA must build, load, install and persist from Cloudflare Pages on iOS Safari and Android without VPN inside Iran. Merely 200 on Pages is insufficient.
- QA provider API must have real authenticated user-family access, verified negative-role tests, short-lived OTP, 6-digit code, adequate server-side abuse throttling and session revocation.
- Kavenegar verification template approved by provider and one owner-approved charged test SMS successfully received, never expose API key.
- QA child writes to Supabase -> authorized mother/father see correctly -> outsider denied -> private child information denied -> family member revoked immediately -> 4 seconds accurate -> offline resend deduplicated. No false assurance based on DB-only tests.
- Real-data migration, domain cutover, signed APK publication, adding paid services and DNS/permissions change are distinct owner approvals.

## Work ledger

- [x] Existing Cloudflare Pages GitHub integration / DNS authority / Supabase QA infrastructure audited.
- [x] QA Cloudflare static build script and fail-closed Pages Functions authored on isolated GitHub branch.
- [ ] Independent Cloudflare QA site build/deploy, validated HTTP content type and status.
- [ ] Supabase authenticated family endpoints; no rewrite with privileged client keys.
- [ ] Approved Kavenegar OTP and live QA delivery.
- [ ] Owner-approved Arvan CNAME domain cutover and post-change LTE verification.
