# ADR 0004 — AI Guides, Learning & Wellbeing

Status: Accepted for Phase 4 engineering/staging.

## Decision
AI Guides are advisory. They may propose study/planner/wellbeing actions but never silently mutate planner data. Proposals require explicit user acceptance. Wellbeing guidance is self-reflection/support, not diagnosis or treatment.

AI sessions and wellbeing check-ins are owner-private by default. Parent/family membership does not grant transcript access. A user may mark a wellbeing check-in `guardian_summary`, but Phase 4 does not expose raw notes through guardian endpoints.

The server applies a safety classifier before guide output. High-risk self-harm language receives a fixed safety response rather than ordinary coaching. This is an engineering guardrail, not the final jurisdiction-specific crisis system.

## Provider boundary
Phase 4 core does not require an external AI provider. A deterministic local guide keeps tests/staging functional and prevents accidental transmission of minor-sensitive content. A future provider adapter must pass privacy/retention and safety review before production enablement.

## Production gate
Public production exposure of wellbeing/minor-sensitive generative AI remains disabled until legal/guardian consent, severity taxonomy, localized emergency resources, provider privacy/retention, and retention/export/deletion policies are approved.
