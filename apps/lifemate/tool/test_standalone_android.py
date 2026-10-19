#!/usr/bin/env python3
"""Bounded, synthetic acceptance of the real device-only SQLite/Android path.

Only a fresh API35 SDK emulator is accepted. Install the deliverable first and
capture its ordinary onboarding launch, then upgrade that owned install to the
separately built, never-distributed fixture with the identical certificate.
No uninstall, data clearing, force-stop, or network service is used.
"""
import argparse
import hashlib
import json
import os
import re
import secrets
import shutil
import struct
import subprocess
import time
import uuid
import xml.etree.ElementTree as ET
from pathlib import Path

# Reuse transport and the strict serial boundary without changing the online
# acceptance tool's fixed application identity or its regression tests.
from test_native_reminders_android import Adb, AcceptanceError, require, validate_serial

PACKAGE = "ir.lifeguide.app.device"
COMPONENT = PACKAGE + "/ir.lifeguide.app.MainActivity"
LABEL = "لایف‌گاید شخصی"
SCOPE = "device-planner:v1:11111111-1111-4111-8111-111111111111"
DATABASE = "standalone_acceptance.sqlite"
COMPANION = "LifeGuide EMULATOR FIXTURE"
GENERIC_BODY = "برای دیدن برنامهٔ شخصی، لایف‌گاید را باز کنید."
CHANNEL = "lifeguide_personal_plan_v1"
CANARY = "SYNTHETIC_PRIVATE_TASK_CANARY"
MARKER = "LG_STANDALONE_ACCEPTANCE "
MODES = {"seed", "inspect", "change", "cancel", "off"}
CHECKS = {"rawSqlAfterClose", "profilePersists", "weeklyDifferentTimes",
          "onceAndEveryTwoDays", "independentEditAndTick", "archivePersists"}
PREFERENCES = "shared_prefs/lifeguide_local_reminders_v1.xml"
UUID = r"[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}"
PID_QUERY = ("pids=$(pidof " + PACKAGE + "); code=$?; "
             "if [ \"$code\" -eq 0 ] && [ -n \"$pids\" ]; then printf PRESENT; "
             "elif [ \"$code\" -eq 1 ] && [ -z \"$pids\" ]; then printf ABSENT; "
             "else exit 2; fi")
LIMITATIONS = {name: "UNVERIFIED" for name in (
    "physicalDevice", "reboot", "Doze", "soundOrVibration", "permissionConsentUI",
    "Safari", "signedRelease", "onlineFamilyOrSynchronization")}


def _positive(value):
    return type(value) is int and value > 0


def manifest_check(apk):
    # Kept lazy so host safety tests need no APK inspection/build dependency.
    from check_standalone_apk import check
    return check(apk)


def certificate_digest(apk):
    signer = shutil.which("apksigner")
    if signer is None:
        for key in ("ANDROID_HOME", "ANDROID_SDK_ROOT"):
            root = os.environ.get(key)
            if root:
                choices = sorted((Path(root) / "build-tools").glob("*/apksigner"))
                if choices:
                    signer = str(choices[-1])
                    break
    require(signer is not None, "apksigner_required")
    try:
        result = subprocess.run([signer, "verify", "--print-certs", str(apk)],
            capture_output=True, text=True, timeout=30, check=False)
        values = re.findall(r"(?m)^(?:Signer #\d+|V[1-4](?:\.\d+)? Signer:) certificate SHA-256 digest: ([0-9a-fA-F]{64})\s*$", result.stdout)
        require(result.returncode == 0 and len(values) == 1, "apk_signature_rejected")
        return values[0].lower()
    except (OSError, subprocess.SubprocessError):
        raise AcceptanceError("apk_signature_rejected") from None


def fixture_marker(line, nonce, mode):
    require(re.fullmatch(r"[0-9a-f]{8,32}", nonce) is not None and mode in MODES,
            "invalid_fixture_request")
    if MARKER not in line:
        return None
    raw = line.split(MARKER, 1)[1]
    try:
        marker = json.loads(raw)
    except ValueError:
        if nonce in raw:
            raise AcceptanceError("invalid_fixture_marker") from None
        return None
    if not isinstance(marker, dict) or marker.get("nonce") != nonce:
        return None
    require(marker.get("mode") == mode and marker.get("syntheticDataOnly") is True
            and marker.get("database") == DATABASE, "invalid_fixture_marker")
    status = marker.get("status")
    required = {"supported", "permissionGranted", "active", "activeScope", "enabled",
                "scheduledCount", "timing", "canScheduleExactAlarms"}
    require(isinstance(status, dict) and required <= set(status), "invalid_fixture_status")
    require(status["supported"] is True and
            all(type(status[k]) is bool for k in ("permissionGranted", "active", "enabled", "canScheduleExactAlarms"))
            and type(status["scheduledCount"]) is int and status["scheduledCount"] in (0, 1)
            and status["timing"] in ("exact", "approximate")
            and status["canScheduleExactAlarms"] == (status["timing"] == "exact")
            and (re.fullmatch("device-planner:v1:" + UUID, status["activeScope"] or "") is not None
                 if status["active"] else status["activeScope"] is None)
            and (status["active"] or status["scheduledCount"] == 0), "invalid_fixture_status")
    checks = marker.get("checks")
    require(isinstance(checks, dict) and all(type(checks.get(k)) is bool for k in CHECKS & checks.keys()),
            "invalid_fixture_database_checks")
    clean = {"nonce": nonce, "mode": mode, "syntheticDataOnly": True,
             "database": DATABASE, "status": {k: status[k] for k in sorted(required)},
             "checks": {k: checks[k] for k in sorted(CHECKS & checks.keys())}}
    if "scheduledAtEpochMs" in marker:
        require(mode in ("seed", "change") and _positive(marker["scheduledAtEpochMs"]),
                "invalid_fixture_deadline")
        clean["scheduledAtEpochMs"] = marker["scheduledAtEpochMs"]
    return clean


def active_fixture_keys(output):
    keys = []
    for line in output.splitlines():
        key = line.strip()
        pieces = key.split("|")
        if len(pieces) < 2 or pieces[1] != PACKAGE:
            continue
        require(len(pieces) == 5 and pieces[0] == "0" and pieces[2] == "1" and
                re.fullmatch("lifeguide-plan:" + UUID, pieces[3]) is not None and
                re.fullmatch(r"[0-9]+", pieces[4]) is not None and key not in keys,
                "unexpected_fixture_notification")
        keys.append(key)
    require(len(keys) <= 1, "unexpected_fixture_notification")
    return keys


def check_notification_record(dump, key):
    require(active_fixture_keys(key) == [key], "invalid_fixture_notification_key")
    records = re.split(r"(?m)(?=^[ \t]*NotificationRecord\()", dump)
    matches = [r for r in records if
               re.search(r"\bkey=" + re.escape(key) + r"(?=[\s):])", r) and
               re.search(r"\bpkg=" + re.escape(PACKAGE) + r"(?=[\s)])", r)]
    require(len(matches) == 1, "fixture_notification_record_missing_or_ambiguous")
    record = matches[0]
    titles = re.findall(r"android\.title=String \(([^\n]*)\)", record)
    bodies = re.findall(r"android\.text=String \(([^\n]*)\)", record)
    require(bool(titles) and all(t == COMPANION for t in titles), "fixture_notification_title_mismatch")
    require(bool(bodies) and all(b == GENERIC_BODY for b in bodies), "fixture_notification_body_mismatch")
    require(CANARY not in record, "fixture_notification_contains_private_canary")
    require(re.search(r"(?:channel=|mId=['\"]?)" + re.escape(CHANNEL) + r"(?=['\"\s,)])", record),
            "fixture_notification_channel_mismatch")
    return {"titleMatches": True, "genericBodyMatches": True, "privateCanaryAbsent": True}


def parse_preferences(xml, *, expected_scope=None):
    """Validate the isolated synthetic native state, never publish raw XML."""
    try:
        require(len(xml) <= 32768 and "<!" not in xml, "unexpected_fixture_preferences")
        root = ET.fromstring(xml)
        require(root.tag == "map" and not root.attrib, "unexpected_fixture_preferences")
        if len(root) == 0:
            return None
        require(len(root) == 1 and root[0].tag == "string" and
                root[0].attrib == {"name": "active"} and len(root[0]) == 0, "unexpected_fixture_preferences")
        state = json.loads(root[0].text or "")
        require(isinstance(state, dict) and set(state) <= {
            "scope", "generation", "issuedAtEpochMs", "validUntilEpochMs", "reminders", "deliveryExpired", "leaseKind"}
            and re.fullmatch("device-planner:v1:" + UUID, state.get("scope", "")) is not None
            and (expected_scope is None or state["scope"] == expected_scope)
            and str(uuid.UUID(state["generation"], version=4)) == state["generation"]
            and _positive(state.get("issuedAtEpochMs")) and _positive(state.get("validUntilEpochMs"))
            and 0 < state["validUntilEpochMs"] - state["issuedAtEpochMs"] <= 31 * 86400000
            and state.get("leaseKind") == "device-planner-v1"
            and isinstance(state.get("reminders"), list) and len(state["reminders"]) <= 1,
            "unexpected_fixture_preferences")
        if "deliveryExpired" in state:
            require(type(state["deliveryExpired"]) is bool, "unexpected_fixture_preferences")
        for row in state["reminders"]:
            require(isinstance(row, dict) and set(row) <= {
                "id", "planItemId", "scheduledAtEpochMs", "companionName", "delivered"}
                and re.fullmatch(UUID, row.get("id", "")) is not None
                and re.fullmatch(UUID, row.get("planItemId", "")) is not None
                and row.get("companionName") == COMPANION and _positive(row.get("scheduledAtEpochMs"))
                and state["issuedAtEpochMs"] < row["scheduledAtEpochMs"] <= state["validUntilEpochMs"]
                and type(row.get("delivered", False)) is bool, "unexpected_fixture_preferences")
        return state
    except (ET.ParseError, ValueError, TypeError, KeyError, AttributeError):
        raise AcceptanceError("unexpected_fixture_preferences") from None


class Harness:
    def __init__(self, *, serial, user_apk, fixture_apk, allow_reset, screenshot,
                 adb=None, manifest_check=manifest_check, certificate_check=certificate_digest,
                 clock=time.monotonic, sleep=time.sleep):
        self.serial, self.user_apk, self.fixture_apk = serial, Path(user_apk), Path(fixture_apk)
        self.allow_reset, self.screenshot = allow_reset, Path(screenshot)
        self.adb, self.manifest_check, self.certificate_check = adb, manifest_check, certificate_check
        self.clock, self.sleep = clock, sleep
        self.installed = self.user_launched = self.fixture_installed = False
        self.scope = None
        self.receipt = {"schemaVersion": 1, "result": "FAIL", "syntheticDataOnly": True,
            "scope": "fresh API35 emulator; actual isolated SQLite and native notification",
            "currentPhase": "preflight", "limitations": LIMITATIONS.copy(), "checks": {}}

    def install_user(self):
        validate_serial(self.serial)
        require(self.allow_reset is True, "synthetic_emulator_reset_flag_required")
        require(self.user_apk.is_file() and self.fixture_apk.is_file(), "two_apk_files_required")
        manifests, certificates = [], []
        for apk in (self.user_apk, self.fixture_apk):
            try:
                report = self.manifest_check(apk)
                require(isinstance(report, dict) and report.get("result") == "PASS" and
                    report.get("package") == PACKAGE and report.get("label") == LABEL and
                    report.get("debuggable") is True and report.get("internetPermission") is False and
                    report.get("targetSdkVersion") == 36 and
                    re.fullmatch(r"[0-9a-f]{64}", report.get("sha256", "")) is not None,
                    "apk_manifest_rejected")
                certificate = self.certificate_check(apk)
                require(re.fullmatch(r"[0-9a-f]{64}", certificate or "") is not None, "apk_signature_rejected")
            except AcceptanceError:
                raise
            except Exception:
                raise AcceptanceError("apk_manifest_rejected") from None
            manifests.append(report)
            certificates.append(certificate)
        require(certificates[0] == certificates[1], "apk_certificates_differ")
        if self.adb is None:
            self.adb = Adb(self.serial)
        require(self.adb.command("get-state").strip() == "device", "emulator_not_ready")
        kernel = self.adb.shell("getprop", "ro.kernel.qemu").strip()
        boot = self.adb.shell("getprop", "ro.boot.qemu").strip()
        require("1" in (kernel, boot), "qemu_emulator_required")
        require(self.adb.shell("getprop", "ro.hardware").strip() in ("ranchu", "goldfish"), "android_emulator_hardware_required")
        require(re.fullmatch(r"sdk_(?:gphone|phone)[A-Za-z0-9_]*",
                self.adb.shell("getprop", "ro.product.name").strip()) is not None, "synthetic_sdk_product_required")
        require(self.adb.shell("getprop", "ro.build.version.sdk").strip() == "35", "api_35_required")
        require(not self.adb.shell("pm", "list", "packages", PACKAGE).strip(), "fresh_emulator_required_package_already_present")
        output = self.adb.command("install", str(self.user_apk))
        require("Success" in output.splitlines() and "Failure" not in output and "Error" not in output,
                "user_apk_install_failed")
        self.installed = True
        self.receipt["apks"] = {role: {name: report[name] for name in (
            "sha256", "package", "label", "debuggable", "internetPermission", "targetSdkVersion")}
            for role, report in zip(("user", "fixtureNeverDistribute"), manifests)}
        self.receipt["certificateSha256"] = certificates[0]
        self.receipt["checks"]["emulatorAndFreshInstallGates"] = "PASS"

    def _ready(self):
        require(self.installed, "package_not_installed_by_this_runner")

    def process_state(self):
        self._ready()
        state = self.adb.shell("sh", "-c", PID_QUERY).strip()
        require(state in ("PRESENT", "ABSENT"), "fixture_process_query_failed")
        return state

    def process_dead(self, *, before=None):
        self._ready()
        self.receipt.pop("processExit", None)
        self.adb.shell("input", "keyevent", "KEYCODE_HOME")
        until, attempts = self.clock() + 10, 0
        while True:
            self.adb.shell("am", "kill", PACKAGE)
            attempts += 1
            state = self.process_state()
            self.receipt["lastProcessState"] = state
            if state == "ABSENT":
                if before is not None:
                    require(self.device_epoch_ms() + 1000 < before, "process_absence_missed_alarm_deadline")
                self.receipt["processExit"] = {"confirmedAbsent": True, "ordinaryKillAttempts": attempts}
                return
            require(self.clock() < until, "fixture_process_did_not_exit")
            self.sleep(0.25)

    def first_user_launch(self):
        self._ready()
        require(not self.fixture_installed, "fixture_cannot_prove_user_first_launch")
        self.receipt["currentPhase"] = "user_first_launch"
        output = self.adb.shell("am", "start", "-W", "-f", "0x10008000", "-n", COMPONENT)
        require("Error" not in output and "Exception" not in output, "user_activity_launch_failed")
        self.sleep(3)
        require(self.process_state() == "PRESENT", "user_first_launch_process_not_alive")
        # No UI interaction or profile creation occurs before this screenshot.
        try:
            result = subprocess.run(["adb", "-s", self.serial, "exec-out", "screencap", "-p"],
                capture_output=True, timeout=30, check=False)
            png = result.stdout
            require(result.returncode == 0 and 24 <= len(png) <= 16 * 1024 * 1024 and
                png[:8] == b"\x89PNG\r\n\x1a\n" and png[12:16] == b"IHDR", "user_screenshot_failed")
            width, height = struct.unpack(">II", png[16:24])
            require(100 <= width <= 4096 and 100 <= height <= 4096, "user_screenshot_failed")
            self.screenshot.parent.mkdir(parents=True, exist_ok=True)
            self.screenshot.write_bytes(png)
        except (OSError, subprocess.SubprocessError):
            raise AcceptanceError("user_screenshot_failed") from None
        ui = self.adb.shell("uiautomator", "dump", "/dev/tty", allow_failure=True)
        require(not any(text in ui for text in ("https://", "http://", "نشانی API", "آدرس API")),
                "user_launch_url_prompt_detected")
        self.receipt["userFirstLaunch"] = {"processAlive": True,
            "ordinaryLaunchNoExtras": True, "screenshotSha256": hashlib.sha256(png).hexdigest(),
            "screenshotFile": self.screenshot.name, "urlPromptDetected": False,
            "localWelcomeText": "PASS" if "جای کوچکی برای برنامه‌های تو" in ui else "UNVERIFIED"}
        self.user_launched = True
        self.receipt["checks"]["actualUserApkFirstLaunchScreenshot"] = "PASS"

    def install_fixture(self):
        self._ready()
        require(self.user_launched, "user_first_launch_not_verified")
        require(not self.fixture_installed, "fixture_already_installed")
        self.process_dead()
        output = self.adb.command("install", "-r", str(self.fixture_apk))
        require("Success" in output.splitlines() and "Failure" not in output and "Error" not in output,
                "owned_fixture_upgrade_failed")
        self.fixture_installed = True
        self.adb.shell("pm", "grant", PACKAGE, "android.permission.POST_NOTIFICATIONS")
        self.adb.shell("cmd", "appops", "set", PACKAGE, "SCHEDULE_EXACT_ALARM", "allow")
        self.receipt["checks"]["fixtureUpgradePreservesFreshUserData"] = "PASS"

    def launch(self, mode):
        require(self.fixture_installed and mode in MODES, "fixture_not_ready")
        self.receipt["currentPhase"] = "before_launch_" + mode
        self.process_dead()
        nonce = secrets.token_hex(8)
        route = "/" + mode + "?nonce=" + nonce
        output = self.adb.shell("am", "start", "-W", "-f", "0x10008000",
            "-n", COMPONENT, "--es", "route", route)
        require("Error" not in output and "Exception" not in output, "fixture_activity_launch_failed")
        self.receipt["currentPhase"] = "waiting_" + mode + "_marker"
        until = self.clock() + 30
        while True:
            logs = self.adb.command("logcat", "-d", "-v", "brief", "-s", "flutter:I")
            for line in logs.splitlines():
                marker = fixture_marker(line, nonce, mode)
                if marker is not None:
                    self.receipt["currentPhase"] = "after_" + mode + "_marker"
                    return marker
            require(self.clock() < until, "fixture_marker_timeout")
            self.sleep(0.5)

    def device_epoch_ms(self):
        value = self.adb.shell("date", "+%s").strip()
        require(re.fullmatch(r"[0-9]{10,}", value) is not None, "emulator_clock_unavailable")
        return int(value) * 1000

    def align_to_minute(self):
        # Product records have minute precision. At second 10..15, the next
        # whole minute is genuinely 45..50 seconds away, without a test clock.
        until = self.clock() + 65
        while True:
            second = self.device_epoch_ms() // 1000 % 60
            if 10 <= second <= 15:
                return
            require(self.clock() < until, "emulator_clock_alignment_timeout")
            self.sleep(min(1, (70 - second) % 60 or 1))

    def preferences(self):
        script = "if [ -f " + PREFERENCES + " ]; then cat " + PREFERENCES + "; else printf '<map/>'; fi"
        return parse_preferences(self.adb.shell("run-as", PACKAGE, "sh", "-c", script), expected_scope=self.scope)

    def active_keys(self):
        return active_fixture_keys(self.adb.shell("cmd", "notification", "list"))

    def assert_status(self, marker, *, active, count):
        status = marker["status"]
        require(status["permissionGranted"] is True and status["active"] is active and
                status["enabled"] is active and
                status["scheduledCount"] == count and status["timing"] == "exact" and
                status["canScheduleExactAlarms"] is True, "fixture_status_assertion_failed")
        if active:
            if self.scope is None:
                self.scope = status["activeScope"]
            require(status["activeScope"] == self.scope, "fixture_scope_changed")

    def assert_database(self, marker, names):
        require(all(marker["checks"].get(name) is True for name in names), "real_sqlite_assertion_failed")
        for name in names:
            self.receipt["checks"][name] = "PASS"

    def assert_scheduled(self, marker):
        self.assert_status(marker, active=True, count=1)
        at = marker.get("scheduledAtEpochMs")
        require(_positive(at) and 30000 < at - self.device_epoch_ms() <= 55000,
                "real_record_not_near_45_seconds")
        state = self.preferences()
        require(state is not None and len(state["reminders"]) == 1 and
            state["reminders"][0]["scheduledAtEpochMs"] == at and
            not state["reminders"][0].get("delivered", False), "real_record_schedule_not_persisted")
        require(not self.active_keys(), "unexpected_fixture_notification_before_deadline")
        return at, state

    def wait_for_post(self, at):
        until = self.clock() + max(0, (at - self.device_epoch_ms()) / 1000) + 30
        while True:
            keys = self.active_keys()
            if keys:
                require(self.device_epoch_ms() + 1000 >= at, "fixture_notification_posted_before_deadline")
                return keys[0]
            require(self.clock() < until, "fixture_notification_not_posted")
            self.sleep(1)

    def assert_no_post_through(self, at):
        until = self.clock() + max(0, (at - self.device_epoch_ms()) / 1000) + 5
        while True:
            require(not self.active_keys(), "canceled_fixture_notification_posted")
            if self.clock() >= until:
                return
            self.sleep(min(1, until - self.clock()))

    def run(self):
        self.install_user()
        self.first_user_launch()
        self.install_fixture()
        self.align_to_minute()
        seeded = self.launch("seed")
        self.assert_database(seeded, {"rawSqlAfterClose", "profilePersists", "weeklyDifferentTimes", "onceAndEveryTwoDays"})
        at, scheduled = self.assert_scheduled(seeded)
        self.process_dead(before=at)
        require(self.preferences() == scheduled and not self.active_keys(), "alarm_preceded_process_absence_proof")
        self.receipt["checks"]["processAbsentBeforeAlarm"] = "PASS"
        key = self.wait_for_post(at)
        require(key.split("|")[3] == "lifeguide-plan:" + scheduled["reminders"][0]["id"], "notification_not_from_sqlite_record")
        delivered = self.preferences()
        require(delivered is not None and delivered["generation"] == scheduled["generation"] and
            len(delivered["reminders"]) == 1 and delivered["reminders"][0].get("delivered") is True,
            "native_delivered_marker_missing")
        self.receipt["checks"]["notificationAfterProcessDeath"] = "PASS"
        self.receipt["checks"]["notificationContent"] = check_notification_record(
            self.adb.shell("dumpsys", "notification", "--noredact"), key)
        inspected = self.launch("inspect")
        self.assert_status(inspected, active=True, count=0)
        self.assert_database(inspected, {"rawSqlAfterClose", "profilePersists", "weeklyDifferentTimes", "onceAndEveryTwoDays"})
        require(self.preferences() == delivered and self.active_keys() == [key], "inspect_changed_delivered_state_or_post")
        self.receipt["checks"]["relaunchReadOnlyPreservesNativeGeneration"] = "PASS"
        self.align_to_minute()
        changed = self.launch("change")
        self.assert_database(changed, {"rawSqlAfterClose", "profilePersists", "independentEditAndTick"})
        canceled_at, _ = self.assert_scheduled(changed)
        canceled = self.launch("cancel")
        self.assert_status(canceled, active=True, count=0)
        self.assert_database(canceled, {"rawSqlAfterClose", "archivePersists", "independentEditAndTick"})
        require(self.device_epoch_ms() + 1000 < canceled_at, "fixture_cancellation_missed_deadline")
        state = self.preferences()
        require(state is not None and state["reminders"] == [] and not self.active_keys(), "archive_did_not_cancel_native_alarm")
        self.process_dead(before=canceled_at)
        self.assert_no_post_through(canceled_at)
        self.receipt["checks"]["archiveBeforeDeadlineHasNoOSPost"] = "PASS"
        off = self.launch("off")
        self.assert_status(off, active=False, count=0)
        require(self.preferences() is None and not self.active_keys(), "off_did_not_clear_native_state")
        self.receipt["checks"]["offClearsNativeState"] = "PASS"
        self.receipt["currentPhase"], self.receipt["result"] = "complete", "PASS"
        return self.receipt


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--user-apk", required=True, type=Path)
    parser.add_argument("--fixture-apk", required=True, type=Path)
    parser.add_argument("--serial", required=True)
    parser.add_argument("--allow-synthetic-emulator-reset", action="store_true")
    parser.add_argument("--output", required=True, type=Path)
    options = parser.parse_args(argv)
    harness = Harness(serial=options.serial, user_apk=options.user_apk,
        fixture_apk=options.fixture_apk, allow_reset=options.allow_synthetic_emulator_reset,
        screenshot=options.output.with_name("standalone-user-first-launch.png"))
    try:
        harness.run()
    except AcceptanceError as error:
        harness.receipt["error"] = str(error)
    except Exception:
        harness.receipt["error"] = "unexpected_acceptance_failure"
    options.output.parent.mkdir(parents=True, exist_ok=True)
    options.output.write_text(json.dumps(harness.receipt, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"result": harness.receipt["result"], "error": harness.receipt.get("error")}))
    return 0 if harness.receipt["result"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
