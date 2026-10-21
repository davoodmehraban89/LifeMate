"""Synthetic-only SQLite portability and refusal checks; never open owner data."""
import copy
import hashlib
import importlib
import importlib.util
import json
from pathlib import Path
import re
import sqlite3
import tempfile
import unittest
from unittest import mock

from scripts.personal_recovery import files
from scripts.personal_recovery.common import (
    FIXTURE_APPLICATION_ID, MAX_PAYLOAD_BYTES, MAX_ROWS, RecoveryError,
)

ROOT = Path(__file__).resolve().parents[2]
P = '11111111-1111-4111-8111-111111111111'
A = '22222222-2222-4222-8222-222222222222'
B = '33333333-3333-4333-8333-333333333333'
O = '44444444-4444-4444-8444-444444444444'


def fixture_connection(path, *, marked=True):
    """Use the actual application's DDL, independently of the new exporter."""
    connection = sqlite3.connect(path)
    source = (ROOT / 'apps/lifemate/lib/standalone/store.dart').read_text()
    for sql in re.findall(r"'''(CREATE TABLE .*?)'''", source, re.DOTALL):
        connection.execute(sql)
    connection.execute('CREATE INDEX local_occurrences_date ON local_occurrences(occurrence_date)')
    connection.execute('PRAGMA user_version = 1')
    if marked:
        connection.execute(f'PRAGMA application_id = {FIXTURE_APPLICATION_ID}')
    connection.execute('INSERT INTO local_profiles VALUES (1,?,?,?,?,?)',
                       (P, 'Fictional آزمایشی', 'girl_minor', 'Fictional همراه', 'mint'))
    connection.execute('INSERT INTO local_plans VALUES (?,?,?,?,?,?,?,?,?,?,?)',
                       (A, P, 'Fictional weekly', 'routine', 'weekly', '2024-01-01',
                        '2024-02-29', 400, 500, 30, 1))
    connection.execute('INSERT INTO local_plans VALUES (?,?,?,?,?,?,?,?,?,?,?)',
                       (B, P, 'Fictional one-off', 'event', 'once', '2024-02-29',
                        None, 0, 1440, None, 0))
    connection.executemany('INSERT INTO local_weekly_slots VALUES (?,?,?,?)',
                           [(A, 7, 700, 750), (A, 1, 600, 630)])
    connection.execute('INSERT INTO local_occurrences VALUES (?,?,?,?,?,?,?,?,?,?)',
                       (O, A, '2024-01-01', 'Fictional edited independent title',
                        'task', 800, 900, 1, 1, 0))
    connection.commit()
    return connection


class SnapshotTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name) / 'fictional.sqlite'
        connection = fixture_connection(self.path)
        connection.close()
        self.assertIsNotNone(importlib.util.find_spec('scripts.personal_recovery.snapshot'),
                             'snapshot module is required')
        self.module = importlib.import_module('scripts.personal_recovery.snapshot')

    def document(self):
        return json.loads(self.module.export_fixture(self.path))

    def reject_document(self, document):
        with self.assertRaises(RecoveryError):
            self.module.database_from_snapshot(json.dumps(document).encode())

    def test_exact_roundtrip_all_fields_and_source_digest(self):
        before = hashlib.sha256(self.path.read_bytes()).hexdigest()
        payload = self.module.export_fixture(self.path)
        self.assertEqual(hashlib.sha256(self.path.read_bytes()).hexdigest(), before)
        self.assertEqual(sorted(p.name for p in self.path.parent.iterdir()), ['fictional.sqlite'])
        document = json.loads(payload)
        self.assertEqual(set(document), {'format', 'schemaVersion', 'syntheticOnly', 'tables'})
        self.assertEqual(document['format'], 'LifeGuideSyntheticRecovery')
        self.assertIs(document['syntheticOnly'], True)
        self.assertEqual(document['schemaVersion'], 1)
        self.assertEqual(document['tables']['local_occurrences'][0]['title'],
                         'Fictional edited independent title')
        self.assertEqual([s['weekday'] for s in document['tables']['local_weekly_slots']], [1, 7])
        self.assertEqual(payload, json.dumps(document, ensure_ascii=False, sort_keys=True,
                                            separators=(',', ':'), allow_nan=False).encode())
        restored = self.path.parent / 'restored.sqlite'
        restored.write_bytes(self.module.database_from_snapshot(payload))
        self.assertEqual(self.module.export_fixture(restored), payload)
        with sqlite3.connect(self.path) as original, sqlite3.connect(restored) as result:
            for table in document['tables']:
                self.assertEqual(sorted(original.execute(f'SELECT * FROM {table}').fetchall()),
                                 sorted(result.execute(f'SELECT * FROM {table}').fetchall()))
            self.assertEqual(result.execute('PRAGMA integrity_check').fetchall(), [('ok',)])
            self.assertEqual(result.execute('PRAGMA foreign_key_check').fetchall(), [])

    def test_sample_has_fictional_past_rows_for_all_recurrences_and_independent_state(self):
        self.path.write_bytes(self.module.create_sample_database())
        tables = self.document()['tables']
        self.assertEqual({p['recurrence'] for p in tables['local_plans']},
                         {'once', 'daily', 'everyTwoDays', 'weekly'})
        self.assertEqual({p['kind'] for p in tables['local_plans']}, {'task', 'event', 'routine'})
        self.assertTrue(all(p['start_date'].startswith('2024-') for p in tables['local_plans']))
        self.assertTrue(all('Fictional' in p['title'] for p in tables['local_plans']))
        self.assertTrue(any(o['completed'] and o['archived'] for o in tables['local_occurrences']))
        self.assertTrue(any(p['archived'] for p in tables['local_plans']))
        plans = {p['id']: p for p in tables['local_plans']}
        self.assertTrue(any(o['title'] != plans[o['plan_id']]['title']
                            for o in tables['local_occurrences']))

    def test_marker_checked_before_any_schema_or_content_query(self):
        with sqlite3.connect(self.path) as connection:
            connection.execute('PRAGMA application_id = 0')
        real_connect = sqlite3.connect
        queries = []

        def traced_connect(*args, **kwargs):
            connection = real_connect(*args, **kwargs)
            connection.set_trace_callback(queries.append)
            return connection

        with mock.patch.object(self.module.sqlite3, 'connect', side_effect=traced_connect):
            with self.assertRaises(RecoveryError):
                self.module.export_fixture(self.path)
        self.assertEqual(queries, [])
        with real_connect(self.path) as connection:
            connection.execute(f'PRAGMA application_id = {FIXTURE_APPLICATION_ID}')
        with mock.patch.object(self.module.sqlite3, 'connect', side_effect=traced_connect):
            self.module.export_fixture(self.path)
        marker = next(index for index, query in enumerate(queries) if query == 'PRAGMA application_id')
        first_select = next(index for index, query in enumerate(queries) if 'SELECT' in query.upper())
        self.assertLess(marker, first_select)

    def test_marker_is_safety_gate_not_authentication(self):
        self.assertIn('not authentication', self.module.__doc__)

    def test_unknown_version_refused_without_source_change(self):
        with sqlite3.connect(self.path) as connection:
            connection.execute('PRAGMA user_version = 2')
        before = self.path.read_bytes()
        with self.assertRaises(RecoveryError):
            self.module.export_fixture(self.path)
        self.assertEqual(before, self.path.read_bytes())

    def test_extra_sql_objects_or_modified_schema_refused(self):
        cases = [
            'CREATE TABLE unexpected (secret TEXT)',
            'CREATE VIEW unexpected AS SELECT * FROM local_profiles',
            'CREATE TRIGGER unexpected AFTER INSERT ON local_plans BEGIN DELETE FROM local_profiles; END',
            'CREATE INDEX unexpected ON local_profiles(display_name)',
            'ALTER TABLE local_profiles ADD COLUMN unexpected TEXT',
        ]
        for sql in cases:
            with self.subTest(sql=sql):
                path = self.path.parent / 'modified.sqlite'
                path.write_bytes(self.path.read_bytes())
                with sqlite3.connect(path) as connection:
                    connection.execute(sql)
                with self.assertRaises(RecoveryError):
                    self.module.export_fixture(path)

    def test_android_metadata_optional_and_never_exported(self):
        expected = self.module.export_fixture(self.path)
        with sqlite3.connect(self.path) as connection:
            connection.execute('CREATE TABLE android_metadata (locale TEXT)')
            connection.execute("INSERT INTO android_metadata VALUES ('fictional_locale')")
        self.assertEqual(self.module.export_fixture(self.path), expected)
        with sqlite3.connect(self.path) as connection:
            connection.execute('ALTER TABLE android_metadata ADD COLUMN extra TEXT')
        with self.assertRaises(RecoveryError):
            self.module.export_fixture(self.path)

    def test_invalid_database_types_and_dates_refused(self):
        for sql in ["UPDATE local_plans SET start_date='2024-02-30'",
                    "UPDATE local_plans SET id='xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx' WHERE title='Fictional weekly'",
                    "UPDATE local_plans SET start_minute='secret invalid value'",
                    "UPDATE local_occurrences SET plan_id='99999999-9999-4999-8999-999999999999'"]:
            with self.subTest(sql=sql):
                path = self.path.parent / 'invalid.sqlite'
                path.write_bytes(self.path.read_bytes())
                with sqlite3.connect(path) as connection:
                    connection.execute('PRAGMA ignore_check_constraints = ON')
                    connection.execute(sql)
                with self.assertRaises(RecoveryError) as error:
                    self.module.export_fixture(path)
                self.assertNotIn('secret', str(error.exception))

    def test_nonexistent_corrupt_and_symlink_sources_refused(self):
        for path in [self.path.parent / 'missing', self.path.parent / 'corrupt',
                     self.path.parent / 'symlink']:
            if path.name == 'corrupt':
                path.write_bytes(b'fictional not sqlite')
            if path.name == 'symlink':
                path.symlink_to(self.path)
            with self.subTest(path=path.name), self.assertRaises(RecoveryError):
                self.module.export_fixture(path)
        self.assertFalse((self.path.parent / 'missing').exists())

    def test_source_symlink_swap_refused_before_sqlite_content_read(self):
        replacement = self.path.parent / 'replacement.sqlite'
        saved_original = self.path.parent / 'original.sqlite'
        replacement.write_bytes(self.path.read_bytes())
        with sqlite3.connect(replacement) as connection:
            connection.execute("UPDATE local_profiles SET display_name='Fictional swap canary'")
        original_hash = hashlib.sha256(self.path.read_bytes()).hexdigest()
        replacement_hash = hashlib.sha256(replacement.read_bytes()).hexdigest()
        real_lstat = Path.lstat
        real_connect = sqlite3.connect
        queries = []
        swapped = False

        def swapping_lstat(candidate, *args, **kwargs):
            nonlocal swapped
            info = real_lstat(candidate, *args, **kwargs)
            if candidate == self.path and not swapped:
                swapped = True
                self.path.rename(saved_original)
                self.path.symlink_to(replacement)
            return info

        def traced_connect(*args, **kwargs):
            connection = real_connect(*args, **kwargs)
            connection.set_trace_callback(queries.append)
            return connection

        with mock.patch.object(Path, 'lstat', new=swapping_lstat), \
                mock.patch.object(self.module.sqlite3, 'connect', side_effect=traced_connect):
            with self.assertRaises(RecoveryError):
                self.module.export_fixture(self.path)
        self.assertTrue(swapped)
        self.assertFalse(any('SELECT' in query.upper() for query in queries), queries)
        self.assertEqual(hashlib.sha256(saved_original.read_bytes()).hexdigest(), original_hash)
        self.assertEqual(hashlib.sha256(replacement.read_bytes()).hexdigest(), replacement_hash)

    def test_unmarked_and_future_schema_headers_refused_before_body_read(self):
        original = self.path.read_bytes()
        cases = [(68, b'\x00\x00\x00\x00', 'synthetic_marker_required'),
                 (60, b'\x00\x00\x00\x02', 'unsupported_schema')]
        for offset, changed, code in cases:
            with self.subTest(code=code):
                modified = original[:offset] + changed + original[offset + 4:]
                self.path.write_bytes(modified)
                before = hashlib.sha256(modified).hexdigest()
                real_fdopen = files.os.fdopen
                reads = []

                class ObservedStream:
                    def __init__(self, stream):
                        self.stream = stream

                    def __enter__(self):
                        return self

                    def __exit__(self, *args):
                        self.stream.close()

                    def read(self, size=-1):
                        chunk = self.stream.read(size)
                        reads.append(len(chunk))
                        return chunk

                def observed_fdopen(*args, **kwargs):
                    return ObservedStream(real_fdopen(*args, **kwargs))

                with mock.patch.object(files.os, 'fdopen', side_effect=observed_fdopen), \
                        mock.patch.object(self.module.sqlite3, 'connect') as connection:
                    with self.assertRaises(RecoveryError) as error:
                        self.module.export_fixture(self.path)
                self.assertEqual(reads, [100])
                self.assertEqual(error.exception.code, code)
                connection.assert_not_called()
                self.assertEqual(hashlib.sha256(self.path.read_bytes()).hexdigest(), before)

    def test_cold_wal_headers_refused_before_sqlite_open(self):
        original = self.path.read_bytes()
        real_connect = sqlite3.connect
        calls = []

        def recording_connect(*args, **kwargs):
            calls.append(args[0])
            return real_connect(*args, **kwargs)

        for versions in [b'\x02\x02', b'\x01\x02', b'\x02\x01']:
            with self.subTest(versions=versions):
                modified = original[:18] + versions + original[20:]
                self.path.write_bytes(modified)
                calls.clear()
                with mock.patch.object(self.module.sqlite3, 'connect', side_effect=recording_connect):
                    with self.assertRaises(RecoveryError):
                        self.module.export_fixture(self.path)
                self.assertEqual(calls, [])
                self.assertEqual(self.path.read_bytes(), modified)

    def test_active_sidecars_refused(self):
        for suffix in ['-wal', '-shm', '-journal']:
            sidecar = Path(str(self.path) + suffix)
            sidecar.write_bytes(b'fictional')
            with self.subTest(suffix=suffix), self.assertRaises(RecoveryError):
                self.module.export_fixture(self.path)
            sidecar.unlink()

    def test_strict_json_and_top_level_contract(self):
        for raw in [b'{}', b'[]', b'null', b'\xff', b'{', b'{"format":1,"format":2}',
                    b'{"x":NaN}', b'{"x":Infinity}', b'[' * 1100]:
            with self.subTest(raw=raw[:30]), self.assertRaises(RecoveryError):
                self.module.database_from_snapshot(raw)
        document = self.document()
        for key, value in [('schemaVersion', True), ('schemaVersion', 2),
                           ('syntheticOnly', 1), ('syntheticOnly', False),
                           ('format', 'unknown'), ('extra', 'forbidden')]:
            changed = copy.deepcopy(document)
            changed[key] = value
            with self.subTest(key=key, value=value):
                self.reject_document(changed)
        raw = self.module.export_fixture(self.path).decode()
        raw = raw.replace('"singleton":1', '"singleton":1,"singleton":1')
        with self.assertRaises(RecoveryError):
            self.module.database_from_snapshot(raw.encode())

    def test_unknown_missing_tables_rows_and_columns_refused(self):
        document = self.document()
        changes = []
        extra = copy.deepcopy(document)
        extra['tables']['android_metadata'] = []
        changes.append(extra)
        missing = copy.deepcopy(document)
        del missing['tables']['local_plans']
        changes.append(missing)
        for value in [{}, None, ['wrong']]:
            changed = copy.deepcopy(document)
            changed['tables']['local_plans'] = value
            changes.append(changed)
        for remove in [False, True]:
            changed = copy.deepcopy(document)
            row = changed['tables']['local_plans'][0]
            if remove:
                del row['title']
            else:
                row['extra'] = 'forbidden'
            changes.append(changed)
        for changed in changes:
            with self.subTest(changed=changes.index(changed)):
                self.reject_document(changed)

    def test_invalid_scalar_values_refused(self):
        document = self.document()
        cases = [
            ('local_profiles', 'singleton', True), ('local_profiles', 'singleton', 0),
            ('local_profiles', 'id', 'not-a-uuid'),
            ('local_profiles', 'id', P.upper().replace('11111111', 'AAAAAAAA', 1)),
            ('local_profiles', 'category', 'child'), ('local_profiles', 'theme_key', 'unknown'),
            ('local_profiles', 'display_name', ' '), ('local_profiles', 'display_name', 'a' * 81),
            ('local_profiles', 'companion_name', 'a' * 41),
            ('local_profiles', 'display_name', '\x00'),
            ('local_plans', 'title', 'a' * 201), ('local_plans', 'title', 42),
            ('local_plans', 'kind', 'other'), ('local_plans', 'recurrence', 'monthly'),
            ('local_plans', 'start_date', '2024-02-30'), ('local_plans', 'start_date', '2024-1-01'),
            ('local_plans', 'start_date', '0000-01-01'),
            ('local_plans', 'until_date', '2023-12-31'),
            ('local_plans', 'start_minute', True), ('local_plans', 'start_minute', 1.0),
            ('local_plans', 'start_minute', '1'), ('local_plans', 'start_minute', -1),
            ('local_plans', 'end_minute', 1441), ('local_plans', 'end_minute', 400),
            ('local_plans', 'archived', 2), ('local_plans', 'reminder_minutes', 20),
            ('local_weekly_slots', 'weekday', 8), ('local_weekly_slots', 'weekday', False),
            ('local_weekly_slots', 'end_minute', 1),
            ('local_occurrences', 'completed', True), ('local_occurrences', 'archived', -1),
            ('local_occurrences', 'occurrence_date', '2023-02-29'),
            ('local_occurrences', 'reminder_minutes', 1),
        ]
        for table, key, value in cases:
            with self.subTest(table=table, key=key, value=value):
                changed = copy.deepcopy(document)
                changed['tables'][table][0][key] = value
                self.reject_document(changed)

    def test_duplicate_primary_and_unique_keys_refused(self):
        document = self.document()
        for table in document['tables']:
            changed = copy.deepcopy(document)
            changed['tables'][table].append(copy.deepcopy(changed['tables'][table][0]))
            with self.subTest(table=table):
                self.reject_document(changed)
        changed = copy.deepcopy(document)
        occurrence = copy.deepcopy(changed['tables']['local_occurrences'][0])
        occurrence['id'] = '55555555-5555-4555-8555-555555555555'
        changed['tables']['local_occurrences'].append(occurrence)
        self.reject_document(changed)

    def test_foreign_keys_and_weekly_recurrence_links_refused(self):
        document = self.document()
        for table, key in [('local_plans', 'profile_id'),
                           ('local_occurrences', 'plan_id'), ('local_weekly_slots', 'plan_id')]:
            changed = copy.deepcopy(document)
            changed['tables'][table][0][key] = O
            with self.subTest(table=table):
                self.reject_document(changed)
        changed = copy.deepcopy(document)
        changed['tables']['local_weekly_slots'] = []
        self.reject_document(changed)
        changed = copy.deepcopy(document)
        changed['tables']['local_plans'][0]['recurrence'] = 'daily'
        self.reject_document(changed)

    def test_payload_and_row_limits(self):
        with self.assertRaises(RecoveryError):
            self.module.database_from_snapshot(b' ' * (MAX_PAYLOAD_BYTES + 1))
        changed = self.document()
        changed['tables']['local_occurrences'] = [changed['tables']['local_occurrences'][0]] * (MAX_ROWS + 1)
        self.reject_document(changed)
        with self.path.open('ab') as stream:
            stream.truncate(MAX_PAYLOAD_BYTES + 1)
        with self.assertRaises(RecoveryError):
            self.module.export_fixture(self.path)

    def test_empty_v1_database_roundtrips(self):
        with sqlite3.connect(self.path) as connection:
            for table in ['local_occurrences', 'local_weekly_slots', 'local_plans', 'local_profiles']:
                connection.execute(f'DELETE FROM {table}')
        payload = self.module.export_fixture(self.path)
        self.path.write_bytes(self.module.database_from_snapshot(payload))
        self.assertTrue(all(not rows for rows in self.document()['tables'].values()))


if __name__ == '__main__':
    unittest.main()
