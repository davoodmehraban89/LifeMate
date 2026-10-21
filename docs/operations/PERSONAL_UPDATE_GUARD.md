# Personal Android update delivery guard — 2026-10-21

Offline data preservation takes priority. This change blocks incompatible APK
delivery; it does not provide a new installable update or prove preservation of
the child's installed data. App code9, the normal manifest checker, SQLite
schema1 and the online edition remain unchanged.

The public [baseline](personal-delivered-baseline.json) describes the **DELIVERED**
APK, not a verified reading of the actual device. Its identity comes from
[the existing handoff](PERSONAL_ANDROID.md) and
[recorded APK verification](../audits/evidence/personal-android-2026-10-20.json).
Actual-device signer/version and upgrade preservation remain **UNVERIFIED**.

## Recorded comparison

| Evidence | Delivered baseline | PR39 personal CI |
| --- | --- | --- |
| Run | 39480587450 | 39541418453 |
| Source | `3e36dfd4f01d51e11816c0f97d1abda4266f1945` | `c5cb3084f665cb5b1546447e34e35963e5ea5597` |
| User APK artifact | 12292340083 | 12320495397 |
| Package | `ir.lifeguide.app.device` | `ir.lifeguide.app.device` |
| Version code | 9 | 9 |
| Certificate SHA256 | `4ef990d647fc98ac41113d5dbe7ee476ba80bf95b71b5f219b7863fa95263391` | `0e5c979c14a3f293a443aba20e7e54e228ae98d78ed9861a1f0fb3f00ec20889` |
| APK SHA256 | `c24ff6e75a987945399b0d96129f5d1a72525fa0270f31b0c481f9780f84db8e` | `7eea3d839179d02d140389da62ba7c2a14894c031f96b6a21a47e742164284b0` |

The latest CI succeeded. Its verification artifact12320565252 was obtained
through the official GitHub connector and inspected in memory. ZIP SHA256
`ba787baff54364a0f9d32b713c43447f3d53f84fd2a1a52be5d0e2a02a03d055`
matched GitHub's artifact digest. Its apksigner report and emulator receipt agree
on the newer certificate; the signature report says Android Debug, v2 verified,
v3 false. This is recorded CI evidence, **not a new local cryptographic
verification of the whole APK**. The baseline must never advance to a random
new debug certificate just to pass CI.

The certificate mismatch prevents a normal update over the delivered package.
Equal code9 also fails the new monotonic-delivery policy; Android can allow
same-version replacement in some circumstances. Availability of the original
matching private key is unknown. An unrelated new owner key cannot replace
this v2-signed installation. A certificate/APK does not supply its private key.
No signing key was read, generated, exported or configured.

## Enforced delivery policy

`tool/check_standalone_update.py` accepts only an actual APK path. It reads the
binary manifest with the existing parser, computes the APK hash and invokes the
existing `certificate_digest` apksigner probe. A successful verifier process and
exactly one valid certificate digest are required. Neither a CLI-provided digest
nor a CLI-provided baseline can establish trust.

The reviewed baseline requires the same package and original signer plus a
strictly greater version code. Missing verifier, invalid/multiple signer output,
invalid manifest/baseline and incompatible candidates produce sanitized reason
codes and a nonzero exit. A necessary-compatibility PASS still reports
`dataPreservation: UNVERIFIED` and `delivery: BLOCKED`.

The workflow keeps existing build/tests and fresh-emulator SQLite/notification
acceptance before the new compatibility check. The check is immediately before
the user-APK upload so a signer mismatch does not prevent native regression
evidence. That upload additionally has an explicit source-level `if: ${{ false }}`
hold, with no environment, workflow-input or manual-dispatch bypass. Diagnostic
artifacts still upload with `always()`. Current code9 must fail compatibility;
the resulting failed delivery job is intentional and is not a green-APK claim.

Removing the upload hold requires reviewed implementation and independent
acceptance of exact delivered APK → candidate using the default product DB.
The current same-run fixture uses another DB and creates records after its
replacement, so it does not meet this requirement. Acceptance must preserve
profile/UUIDs/theme/companion, weekly dates/times, per-occurrence edits/ticks and
archives, reminder opt-in/off and native pending/delivered state. It must verify
no onboarding/data reset/duplicate notification, and a future reminder after
replacement with the process absent. Never uninstall or clear child data to
resolve a signature conflict. Physical-device acceptance remains separate.

## Local verification actually run

Commands below run from `apps/lifemate` unless stated otherwise. All new tests
were written first. Before implementation:

```text
python3 -B -m unittest discover -s tool -p 'check_standalone_update_test.py' -v
Ran 12 tests in 0.002s
FAILED (failures=12)
AssertionError: unexpectedly None : The fail-closed personal update guard is missing
```

After implementation:

```text
python3 -B -m unittest discover -s tool -p '*standalone*test.py' -v
Ran 35 tests in 0.026s
OK

python3 -B -m unittest discover -s tool -p '*test.py' -v
Ran 60 tests in 0.030s
OK
```

The new policy tests cover wrong signer/package, equal/lower/invalid version,
missing/malformed/multiple/failed verifier output and a necessary-compatible
candidate that still cannot claim data preservation. External-process outputs
and parser results are mocked only to test rejection boundaries; those tests
are **not cryptographic or Android acceptance evidence**.

The pure policy replay below uses the independently obtained CI report values,
not an APK verifier result from this workspace:

```sh
python3 -B - <<'PY'
import json
import sys
sys.path.insert(0, 'tool')
from check_standalone_update import load_baseline, validate_compatibility
reported_ci_evidence = {
    'package': 'ir.lifeguide.app.device',
    'versionCode': 9,
    'certificateSha256': '0e5c979c14a3f293a443aba20e7e54e228ae98d78ed9861a1f0fb3f00ec20889',
    'apkSha256': '7eea3d839179d02d140389da62ba7c2a14894c031f96b6a21a47e742164284b0',
}
print(json.dumps(validate_compatibility(reported_ci_evidence, load_baseline()), sort_keys=True))
PY
```

```json
{"dataPreservation": "UNVERIFIED", "delivery": "BLOCKED", "deliveryReasonCode": "default_database_upgrade_acceptance_missing", "installedDeviceVerification": "UNVERIFIED", "reasonCodes": ["certificate_mismatch", "version_code_not_incremented"], "result": "BLOCKED"}
```

No new local Android build, apksigner verification or device installation was
performed for this guard. No merge, deploy, live configuration or real data was
changed. Existing code9 builds and random debug signing are not repair claims.
