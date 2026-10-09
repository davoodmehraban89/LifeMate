**Historical snapshot — retained as decision/evidence history. Current product: LifeGuide; current execution status: PROJECT_STATE.md.**

# LifeGuide backend contract

Phase 2 keeps infrastructure provider-neutral.

## IdentityProvider
Required operations: register(email,password), verifyEmail(token), signIn(email,password), requestPasswordReset(email), resetPassword(token,newPassword), changePassword(session,currentPassword,newPassword), revokeSession(session).

Security requirements: normalized email; non-enumerating recovery response; single-use/time-limited verification and reset tokens stored as digests; modern password hashing in the identity adapter; session rotation/revocation; rate limiting; audit sensitive changes.

## LifeGuide API authorization
Every request resolves an authenticated `app_user`. Family operations evaluate active membership and explicit guardian relationships server-side. `owner_admin` is administrative authority and never grants blanket access to private teen content. Safety-controlled access is a separate audited policy path.

## Invitation
Invitation token is random, time-limited and stored only as a digest. Acceptance requires authenticated email match (or an explicitly audited admin correction flow), active pending status and expiry validation. Membership is created transactionally with invitation acceptance.

## PostgreSQL
`migrations/` contains portable schema migrations. Database helper functions/constraints are defense in depth. Clients never connect with database-owner credentials.

## Staging
CI exercises migrations/tests against an isolated PostgreSQL service. Persistent managed staging is attached separately and must use its own credentials/data before Phase 2 is declared complete.

Current hosting is the root Docker Compose Stage 0 package; see docs/operations/STAGE0.md. Backend version0.5.0 requires current migrations before startup. External AI/voice and sensitive features are disabled; actual evidence and UNVERIFIED release/device gates are in PROJECT_STATE.md.
