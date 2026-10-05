# LifeMate — Phase 2 Quality Gates

## Pull request gates
Once application code exists, every implementation PR must run:
1. formatting check;
2. Flutter/Dart static analysis;
3. unit/widget tests relevant to changed domain/UI;
4. authorization/database tests when schema/RLS changes;
5. Android debug build smoke;
6. Web release/debug build smoke as appropriate;
7. secret scanning/dependency review available in the repository plan/tooling.

## Security tests required for identity/family
For each protected resource, test allowed and denied access for: owner profile, related guardian, unrelated family member, removed member, unauthenticated user and privileged server path where applicable. RLS tests must cover SELECT/INSERT/UPDATE/DELETE rather than only happy-path reads.

## Staging rule
All deployable changes land in staging before production. Staging uses separate environment/secrets/data from production. No production deploy, destructive migration or sensitive access change is implied by merge alone.

## Observability baseline
- Crash/error reporting with sensitive-data scrubbing.
- PostHog only from an explicit event allowlist.
- Feature flags for risky/AI capabilities.
- No raw wellbeing transcript/private free text in analytics.

## UX smoke
At minimum verify Teen and Parent core flows at mobile width, Persian RTL, text scaling, keyboard/input, empty/loading/error states and offline/reconnect behavior relevant to the feature.

## Platform smoke
Android + iPhone Safari + iPhone Home Screen PWA + desktop web for release-critical flows. Browser automation may cover web regressions, but Home Screen/PWA behaviors require real-device validation before production release.

## Definition of done
A feature is not complete because code exists. It requires passing automated checks, acceptance criteria, relevant platform smoke, updated decisions/state and explicit remaining-risk disclosure.