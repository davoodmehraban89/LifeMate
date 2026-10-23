# Synthetic Android recovery acceptance — B2

Approved boundary: ADR0018 option B preparation and fictional tests only. This is a separate PR on PR44. No owner data/phone, owner signing key, distribution, merge, deploy or DNS. Original `.device` certificate baseline and user-APK upload hold stay fixed.

The temporary execution environment was replaced before the previous uncommitted B2 harness reached GitHub. PR44 remains durable and its general CI39673693877 actually succeeded. Rebuild B2 from the persisted plan; commit partial work explicitly before environment resets. Do not call the lost draft verified code.

## Ownership and acceptance

- Coordinator: Gradle opt-in QA identity, manifest and Dart wrapper, workflow, docs/evidence; no application schema/feature changes.
- Host QA implementer: four new `*personal_recovery*` checker/harness Python files under `apps/lifemate/tool`; RED/GREEN for safety gates before integration.
- Independent reviewer: whole B2 diff and refusal paths. Coordinator runs actual CI and inspects receipt/screenshots.

1. Before any adb mutation, require explicit fictional-emulator acknowledgement, `emulator-N` serial, qemu+SDK hardware/product, API35, and no LifeGuide packages.
2. Inspect/signature-verify the exact delivered original APK using immutable baseline hash/certificate/package/code. Install without overwrite; seed only a newly owned, unlaunched install's absent default DB with the B1 closed fictional fixture. No uninstall, clear-data, force-stop, root or source checkpoint.
3. Launch ordinary original app UI, verify fictional profile visible, close normally and confirm process absent. Capture only when the same inert sidecar shape holds before and after: no sidecars; regular zero-byte WAL with absent/regular SHM and no journal; or regular zero-byte TRUNCATE journal with no WAL/SHM. Require PID absence both times; reject symlinks, abnormal sidecar types, nonempty WAL/journal, orphan SHM, and journal coexistence with WAL/SHM. Never remove/checkpoint any source file. This bounded amendment follows the actual c5942f4 Android metadata receipt (journal0/WAL+SHM absent), not a new owner-data transfer permission. Normalize only a private host copy, validate B1 snapshot and compare all fields after reopen.
4. B1 authenticated in-memory encrypted roundtrip; install never-distributed `.personal` QA code10 alongside. Seed only absent default DB, launch/reopen ordinary UI, compare all fields/IDs and independent SQL. Notifications/OS permission remain OFF; no consent copied.
5. Reopen original again, then update only the new QA app with same ephemeral test certificate and code11. Close/reopen both default DBs and compare every record. Test certificate is not an owner key or promise of production upgrades.
6. Use file-based UIAutomator dump with owned temporary filename and cleanup; `/dev/tty` was actually broken on the prior API35 run. Screenshots contain fictional records only.
7. CI uploads sanitized JSON and fictional PNGs only. No APK, SQLite, archive or key upload. App/fixture builds are debug-only with matching Gradle properties, Dart defines, target and codes; release/profile/mismatch fail closed. Existing online `.app` and personal `.device` defaults remain unchanged.

## Ledger

- [x] Host safety and manifest RED/GREEN.
- [x] Opt-in QA build gates; default identities preserved.
- [x] Independent review; applicable tests/format/analyze run.
- [x] Actual fresh API35 CI; inspect outputs and screenshots before claims.
- [x] Record failures and precise remaining UNVERIFIED items; PR and stop at real-data boundary.

Physical devices, Windows/USB/ACL, real data/keys, old-app notification ON/dedup, Doze/sound/reboot, permission consent UI and production readiness remain UNVERIFIED. Real owner transfer requires separately accepted tooling, local user choice and stable signing; this test harness is not that interface.

## Recorded outcome — 2026-10-23

Functional bdc97c8d95992385e91b40853d1c7a6c40c4c494: actual API35 run39914081997 PASS/complete; original UI, encrypted roundtrip, both default DBs close/reopen, QA same-test-key10→11 and second reopen all passed with full-field/independent SQL equality. Original DB hash unchanged, QA notifications OFF. Root officially downloaded artifact12484965895, verified ZIP/PNG hashes, inspected receipt and both real fictional screenshots. Host82/B1-55/Flutter332 and eight negative Gradle cases passed. GeneralCI39914082002 succeeded.

Actual prior failures (including the two date-dependent picker test failures) are retained in evidence; no success inferred from a failed run. The later date-picker fix is test-only, with unchanged RED2 then GREEN2, full332 pass and deterministic duplicate-label coverage. Final docs-only commit is not a new code test run (UNVERIFIED).

Personal delivery run39914082024 remains BLOCKED by original signer/version/default-DB upgrade guard; baseline and hard upload hold are unchanged. B2 does not prove old-install update or an owner signing key. [Evidence](../../audits/evidence/personal-recovery-android-2026-10-23.json), [runbook](../../operations/PERSONAL_RECOVERY_ANDROID_QA.md). Stop at this synthetic package boundary; no owner operation or new APK handoff.
