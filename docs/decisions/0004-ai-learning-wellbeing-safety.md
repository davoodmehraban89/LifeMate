# ADR 0004 — AI Guides, Learning & Wellbeing

Status: Accepted for Phase 4 engineering/staging.

## Decision
AI Guides are advisory. They may propose study, planner, wellbeing and family-support actions but never silently mutate planner data. Explicit proposals require user acceptance.

Wellbeing guidance is supportive self-reflection and family communication guidance, not diagnosis, treatment or a substitute for a clinician or emergency service. The product must not present AI as a doctor or psychologist.

AI sessions, messages and wellbeing notes are owner-private by default. Family membership or family-admin status does not grant raw transcript access. A wellbeing check-in can be marked `guardian_summary`; guardian endpoints expose only aggregates and safety signals, never the note body or private AI transcript.

Parents/guardians with an active guardian relationship can request family guidance. The guide receives only authorized academic metrics, authorized wellbeing aggregates and safety-signal counts. The API response explicitly records that raw notes and raw conversations were not included.

## Safety boundary
The server classifies messages before generative output. High-risk self-harm language receives a fixed safety-first response and creates a separate `wellbeing_safety_event` signal. Safety escalation is therefore distinct from ordinary privacy sharing.

The fixed urgent response directs the user toward an immediately available trusted person and local emergency resources. This is an engineering guardrail, not the final jurisdiction-specific crisis system.

## Provider boundary
Phase 4 has a provider-neutral OpenAI-compatible adapter controlled by `AI_BASE_URL`, `AI_API_KEY` and `AI_MODEL`. If no approved provider is configured, staging uses the deterministic local guide. Urgent safety responses never depend on the external model.

No minor-sensitive provider configuration may be enabled in public production until provider privacy, retention, data-location and safety review passes.

## Learning behavior
Study guidance should favor hints, decomposition, active recall and checking understanding rather than immediately supplying final homework answers. Learning goals and confidence/difficulty check-ins remain separate from grades so the product can track learning process as well as outcomes.

## Production gate
Public production exposure of wellbeing/minor-sensitive generative AI remains disabled until all of these are approved:
- jurisdiction-specific legal and guardian-consent review;
- safety severity taxonomy and escalation policy;
- localized emergency resources;
- AI provider privacy/retention/data-location review;
- wellbeing and AI retention/export/deletion policy;
- final voice-provider privacy review before voice conversations are enabled.

Voice remains a product requirement, but Phase 4 does not enable microphone/TTS transmission until the provider/privacy gate is selected and tested.
