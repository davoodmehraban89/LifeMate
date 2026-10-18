import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Widget tests have no Android alarm service. Keep its default inactive and
/// deterministic; local_reminders_test overrides this boundary explicitly.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('lifeguide/local_reminders'), (call) async {
      if (const {'status', 'requestPermission', 'requestExactAlarmAccess'}
          .contains(call.method)) {
        return <String, Object?>{
          'supported': true,
          'permissionGranted': false,
          'active': false,
          'scheduledCount': 0,
          'timing': 'approximate',
        };
      }
      return true;
    });
  });
  await testMain();
}
