# ADR-0002 — Family, Privacy and Parental Visibility

- **Status:** Accepted at product-principle level; detailed policy pending
- **Date:** 2026-10-05

## Context
LifeGuide must support meaningful parent involvement for minors while preserving enough personal space for a teen to trust and use the product. Treating all teen data as either fully private or fully parent-visible is unsuitable.

## Decision
Use independent accounts within a dynamic `Family Workspace` and a layered visibility model.

Initial conceptual visibility classes:
- Private
- Selected family members
- Parent/guardian
- Family
- Safety-controlled

Parents/guardians may receive authorized planning, academic information and actionable summaries/alerts. Private wellbeing conversations are not automatically exposed as full transcripts. Safety escalation is a separate policy path and can override ordinary sharing only under explicitly defined conditions.

Family membership and roles must be dynamic; no fixed family size or fixed father/mother/one-child schema.

## Consequences
- Authorization and parental visibility must be enforced server-side.
- AI context access must obey the same permissions; an AI guide does not gain universal access by default.
- Sensitive policy changes require auditability.
- Detailed age policy, consent model, safety thresholds and jurisdiction-specific requirements remain to be specified before production.
