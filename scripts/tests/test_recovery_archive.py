"""Synthetic-only tests of the versioned, authenticated recovery envelope."""

import importlib
import unittest
from unittest.mock import patch

from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.scrypt import Scrypt

from scripts.personal_recovery.common import MAX_PAYLOAD_BYTES, RecoveryError


MAGIC = b"LGRF\x01"
HEADER_SIZE = 33
TAG_SIZE = 16
PASSWORD = "fictional recovery phrase"


class RecoveryArchiveTests(unittest.TestCase):
    def setUp(self):
        try:
            self.archive = importlib.import_module("scripts.personal_recovery.archive")
        except ModuleNotFoundError:
            self.fail("Recovery archive implementation is missing")

    def assert_refused_before_kdf(self, operation, value, password, code):
        with patch.object(self.archive, "Scrypt") as kdf:
            with self.assertRaises(RecoveryError) as caught:
                operation(value, password)
            self.assertEqual(caught.exception.code, code)
            self.assertEqual(str(caught.exception), code)
            kdf.assert_not_called()

    def test_round_trip_arbitrary_bytes(self):
        payload = b"fictional-only\x00\xff\x80" * 100
        encrypted = self.archive.seal(payload, PASSWORD)
        self.assertEqual(self.archive.open_archive(encrypted, PASSWORD), payload)
        self.assertNotIn(payload, encrypted)

    def test_empty_payload_round_trip(self):
        encrypted = self.archive.seal(b"", PASSWORD)
        self.assertEqual(len(encrypted), HEADER_SIZE + TAG_SIZE)
        self.assertEqual(self.archive.open_archive(encrypted, PASSWORD), b"")

    def test_format_and_fixed_crypto_parameters_with_independent_decryption(self):
        payload = b"fictional independent compatibility fixture"
        encrypted = self.archive.seal(payload, PASSWORD)
        self.assertEqual(encrypted[:5], MAGIC)
        self.assertEqual(len(encrypted), len(payload) + HEADER_SIZE + TAG_SIZE)
        key = Scrypt(salt=encrypted[5:21], length=32, n=32768, r=8, p=1).derive(
            PASSWORD.encode("utf-8")
        )
        self.assertEqual(
            AESGCM(key).decrypt(encrypted[21:33], encrypted[33:], encrypted[:33]),
            payload,
        )

    def test_open_independently_constructed_archive(self):
        salt = bytes(range(16))
        nonce = bytes(range(12))
        header = MAGIC + salt + nonce
        key = Scrypt(salt=salt, length=32, n=32768, r=8, p=1).derive(
            PASSWORD.encode("utf-8")
        )
        payload = b"fictional external envelope"
        encrypted = header + AESGCM(key).encrypt(nonce, payload, header)
        self.assertEqual(self.archive.open_archive(encrypted, PASSWORD), payload)

    def test_every_seal_uses_new_salt_and_nonce(self):
        first = self.archive.seal(b"fictional", PASSWORD)
        second = self.archive.seal(b"fictional", PASSWORD)
        self.assertNotEqual(first[5:21], second[5:21])
        self.assertNotEqual(first[21:33], second[21:33])
        self.assertNotEqual(first, second)

    def test_wrong_password_and_tampering_share_safe_authentication_error(self):
        encrypted = self.archive.seal(b"fictional integrity fixture", PASSWORD)
        cases = [(encrypted, "another fictional password")]
        for index in (5, 20, 21, 32, 33, len(encrypted) - 1):
            changed = bytearray(encrypted)
            changed[index] ^= 1
            cases.append((bytes(changed), PASSWORD))
        cases.append((encrypted + b"\x00", PASSWORD))
        cases.append((encrypted[:-1], PASSWORD))
        for changed, password in cases:
            with self.subTest(case=len(changed), password_matches=password == PASSWORD):
                with self.assertRaises(RecoveryError) as caught:
                    self.archive.open_archive(changed, password)
                self.assertEqual(caught.exception.code, "archive_authentication_failed")
                self.assertEqual(str(caught.exception), "archive_authentication_failed")
                self.assertIsNone(caught.exception.__cause__)
                self.assertTrue(caught.exception.__suppress_context__)

    def test_header_magic_and_version_rejected_before_kdf(self):
        valid_size = MAGIC + bytes(16 + 12 + TAG_SIZE)
        for index in range(5):
            changed = bytearray(valid_size)
            changed[index] ^= 1
            with self.subTest(index=index):
                self.assert_refused_before_kdf(
                    self.archive.open_archive, bytes(changed), PASSWORD, "invalid_archive"
                )

    def test_truncated_archive_rejected_before_kdf(self):
        for size in (0, 4, 5, 20, 21, 32, 33, 48):
            with self.subTest(size=size):
                self.assert_refused_before_kdf(
                    self.archive.open_archive, (MAGIC + bytes(44))[:size],
                    PASSWORD, "invalid_archive"
                )

    def test_oversized_archive_rejected_before_kdf(self):
        encrypted = MAGIC + bytes(MAX_PAYLOAD_BYTES + HEADER_SIZE + TAG_SIZE - 4)
        self.assertEqual(len(encrypted), MAX_PAYLOAD_BYTES + HEADER_SIZE + TAG_SIZE + 1)
        self.assert_refused_before_kdf(
            self.archive.open_archive, encrypted, PASSWORD, "invalid_archive"
        )

    def test_oversized_payload_rejected_before_kdf(self):
        self.assert_refused_before_kdf(
            self.archive.seal, bytes(MAX_PAYLOAD_BYTES + 1), PASSWORD, "invalid_payload"
        )

    def test_exact_payload_boundary_round_trip(self):
        payload = b"f" * MAX_PAYLOAD_BYTES
        encrypted = self.archive.seal(payload, PASSWORD)
        self.assertEqual(len(encrypted), MAX_PAYLOAD_BYTES + HEADER_SIZE + TAG_SIZE)
        self.assertEqual(self.archive.open_archive(encrypted, PASSWORD), payload)

    def test_invalid_passphrase_rejected_before_kdf_in_both_directions(self):
        encrypted = MAGIC + bytes(16 + 12 + TAG_SIZE)
        for password in ("", "x" * 11, "x" * 1025, "\u0628" * 513, "x" * 12 + "\ud800", None, b"fictional password"):
            for operation, value in ((self.archive.seal, b"fixture"), (self.archive.open_archive, encrypted)):
                with self.subTest(operation=operation.__name__, password_type=type(password).__name__):
                    self.assert_refused_before_kdf(operation, value, password, "invalid_passphrase")

    def test_minimum_character_and_maximum_utf8_passphrase_boundaries(self):
        for password in ("x" * 12, "x" * 1024, "\u0628" * 512):
            with self.subTest(characters=len(password)):
                encrypted = self.archive.seal(b"fictional boundary", password)
                self.assertEqual(self.archive.open_archive(encrypted, password), b"fictional boundary")

    def test_unicode_passphrase_is_used_without_normalization(self):
        composed = "fictional-\u00e9-phrase"
        decomposed = "fictional-e\u0301-phrase"
        encrypted = self.archive.seal("ساختگی".encode("utf-8"), composed)
        self.assertEqual(self.archive.open_archive(encrypted, composed), "ساختگی".encode("utf-8"))
        with self.assertRaises(RecoveryError) as caught:
            self.archive.open_archive(encrypted, decomposed)
        self.assertEqual(caught.exception.code, "archive_authentication_failed")

    def test_character_count_not_utf8_length_controls_passphrase_minimum(self):
        self.assert_refused_before_kdf(
            self.archive.seal, b"fictional", "\u0628" * 6, "invalid_passphrase"
        )

    def test_nonbytes_payloads_and_archives_are_safely_rejected_before_kdf(self):
        for value in (None, "fictional", bytearray(b"fictional"), memoryview(b"fictional"), 4):
            with self.subTest(value_type=type(value).__name__):
                self.assert_refused_before_kdf(self.archive.seal, value, PASSWORD, "invalid_payload")
                self.assert_refused_before_kdf(self.archive.open_archive, value, PASSWORD, "invalid_archive")


if __name__ == "__main__":
    unittest.main()
