import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../tool/native_reminder_fixture.dart' as fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('lifeguide/local_reminders');
  final calls = <MethodCall>[];
  final now = DateTime.utc(2026, 10, 19, 8);
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'status') {
        return {
          'supported': true,
          'permissionGranted': true,
          'active': true,
          'activeScope': fixture.scope,
          'scheduledCount': 1,
          'timing': 'exact',
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
  test('disabled and non-Android fixtures never reach native storage',
      () async {
    for (final flags in [
      (false, true, true),
      (true, false, true),
      (true, true, false)
    ]) {
      await expectLater(
          fixture.runFixture('/schedule?nonce=0123456789abcdef&delay=45',
              enabled: flags.$1,
              debug: flags.$2,
              android: flags.$3,
              now: () => now),
          throwsStateError);
      expect(calls, isEmpty);
    }
  });
  test('unknown commands and malformed metadata fail before channel access',
      () async {
    for (final route in [
      '/',
      '/other?nonce=01234567',
      '/schedule?nonce=bad&delay=45',
      '/schedule?nonce=01234567&delay=0',
      '/schedule?nonce=01234567&delay=999',
      '/inspect?nonce=01234567&owner=private',
      '/inspect?nonce=01234567&nonce=abcdef01',
      'https://example.invalid/inspect?nonce=01234567'
    ]) {
      await expectLater(
          fixture.runFixture(route,
              enabled: true, debug: true, android: true, now: () => now),
          throwsArgumentError);
      expect(calls, isEmpty);
    }
  });
  test('schedule uses production port with only synthetic opaque metadata',
      () async {
    final result = await fixture.runFixture(
        '/schedule?nonce=0123456789abcdef&delay=45',
        enabled: true,
        debug: true,
        android: true,
        now: () => now);
    expect(calls.map((c) => c.method),
        ['status', 'deactivate', 'activate', 'replace', 'status']);
    final payload =
        calls.singleWhere((c) => c.method == 'replace').arguments as Map;
    expect(payload['scope'], fixture.scope);
    expect(payload['reminders'], [
      {
        'id': fixture.reminder,
        'planItemId': fixture.plan,
        'scheduledAtEpochMs':
            now.add(const Duration(seconds: 45)).millisecondsSinceEpoch,
        'companionName': fixture.companion
      }
    ]);
    expect(result['simulatedServerAcknowledgement'], isTrue);
    expect(result['mode'], 'schedule');
    expect(result.toString(), isNot(contains('SYNTHETIC_PRIVATE_TASK_CANARY')));
  });
  test('inspect after restart reads without resetting persisted generation',
      () async {
    await fixture.runFixture('/inspect?nonce=0123456789abcdef',
        enabled: true, debug: true, android: true, now: () => now);
    expect(calls.map((c) => c.method), ['status']);
  });
  test('suppression and off do not reactivate a previous fixture', () async {
    await fixture.runFixture('/suppress?nonce=0123456789abcdef',
        enabled: true, debug: true, android: true, now: () => now);
    expect(calls.map((c) => c.method), ['suppressPlanItems', 'status']);
    calls.clear();
    await fixture.runFixture('/off?nonce=0123456789abcdef',
        enabled: true, debug: true, android: true, now: () => now);
    expect(calls.map((c) => c.method), ['deactivate', 'status']);
  });
}
