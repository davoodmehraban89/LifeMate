**Historical snapshot — retained as decision/evidence history. Current product: LifeGuide; current execution status: PROJECT_STATE.md.**

# LifeMate — Safety, Privacy & Risk Baseline v1

## Product safety boundary
LifeMate may provide general wellbeing reflection, coping ideas, communication prompts and educational support. It must not claim diagnosis, treatment, professional licensure or certainty about a user's mental state. The AI must not encourage emotional dependency or represent itself as a replacement for trusted people/professional care.

## Privacy model
Raw private wellbeing conversations are not routine parent-report content. Parent support uses authorized structured signals/trends and actionable guidance. Safety escalation is a separate, narrowly governed path; it is not a blanket permission to inspect private history.

## High-priority risks
1. **Authorization leak across family members** — mitigate with relationship-aware server RLS, deny-path tests and audit events.
2. **Overexposure of teen wellbeing content** — separate raw sessions, derived parent insights and safety events; explicit policy tests.
3. **AI overclaim/clinical framing** — system policy, response evaluation, prohibited claims and escalation behavior.
4. **False reassurance / missed urgent risk** — safety-specific detection/escalation design, conservative wording, clear human/emergency pathways appropriate to deployment jurisdiction.
5. **Notification harm/pressure** — quiet hours, configurable frequency, supportive copy, no punitive streak pressure.
6. **Account takeover/recovery abuse** — verified recovery channel, non-enumerating responses, rate limits, secure redirect/session handling.
7. **Sensitive telemetry leakage** — analytics allowlist; never send raw wellbeing transcript, password, auth token or private free text to product analytics.
8. **AI provider data exposure** — server-side provider calls, minimal context, provider retention/privacy review before production.
9. **Child consent/legal mismatch** — deployment jurisdiction and age/guardian consent rules require explicit legal review before public production involving minors.
10. **Family relationship dispute** — guardian changes/removal need controlled workflow; role label alone is not proof of legal guardianship.

## Safety event principles
- Define categories and severity before implementation; do not let the LLM invent escalation thresholds dynamically.
- Store minimum necessary event metadata and access it through a dedicated audited path.
- User-facing messaging should be transparent about when ordinary privacy may be overridden by the configured safety policy.
- No automated punitive action against a child.

## Phase 1 unresolved-but-owned items
These are not blockers to Phase 2 scaffolding but are blockers to public production of wellbeing features: deployment jurisdiction/legal review; precise guardian consent rules; safety severity taxonomy; emergency resource localization; wellbeing retention/export/deletion policy; AI provider contractual/privacy review.

## Release rule
AI wellbeing features remain feature-flagged off in production until their dedicated safety test suite and policy review pass.