# ADR-0004 — Frontend Baseline: Flutter

- **Status:** Accepted for Phase 2 baseline
- **Date:** 2026-10-05

## Decision
Use **Flutter** as the initial client framework for Android and the app-centric responsive Web/PWA surface, with platform-specific web integration where standards-based PWA behavior requires it.

## Why
LifeMate is an app-centric experience rather than a document/SEO site. A shared Dart/Flutter product surface reduces divergence between Android and PWA while preserving high visual fidelity and RTL control. Official Flutter guidance identifies PWAs, SPAs and existing mobile-style applications as suitable Flutter web scenarios.

## Important constraint
Flutter no longer generates/manages an application caching service worker by default. Offline/PWA caching must therefore be an explicit web concern using a custom standards-based service worker/Workbox or equivalent, not an assumed framework feature.

## Boundaries
- Do not force every web capability through Flutter abstractions. Manifest, install UX, Web Push/service worker integration, safe-area/platform metadata and browser-specific capability detection may live in `web/` integration code.
- Do not promise background behavior unsupported by iOS/PWA.
- Native iOS packaging remains a future distribution option because Flutter can target iOS, but initial iPhone distribution is PWA.
- Revisit this ADR only if a Phase 2 spike proves a blocking requirement (not aesthetic preference) cannot be delivered reliably.

## Alternatives considered
Separate Kotlin Android + React/Next PWA offers maximum platform specialization but creates two primary UI codebases before product-market validation. React Native does not remove the need for a separate web/PWA strategy as cleanly for this product. Both remain fallback options if a verified blocker appears.