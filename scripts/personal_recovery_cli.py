#!/usr/bin/env python3
"""Fictional recovery rehearsal. Never use this QA entry point on owner data."""

import argparse
import getpass
import hashlib
import json
from pathlib import Path
import secrets
import sqlite3
import sys
import warnings

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from scripts.personal_recovery.archive import open_archive, seal
from scripts.personal_recovery.common import MAX_PAYLOAD_BYTES, RecoveryError
from scripts.personal_recovery.files import publish_new, read_bounded
from scripts.personal_recovery.snapshot import (
    create_sample_database,
    database_from_snapshot,
    export_fixture,
)


def pack_fixture(source: Path, destination: Path, passphrase: str) -> None:
    # export_fixture refuses an unmarked DB before reading its profile/task data.
    payload = export_fixture(source)
    publish_new(destination, seal(payload, passphrase))


def restore_fixture(source: Path, destination: Path, passphrase: str) -> None:
    raw = read_bounded(source, MAX_PAYLOAD_BYTES + 64)
    payload = open_archive(raw, passphrase)
    database = database_from_snapshot(payload)
    publish_new(destination, database)


def _ask_password(confirm: bool) -> str:
    if not sys.stdin.isatty():
        raise RecoveryError("interactive_terminal_required")
    # Refuse getpass's echoing fallback if a hidden terminal is unavailable.
    with warnings.catch_warnings():
        warnings.simplefilter("error", getpass.GetPassWarning)
        try:
            value = getpass.getpass("Synthetic QA passphrase (hidden): ")
            if confirm and value != getpass.getpass("Repeat passphrase (hidden): "):
                raise RecoveryError("passphrase_confirmation_mismatch")
            return value
        except (getpass.GetPassWarning, EOFError):
            raise RecoveryError("interactive_terminal_required") from None


def _expect_refusal(operation, destination: Path) -> None:
    try:
        operation()
    except RecoveryError:
        if destination.exists():
            raise RecoveryError("demo_failed") from None
        return
    raise RecoveryError("demo_failed")


def demo(directory: Path) -> dict:
    """Exercise real disk SQLite, encryption and reopen with process-local secret."""
    directory = Path(directory)
    if directory.is_symlink():
        raise RecoveryError("invalid_demo_directory")
    if directory.exists():
        if not directory.is_dir() or any(directory.iterdir()):
            raise RecoveryError("demo_directory_not_empty")
    else:
        directory.mkdir(mode=0o700)
    source = directory / "synthetic-source.sqlite"
    archive = directory / "synthetic-transfer.lgrf"
    restored = directory / "synthetic-restored.sqlite"
    publish_new(source, create_sample_database())
    original_hash = hashlib.sha256(source.read_bytes()).hexdigest()
    before = export_fixture(source)
    passphrase = secrets.token_urlsafe(32)
    pack_fixture(source, archive, passphrase)
    invalid_destination = directory / "must-not-exist.sqlite"
    _expect_refusal(lambda: restore_fixture(archive, invalid_destination, secrets.token_urlsafe(32)), invalid_destination)
    corrupted = bytearray(read_bounded(archive, MAX_PAYLOAD_BYTES + 64))
    corrupted[-1] ^= 1
    _expect_refusal(lambda: open_archive(bytes(corrupted), passphrase), invalid_destination)
    restore_fixture(archive, restored, passphrase)
    if export_fixture(restored) != before:
        raise RecoveryError("demo_failed")
    if hashlib.sha256(source.read_bytes()).hexdigest() != original_hash:
        raise RecoveryError("demo_failed")
    restored_hash = hashlib.sha256(restored.read_bytes()).hexdigest()
    try:
        restore_fixture(archive, restored, passphrase)
    except RecoveryError as failure:
        if failure.code != "destination_exists":
            raise RecoveryError("demo_failed") from None
    else:
        raise RecoveryError("demo_failed")
    if hashlib.sha256(restored.read_bytes()).hexdigest() != restored_hash:
        raise RecoveryError("demo_failed")
    with sqlite3.connect(f"{restored.resolve().as_uri()}?mode=ro", uri=True) as db:
        if db.execute("PRAGMA quick_check").fetchone() != ("ok",):
            raise RecoveryError("demo_failed")
        if db.execute("PRAGMA foreign_key_check").fetchall():
            raise RecoveryError("demo_failed")
        tables = ("local_profiles", "local_plans", "local_weekly_slots", "local_occurrences")
        counts = {table: db.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0] for table in tables}
        if any(count == 0 for count in counts.values()):
            raise RecoveryError("demo_failed")
    return {
        "schemaVersion": 1,
        "result": "PASS",
        "syntheticOnly": True,
        "scope": "host SQLite v1 encrypted recovery rehearsal; no device or owner data",
        "counts": counts,
        "canonicalSnapshotSha256": hashlib.sha256(before).hexdigest(),
        "checks": {
            "fullFieldRoundTripAfterCloseReopen": "PASS",
            "sourceBytesUnchanged": "PASS",
            "independentSqlIntegrityAndCounts": "PASS",
            "invalidCredentialRejectedBeforeOutput": "PASS",
            "tamperingRejected": "PASS",
            "repeatRestoreRefusedWithoutOverwrite": "PASS",
        },
        "limitations": {
            "androidSideBySide": "UNVERIFIED",
            "subsequentSignedAppUpgrade": "UNVERIFIED",
            "physicalDeviceOrOwnerData": "UNVERIFIED",
            "WindowsAndUsb": "UNVERIFIED",
            "powerLossDurability": "UNVERIFIED",
            "ownerSigningKey": "UNVERIFIED",
        },
    }


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subcommands = parser.add_subparsers(dest="command", required=True)
    for name in ("create-fixture", "pack", "restore-fixture", "demo"):
        command = subcommands.add_parser(name)
        command.add_argument("--acknowledge-synthetic-only", action="store_true")
        if name == "demo":
            command.add_argument("--directory", type=Path, required=True)
        else:
            command.add_argument("--output", type=Path, required=True)
            if name != "create-fixture":
                command.add_argument("--source", type=Path, required=True)
    args = parser.parse_args(argv)
    try:
        if not args.acknowledge_synthetic_only:
            raise RecoveryError("synthetic_acknowledgement_required")
        if args.command == "demo":
            report = demo(args.directory)
        else:
            if args.command == "create-fixture":
                publish_new(args.output, create_sample_database())
            elif args.command == "pack":
                pack_fixture(args.source, args.output, _ask_password(confirm=True))
            else:
                restore_fixture(args.source, args.output, _ask_password(confirm=False))
            report = {"status": "PASS", "syntheticOnly": True}
        print(json.dumps(report, ensure_ascii=True, sort_keys=True))
        return 0
    except RecoveryError as failure:
        print(json.dumps({"status": "REFUSED", "reason": failure.code, "syntheticOnly": True}))
        return 2
    except (OSError, sqlite3.Error):
        print(json.dumps({"status": "REFUSED", "reason": "file_io_error", "syntheticOnly": True}))
        return 2
    except KeyboardInterrupt:
        print(json.dumps({"status": "CANCELLED", "reason": "interrupted", "syntheticOnly": True}))
        return 130


if __name__ == "__main__":
    raise SystemExit(main())
