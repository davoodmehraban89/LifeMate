#!/usr/bin/env python3
"""Synthetic-only recovery rehearsal on an explicitly selected fresh API35 AVD.

Never point this tool at an owner phone, owner data or owner signing key. Only
the exact delivered original and two explicitly marked debug QA APKs qualify.
No uninstall, clear-data, force-stop, root, permission grant or source checkpoint.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import selectors
import shlex
import sqlite3
import struct
import subprocess
import sys
import tempfile
import time
import xml.etree.ElementTree as ET

from test_native_reminders_android import Adb, AcceptanceError, require, validate_serial
from test_standalone_android import certificate_digest
from check_standalone_apk import check as original_manifest_check
from check_personal_recovery_apk import check as qa_manifest_check

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))
from scripts.personal_recovery.archive import open_archive, seal
from scripts.personal_recovery.common import FIXTURE_APPLICATION_ID, MAX_PAYLOAD_BYTES, RecoveryError
from scripts.personal_recovery.files import publish_new, read_bounded
from scripts.personal_recovery.snapshot import create_sample_database, database_from_snapshot, export_fixture

ORIGINAL = 'ir.lifeguide.app.device'
QA = 'ir.lifeguide.app.personal'
ORIGINAL_SHA = 'c24ff6e75a987945399b0d96129f5d1a72525fa0270f31b0c481f9780f84db8e'
ORIGINAL_CERT = '4ef990d647fc98ac41113d5dbe7ee476ba80bf95b71b5f219b7863fa95263391'
DATABASE = 'databases/lifeguide_standalone_v1.sqlite'
PROFILE = 'Fictional آزمایشی'
CHOICE = 'shared_prefs/lifeguide_device_planner_reminders_v1.xml'
REMINDERS = 'shared_prefs/lifeguide_local_reminders_v1.xml'
TABLE_ORDER = {'local_profiles': 'singleton', 'local_plans': 'id',
               'local_weekly_slots': 'plan_id,weekday', 'local_occurrences': 'id'}
LIMITATIONS = {name: 'UNVERIFIED' for name in (
    'physicalDevice', 'Windows', 'USB', 'ownerSigningKey', 'ownerData',
    'originalNotificationsEnabled', 'Doze', 'reboot', 'soundOrVibration',
    'powerLossOrFullDisk', 'distributionApk')}


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def binary_adb(serial, remote, data=None):
    """Bound both pipes while keeping SQLite/PNG bytes out of text decoding/logs."""
    validate_serial(serial)
    require(data is None or isinstance(data, bytes) and len(data) <= MAX_PAYLOAD_BYTES,
            'binary_input_limit')
    process = None
    try:
        process = subprocess.Popen(['adb', '-s', serial, 'exec-out', remote],
            stdin=subprocess.PIPE if data is not None else subprocess.DEVNULL,
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        result, sent = bytearray(), 0
        with selectors.DefaultSelector() as poller:
            os.set_blocking(process.stdout.fileno(), False)
            poller.register(process.stdout, selectors.EVENT_READ, 'read')
            if data:
                os.set_blocking(process.stdin.fileno(), False)
                poller.register(process.stdin, selectors.EVENT_WRITE, 'write')
            elif data is not None:
                process.stdin.close()
            deadline = time.monotonic() + 30
            while poller.get_map():
                require(time.monotonic() < deadline, 'binary_adb_timeout')
                for key, _ in poller.select(0.2):
                    if key.data == 'read':
                        chunk = os.read(key.fd, min(65536, MAX_PAYLOAD_BYTES + 1 - len(result)))
                        if not chunk:
                            poller.unregister(key.fileobj)
                        else:
                            result.extend(chunk)
                            require(len(result) <= MAX_PAYLOAD_BYTES, 'binary_output_limit')
                    else:
                        sent += os.write(key.fd, data[sent:sent + 65536])
                        if sent == len(data):
                            poller.unregister(key.fileobj)
                            process.stdin.close()
            require(process.wait(timeout=max(0.01, deadline - time.monotonic())) == 0,
                    'binary_adb_failed')
            return bytes(result)
    except (OSError, subprocess.SubprocessError):
        raise AcceptanceError('binary_adb_failed') from None
    finally:
        if process is not None:
            if process.poll() is None:
                process.kill()
            process.wait()
            for pipe in (process.stdin, process.stdout):
                if pipe is not None:
                    pipe.close()


def notification_preferences_off(xml, *, choice):
    try:
        require(isinstance(xml, str) and len(xml) <= 32768 and '<!' not in xml,
                'notification_state_not_off')
        root = ET.fromstring(xml)
        require(root.tag == 'map' and not root.attrib and not (root.text or '').strip(),
                'notification_state_not_off')
        if len(root) == 0:
            return True
        require(choice and len(root) == 1 and root[0].tag == 'boolean' and
                root[0].attrib == {'name': 'enabled', 'value': 'false'} and
                len(root[0]) == 0 and not (root[0].text or '').strip() and
                not (root[0].tail or '').strip(), 'notification_state_not_off')
        return True
    except (ET.ParseError, TypeError, ValueError):
        raise AcceptanceError('notification_state_not_off') from None


def normalized_snapshot(source, destination):
    """Normalize only a private host copy of a closed, sidecar-free owned DB.

    Android may leave a WAL-mode header after its last close without WAL/SHM.
    Immutable read-only backup reads that complete main file without touching it.
    DELETE journaling is selected exclusively on the separate host test copy.
    """
    source, destination = Path(source), Path(destination)
    before = read_bounded(source, MAX_PAYLOAD_BYTES)
    require(before[:16] == b'SQLite format 3\0' and len(before) >= 100,
            'captured_database_invalid')
    require(all(not Path(str(source) + suffix).exists() for suffix in ('-wal', '-shm', '-journal')),
            'host_source_sidecar_present')
    publish_new(destination, b'')
    try:
        with sqlite3.connect(source.resolve().as_uri() + '?mode=ro&immutable=1', uri=True) as src:
            require(src.execute('PRAGMA application_id').fetchone() == (FIXTURE_APPLICATION_ID,)
                    and src.execute('PRAGMA user_version').fetchone() == (1,),
                    'synthetic_database_marker_required')
            with sqlite3.connect(destination) as dst:
                src.backup(dst)
                require(dst.execute('PRAGMA journal_mode=DELETE').fetchone() == ('delete',),
                        'host_copy_normalization_failed')
        return export_fixture(destination)
    finally:
        require(read_bounded(source, MAX_PAYLOAD_BYTES) == before, 'host_source_bytes_changed')


def independent_sql(path):
    """All columns and IDs, using separate SELECTs independent of snapshot JSON."""
    with sqlite3.connect(Path(path).resolve().as_uri() + '?mode=ro&immutable=1', uri=True) as db:
        require(db.execute('PRAGMA quick_check').fetchall() == [('ok',)] and
                not db.execute('PRAGMA foreign_key_check').fetchall(), 'independent_sql_failed')
        return {table: db.execute(f'SELECT * FROM {table} ORDER BY {order}').fetchall()
                for table, order in TABLE_ORDER.items()}


class Harness:
    def __init__(self, *, serial, original_apk, qa_apk, upgrade_apk, acknowledge, output,
                 adb=None, original_check=original_manifest_check, qa_check=qa_manifest_check,
                 certificate_check=certificate_digest, clock=time.monotonic, sleep=time.sleep):
        self.serial, self.acknowledge, self.output = serial, acknowledge, Path(output)
        self.paths = [Path(p) for p in (original_apk, qa_apk, upgrade_apk)]
        self.adb, self.original_check, self.qa_check = adb, original_check, qa_check
        self.certificate_check, self.clock, self.sleep = certificate_check, clock, sleep
        self.owned, self.seeded, self.launched = set(), set(), set()
        self.gated = False
        self.receipt = {'schemaVersion': 1, 'result': 'FAIL', 'syntheticDataOnly': True,
            'currentPhase': 'preflight', 'checks': {}, 'limitations': LIMITATIONS.copy()}

    def binary(self, remote, data=None):
        return binary_adb(self.serial, remote, data)

    def preflight(self):
        validate_serial(self.serial)
        require(self.acknowledge is True, 'synthetic_emulator_acknowledgement_required')
        require(all(p.is_file() and not p.is_symlink() for p in self.paths), 'three_apk_files_required')
        try:
            reports = [self.original_check(self.paths[0])]
            require(reports[0].get('result') == 'PASS' and
                    reports[0].get('package') == ORIGINAL and reports[0].get('versionCode') == 9
                    and reports[0].get('versionName') == '0.7.2-personal.1'
                    and reports[0].get('sha256') == ORIGINAL_SHA, 'original_apk_rejected')
            for path, code in zip(self.paths[1:], (10, 11)):
                report = self.qa_check(path, expected_code=code)
                require(report.get('result') == 'PASS' and report.get('package') == QA
                        and report.get('versionCode') == code
                        and report.get('versionName') == f'0.7.2-recovery-qa.{code}'
                        and re.fullmatch('[0-9a-f]{64}', report.get('sha256', '')),
                        'qa_apk_rejected')
                reports.append(report)
            certificates = [self.certificate_check(p) for p in self.paths]
            require(certificates[0] == ORIGINAL_CERT, 'original_apk_certificate_rejected')
            require(all(re.fullmatch('[0-9a-f]{64}', c or '') for c in certificates),
                    'apk_certificate_rejected')
            require(certificates[1] == certificates[2], 'qa_upgrade_signer_mismatch')
            require(certificates[1] != ORIGINAL_CERT, 'qa_signer_must_differ_from_original')
        except AcceptanceError:
            raise
        except Exception:
            raise AcceptanceError('apk_inspection_failed') from None
        if self.adb is None:
            self.adb = Adb(self.serial)
        require(self.adb.command('get-state').strip() == 'device', 'emulator_not_ready')
        require('1' in (self.adb.shell('getprop', 'ro.kernel.qemu').strip(),
                        self.adb.shell('getprop', 'ro.boot.qemu').strip()), 'qemu_emulator_required')
        require(self.adb.shell('getprop', 'ro.hardware').strip() in ('ranchu', 'goldfish'),
                'android_emulator_hardware_required')
        require(re.fullmatch(r'sdk_(?:gphone|phone)[A-Za-z0-9_]*',
                self.adb.shell('getprop', 'ro.product.name').strip()), 'synthetic_sdk_product_required')
        require(self.adb.shell('getprop', 'ro.build.version.sdk').strip() == '35', 'api_35_required')
        require(not self.adb.shell('pm', 'list', 'packages', 'ir.lifeguide.app').strip(),
                'fresh_emulator_required_package_already_present')
        self.gated = True
        self.receipt['apks'] = {role: {key: report[key] for key in
            ('package', 'versionCode', 'versionName', 'sha256')}
            for role, report in zip(('original', 'qaNeverDistribute', 'upgradeNeverDistribute'), reports)}
        self.receipt['certificatesSha256'] = certificates
        self.receipt['checks']['allApksAndFreshEmulatorGatedBeforeInstall'] = 'PASS'

    def _owned(self, package):
        require(package in (ORIGINAL, QA) and package in self.owned, 'package_not_owned_by_this_runner')

    def install(self, package, *, upgrade=False):
        require(self.gated, 'preflight_required')
        require(package in (ORIGINAL, QA), 'unexpected_package')
        require((package == QA and package in self.owned) if upgrade else package not in self.owned,
                'invalid_install_lifecycle')
        path = self.paths[2 if upgrade else 0 if package == ORIGINAL else 1]
        parts = ('install', '-r', str(path)) if upgrade else ('install', str(path))
        output = self.adb.command(*parts)
        require('Success' in output.splitlines() and 'Failure' not in output and 'Error' not in output,
                'apk_install_failed')
        self.owned.add(package)

    def process_state(self, package):
        self._owned(package)
        query = ('pids=$(pidof ' + package + '); code=$?; '
            'if [ "$code" -eq 0 ] && [ -n "$pids" ]; then printf PRESENT; '
            'elif [ "$code" -eq 1 ] && [ -z "$pids" ]; then printf ABSENT; else exit 2; fi')
        state = self.adb.shell('sh', '-c', query).strip()
        require(state in ('PRESENT', 'ABSENT'), 'process_query_failed')
        return state

    def _cold(self, package):
        require(self.process_state(package) == 'ABSENT', 'database_process_must_be_absent')
        query = ' && '.join('test ! -e ' + DATABASE + suffix for suffix in ('-wal', '-shm', '-journal'))
        output = self.adb.shell('run-as', package, 'sh', '-c',
            f'if {query}; then printf CLEAN; else printf SIDECAR; fi').strip()
        require(output == 'CLEAN', 'database_sidecar_present')

    def _remote(self, package, script):
        self._owned(package)
        return 'run-as ' + package + ' sh -c ' + shlex.quote(script)

    def seed(self, package, raw):
        self._owned(package)
        require(package not in self.launched and package not in self.seeded, 'seed_before_first_launch_only')
        require(isinstance(raw, bytes) and 100 <= len(raw) <= MAX_PAYLOAD_BYTES and
                raw[:16] == b'SQLite format 3\0' and
                int.from_bytes(raw[68:72], 'big') == FIXTURE_APPLICATION_ID, 'synthetic_seed_required')
        self._cold(package)
        tests = ' && '.join('test ! -e ' + DATABASE + suffix for suffix in ('', '-wal', '-shm', '-journal'))
        script = f'set -C; umask 077; mkdir -p databases && {tests} && cat > {DATABASE}'
        self.binary(self._remote(package, script), raw)
        self.seeded.add(package)
        require(self.capture(package) == raw, 'seed_bytes_not_confirmed')

    def capture(self, package):
        self._cold(package)
        raw = self.binary(self._remote(package, 'cat ' + DATABASE))
        self._cold(package)
        require(100 <= len(raw) <= MAX_PAYLOAD_BYTES and raw[:16] == b'SQLite format 3\0'
                and int.from_bytes(raw[68:72], 'big') == FIXTURE_APPLICATION_ID,
                'captured_database_invalid')
        return raw

    def profile_visible(self, package):
        self._owned(package)
        path = '/data/local/tmp/lifeguide-recovery-' + secrets.token_hex(12) + '.xml'
        try:
            self.adb.shell('uiautomator', 'dump', path)
            xml = self.adb.shell('cat', path)
            require(len(xml) <= MAX_PAYLOAD_BYTES and '<!' not in xml, 'invalid_ui_hierarchy')
            root = ET.fromstring(xml)
            require(root.tag == 'hierarchy' and len(root) > 0 and
                    all(node.tag == 'node' for node in root.iter() if node is not root),
                    'invalid_ui_hierarchy')
            return any(node.attrib.get('text') in (PROFILE, 'سلام ' + PROFILE)
                       for node in root.iter('node'))
        except ET.ParseError:
            raise AcceptanceError('invalid_ui_hierarchy') from None
        finally:
            self.adb.shell('rm', path)

    def launch(self, package):
        self._owned(package)
        require(package in self.seeded, 'seed_required_before_launch')
        component = package + '/ir.lifeguide.app.MainActivity'
        output = self.adb.shell('am', 'start', '-W', '-f', '0x10008000', '-n', component)
        require('Error' not in output and 'Exception' not in output, 'ordinary_ui_launch_failed')
        self.launched.add(package)
        deadline = self.clock() + 30
        while not self.profile_visible(package):
            require(self.clock() < deadline, 'real_profile_ui_not_visible')
            self.sleep(0.5)
        require(self.process_state(package) == 'PRESENT', 'ordinary_ui_process_missing')

    def close(self, package):
        self._owned(package)
        self.adb.shell('input', 'keyevent', 'KEYCODE_HOME')
        deadline = self.clock() + 15
        while True:
            self.adb.shell('am', 'kill', package)
            if self.process_state(package) == 'ABSENT':
                return
            require(self.clock() < deadline, 'ordinary_process_exit_failed')
            self.sleep(0.25)

    def notifications_off(self):
        self._cold(QA)
        for path, choice in ((CHOICE, True), (REMINDERS, False)):
            script = f'if [ -e {path} ]; then cat {path}; else printf "<map/>"; fi'
            raw = self.binary(self._remote(QA, script))
            try:
                xml = raw.decode('utf-8')
            except UnicodeError:
                raise AcceptanceError('notification_state_not_off') from None
            notification_preferences_off(xml, choice=choice)
        package_dump = self.adb.shell('dumpsys', 'package', QA)
        permission_states = re.findall(
            r'(?m)^\s*android\.permission\.POST_NOTIFICATIONS: granted=(true|false)(?=,|\s*$)',
            package_dump)
        require(permission_states == ['false'], 'qa_notification_permission_not_denied')
        for line in self.adb.shell('cmd', 'notification', 'list').splitlines():
            require(QA not in line.split('|'), 'qa_os_notification_present')
        self._cold(QA)

    def screenshot(self):
        raw = self.binary('screencap -p')
        require(24 <= len(raw) <= MAX_PAYLOAD_BYTES and raw[:8] == b'\x89PNG\r\n\x1a\n'
                and raw[12:16] == b'IHDR', 'fictional_screenshot_failed')
        width, height = struct.unpack('>II', raw[16:24])
        require(100 <= width <= 4096 and 100 <= height <= 4096, 'fictional_screenshot_failed')
        publish_new(self.output.with_suffix('.png'), raw)
        self.receipt['fictionalUiScreenshotSha256'] = digest(raw)

    def run(self):
        self.preflight()
        with tempfile.TemporaryDirectory(prefix='lifeguide-synthetic-recovery-') as directory:
            private = Path(directory)
            os.chmod(private, 0o700)
            reference = private / 'fixture.sqlite'
            fixture = create_sample_database()
            publish_new(reference, fixture)
            expected, sql = export_fixture(reference), independent_sql(reference)
            self.receipt['counts'] = {table: len(rows) for table, rows in sql.items()}
            self.receipt['canonicalSnapshotSha256'] = digest(expected)
            self.receipt['currentPhase'] = 'original_seed_and_ordinary_ui'
            self.install(ORIGINAL)
            self.seed(ORIGINAL, fixture)
            self.launch(ORIGINAL)
            self.screenshot()
            self.close(ORIGINAL)
            original = self.capture(ORIGINAL)
            source = private / 'closed-original.sqlite'
            publish_new(source, original)
            snapshot = normalized_snapshot(source, private / 'original-copy.sqlite')
            require(snapshot == expected and independent_sql(private / 'original-copy.sqlite') == sql,
                    'original_full_field_mismatch')
            passphrase = secrets.token_urlsafe(32)
            archive = seal(snapshot, passphrase)
            restored = database_from_snapshot(open_archive(archive, passphrase))
            del passphrase
            require(source.read_bytes() == original, 'host_source_bytes_changed')
            self.receipt['checks']['hostEncryptedFullFieldRoundTripSourceUnchanged'] = 'PASS'
            self.receipt['currentPhase'] = 'side_by_side_restore'
            self.install(QA)
            self.seed(QA, restored)

            def verify_cycle(phase):
                self.receipt['currentPhase'] = phase
                for package, role in ((ORIGINAL, 'original'), (QA, 'qa')):
                    self.launch(package)
                    self.close(package)
                    raw = self.capture(package)
                    captured = private / (phase + '-' + role + '.sqlite')
                    copied = private / (phase + '-' + role + '-copy.sqlite')
                    publish_new(captured, raw)
                    actual = normalized_snapshot(captured, copied)
                    require(actual == expected and independent_sql(copied) == sql,
                            'full_field_or_independent_sql_mismatch')
                    if package == ORIGINAL:
                        require(raw == original, 'original_source_bytes_changed')
                self.notifications_off()
                self.receipt['checks'][phase] = 'PASS'

            verify_cycle('both_apps_after_first_close')
            verify_cycle('both_apps_after_reopen')
            self.receipt['currentPhase'] = 'qa_same_test_key_upgrade'
            self.install(QA, upgrade=True)
            verify_cycle('both_apps_after_qa_upgrade')
            verify_cycle('both_apps_after_upgrade_reopen')
            require(source.read_bytes() == original, 'host_source_bytes_changed')
            self.receipt['checks']['qaNotificationsDefaultOffNoConsentTransferred'] = 'PASS'
            self.receipt['checks']['originalSourceBytesUnchangedAcrossRestoreAndUpgrade'] = 'PASS'
            self.receipt['originalClosedDatabaseSha256'] = digest(original)
        self.receipt.update(result='PASS', currentPhase='complete')
        return self.receipt


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--serial', required=True)
    parser.add_argument('--original-apk', type=Path, required=True)
    parser.add_argument('--qa-apk', type=Path, required=True)
    parser.add_argument('--upgrade-apk', type=Path, required=True)
    parser.add_argument('--acknowledge-synthetic-emulator-only', action='store_true')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args(argv)
    runner = Harness(serial=args.serial, original_apk=args.original_apk, qa_apk=args.qa_apk,
        upgrade_apk=args.upgrade_apk, acknowledge=args.acknowledge_synthetic_emulator_only,
        output=args.output)
    code = 0
    try:
        runner.run()
    except (AcceptanceError, RecoveryError) as error:
        runner.receipt['errorCode'] = error.code if isinstance(error, RecoveryError) else str(error)
        code = 2
    except KeyboardInterrupt:
        runner.receipt['errorCode'], code = 'interrupted', 130
    except Exception:
        runner.receipt['errorCode'], code = 'host_acceptance_failed', 2
    try:
        publish_new(args.output, (json.dumps(runner.receipt, sort_keys=True, indent=2) + '\n').encode())
    except (OSError, RecoveryError):
        print(json.dumps({'result': 'FAIL', 'errorCode': 'receipt_publication_failed',
                          'syntheticDataOnly': True}))
        return 2
    print(json.dumps({'result': runner.receipt['result'], 'currentPhase': runner.receipt['currentPhase'],
                      **({'errorCode': runner.receipt['errorCode']} if code else {})}))
    return code


if __name__ == '__main__':
    raise SystemExit(main())
