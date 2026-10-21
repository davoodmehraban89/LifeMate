#!/usr/bin/env python3
"""Check necessary APK update compatibility; data-preserving delivery stays blocked."""
import argparse
import hashlib
import json
import re
from pathlib import Path
from zipfile import ZipFile

from check_apk_manifest import manifest_tags
from test_standalone_android import certificate_digest

BASELINE_PATH = Path(__file__).resolve().parents[3] / 'docs/operations/personal-delivered-baseline.json'
PACKAGE = 'ir.lifeguide.app.device'


def _digest(value):
    return isinstance(value, str) and re.fullmatch(r'[0-9a-f]{64}', value) is not None


def load_baseline():
    """Only reviewed repository source supplies the public delivered baseline."""
    baseline = json.loads(BASELINE_PATH.read_text(encoding='utf-8'))
    if (not isinstance(baseline, dict) or baseline.get('schemaVersion') != 1 or
            baseline.get('status') != 'DELIVERED' or baseline.get('package') != PACKAGE or
            type(baseline.get('versionCode')) is not int or baseline['versionCode'] < 1 or
            not _digest(baseline.get('certificateSha256')) or not _digest(baseline.get('apkSha256')) or
            baseline.get('installedDeviceVerification') != 'UNVERIFIED' or
            not isinstance(baseline.get('source'), dict) or
            type(baseline['source'].get('artifactId')) is not int):
        raise ValueError('delivered_baseline_invalid')
    return baseline


def _report(reasons):
    return {'result': 'BLOCKED' if reasons else 'PASS', 'reasonCodes': reasons,
            'dataPreservation': 'UNVERIFIED', 'installedDeviceVerification': 'UNVERIFIED',
            'delivery': 'BLOCKED', 'deliveryReasonCode': 'default_database_upgrade_acceptance_missing'}


def validate_compatibility(evidence, baseline):
    """Pure policy over independently inspected evidence, never an APK verifier.

    The command-line path below obtains these values from the actual APK and
    apksigner. Passing these checks cannot establish database preservation.
    """
    reasons = []
    if evidence.get('package') != baseline['package']:
        reasons.append('package_mismatch')
    certificate = evidence.get('certificateSha256')
    if not _digest(certificate):
        reasons.append('certificate_invalid')
    elif certificate != baseline['certificateSha256']:
        reasons.append('certificate_mismatch')
    version = evidence.get('versionCode')
    if type(version) is not int or version < 1:
        reasons.append('version_code_invalid')
    elif version <= baseline['versionCode']:
        reasons.append('version_code_not_incremented')
    if not _digest(evidence.get('apkSha256')):
        reasons.append('apk_digest_invalid')
    return _report(reasons)


def check(apk):
    try:
        baseline = load_baseline()
    except Exception:
        return _report(['delivered_baseline_invalid'])
    try:
        apk = Path(apk)
        with ZipFile(apk) as archive:
            if archive.namelist().count('AndroidManifest.xml') != 1:
                raise ValueError('ambiguous_manifest')
            tags = manifest_tags(archive.read('AndroidManifest.xml'))
        manifests = [attributes for tag, attributes in tags if tag == 'manifest']
        if len(manifests) != 1:
            raise ValueError('ambiguous_manifest')
        evidence = {key: manifests[0].get(key) for key in ('package', 'versionCode')}
        evidence['apkSha256'] = hashlib.sha256(apk.read_bytes()).hexdigest()
    except Exception:
        return _report(['candidate_manifest_invalid'])
    try:
        # Existing verifier requires a successful apksigner process and exactly
        # one certificate digest. No CLI flag/report can supply a trusted signer.
        evidence['certificateSha256'] = certificate_digest(apk)
    except Exception:
        return _report(['candidate_signature_unverified'])
    return validate_compatibility(evidence, baseline)


class _Parser(argparse.ArgumentParser):
    def error(self, message):
        raise ValueError('arguments_invalid')


def main(argv=None):
    parser = _Parser(description=__doc__)
    parser.add_argument('apk', type=Path)
    try:
        options = parser.parse_args(argv)
    except ValueError:
        result = _report(['arguments_invalid'])
    else:
        result = check(options.apk)
    print(json.dumps(result, sort_keys=True))
    return 0 if result['result'] == 'PASS' else 1


if __name__ == '__main__':
    raise SystemExit(main())
