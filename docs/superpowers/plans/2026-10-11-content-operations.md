# LifeGuide — content operations implementation plan

> Execute the already authorized local work. Do not request approval for routine reversible implementation choices; preserve explicit live/release restrictions.

**Goal:** deliver a real consented feedback-to-research workflow and improve existing learning interfaces without rebuilding the shared backend.

**Architecture:** Express/PostgreSQL explicit capability grants, server-side version/idempotency/consent checks, Flutter runtime API, account/endpoint mutation journal and online-only restricted inbox. No external AI or private-data extraction.

**Stack:** Node22, PostgreSQL16, Flutter3.47.6, compiled Chromium substitutes and existing Compose TLS/backup package.

- [x] Read AGENTS.md/PROJECT_STATE.md and audit remaining code against actual state.
- [x] Define scoped capabilities, transitions, journal/brief payloads and withdrawal behavior.
- [ ] Backend RED: unauthorized parent, consent/withdrawal, stale updates, lost acknowledgement, expiry/revocation, bounded listing and private-free brief cases.
- [ ] Backend GREEN: migration0016, dedicated review router, role policy and local synthetic-only capability CLI.
- [ ] Client RED/GREEN: inbox/filter/status/brief, namespace invalidation and exact retry acknowledgement; owner review/history page; status accessibility.
- [ ] Root integration: actual-capability menu, learning history route, versions/docs.
- [ ] Research: latest official grade1 math pages, original draft teaching/questions, media shortlist with all unreviewed gates explicit; no download/rehosting or false publication.
- [ ] Complete bounded independent report/remaining engineering tasks, document policy and acceptance separately.
- [ ] Run pinned Node22 migrations/repeat/role isolation/restore and full backend tests; full Flutter/analyzer; one frozen-source web build and actual local HTTPS/browser substitutes.
- [ ] Review code, secret/naming/diff checks, record exact outputs and UNVERIFIED hardware/live/content gates.
- [ ] Small commits, feature PR, actual CI/debug artifact receipts and current handover. No merge/deploy/public release.

Detailed acceptance is in the matching design and completion-gap audit. A failed or unrun check is not green. Historical0.6 receipts certify their recorded source only.
