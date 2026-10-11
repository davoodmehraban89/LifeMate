# ADR 0013 — Evidence of learning, publication review and private family feedback

Date: 2026-10-09. Status: accepted for local development. Extends ADR0012 following the owner's stricter content requirements.

LifeGuide serves the whole family. School textbooks from authoritative current Iranian editions anchor school objectives; teaching methods use international learning research. Future parenting, couple communication, sibling relationships and workplace learning are separate age/audience contexts, not school grades or gender stereotypes.

Video metadata is a research candidate, not approved teaching. Every teaching resource and assessment starts draft. Learner publication requires a recorded full review of current-edition alignment, accuracy, age suitability, explanation/exercises and display rights. Imports cannot publish candidates. The current research has no completed pedagogical video reviews; therefore it must not automatically populate the published player list. Rights and third-party behavior remain explicit.

Separate self-reported completion, recorded study time and assessment evidence. The assessment foundation grades submitted answers server-side, returns explanatory/remedial feedback, stores versioned owner-private attempts and proposes spaced review. It does not infer comprehension from watching, call a single score mastery, or guarantee understanding. Questions require review before publication. Broader chapter exams, open-answer rubrics and effectiveness measurement remain future acceptance work.

Feedback to the content team is an explicit, separate submission. No extraction of private AI conversations, notes, health/cycle details or abuse disclosures into product analytics/development occurs. The service stores only a user-chosen minimal summary/category and target; account identity is server-derived. Consent, per-owner access, rate limits, stable mutation IDs and withdrawal are server-enforced. The development loop is request → triage → research brief → owner review → branch/PR/tests → separately approved release. No autonomous live code change, private-data export or notification to another person is authorized by this ADR.

Age-appropriate AI support remains disabled until provider, consent, privacy and safeguarding gates are met. It must never introduce itself as a psychologist or diagnose. An abuse disclosure needs a distinct reviewed support/safety flow, an appropriate safe adult/professional route and an explicit imminent-danger policy; automatic parental forwarding may harm a child when a caregiver is implicated. This ADR does not implement or certify that flow. Sensitive data residency in-country, licensed specialist review, retention and minor consent remain launch gates.

Generalized international curricula/providers/languages use separate catalogue context, not changes to the existing repo/schema/JWT names. Public hosting, current-child data migration and commercial release remain unauthorized.
