# LifeMate — Project State

**Last updated:** 2026-10-05
**Phase:** Phase 4 — AI Guides, Learning & Wellbeing — COMPLETE (engineering/staging-safe core)
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
- Migration `0004_ai_learning_wellbeing.sql` defines six Phase 4 tables and owner-oriented indexes.
- Phase 4 API implements learning goals/check-ins, wellbeing check-ins, AI sessions/messages and proposal decisions.
- High-risk self-harm language follows a fixed urgent-support path; guide output declares advisory/non-diagnostic/no-automatic-action semantics.
- Wellbeing list responses exclude raw notes and are owner-scoped.
- RTL Phase 4 hub communicates advisory, privacy and non-diagnostic boundaries.
- ADR `docs/decisions/0004-ai-learning-wellbeing-safety.md` records privacy, provider and production safety decisions.
- CI run 120 passed backend tests/dependency audit/schema verification, security scanning, Flutter format/analyze/tests, Web release build and Android debug build at branch head `505c110f5d0a5cc95200efcf25465a54a5bdb84c`.

## Phase 5 entry point
Hardening, observability and release readiness: production-grade telemetry, rate limiting/abuse controls, backup/restore drills, performance/accessibility regression, release packaging and operational runbooks.

## Production-gate items intentionally deferred
Jurisdiction-specific legal/guardian consent review; final safety severity taxonomy; emergency resource localization; external AI provider privacy/retention review; wellbeing retention/export/deletion policy. These gates block public production exposure of minor-sensitive wellbeing AI but do not invalidate the completed Phase 4 engineering core.

## Guardrail
AI/wellbeing production exposure stays disabled until dedicated safety/legal/provider gates pass. Production deploys, destructive migrations and sensitive access changes require explicit action-specific approval.
