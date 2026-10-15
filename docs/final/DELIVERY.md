# LifeGuide Feature 1 — Historical Delivery Checklist

**Status as of 2026-10-15:** historical checklist, not current release acceptance. Artifact labels below match the old CI configuration. Phase 0 identified authorization, sensitive-data and device acceptance blockers; cycle tracking is not an approved MVP capability. Follow [PROJECT_STATE](../../PROJECT_STATE.md) before using this checklist. No fresh APK, release signature or device test is verified by this document.

## Installable outputs
Every green CI run retains:
- `lifemate-android-apk` — release APK for owner-side Android installation/testing.
- `lifemate-web-release` — production Web/PWA bundle for controlled hosting/testing.

## iOS
The Flutter iOS project is present in `apps/lifemate/ios`. A signed `.ipa` requires macOS/Xcode plus the owner's Apple Developer signing identity/provisioning profile. Verification command on an authorized macOS runner: `flutter build ios --release --no-codesign`; distribution requires explicit signing/publication approval.

## Feature 1 test path
1. Sign in with a test account.
2. Open **پروفایل و خانواده → خانواده و یادگیری ایران**.
3. Choose mother/father/child persona. For a child choose grade 1–12; grade 7 resolves to first year of lower secondary.
4. Verify grade catalog and official textbook-source links.
5. Verify Jalali 1405 event data, Saturday week start and Iran weekend defaults.
6. Verify notification preferences and sensitive-preview default-off behavior through the API-backed settings model.
7. Verify private cycle entries are visible only to the owning account.

## External gates
Public production release, store publication, Apple signing, production push-provider credentials, external AI/voice enablement, and textbook PDF redistribution remain explicit external gates.
