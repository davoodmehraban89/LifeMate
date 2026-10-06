# LifeGuide Rebrand & Domain Migration Design

Date: 2026-10-06
Status: Approved design, pending implementation plan and execution
Repository: davoodmehraban89/LifeMate
Current runtime project: LifeMate-Staging
New product brand: LifeGuide
Primary owned domain: lifeguide.ir

## 1. Goal

Rebrand the existing LifeMate product to LifeGuide without rebuilding the project, while preserving working functionality and keeping the current staging release path intact.

The migration must also establish LifeGuide-owned web and email identity so the project no longer depends on any domain, API key, or sender identity belonging to other projects.

## 2. Scope

### In scope

- Replace user-facing product branding from LifeMate to LifeGuide.
- Use `lifeguide.ir` as the canonical brand domain.
- Prepare:
  - `app.lifeguide.ir` for the PWA.
  - `api.lifeguide.ir` for the backend API.
  - `no-reply@lifeguide.ir` for transactional email.
- Update Flutter/PWA metadata and visible UI branding.
- Update Android application label and release artifact naming.
- Audit Android application ID and migrate away from the current example identifier using a production-safe LifeGuide identifier.
- Update backend transactional email subjects/body text from LifeMate to LifeGuide.
- Update public URLs used inside verification, reset-password, and invitation emails.
- Update relevant documentation and release notes.
- Configure Resend exclusively with LifeGuide-owned domain/sender resources.
- Re-run CI and smoke tests after rebranding.
- Produce a stable `LifeGuide.apk` and HTTPS PWA endpoint.

### Out of scope for this migration

- Rebuilding application architecture.
- Renaming database tables, columns, enum values, or historical migration identifiers solely for branding.
- Destructive database migration.
- New feature development unrelated to the rebrand.
- Altering resources, DNS, domains, sender identities, API keys, or services owned by Factoreasy or other projects.
- App Store / Google Play production release.
- Large visual redesign.

## 3. Brand conventions

Canonical product name:

`LifeGuide`

Persian display name where needed:

`لایف‌گاید`

Primary domain:

`lifeguide.ir`

Recommended service layout:

- Website / future landing page: `https://lifeguide.ir`
- PWA: `https://app.lifeguide.ir`
- API: `https://api.lifeguide.ir`
- Transactional email sender: `LifeGuide <no-reply@lifeguide.ir>`

Staging Railway domains may remain available as fallback operational endpoints during migration, but they are not the long-term product identity.

## 4. Technical strategy

### 4.1 Preserve repository and data continuity

The existing repository remains the source of truth during this migration. No new replacement project is created.

Existing database schemas and historical migration names remain unchanged unless they are directly user-visible or technically required to change.

### 4.2 User-facing rename

Audit and replace branded strings in:

- Flutter application UI.
- PWA manifest/title metadata.
- Android application label.
- Login/register/verification flows.
- Transactional email subjects and bodies.
- README and user-facing documentation.
- Build/release artifact names.

Replacement must be targeted. Generic identifiers containing `lifemate` are not blindly renamed if doing so risks compatibility.

### 4.3 Android package identity

The current example package identifier is not production-ready.

The implementation phase must inspect current Android package configuration and choose a stable LifeGuide application ID. Preferred pattern:

`ir.lifeguide.app`

If Android tooling or package namespace constraints make this inappropriate, the implementation plan must document the selected final identifier before changing it.

Signing remains internal/test signing for the current release candidate unless a production keystore is separately approved.

### 4.4 Domain migration

DNS will be configured only for `lifeguide.ir`.

Expected records will be derived from Railway and Resend rather than guessed.

The migration order should avoid outage:

1. Keep current Railway endpoints functioning.
2. Attach and verify `api.lifeguide.ir`.
3. Attach and verify `app.lifeguide.ir`.
4. Update application API base URL and CORS.
5. Verify LifeGuide email domain in Resend.
6. Configure `EMAIL_FROM=LifeGuide <no-reply@lifeguide.ir>`.
7. Update `PUBLIC_APP_URL`.
8. Smoke test.
9. Keep Railway-generated domains as fallback until verification is complete.

### 4.5 Email isolation

LifeGuide must use its own Resend sender/domain configuration.

Mandatory rules:

- Do not modify Factoreasy DNS.
- Do not modify or delete Factoreasy Resend resources.
- Do not use a Factoreasy sender address for LifeGuide.
- Create or use a LifeGuide-specific Resend API key restricted to the LifeGuide domain where supported.
- Store the key only as a secret/environment variable.
- Never commit or display it in source code or documentation.

Transactional email flows to verify:

- Email verification.
- Forgot/reset password.
- Family invitation.

### 4.6 Backend branding

The backend can keep internal schema identifiers for compatibility, but all externally visible copy must say LifeGuide.

Examples:

- `تأیید حساب LifeGuide`
- `برای تأیید حساب LifeGuide ...`
- `بازیابی رمز عبور LifeGuide`

JWT issuer/audience or other security-sensitive protocol identifiers should not be renamed merely for appearance unless the implementation audit confirms the migration is safe and coordinated.

## 5. UX requirements

Registration page must explicitly state:

`رمز عبور باید حداقل ۱۰ کاراکتر باشد.`

After successful registration, show a clear success state such as:

`ثبت‌نام با موفقیت انجام شد. برای فعال‌سازی حساب، ایمیل خود را بررسی و روی لینک تأیید LifeGuide بزنید.`

The UI must not say an email was sent unless the backend reports that the delivery provider accepted the message for sending.

If email delivery is unavailable, present an actionable non-misleading error/state.

## 6. Deployment and release artifacts

Required user-facing outputs:

- PWA reachable over HTTPS under LifeGuide domain.
- Android artifact named `LifeGuide.apk`.
- Both clients connected to the same online backend and PostgreSQL database.
- Backend reachable via LifeGuide API domain.
- Existing Railway fallback endpoint retained until migration validation completes.

## 7. Security and privacy

This migration must not weaken any existing minor-data or family-isolation controls.

Special care:

- No secrets in repository or chat-visible documentation.
- No accidental cross-project secret/domain reuse.
- No destructive database reset.
- No production signing secrets committed to Git.
- CORS restricted to approved LifeGuide origins.
- Transactional email links use HTTPS LifeGuide URLs.
- Existing child/guardian privacy boundaries remain unchanged.

## 8. Validation

### CI

All existing required checks must pass before final release declaration.

### Smoke tests

Minimum post-migration tests:

- PWA opens from LifeGuide HTTPS domain.
- Android APK installs and opens.
- Register.
- Registration password validation message.
- Registration success/email instruction message.
- Verification email accepted by Resend and delivered to a real inbox.
- Email verification link works.
- Login after verification.
- Forgot password email.
- Reset password.
- Profile.
- Family creation.
- Invitation email.
- Parent/child relationship.
- Planner.
- Education profile.
- Calendar.
- Logout/session behavior.
- API connectivity from both PWA and Android.

### Cross-project isolation check

Explicitly verify that no LifeGuide runtime configuration references:

- `factoreasy.ir`
- Factoreasy sender addresses.
- Factoreasy-specific API keys.
- Other unrelated project service domains.

## 9. Rollback

Until LifeGuide domains are fully validated:

- Retain current Railway-generated service domains.
- Do not delete working services.
- Do not remove old endpoints until both PWA and API custom domains pass smoke testing.
- Changes should be committed in reversible steps.

If custom-domain migration fails, clients may temporarily continue using the current working Railway backend while DNS/configuration is corrected.

## 10. Definition of Done

The rebrand is complete only when:

- Product UI consistently displays LifeGuide.
- No user-facing LifeMate branding remains in active flows.
- PWA is available via `app.lifeguide.ir` over HTTPS.
- Backend is available via `api.lifeguide.ir` over HTTPS.
- CORS allows the LifeGuide PWA and rejects unapproved origins.
- Resend has a verified LifeGuide-owned sending domain.
- Verification/reset/invitation email uses `no-reply@lifeguide.ir`.
- A real external inbox receives the verification email.
- `LifeGuide.apk` is generated and works against the same API.
- Registration clearly documents the 10-character minimum password.
- Registration clearly instructs users to check email after success.
- CI is green.
- Required smoke tests are documented as passed or explicitly unresolved.
- No Factoreasy or unrelated project resource is modified or referenced by LifeGuide runtime configuration.
