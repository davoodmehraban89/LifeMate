import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate/standalone/reminders.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

final class FailingOffPreferences extends InMemorySharedPreferencesAsync {
  FailingOffPreferences() : super.empty();
  bool failOff = false;
  @override
  Future<bool> setBool(
      String key, bool value, SharedPreferencesOptions options) {
    if (!value && failOff) throw StateError('Preference disk unavailable');
    return super.setBool(key, value, options);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('lifeguide/device_planner_reminders');
  const profile = '11111111-1111-4111-8111-111111111111';
  const item = '22222222-2222-4222-8222-222222222222';
  final now = DateTime.utc(2026, 10, 19, 8);
  final calls = <MethodCall>[];
  late StandaloneReminderPort port;
  late FailingOffPreferences preferences;
  bool nativeEnabled = false, active = false, supported = true;
  int scheduled = 0;
  List<dynamic> payload = [];
  Future<void> Function(MethodCall)? intercept;
  LocalPersonalReminder row(
          {String id = item,
          String profileId = profile,
          DateTime? at,
          bool completed = false,
          bool archived = false}) =>
      LocalPersonalReminder(
          id: id,
          planItemId: id,
          profileId: profileId,
          scheduledAt: at ?? now.add(const Duration(hours: 1)),
          completed: completed,
          archived: archived);
  String idAt(int index) =>
      '${index.toRadixString(16).padLeft(8, '0')}-2222-4222-8222-222222222222';

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    preferences = FailingOffPreferences();
    SharedPreferencesAsyncPlatform.instance = preferences;
    port = StandaloneReminderPort(now: () => now);
    nativeEnabled = false;
    active = false;
    supported = true;
    scheduled = 0;
    payload = [];
    calls.clear();
    intercept = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (intercept != null) await intercept!(call);
      if (!supported) {
        return {
          'supported': false,
          'enabled': false,
          'permissionGranted': false,
          'active': false,
          'scheduledCount': 0,
          'timing': 'approximate'
        };
      }
      if (call.method == 'setEnabled') {
        nativeEnabled = (call.arguments as Map)['enabled'] == true;
        if (!nativeEnabled) {
          active = false;
          scheduled = 0;
          payload = [];
        }
      }
      if (call.method == 'activate') active = true;
      if (call.method == 'replace') {
        payload = (call.arguments as Map)['reminders'] as List;
        scheduled = payload.length;
      }
      if (call.method == 'deactivate') {
        active = false;
        scheduled = 0;
        payload = [];
      }
      if (['status', 'requestPermission', 'requestExactAlarmAccess']
          .contains(call.method)) {
        return {
          'supported': true,
          'enabled': nativeEnabled,
          'permissionGranted': true,
          'active': active,
          'scheduledCount': scheduled,
          'timing': 'approximate',
          'activeScope': active ? 'device-planner:v1:$profile' : null,
          'validUntilEpochMs': active
              ? now.add(const Duration(days: 31)).millisecondsSinceEpoch
              : null,
          'exactAlarmSupported': true,
          'canScheduleExactAlarms': false
        };
      }
      return true;
    });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('opening and reconciliation remain OFF without permission prompts',
      () async {
    expect((await port.status(profileId: profile)).enabled, isFalse);
    final result = await port
        .reconcile([row()], companionName: 'همراه من', profileId: profile);
    expect(result.enabled, isFalse);
    expect(result.active, isFalse);
    expect(calls.map((call) => call.method), isNot(contains('activate')));
    expect(
        calls.map((call) => call.method), isNot(contains('requestPermission')));
  });
  test(
      'explicit enable selects next 28 days and soonest 128 with opaque payload',
      () async {
    final rows = List.generate(
        130, (i) => row(id: idAt(i), at: now.add(Duration(minutes: 130 - i))));
    rows.addAll([
      row(id: idAt(131), at: now.subtract(const Duration(seconds: 1))),
      row(id: idAt(132), at: now.add(const Duration(days: 29))),
      row(id: idAt(133), completed: true),
      row(id: idAt(134), archived: true)
    ]);
    final result =
        await port.enable(rows, companionName: 'همراه من', profileId: profile);
    expect(result.enabled, isTrue);
    expect(result.active, isTrue);
    expect(result.eligibleCount, 130);
    expect(result.selectedCount, 128);
    expect(result.scheduledCount, 128);
    expect(calls.where((call) => call.method == 'requestPermission'),
        hasLength(1));
    final activation = calls.singleWhere((call) => call.method == 'activate');
    expect((activation.arguments as Map)['validUntilEpochMs'],
        now.add(const Duration(days: 31)).millisecondsSinceEpoch);
    expect((payload.first as Map)['id'], idAt(129));
    expect((payload.last as Map)['id'], idAt(2));
    expect(
        (payload.first as Map).keys,
        unorderedEquals(
            ['id', 'planItemId', 'scheduledAtEpochMs', 'companionName']));
  });
  test('completed and archived stay cancelled after restored choice', () async {
    await port.enable([row()], companionName: 'همراه من', profileId: profile);
    await port.suspendUntilReconcile(profileId: profile);
    expect(nativeEnabled, isTrue);
    expect(active, isFalse);
    calls.clear();
    final reopened = StandaloneReminderPort(now: () => now);
    final result = await reopened.reconcile(
        [row(completed: true), row(id: idAt(3), archived: true)],
        companionName: 'همراه من', profileId: profile);
    expect(result.enabled, isTrue);
    expect(result.scheduledCount, 0);
    expect(payload, isEmpty);
    expect(
        calls.map((call) => call.method), isNot(contains('requestPermission')));
  });
  test('suspension invalidates in-flight scheduling and fresh DB read restores',
      () async {
    await port.enable([row()], companionName: 'همراه من', profileId: profile);
    final entered = Completer<void>(), release = Completer<void>();
    intercept = (call) async {
      if (call.method == 'activate' && !entered.isCompleted) {
        entered.complete();
        await release.future;
      }
    };
    calls.clear();
    final updating =
        port.reconcile([row()], companionName: 'همراه من', profileId: profile);
    await entered.future;
    final suspending = port.suspendUntilReconcile(profileId: profile);
    release.complete();
    await Future.wait([updating, suspending]);
    expect(active, isFalse);
    expect(nativeEnabled, isTrue);
    expect(calls.map((call) => call.method), isNot(contains('replace')));
    intercept = null;
    await StandaloneReminderPort(now: () => now)
        .reconcile([row()], companionName: 'همراه من', profileId: profile);
    expect(active, isTrue);
    expect(scheduled, 1);
  });
  test('OFF invalidates an activation already in flight', () async {
    final entered = Completer<void>(), release = Completer<void>();
    intercept = (call) async {
      if (call.method == 'activate') {
        entered.complete();
        await release.future;
      }
    };
    final enabling =
        port.enable([row()], companionName: 'همراه من', profileId: profile);
    await entered.future;
    final disabling = port.disable(profileId: profile);
    release.complete();
    await Future.wait([enabling, disabling]);
    expect(nativeEnabled, isFalse);
    expect(active, isFalse);
    expect(calls.map((call) => call.method), isNot(contains('replace')));
    await StandaloneReminderPort(now: () => now)
        .reconcile([row()], companionName: 'همراه من', profileId: profile);
    expect(active, isFalse);
  });
  test('failed Dart OFF write cancels native; stale ON cannot resurrect',
      () async {
    await port.enable([row()], companionName: 'همراه من', profileId: profile);
    preferences.failOff = true;
    await expectLater(port.disable(profileId: profile), throwsStateError);
    expect(nativeEnabled, isFalse);
    expect(active, isFalse);
    final result = await StandaloneReminderPort(now: () => now)
        .reconcile([row()], companionName: 'همراه من', profileId: profile);
    expect(result.enabled, isFalse);
    expect(result.active, isFalse);
    expect(scheduled, 0);
  });
  test('invalid profiles, IDs, timestamps and names never schedule', () async {
    for (final invalid in [
      row(profileId: idAt(5)),
      row(id: 'not-a-uuid'),
      row(at: DateTime(2026, 10, 19, 9))
    ]) {
      expect(
          () => port
              .enable([invalid], companionName: 'همراه من', profileId: profile),
          throwsArgumentError);
    }
    expect(
        () => port
            .enable([row()], companionName: 'bad\nname', profileId: profile),
        throwsArgumentError);
    expect(
        () => port.enable([row()],
            companionName: List.filled(41, '👩‍🔬').join(), profileId: profile),
        throwsArgumentError);
    expect(calls, isEmpty);
  });
  test('unsupported native build and missing plugin are honest', () async {
    supported = false;
    final unavailable = await port
        .enable([row()], companionName: 'همراه من', profileId: profile);
    expect(unavailable.supported, isFalse);
    expect(unavailable.enabled, isFalse);
    await port.disable(profileId: profile);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    expect(
        (await StandaloneReminderPort().status(profileId: profile)).supported,
        isFalse);
  });
  test('non-Android never reaches native or claims background support',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(
        (await port
                .enable([row()], companionName: 'همراه من', profileId: profile))
            .supported,
        isFalse);
    await port
        .reconcile([row()], companionName: 'همراه من', profileId: profile);
    await port.disable(profileId: profile);
    expect(calls, isEmpty);
  });
}
