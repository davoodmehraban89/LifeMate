**Historical snapshot — retained as decision/evidence history. Current product: LifeGuide; current execution status: PROJECT_STATE.md.**

# LifeMate — Project State

**Last updated:** 2026-10-05
**Phase:** Phase 5 — Hardening, Observability & Release — COMPLETE
**Repository:** `davoodmehraban89/LifeMate`
**Working product name:** LifeMate — approved

## Transfer checkpoint
Phases 1–5 engineering core are complete. LifeMate now has the foundation/identity, planner-school-family core, advisory learning/wellbeing guides, and the operational hardening/release-readiness layer required for a controlled beta. Public production release and minor-sensitive external AI/voice exposure remain intentionally gated and require separate explicit approval.

## Five-phase roadmap
1. **Foundation, Product Contract & UX Direction** — COMPLETE
2. **Product Foundation & Identity** — COMPLETE
3. **Planner, School & Family Core** — COMPLETE
4. **AI Guides, Learning & Wellbeing** — COMPLETE
5. **Hardening, Observability & Release** — COMPLETE

## Accepted architecture baseline
- Flutter Android + responsive Web/PWA; future packaged/native iOS path preserved.
- Provider-neutral Node API + PostgreSQL; Railway remains staging host.
- LifeMate-owned identity/session adapter; server-side relationship-aware authorization.
- Offline client support does not replace server authority.
- AI guides are advisory and plan proposals require explicit acceptance.
- Wellbeing/AI transcripts remain owner-private; family membership does not grant transcript access.

## Phase 4 completed vertical slice
Learning goal → learning check-in → wellbeing check-in → AI guide session → safety classification → advisory response → explicit plan proposal → accept/reject decision. No guide response silently mutates planner state.

### Verified Phase 4 gates
- Migration `0004_ai_learning_wellbeing.sql` defines seven Phase 4 tables, including the separate `wellbeing_safety_event` ledger, and owner-oriented indexes.
- Phase 4 API implements learning goals/check-ins, private/guardian-summary wellbeing check-ins, AI sessions/messages, explicit proposal decisions, guardian wellbeing summaries and privacy-preserving family guidance.
- High-risk self-harm language follows a fixed urgent-support path and writes a separate safety signal; ordinary family membership never grants raw wellbeing notes or AI transcripts.
- Study/planner/wellbeing guidance is advisory, non-diagnostic and never silently mutates planner data.
- Flutter includes interactive guide chat, learning goals/check-ins, wellbeing check-ins, guardian summary and parent family-guidance flows.
- ADR `docs/decisions/0004-ai-learning-wellbeing-safety.md` records privacy, provider, voice and production safety gates.

## Phase 5 completed scope
- Production-entrypoint request correlation, security headers, privacy-safe structured request/error telemetry and bounded request bodies.
- Configurable general/auth/AI fixed-window rate limits with HTTP 429 and `Retry-After`.
- Separate `/live` and database-backed `/ready` operational probes while retaining `/health` compatibility.
- PostgreSQL-native backup/restore scripts plus an automated CI data round-trip restore drill.
- Release regression gates for backend tests/syntax/audit/schema, secret scanning, Flutter format/analyze/tests, Web release build, Android build and PWA install/RTL metadata.
- Deployment, rollback, backup/restore, incident-response and production-readiness runbooks plus changelog/version discipline.
- Railway staging API function hardened with request IDs, security headers, rate limiting, `/live`, `/ready` and privacy-safe error handling; staging tracing and auto-instrumentation enabled.

### Verified Phase 5 gates
- Red-first operations contract was observed failing before the hardening implementation; subsequent backend contract/integration tests passed.
- GitHub Actions run 165 at branch commit `125c44f55827dc5ed26d81fe821969348db4598e` completed successfully: security, backend and Flutter jobs all green.
- Backend run 165 passed migrations, authorization tests, dependency audit, 11 Node tests, syntax checks, 28-table schema verification and the backup/restore data round-trip drill.
- Flutter run 165 passed formatting, analysis, widget/tests, PWA release metadata checks, Web release build and Android debug build.
- Railway staging deployment `0cd21bed-5cba-494b-afef-7f45312f2fdf` is SUCCESS/online with no reported warnings or critical issues after Phase 5 hardening.
- Railway staging source inspection confirms the operational middleware and `/live` + `/ready` routes are deployed; external AI/voice remain unenabled and Phase 4 AI continues in local-fallback mode.

## Production-gate items intentionally deferred
Jurisdiction-specific legal/guardian consent review; final safety severity taxonomy; emergency resource localization; external AI provider privacy/retention review; wellbeing retention/export/deletion policy; voice-provider privacy review; production push-provider configuration; final device beta acceptance. These are release gates, not missing Phase 5 engineering-core work.

## Release status
Engineering phases 1–5: COMPLETE.
Controlled family beta: READY FOR OWNER-APPROVED DEVICE TESTING.
Public production deployment/release: NOT PERFORMED.

## Guardrail
AI/wellbeing production exposure stays disabled until dedicated safety/legal/provider gates pass. Production deploys, destructive migrations, public release and sensitive access changes require explicit action-specific approval.
