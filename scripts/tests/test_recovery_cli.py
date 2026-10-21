"""End-to-end host checks with fictional data and independently opened SQLite."""

from contextlib import redirect_stdout
import hashlib
import io
import json
from pathlib import Path
import sqlite3
import tempfile
import unittest
from unittest.mock import patch

from scripts.personal_recovery.common import RecoveryError
from scripts.personal_recovery.snapshot import create_sample_database, export_fixture
from scripts.personal_recovery_cli import demo, main, pack_fixture, restore_fixture


class RecoveryCliTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        # Deliberately fictional test passphrase, not an owner credential.
        self.password = "fictional test phrase only"

    def fixture(self):
        source = self.root / "source.sqlite"
        source.write_bytes(create_sample_database())
        return source

    def test_real_files_close_reopen_full_snapshot_matches_without_source_changes(self):
        source = self.fixture()
        source_hash = hashlib.sha256(source.read_bytes()).hexdigest()
        archive = self.root / "transfer.lgrf"
        restored = self.root / "restored.sqlite"
        expected = export_fixture(source)
        pack_fixture(source, archive, self.password)
        restore_fixture(archive, restored, self.password)
        self.assertEqual(export_fixture(restored), expected)
        self.assertEqual(hashlib.sha256(source.read_bytes()).hexdigest(), source_hash)
        self.assertFalse(source.read_bytes()[:64] in archive.read_bytes())
        with sqlite3.connect(f"{restored.as_uri()}?mode=ro", uri=True) as db:
            self.assertEqual(db.execute("PRAGMA quick_check").fetchone(), ("ok",))
            self.assertEqual(db.execute("PRAGMA foreign_key_check").fetchall(), [])
            for table in ("local_profiles", "local_plans", "local_weekly_slots", "local_occurrences"):
                self.assertGreater(db.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0], 0)

    def test_wrong_password_tamper_and_repeat_never_modify_or_create_destination(self):
        source = self.fixture()
        archive = self.root / "transfer.lgrf"
        destination = self.root / "restored.sqlite"
        pack_fixture(source, archive, self.password)
        with self.assertRaises(RecoveryError):
            restore_fixture(archive, destination, "incorrect fictional phrase")
        self.assertFalse(destination.exists())
        raw = bytearray(archive.read_bytes())
        raw[-1] ^= 1
        corrupted = self.root / "corrupted.lgrf"
        corrupted.write_bytes(raw)
        with self.assertRaises(RecoveryError):
            restore_fixture(corrupted, destination, self.password)
        self.assertFalse(destination.exists())
        restore_fixture(archive, destination, self.password)
        previous = destination.read_bytes()
        with self.assertRaises(RecoveryError) as refusal:
            restore_fixture(archive, destination, self.password)
        self.assertEqual(refusal.exception.code, "destination_exists")
        self.assertEqual(destination.read_bytes(), previous)

    def test_unmarked_source_refused_without_archive(self):
        source = self.fixture()
        with sqlite3.connect(source) as db:
            db.execute("PRAGMA application_id=0")
        destination = self.root / "refused.lgrf"
        with self.assertRaises(RecoveryError):
            pack_fixture(source, destination, self.password)
        self.assertFalse(destination.exists())

    def test_missing_acknowledgement_cannot_create_any_files(self):
        output = io.StringIO()
        with redirect_stdout(output):
            code = main(["create-fixture", "--output", str(self.root / "blocked.sqlite")])
        self.assertEqual(code, 2)
        self.assertEqual(json.loads(output.getvalue())["reason"], "synthetic_acknowledgement_required")
        self.assertEqual(list(self.root.iterdir()), [])

    def test_noninteractive_pack_refuses_without_reading_passphrase(self):
        source = self.fixture()
        output = io.StringIO()
        with patch("sys.stdin.isatty", return_value=False), patch("getpass.getpass") as prompt, redirect_stdout(output):
            code = main(["pack", "--source", str(source), "--output", str(self.root / "blocked"), "--acknowledge-synthetic-only"])
        self.assertEqual(code, 2)
        self.assertEqual(json.loads(output.getvalue())["reason"], "interactive_terminal_required")
        prompt.assert_not_called()
        self.assertFalse((self.root / "blocked").exists())

    def test_failure_output_contains_only_reason_not_payload_paths_or_password(self):
        output = io.StringIO()
        with patch("scripts.personal_recovery_cli._ask_password", return_value=self.password), redirect_stdout(output):
            code = main(["pack", "--source", str(self.root / "missing"), "--output", str(self.root / "none"), "--acknowledge-synthetic-only"])
        self.assertEqual(code, 2)
        report = json.loads(output.getvalue())
        self.assertEqual(set(report), {"status", "reason", "syntheticOnly"})
        self.assertNotIn(str(self.root), output.getvalue())
        self.assertNotIn(self.password, output.getvalue())

    def test_demo_receipt_is_sanitized_and_records_independent_checks(self):
        directory = self.root / "demo"
        receipt = demo(directory)
        self.assertEqual(receipt["result"], "PASS")
        self.assertTrue(receipt["syntheticOnly"])
        self.assertTrue(all(value == "PASS" for value in receipt["checks"].values()))
        self.assertEqual(receipt["limitations"]["androidSideBySide"], "UNVERIFIED")
        self.assertNotIn("display_name", json.dumps(receipt))
        self.assertNotIn("password", json.dumps(receipt).lower())
        with self.assertRaises(RecoveryError):
            demo(directory)


if __name__ == "__main__":
    unittest.main()
