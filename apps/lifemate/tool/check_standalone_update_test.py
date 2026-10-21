"""Delivery policy and verifier-output tests, not real APK/upgrade acceptance."""
import contextlib
import importlib
import io
import json
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from zipfile import ZipFile

try:
    subject = importlib.import_module('check_standalone_update')
except ModuleNotFoundError:
    subject = None

DELIVERED_CERTIFICATE = '4ef990d647fc98ac41113d5dbe7ee476ba80bf95b71b5f219b7863fa95263391'
LATEST_CI_CERTIFICATE = '0e5c979c14a3f293a443aba20e7e54e228ae98d78ed9861a1f0fb3f00ec20889'


class StandaloneUpdateTest(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(subject, 'The fail-closed personal update guard is missing')
        self.baseline = subject.load_baseline()
        self.evidence = {'package': 'ir.lifeguide.app.device', 'versionCode': 10,
                         'certificateSha256': DELIVERED_CERTIFICATE,
                         'apkSha256': 'a' * 64}

    def validate(self, **changes):
        return subject.validate_compatibility(self.evidence | changes, self.baseline)

    def test_committed_baseline_identifies_delivered_artifact_not_verified_device(self):
        self.assertEqual(self.baseline['status'], 'DELIVERED')
        self.assertEqual(self.baseline['versionCode'], 9)
        self.assertEqual(self.baseline['certificateSha256'], DELIVERED_CERTIFICATE)
        self.assertEqual(self.baseline['apkSha256'],
                         'c24ff6e75a987945399b0d96129f5d1a72525fa0270f31b0c481f9780f84db8e')
        self.assertEqual(self.baseline['source']['artifactId'], 12292340083)
        self.assertEqual(self.baseline['installedDeviceVerification'], 'UNVERIFIED')

    def test_matching_signer_higher_code_only_passes_necessary_compatibility(self):
        result = self.validate()
        self.assertEqual(result['result'], 'PASS')
        self.assertEqual(result['reasonCodes'], [])
        self.assertEqual(result['dataPreservation'], 'UNVERIFIED')
        self.assertEqual(result['installedDeviceVerification'], 'UNVERIFIED')
        self.assertEqual(result['delivery'], 'BLOCKED')

    def test_new_random_signer_is_rejected(self):
        result = self.validate(certificateSha256=LATEST_CI_CERTIFICATE)
        self.assertEqual(result['result'], 'BLOCKED')
        self.assertIn('certificate_mismatch', result['reasonCodes'])

    def test_equal_lower_missing_or_noninteger_version_is_rejected(self):
        for value in (9, 8, 0, -1, None, '10', True):
            with self.subTest(version=value):
                result = self.validate(versionCode=value)
                self.assertEqual(result['result'], 'BLOCKED')
                self.assertTrue({'version_code_not_incremented', 'version_code_invalid'} &
                                set(result['reasonCodes']))

    def test_wrong_package_is_rejected_without_echoing_untrusted_value(self):
        result = self.validate(package='PRIVATE_UNTRUSTED_PACKAGE')
        self.assertIn('package_mismatch', result['reasonCodes'])
        self.assertNotIn('PRIVATE_UNTRUSTED_PACKAGE', json.dumps(result))

    def test_missing_or_malformed_certificate_is_rejected(self):
        for value in (None, '', 'a' * 63, ['a' * 64], 'PRIVATE_EXCEPTION'):
            with self.subTest(certificate=value):
                result = self.validate(certificateSha256=value)
                self.assertEqual(result['result'], 'BLOCKED')
                self.assertIn('certificate_invalid', result['reasonCodes'])

    def test_recorded_ci39_evidence_is_blocked_for_both_independent_reasons(self):
        result = self.validate(versionCode=9, certificateSha256=LATEST_CI_CERTIFICATE,
                               apkSha256='7eea3d839179d02d140389da62ba7c2a14894c031f96b6a21a47e742164284b0')
        self.assertEqual(result['result'], 'BLOCKED')
        self.assertEqual(set(result['reasonCodes']),
                         {'certificate_mismatch', 'version_code_not_incremented'})


class ActualInspectionBoundaryTest(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(subject, 'The fail-closed personal update guard is missing')
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.apk = Path(self.directory.name) / 'synthetic-not-a-real-apk.zip'
        with ZipFile(self.apk, 'w') as archive:
            archive.writestr('AndroidManifest.xml', b'synthetic parser boundary')
        self.tags = [('manifest', {'package': 'ir.lifeguide.app.device', 'versionCode': 10})]
        self.signer_output = 'V2 Signer: certificate SHA-256 digest: ' + DELIVERED_CERTIFICATE + '\n'

    def inspect(self, output=None, returncode=0):
        # Only the external verifier/parser boundaries are mocked. This proves
        # rejection behavior and wiring, never a cryptographic APK acceptance.
        with patch.object(subject, 'manifest_tags', return_value=self.tags), \
                patch('test_standalone_android.shutil.which', return_value='/synthetic/apksigner'), \
                patch('test_standalone_android.subprocess.run', return_value=subprocess.CompletedProcess(
                    [], returncode, self.signer_output if output is None else output, 'PRIVATE_STDERR')):
            return subject.check(self.apk)

    def test_actual_probe_reads_apk_manifest_and_verified_digest(self):
        result = self.inspect()
        self.assertEqual(result['result'], 'PASS')
        self.assertEqual(result['dataPreservation'], 'UNVERIFIED')
        self.assertEqual(result['delivery'], 'BLOCKED')
        self.tags[0][1]['versionCode'] = 9
        self.assertIn('version_code_not_incremented', self.inspect()['reasonCodes'])

    def test_unverified_missing_malformed_or_multiple_signer_output_blocks(self):
        for code, output in ((1, self.signer_output), (0, ''),
                             (0, self.signer_output.replace(DELIVERED_CERTIFICATE, 'a' * 63)),
                             (0, self.signer_output + self.signer_output),
                             (0, self.signer_output.replace('certificate', 'public key'))):
            with self.subTest(code=code, output=output):
                result = self.inspect(output, code)
                self.assertEqual(result['result'], 'BLOCKED')
                self.assertEqual(result['reasonCodes'], ['candidate_signature_unverified'])
                self.assertNotIn('PRIVATE_STDERR', json.dumps(result))

    def test_missing_verifier_cannot_use_cli_supplied_certificate(self):
        with patch.object(subject, 'manifest_tags', return_value=self.tags), \
                patch('test_standalone_android.shutil.which', return_value=None), \
                patch.dict('os.environ', {'ANDROID_HOME': '', 'ANDROID_SDK_ROOT': ''}):
            self.assertEqual(subject.check(self.apk)['reasonCodes'], ['candidate_signature_unverified'])
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            code = subject.main([str(self.apk), '--certificate-sha256', DELIVERED_CERTIFICATE])
        self.assertNotEqual(code, 0)
        self.assertEqual(json.loads(output.getvalue())['reasonCodes'], ['arguments_invalid'])

    def test_unreadable_or_ambiguous_manifest_is_sanitized(self):
        for tags in ([], self.tags + self.tags):
            with self.subTest(tags=tags), patch.object(subject, 'manifest_tags', return_value=tags):
                self.assertEqual(subject.check(self.apk)['reasonCodes'], ['candidate_manifest_invalid'])
        self.apk.write_bytes(b'PRIVATE_INVALID_APK_BYTES')
        result = subject.check(self.apk)
        self.assertEqual(result['reasonCodes'], ['candidate_manifest_invalid'])
        self.assertNotIn('PRIVATE_INVALID_APK_BYTES', json.dumps(result))

    def test_unavailable_or_invalid_baseline_blocks_before_candidate_inspection(self):
        for content in (None, '{', '{}'):
            with self.subTest(content=content):
                path = Path(self.directory.name) / 'baseline.json'
                if content is not None:
                    path.write_text(content, encoding='utf-8')
                with patch.object(subject, 'BASELINE_PATH', path):
                    self.assertEqual(subject.check(self.apk)['reasonCodes'], ['delivered_baseline_invalid'])


if __name__ == '__main__':
    unittest.main()
