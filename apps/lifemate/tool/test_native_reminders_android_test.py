"""Host-side tests only: no adb, emulator, account, network, or APK build."""
import json
import contextlib
import io
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from urllib.parse import parse_qs, urlparse
from xml.sax.saxutils import escape

import test_native_reminders_android as subject


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
        return self.responses.get(parts, "")

    def shell(self, *parts, allow_failure=False):
        return self.command("shell", *parts, allow_failure=allow_failure)


class SyntheticEmulator(FakeAdb):
    """A model of adb responses, not evidence of Android device behavior."""
    def __init__(self):
        super().__init__()
        self.elapsed = 0
        self.state = None
        self.posted = False
        self.alive = False
        self.exact = True
        self.markers = []
        self.generation = 0
        self.modes = []
        self.private_body = False
        self.refuse_kill = False
        self.pid_query_failure = False
        self.background_delay = 0
        self.background_ready_at = 0
        self.pid_states = []

    def clock(self):
        return self.elapsed

    def epoch(self):
        return 1800000000000 + int(self.elapsed * 1000)

    def sleep(self, seconds):
        self.elapsed += seconds
        if self.state and self.exact:
            for row in self.state["reminders"]:
                if not row.get("delivered") and row["scheduledAtEpochMs"] <= self.epoch():
                    row["delivered"] = True
                    self.posted = True
                    self.alive = True  # The native receiver may start its process.

    def status(self):
        return {"supported": True, "permissionGranted": True,
                "active": self.state is not None,
                "activeScope": subject.SCOPE if self.state else None,
                "scheduledCount": sum(row["scheduledAtEpochMs"] > self.epoch()
                                      for row in self.state["reminders"]) if self.state else 0,
                "timing": "exact" if self.exact else "approximate",
                "canScheduleExactAlarms": self.exact}

    def key(self):
        return f"0|{subject.PACKAGE}|1|lifeguide-plan:{subject.REMINDER}|10123"

    def command(self, *parts, allow_failure=False):
        self.calls.append(parts)
        if parts[0] == "logcat":
            return "\n".join(self.markers)
        if parts[:4] == ("shell", "cmd", "appops", "set"):
            self.exact = parts[-1] == "allow"
        if parts == ("shell", "input", "keyevent", "KEYCODE_HOME"):
            self.background_ready_at = self.elapsed + self.background_delay
            return ""
        if parts == ("shell", "am", "kill", subject.PACKAGE):
            if self.refuse_kill:
                self.alive = True
            elif self.elapsed >= self.background_ready_at:
                self.alive = False
            return ""
        if parts == ("shell", "pidof", subject.PACKAGE):
            if self.pid_query_failure:
                return ""
            return "123\n" if self.alive else ""
        if parts[:3] == ("shell", "sh", "-c"):
            if self.pid_query_failure:
                return ""
            state = "PRESENT" if self.alive else "ABSENT"
            self.pid_states.append(state)
            return state
        if parts == ("shell", "date", "+%s"):
            return str(self.epoch() // 1000)
        if parts[:3] == ("shell", "run-as", subject.PACKAGE):
            if self.state is None:
                return "<map/>"
            return '<map><string name="active">' + escape(json.dumps(self.state)) + '</string></map>'
        if parts == ("shell", "cmd", "notification", "list"):
            return self.key() + "\n" if self.posted else ""
        if parts[:3] == ("shell", "dumpsys", "notification"):
            body = subject.CANARY if self.private_body else subject.GENERIC_BODY
            return (f"NotificationRecord(pkg={subject.PACKAGE} key={self.key()})\n"
                    f"  channel={subject.CHANNEL}\n"
                    f"  android.title=String ({subject.COMPANION})\n"
                    f"  android.text=String ({body})\n")
        if parts[:3] == ("shell", "am", "start"):
            self.alive = True
            route = urlparse(parts[-1])
            mode = route.path.removeprefix("/")
            query = parse_qs(route.query)
            self.modes.append(mode)
            if mode == "schedule":
                self.generation += 1
                self.state = {
                    "scope": subject.SCOPE,
                    "generation": f"{self.generation:08x}-4444-4444-8444-444444444444",
                    "issuedAtEpochMs": self.epoch(),
                    "validUntilEpochMs": self.epoch() + 600000,
                    "reminders": [{"id": subject.REMINDER, "planItemId": subject.PLAN,
                                   "companionName": subject.COMPANION,
                                   "scheduledAtEpochMs": self.epoch() + 45000}],
                }
                self.posted = False
            elif mode == "suppress" and self.state:
                self.state["reminders"] = []
                self.posted = False
            elif mode == "off":
                self.state = None
                self.posted = False
            marker = {"nonce": query["nonce"][0], "mode": mode,
                      "status": self.status(), "simulatedServerAcknowledgement": True}
            if mode == "schedule":
                marker["scheduledAtEpochMs"] = self.state["reminders"][0]["scheduledAtEpochMs"]
            self.markers.append(subject.MARKER + json.dumps(marker))
            return "Success"
        return self.responses.get(parts, "")


class PreflightTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.apk = Path(self.directory.name) / "fixture.apk"
        self.apk.write_bytes(b"synthetic APK placeholder; manifest check is mocked")
        self.manifest = {
            "result": "PASS", "mode": "debug", "package": subject.PACKAGE,
            "debuggable": True, "targetSdkVersion": 36, "sha256": "a" * 64,
        }

    def harness(self, adb, **overrides):
        values = dict(serial="emulator-5554", apk=self.apk, allow_reset=True,
                      adb=adb, manifest_check=lambda path, mode: self.manifest)
        values.update(overrides)
        return subject.Harness(**values)

    def assert_read_only(self, adb):
        for parts in adb.calls:
            self.assertNotEqual(parts[0], "install")
            if parts[0] == "shell":
                self.assertIn(parts[1:3], [("getprop", "ro.kernel.qemu"),
                    ("getprop", "ro.boot.qemu"), ("getprop", "ro.hardware"),
                    ("getprop", "ro.product.name"), ("getprop", "ro.build.version.sdk"),
                    ("pm", "list")])

    def test_physical_serial_refused_before_any_adb_call(self):
        for serial in ("R58REALDEVICE", "", "emulator-5554;echo bad", "emulator-5554\n"):
            with self.subTest(serial=serial):
                adb = FakeAdb()
                with self.assertRaises(subject.AcceptanceError):
                    self.harness(adb, serial=serial).install_fixture()
                self.assertEqual(adb.calls, [])

    def test_reset_confirmation_required_before_any_adb_call(self):
        adb = FakeAdb()
        with self.assertRaises(subject.AcceptanceError):
            self.harness(adb, allow_reset=False).install_fixture()
        self.assertEqual(adb.calls, [])

    def test_missing_apk_refused_before_any_adb_call(self):
        adb = FakeAdb()
        with self.assertRaises(subject.AcceptanceError):
            self.harness(adb, apk=self.apk.with_name("missing.apk")).install_fixture()
        self.assertEqual(adb.calls, [])

    def test_bad_manifest_refused_before_any_adb_call(self):
        adb = FakeAdb()
        def reject(path, mode):
            raise ValueError("do not expose arbitrary checker output")
        with self.assertRaisesRegex(subject.AcceptanceError, "apk_manifest_rejected"):
            self.harness(adb, manifest_check=reject).install_fixture()
        self.assertEqual(adb.calls, [])

    def test_non_debug_or_wrong_target_manifest_is_rejected(self):
        for changes in ({"debuggable": False}, {"targetSdkVersion": 35}, {"package": "other.app"}):
            adb = FakeAdb()
            with self.subTest(changes=changes):
                with self.assertRaises(subject.AcceptanceError):
                    self.harness(adb, manifest_check=lambda path, mode: self.manifest | changes).install_fixture()
                self.assertEqual(adb.calls, [])

    def test_each_emulator_gate_prevents_mutation(self):
        cases = [
            {("get-state",): "offline\n"},
            {("shell", "getprop", "ro.kernel.qemu"): "", ("shell", "getprop", "ro.boot.qemu"): "0"},
            {("shell", "getprop", "ro.hardware"): "real-phone-chip"},
            {("shell", "getprop", "ro.product.name"): "owners_phone"},
            {("shell", "getprop", "ro.build.version.sdk"): "34"},
            {("shell", "pm", "list", "packages", subject.PACKAGE): "package:ir.lifeguide.app\n"},
        ]
        for responses in cases:
            with self.subTest(responses=responses):
                adb = FakeAdb(responses)
                with self.assertRaises(subject.AcceptanceError):
                    self.harness(adb).install_fixture()
                self.assert_read_only(adb)

    def test_install_follows_all_gates_and_no_other_package_is_touched(self):
        adb = FakeAdb()
        self.harness(adb).install_fixture()
        install_index = next(i for i, parts in enumerate(adb.calls) if parts[0] == "install")
        self.assertIn(("shell", "pm", "list", "packages", subject.PACKAGE), adb.calls[:install_index])
        self.assertIn(("shell", "pm", "grant", subject.PACKAGE, "android.permission.POST_NOTIFICATIONS"), adb.calls)
        self.assertIn(("shell", "cmd", "appops", "set", subject.PACKAGE, "SCHEDULE_EXACT_ALARM", "allow"), adb.calls)
        flattened = " ".join(" ".join(parts) for parts in adb.calls)
        for forbidden in ("force-stop", "kill-server", "uninstall", "logcat -c"):
            self.assertNotIn(forbidden, flattened)


class ParsingTest(unittest.TestCase):
    def key(self, reminder=subject.REMINDER):
        return f"0|{subject.PACKAGE}|1|lifeguide-plan:{reminder}|10123"

    def test_active_keys_only_recognize_exact_package_id_and_tag(self):
        own = self.key()
        output = "\n".join((own, "0|other.app|1|lifeguide-plan:private|10124",
                            f"0|{subject.PACKAGE}.fake|1|lifeguide-plan:{subject.REMINDER}|10125"))
        self.assertEqual(subject.active_fixture_keys(output), [own])
        self.assertEqual(subject.active_fixture_keys("no active keys\n"), [])

    def test_unknown_own_notification_is_refused_without_echoing_it(self):
        with self.assertRaisesRegex(subject.AcceptanceError, "unexpected_fixture_notification") as caught:
            subject.active_fixture_keys(f"0|{subject.PACKAGE}|9|private-user-title|10123")
        self.assertNotIn("private-user-title", str(caught.exception))

    def test_notification_check_uses_matching_record_only(self):
        key = self.key()
        dump = ("Notification List:\n  NotificationRecord(pkg=other.app key=other)\n"
                "  android.text=String (SYNTHETIC_PRIVATE_TASK_CANARY)\n"
                f"  NotificationRecord(pkg={subject.PACKAGE} key={key})\n"
                f"    android.title=String ({subject.COMPANION})\n"
                f"    android.text=String ({subject.GENERIC_BODY})\n")
        result = subject.check_notification_record(dump, key)
        self.assertEqual(result, {"titleMatches": True, "genericBodyMatches": True,
                                  "privateCanaryAbsent": True})
        self.assertNotIn("other.app", json.dumps(result))

    def test_notification_canary_or_wrong_body_fails(self):
        for body in ("wrong body", subject.GENERIC_BODY + " SYNTHETIC_PRIVATE_TASK_CANARY"):
            dump = (f"NotificationRecord(pkg={subject.PACKAGE} key={self.key()})\n"
                    f"android.title=String ({subject.COMPANION})\nandroid.text=String ({body})")
            with self.assertRaises(subject.AcceptanceError):
                subject.check_notification_record(dump, self.key())

    def test_android_record_key_terminator_and_channel_are_recognized(self):
        dump = (f"  NotificationRecord(abc: pkg={subject.PACKAGE} user=UserHandle{{0}} "
                f"id=1 key={self.key()}: Notification(channel={subject.CHANNEL} vis=PRIVATE))\n"
                f"    android.title=String ({subject.COMPANION})\n"
                f"    android.text=String ({subject.GENERIC_BODY})\n")
        result = subject.check_notification_record(dump, self.key(), require_channel=True)
        self.assertTrue(result["genericBodyMatches"])

    def test_marker_requires_nonce_mode_fixture_scope_and_simulation_label(self):
        marker = {"nonce": "0123456789abcdef", "mode": "inspect", "simulatedServerAcknowledgement": True,
                  "status": {"supported": True, "permissionGranted": True, "active": True,
                             "activeScope": subject.SCOPE, "scheduledCount": 0, "timing": "exact",
                             "canScheduleExactAlarms": True}}
        line = "I/flutter (123): LG_NATIVE_REMINDER_FIXTURE " + json.dumps(marker)
        self.assertEqual(subject.fixture_marker(line, marker["nonce"], "inspect")["status"]["scheduledCount"], 0)
        self.assertIsNone(subject.fixture_marker(line, "a" * 16, "inspect"))
        for change in ({"simulatedServerAcknowledgement": False},
                       {"status": marker["status"] | {"activeScope": "real-user-scope"}}):
            with self.assertRaises(subject.AcceptanceError):
                subject.fixture_marker("LG_NATIVE_REMINDER_FIXTURE " + json.dumps(marker | change), marker["nonce"], "inspect")

    def test_incomplete_or_inconsistent_status_is_a_sanitized_failure(self):
        status = {"supported": True, "permissionGranted": True, "active": False,
                  "activeScope": None, "scheduledCount": 0, "timing": "exact",
                  "canScheduleExactAlarms": True}
        for broken in ({key: value for key, value in status.items() if key != "activeScope"},
                       status | {"canScheduleExactAlarms": False}):
            marker = {"nonce": "0123456789abcdef", "mode": "inspect", "status": broken,
                      "simulatedServerAcknowledgement": True}
            with self.subTest(status=broken):
                with self.assertRaises(subject.AcceptanceError):
                    subject.fixture_marker(subject.MARKER + json.dumps(marker), marker["nonce"], "inspect")

    def test_native_preferences_only_accept_known_synthetic_payload(self):
        state = {"scope": subject.SCOPE, "generation": "44444444-4444-4444-8444-444444444444",
                 "issuedAtEpochMs": 1800000000000, "validUntilEpochMs": 1800000600000,
                 "reminders": [{"id": subject.REMINDER, "planItemId": subject.PLAN,
                                "scheduledAtEpochMs": 1800000045000,
                                "companionName": subject.COMPANION, "delivered": True}]}
        from xml.sax.saxutils import escape
        xml = '<map><string name="active">' + escape(json.dumps(state)) + '</string></map>'
        parsed = subject.parse_preferences(xml)
        self.assertTrue(parsed["reminders"][0]["delivered"])
        self.assertIsNone(subject.parse_preferences('<map/>'))
        state["reminders"][0]["companionName"] = "real private task text"
        with self.assertRaisesRegex(subject.AcceptanceError, "unexpected_fixture_preferences") as caught:
            subject.parse_preferences('<map><string name="active">' + escape(json.dumps(state)) + '</string></map>')
        self.assertNotIn("real private task text", str(caught.exception))

    def test_adb_shell_quoting_keeps_initial_route_a_single_argument(self):
        completed = type("Completed", (), {"returncode": 0, "stdout": "", "stderr": ""})()
        with patch.object(subject.subprocess, "run", return_value=completed) as run:
            subject.Adb("emulator-5554").shell("am", "start", "--es", "route", "/schedule?nonce=abc12345&delay=45")
        arguments = run.call_args.args[0]
        self.assertEqual(arguments[:4], ["adb", "-s", "emulator-5554", "shell"])
        self.assertIn("'/schedule?nonce=abc12345&delay=45'", arguments[4])


class LifecycleTest(unittest.TestCase):
    def harness(self, adb):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        apk = Path(directory.name) / "fixture.apk"
        apk.write_bytes(b"synthetic only")
        manifest = {"result": "PASS", "mode": "debug", "package": subject.PACKAGE,
                    "debuggable": True, "targetSdkVersion": 36, "sha256": "a" * 64}
        return subject.Harness(serial="emulator-5554", apk=apk, allow_reset=True, adb=adb,
                               manifest_check=lambda path, mode: manifest,
                               clock=adb.clock, sleep=adb.sleep)

    def test_full_sequence_with_virtual_time_finishes_off_and_labels_limits(self):
        adb = SyntheticEmulator()
        receipt = self.harness(adb).run()
        self.assertEqual(receipt["result"], "PASS")
        self.assertEqual(adb.modes, ["inspect", "schedule", "inspect", "suppress",
                                     "schedule", "suppress", "schedule", "off"])
        self.assertGreaterEqual(adb.elapsed, 95)
        self.assertIsNone(adb.state)
        self.assertFalse(adb.posted)
        self.assertFalse(adb.exact)
        self.assertTrue(all(value == "UNVERIFIED" for value in receipt["limitations"].values()))
        self.assertEqual(receipt["checks"]["approximateAlarmDeliveryTiming"], "UNVERIFIED")
        self.assertEqual(receipt["checks"]["notificationContent"]["privateCanaryAbsent"], True)
        serialized = json.dumps(receipt)
        self.assertNotIn(subject.CANARY, serialized)
        self.assertNotIn("NotificationRecord", serialized)
        self.assertNotIn("<map", serialized)
        for index, parts in enumerate(adb.calls):
            if parts[:3] == ("shell", "am", "start"):
                self.assertEqual(adb.calls[index - 3:index], [
                    ("shell", "input", "keyevent", "KEYCODE_HOME"),
                    ("shell", "am", "kill", subject.PACKAGE),
                    ("shell", "sh", "-c", subject.PID_QUERY)])
        commands = " ".join(" ".join(parts) for parts in adb.calls)
        for forbidden in ("force-stop", "kill-server", "uninstall", "logcat -c"):
            self.assertNotIn(forbidden, commands)

    def test_process_claim_fails_when_pid_remains(self):
        adb = SyntheticEmulator()
        adb.refuse_kill = True
        harness = self.harness(adb)
        with self.assertRaisesRegex(subject.AcceptanceError, "fixture_process_did_not_exit"):
            harness.run()
        self.assertEqual(adb.modes, [])
        self.assertEqual(harness.receipt["currentPhase"], "before_launch_inspect")
        self.assertEqual(harness.receipt["lastProcessState"], "PRESENT")
        self.assertNotIn("processExit", harness.receipt)

    def test_retries_ordinary_kill_after_home_background_transition(self):
        adb = SyntheticEmulator()
        adb.background_delay = 1
        adb.alive = True
        harness = self.harness(adb)
        harness.install_fixture()
        self.assertTrue(harness.process_dead())
        self.assertFalse(adb.alive)
        self.assertEqual(adb.pid_states[0], "PRESENT")
        self.assertEqual(adb.pid_states[-1], "ABSENT")
        self.assertGreaterEqual(adb.elapsed, adb.background_delay)
        self.assertLessEqual(adb.elapsed, 10)
        kills = [parts for parts in adb.calls
                 if parts == ("shell", "am", "kill", subject.PACKAGE)]
        self.assertGreater(len(kills), 1)
        self.assertEqual(harness.receipt["processExit"], {
            "confirmedAbsent": True, "ordinaryKillAttempts": len(kills)})

    def test_late_process_absence_cannot_claim_death_before_alarm(self):
        class SlowScheduledKill(SyntheticEmulator):
            delayed = False

            def command(self, *parts, allow_failure=False):
                if (parts == ("shell", "am", "kill", subject.PACKAGE) and
                        self.state and self.state["reminders"] and not self.delayed):
                    self.delayed = True
                    self.sleep(46)  # The modeled receiver posts before kill completes.
                return super().command(*parts, allow_failure=allow_failure)

        adb = SlowScheduledKill()
        harness = self.harness(adb)
        with self.assertRaisesRegex(subject.AcceptanceError, "process_absence_missed_alarm_deadline"):
            harness.run()
        self.assertTrue(adb.posted)
        self.assertEqual(harness.receipt["currentPhase"], "after_schedule_created")
        self.assertNotIn("processAbsentBeforeAlarm", harness.receipt["checks"])

    def test_empty_failed_pid_query_cannot_claim_process_absence(self):
        adb = SyntheticEmulator()
        adb.pid_query_failure = True
        with self.assertRaisesRegex(subject.AcceptanceError, "fixture_process_query_failed"):
            self.harness(adb).run()
        self.assertEqual(adb.modes, [])

    def test_os_post_with_private_body_fails_without_echoing_body(self):
        adb = SyntheticEmulator()
        adb.private_body = True
        with self.assertRaises(subject.AcceptanceError) as caught:
            self.harness(adb).run()
        self.assertNotIn(subject.CANARY, str(caught.exception))

    def test_cli_refusal_writes_only_sanitized_receipt_without_adb(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        output = Path(directory.name) / "receipt.json"
        with patch.object(subject, "Adb") as adb, contextlib.redirect_stdout(io.StringIO()):
            exit_code = subject.main(["--serial", "REAL_PHONE", "--apk", "/nonexistent.apk",
                                      "--allow-synthetic-emulator-reset", "--output", str(output)])
        self.assertEqual(exit_code, 1)
        adb.assert_not_called()
        receipt = json.loads(output.read_text())
        self.assertEqual(receipt["result"], "FAIL")
        self.assertEqual(receipt["error"], "explicit_emulator_serial_required")
        self.assertNotIn("REAL_PHONE", output.read_text())


if __name__ == "__main__":
    unittest.main()
