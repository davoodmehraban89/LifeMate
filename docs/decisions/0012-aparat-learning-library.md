# ADR 0012 — Grade-aware learning catalogue and in-page Aparat

Date: 2026-10-09. Status: accepted for local implementation; deployment remains gated.

Feature 1 supplies education profiles and a grade-7 textbook seed but no teaching videos or lesson progress. The owner requests grades1–12 teaching inside LifeGuide, using Aparat embeds without downloading or redirecting by default.

Extend the existing PostgreSQL curriculum/textbook model with evidence-bearing ordered units/resources and owner-private self-reported progress. Use deterministic imports, expected-version mutations and durable client queues. Reuse canonical planner/study sessions; do not infer learning from playback.

Use the official HTTPS Aparat player in a click-to-load iframe on web/PWA and an in-page WebView on Android. Accept only a video hash, no arbitrary HTML/URL. Keep credentials and user metadata out of provider requests, suppress referrer, permit only the player frame in the application's frame policy. Aparat is a narrow user-authorized exception to the local-only runtime-assets policy; no external font/CanvasKit/API dependency follows from it.

Tradeoffs: video streaming cannot be offline; provider advertisements, cookies, removal, availability and network restrictions are outside LifeGuide's control. Metadata/free-access checks do not certify teaching quality. Catalogue counts must disclose missing coverage and edition alignment. Full pedagogical review and Android/Safari acceptance remain UNVERIFIED. No provider account, payment, public deployment or live migration follows from this ADR.
