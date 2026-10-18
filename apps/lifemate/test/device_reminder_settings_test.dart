import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:lifemate/api.dart';
import 'package:lifemate/device_reminder_coordinator.dart';
import 'package:lifemate/device_reminder_preferences.dart';
import 'package:lifemate/device_reminder_settings.dart';
import 'package:lifemate/local_reminders.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

class _Port implements LocalReminderPort {
  _Port({this.supported = true});
  final bool supported;
  int exactRequests = 0;
  @override
  Future<LocalReminderStatus> status() async => LocalReminderStatus(
      supported: supported,
      permissionGranted: supported,
      active: false,
      scheduledCount: 0,
      exactAlarmSupported: supported);
  @override
  Future<LocalReminderStatus> requestExactAlarmAccess() async {
    exactRequests++;
    return status();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData({});
  });
  HttpIdentityApi api() => HttpIdentityApi(
      baseUrl: 'https://fixture.invalid/api',
      client: MockClient((_) async => throw StateError('Unexpected network')))
    ..accessToken = 'synthetic-access'
    ..currentUserId = '11111111-1111-4111-8111-111111111111';
  testWidgets(
      'unsupported device shows honest background state and disabled opt-in',
      (tester) async {
    final client = api(), port = _Port(supported: false);
    await tester.pumpWidget(MaterialApp(
        home: DeviceReminderSettingsPage(
            api: client,
            coordinator: DeviceReminderCoordinator(client, port: port))));
    await tester.pumpAndSettle();
    expect(find.text('اعلان پس‌زمینه در این دستگاه پشتیبانی نمی‌شود.'),
        findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
  });
  testWidgets(
      'nickname save remains scoped and exact permission is user initiated',
      (tester) async {
    final client = api(), port = _Port();
    await tester.pumpWidget(MaterialApp(
        home: DeviceReminderSettingsPage(
            api: client,
            coordinator: DeviceReminderCoordinator(client, port: port))));
    await tester.pumpAndSettle();
    expect(port.exactRequests, 0);
    await tester.enterText(
        find.byKey(const ValueKey('companion-nickname')), 'همراه من');
    await tester.tap(find.text('ذخیرهٔ نام همراه'));
    await tester.pumpAndSettle();
    expect(await DeviceReminderPreferences().read(client.cacheNamespace!),
        'همراه من');
    expect(
        await DeviceReminderPreferences().read('https://other.invalid|other'),
        'LifeGuide');
    await tester.ensureVisible(find.text('اجازهٔ زمان‌بندی دقیق'));
    await tester.tap(find.text('اجازهٔ زمان‌بندی دقیق'));
    await tester.pumpAndSettle();
    expect(port.exactRequests, 1);
  });
}
