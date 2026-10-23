"""Read-only signing preparation; all values and files are synthetic."""

from contextlib import redirect_stdout
import getpass
import io
import json
import os
from pathlib import Path
import struct
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from scripts import signing_preflight as tool


FACTS = {"schemaVersion": 1, "status": "INSPECTED", "certificateSha256": "a" * 64,
         "debugCertificate": False, "privateKeyProof": True,
         "certificateCurrentlyValid": True}
CANARY = "FICTIONAL_SECRET_NEVER_PRINT"


class SigningPreflightTest(unittest.TestCase):
    def call(self, arguments, **patches):
        output = io.StringIO()
        with redirect_stdout(output):
            result = tool.main(arguments)
        return result, json.loads(output.getvalue())

    def test_default_never_reads_key_or_runs_key_inspection(self):
        with patch.object(tool, "_java_available", return_value=True), \
                patch.object(tool, "read_bounded", side_effect=AssertionError("private IO")), \
                patch.object(tool, "_run_inspector", side_effect=AssertionError("inspection")):
            code, report = self.call([])
        self.assertEqual(code, 0)
        self.assertEqual(report["status"], "CHECKED")
        self.assertEqual(report["keyInspection"], "UNVERIFIED")
        self.assertEqual(report["delivery"], "BLOCKED")

    def test_missing_java_is_refused(self):
        with patch.object(tool, "_java_available", return_value=False):
            code, report = self.call(["check"])
        self.assertEqual(code, 2)
        self.assertEqual(report["reason"], "jdk17_required")

    def test_source_launcher_checks_compiler_module_without_javac_executable(self):
        for modules, expected in ((b"java.base@21\njdk.compiler@21\n", True),
                                   (b"java.base@21\n", False)):
            with self.subTest(expected=expected), \
                    patch.object(tool.shutil, "which", side_effect=lambda name: "/synthetic/java" if name == "java" else None), \
                    patch.object(tool.subprocess, "run", side_effect=[
                        subprocess.CompletedProcess([], 0, b'openjdk version "21.0.1"\n'),
                        subprocess.CompletedProcess([], 0, modules),
                        subprocess.CompletedProcess([], 2, b'{"schemaVersion":1,"status":"REFUSED","reason":"invalid_request"}')]):
                self.assertEqual(tool._java_available(), expected)

    def test_compiler_module_without_source17_support_is_refused(self):
        with patch.object(tool.shutil, "which", return_value="/synthetic/java"), \
                patch.object(tool.subprocess, "run", side_effect=[
                    subprocess.CompletedProcess([], 0, b'openjdk version "21.0.1"\n'),
                    subprocess.CompletedProcess([], 0, b'jdk.compiler@21\n'),
                    subprocess.CompletedProcess([], 1, b'unsupported source release')]):
            self.assertFalse(tool._java_available())

    def test_acknowledgement_before_private_io_or_prompt(self):
        with patch.object(tool, "read_bounded", side_effect=AssertionError("private IO")), \
                patch.object(tool, "_passwords", side_effect=AssertionError("prompt")):
            code, report = self.call(["inspect", "--keystore", CANARY, "--alias", CANARY])
        self.assertEqual(code, 2)
        self.assertEqual(report["reason"], "owner_local_acknowledgement_required")
        self.assertNotIn(CANARY, json.dumps(report))

    def test_noninteractive_before_private_io_or_helper(self):
        with patch.object(tool.sys.stdin, "isatty", return_value=False), \
                patch.object(tool, "read_bounded", side_effect=AssertionError("private IO")), \
                patch.object(tool, "_run_inspector", side_effect=AssertionError("helper")):
            code, report = self.call(["inspect", "--keystore", CANARY, "--alias", CANARY,
                                      "--acknowledge-owner-local-inspection"])
        self.assertEqual(code, 2)
        self.assertEqual(report["reason"], "interactive_terminal_required")

    def test_getpass_echo_fallback_refused(self):
        with patch.object(tool.sys.stdin, "isatty", return_value=True), \
                patch.object(tool.getpass, "getpass", side_effect=getpass.GetPassWarning(CANARY)):
            with self.assertRaises(tool.PreflightError) as failure:
                tool._passwords()
        self.assertEqual(failure.exception.code, "interactive_terminal_required")

    def test_hidden_password_and_same_key_password(self):
        with patch.object(tool.sys.stdin, "isatty", return_value=True), \
                patch.object(tool.getpass, "getpass", side_effect=[CANARY, ""]):
            self.assertEqual(tool._passwords(), (CANARY, CANARY))

    def test_separate_hidden_key_password(self):
        with patch.object(tool.sys.stdin, "isatty", return_value=True), \
                patch.object(tool.getpass, "getpass", side_effect=[CANARY, CANARY + "2"]):
            self.assertEqual(tool._passwords(), (CANARY, CANARY + "2"))

    def test_invalid_arguments_never_echo_values(self):
        for arguments in (["--password", CANARY], ["inspect", "--bad", CANARY],
                          ["generate-key", CANARY], ["--baseline", CANARY],
                          ["inspect", "--alias"], ["--acknowledge-owner", CANARY]):
            with self.subTest(arguments=arguments):
                code, report = self.call(arguments)
                self.assertEqual(code, 2)
                self.assertEqual(report["reason"], "arguments_invalid")
                self.assertNotIn(CANARY, json.dumps(report))

    def test_baseline_invalid_is_sanitized(self):
        with patch.object(tool, "load_baseline", side_effect=ValueError(CANARY)):
            code, report = self.call([])
        self.assertEqual(code, 2)
        self.assertEqual(report["reason"], "delivered_baseline_invalid")

    def test_fixture_inspection_reports_facts_but_never_delivery(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "synthetic-only.jks"
            source.write_bytes(b"fictional-encrypted-key-placeholder")
            before = source.read_bytes()
            with patch.object(tool, "_run_inspector", return_value=FACTS):
                report = tool.inspect_key(source, CANARY, CANARY, CANARY)
            self.assertEqual(source.read_bytes(), before)
        self.assertEqual(report["status"], "INSPECTED")
        self.assertEqual(report["signerCompatibility"], "DIFFERENT")
        self.assertTrue(report["privateKeyProof"])
        for key, value in {"delivery": "BLOCKED", "releaseReadiness": "UNVERIFIED",
                           "dataPreservation": "UNVERIFIED",
                           "installedDeviceVerification": "UNVERIFIED"}.items():
            self.assertEqual(report[key], value)
        self.assertNotIn(CANARY, json.dumps(report))

    def test_matching_debug_signer_does_not_unlock_release(self):
        baseline = tool.load_baseline()
        facts = dict(FACTS, certificateSha256=baseline["certificateSha256"], debugCertificate=True)
        report = tool._inspection_report(facts, baseline)
        self.assertEqual(report["signerCompatibility"], "MATCH")
        self.assertIn("debug_certificate_not_for_release", report["reasonCodes"])
        self.assertEqual(report["delivery"], "BLOCKED")
        self.assertEqual(report["releaseReadiness"], "UNVERIFIED")

    def test_alias_and_password_bounds_checked_before_file_io(self):
        for alias, store, key in (("", CANARY, CANARY), ("x" * 257, CANARY, CANARY),
                                   (CANARY, "", CANARY), (CANARY, "x" * 4097, CANARY),
                                   (CANARY, CANARY, "\x00"), ("x\n", CANARY, CANARY)):
            with self.subTest(aliasLength=len(alias), storeLength=len(store)), \
                    patch.object(tool, "read_bounded", side_effect=AssertionError("file IO")):
                with self.assertRaises(tool.PreflightError):
                    tool.inspect_key(Path("unused"), alias, store, key)

    def test_missing_directory_and_oversized_files_refused(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            oversized = root / "large"
            with oversized.open("wb") as stream:
                stream.truncate(tool.MAX_KEYSTORE_BYTES + 1)
            for path in (root / "missing", root, oversized):
                with self.subTest(kind=path.name), \
                        patch.object(tool, "_run_inspector", side_effect=AssertionError("helper")):
                    with self.assertRaises(tool.PreflightError):
                        tool.inspect_key(path, CANARY, CANARY, CANARY)

    @unittest.skipUnless(os.name == "posix", "POSIX link/FIFO guard")
    def test_symlink_and_fifo_refused_before_helper(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "regular"
            source.write_bytes(b"fictional")
            link = root / "link"
            link.symlink_to(source)
            fifo = root / "fifo"
            os.mkfifo(fifo)
            with patch.object(tool, "_run_inspector", side_effect=AssertionError("helper")):
                for path in (link, fifo):
                    with self.assertRaises(tool.PreflightError):
                        tool.inspect_key(path, CANARY, CANARY, CANARY)
            self.assertEqual(source.read_bytes(), b"fictional")

    def test_binary_frame_no_secrets_in_child_arguments(self):
        process = subprocess.CompletedProcess([], 0, json.dumps(FACTS).encode())
        with patch.object(tool.shutil, "which", return_value="/synthetic/java"), \
                patch.object(tool.subprocess, "run", return_value=process) as run:
            self.assertEqual(tool._run_inspector(b"fictional", CANARY, CANARY, CANARY), FACTS)
        args, options = run.call_args
        self.assertNotIn(CANARY, repr(args))
        self.assertTrue(options["input"].startswith(b"LGKI"))
        frame = options["input"][4:]
        for value in (b"fictional", CANARY.encode(), CANARY.encode(), CANARY.encode()):
            length = struct.unpack(">I", frame[:4])[0]
            self.assertEqual(frame[4:4 + length], value)
            frame = frame[4 + length:]
        self.assertEqual(frame, b"")
        self.assertEqual(options["timeout"], 30)
        self.assertEqual(options["stderr"], subprocess.DEVNULL)

    def test_java_injection_and_arbitrary_secrets_not_forwarded(self):
        bad = {key: CANARY for key in ("JAVA_TOOL_OPTIONS", "_JAVA_OPTIONS", "JDK_JAVA_OPTIONS",
                                       "CLASSPATH", "SYNTHETIC_UNRELATED_SECRET")}
        with patch.dict(os.environ, bad):
            environment = tool._java_environment()
        for key in bad:
            self.assertNotIn(key, environment)

    def test_malformed_helper_output_refused_without_echo(self):
        for output in (CANARY.encode(), b"{}", json.dumps(dict(FACTS, surprise=CANARY)).encode(),
                       json.dumps(dict(FACTS, privateKeyProof=False)).encode(),
                       json.dumps(dict(FACTS, debugCertificate=1)).encode(),
                       json.dumps(dict(FACTS, certificateSha256="bad")).encode(),
                       b"x" * 4097):
            with self.subTest(length=len(output)), \
                    patch.object(tool.shutil, "which", return_value="/synthetic/java"), \
                    patch.object(tool.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, output)):
                with self.assertRaises(tool.PreflightError) as failure:
                    tool._run_inspector(b"fictional", CANARY, CANARY, CANARY)
                self.assertEqual(failure.exception.code, "inspector_invalid_response")
                self.assertNotIn(CANARY, str(failure.exception))

    def test_helper_refusal_whitelisted_only(self):
        for reason, expected in (("keystore_unreadable", "keystore_unreadable"),
                                 (CANARY, "inspector_invalid_response")):
            output = json.dumps({"schemaVersion": 1, "status": "REFUSED", "reason": reason}).encode()
            with patch.object(tool.shutil, "which", return_value="/synthetic/java"), \
                    patch.object(tool.subprocess, "run", return_value=subprocess.CompletedProcess([], 2, output)):
                with self.assertRaises(tool.PreflightError) as failure:
                    tool._run_inspector(b"fictional", CANARY, CANARY, CANARY)
                self.assertEqual(failure.exception.code, expected)

    def test_timeout_or_subprocess_failure_sanitized(self):
        for failure, expected in ((subprocess.TimeoutExpired(CANARY, 30), "inspector_timeout"),
                                  (OSError(CANARY), "inspector_unavailable")):
            with patch.object(tool.shutil, "which", return_value="/synthetic/java"), \
                    patch.object(tool.subprocess, "run", side_effect=failure):
                with self.assertRaises(tool.PreflightError) as result:
                    tool._run_inspector(b"fictional", CANARY, CANARY, CANARY)
                self.assertEqual(result.exception.code, expected)

    def test_wrong_exit_code_cannot_approve(self):
        with patch.object(tool.shutil, "which", return_value="/synthetic/java"), \
                patch.object(tool.subprocess, "run", return_value=subprocess.CompletedProcess([], 2, json.dumps(FACTS).encode())):
            with self.assertRaises(tool.PreflightError):
                tool._run_inspector(b"fictional", CANARY, CANARY, CANARY)


if __name__ == "__main__":
    unittest.main()
