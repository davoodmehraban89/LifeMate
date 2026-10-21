import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate/standalone/model.dart';
import 'package:lifemate/standalone/reminder_coordinator.dart';
import 'package:lifemate/standalone/reminder_settings.dart';
import 'package:lifemate/standalone/reminders.dart';
import 'package:lifemate/standalone/store.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  const channel = MethodChannel('lifeguide/device_planner_reminders');
  final now = DateTime(2026, 10, 21, 8);
  late Directory directory;
  late StandaloneStore store;
  late StandaloneReminderCoordinator coordinator;
  final methods = <String>[];
  bool enabled = false, active = false, failSettings = false;
  bool permissionGranted = true;
  int scheduled = 0;

  setUpAll(() async {
    sqfliteFfiInit();
    await (FontLoader('LifeGuidePersian')
          ..addFont(rootBundle.load('assets/fonts/LifeGuidePersian.ttf')))
        .load();
  });
  setUp(() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    enabled = false;
    active = false;
    failSettings = false;
    permissionGranted = true;
    scheduled = 0;
    methods.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      methods.add(call.method);
      if (call.method == 'openNotificationSettings' && failSettings) {
        throw PlatformException(code: 'settings_unavailable');
      }
      if (call.method == 'setEnabled')
        enabled = (call.arguments as Map)['enabled'] == true;
      if (call.method == 'activate') active = true;
      if (call.method == 'deactivate') {
        active = false;
        scheduled = 0;
      }
      if (call.method == 'replace')
        scheduled = ((call.arguments as Map)['reminders'] as List).length;
      if (['status', 'requestPermission', 'requestExactAlarmAccess']
          .contains(call.method)) {
        return {
          'supported': true,
          'enabled': enabled,
          'permissionGranted': permissionGranted,
          'active': active,
          'scheduledCount': scheduled,
          'timing': 'approximate'
        };
      }
      return true;
    });
    directory = await Directory.systemTemp.createTemp('lifeguide-reminder-ui-');
    store = await StandaloneStore.open(
        path: '${directory.path}/planner.sqlite',
        factory: databaseFactoryFfiNoIsolate);
    await store.createProfile(
        displayName: 'نمونه ساختگی',
        category: StandaloneProfileCategory.girlMinor);
    await store.createPlan(StandalonePlanDraft(
        title: 'برنامهٔ ساختگی',
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
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  Future<void> idle(WidgetTester tester) async {
    for (var i = 0; i < 100; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await tester.pumpAndSettle();
      if (find.byType(LinearProgressIndicator).evaluate().isEmpty &&
          coordinator.status != null) return;
    }
    fail('Reminder settings never finished reading actual SQLite.');
  }

  Future<void> open(WidgetTester tester, {double scale = 1}) async {
    await tester.pumpWidget(MaterialApp(
        theme: ThemeData(fontFamily: 'LifeGuidePersian'),
        locale: const Locale('fa'),
        supportedLocales: const [Locale('fa')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!),
        home: StandaloneReminderSettings(
            store: store, coordinator: coordinator)));
    await idle(tester);
  }

  Future<void> openSystemSettings(WidgetTester tester) async {
    final button =
        find.byKey(const Key('personal-notification-system-settings'));
    expect(button, findsOneWidget);
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'system notification settings never opts in or changes saved plans',
      (tester) async {
    await tester.runAsync(() async {
      await open(tester);
      final before = (await store.listPlans()).single;
      methods.clear();
      await openSystemSettings(tester);
      expect(methods, ['openNotificationSettings']);
      expect(enabled, isFalse);
      expect(coordinator.status!.enabled, isFalse);
      expect((await store.listPlans()).single.id, before.id);
      expect(tester.takeException(), isNull);
    });
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  testWidgets('failed settings intent leaves existing reminder schedule intact',
      (tester) async {
    await tester.runAsync(() async {
      await coordinator.enable(store);
      await open(tester);
      final before = coordinator.status!;
      expect(scheduled, 1);
      failSettings = true;
      methods.clear();
      await openSystemSettings(tester);
      expect(methods, ['openNotificationSettings']);
      expect(enabled, isTrue);
      expect(active, isTrue);
      expect(scheduled, 1);
      expect(coordinator.status, same(before));
      expect(find.textContaining('تنظیمات اعلان باز نشد'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('return from Android settings rereads permission and stays OFF',
      (tester) async {
    await tester.runAsync(() async {
      await open(tester);
      await openSystemSettings(tester);
      methods.clear();
      permissionGranted = false;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await idle(tester);
      expect(methods, contains('status'));
      expect(methods, isNot(contains('requestPermission')));
      expect(methods, isNot(contains('setEnabled')));
      expect(methods, isNot(contains('activate')));
      expect(coordinator.status!.enabled, isFalse);
      expect(coordinator.status!.permissionGranted, isFalse);
      expect(find.textContaining('مجوز اعلان: داده نشده'), findsOneWidget);
      expect((await store.listPlans()), hasLength(1));
      expect(tester.takeException(), isNull);
    });
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets(
      'sound settings is usable at width 320 and text scale 200 percent',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      await open(tester, scale: 2);
      final button =
          find.byKey(const Key('personal-notification-system-settings'));
      await tester.ensureVisible(button);
      final size = tester.getSize(button);
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
      expect(size.width, lessThanOrEqualTo(320));
      methods.clear();
      await openSystemSettings(tester);
      expect(methods, ['openNotificationSettings']);
      expect(tester.takeException(), isNull);
    });
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
