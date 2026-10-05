# LifeMate — Project State

**Last updated:** 2026-10-05
**Phase:** Phase 4 — AI Guides, Learning & Wellbeing — COMPLETE
**Repository:** `davoodmehraban89/LifeMate`
**Working product name:** LifeMate — approved

## Transfer checkpoint
Phases 1–4 engineering core are complete. Phase 4 adds learning goals/check-ins, private wellbeing check-ins, advisory study/planner/wellbeing guides, explicit AI plan proposals, a high-risk safety response path, RTL UI surface and dedicated safety/privacy architecture. Public production exposure of minor-sensitive wellbeing AI remains intentionally gated.

## Five-phase roadmap
1. **Foundation, Product Contract & UX Direction** — COMPLETE
2. **Product Foundation & Identity** — COMPLETE
3. **Planner, School & Family Core** — COMPLETE
4. **AI Guides, Learning & Wellbeing** — COMPLETE
5. **Hardening, Observability & Release** — NEXT

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
- CI run 143 passed backend integration/schema/contract tests, dependency audit, security scanning, Flutter format/analyze/tests, Web release build and Android debug build at branch head `dc750c81735664b87e3a651e0860b3ba807cc906`.
- Railway staging migration verified `PHASE4_DB_SMOKE_OK` with all seven Phase 4 tables.
- Railway staging API function deployed successfully and is listening on port 8080 with the Phase 4 learning/wellbeing/guardian routes.

## Phase 5 entry point
Hardening, observability and release readiness: production-grade telemetry, rate limiting/abuse controls, backup/restore drills, performance/accessibility regression, release packaging and operational runbooks.

## Production-gate items intentionally deferred
Jurisdiction-specific legal/guardian consent review; final safety severity taxonomy; emergency resource localization; external AI provider privacy/retention review; wellbeing retention/export/deletion policy. These gates block public production exposure of minor-sensitive wellbeing AI but do not invalidate the completed Phase 4 engineering core.

## Guardrail
AI/wellbeing production exposure stays disabled until dedicated safety/legal/provider gates pass. Production deploys, destructive migrations and sensitive access changes require explicit action-specific approval.
