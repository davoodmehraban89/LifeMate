"""Real JDK integration, using only disposable fictional keystores."""

import hashlib
import json
import shutil
import struct
import unittest

from scripts.tests.signing_test_support import request_frame, run_inspector, synthetic_keystores


@unittest.skipUnless(shutil.which("java") and shutil.which("keytool"), "JDK required")
class SigningJavaTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.fixture_context = synthetic_keystores()
        cls.fixtures = cls.fixture_context.__enter__()
        cls.addClassCleanup(cls.fixture_context.__exit__, None, None, None)

    def inspect(self, path=None, *, alias=None, store_password=None, key_password=None):
        fixture = self.fixtures
        path = path or fixture.jks_path
        frame = request_frame(
            path.read_bytes(), alias if alias is not None else fixture.alias,
            store_password if store_password is not None else fixture.store_password,
            key_password if key_password is not None else (
                fixture.store_password if path.suffix == ".p12" else fixture.key_password),
        )
        return self.parse(run_inspector(frame))

    def parse(self, result):
        self.assertIn(result.returncode, (0, 2), "helper must return its fixed protocol status")
        self.assertEqual(result.stderr, b"", "helper must suppress raw diagnostic output")
        try:
            report = json.loads(result.stdout)
        except (ValueError, UnicodeDecodeError):
            self.fail("helper must return a JSON report")
        rendered = result.stdout.decode("utf-8")
        for sensitive in (self.fixtures.alias, self.fixtures.store_password,
                          self.fixtures.key_password, str(self.fixtures.directory)):
            self.assertTrue(sensitive not in rendered, "helper output leaked fixture input")
        return result.returncode, report

    def assert_refused(self, result, reason):
        self.assertEqual(result, (2, {"schemaVersion": 1, "status": "REFUSED", "reason": reason}))

    def test_rsa_jks_proof_repeats_and_source_bytes_stay_unchanged(self):
        path = self.fixtures.jks_path
        before = hashlib.sha256(path.read_bytes()).digest()
        expected = {"schemaVersion": 1, "status": "INSPECTED",
                    "certificateSha256": self.fixtures.fingerprints[path],
                    "debugCertificate": False, "privateKeyProof": True,
                    "certificateCurrentlyValid": True}
        self.assertEqual(self.inspect(path), (0, expected))
        self.assertEqual(self.inspect(path), (0, expected))
        self.assertEqual(hashlib.sha256(path.read_bytes()).digest(), before)

    def test_ec_pkcs12_and_encrypted_copy_have_same_public_facts(self):
        source = self.fixtures.pkcs12_path
        original = source.read_bytes()
        copied = self.fixtures.directory / "encrypted-copy.p12"
        copied.write_bytes(original)
        expected = {"schemaVersion": 1, "status": "INSPECTED",
                    "certificateSha256": self.fixtures.fingerprints[source],
                    "debugCertificate": False, "privateKeyProof": True,
                    "certificateCurrentlyValid": True}
        self.assertEqual(self.inspect(source), (0, expected))
        self.assertEqual(self.inspect(copied), (0, expected))
        self.assertEqual(source.read_bytes(), original)
        self.assertEqual(copied.read_bytes(), original)

    def test_debug_certificate_is_reported(self):
        code, report = self.inspect(self.fixtures.debug_path)
        self.assertEqual(code, 0)
        self.assertIs(report["debugCertificate"], True)

    def test_expired_certificate_is_reported_without_blocking_proof(self):
        path = self.fixtures.directory / "expired.jks"
        self.fixtures.create_key(path, "RSA", expired=True)
        code, report = self.inspect(path)
        self.assertEqual(code, 0)
        self.assertIs(report["certificateCurrentlyValid"], False)
        self.assertIs(report["privateKeyProof"], True)

    def test_wrong_store_password_is_sanitized(self):
        self.assert_refused(self.inspect(store_password="canary-wrong-store"), "keystore_unreadable")

    def test_wrong_key_password_is_sanitized(self):
        self.assert_refused(self.inspect(key_password="canary-wrong-key"), "private_key_unavailable")

    def test_missing_alias_and_certificate_only_entry_refused(self):
        self.assert_refused(self.inspect(alias="canary-missing-alias"), "private_key_unavailable")
        self.assert_refused(self.inspect(self.fixtures.cert_only_path), "private_key_unavailable")

    def test_unsupported_dsa_refused(self):
        self.assert_refused(self.inspect(self.fixtures.dsa_path), "unsupported_key_algorithm")

    def test_unrelated_rsa_certificate_fails_actual_private_key_proof(self):
        path = self.fixtures.mismatched_certificate_store()
        self.assert_refused(self.inspect(path), "key_proof_failed")

    def test_corrupt_keystore_refused_without_echo(self):
        frame = request_frame(b"canary-corrupt-file", self.fixtures.alias,
                              self.fixtures.store_password, self.fixtures.key_password)
        self.assert_refused(self.parse(run_inspector(frame)), "keystore_unreadable")

    def test_malformed_frames_refused_before_loading(self):
        valid = request_frame(self.fixtures.jks_path.read_bytes(), self.fixtures.alias,
                              self.fixtures.store_password, self.fixtures.key_password)
        malformed = [b"", b"BAD!", b"LGKI" + struct.pack(">I", 2 * 1024 * 1024 + 1),
                     valid[:-1], valid + b"trailing-canary",
                     request_frame(b"file", "", "pass", "pass"),
                     request_frame(b"file", "a" * 257, "pass", "pass"),
                     request_frame(b"file", "alias", "", "pass"),
                     request_frame(b"file", "alias", "p" * 4097, "pass"),
                     request_frame(b"file", "alias", "pass", "line\ncanary"),
                     request_frame(b"file", "alias", "nul\0canary", "pass"),
                     b"LGKI" + struct.pack(">I", 1) + b"x" + struct.pack(">I", 1) + b"\xff"
                     + struct.pack(">I", 4) + b"pass" + struct.pack(">I", 4) + b"pass"]
        for frame in malformed:
            with self.subTest(case=malformed.index(frame)):
                self.assert_refused(self.parse(run_inspector(frame)), "invalid_request")


if __name__ == "__main__":
    unittest.main()
