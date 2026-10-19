# LifeGuide personal device planner — implementation plan

> **For agentic workers:** Use isolated specialist ownership with integration and independent review by the root. Checkboxes record the bounded delivery, not release readiness.

**Goal:** Deliver an Android APK usable immediately without API setup: private weekly planning, independent occurrence completion, local notifications and durable restart.
**Architecture:** Separate debug-only Android package/entrypoint; authoritative transactional SQLite, no HTTP imports or INTERNET permission. Reuse the proven native alarm engine behind a distinct guarded device channel; keep online identity/permissions unchanged.
**Tech stack:** Flutter3.47.6, Dart, sqflite, Android AlarmManager/NotificationManager.
**Spec:** [ADR0016](../../decisions/0016-initial-child-planner-delivery.md), current owner instruction for a usable APK without API and subsequent continue after scoped explanation.

## Global constraints

- One local personal profile; profile_category never grants a family role. No phone/email/OTP/server account claims.
- Separate `ir.lifeguide.app.device`, label «لایف‌گاید شخصی», version0.7.2-personal.1/code9; production `ir.lifeguide.app` unchanged. Debug is not a release.
- SQLite v1 in app-private storage, backup disabled. No imports from online API/cache/auth. No sample rows in the user build; fixtures use separate database files.
- No merge/deploy/DNS/foreign real child data. Tests synthetic; every runtime claim needs commands/output. Phone/Safari/Iran acceptance stays UNVERIFIED.

## Review focus

1. Save failures/corrupt DB must never report success or silently reset data.
2. Repeated generation and restarts cannot duplicate occurrences or tick a different date.
3. An OFF choice or edited/completed item must not reappear as a stale alarm after asynchronous work/restart.
4. The user artifact must be the real standalone entrypoint, not a fixture or ordinary online APK.
5. App update/install must not overwrite an older app/account/cache or require data deletion.

## Task1 — Durable personal data (owner: standalone_storage)

- [ ] Implement `lib/standalone/model.dart` and `store.dart` and actual file DB tests in `test/standalone_store_test.dart`.
- [ ] Single editable profile; daily/every2days/weekday slots/one-off, independent occurrence edits, completion and archive.
- [ ] Verify Create→Close→Reopen→Read→Update→Read→Archive; transactions, validation, stable IDs and generation uniqueness.

## Task2 — Working RTL interface (owner: standalone_ui)

- [ ] `standalone/app.dart`, `planner_ui.dart`, `settings_ui.dart`, focused widget tests. No account/server screens or inert feature cards.
- [ ] Home, Saturday-first week, editable forms, per-occurrence details, explicit device-only setting, local profile/theme edits.
- [ ] Before-write alarm invalidation, awaited save, after-write refresh; storage failures stay visible without clearing data.

## Task3 — Local reminders (owner: standalone_reminders; native helper owns its Kotlin files)

- [ ] Dedicated device-only types/channel; BuildConfig guard; no fabricated server acknowledgement.
- [ ] Default OFF, explicit permission/opt-in, next28days/max128 nearest records with visible limit; generic lock-screen body and chosen companion name.
- [ ] Native and Dart OFF choices fail closed; suspend before data writes and reconcile only from actual DB rows. Online24h lease remains unchanged; device lease capped31days.

## Task4 — Isolation and delivery (owner: root)

- [ ] Gradle debug-only package and highest-priority no-INTERNET manifest; isolated `standalone_main.dart`, actual reminder settings/coordinator.
- [ ] Binary checker rejects online package, wrong version/activity, network/extra permissions, backup or exported reminder receiver.
- [ ] CI builds user APK first, copies LifeGuide.apk, then builds never-distributed fixture. Guard filenames/entrypoints and verify both signatures/manifests.

## Task5 — Android acceptance (owner: standalone_android_acceptance)

- [ ] Fresh emulator only; refuse physical/preinstalled package before writes. Launch exact user APK and capture onboarding screenshot.
- [ ] Replace only the just-installed synthetic fixture package with same-cert fixture; alternate fixture SQLite; real independent SQL reads and restart/tick/edit/archive.
- [ ] Prove native alarm after ordinary process death, cancellation before deadline and OFF; no force-stop/manual notification and no false-death transport fallback.

## Final gates (owner: root)

- [ ] Run full Flutter suite/analyze/format, Python tool tests, JSON/naming/credential scans; preserve failing outputs and fixes.
- [ ] Independent review; small dependent PR; actual CI logs, artifact digest/manifest/signature. No merge or deployment.
- [ ] Preserve tracked source, evidence and correct downloadable LifeGuide.apk in /workspace; explain local-only scope and real-device gaps.

Commands/results become VERIFIED only after execution; expected outcomes here are UNVERIFIED until the evidence report is written.
