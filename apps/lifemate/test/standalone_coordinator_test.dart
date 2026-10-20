import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate/standalone/model.dart';
import 'package:lifemate/standalone/reminder_coordinator.dart';
import 'package:lifemate/standalone/reminders.dart';
import 'package:lifemate/standalone/store.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);
  late Directory directory;
  late StandaloneStore store;
  late StandaloneReminderCoordinator coordinator;
  final now = DateTime(2026, 10, 19, 8);
  final calls = <String>[];
  bool enabled = false, active = false;
  List<dynamic> rows = [];
  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    calls.clear();
    enabled = false;
    active = false;
    rows = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('lifeguide/device_planner_reminders'),
            (call) async {
      calls.add(call.method);
      if (call.method == 'setEnabled') {
        enabled = (call.arguments as Map)['enabled'] == true;
      }
      if (call.method == 'activate') active = true;
      if (call.method == 'deactivate') {
        active = false;
        rows = [];
      }
      if (call.method == 'replace') {
        rows = (call.arguments as Map)['reminders'] as List;
      }
      if (['status', 'requestPermission', 'requestExactAlarmAccess']
          .contains(call.method)) {
        return {
          'supported': true,
          'enabled': enabled,
          'permissionGranted': true,
          'active': active,
          'scheduledCount': rows.length,
          'timing': 'approximate'
        };
      }
      return true;
    });
    directory = await Directory.systemTemp.createTemp('lifeguide-coordinator-');
    store = await StandaloneStore.open(
        path: '${directory.path}/planner.sqlite', factory: databaseFactoryFfi);
    await store.createProfile(
        displayName: 'نمونه ساختگی',
        category: StandaloneProfileCategory.girlMinor);
    await store.createPlan(StandalonePlanDraft(
        title: 'عنوان خصوصی ساختگی',
        kind: StandalonePlanKind.task,
        recurrence: StandaloneRecurrence.once,
        startDate: now,
        startMinute: 600,
        endMinute: 660,
        reminderMinutes: 5));
    coordinator = StandaloneReminderCoordinator(
        port: StandaloneReminderPort(now: () => now), now: () => now);
  });
  tearDown(() async {
    coordinator.dispose();
    await store.close();
    await directory.delete(recursive: true);
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('lifeguide/device_planner_reminders'), null);
  });
  test(
      'startup is OFF; committed row schedules without private title; completion cancels',
      () async {
    await coordinator.refresh(store);
    expect(coordinator.status!.enabled, isFalse);
    expect(calls, isNot(contains('requestPermission')));
    await coordinator.enable(store);
    expect(rows, hasLength(1));
    expect(rows.single.toString(), isNot(contains('عنوان خصوصی')));
    final occurrence =
        (await store.occurrences(from: now, through: now)).single;
    expect((rows.single as Map)['id'], occurrence.id);
    await coordinator.beforeChange(store);
    expect(active, isFalse);
    await coordinator.refresh(store);
    expect(active, isFalse,
        reason: 'resume cannot restore alarms during a write');
    await store.updateOccurrence(occurrence.id, completed: true);
    await coordinator.afterChange(store);
    expect(rows, isEmpty);
    expect(coordinator.status!.enabled, isTrue);
  });
  test('failed authoritative read cancels old alarms and exposes an error',
      () async {
    await coordinator.enable(store);
    expect(rows, hasLength(1));
    await store.close();
    await expectLater(coordinator.refresh(store), throwsA(anything));
    expect(active, isFalse);
    expect(coordinator.error, isNotNull);
  });
}
