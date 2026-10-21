"""Host safety tests; these are not evidence of Android or SQLite execution."""
import contextlib
import io
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from urllib.parse import parse_qs, urlparse
from xml.sax.saxutils import escape

import test_standalone_android as subject


class CertificateTest(unittest.TestCase):
    def test_sdk36_v2_output_and_legacy_single_signer(self):
        from subprocess import CompletedProcess
        for prefix in ('V2 Signer:', 'Signer #1'):
            output = prefix + ' certificate SHA-256 digest: ' + 'a' * 64 + '\n'
            with self.subTest(prefix=prefix), patch.object(subject.shutil, 'which', return_value='/synthetic/apksigner'), patch.object(subject.subprocess, 'run', return_value=CompletedProcess([], 0, output, '')):
                self.assertEqual(subject.certificate_digest(Path('/synthetic/never-read.apk')), 'a' * 64)

    def test_bad_or_multiple_certificates_or_failed_verification_rejected(self):
        from subprocess import CompletedProcess
        valid = 'V2 Signer: certificate SHA-256 digest: ' + 'a' * 64 + '\n'
        for code, output in ((1, valid), (0, ''), (0, valid + valid), (0, valid.replace('certificate', 'public key'))):
            with self.subTest(code=code, output=output), patch.object(subject.shutil, 'which', return_value='/synthetic/apksigner'), patch.object(subject.subprocess, 'run', return_value=CompletedProcess([], code, output, '')):
                with self.assertRaisesRegex(subject.AcceptanceError, 'apk_signature_rejected'):
                    subject.certificate_digest(Path('/synthetic/never-read.apk'))


class FakeAdb:
    def __init__(self, overrides=None):
        self.calls = []
        self.responses = {
            ("get-state",): "device\n",
            ("shell", "getprop", "ro.kernel.qemu"): "1\n",
            ("shell", "getprop", "ro.boot.qemu"): "1\n",
            ("shell", "getprop", "ro.hardware"): "ranchu\n",
            ("shell", "getprop", "ro.product.name"): "sdk_gphone64_x86_64\n",
            ("shell", "getprop", "ro.build.version.sdk"): "35\n",
            ("shell", "pm", "list", "packages", subject.PACKAGE): "",
        }
        self.responses.update(overrides or {})

    def command(self, *parts, allow_failure=False):
        self.calls.append(parts)
        if parts[0] == "install":
            return "Success\n"
        return self.responses.get(parts, "")

    def shell(self, *parts, allow_failure=False):
        return self.command("shell", *parts, allow_failure=allow_failure)


class SafetyTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.user = Path(self.directory.name) / "user.apk"
        self.fixture = Path(self.directory.name) / "fixture.apk"
        self.user.write_bytes(b"user placeholder")
        self.fixture.write_bytes(b"fixture placeholder")
        self.manifest = {"result": "PASS", "package": subject.PACKAGE,
            "label": subject.LABEL, "debuggable": True, "internetPermission": False,
            "targetSdkVersion": 36, "sha256": "a" * 64}

    def harness(self, adb, **extra):
        values = dict(serial="emulator-5554", user_apk=self.user,
                      fixture_apk=self.fixture, allow_reset=True, adb=adb,
                      manifest_check=lambda path: self.manifest,
                      certificate_check=lambda path: "b" * 64,
                      screenshot=Path(self.directory.name) / "first-launch.png")
        values.update(extra)
        return subject.Harness(**values)

    def assert_read_only(self, adb):
        for parts in adb.calls:
            self.assertNotEqual(parts[0], "install")
            if parts[0] == "shell":
                self.assertIn(parts[1:3], [("getprop", "ro.kernel.qemu"),
                    ("getprop", "ro.boot.qemu"), ("getprop", "ro.hardware"),
                    ("getprop", "ro.product.name"), ("getprop", "ro.build.version.sdk"),
                    ("pm", "list")])

    def test_physical_and_implicit_serial_refused_without_adb(self):
        for serial in ("", "R58PHONE", "emulator-5554;bad", "emulator-5555", "emulator-5554\n"):
            adb = FakeAdb()
            with self.subTest(serial=serial), self.assertRaises(subject.AcceptanceError):
                self.harness(adb, serial=serial).install_user()
            self.assertEqual(adb.calls, [])

    def test_confirmation_and_two_existing_apks_required_before_adb(self):
        for change in ({"allow_reset": False}, {"user_apk": self.user.with_name("absent")},
                       {"fixture_apk": self.fixture.with_name("absent")}):
            adb = FakeAdb()
            with self.subTest(change=change), self.assertRaises(subject.AcceptanceError):
                self.harness(adb, **change).install_user()
            self.assertEqual(adb.calls, [])

    def test_both_manifest_and_same_certificate_checked_before_adb(self):
        for change in ({"debuggable": False}, {"internetPermission": True},
                       {"label": "other"}, {"package": "ir.lifeguide.app"},
                       {"targetSdkVersion": 35}):
            adb = FakeAdb()
            with self.subTest(change=change), self.assertRaises(subject.AcceptanceError):
                self.harness(adb, manifest_check=lambda path: self.manifest | change).install_user()
            self.assertEqual(adb.calls, [])
        adb = FakeAdb()
        with self.assertRaisesRegex(subject.AcceptanceError, "apk_certificates_differ"):
            self.harness(adb, certificate_check=lambda path: ("b" if path == self.user else "c") * 64).install_user()
        self.assertEqual(adb.calls, [])

    def test_all_emulator_gates_precede_writes(self):
        for override in ({("get-state",): "offline"},
            {("shell", "getprop", "ro.kernel.qemu"): "0", ("shell", "getprop", "ro.boot.qemu"): "0"},
            {("shell", "getprop", "ro.hardware"): "phone"},
            {("shell", "getprop", "ro.product.name"): "owner"},
            {("shell", "getprop", "ro.build.version.sdk"): "34"},
            {("shell", "pm", "list", "packages", subject.PACKAGE): "package:" + subject.PACKAGE}):
            adb = FakeAdb(override)
            with self.subTest(override=override), self.assertRaises(subject.AcceptanceError):
                self.harness(adb).install_user()
            self.assert_read_only(adb)

    def test_owned_upgrade_requires_actual_first_launch_proof(self):
        adb = FakeAdb()
        harness = self.harness(adb)
        harness.install_user()
        with self.assertRaisesRegex(subject.AcceptanceError, "user_first_launch_not_verified"):
            harness.install_fixture()
        installs = [call for call in adb.calls if call[0] == "install"]
        self.assertEqual(installs, [("install", str(self.user))])
        harness.user_launched = True
        adb.responses[("shell", "sh", "-c", subject.PID_QUERY)] = "ABSENT"
        harness.install_fixture()
        self.assertIn(("install", "-r", str(self.fixture)), adb.calls)
        commands = " ".join(" ".join(call) for call in adb.calls)
        for forbidden in ("uninstall", "force-stop", "kill-server", "logcat -c"):
            self.assertNotIn(forbidden, commands)

    def test_empty_pid_response_is_not_absence_and_late_absence_is_not_proof(self):
        adb = FakeAdb()
        harness = self.harness(adb)
        harness.installed = True
        with self.assertRaisesRegex(subject.AcceptanceError, "fixture_process_query_failed"):
            harness.process_dead()
        adb.responses[("shell", "sh", "-c", subject.PID_QUERY)] = "ABSENT"
        adb.responses[("shell", "date", "+%s")] = "1800000046"
        with self.assertRaisesRegex(subject.AcceptanceError, "process_absence_missed_alarm_deadline"):
            harness.process_dead(before=1800000045000)
        self.assertNotIn("processAbsentBeforeAlarm", harness.receipt["checks"])

    def test_cli_refusal_receipt_does_not_expose_raw_arguments(self):
        output = Path(self.directory.name) / "receipt.json"
        with patch.object(subject, "Adb") as adb, contextlib.redirect_stdout(io.StringIO()):
            code = subject.main(["--user-apk", str(self.user), "--fixture-apk", str(self.fixture),
                "--serial", "PRIVATE_PHONE", "--allow-synthetic-emulator-reset", "--output", str(output)])
        self.assertEqual(code, 1)
        adb.assert_not_called()
        self.assertNotIn("PRIVATE_PHONE", output.read_text())


class ParsingTest(unittest.TestCase):
    def marker(self, mode="seed"):
        return {"nonce": "0123456789abcdef", "mode": mode, "syntheticDataOnly": True,
            "database": subject.DATABASE, "checks": {"rawSqlAfterClose": True,
            "profilePersists": True, "weeklyDifferentTimes": True,
            "onceAndEveryTwoDays": True},
            "status": {"supported": True, "permissionGranted": True, "active": True, "enabled": True,
                "activeScope": subject.SCOPE, "scheduledCount": 1,
                "timing": "exact", "canScheduleExactAlarms": True},
            "scheduledAtEpochMs": 1800000045000}

    def test_marker_whitelist_discards_arbitrary_private_fields(self):
        marker = self.marker() | {"private": "DO_NOT_PUBLISH"}
        marker["checks"]["private"] = "DO_NOT_PUBLISH"
        parsed = subject.fixture_marker(subject.MARKER + json.dumps(marker), marker["nonce"], "seed")
        self.assertNotIn("DO_NOT_PUBLISH", json.dumps(parsed))
        self.assertIsNone(subject.fixture_marker(subject.MARKER + json.dumps(marker), "a" * 16, "seed"))

    def test_marker_rejects_wrong_database_scope_or_fixture_label(self):
        for update in ({"database": "lifeguide_standalone_v1.sqlite"},
                       {"syntheticDataOnly": False}, {"mode": "inspect"},
                       {"status": self.marker()["status"] | {"activeScope": "private"}}):
            marker = self.marker() | update
            with self.subTest(update=update), self.assertRaises(subject.AcceptanceError):
                subject.fixture_marker(subject.MARKER + json.dumps(marker), marker["nonce"], "seed")

    def test_public_lock_screen_version_has_separate_generic_title(self):
        key = '0|' + subject.PACKAGE + '|1|lifeguide-plan:' + '22222222-2222-4222-8222-222222222222' + '|10001'
        primary = (f'NotificationRecord(pkg={subject.PACKAGE} key={key}: Notification(channel={subject.CHANNEL}))\n'
            f'android.title=String ({subject.COMPANION})\nandroid.text=String ({subject.GENERIC_BODY})\n')
        public = f'publicVersion\nandroid.title=String (LifeGuide)\nandroid.text=String ({subject.GENERIC_BODY})\n'
        self.assertTrue(subject.check_notification_record(primary + public, key)['titleMatches'])
        for bad in (primary.replace(subject.COMPANION, 'wrong') + public,
                    primary + public.replace('LifeGuide)', 'wrong)'),
                    primary + public.replace(subject.GENERIC_BODY, subject.CANARY)):
            with self.assertRaises(subject.AcceptanceError):
                subject.check_notification_record(bad, key)

    def test_notification_parser_accepts_only_owned_uuid_tag(self):
        identifier = "33333333-3333-4333-8333-333333333333"
        key = f"0|{subject.PACKAGE}|1|lifeguide-plan:{identifier}|10123"
        self.assertEqual(subject.active_fixture_keys(key), [key])
        with self.assertRaisesRegex(subject.AcceptanceError, "unexpected_fixture_notification"):
            subject.active_fixture_keys(f"0|{subject.PACKAGE}|1|private-title|10123")

    def test_preferences_only_allow_synthetic_scope_and_companion(self):
        from xml.sax.saxutils import escape
        row = {"id": "33333333-3333-4333-8333-333333333333",
            "planItemId": "33333333-3333-4333-8333-333333333333",
            "scheduledAtEpochMs": 1800000045000, "companionName": subject.COMPANION}
        state = {"scope": subject.SCOPE, "generation": "44444444-4444-4444-8444-444444444444",
            "issuedAtEpochMs": 1800000000000, "validUntilEpochMs": 1800086400000,
            "reminders": [row], "leaseKind": "device-planner-v1"}
        def xml():
            return '<map><string name="active">' + escape(json.dumps(state)) + '</string></map>'
        self.assertEqual(subject.parse_preferences(xml()), state)
        row["companionName"] = "private user name"
        with self.assertRaises(subject.AcceptanceError) as caught:
            subject.parse_preferences(xml())
        self.assertNotIn("private user name", str(caught.exception))

    def test_fixture_source_has_separate_db_and_no_server_acknowledgement(self):
        source = Path(__file__).with_name("standalone_acceptance_fixture.dart").read_text()
        self.assertIn("LG_STANDALONE_ACCEPTANCE", source)
        self.assertIn("StandaloneStore.open", source)
        self.assertIn("rawQuery", source)
        self.assertIn(subject.DATABASE, source)
        self.assertNotIn("serverAcknowledged", source)
        self.assertNotIn("LocalOnlyApi", source)


class SyntheticEmulator(FakeAdb):
    """A host model for orchestration checks, never Android acceptance evidence."""
    def __init__(self):
        super().__init__()
        self.elapsed = 0
        self.alive = self.posted = self.enabled = False
        self.state = None
        self.markers, self.modes = [], []
        self.refuse_kill = False
        self.pid_failure = False
        self.background_delay = 0
        self.background_ready = 0
        self.late_kill = False
        self.settings_visible = False
        self.settings_matches = True
        self.pipe_dump_empty = False
        self.dump_files = {}
        self.identifier = "33333333-3333-4333-8333-333333333333"

    def clock(self):
        return self.elapsed

    def epoch(self):
        return 1800000010000 + int(self.elapsed * 1000)

    def sleep(self, seconds):
        self.elapsed += seconds
        if self.state and self.state["reminders"]:
            row = self.state["reminders"][0]
            if not row.get("delivered") and row["scheduledAtEpochMs"] <= self.epoch():
                row["delivered"] = True
                self.posted = self.alive = True

    def key(self):
        return f"0|{subject.PACKAGE}|1|lifeguide-plan:{self.identifier}|10123"

    def command(self, *parts, allow_failure=False):
        if parts[0] == "install":
            return super().command(*parts, allow_failure=allow_failure)
        self.calls.append(parts)
        if parts == ("shell", "input", "keyevent", "KEYCODE_HOME"):
            self.background_ready = self.elapsed + self.background_delay
            return ""
        if parts == ('shell', 'input', 'keyevent', 'KEYCODE_BACK'):
            self.settings_visible = False
            return ''
        if parts[:3] == ('shell', 'uiautomator', 'dump'):
            title = 'یادآوری برنامهٔ شخصی' if self.settings_matches else 'Other channel'
            xml = ('<hierarchy><node package="com.android.settings" text="' + title +
                   '" /></hierarchy>') if self.settings_visible else ''
            if parts[3] == '/dev/tty':
                return '' if self.pipe_dump_empty else xml
            self.dump_files[parts[3]] = xml
            return 'UI hierchary dumped to: ' + parts[3]
        if parts[:2] == ('shell', 'cat'):
            return self.dump_files.get(parts[2], '')
        if parts[:3] == ('shell', 'rm', '-f'):
            self.dump_files.pop(parts[3], None)
            return ''
        if parts == ("shell", "am", "kill", subject.PACKAGE):
            if self.late_kill and self.state and self.state["reminders"]:
                self.sleep(60)
            self.alive = self.refuse_kill or self.elapsed < self.background_ready
            return ""
        if parts == ("shell", "sh", "-c", subject.PID_QUERY):
            return "" if self.pid_failure else ("PRESENT" if self.alive else "ABSENT")
        if parts == ("shell", "date", "+%s"):
            return str(self.epoch() // 1000)
        if parts[0] == "logcat":
            return "\n".join(self.markers)
        if parts[:3] == ("shell", "run-as", subject.PACKAGE):
            return "<map/>" if self.state is None else ('<map><string name="active">' +
                escape(json.dumps(self.state)) + '</string></map>')
        if parts == ("shell", "cmd", "notification", "list"):
            return self.key() if self.posted else ""
        if parts[:3] == ("shell", "dumpsys", "notification"):
            return (f"NotificationRecord(pkg={subject.PACKAGE} key={self.key()}: "
                f"Notification(channel={subject.CHANNEL}))\n"
                f"android.title=String ({subject.COMPANION})\n"
                f"android.text=String ({subject.GENERIC_BODY})\n")
        if parts[:3] == ("shell", "am", "start"):
            self.alive = True
            if "--es" not in parts:
                return "Status: ok"
            route = urlparse(parts[-1])
            mode = route.path[1:]
            self.modes.append(mode)
            at = None
            if mode in ("seed", "change"):
                at = (self.epoch() // 60000 + 1) * 60000
                self.enabled, self.posted = True, False
                self.state = {"scope": subject.SCOPE,
                    "generation": "44444444-4444-4444-8444-444444444444",
                    "issuedAtEpochMs": self.epoch(), "validUntilEpochMs": self.epoch() + 31 * 86400000,
                    "leaseKind": "device-planner-v1", "reminders": [{"id": self.identifier,
                    "planItemId": self.identifier, "companionName": subject.COMPANION,
                    "scheduledAtEpochMs": at}]}
            elif mode == "cancel":
                self.state["reminders"] = []
                self.posted = False
            elif mode == "off":
                self.enabled, self.posted, self.state = False, False, None
            elif mode == 'settings':
                self.settings_visible = True
            status = {"supported": True, "permissionGranted": True,
                "active": self.state is not None, "enabled": self.enabled,
                "activeScope": subject.SCOPE if self.state else None,
                "scheduledCount": sum(r["scheduledAtEpochMs"] > self.epoch()
                    for r in self.state["reminders"]) if self.state else 0,
                "timing": "exact", "canScheduleExactAlarms": True}
            marker = {"nonce": parse_qs(route.query)["nonce"][0], "mode": mode,
                "syntheticDataOnly": True, "database": subject.DATABASE, "status": status,
                "checks": {k: True for k in subject.CHECKS}}
            if at:
                marker["scheduledAtEpochMs"] = at
            self.markers.append(subject.MARKER + json.dumps(marker))
            return "Status: ok"
        return self.responses.get(parts, "")


class LifecycleTest(unittest.TestCase):
    setUp = SafetyTest.setUp

    def harness(self, adb, **extra):
        values = {"clock": adb.clock, "sleep": adb.sleep}
        values.update(extra)
        return SafetyTest.harness(self, adb, **values)

    def first_launch(self, harness):
        # Real screenshot handling is separately tested below; this host model
        # cannot provide a genuine image from an Android display.
        harness.adb.shell("am", "start", "-W", "-f", "0x10008000", "-n", subject.COMPONENT)
        harness.user_launched = True

    def png_result(self):
        import struct
        png = b'\x89PNG\r\n\x1a\n' + b'\0\0\0\rIHDR' + struct.pack('>II', 1080, 1920)
        return type('Result', (), {'returncode': 0, 'stdout': png})()

    def test_non_tty_dump_is_read_then_removed_without_losing_the_strict_check(self):
        adb = SyntheticEmulator()
        adb.pipe_dump_empty = True
        harness = self.harness(adb)
        error = None
        with patch.object(harness, 'first_user_launch', side_effect=lambda: self.first_launch(harness)), \
             patch.object(subject.subprocess, 'run', return_value=self.png_result()):
            try:
                receipt = harness.run()
            except subject.AcceptanceError as failed:
                error = str(failed)
        self.assertIsNone(error, 'Empty non-PTY dump must not prevent independent file verification')
        self.assertEqual(receipt['checks']['nativeNotificationSettingsWhileOff'], 'PASS')
        self.assertFalse(receipt['settingsObservation']['legacyTty']['verified'])
        self.assertTrue(receipt['settingsObservation']['file']['verified'])
        self.assertIn('legacyTtyAfterFile', receipt['settingsObservation'])
        self.assertFalse(receipt['settingsObservation']['legacyTtyAfterFile']['verified'])
        self.assertFalse(adb.dump_files)
        for call in adb.calls:
            if call[:3] == ('shell', 'rm', '-f'):
                self.assertRegex(call[3], r'^/data/local/tmp/lifeguide-settings-[0-9a-f]{16}\.xml$')

    def test_full_mode_sequence_and_sanitized_receipt(self):
        adb = SyntheticEmulator()
        harness = self.harness(adb)
        with patch.object(harness, "first_user_launch", side_effect=lambda: self.first_launch(harness)), \
             patch.object(subject.subprocess, 'run', return_value=self.png_result()):
            receipt = harness.run()
        self.assertEqual(receipt["result"], "PASS")
        self.assertEqual(adb.modes, ["seed", "inspect", "change", "cancel", "off", "settings", "inspect"])
        self.assertEqual(receipt["checks"]["nativeNotificationSettingsWhileOff"], "PASS")
        self.assertEqual(receipt["checks"]["sqliteAfterNotificationSettings"], "PASS")
        self.assertIsNone(adb.state)
        self.assertFalse(adb.posted)
        self.assertGreater(adb.elapsed, 95)
        self.assertTrue(all(value == "UNVERIFIED" for value in receipt["limitations"].values()))
        serialized = json.dumps(receipt)
        for forbidden in (subject.CANARY, "NotificationRecord", "<map", "nonce"):
            self.assertNotIn(forbidden, serialized)
        launches = [p for p in adb.calls if p[:3] == ("shell", "am", "start")]
        self.assertNotIn("--es", launches[0])
        for parts in launches:
            self.assertIn(subject.COMPONENT, parts)
            self.assertEqual(parts[parts.index("-f") + 1], "0x10008000")
        commands = " ".join(" ".join(call) for call in adb.calls)
        for forbidden in ("uninstall", "force-stop", "kill-server", "logcat -c"):
            self.assertNotIn(forbidden, commands)

    def test_real_first_launch_path_requires_present_pid_and_valid_png(self):
        import struct
        adb = SyntheticEmulator()
        harness = self.harness(adb)
        harness.install_user()
        png = b"\x89PNG\r\n\x1a\n" + b"\0\0\0\rIHDR" + struct.pack(">II", 1080, 1920)
        result = type("Result", (), {"returncode": 0, "stdout": png})()
        with patch.object(subject.subprocess, "run", return_value=result):
            harness.first_user_launch()
        self.assertTrue(harness.user_launched)
        self.assertEqual(harness.screenshot.read_bytes(), png)
        self.assertTrue(harness.receipt["userFirstLaunch"]["ordinaryLaunchNoExtras"])

    def test_background_transition_retries_and_failed_pid_never_claims_absence(self):
        adb = SyntheticEmulator()
        adb.background_delay = 1
        harness = self.harness(adb)
        harness.installed = True
        harness.process_dead()
        self.assertGreaterEqual(adb.elapsed, 1)
        self.assertGreater(harness.receipt["processExit"]["ordinaryKillAttempts"], 1)
        adb.pid_failure = True
        with self.assertRaisesRegex(subject.AcceptanceError, "fixture_process_query_failed"):
            harness.process_dead()
        self.assertNotIn("processExit", harness.receipt)

    def test_late_absence_cannot_claim_notification_after_process_death(self):
        adb = SyntheticEmulator()
        adb.late_kill = True
        harness = self.harness(adb)
        with patch.object(harness, "first_user_launch", side_effect=lambda: self.first_launch(harness)):
            with self.assertRaisesRegex(subject.AcceptanceError, "process_absence_missed_alarm_deadline"):
                harness.run()
        self.assertNotIn("processAbsentBeforeAlarm", harness.receipt["checks"])

    def test_wrong_native_settings_screen_cannot_claim_acceptance(self):
        adb = SyntheticEmulator()
        adb.settings_matches = False
        harness = self.harness(adb)
        with patch.object(harness, "first_user_launch", side_effect=lambda: self.first_launch(harness)), \
             patch.object(subject.subprocess, 'run', return_value=self.png_result()):
            with self.assertRaisesRegex(subject.AcceptanceError, 'notification_settings_screen_not_verified'):
                harness.run()
        self.assertNotIn('nativeNotificationSettingsWhileOff', harness.receipt['checks'])
        self.assertEqual(harness.receipt['result'], 'FAIL')
        self.assertFalse(adb.dump_files)


class NotificationSettingsTest(unittest.TestCase):
    def checker(self):
        function = getattr(subject, 'notification_settings_visible', None)
        self.assertTrue(callable(function), 'Native settings screen verification is missing')
        return function

    def xml(self, package='com.android.settings', title='یادآوری برنامهٔ شخصی'):
        return ('<?xml version="1.0" encoding="UTF-8"?>'
                '<hierarchy rotation="0"><node package="' + package +
                '" text="' + title + '" /></hierarchy>')

    def test_only_system_settings_with_our_channel_title_is_accepted(self):
        check = self.checker()
        self.assertTrue(check(self.xml()))
        self.assertTrue(check('UI hierchary dumped to: /dev/tty\n' + self.xml()))
        for wrong in (self.xml(package=subject.PACKAGE),
                      self.xml(title='Other channel'),
                      self.xml(package='unrelated.app')):
            with self.subTest(wrong=wrong):
                self.assertFalse(check(wrong))

    def test_missing_malformed_or_oversized_settings_dump_cannot_pass(self):
        check = self.checker()
        for wrong in ('', 'ERROR: could not get idle state', '<hierarchy>',
                      '<!DOCTYPE x>' + self.xml(), self.xml() * 1000):
            with self.subTest(size=len(wrong)):
                self.assertFalse(check(wrong))

    def test_unrelated_node_label_cannot_supply_the_system_title(self):
        check = self.checker()
        mixed = ('<hierarchy><node package="com.android.settings" text="Other" />'
                 '<node package="unrelated.app" text="یادآوری برنامهٔ شخصی" /></hierarchy>')
        self.assertFalse(check(mixed))

    def test_diagnostic_summary_is_bounded_and_does_not_publish_ui_labels(self):
        summarize = getattr(subject, 'notification_settings_summary', None)
        self.assertTrue(callable(summarize), 'Sanitized native-screen diagnostics are missing')
        summary = summarize(self.xml())
        self.assertTrue(summary['verified'])
        self.assertTrue(summary['systemSettingsNodePresent'])
        self.assertFalse(summarize('')['validHierarchy'])
        serialized = json.dumps(summarize(self.xml(title='SYNTHETIC_PRIVATE_TASK_CANARY')))
        self.assertNotIn('SYNTHETIC_PRIVATE_TASK_CANARY', serialized)
        self.assertNotIn('<hierarchy', serialized)


if __name__ == "__main__":
    unittest.main()
