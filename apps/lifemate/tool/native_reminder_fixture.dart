// Emulator-only test entry point. Never import from lib/ or distribute its APK.
// No API, credentials, identity or real server acknowledgement is involved.
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lifemate/local_reminders.dart';

const owner = '11111111-1111-4111-8111-111111111111';
const plan = '22222222-2222-4222-8222-222222222222';
const reminder = '33333333-3333-4333-8333-333333333333';
const scope = 'emulator-fixture-v1|$owner';
const companion = 'LifeGuide EMULATOR FIXTURE';

/// The host additionally refuses physical devices and preinstalled packages.
/// Flags are injectable only to test this tool's fail-closed boundary.
Future<Map<String, Object?>> runFixture(String route,
    {required bool enabled,
    required bool debug,
    required bool android,
    DateTime Function()? now}) async {
  if (!enabled || !debug || !android) {
    throw StateError('fixture_disabled');
  }
  final uri = Uri.tryParse(route);
  const modes = {'/schedule', '/inspect', '/suppress', '/off'};
  if (uri == null ||
      uri.hasScheme ||
      uri.hasAuthority ||
      uri.hasFragment ||
      !modes.contains(uri.path) ||
      uri.queryParametersAll.entries.any((e) =>
          e.value.length != 1 ||
          !(e.key == 'nonce' ||
              (uri.path == '/schedule' && e.key == 'delay')))) {
    throw ArgumentError('invalid_fixture_route');
  }
  final nonce = uri.queryParameters['nonce'] ?? '';
  final delay = int.tryParse(uri.queryParameters['delay'] ?? '45');
  if (!RegExp(r'^[0-9a-f]{8,32}$').hasMatch(nonce) ||
      delay == null ||
      delay < 30 ||
      delay > 90) {
    throw ArgumentError('invalid_fixture_metadata');
  }
  final clock = now ?? DateTime.now;
  final port = AndroidLocalReminderPort(now: clock);
  DateTime? at;
  switch (uri.path) {
    case '/schedule':
      final before = await port.status();
      if (!before.supported || !before.permissionGranted) {
        throw StateError('fixture_permission_not_granted');
      }
      await port.deactivate();
      final utc = clock().toUtc();
      at = utc.add(Duration(seconds: delay));
      await port.activate(scope,
          validUntil: utc.add(const Duration(minutes: 10)));
      await port.replace(
          scope,
          [
            LocalReminder(
                id: reminder,
                planItemId: plan,
                scheduledAt: at,
                companionName: companion,
                ownerUserId: owner,
                serverAcknowledged: true)
          ],
          currentUserId: owner);
    case '/suppress':
      await port.suppressPlanItems(scope, {plan});
    case '/off':
      await port.deactivate();
    case '/inspect':
      break; // Intentionally no activate: preserve the stored generation.
  }
  final status = await port.status();
  return {
    'nonce': nonce,
    'mode': uri.path.substring(1),
    'simulatedServerAcknowledgement': true,
    if (at != null) 'scheduledAtEpochMs': at.millisecondsSinceEpoch,
    'status': {
      'supported': status.supported,
      'permissionGranted': status.permissionGranted,
      'active': status.active,
      'activeScope': status.activeScope,
      'scheduledCount': status.scheduledCount,
      'timing': status.timing,
      'canScheduleExactAlarms': status.canScheduleExactAlarms
    }
  };
}

Future<void> main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  final route = binding.platformDispatcher.defaultRouteName;
  const enabled = bool.fromEnvironment('LG_NATIVE_REMINDER_FIXTURE');
  final android = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  const label = 'EMULATOR ONLY — SYNTHETIC DATA — NOT THE APPLICATION';
  runApp(const MaterialApp(
      initialRoute: '/',
      home: Scaffold(
          body: SafeArea(
              child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('$label\nSYNTHETIC_PRIVATE_TASK_CANARY'))))));
  try {
    final result = await runFixture(route,
        enabled: enabled, debug: kDebugMode, android: android);
    debugPrint('LG_NATIVE_REMINDER_FIXTURE ${jsonEncode(result)}');
  } catch (_) {
    // Never dump native exceptions, routes or arbitrary storage into logs.
    debugPrint('LG_NATIVE_REMINDER_FIXTURE_ERROR fixture_failed_closed');
  }
}
