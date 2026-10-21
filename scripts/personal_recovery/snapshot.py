"""Portable, synthetic-only recovery snapshots of the standalone SQLite v1 store.

The application_id marker is an accident-prevention gate, not authentication or
proof of provenance: anyone can set it. This kit must never be used on owner data.
Only closed rollback-journal fixtures without sidecars are accepted. WAL-mode
headers are refused even after their sidecars have been removed.
"""
from datetime import date
import json
from pathlib import Path
import re
import sqlite3
import uuid

from .common import (
    FIXTURE_APPLICATION_ID, MAX_PAYLOAD_BYTES, MAX_ROWS, RecoveryError, SCHEMA_VERSION,
)
from .files import read_bounded

FORMAT = 'LifeGuideSyntheticRecovery'
# Fixed statements mirror StandaloneStore._migrate v1. Source SQL is never run.
DDL = (
    """CREATE TABLE local_profiles (
        singleton INTEGER PRIMARY KEY CHECK(singleton = 1),
        id TEXT NOT NULL UNIQUE CHECK(length(id) = 36),
        display_name TEXT NOT NULL CHECK(length(trim(display_name)) BETWEEN 1 AND 80),
        category TEXT NOT NULL CHECK(category IN ('girl_minor','boy_minor','adult')),
        companion_name TEXT NOT NULL CHECK(length(trim(companion_name)) BETWEEN 1 AND 40),
        theme_key TEXT NOT NULL CHECK(theme_key IN ('violet','blue','mint','coral'))
      )""",
    """CREATE TABLE local_plans (
        id TEXT PRIMARY KEY NOT NULL CHECK(length(id) = 36),
        profile_id TEXT NOT NULL REFERENCES local_profiles(id),
        title TEXT NOT NULL CHECK(length(trim(title)) BETWEEN 1 AND 200),
        kind TEXT NOT NULL CHECK(kind IN ('task','event','routine')),
        recurrence TEXT NOT NULL CHECK(recurrence IN ('once','daily','everyTwoDays','weekly')),
        start_date TEXT NOT NULL CHECK(length(start_date) = 10),
        until_date TEXT CHECK(until_date IS NULL OR (length(until_date) = 10 AND until_date >= start_date)),
        start_minute INTEGER NOT NULL CHECK(start_minute BETWEEN 0 AND 1439),
        end_minute INTEGER NOT NULL CHECK(end_minute BETWEEN 1 AND 1440 AND end_minute > start_minute),
        reminder_minutes INTEGER CHECK(reminder_minutes IS NULL OR reminder_minutes IN (0,5,10,15,30)),
        archived INTEGER NOT NULL DEFAULT 0 CHECK(archived IN (0,1))
      )""",
    """CREATE TABLE local_weekly_slots (
        plan_id TEXT NOT NULL REFERENCES local_plans(id),
        weekday INTEGER NOT NULL CHECK(weekday BETWEEN 1 AND 7),
        start_minute INTEGER NOT NULL CHECK(start_minute BETWEEN 0 AND 1439),
        end_minute INTEGER NOT NULL CHECK(end_minute BETWEEN 1 AND 1440 AND end_minute > start_minute),
        PRIMARY KEY(plan_id, weekday)
      )""",
    """CREATE TABLE local_occurrences (
        id TEXT PRIMARY KEY NOT NULL CHECK(length(id) = 36),
        plan_id TEXT NOT NULL REFERENCES local_plans(id),
        occurrence_date TEXT NOT NULL CHECK(length(occurrence_date) = 10),
        title TEXT NOT NULL CHECK(length(trim(title)) BETWEEN 1 AND 200),
        kind TEXT NOT NULL CHECK(kind IN ('task','event','routine')),
        start_minute INTEGER NOT NULL CHECK(start_minute BETWEEN 0 AND 1439),
        end_minute INTEGER NOT NULL CHECK(end_minute BETWEEN 1 AND 1440 AND end_minute > start_minute),
        completed INTEGER NOT NULL DEFAULT 0 CHECK(completed IN (0,1)),
        archived INTEGER NOT NULL DEFAULT 0 CHECK(archived IN (0,1)),
        reminder_minutes INTEGER CHECK(reminder_minutes IS NULL OR reminder_minutes IN (0,5,10,15,30)),
        UNIQUE(plan_id, occurrence_date)
      )""",
    'CREATE INDEX local_occurrences_date ON local_occurrences(occurrence_date)',
)
COLUMNS = {
    'local_profiles': ('singleton', 'id', 'display_name', 'category', 'companion_name', 'theme_key'),
    'local_plans': ('id', 'profile_id', 'title', 'kind', 'recurrence', 'start_date', 'until_date',
                    'start_minute', 'end_minute', 'reminder_minutes', 'archived'),
    'local_weekly_slots': ('plan_id', 'weekday', 'start_minute', 'end_minute'),
    'local_occurrences': ('id', 'plan_id', 'occurrence_date', 'title', 'kind', 'start_minute',
                          'end_minute', 'completed', 'archived', 'reminder_minutes'),
}
PRIMARY_KEYS = {
    'local_profiles': ('singleton',), 'local_plans': ('id',),
    'local_weekly_slots': ('plan_id', 'weekday'), 'local_occurrences': ('id',),
}
KINDS = ('task', 'event', 'routine')
RECURRENCES = ('once', 'daily', 'everyTwoDays', 'weekly')


def _require(condition):
    if not condition:
        raise RecoveryError('invalid_snapshot')


def _integer(value, minimum, maximum):
    _require(type(value) is int and minimum <= value <= maximum)


def _text(value, maximum):
    _require(type(value) is str and '\x00' not in value)
    try:
        length = len(value.strip().encode('utf-16-le')) // 2
    except UnicodeError:
        raise RecoveryError('invalid_snapshot') from None
    _require(1 <= length <= maximum)


def _uuid(value):
    _require(type(value) is str)
    try:
        parsed = uuid.UUID(value)
    except (ValueError, AttributeError):
        raise RecoveryError('invalid_snapshot') from None
    _require(str(parsed) == value and parsed.version == 4 and parsed.variant == uuid.RFC_4122)


def _date(value):
    _require(type(value) is str and re.fullmatch(r'[0-9]{4}-[0-9]{2}-[0-9]{2}', value))
    try:
        date.fromisoformat(value)
    except ValueError:
        raise RecoveryError('invalid_snapshot') from None


def _time(row):
    _integer(row['start_minute'], 0, 1439)
    _integer(row['end_minute'], 1, 1440)
    _require(row['end_minute'] > row['start_minute'])


def _reminder(value):
    _require(value is None or (type(value) is int and value in (0, 5, 10, 15, 30)))


def _validate(document):
    _require(type(document) is dict and set(document) == {'format', 'schemaVersion', 'syntheticOnly', 'tables'})
    _require(document['format'] == FORMAT and type(document['format']) is str)
    _require(type(document['schemaVersion']) is int and document['schemaVersion'] == SCHEMA_VERSION)
    _require(document['syntheticOnly'] is True)
    tables = document['tables']
    _require(type(tables) is dict and set(tables) == set(COLUMNS))
    total = 0
    for table, columns in COLUMNS.items():
        rows = tables[table]
        _require(type(rows) is list)
        total += len(rows)
        _require(total <= MAX_ROWS)
        for row in rows:
            _require(type(row) is dict and set(row) == set(columns))
    _require(len(tables['local_profiles']) <= 1)
    profile_ids = set()
    for row in tables['local_profiles']:
        _integer(row['singleton'], 1, 1)
        _uuid(row['id'])
        _text(row['display_name'], 80)
        _text(row['companion_name'], 40)
        _require(row['category'] in ('girl_minor', 'boy_minor', 'adult'))
        _require(row['theme_key'] in ('violet', 'blue', 'mint', 'coral'))
        profile_ids.add(row['id'])
    plans = {}
    for row in tables['local_plans']:
        _uuid(row['id'])
        _uuid(row['profile_id'])
        _require(row['id'] not in plans and row['profile_id'] in profile_ids)
        _text(row['title'], 200)
        _require(row['kind'] in KINDS and row['recurrence'] in RECURRENCES)
        _date(row['start_date'])
        if row['until_date'] is not None:
            _date(row['until_date'])
            _require(row['until_date'] >= row['start_date'])
        _time(row)
        _reminder(row['reminder_minutes'])
        _integer(row['archived'], 0, 1)
        plans[row['id']] = row
    slots = set()
    weekly_plan_ids = set()
    for row in tables['local_weekly_slots']:
        _uuid(row['plan_id'])
        _require(row['plan_id'] in plans and plans[row['plan_id']]['recurrence'] == 'weekly')
        _integer(row['weekday'], 1, 7)
        _time(row)
        key = (row['plan_id'], row['weekday'])
        _require(key not in slots)
        slots.add(key)
        weekly_plan_ids.add(row['plan_id'])
    _require(weekly_plan_ids == {p['id'] for p in plans.values() if p['recurrence'] == 'weekly'})
    occurrence_ids = set()
    occurrence_dates = set()
    for row in tables['local_occurrences']:
        _uuid(row['id'])
        _uuid(row['plan_id'])
        _require(row['plan_id'] in plans and row['id'] not in occurrence_ids)
        _date(row['occurrence_date'])
        key = (row['plan_id'], row['occurrence_date'])
        _require(key not in occurrence_dates)
        occurrence_dates.add(key)
        occurrence_ids.add(row['id'])
        _text(row['title'], 200)
        _require(row['kind'] in KINDS)
        _time(row)
        _integer(row['completed'], 0, 1)
        _integer(row['archived'], 0, 1)
        _reminder(row['reminder_minutes'])
    return {table: sorted(tables[table], key=lambda row: tuple(row[key] for key in PRIMARY_KEYS[table]))
            for table in COLUMNS}


def _document(tables):
    return {'format': FORMAT, 'schemaVersion': SCHEMA_VERSION, 'syntheticOnly': True, 'tables': tables}


def _canonical(document):
    payload = json.dumps(document, ensure_ascii=False, sort_keys=True, separators=(',', ':'),
                         allow_nan=False).encode('utf-8')
    if len(payload) > MAX_PAYLOAD_BYTES:
        raise RecoveryError('payload_too_large')
    return payload


def _new_database():
    connection = sqlite3.connect(':memory:')
    try:
        connection.execute('PRAGMA foreign_keys = ON')
        connection.execute(f'PRAGMA application_id = {FIXTURE_APPLICATION_ID}')
        connection.execute(f'PRAGMA user_version = {SCHEMA_VERSION}')
        for sql in DDL:
            connection.execute(sql)
    except BaseException:
        connection.close()
        raise
    return connection


def _normalize_sql(sql):
    if sql is None:
        return None
    # Preserve quoted literals exactly; ignore formatting between SQL tokens.
    return ''.join(token if token.startswith("'") else re.sub(r'\s+', '', token).lower()
                   for token in re.findall(r"'(?:''|[^'])*'|[^']+", sql))


def _schema(connection):
    return {(kind, name, table, _normalize_sql(sql)) for kind, name, table, sql in
            connection.execute('SELECT type,name,tbl_name,sql FROM sqlite_schema')}


def _validate_source_header(prefix):
    """Gate the first 100 bytes before reading any fixture body into memory."""
    if len(prefix) != 100 or prefix[:16] != b'SQLite format 3\x00':
        raise RecoveryError('invalid_source')
    if int.from_bytes(prefix[68:72], 'big') != FIXTURE_APPLICATION_ID:
        raise RecoveryError('synthetic_marker_required')
    if int.from_bytes(prefix[60:64], 'big') != SCHEMA_VERSION:
        raise RecoveryError('unsupported_schema')
    # A standalone image cannot resolve WAL state. Require rollback-journal
    # read/write versions rather than rewriting headers or ignoring WAL.
    if prefix[18:20] != b'\x01\x01':
        raise RecoveryError('source_not_closed')


def export_fixture(path: Path) -> bytes:
    """Read an explicitly marked, closed fixture without changing its files."""
    connection = None
    try:
        path = Path(path)
        if any(Path(str(path) + suffix).exists() for suffix in ('-wal', '-shm', '-journal')):
            raise RecoveryError('source_not_closed')
        # The shared descriptor-based reader checks the opened file's identity and
        # size. SQLite only sees these bounded bytes; it never reopens the path.
        source = read_bounded(path, MAX_PAYLOAD_BYTES, prefix_validator=_validate_source_header)
        connection = sqlite3.connect(':memory:')
        connection.deserialize(source)
        connection.execute('PRAGMA query_only = ON')
        connection.execute('PRAGMA trusted_schema = OFF')
        if connection.execute('PRAGMA application_id').fetchone() != (FIXTURE_APPLICATION_ID,):
            raise RecoveryError('synthetic_marker_required')
        if connection.execute('PRAGMA user_version').fetchone() != (SCHEMA_VERSION,):
            raise RecoveryError('unsupported_schema')
        reference = _new_database()
        try:
            expected_schema = _schema(reference)
        finally:
            reference.close()
        actual_schema = _schema(connection)
        android = ('table', 'android_metadata', 'android_metadata',
                   _normalize_sql('CREATE TABLE android_metadata (locale TEXT)'))
        if actual_schema not in (expected_schema, expected_schema | {android}):
            raise RecoveryError('unsupported_schema')
        if connection.execute('PRAGMA integrity_check').fetchall() != [('ok',)]:
            raise RecoveryError('invalid_source')
        if connection.execute('PRAGMA foreign_key_check').fetchall():
            raise RecoveryError('invalid_source')
        tables = {}
        total = 0
        for table, columns in COLUMNS.items():
            count = connection.execute(f'SELECT count(*) FROM {table}').fetchone()[0]
            total += count
            if total > MAX_ROWS:
                raise RecoveryError('too_many_rows')
            # All identifiers originate in this module's whitelist.
            values = connection.execute(f'SELECT {",".join(columns)} FROM {table}').fetchall()
            tables[table] = [dict(zip(columns, row)) for row in values]
        return _canonical(_document(_validate(_document(tables))))
    except (OSError, sqlite3.Error, ValueError, TypeError, UnicodeError, OverflowError):
        raise RecoveryError('invalid_source') from None
    finally:
        if connection is not None:
            connection.close()


def _unique_object(pairs):
    result = {}
    for key, value in pairs:
        _require(key not in result)
        result[key] = value
    return result


def _reject_constant(_value):
    raise RecoveryError('invalid_snapshot')


def database_from_snapshot(payload: bytes) -> bytes:
    """Validate JSON and rebuild in memory; never execute payload-supplied SQL."""
    if type(payload) is not bytes or len(payload) > MAX_PAYLOAD_BYTES:
        raise RecoveryError('invalid_snapshot')
    connection = None
    try:
        document = json.loads(payload.decode('utf-8'), object_pairs_hook=_unique_object,
                              parse_constant=_reject_constant)
        tables = _validate(document)
        connection = _new_database()
        for table, columns in COLUMNS.items():
            sql = f'INSERT INTO {table} ({",".join(columns)}) VALUES ({",".join("?" for _ in columns)})'
            connection.executemany(sql, [tuple(row[key] for key in columns) for row in tables[table]])
        connection.commit()
        if connection.execute('PRAGMA integrity_check').fetchall() != [('ok',)]:
            raise RecoveryError('invalid_snapshot')
        if connection.execute('PRAGMA foreign_key_check').fetchall():
            raise RecoveryError('invalid_snapshot')
        result = connection.serialize()
        if len(result) > MAX_PAYLOAD_BYTES:
            raise RecoveryError('payload_too_large')
        return result
    except (ValueError, TypeError, UnicodeError, OverflowError, RecursionError, sqlite3.Error):
        raise RecoveryError('invalid_snapshot') from None
    finally:
        if connection is not None:
            connection.close()


def create_sample_database() -> bytes:
    """Create explicit fictional QA records, all dated in 2024, entirely in memory."""
    profile_id = '11111111-1111-4111-8111-111111111111'
    plan_ids = [f'{n:08d}-2222-4222-8222-222222222222' for n in range(1, 5)]
    tables = {table: [] for table in COLUMNS}
    tables['local_profiles'] = [dict(zip(COLUMNS['local_profiles'],
        (1, profile_id, 'Fictional آزمایشی', 'girl_minor', 'Fictional همراه', 'violet')))]
    for index, recurrence in enumerate(RECURRENCES):
        values = (plan_ids[index], profile_id, f'Fictional {recurrence}',
                  KINDS[index % len(KINDS)], recurrence, '2024-01-01',
                  None if index == 0 else '2024-02-29', 480 + index * 60,
                  510 + index * 60, (None, 5, 15, 30)[index], int(index == 3))
        tables['local_plans'].append(dict(zip(COLUMNS['local_plans'], values)))
        values = (f'{index + 1:08d}-3333-4333-8333-333333333333', plan_ids[index],
                  '2024-01-01', f'Fictional edited occurrence {index + 1}',
                  KINDS[(index + 1) % len(KINDS)], 800 + index * 20, 810 + index * 20,
                  int(index % 2 == 1), int(index == 3), (0, None, 10, 30)[index])
        tables['local_occurrences'].append(dict(zip(COLUMNS['local_occurrences'], values)))
    tables['local_weekly_slots'] = [dict(zip(COLUMNS['local_weekly_slots'],
                                            (plan_ids[3], weekday, start, start + 45)))
                                    for weekday, start in ((1, 600), (4, 900), (7, 1000))]
    return database_from_snapshot(_canonical(_document(tables)))
