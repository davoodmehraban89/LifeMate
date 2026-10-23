# Local signing preflight implementation plan

Spec: [local signing preflight](../specs/2026-10-23-local-signing-preflight.md).
Base: PR45 `5f0c4da`; branch `feat/local-signing-preflight`.
Owner/coordinator: root; Java helper owner: signing inspector implementer;
independent review: separate reviewer. No owner key/device/data actions.

## Task 1 — JDK inspector and synthetic integration tests

Files owned: `scripts/java/LifeGuideKeyInspector.java`,
`scripts/tests/test_signing_java.py`, `scripts/tests/signing_test_support.py`.
Use the exact binary protocol and helper JSON schema in the spec. Success:
`schemaVersion: 1`, `status: INSPECTED`, four public fields named there; exit0.
Failure: `schemaVersion:1,status:REFUSED,reason:<fixed code>`; exit2.
Reason enum: `invalid_request`, `keystore_unreadable`, `private_key_unavailable`,
`unsupported_key_algorithm`, `key_proof_failed`, `inspection_failed`.
Reject trailing bytes and unsupported entry types. Sanitize all exceptions.
Remove password byte/char arrays best-effort. No dependencies beyond JDK17.

First write/run tests against absent helper (RED), then implementation (GREEN).
Actual keytool fixture generation is test-only in TemporaryDirectory; use
per-process random credentials via keytool `:env` flags and capture its output.
Never print test credentials or raw subprocess errors; no artifact upload.
Run `python3 -m unittest scripts.tests.test_signing_java -v`.
Expected: all tests pass with real JDK; fixture source hash unchanged.

## Task 2 — Python CLI and read-only/error guards

Files owned: `scripts/signing_preflight.py`,
`scripts/tests/test_signing_preflight.py`. Root implements independently of Java
files, consuming the exact protocol. Load baseline via existing verifier. Reuse
`read_bounded` for encrypted key file. `check` is default; `inspect --keystore
PATH --alias ALIAS --acknowledge-owner-local-inspection` is explicit/TTY-only.
Errors are JSON with safe fixed codes, never argparse argument interpolation.
No password env/CLI support, no key generation, no input searching, no file
writes. Java child options in env stripped, captured stdout strictly validated,
stderr discarded, timeout enforced. Tool report always delivery BLOCKED.

First write/run tests before implementation. Run
`python3 -m unittest scripts.tests.test_signing_preflight -v`.
Expected: safety gates fail closed, real inspector integration uses only fixtures.

## Task 3 — CI, guide, regression and independent review

Add `.github/workflows/signing-preflight-qa.yml`: paths-limited ubuntu/windows,
Python3.11/JDK17, contents read, no secrets/APK/device/network-dependent tests,
no test-key/report artifacts. Add Persian guide with check command and future
owner-only inspect command clearly gated by separate authorization. Explain
matching/different/debug results, no uninstall or sharing keys/passwords, limits.
Run new suites + existing Python tool/recovery suites; inspect every output.
Independent whole-packet review for secret leakage/file mutation/gate bypass.
Record actual commands/output and CI results in evidence JSON; record unrun
platforms/owner operations as UNVERIFIED. Update PROJECT_STATE. Open small PR on
PR45; no merge/release/deploy. Stop after handover.

## Execution ledger

- Setup: clean isolated worktree at `5f0c4da`; inherited AGENTS/state read.
- Preflight: Java→Python exact protocol/JSON shared; no overlapping implementation
  files. Tests and docs use baseline reader without alternative baseline input.
- Ruling: no new key-generation/transfer feature; read-only inspection is the
  smallest prep dependency. A wrong scope choice costs deferred usable transfer,
  not a change to installed data or approved policy.
- Task1: `79e1211`, 11 Java tests PASS on actual Temurin17; absent-helper RED and
  deliberately removed-proof mutation RED observed (synthetic mismatched cert).
- Task2: 24 Python tests PASS, including real synthetic CLI→JDK→keypair proof;
  missing-module RED, source17 capability RED, pre-prompt guard RED recorded.
- Ruling: check compiler module and empty-input source17 probe, not `javac` binary
  presence — system21 has compiler but lacks ct.sym/source17; false capability
  acceptance would delay inspection failure until after credentials. No key read
  during the probe. Downloaded temporary official checksum-verified JDK17 only.
- Ruling: inherited 82 host guards run on Ubuntu only because they invoke POSIX
  shell/FIFO operations; new signing suites run on both CI systems. Wrong scope
  costs missing Windows legacy-guard coverage, not weaker Android release gates.
- Local full regression: 90 tests in32.576s OK (55 recovery +35 signing), inherited
  host82 in0.197s OK; source compile and `git diff --check` exit0.
- Task3: CI and independent review pending; no owner key/device/data inspection,
  config/signing/build/APK/merge/deploy/DNS performed by this packet.
