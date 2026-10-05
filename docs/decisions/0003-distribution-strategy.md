# ADR-0003 — Initial Distribution Strategy

- **Status:** Accepted at product-strategy level; frontend technology pending validation
- **Date:** 2026-10-05

## Context
The product must support Android, iPhone/iPad and desktop/web. iOS store distribution can be operationally constrained for the initial target environment, so iPhone access must not depend on App Store publication.

## Decision
Initial distribution targets:
- **Android:** installable application.
- **iPhone/iPad:** high-quality PWA with Add to Home Screen and standalone experience.
- **Web/Desktop:** responsive web application.

All clients share the same backend, identity, permissions and data model. Architecture must preserve a future path to packaged/native iOS distribution.

The iPhone PWA must be designed as a product surface, not a fallback webpage: branded icon, splash/entry, safe-area handling, responsive/RTL UI, offline-aware behavior where feasible, and clear install guidance.

## Consequences
- PWA platform limitations must be validated before committing to features such as background execution, notifications and storage assumptions.
- Cross-platform frontend technology remains an implementation decision. Flutter is a candidate, not yet an irreversible commitment.
- Backend contracts and domain rules must remain client-independent.
