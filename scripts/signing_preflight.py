#!/usr/bin/env python3
"""Read-only local signing preparation. Never signs, exports or delivers an APK."""

import argparse
import getpass
import json
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys
import warnings

ROOT = Path(__file__).resolve().parents[1]
if __package__ in (None, ""):
    sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "apps/lifemate/tool"))

from check_standalone_update import load_baseline
from scripts.personal_recovery.common import RecoveryError
from scripts.personal_recovery.files import read_bounded

MAX_KEYSTORE_BYTES = 2 * 1024 * 1024
HELPER = ROOT / "scripts/java/LifeGuideKeyInspector.java"
REFUSALS = frozenset({"invalid_request", "keystore_unreadable", "private_key_unavailable",
                      "unsupported_key_algorithm", "key_proof_failed", "inspection_failed"})


class PreflightError(Exception):
    def __init__(self, code):
        self.code = code
        super().__init__(code)


def _java_environment():
    # Do not inherit arbitrary credentials or JVM agent/options injection.
    allowed = {"PATH", "SYSTEMROOT", "WINDIR", "TEMP", "TMP", "TMPDIR", "LANG", "LC_ALL"}
    return {key: value for key, value in os.environ.items() if key.upper() in allowed}


def _java_available():
    java = shutil.which("java")
    if java is None:
        return False
    try:
        process = subprocess.run([java, "-version"], stdin=subprocess.DEVNULL,
                                 stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                 env=_java_environment(), timeout=10, check=False)
        if process.returncode != 0 or len(process.stdout) > 4096:
            return False
        version = re.search(rb'\bversion\s+"(\d+)(?:\.[^"\r\n]*)?"', process.stdout)
        if version is None or int(version[1]) < 17:
            return False
        modules = subprocess.run([java, "--list-modules"], stdin=subprocess.DEVNULL,
                                 stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                 env=_java_environment(), timeout=10, check=False)
        if (modules.returncode != 0 or len(modules.stdout) > 32768
                or not any(line.startswith(b"jdk.compiler@") for line in modules.stdout.splitlines())):
            return False
        # A stripped runtime can list jdk.compiler yet lack source17 support.
        # Compile the fixed helper with empty input: no key/alias/password/file.
        probe = subprocess.run([java, "-Xmx96m", "--source", "17", str(HELPER)],
                               input=b"", stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                               timeout=30, env=_java_environment(), check=False)
        try:
            _helper_result(probe)
        except PreflightError as failure:
            return failure.code == "invalid_request"
        return False
    except (OSError, subprocess.TimeoutExpired, ValueError):
        return False


def _baseline():
    try:
        return load_baseline()
    except Exception:
        raise PreflightError("delivered_baseline_invalid") from None


def _boundary_report():
    return {"schemaVersion": 1, "delivery": "BLOCKED", "releaseReadiness": "UNVERIFIED",
            "installedDeviceVerification": "UNVERIFIED", "dataPreservation": "UNVERIFIED"}


def _inspection_report(facts, baseline):
    match = facts["certificateSha256"] == baseline["certificateSha256"]
    reasons = []
    if not match:
        reasons.append("different_from_delivered_signer")
    if facts["debugCertificate"]:
        reasons.append("debug_certificate_not_for_release")
    return dict(_boundary_report(), **facts, signerCompatibility="MATCH" if match else "DIFFERENT",
                reasonCodes=reasons, keyInspection="VERIFIED_LOCAL_CHALLENGE")


def _encode(value, limit):
    if not isinstance(value, str) or not value or any(c in value for c in "\x00\r\n"):
        raise PreflightError("invalid_inspection_input")
    try:
        raw = value.encode("utf-8", errors="strict")
    except UnicodeError:
        raise PreflightError("invalid_inspection_input") from None
    if len(raw) > limit:
        raise PreflightError("invalid_inspection_input")
    return raw


def _no_duplicate_keys(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate_json_key")
        result[key] = value
    return result


def _helper_result(process):
    try:
        if not isinstance(process.stdout, bytes) or len(process.stdout) > 4096:
            raise ValueError("invalid_output")
        value = json.loads(process.stdout, object_pairs_hook=_no_duplicate_keys)
        if not isinstance(value, dict) or type(value.get("schemaVersion")) is not int or value["schemaVersion"] != 1:
            raise ValueError("invalid_schema")
        if (process.returncode == 2 and set(value) == {"schemaVersion", "status", "reason"}
                and value["status"] == "REFUSED" and value["reason"] in REFUSALS):
            raise PreflightError(value["reason"])
        if (process.returncode != 0 or set(value) != {"schemaVersion", "status", "certificateSha256",
                "debugCertificate", "privateKeyProof", "certificateCurrentlyValid"}
                or value["status"] != "INSPECTED"
                or not isinstance(value["certificateSha256"], str)
                or re.fullmatch(r"[0-9a-f]{64}", value["certificateSha256"]) is None
                or type(value["privateKeyProof"]) is not bool or not value["privateKeyProof"]
                or type(value["debugCertificate"]) is not bool
                or type(value["certificateCurrentlyValid"]) is not bool):
            raise ValueError("invalid_facts")
        return value
    except PreflightError:
        raise
    except (ValueError, TypeError, KeyError, UnicodeError):
        raise PreflightError("inspector_invalid_response") from None


def _run_inspector(encrypted, alias, store_password, key_password):
    fields = (encrypted, _encode(alias, 256), _encode(store_password, 4096), _encode(key_password, 4096))
    if not isinstance(encrypted, bytes) or not encrypted or len(encrypted) > MAX_KEYSTORE_BYTES:
        raise PreflightError("invalid_inspection_input")
    java = shutil.which("java")
    if java is None:
        raise PreflightError("jdk17_required")
    frame = b"LGKI" + b"".join(struct.pack(">I", len(field)) + field for field in fields)
    try:
        process = subprocess.run([java, "-Xmx96m", "--source", "17", str(HELPER)],
                                 input=frame, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                 timeout=30, env=_java_environment(), check=False)
    except subprocess.TimeoutExpired:
        raise PreflightError("inspector_timeout") from None
    except OSError:
        raise PreflightError("inspector_unavailable") from None
    return _helper_result(process)


def inspect_key(path, alias, store_password, key_password):
    """Internal read-only API. CLI additionally requires acknowledgement and TTY.

    Callers must supply only an explicitly chosen local key, never auto-discover
    owner files. Tests use this API with process-local synthetic fixtures only.
    Python cannot guarantee zeroization of immutable strings/bytes in memory.
    """
    _encode(alias, 256)
    _encode(store_password, 4096)
    _encode(key_password, 4096)
    baseline = _baseline()
    try:
        encrypted = read_bounded(Path(path), MAX_KEYSTORE_BYTES)
    except RecoveryError as failure:
        raise PreflightError(failure.code) from None
    except (OSError, ValueError):
        raise PreflightError("invalid_input_file") from None
    return _inspection_report(_run_inspector(encrypted, alias, store_password, key_password), baseline)


def _passwords():
    if not sys.stdin.isatty():
        raise PreflightError("interactive_terminal_required")
    with warnings.catch_warnings():
        warnings.simplefilter("error", getpass.GetPassWarning)
        try:
            store = getpass.getpass("Local keystore password (hidden): ")
            key = getpass.getpass("Local key password (Enter = same; hidden): ")
        except (getpass.GetPassWarning, EOFError):
            raise PreflightError("interactive_terminal_required") from None
    return store, key or store


class _Parser(argparse.ArgumentParser):
    def error(self, message):
        # argparse's default interpolates unknown argument values into stderr.
        raise PreflightError("arguments_invalid")


def main(argv=None):
    parser = _Parser(description=__doc__, allow_abbrev=False)
    commands = parser.add_subparsers(dest="command", parser_class=_Parser)
    commands.add_parser("check", allow_abbrev=False,
                        help="Check public baseline and JDK only; no key access")
    inspect = commands.add_parser("inspect", allow_abbrev=False,
                                  help="Explicit owner-local read-only inspection; hidden passwords")
    inspect.add_argument("--keystore", type=Path, required=True)
    inspect.add_argument("--alias", required=True)
    inspect.add_argument("--acknowledge-owner-local-inspection", action="store_true")
    try:
        args = parser.parse_args(argv)
        if args.command == "inspect":
            if not args.acknowledge_owner_local_inspection:
                raise PreflightError("owner_local_acknowledgement_required")
            if not sys.stdin.isatty():
                raise PreflightError("interactive_terminal_required")
            if not _java_available():
                raise PreflightError("jdk17_required")
            store, key = _passwords()
            report = inspect_key(args.keystore, args.alias, store, key)
        else:
            baseline = _baseline()
            if not _java_available():
                raise PreflightError("jdk17_required")
            report = dict(_boundary_report(), status="CHECKED", java17OrNewer=True,
                          keyInspection="UNVERIFIED", baselineCertificateSha256=baseline["certificateSha256"],
                          baselineVersionCode=baseline["versionCode"])
        print(json.dumps(report, sort_keys=True))
        return 0
    except PreflightError as failure:
        print(json.dumps(dict(_boundary_report(), status="REFUSED", reason=failure.code), sort_keys=True))
        return 2
    except KeyboardInterrupt:
        print(json.dumps(dict(_boundary_report(), status="CANCELLED", reason="interrupted"), sort_keys=True))
        return 130


if __name__ == "__main__":
    raise SystemExit(main())
