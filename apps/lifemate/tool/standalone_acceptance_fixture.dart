// Synthetic emulator-only entry point. This APK must never be distributed.
// The user APK is launched first; the host then upgrades its own fresh install.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lifemate/standalone/model.dart';
import 'package:lifemate/standalone/reminders.dart';
import 'package:lifemate/standalone/store.dart';
import 'package:path/path.dart' as paths;
import 'package:sqflite/sqflite.dart';

const _database = 'standalone_acceptance.sqlite';
const _companion = 'LifeGuide EMULATOR FIXTURE';
const _canary = 'SYNTHETIC_PRIVATE_TASK_CANARY';
const _weekly = '${_canary}_WEEK';
const _alternate = '${_canary}_EVERY_TWO';
const _once = '${_canary}_ONCE';
const _near = '${_canary}_NEAR';

void _require(bool condition) {
  if (!condition) throw StateError('synthetic_sqlite_assertion_failed');
}

Future<Database> _raw(String path, {bool readOnly = true}) =>
    databaseFactory.openDatabase(path,
        options:
            OpenDatabaseOptions(readOnly: readOnly, singleInstance: false));

Future<Map<String, Object?>> _metadata(String path) async {
  final db = await _raw(path);
  try {
    return (await db.rawQuery('SELECT * FROM acceptance_meta')).single;
  } finally {
    await db.close();
  }
}

Future<void> _writeMetadata(String path, Map<String, Object?> values,
    {bool create = false}) async {
  final db = await _raw(path, readOnly: false);
  try {
    if (create) {
      await db.execute('''CREATE TABLE acceptance_meta (
        singleton INTEGER PRIMARY KEY CHECK(singleton = 1),
        base_date TEXT NOT NULL, first_weekly_id TEXT NOT NULL,
        second_weekly_id TEXT NOT NULL, near_id TEXT NOT NULL,
        second_near_id TEXT, phase TEXT NOT NULL)''');
      await db.insert('acceptance_meta', {'singleton': 1, ...values});
    } else {
      _require(
          await db.update('acceptance_meta', values, where: 'singleton = 1') ==
              1);
    }
  } finally {
    await db.close();
  }
}

/// These queries run only after the application store has really closed. They
/// inspect the actual file without UI state, model serialization or a fake API.
Future<Map<String, bool>> _audit(String path) async {
  final db = await _raw(path);
  late final Map<String, Object?> meta;
  try {
    _require(
        (await db.rawQuery('PRAGMA quick_check')).single.values.single == 'ok');
    _require((await db.rawQuery('PRAGMA user_version')).single.values.single ==
        StandaloneStore.schemaVersion);
    final profiles = await db.rawQuery('SELECT * FROM local_profiles');
    _require(profiles.length == 1 &&
        profiles.single['display_name'] == 'EMULATOR SYNTHETIC ADULT' &&
        profiles.single['category'] == 'adult' &&
        profiles.single['companion_name'] == _companion);
    meta = (await db.rawQuery('SELECT * FROM acceptance_meta')).single;
    final phase = meta['phase'];
    _require(const {'seeded', 'changed', 'canceled'}.contains(phase));
    final plans = await db.rawQuery('SELECT * FROM local_plans');
    final weeklyPlan = plans.singleWhere((r) => r['title'] == _weekly);
    final everyPlan = plans.singleWhere((r) => r['title'] == _alternate);
    final oncePlan = plans.singleWhere((r) => r['title'] == _once);
    _require(weeklyPlan['recurrence'] == 'weekly' &&
        everyPlan['recurrence'] == 'everyTwoDays' &&
        oncePlan['recurrence'] == 'once');
    final slots = await db.rawQuery(
        'SELECT * FROM local_weekly_slots WHERE plan_id = ? ORDER BY start_minute',
        [weeklyPlan['id']]);
    _require(slots.length == 2 &&
        slots[0]['start_minute'] == 600 &&
        slots[0]['end_minute'] == 630 &&
        slots[1]['start_minute'] == 900 &&
        slots[1]['end_minute'] == 945 &&
        slots[0]['weekday'] != slots[1]['weekday']);
    final rows = await db.rawQuery('SELECT * FROM local_occurrences');
    final first = rows.singleWhere((r) => r['id'] == meta['first_weekly_id']);
    final second = rows.singleWhere((r) => r['id'] == meta['second_weekly_id']);
    _require(first['plan_id'] == weeklyPlan['id'] &&
        second['plan_id'] == weeklyPlan['id'] &&
        first['occurrence_date'] != second['occurrence_date'] &&
        second['title'] == _weekly &&
        second['start_minute'] == 900 &&
        second['end_minute'] == 945 &&
        second['completed'] == 0 &&
        second['archived'] == 0);
    final changed = phase != 'seeded';
    _require(first['title'] == (changed ? '${_weekly}_EDIT' : _weekly) &&
        first['start_minute'] == (changed ? 610 : 600) &&
        first['end_minute'] == (changed ? 640 : 630) &&
        first['completed'] == (changed ? 1 : 0) &&
        first['archived'] == 0);
    final base = StandaloneDate.parse(meta['base_date'] as String);
    final everyRows = rows
        .where((r) => r['plan_id'] == everyPlan['id'])
        .toList()
      ..sort((a, b) => (a['occurrence_date'] as String)
          .compareTo(b['occurrence_date'] as String));
    _require(everyRows.length == 4);
    for (var i = 0; i < 4; i++) {
      _require(everyRows[i]['occurrence_date'] ==
          StandaloneDate.key(StandaloneDate.addDays(base, i * 2)));
    }
    final onceRows = rows.where((r) => r['plan_id'] == oncePlan['id']).toList();
    _require(onceRows.length == 1 &&
        onceRows.single['occurrence_date'] ==
            StandaloneDate.key(StandaloneDate.addDays(base, 1)));
    _require(rows.length == (changed ? 9 : 8));
    if (phase == 'canceled') {
      final canceled =
          rows.singleWhere((r) => r['id'] == meta['second_near_id']);
      _require(canceled['completed'] == 1 &&
          canceled['archived'] == 1 &&
          plans.singleWhere(
                  (p) => p['id'] == canceled['plan_id'])['archived'] ==
              1);
    }
  } finally {
    await db.close();
  }
  // Reopen through the product store as a second persistence check. No
  // occurrences() call here: inspection must not materialize additional rows.
  final reopened = await StandaloneStore.open(path: path);
  try {
    _require((await reopened.profile())?.companionName == _companion);
    _require((await reopened.occurrence(meta['second_weekly_id'] as String))
            ?.completed ==
        false);
  } finally {
    await reopened.close();
  }
  return {
    'rawSqlAfterClose': true,
    'profilePersists': true,
    'weeklyDifferentTimes': true,
    'onceAndEveryTwoDays': true,
    if (meta['phase'] != 'seeded') 'independentEditAndTick': true,
    if (meta['phase'] == 'canceled') 'archivePersists': true,
  };
}

Future<StandaloneOccurrence> _createNear(StandaloneStore store,
    {required String suffix}) async {
  final now = DateTime.now();
  // Host aligns the real device clock before launch. No injected clock or
  // arbitrary native reminder timestamp substitutes for this stored record.
  final at = DateTime(now.year, now.month, now.day, now.hour, now.minute + 1);
  _require(at.difference(now).inSeconds >= 30);
  final minute = at.hour * 60 + at.minute;
  final plan = await store.createPlan(StandalonePlanDraft(
      title: '$_near$suffix',
      kind: StandalonePlanKind.task,
      recurrence: StandaloneRecurrence.once,
      startDate: StandaloneDate.only(at),
      startMinute: minute,
      endMinute: minute + 1,
      reminderMinutes: 0));
  return (await store.occurrences(
          from: StandaloneDate.only(at), through: StandaloneDate.only(at)))
      .singleWhere((o) => o.planId == plan.id);
}

Future<void> _seed(String path) async {
  _require(!await File(path).exists());
  final store = await StandaloneStore.open(path: path);
  final base = StandaloneDate.addDays(DateTime.now(), -14);
  late final StandaloneOccurrence near;
  late final List<StandaloneOccurrence> weekly;
  try {
    _require(await store.profile() == null);
    await store.createProfile(
        displayName: 'EMULATOR SYNTHETIC ADULT',
        category: StandaloneProfileCategory.adult,
        companionName: _companion);
    final plan = await store.createPlan(StandalonePlanDraft(
        title: _weekly,
        kind: StandalonePlanKind.task,
        recurrence: StandaloneRecurrence.weekly,
        startDate: base,
        untilDate: StandaloneDate.addDays(base, 6),
        startMinute: 600,
        endMinute: 630,
        weeklySlots: [
          StandaloneWeeklySlot(
              weekday: base.weekday, startMinute: 600, endMinute: 630),
          StandaloneWeeklySlot(
              weekday: StandaloneDate.addDays(base, 2).weekday,
              startMinute: 900,
              endMinute: 945),
        ]));
    await store.createPlan(StandalonePlanDraft(
        title: _alternate,
        kind: StandalonePlanKind.routine,
        recurrence: StandaloneRecurrence.everyTwoDays,
        startDate: base,
        untilDate: StandaloneDate.addDays(base, 6),
        startMinute: 700,
        endMinute: 730));
    await store.createPlan(StandalonePlanDraft(
        title: _once,
        kind: StandalonePlanKind.event,
        recurrence: StandaloneRecurrence.once,
        startDate: StandaloneDate.addDays(base, 1),
        startMinute: 800,
        endMinute: 830));
    weekly = (await store.occurrences(
            from: base, through: StandaloneDate.addDays(base, 6)))
        .where((o) => o.planId == plan.id)
        .toList();
    _require(weekly.length == 2);
    near = await _createNear(store, suffix: '_FIRST');
  } finally {
    await store.close();
  }
  await _writeMetadata(
      path,
      {
        'base_date': StandaloneDate.key(base),
        'first_weekly_id': weekly[0].id,
        'second_weekly_id': weekly[1].id,
        'near_id': near.id,
        'phase': 'seeded',
      },
      create: true);
}

Future<void> _change(String path) async {
  final meta = await _metadata(path);
  _require(meta['phase'] == 'seeded');
  final store = await StandaloneStore.open(path: path);
  late final StandaloneOccurrence near;
  try {
    await store.updateOccurrence(meta['first_weekly_id'] as String,
        title: '${_weekly}_EDIT',
        startMinute: 610,
        endMinute: 640,
        completed: true);
    _require((await store.occurrence(meta['second_weekly_id'] as String))
            ?.completed ==
        false);
    await store.updateOccurrence(meta['near_id'] as String, completed: true);
    near = await _createNear(store, suffix: '_SECOND');
  } finally {
    await store.close();
  }
  await _writeMetadata(path, {'second_near_id': near.id, 'phase': 'changed'});
}

Future<void> _cancel(String path) async {
  final meta = await _metadata(path);
  _require(meta['phase'] == 'changed');
  final store = await StandaloneStore.open(path: path);
  try {
    final near = await store.occurrence(meta['second_near_id'] as String);
    _require(near != null && near.remindAt!.isAfter(DateTime.now()));
    await store.updateOccurrence(near!.id, completed: true);
    await store.archiveOccurrence(near.id);
    await store.archivePlan(near.planId);
  } finally {
    await store.close();
  }
  await _writeMetadata(path, {'phase': 'canceled'});
}

/// This takes the pending occurrences back out of the actual SQLite store and
/// sends only their identity, instant and generic companion name to Android.
Future<StandaloneProfile> _profile(String path) async {
  final store = await StandaloneStore.open(path: path);
  try {
    final profile = await store.profile();
    _require(profile?.companionName == _companion);
    return profile!;
  } finally {
    await store.close();
  }
}

Future<DateTime?> _reconcile(String path, StandaloneReminderPort port,
    {bool enable = false}) async {
  final store = await StandaloneStore.open(path: path);
  try {
    final now = DateTime.now().toUtc();
    final rows = await store.pendingReminders(
        from: now, through: now.add(const Duration(minutes: 10)));
    _require(rows.length <= 1);
    final profile = await store.profile();
    _require(profile?.companionName == _companion);
    final reminders = rows
        .map((row) => LocalPersonalReminder(
            id: row.id,
            planItemId: row.id,
            profileId: profile!.id,
            scheduledAt: row.remindAt!.toUtc(),
            completed: row.completed,
            archived: row.archived))
        .toList();
    if (enable) {
      await port.enable(reminders,
          companionName: profile!.companionName, profileId: profile.id);
    } else {
      await port.reconcile(reminders,
          companionName: profile!.companionName, profileId: profile.id);
    }
    return rows.isEmpty ? null : rows.single.remindAt!.toUtc();
  } finally {
    await store.close();
  }
}

Future<Map<String, Object?>> runStandaloneFixture(String route,
    {required bool enabled, required bool debug, required bool android}) async {
  if (!enabled || !debug || !android) throw StateError('fixture_disabled');
  final uri = Uri.tryParse(route);
  const modes = {
    '/seed',
    '/inspect',
    '/change',
    '/cancel',
    '/off',
    '/settings'
  };
  if (uri == null ||
      uri.hasScheme ||
      uri.hasAuthority ||
      uri.hasFragment ||
      !modes.contains(uri.path) ||
      uri.queryParametersAll.length != 1 ||
      uri.queryParametersAll['nonce']?.length != 1 ||
      !RegExp(r'^[0-9a-f]{8,32}$')
          .hasMatch(uri.queryParameters['nonce'] ?? '')) {
    throw ArgumentError('invalid_fixture_route');
  }
  final path = paths.join(await getDatabasesPath(), _database);
  final port = StandaloneReminderPort();
  DateTime? at;
  Map<String, bool> checks = {};
  switch (uri.path) {
    case '/seed':
      final status = await port.status();
      _require(status.supported && status.permissionGranted);
      await _seed(path);
      checks = await _audit(path);
      at = await _reconcile(path, port, enable: true);
      _require(at != null);
    case '/inspect':
      checks = await _audit(path);
      break; // No enable/activate/replace: preserve native delivered generation.
    case '/change':
      await port.suspendUntilReconcile(profileId: (await _profile(path)).id);
      await _change(path);
      checks = await _audit(path);
      at = await _reconcile(path, port);
      _require(at != null);
    case '/cancel':
      await port.suspendUntilReconcile(profileId: (await _profile(path)).id);
      await _cancel(path);
      checks = await _audit(path);
      _require(await _reconcile(path, port) == null);
    case '/off':
      await port.disable(profileId: (await _profile(path)).id);
    case '/settings':
      // Existing fixture data only; no enable/reconcile/write belongs here.
      checks = await _audit(path);
      final before = await port.status(profileId: (await _profile(path)).id);
      _require(!before.enabled && !before.active && before.scheduledCount == 0);
      await port.openNotificationSettings();
  }
  final status = await port.status(profileId: (await _profile(path)).id);
  return {
    'nonce': uri.queryParameters['nonce'],
    'mode': uri.path.substring(1),
    'syntheticDataOnly': true,
    'database': _database,
    'checks': checks,
    if (at != null) 'scheduledAtEpochMs': at.millisecondsSinceEpoch,
    'status': {
      'supported': status.supported,
      'permissionGranted': status.permissionGranted,
      'active': status.active,
      'enabled': status.enabled,
      'activeScope': status.activeScope,
      'scheduledCount': status.scheduledCount,
      'timing': status.timing,
      'canScheduleExactAlarms': status.canScheduleExactAlarms,
    },
  };
}

Future<void> main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  final route = binding.platformDispatcher.defaultRouteName;
  const enabled = bool.fromEnvironment('LG_STANDALONE_ACCEPTANCE') &&
      bool.fromEnvironment('LIFEGUIDE_STANDALONE');
  final android = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  runApp(const MaterialApp(
      initialRoute: '/',
      home: Scaffold(
          body: SafeArea(
              child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                      'EMULATOR ONLY — SYNTHETIC DATA — NEVER DISTRIBUTE\n$_canary'))))));
  try {
    final result = await runStandaloneFixture(route,
        enabled: enabled, debug: kDebugMode, android: android);
    debugPrint('LG_STANDALONE_ACCEPTANCE ${jsonEncode(result)}');
  } catch (_) {
    // Arbitrary database exceptions, routes and private records are never logged.
    debugPrint('LG_STANDALONE_ACCEPTANCE_ERROR fixture_failed_closed');
  }
}
