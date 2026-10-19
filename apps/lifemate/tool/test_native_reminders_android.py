#!/usr/bin/env python3
"""Run synthetic native reminder acceptance on a fresh API 35 Android emulator.

Build only the debug tool/native_reminder_fixture.dart entry point with
--dart-define=LG_NATIVE_REMINDER_FIXTURE=true. Never distribute that APK.
This runner never selects a device implicitly or removes an existing install.
Only sanitized assertions are written; adb output stays in memory.
"""
import argparse
import json
import re
import secrets
import shlex
import subprocess
import time
import uuid
import xml.etree.ElementTree as ET
from pathlib import Path

import check_apk_manifest

PACKAGE = "ir.lifeguide.app"
SCOPE = "emulator-fixture-v1|11111111-1111-4111-8111-111111111111"
PLAN = "22222222-2222-4222-8222-222222222222"
REMINDER = "33333333-3333-4333-8333-333333333333"
COMPANION = "LifeGuide EMULATOR FIXTURE"
GENERIC_BODY = "برای دیدن برنامهٔ شخصی، لایف‌گاید را باز کنید."
CHANNEL = "lifeguide_personal_plan_v1"
MARKER = "LG_NATIVE_REMINDER_FIXTURE "
CANARY = "SYNTHETIC_PRIVATE_TASK_CANARY"
PREFERENCES = "shared_prefs/lifeguide_local_reminders_v1.xml"
# A missing process makes pidof exit 1. Preserve transport/remote failures, and
# require the explicit ABSENT token rather than interpreting empty output.
PID_QUERY = ("pids=$(pidof " + PACKAGE + "); code=$?; "
             "if [ \"$code\" -eq 0 ] && [ -n \"$pids\" ]; then printf PRESENT; "
             "elif [ \"$code\" -eq 1 ] && [ -z \"$pids\" ]; then printf ABSENT; "
             "else exit 2; fi")
MODES = {"schedule", "inspect", "suppress", "off"}
LIMITATIONS = {
    name: "UNVERIFIED" for name in (
        "physicalDevice", "reboot", "Doze", "soundOrVibration",
        "permissionConsentUI", "realServerAcknowledgement", "signedRelease",
    )
}


class AcceptanceError(Exception):
    """An intentionally sanitized error code; never wrap raw device output."""


def require(condition, code):
    if not condition:
        raise AcceptanceError(code)


def validate_serial(serial):
    require(isinstance(serial, str) and
            re.fullmatch(r"emulator-[0-9]{4,5}", serial) is not None,
            "explicit_emulator_serial_required")
    port = int(serial.split("-")[1])
    require(1024 <= port <= 65534 and port % 2 == 0,
            "invalid_emulator_console_port")


class Adb:
    def __init__(self, serial):
        validate_serial(serial)
        self.serial = serial

    def command(self, *parts, allow_failure=False):
        try:
            result = subprocess.run(
                ["adb", "-s", self.serial, *parts], capture_output=True,
                text=True, encoding="utf-8", errors="replace", timeout=30,
                check=False)
        except (OSError, subprocess.SubprocessError):
            raise AcceptanceError("adb_command_unavailable") from None
        require(allow_failure or result.returncode == 0, "adb_command_failed")
        return result.stdout

    def shell(self, *parts, allow_failure=False):
        # adb shell uses a remote shell even when the host subprocess does not.
        return self.command("shell", " ".join(shlex.quote(str(p)) for p in parts),
                            allow_failure=allow_failure)


def active_fixture_keys(output):
    """Parse only `cmd notification list` active keys, never dumpsys history."""
    found = []
    for line in output.splitlines():
        key = line.strip()
        pieces = key.split("|")
        if len(pieces) < 2 or pieces[1] != PACKAGE:
            continue
        require(len(pieces) == 5 and pieces[0] == "0" and pieces[2] == "1" and
                pieces[3] == "lifeguide-plan:" + REMINDER and
                re.fullmatch(r"[0-9]+", pieces[4]) is not None,
                "unexpected_fixture_notification")
        require(key not in found, "duplicate_fixture_notification")
        found.append(key)
    require(len(found) <= 1, "unexpected_fixture_notification")
    return found


def _notification_record(dump, key):
    require(active_fixture_keys(key) == [key], "invalid_fixture_notification_key")
    records = re.split(r"(?m)(?=^[ \t]*NotificationRecord\()", dump)
    matching = [record for record in records
                if re.search(r"\bkey=" + re.escape(key) + r"(?=[\s):])", record)
                and re.search(r"\bpkg=" + re.escape(PACKAGE) + r"(?=[\s)])", record)]
    require(len(matching) == 1, "fixture_notification_record_missing_or_ambiguous")
    return matching[0]


def check_notification_record(dump, key, *, require_channel=False):
    record = _notification_record(dump, key)
    titles = re.findall(r"android\.title=String \(([^\n]*)\)", record)
    bodies = re.findall(r"android\.text=String \(([^\n]*)\)", record)
    require(bool(titles) and titles[0] == COMPANION,
            "fixture_notification_title_mismatch")
    require(bool(bodies) and all(body == GENERIC_BODY for body in bodies),
            "fixture_notification_body_mismatch")
    require(CANARY not in record, "fixture_notification_contains_private_canary")
    if require_channel:
        require(re.search(r"(?:channel=|mId=['\"]?)" + re.escape(CHANNEL) +
                          r"(?=['\"\s,)])", record) is not None,
                "fixture_notification_channel_mismatch")
    return {"titleMatches": True, "genericBodyMatches": True,
            "privateCanaryAbsent": True}


def _integer(value):
    return type(value) is int and value > 0


def fixture_marker(line, nonce, mode):
    require(re.fullmatch(r"[0-9a-f]{8,32}", nonce) is not None and mode in MODES,
            "invalid_fixture_request")
    if MARKER not in line:
        return None
    raw = line.split(MARKER, 1)[1]
    try:
        marker = json.loads(raw)
    except (ValueError, TypeError):
        if nonce in raw:
            raise AcceptanceError("invalid_fixture_marker") from None
        return None
    if not isinstance(marker, dict) or marker.get("nonce") != nonce:
        return None
    require(marker.get("mode") == mode, "unexpected_fixture_mode")
    require(marker.get("simulatedServerAcknowledgement") is True,
            "fixture_simulation_label_missing")
    status = marker.get("status")
    required_status = {"supported", "permissionGranted", "active", "activeScope",
                       "scheduledCount", "timing", "canScheduleExactAlarms"}
    require(isinstance(status, dict) and required_status <= set(status),
            "invalid_fixture_status")
    require(status.get("supported") is True and
            all(type(status.get(name)) is bool for name in
                ("permissionGranted", "active", "canScheduleExactAlarms")) and
            type(status.get("scheduledCount")) is int and
            status["scheduledCount"] in (0, 1) and
            status.get("timing") in ("exact", "approximate"),
            "invalid_fixture_status")
    require(status["canScheduleExactAlarms"] == (status["timing"] == "exact"),
            "invalid_fixture_status")
    require(status.get("activeScope") == (SCOPE if status["active"] else None),
            "unexpected_fixture_scope")
    require(status["active"] or status["scheduledCount"] == 0,
            "invalid_fixture_status")
    clean = {"nonce": nonce, "mode": mode,
             "simulatedServerAcknowledgement": True,
             "status": {name: status[name] for name in (
                 "supported", "permissionGranted", "active", "activeScope",
                 "scheduledCount", "timing", "canScheduleExactAlarms")}}
    if "scheduledAtEpochMs" in marker:
        require(mode == "schedule" and _integer(marker["scheduledAtEpochMs"]),
                "invalid_fixture_deadline")
        clean["scheduledAtEpochMs"] = marker["scheduledAtEpochMs"]
    return clean


def parse_preferences(xml):
    """Accept only the known synthetic native state; do not return private data."""
    try:
        require(len(xml) <= 32768 and "<!" not in xml,
                "unexpected_fixture_preferences")
        root = ET.fromstring(xml)
        require(root.tag == "map" and not root.attrib,
                "unexpected_fixture_preferences")
        if len(root) == 0:
            return None
        require(len(root) == 1 and root[0].tag == "string" and
                root[0].attrib == {"name": "active"} and len(root[0]) == 0,
                "unexpected_fixture_preferences")
        state = json.loads(root[0].text or "")
        require(isinstance(state, dict) and set(state) <= {
            "scope", "generation", "issuedAtEpochMs", "validUntilEpochMs",
            "reminders", "deliveryExpired"}, "unexpected_fixture_preferences")
        require(state.get("scope") == SCOPE and
                str(uuid.UUID(state["generation"], version=4)) == state["generation"] and
                _integer(state.get("issuedAtEpochMs")) and
                _integer(state.get("validUntilEpochMs")) and
                0 < state["validUntilEpochMs"] - state["issuedAtEpochMs"] <= 600000 and
                isinstance(state.get("reminders"), list) and len(state["reminders"]) <= 1,
                "unexpected_fixture_preferences")
        if "deliveryExpired" in state:
            require(type(state["deliveryExpired"]) is bool,
                    "unexpected_fixture_preferences")
        for row in state["reminders"]:
            require(isinstance(row, dict) and set(row) <= {
                "id", "planItemId", "scheduledAtEpochMs", "companionName", "delivered"} and
                row.get("id") == REMINDER and row.get("planItemId") == PLAN and
                row.get("companionName") == COMPANION and
                _integer(row.get("scheduledAtEpochMs")) and
                state["issuedAtEpochMs"] < row["scheduledAtEpochMs"] <= state["validUntilEpochMs"] and
                type(row.get("delivered", False)) is bool,
                "unexpected_fixture_preferences")
        return state
    except (ET.ParseError, ValueError, TypeError, KeyError, AttributeError):
        raise AcceptanceError("unexpected_fixture_preferences") from None


class Harness:
    def __init__(self, *, serial, apk, allow_reset, adb=None,
                 manifest_check=check_apk_manifest.check,
                 clock=time.monotonic, sleep=time.sleep):
        self.serial, self.apk, self.allow_reset = serial, Path(apk), allow_reset
        self.adb = adb
        self.manifest_check = manifest_check
        self.clock, self.sleep = clock, sleep
        self.installed = False
        self.receipt = {"schemaVersion": 1, "result": "FAIL",
                        "scope": "synthetic API 35 emulator only",
                        "simulatedServerAcknowledgement": True,
                        "limitations": LIMITATIONS.copy(), "checks": {}}

    def install_fixture(self):
        validate_serial(self.serial)
        require(self.allow_reset is True, "synthetic_emulator_reset_flag_required")
        require(self.apk.is_file(), "apk_file_required")
        try:
            manifest = self.manifest_check(self.apk, "debug")
            require(isinstance(manifest, dict) and manifest.get("result") == "PASS" and
                    manifest.get("mode") == "debug" and manifest.get("package") == PACKAGE and
                    manifest.get("debuggable") is True and
                    type(manifest.get("targetSdkVersion")) is int and
                    manifest["targetSdkVersion"] == 36 and
                    re.fullmatch(r"[0-9a-f]{64}", manifest.get("sha256", "")) is not None,
                    "apk_manifest_rejected")
        except Exception:
            raise AcceptanceError("apk_manifest_rejected") from None
        if self.adb is None:
            self.adb = Adb(self.serial)
        require(self.adb.command("get-state").strip() == "device", "emulator_not_ready")
        kernel = self.adb.shell("getprop", "ro.kernel.qemu").strip()
        boot = self.adb.shell("getprop", "ro.boot.qemu").strip()
        require("1" in (kernel, boot), "qemu_emulator_required")
        require(self.adb.shell("getprop", "ro.hardware").strip() in ("ranchu", "goldfish"),
                "android_emulator_hardware_required")
        product = self.adb.shell("getprop", "ro.product.name").strip()
        require(re.fullmatch(r"sdk_(?:gphone|phone)[A-Za-z0-9_]*", product) is not None,
                "synthetic_sdk_product_required")
        require(self.adb.shell("getprop", "ro.build.version.sdk").strip() == "35",
                "api_35_required")
        require(not self.adb.shell("pm", "list", "packages", PACKAGE).strip(),
                "fresh_emulator_required_package_already_present")
        installed = self.adb.command("install", str(self.apk))
        require("Failure" not in installed and "Error" not in installed,
                "fixture_install_failed")
        self.installed = True
        self.adb.shell("pm", "grant", PACKAGE, "android.permission.POST_NOTIFICATIONS")
        self.adb.shell("cmd", "appops", "set", PACKAGE, "SCHEDULE_EXACT_ALARM", "allow")
        self.receipt["apk"] = {name: manifest[name] for name in
                               ("sha256", "package", "debuggable", "targetSdkVersion")}
        self.receipt["checks"]["emulatorAndFreshInstallGates"] = "PASS"

    def _ready(self):
        require(self.installed, "fixture_not_installed_by_this_runner")

    def process_dead(self):
        self._ready()
        self.adb.shell("input", "keyevent", "KEYCODE_HOME")
        self.adb.shell("am", "kill", PACKAGE)
        until = self.clock() + 10
        while True:
            state = self.adb.shell("sh", "-c", PID_QUERY).strip()
            require(state in ("PRESENT", "ABSENT"), "fixture_process_query_failed")
            if state == "ABSENT":
                return True
            require(self.clock() < until, "fixture_process_did_not_exit")
            self.sleep(0.25)

    def launch(self, mode):
        self._ready()
        require(mode in MODES, "invalid_fixture_request")
        self.process_dead()
        nonce = secrets.token_hex(8)
        route = "/" + mode + "?nonce=" + nonce
        if mode == "schedule":
            route += "&delay=45"
        output = self.adb.shell("am", "start", "-W", "-n", PACKAGE + "/.MainActivity",
                                "--es", "route", route)
        require("Error" not in output and "Exception" not in output,
                "fixture_activity_launch_failed")
        until = self.clock() + 30
        while True:
            logs = self.adb.command("logcat", "-d", "-v", "brief", "-s", "flutter:I")
            for line in logs.splitlines():
                marker = fixture_marker(line, nonce, mode)
                if marker is not None:
                    return marker
            require(self.clock() < until, "fixture_marker_timeout")
            self.sleep(0.5)

    def preferences(self):
        self._ready()
        script = ("if [ -f " + PREFERENCES + " ]; then cat " + PREFERENCES +
                  "; else printf '<map/>'; fi")
        return parse_preferences(self.adb.shell("run-as", PACKAGE, "sh", "-c", script))

    def active_keys(self):
        self._ready()
        return active_fixture_keys(self.adb.shell("cmd", "notification", "list"))

    def device_epoch_ms(self):
        output = self.adb.shell("date", "+%s").strip()
        require(re.fullmatch(r"[0-9]{10,}", output) is not None, "emulator_clock_unavailable")
        return int(output) * 1000

    def assert_status(self, marker, *, active, count, exact):
        status = marker["status"]
        require(status["permissionGranted"] is True and status["active"] is active and
                status["scheduledCount"] == count and
                status["canScheduleExactAlarms"] is exact and
                status["timing"] == ("exact" if exact else "approximate"),
                "fixture_status_assertion_failed")

    def scheduled(self, *, exact):
        marker = self.launch("schedule")
        self.assert_status(marker, active=True, count=1, exact=exact)
        at = marker.get("scheduledAtEpochMs")
        require(_integer(at) and 15000 < at - self.device_epoch_ms() <= 47000,
                "fixture_schedule_not_future_45_seconds")
        state = self.preferences()
        require(state is not None and len(state["reminders"]) == 1 and
                state["reminders"][0]["scheduledAtEpochMs"] == at and
                state["reminders"][0].get("delivered", False) is False,
                "fixture_schedule_not_persisted")
        require(self.active_keys() == [], "unexpected_fixture_notification_before_deadline")
        return at, state

    def wait_for_post(self, at):
        until = self.clock() + max(0, (at - self.device_epoch_ms()) / 1000) + 30
        while True:
            keys = self.active_keys()
            if keys:
                require(self.device_epoch_ms() + 1000 >= at,
                        "fixture_notification_posted_before_deadline")
                return keys[0]
            require(self.clock() < until, "fixture_notification_not_posted")
            self.sleep(1)

    def assert_no_post_through(self, at):
        # Check throughout the interval, not only a final snapshot.
        remaining = max(0, (at - self.device_epoch_ms()) / 1000) + 5
        until = self.clock() + remaining
        while True:
            require(self.active_keys() == [], "canceled_fixture_notification_posted")
            if self.clock() >= until:
                return
            self.sleep(min(1, until - self.clock()))

    def run(self):
        self.install_fixture()
        checks = self.receipt["checks"]
        initial = self.launch("inspect")
        self.assert_status(initial, active=False, count=0, exact=True)
        require(self.preferences() is None and not self.active_keys(),
                "fresh_inspect_created_native_state")
        checks["inspectDoesNotActivate"] = "PASS"

        at, scheduled = self.scheduled(exact=True)
        self.process_dead()
        checks["processAbsentBeforeAlarm"] = "PASS"
        key = self.wait_for_post(at)
        delivered = self.preferences()
        require(delivered is not None and delivered["generation"] == scheduled["generation"] and
                len(delivered["reminders"]) == 1 and
                delivered["reminders"][0].get("delivered") is True,
                "native_delivered_marker_missing")
        checks["notificationAfterProcessDeath"] = "PASS"
        checks["notificationContent"] = check_notification_record(
            self.adb.shell("dumpsys", "notification", "--noredact"), key,
            require_channel=True)
        checks["notificationChannel"] = CHANNEL

        inspected = self.launch("inspect")
        self.assert_status(inspected, active=True, count=0, exact=True)
        require(self.preferences() == delivered and self.active_keys() == [key],
                "inspect_changed_delivered_state_or_post")
        checks["relaunchPreservesDeliveredStateAndPost"] = "PASS"

        suppressed = self.launch("suppress")
        self.assert_status(suppressed, active=True, count=0, exact=True)
        state = self.preferences()
        require(state is not None and state["reminders"] == [] and not self.active_keys(),
                "suppress_did_not_clear_delivered_post")
        checks["suppressClearsDeliveredPost"] = "PASS"

        canceled_at, _ = self.scheduled(exact=True)
        suppressed = self.launch("suppress")
        self.assert_status(suppressed, active=True, count=0, exact=True)
        require(self.device_epoch_ms() < canceled_at, "fixture_cancellation_missed_deadline")
        state = self.preferences()
        require(state is not None and state["reminders"] == [],
                "fixture_cancellation_not_persisted")
        self.process_dead()
        self.assert_no_post_through(canceled_at)
        checks["cancelBeforeDeadlineHasNoOSPost"] = "PASS"

        self.adb.shell("cmd", "appops", "set", PACKAGE, "SCHEDULE_EXACT_ALARM", "deny")
        self.scheduled(exact=False)
        checks["deniedExactAccessReportsApproximate"] = "PASS"
        checks["approximateAlarmDeliveryTiming"] = "UNVERIFIED"
        off = self.launch("off")
        self.assert_status(off, active=False, count=0, exact=False)
        require(self.preferences() is None and not self.active_keys(),
                "off_did_not_clear_native_state_and_posts")
        checks["offClearsNativeStateAndPosts"] = "PASS"
        self.receipt["result"] = "PASS"
        return self.receipt


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--serial", required=True)
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--allow-synthetic-emulator-reset", action="store_true")
    parser.add_argument("--output", type=Path)
    options = parser.parse_args(argv)
    harness = Harness(serial=options.serial, apk=options.apk,
                      allow_reset=options.allow_synthetic_emulator_reset)
    try:
        receipt = harness.run()
    except AcceptanceError as error:
        receipt = harness.receipt
        receipt["error"] = str(error)
    serialized = json.dumps(receipt, ensure_ascii=False, indent=2) + "\n"
    if options.output:
        options.output.parent.mkdir(parents=True, exist_ok=True)
        options.output.write_text(serialized, encoding="utf-8")
    print(serialized, end="")
    return 0 if receipt["result"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
