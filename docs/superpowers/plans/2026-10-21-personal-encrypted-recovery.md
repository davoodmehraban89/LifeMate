# LifeGuide — approved synthetic recovery preparation

**Scope approved by the owner on 2026-10-21:** prepare option B in ADR0018 and test with fictional data only. No real device/data access, signing-key creation, merge, deployment, publication or deletion. Original installation and certificate baseline remain unchanged.

## Acceptance and ownership

1. **Coordinator:** supply this contract, integration CLI, atomic file publication, CI and evidence. Worktree `/tmp/lifeguide-recovery-options`, branch `feat/personal-encrypted-recovery`, based on PR43. No client/backend/schema changes in this package.
2. **Archive implementer:** `scripts/personal_recovery/archive.py` and `scripts/tests/test_recovery_archive.py` only. RED → GREEN for authenticated encryption and hostile input. No shared-file edits.
3. **Snapshot implementer:** `scripts/personal_recovery/snapshot.py` and `scripts/tests/test_recovery_snapshot.py` only. RED → GREEN against the existing SQLite v1 contract. No shared-file edits.
4. **Coordinator:** integrate, test full round trip and filesystem failures, document limits, create a small PR. Separate Android acceptance work follows; it must use fresh emulators and synthetic data, never a connected owner phone.
5. **Independent reviewer:** assess confidentiality/integrity, refusal paths, source preservation and evidence before completion.

Archive and snapshot implementation may proceed concurrently because file ownership and interfaces are disjoint. Integration and mutations to shared files are sequential. Agents must not commit, push, merge, run live commands or spawn more agents.

## Stable interfaces

`common.py`: `RecoveryError(code: str)` exposes only a safe reason code. `MAX_PAYLOAD_BYTES=8*1024*1024`, `MAX_ROWS=20000`, `SCHEMA_VERSION=1`, `FIXTURE_APPLICATION_ID=0x4C475146`.

`archive.py`: `seal(payload: bytes, passphrase: str) -> bytes`, `open_archive(archive: bytes, passphrase: str) -> bytes`. Format: magic `b'LGRF\\x01'`, 16-byte random salt, 12-byte random nonce, AES-256-GCM ciphertext+tag. Authenticate the whole header. Scrypt fixed n=32768/r=8/p=1, key32. Passphrase 12+ characters, <=1024 UTF-8 bytes, no normalization. Size/version bounds before expensive work; wrong password/tampering produce one safe error. Never write plaintext, log secrets, fetch data or accept caller-controlled KDF parameters.

`snapshot.py`: `create_sample_database() -> bytes` returns a valid synthetic SQLite v1 database; `export_fixture(path: Path) -> bytes` opens SQLite read-only and returns canonical UTF-8 JSON; `database_from_snapshot(payload: bytes) -> bytes` validates and reconstructs using fixed DDL in memory. Reject an unmarked source before reading profile/plan content: require `PRAGMA application_id=0x4C475146`, user_version1, whitelisted schema and integrity. The marker is an accident-prevention gate, not authentication or proof of provenance. JSON top-level keys are exactly `format`, `schemaVersion`, `syntheticOnly`, `tables`; format=`LifeGuideSyntheticRecovery`, syntheticOnly=true. Tables use existing column names and JSON row objects; canonical sorting by primary keys. Reject duplicate JSON keys, unknown fields/objects, invalid UUID/date/enum/integer/foreign keys, oversized payload/row counts. Known Android system table `android_metadata(locale TEXT)` may exist but its content is excluded. Preserve all personal profile, plan, weekly-slot and independent occurrence values including archive and completion. Fixture dates in 2024, explicit fictional labels, no phone/email. No source mutation, arbitrary SQL execution, reset or future-schema downgrade.

CLI: `create-fixture`, `pack`, `restore-fixture`, `demo`; all require `--acknowledge-synthetic-only`. No real-data override, adb or physical-device commands. Password via getpass only. Destination write-once, mode0600, atomic no-overwrite publication; validation completes before output creation. Demo uses a process-local random test password and reports counts/hashes/booleans only; never password or content. Interrupt/space failures must leave source and existing destination untouched. This is a synthetic QA tool, not an owner backup feature.

## Verification ledger

- [ ] Archive RED/GREEN and tamper/wrong-password/size/version checks.
- [ ] Snapshot RED/GREEN, source hash unchanged, full field/ID round trip and invalid inputs.
- [ ] CLI round trip on disk; close/reopen and independent SQL; no overwrite, interrupted/ENOSPC failure, no output before acknowledgement.
- [ ] Existing Python APK/Android host tests; tracked-secret and naming checks.
- [ ] CI on exact committed source; record success/failure, never infer Android acceptance from host tests.
- [ ] Independent whole-branch review, correct issues, rerun affected tests.
- [ ] PR and Persian runbook/evidence, exact VERIFIED/UNVERIFIED boundaries.

## Deferred separate acceptance package

Use the exact delivered original APK on a fresh emulator with only fictional v1 data; install a never-distributed `.personal` QA app alongside; compare both default databases after close/reopen and a subsequent same-test-key higher-code upgrade. Validate notifications default OFF without transferring consent or alarm state. No owner APK is eligible until stable owner signing and actual consent/local transfer acceptance are resolved. Physical device, Windows/USB, storage exhaustion on phone, OEM sound/Doze/reboot and real-data transfer remain UNVERIFIED unless separately run.
