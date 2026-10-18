import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate/local_reminders.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('lifeguide/local_reminders');
  const owner = '11111111-1111-4111-8111-111111111111',
      item = '22222222-2222-4222-8222-222222222222';
  const scope = 'https://fixture.invalid/api|$owner';
  final now = DateTime.utc(2026, 10, 18, 8);
  final calls = <MethodCall>[];
  late AndroidLocalReminderPort port;
  LocalReminder row(
          {String id = item,
          String ownerId = owner,
          bool ack = true,
          bool pending = false,
          DateTime? at,
          String name = 'همراه من'}) =>
      LocalReminder(
          id: id,
          planItemId: item,
          scheduledAt: at ?? now.add(const Duration(hours: 1)),
          companionName: name,
          ownerUserId: ownerId,
          serverAcknowledged: ack,
          pendingMutation: pending);
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    calls.clear();
    port = AndroidLocalReminderPort(now: () => now);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (['status', 'requestPermission', 'requestExactAlarmAccess']
          .contains(call.method)) {
        return {
          'supported': true,
          'permissionGranted': true,
          'active': true,
          'scheduledCount': 1,
          'timing': 'exact',
          'activeScope': scope,
          'validUntilEpochMs':
              now.add(const Duration(hours: 24)).millisecondsSinceEpoch,
          'exactAlarmSupported': true,
          'canScheduleExactAlarms': true
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
  test('foreign pending and unacknowledged records never reach native alarms',
      () async {
    await port.activate(scope, validUntil: now.add(const Duration(hours: 24)));
    for (final unsafe in [
      row(ownerId: '33333333-3333-4333-8333-333333333333'),
      row(ack: false),
      row(pending: true)
    ]) {
      await expectLater(port.replace(scope, [unsafe], currentUserId: owner),
          throwsArgumentError);
    }
    expect(calls.map((x) => x.method), ['activate']);
  });
  test('scope mismatch cannot replace reminders', () async {
    await port.activate(scope, validUntil: now.add(const Duration(hours: 24)));
    await expectLater(
        port.replace('other', [row()], currentUserId: owner), throwsStateError);
  });
  test('native payload excludes private task text and owner metadata',
      () async {
    await port.activate(scope, validUntil: now.add(const Duration(hours: 24)));
    await port.replace(scope, [row()], currentUserId: owner);
    expect(calls.last.arguments, {
      'scope': scope,
      'reminders': [
        {
          'id': item,
          'planItemId': item,
          'scheduledAtEpochMs':
              now.add(const Duration(hours: 1)).millisecondsSinceEpoch,
          'companionName': 'همراه من'
        }
      ]
    });
  });
  test('past and beyond-lease records are dropped', () async {
    await port.activate(scope, validUntil: now.add(const Duration(hours: 24)));
    await port.replace(
        scope,
        [
          row(at: now.subtract(const Duration(seconds: 1))),
          row(
              id: '44444444-4444-4444-8444-444444444444',
              at: now.add(const Duration(hours: 25)))
        ],
        currentUserId: owner);
    expect((calls.last.arguments as Map)['reminders'], isEmpty);
  });
  test('lease duplicates and control characters fail closed', () async {
    await expectLater(
        port.activate(scope, validUntil: now.add(const Duration(hours: 25))),
        throwsArgumentError);
    await port.activate(scope, validUntil: now.add(const Duration(hours: 24)));
    await expectLater(port.replace(scope, [row(), row()], currentUserId: owner),
        throwsArgumentError);
    await expectLater(
        port.replace(scope, [row(name: 'bad\nname')], currentUserId: owner),
        throwsArgumentError);
  });
  test('forty joined emoji fit nickname limit but forty-one do not', () async {
    await port.activate(scope, validUntil: now.add(const Duration(hours: 24)));
    final name = List.filled(40, '👩‍🔬').join();
    await port.replace(scope, [row(name: name)], currentUserId: owner);
    await expectLater(
        port.replace(scope, [row(name: '$name!')], currentUserId: owner),
        throwsArgumentError);
  });
  test('logout invalidates queued replacement before channel call', () async {
    final entered = Completer<void>(), release = Completer<void>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'activate') {
        entered.complete();
        await release.future;
      }
      return true;
    });
    final activating =
        port.activate(scope, validUntil: now.add(const Duration(hours: 24)));
    await entered.future.timeout(const Duration(seconds: 1));
    final replacing = port.replace(scope, [row()], currentUserId: owner);
    final deactivating = port.deactivate();
    release.complete();
    await Future.wait([activating, replacing, deactivating]);
    expect(calls.map((x) => x.method), ['activate', 'deactivate']);
  });
  test('offline suppression is scoped and opaque', () async {
    await port.activate(scope, validUntil: now.add(const Duration(hours: 24)));
    await port.suppressPlanItems(scope, {item});
    expect(calls.last.method, 'suppressPlanItems');
    expect(calls.last.arguments, {
      'scope': scope,
      'planItemIds': [item]
    });
    await expectLater(
        port.suppressPlanItems('other', {item}), throwsStateError);
    await expectLater(
        port.suppressPlanItems(scope, {'invalid'}), throwsArgumentError);
  });
  test('notification and exact-alarm permissions are separate user actions',
      () async {
    expect(calls, isEmpty);
    final normal = await port.requestPermission();
    expect(calls.last.method, 'requestPermission');
    expect(normal.activeScope, scope);
    expect(normal.validUntil, now.add(const Duration(hours: 24)));
    final exact = await port.requestExactAlarmAccess();
    expect(calls.last.method, 'requestExactAlarmAccess');
    expect(exact.canScheduleExactAlarms, isTrue);
    expect(exact.timing, 'exact');
  });
  test('missing plugin never claims background support', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    expect((await port.status()).supported, isFalse);
    await port.deactivate();
  });
  test('non-Android fallback never calls native scheduling', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect((await port.status()).supported, isFalse);
    await port.activate(scope, validUntil: now.add(const Duration(hours: 1)));
    await port.replace(scope, [row()], currentUserId: owner);
    await port.deactivate();
    expect(calls, isEmpty);
  });
}
