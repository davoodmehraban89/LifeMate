"""Host safety boundaries. Real emulator acceptance is a separate CI run."""
import hashlib
import json
from pathlib import Path
import sqlite3
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import test_personal_recovery_android as subject


class FakeAdb:
    def __init__(self):
        self.calls = []
        self.packages = ''
        self.hardware = 'ranchu'
        self.process = 'ABSENT'
        self.sidecars = 'CLEAN'

    def command(self, *parts, **kwargs):
        self.calls.append(parts)
        return 'device' if parts == ('get-state',) else 'Success\n'

    def shell(self, *parts, **kwargs):
        self.calls.append(parts)
        if parts[0] == 'getprop':
            return {'ro.kernel.qemu': '1', 'ro.boot.qemu': '1',
                    'ro.hardware': self.hardware, 'ro.product.name': 'sdk_gphone64_x86_64',
                    'ro.build.version.sdk': '35'}[parts[1]]
        if parts[:3] == ('pm', 'list', 'packages'):
            return self.packages
        if parts[:2] == ('sh', '-c') and 'pidof ' in parts[2]:
            return self.process
        if parts[0] == 'run-as':
            return self.sidecars
        return ''


class RecoveryBoundaryTest(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.directory = Path(directory.name)
        self.paths = [self.directory / name for name in ('original.apk', 'qa.apk', 'upgrade.apk')]
        for path in self.paths:
            path.write_bytes(b'host test apk')
        self.adb = FakeAdb()

    def make(self, **options):
        defaults = dict(serial='emulator-5554', original_apk=self.paths[0],
                        qa_apk=self.paths[1], upgrade_apk=self.paths[2],
                        acknowledge=True, output=self.directory / 'receipt.json', adb=self.adb,
                        original_check=lambda _: {'result': 'PASS', 'package': subject.ORIGINAL,
                            'versionCode': 9, 'versionName': '0.7.2-personal.1',
                            'sha256': subject.ORIGINAL_SHA},
                        qa_check=lambda _, expected_code=None: {'result': 'PASS',
                            'package': subject.QA, 'versionCode': expected_code,
                            'versionName': f'0.7.2-recovery-qa.{expected_code}', 'sha256': 'a' * 64},
                        certificate_check=lambda p: subject.ORIGINAL_CERT if p == self.paths[0] else 'b' * 64)
        defaults.update(options)
        return subject.Harness(**defaults)

    def assert_no_install(self):
        self.assertFalse(any(call[0] == 'install' for call in self.adb.calls))

    def test_all_inputs_gated_before_any_install(self):
        for options, code in (({'serial': 'physical-phone'}, 'explicit_emulator_serial_required'),
                              ({'acknowledge': False}, 'synthetic_emulator_acknowledgement_required'),
                              ({'certificate_check': lambda _: subject.ORIGINAL_CERT}, 'qa_signer_must_differ_from_original'),
                              ({'original_check': lambda _: {'sha256': '0' * 64}}, 'original_apk_rejected')):
            with self.subTest(code=code):
                self.adb.calls.clear()
                with self.assertRaisesRegex(subject.AcceptanceError, code):
                    self.make(**options).preflight()
                self.assert_no_install()

    def test_rejects_existing_lifeguide_package_and_physical_hardware(self):
        for attribute, value in (('packages', 'package:ir.lifeguide.app\n'),
                                 ('hardware', 'physical')):
            with self.subTest(attribute=attribute):
                old = getattr(self.adb, attribute)
                setattr(self.adb, attribute, value)
                with self.assertRaises(subject.AcceptanceError):
                    self.make().preflight()
                self.assert_no_install()
                setattr(self.adb, attribute, old)

    def test_seed_is_owned_unlaunched_and_no_clobber(self):
        h = self.make()
        sent = []
        raw = subject.create_sample_database()
        h.binary = lambda command, data=None: (sent.append((command, data)) or b'') if data is not None else raw
        with self.assertRaises(subject.AcceptanceError):
            h.seed(subject.ORIGINAL, raw)
        h.preflight()
        h.install(subject.ORIGINAL)
        h.seed(subject.ORIGINAL, raw)
        self.assertIn('set -C', sent[0][0])
        self.assertIn('test ! -e', sent[0][0])
        self.assertEqual(sent[0][1], raw)
        with self.assertRaises(subject.AcceptanceError):
            h.seed(subject.ORIGINAL, raw)

    def test_capture_requires_absence_and_sidecars_before_and_after_read(self):
        h = self.make()
        h.preflight()
        h.install(subject.ORIGINAL)
        reads = []
        h.binary = lambda command, data=None: reads.append(command) or subject.create_sample_database()
        self.adb.process = 'PRESENT'
        with self.assertRaises(subject.AcceptanceError):
            h.capture(subject.ORIGINAL)
        self.assertEqual(reads, [])
        self.adb.process = 'ABSENT'
        self.adb.sidecars = 'SIDECAR'
        with self.assertRaises(subject.AcceptanceError):
            h.capture(subject.ORIGINAL)
        self.assertEqual(reads, [])
        self.adb.sidecars = 'CLEAN'
        def racing_read(command, data=None):
            self.adb.sidecars = 'SIDECAR'
            return subject.create_sample_database()
        h.binary = racing_read
        with self.assertRaises(subject.AcceptanceError):
            h.capture(subject.ORIGINAL)

    def test_capture_accepts_only_stable_empty_wal_cache_shapes(self):
        h = self.make()
        h.preflight()
        h.install(subject.ORIGINAL)
        raw = subject.create_sample_database()
        h.binary = lambda command, data=None: raw
        for shape in ('CLEAN', 'EMPTY_WAL', 'EMPTY_WAL_SHM'):
            self.adb.sidecars = shape
            self.assertEqual(h.capture(subject.ORIGINAL), raw)
        self.adb.sidecars = 'EMPTY_WAL_SHM'
        def changing_read(command, data=None):
            self.adb.sidecars = 'EMPTY_WAL'
            return raw
        h.binary = changing_read
        with self.assertRaisesRegex(subject.AcceptanceError, 'database_cache_shape_changed'):
            h.capture(subject.ORIGINAL)
        for state in ('NONEMPTY_WAL', 'ORPHAN_SHM', 'JOURNAL', 'SIDECAR'):
            self.adb.sidecars = state
            with self.assertRaisesRegex(subject.AcceptanceError, 'database_sidecar_present'):
                h.capture(subject.ORIGINAL)

    def test_actual_exited_sqlite_reader_leaves_empty_wal_cache_only(self):
        source = self.directory / 'real-closed-reader.sqlite'
        fixture = subject.create_sample_database()
        source.write_bytes(fixture)
        script = ("import os,sqlite3,sys; d=sqlite3.connect(sys.argv[1]); "
                  "d.execute('PRAGMA journal_mode=WAL'); "
                  "d.execute('SELECT * FROM local_profiles').fetchall(); os._exit(0)")
        subprocess.run(['python3', '-c', script, str(source)], check=True)
        wal, shm = Path(str(source) + '-wal'), Path(str(source) + '-shm')
        self.assertEqual(wal.stat().st_size, 0)
        self.assertGreater(shm.stat().st_size, 0)
        before = {p: p.read_bytes() for p in (source, wal, shm)}
        # The AVD harness captures the main bytes only AFTER its cold zero-WAL gate.
        captured = self.directory / 'captured-main.sqlite'
        captured.write_bytes(source.read_bytes())
        reference = self.directory / 'reference.sqlite'
        reference.write_bytes(fixture)
        normalized = subject.normalized_snapshot(captured, self.directory / 'normalized.sqlite')
        self.assertEqual(normalized, subject.export_fixture(reference))
        self.assertEqual(subject.independent_sql(reference),
                         subject.independent_sql(self.directory / 'normalized.sqlite'))
        self.assertEqual({p: p.read_bytes() for p in before}, before)

    def test_private_normalization_preserves_wal_header_source_and_full_fields(self):
        raw = bytearray(subject.create_sample_database())
        raw[18:20] = b'\x02\x02'
        source = self.directory / 'closed.sqlite'
        source.write_bytes(raw)
        original = bytes(raw)
        normalized = subject.normalized_snapshot(source, self.directory / 'copy.sqlite')
        self.assertEqual(source.read_bytes(), original)
        reference = self.directory / 'reference.sqlite'
        reference.write_bytes(subject.create_sample_database())
        self.assertEqual(normalized, subject.export_fixture(reference))
        self.assertEqual(subject.independent_sql(self.directory / 'copy.sqlite'),
                         subject.independent_sql(reference))

    def test_notification_choice_and_native_state_are_strictly_off(self):
        for xml in ('<map/>', '<map><boolean name="enabled" value="false" /></map>'):
            self.assertTrue(subject.notification_preferences_off(xml, choice=True))
        self.assertTrue(subject.notification_preferences_off('<map/>', choice=False))
        for xml, choice in (('<map><boolean name="enabled" value="true"/></map>', True),
                            ('<map><string name="active">{}</string></map>', False),
                            ('<!DOCTYPE map><map/>', True),
                            ('<map><boolean name="enabled" value="false"/><boolean name="enabled" value="false"/></map>', True)):
            with self.subTest(xml=xml), self.assertRaises(subject.AcceptanceError):
                subject.notification_preferences_off(xml, choice=choice)

    def test_ui_requires_exact_owned_profile_semantics_and_dump_cleanup(self):
        h = self.make()
        h.preflight()
        h.install(subject.ORIGINAL)
        xml = ''
        def shell(*parts, **kwargs):
            self.adb.calls.append(parts)
            return xml if parts[0] == 'cat' else ''
        self.adb.shell = shell
        for attribute in ('text', 'content-desc'):
            for value in (subject.PROFILE, 'سلام ' + subject.PROFILE):
                with self.subTest(attribute=attribute, value=value):
                    xml = f'<hierarchy><node package="{subject.ORIGINAL}" {attribute}="{value}"/></hierarchy>'
                    self.assertTrue(h.profile_visible(subject.ORIGINAL))
        for attrs in ('text="not fixture"',
                      f'text="extra {subject.PROFILE}"',
                      f'content-desc="سلام {subject.PROFILE} extra"',
                      f'content-desc="{subject.PROFILE}" package="another.app"',
                      f'text="{subject.PROFILE}"'):
            with self.subTest(attrs=attrs):
                xml = '<hierarchy><node ' + attrs + '/></hierarchy>'
                self.assertFalse(h.profile_visible(subject.ORIGINAL))
        for xml in ('<hierarchy><broken>', '<wrong><node/></wrong>'):
            with self.assertRaises(subject.AcceptanceError):
                h.profile_visible(subject.ORIGINAL)
        dumps = [call for call in self.adb.calls if call[0] == 'uiautomator']
        self.assertEqual(len(dumps), 11)
        for call in dumps:
            self.assertRegex(call[2], r'^/data/local/tmp/lifeguide-recovery-[0-9a-f]+\.xml$')
            self.assertIn(('rm', call[2]), self.adb.calls)

    def test_ui_timeout_keeps_failure_even_if_synthetic_diagnostic_fails(self):
        for diagnostic_fails in (False, True):
            with self.subTest(diagnostic_fails=diagnostic_fails):
                ticks = iter((0, 31))
                h = self.make(clock=lambda: next(ticks))
                h.preflight()
                h.install(subject.ORIGINAL)
                h.seeded.add(subject.ORIGINAL)
                h.profile_visible = lambda _: False
                captures = []
                def screenshot(kind='ordinary'):
                    captures.append(kind)
                    if diagnostic_fails:
                        raise subject.AcceptanceError('fictional_screenshot_failed')
                h.screenshot = screenshot
                with self.assertRaisesRegex(subject.AcceptanceError, '^real_profile_ui_not_visible$'):
                    h.launch(subject.ORIGINAL)
                self.assertEqual(captures, ['ui-failure-original'])

    def test_seed_checks_bytes_after_binary_exec_without_overwriting(self):
        h = self.make()
        h.preflight()
        h.install(subject.ORIGINAL)
        h.binary = lambda command, data=None: b''
        with self.assertRaises(subject.AcceptanceError):
            h.seed(subject.ORIGINAL, subject.create_sample_database())

    def test_notification_permission_requires_explicit_runtime_denial(self):
        h = self.make()
        h.preflight()
        h.install(subject.QA)
        h.binary = lambda command, data=None: b'<map/>'
        original_shell = self.adb.shell
        state = 'false'
        def shell(*parts, **kwargs):
            if parts[:2] == ('dumpsys', 'package'):
                return 'runtime permissions:\n android.permission.POST_NOTIFICATIONS: granted=' + state + ', flags=[]\n'
            return original_shell(*parts, **kwargs)
        self.adb.shell = shell
        h.notifications_off()
        state = 'true'
        with self.assertRaisesRegex(subject.AcceptanceError, 'qa_notification_permission_not_denied'):
            h.notifications_off()
        state = ''
        with self.assertRaisesRegex(subject.AcceptanceError, 'qa_notification_permission_not_denied'):
            h.notifications_off()

    def test_binary_transport_bounds_actual_child_output_and_input(self):
        with self.assertRaisesRegex(subject.AcceptanceError, 'binary_input_limit'):
            subject.binary_adb('emulator-5554', 'unused', b'a' * (subject.MAX_PAYLOAD_BYTES + 1))
        popen = subprocess.Popen
        def child(*args, **kwargs):
            return popen(['python3', '-c', 'import sys; sys.stdout.buffer.write(b"a" * (8*1024*1024+1))'], **kwargs)
        with patch.object(subject.subprocess, 'Popen', side_effect=child):
            with self.assertRaisesRegex(subject.AcceptanceError, 'binary_output_limit'):
                subject.binary_adb('emulator-5554', 'unused')

    def test_binary_transport_uses_adb_input_and_output_directions(self):
        # Android15 adb commandline.cpp: exec-in copies stdin to device;
        # exec-out only copies device bytes to stdout and never consumes stdin.
        uploaded = self.directory / 'uploaded-fixture'
        real_popen = subprocess.Popen
        child_source = ("import sys; from pathlib import Path; "
                        "mode=sys.argv[1]; "
                        "Path(sys.argv[2]).write_bytes(sys.stdin.buffer.read()) "
                        "if mode == 'exec-in' else sys.stdout.buffer.write(b'fictional capture')")
        def child(argv, **kwargs):
            return real_popen(['python3', '-c', child_source, argv[3], str(uploaded)], **kwargs)
        payload = bytes(range(256)) * 32
        with patch.object(subject.subprocess, 'Popen', side_effect=child):
            self.assertEqual(subject.binary_adb('emulator-5554', 'fixed synthetic command', payload), b'')
            self.assertEqual(uploaded.read_bytes(), payload)
            self.assertEqual(subject.binary_adb('emulator-5554', 'fixed synthetic command'), b'fictional capture')

    def test_failure_receipt_without_device_is_sanitized(self):
        output = self.directory / 'exports' / 'failed.json'
        code = subject.main(['--serial', 'physical-phone', '--original-apk', str(self.paths[0]),
            '--qa-apk', str(self.paths[1]), '--upgrade-apk', str(self.paths[2]),
            '--acknowledge-synthetic-emulator-only', '--output', str(output)])
        self.assertEqual(code, 2)
        receipt = json.loads(output.read_text())
        self.assertEqual(receipt['result'], 'FAIL')
        self.assertEqual(receipt['errorCode'], 'explicit_emulator_serial_required')
        self.assertEqual(receipt['currentPhase'], 'preflight')
        self.assertNotIn('host test apk', output.read_text())


if __name__ == '__main__':
    unittest.main()
