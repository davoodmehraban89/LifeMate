# LifeGuide — Operating Rules

## Mission
Build LifeGuide as a maintainable, secure, attractive personal/family/learning companion. The product starts with a teen-and-family use case but must not be hard-coded to one family, one age, or one school year.

## Coordination model
The coordinating project lead owns prioritization, dependencies, integration, conflict resolution, and final delivery. Five specialist ownership areas are active:

1. **Product & Research** — discovery, scope, benchmark research, requirements, acceptance criteria.
2. **UX/UI & Brand** — teen/parent/family journeys, design system, RTL/accessibility, Figma, visual assets.
3. **Architecture, Data, Security & Safety** — domain model, auth, permissions, privacy, parental visibility, wellbeing safety, APIs and data architecture.
4. **Cross-platform Development** — Android, iOS/PWA, web, integrations, notifications, offline/sync.
5. **QA, Release & Observability** — independent verification, CI, regression, staging, telemetry and release readiness.

A tool or connector is not an agent. GitHub, Figma, Canva, Supabase, Context7, PostHog, Notion and other services are capabilities used by the responsible owner.

## Source of truth
1. The repository is the technical source of truth.
2. Read `AGENTS.md` and `PROJECT_STATE.md` before substantial work.
3. Significant product/architecture decisions must be recorded under `docs/decisions/`.
4. Notion may mirror management knowledge, but it must not silently override repository decisions.
5. Do not claim a decision, test, deployment, connection, or verification occurred unless it actually occurred.

## Product invariants
- `Profile` is broader than `Student`; school is a life context, not permanent identity.
- Family membership is dynamic; no fixed family size or fixed father/mother/one-child schema.
- Each person has an independent account.
- Sharing must support private, selected members, parent/guardian, family, and safety-controlled visibility where appropriate.
- Parent access and teen privacy are layered policies, not an all-or-nothing switch.
- Sensitive authorization must be enforced server-side.
- Wellbeing AI must not claim medical diagnosis or impersonate a clinician.
- Safety escalation is distinct from ordinary privacy/sharing.
- AI-generated plans are proposals unless the product explicitly defines safe automatic actions.
- The interface must remain usable and appealing as a teen grows older; avoid childish visual language.

## Distribution baseline
- Android: installable application.
- iPhone/iPad: high-quality PWA installed through Add to Home Screen, due to distribution constraints; design must not feel like a bookmarked website.
- Web/Desktop: responsive web experience.
- Preserve a future path to packaged/native iOS distribution without redesigning the domain/backend.

## Engineering workflow
- Prefer simple, reversible architecture over speculative complexity.
- Use feature branches and pull requests once application implementation begins.
- Run applicable tests, lint, static analysis and builds before declaring implementation complete.
- Use staging before production.
- Production deploys, destructive data operations, high-risk schema migrations, public release, paid actions, and sensitive access changes require explicit authorization relevant to that action.
- Secrets must not be committed to the repository or copied into documentation; use environment/secret management.
- Keep authoritative security and permission rules on the backend; client logic may support UX/offline behavior but cannot be the security boundary.

## UX / visual rules
- Persian RTL is first-class.
- Teen experience: warm, modern, graphical, inviting, calm and age-appropriate; not childish.
- Parent experience: clear, actionable and less decorative while sharing the same design language.
- Canva can supply visual assets/illustrations; Figma remains the primary UI/UX and design-system surface.
- Brand, app icon, PWA icon, favicon, splash/entry and login experience are product requirements, not final polish.

## Definition of done
A work item is complete only when its output exists, acceptance criteria have been checked, important unresolved risks are stated, and project state/decision documentation is updated when applicable.
