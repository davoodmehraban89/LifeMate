"""Failure-path tests for write-once synthetic QA artifacts."""

import errno
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

from scripts.personal_recovery.common import RecoveryError
from scripts.personal_recovery.files import publish_new, read_bounded


class RecoveryFilesTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)

    def test_complete_file_private_and_no_temporary_residue(self):
        dest = self.root / "fictional.lgrf"
        publish_new(dest, b"synthetic ciphertext")
        self.assertEqual(dest.read_bytes(), b"synthetic ciphertext")
        self.assertEqual(sorted(p.name for p in self.root.iterdir()), [dest.name])
        if os.name == "posix":
            self.assertEqual(stat.S_IMODE(dest.stat().st_mode), 0o600)

    def test_existing_file_never_overwritten(self):
        dest = self.root / "existing"
        dest.write_bytes(b"keep")
        with self.assertRaises(RecoveryError) as failure:
            publish_new(dest, b"replacement")
        self.assertEqual(failure.exception.code, "destination_exists")
        self.assertEqual(dest.read_bytes(), b"keep")
        self.assertEqual(list(self.root.iterdir()), [dest])

    def test_symlink_never_replaces_or_modifies_target(self):
        target = self.root / "target"
        target.write_bytes(b"keep")
        dest = self.root / "link"
        dest.symlink_to(target)
        with self.assertRaises(RecoveryError):
            publish_new(dest, b"replacement")
        self.assertTrue(dest.is_symlink())
        self.assertEqual(target.read_bytes(), b"keep")

    def test_space_exhaustion_leaves_no_output(self):
        with patch("scripts.personal_recovery.files.os.fsync", side_effect=OSError(errno.ENOSPC, "synthetic")):
            with self.assertRaises(RecoveryError) as failure:
                publish_new(self.root / "new", b"fictional")
        self.assertEqual(failure.exception.code, "file_io_error")
        self.assertEqual(list(self.root.iterdir()), [])

    def test_interruption_before_publish_leaves_no_output(self):
        with patch("scripts.personal_recovery.files.os.fsync", side_effect=KeyboardInterrupt):
            with self.assertRaises(KeyboardInterrupt):
                publish_new(self.root / "new", b"fictional")
        self.assertEqual(list(self.root.iterdir()), [])

    def test_racing_destination_creation_is_preserved(self):
        dest = self.root / "new"
        real_link = os.link

        def raced(source, destination):
            Path(destination).write_bytes(b"other writer")
            return real_link(source, destination)

        with patch("scripts.personal_recovery.files.os.link", side_effect=raced):
            with self.assertRaises(RecoveryError) as failure:
                publish_new(dest, b"replacement")
        self.assertEqual(failure.exception.code, "destination_exists")
        self.assertEqual(dest.read_bytes(), b"other writer")
        self.assertEqual(list(self.root.iterdir()), [dest])

    def test_bounded_read_rejects_oversize_and_symlink(self):
        path = self.root / "input"
        path.write_bytes(b"12345")
        self.assertEqual(read_bounded(path, 5), b"12345")
        with self.assertRaises(RecoveryError):
            read_bounded(path, 4)
        link = self.root / "link"
        link.symlink_to(path)
        with self.assertRaises(RecoveryError):
            read_bounded(link, 5)

    @unittest.skipUnless(hasattr(os, "mkfifo"), "POSIX named-pipe test")
    def test_named_pipe_is_refused_without_waiting_for_writer(self):
        fifo = self.root / "pipe"
        os.mkfifo(fifo)
        code = ("from pathlib import Path; from scripts.personal_recovery.files import read_bounded; "
                "read_bounded(Path(__import__('sys').argv[1]), 10)")
        try:
            result = subprocess.run([sys.executable, "-c", code, str(fifo)], capture_output=True, timeout=2)
        except subprocess.TimeoutExpired:
            self.fail("nonregular input blocked instead of being refused")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b"invalid_input_file", result.stderr)

    def test_swap_after_initial_lstat_cannot_bypass_identity_or_size_checks(self):
        source = self.root / "source"
        source.write_bytes(b"small")
        replacement = self.root / "replacement"
        replacement.write_bytes(b"oversized fictional replacement")
        real_open = os.open

        def swapped(path, flags):
            source.unlink()
            source.symlink_to(replacement)
            return real_open(path, flags)

        with patch("scripts.personal_recovery.files.os.open", side_effect=swapped):
            with self.assertRaises(RecoveryError):
                read_bounded(source, 10)

    def test_regular_file_swap_with_same_size_is_refused(self):
        source = self.root / "source"
        source.write_bytes(b"first")
        replacement = self.root / "replacement"
        replacement.write_bytes(b"other")
        real_open = os.open

        def swapped(path, flags):
            os.replace(replacement, source)
            return real_open(path, flags)

        with patch("scripts.personal_recovery.files.os.open", side_effect=swapped):
            with self.assertRaises(RecoveryError):
                read_bounded(source, 10)

    def test_prefix_refusal_precedes_any_body_read(self):
        source = self.root / "source"
        source.write_bytes(b"f" * 200)
        observed = []

        def reject(prefix):
            observed.append(prefix)
            raise RecoveryError("synthetic_marker_required")

        with self.assertRaises(RecoveryError) as failure:
            read_bounded(source, 300, prefix_validator=reject)
        self.assertEqual(failure.exception.code, "synthetic_marker_required")
        self.assertEqual(observed, [b"f" * 100])

    def test_prefix_gate_uses_unbuffered_stream_without_read_ahead(self):
        source = self.root / "source"
        source.write_bytes(b"f" * 200)
        real_fdopen = os.fdopen
        with patch("scripts.personal_recovery.files.os.fdopen", wraps=real_fdopen) as opening:
            read_bounded(source, 300, prefix_validator=lambda prefix: None)
        self.assertEqual(opening.call_args.kwargs.get("buffering"), 0)


if __name__ == "__main__":
    unittest.main()
