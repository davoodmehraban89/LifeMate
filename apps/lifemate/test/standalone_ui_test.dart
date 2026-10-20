import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate/standalone/app.dart';
import 'package:lifemate/standalone/model.dart';
import 'package:lifemate/standalone/settings_ui.dart';
import 'package:lifemate/standalone/store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory directory;
  late String path;
  late StandaloneStore store;

  setUpAll(() async {
    sqfliteFfiInit();
    await (FontLoader('LifeGuidePersian')
          ..addFont(rootBundle.load('assets/fonts/LifeGuidePersian.ttf')))
        .load();
  });
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('lifeguide-ui-');
    path = '${directory.path}/planner.sqlite';
    // The same SQLite engine and schema as Android, without a background
    // isolate so widget-test fake time does not stall a database message.
    store = await StandaloneStore.open(
        path: path, factory: databaseFactoryFfiNoIsolate);
  });
  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  Future<void> idle(WidgetTester tester) async {
    var idleFrames = 0;
    for (var i = 0; i < 500; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await tester.pumpAndSettle();
      final busy =
          find.byType(CircularProgressIndicator).evaluate().isNotEmpty ||
              find.text('در حال ذخیره…').evaluate().isNotEmpty;
      idleFrames = busy ? 0 : idleFrames + 1;
      if (idleFrames >= 3) return;
    }
    fail('SQLite-backed UI did not become idle.');
  }

  Future<void> open(WidgetTester tester,
      {Future<void> Function(StandaloneStore)? before,
      Future<void> Function(StandaloneStore)? after}) async {
    await tester.pumpWidget(StandaloneApp(
        openStore: () async => store,
        onBeforePlansChange: before,
        onPlansChanged: after));
    await idle(tester);
  }

  Future<void> tap(WidgetTester tester, Finder target) async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (find.byType(SnackBar).evaluate().isNotEmpty) {
      // Dismiss the prior transient result before the next independent action.
      ScaffoldMessenger.of(tester.element(find.byType(SnackBar)))
          .removeCurrentSnackBar();
    }
    await tester.pumpAndSettle();
    if (target.evaluate().isEmpty) {
      await tester.scrollUntilVisible(target, 200,
          scrollable: find.byType(Scrollable).first, maxScrolls: 30);
    }
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await idle(tester);
  }

  Future<void> chooseRepeat(WidgetTester tester, String label) async {
    await tap(tester, find.byKey(const Key('plan-recurrence')));
    await tap(tester, find.text(label).last);
  }

  Future<void> profile() => store.createProfile(
      displayName: 'کاربر ساختگی',
      category: StandaloneProfileCategory.girlMinor);

  Future<void> seedDaily() async {
    await profile();
    await store.createPlan(StandalonePlanDraft(
        title: 'برنامهٔ آزمایشی',
        kind: StandalonePlanKind.task,
        recurrence: StandaloneRecurrence.daily,
        startDate: StandaloneDate.only(DateTime.now()),
        startMinute: 540,
        endMinute: 600));
  }

  testWidgets('onboarding and daily save commit before reminder reconciliation',
      (tester) async {
    await tester.runAsync(() async {
      final events = <String>[];
      await open(tester, before: (actual) async {
        events.add('invalidate:${(await actual.listPlans()).length}');
      }, after: (actual) async {
        events.add('reconcile:${(await actual.listPlans()).length}');
      });
      expect(find.textContaining('بدون حساب و سرور'), findsOneWidget);
      expect(await store.profile(), isNull);
      await tester.enterText(find.byType(TextField), 'نام ساختگی');
      await tap(tester,
          find.byType(DropdownButtonFormField<StandaloneProfileCategory>));
      await tap(tester, find.text('دختر').last);
      await tap(tester, find.text('شروع برنامهٔ من'));
      expect(find.text('سلام نام ساختگی'), findsOneWidget);
      expect(await store.listPlans(), isEmpty);
      await tap(tester, find.text('برنامهٔ تازه'));
      await tester.enterText(
          find.byKey(const Key('plan-title')), 'قدم روزانهٔ ساختگی');
      await chooseRepeat(tester, 'هر روز');
      await tap(tester, find.text('ذخیرهٔ برنامه'));
      expect(events, ['invalidate:0', 'reconcile:1']);
      expect((await store.listPlans()).single.recurrence,
          StandaloneRecurrence.daily);
      await tap(tester, find.byType(Checkbox));
      final today = StandaloneDate.only(DateTime.now());
      final occurrences = await store.occurrences(
          from: today, through: StandaloneDate.addDays(today, 1));
      expect(occurrences.first.completed, isTrue);
      expect(occurrences.last.completed, isFalse);
      await tester.pumpWidget(const SizedBox());
      await store.close();
      store = await StandaloneStore.open(
          path: path, factory: databaseFactoryFfiNoIsolate);
      await open(tester);
      expect(find.text('سلام نام ساختگی'), findsOneWidget);
      expect(find.textContaining('۱ از ۱'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('one occurrence edit and whole-plan archive preserve other dates',
      (tester) async {
    await tester.runAsync(() async {
      await seedDaily();
      await open(tester);
      await tap(tester, find.text('شروع'));
      await tap(tester, find.text('ویرایش همین نوبت'));
      await tester.enterText(
          find.byKey(const Key('occurrence-title')), 'عنوان مستقل');
      await tap(tester, find.text('ثبت تغییر همین نوبت'));
      final today = StandaloneDate.only(DateTime.now());
      var items = await store.occurrences(
          from: today, through: StandaloneDate.addDays(today, 1));
      expect(items.first.title, 'عنوان مستقل');
      expect(items.last.title, 'برنامهٔ آزمایشی');
      await tap(tester, find.text('انجام شد'));
      await tap(tester, find.text('بایگانی…'));
      await tap(tester, find.text('کل برنامه و همهٔ نوبت‌های آینده'));
      expect(await store.listPlans(), isEmpty);
      items = await store.occurrences(
          from: today,
          through: StandaloneDate.addDays(today, 1),
          includeArchived: true);
      expect(items.first.completed, isTrue);
      expect(items.last.completed, isFalse);
      expect(
          find.text('برای این روز هنوز برنامه‌ای ننوشته‌ای.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('weekly editor persists different hours for selected weekdays',
      (tester) async {
    await tester.runAsync(() async {
      await profile();
      await open(tester);
      await tap(tester, find.text('برنامهٔ تازه'));
      await tester.enterText(
          find.byKey(const Key('plan-title')), 'هفتهٔ ساختگی');
      await chooseRepeat(tester, 'روزهای انتخابی هفته');
      await tap(tester, find.byKey(const Key('plan-weekday-6')));
      await tap(tester, find.byKey(const Key('plan-weekday-7')));
      final saturdayHours = find.byKey(const Key('weekly-hours-6'));
      await tap(
          tester,
          find
              .descendant(
                  of: saturdayHours, matching: find.byType(OutlinedButton))
              .last);
      final fields = find.descendant(
          of: find.byType(TimePickerDialog), matching: find.byType(TextField));
      await tester.enterText(fields.at(0), '11');
      await tester.enterText(fields.at(1), '30');
      await tap(tester, find.widgetWithText(TextButton, 'تأیید'));
      await tap(tester, find.text('ذخیرهٔ برنامه'));
      final plan = (await store.listPlans()).single;
      expect(plan.recurrence, StandaloneRecurrence.weekly);
      expect(plan.weeklySlots.map((slot) => slot.weekday), [6, 7]);
      expect(plan.weeklySlots.map((slot) => slot.endMinute), [690, 600]);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets(
      'SQLite failure retains editor; committed reminder failure does not',
      (tester) async {
    await tester.runAsync(() async {
      await profile();
      final db = await databaseFactoryFfiNoIsolate.openDatabase(path);
      await db.execute('''CREATE TRIGGER synthetic_write_failure
      BEFORE INSERT ON local_plans BEGIN
      SELECT RAISE(ABORT, 'synthetic disk-write failure'); END''');
      await open(tester,
          after: (_) async => throw StateError('synthetic alarm'));
      await tap(tester, find.text('برنامهٔ تازه'));
      await tester.enterText(find.byKey(const Key('plan-title')), 'حفظ فرم');
      await chooseRepeat(tester, 'یک روز در میان');
      await tap(tester, find.text('ذخیرهٔ برنامه'));
      expect(await store.listPlans(), isEmpty);
      await tester.scrollUntilVisible(find.byKey(const Key('plan-title')), -200,
          scrollable: find.byType(Scrollable).first);
      expect(
          tester
              .widget<TextField>(find.byKey(const Key('plan-title')))
              .controller!
              .text,
          'حفظ فرم');
      await tester.scrollUntilVisible(
          find.text('برنامه ذخیره نشد. می‌توانی دوباره تلاش کنی.'), 200,
          scrollable: find.byType(Scrollable).first);
      expect(find.text('برنامه ذخیره نشد. می‌توانی دوباره تلاش کنی.'),
          findsOneWidget);
      await db.execute('DROP TRIGGER synthetic_write_failure');
      await tap(tester, find.text('ذخیرهٔ برنامه'));
      expect((await store.listPlans()).single.recurrence,
          StandaloneRecurrence.everyTwoDays);
      expect(find.byKey(const Key('plan-title')), findsNothing);
      expect(
          find.text(
              'برنامه ذخیره شد؛ آماده‌سازی یادآوری را در تنظیمات بررسی کن.'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('onboarding reload failure never recreates a committed profile',
      (tester) async {
    await tester.runAsync(() async {
      var reloads = 0;
      await tester.pumpWidget(MaterialApp(
          home: StandaloneOnboarding(
              store: store,
              onSaved: () async {
                reloads++;
                if (reloads == 1) throw StateError('synthetic read failure');
              })));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'نام محفوظ');
      await tap(tester,
          find.byType(DropdownButtonFormField<StandaloneProfileCategory>));
      await tap(tester, find.text('بزرگسال').last);
      await tap(tester, find.text('شروع برنامهٔ من'));
      final id = (await store.profile())!.id;
      expect(find.textContaining('نام روی این گوشی ذخیره شد'), findsOneWidget);
      await tap(tester, find.text('باز کردن برنامهٔ من'));
      expect((await store.profile())!.id, id);
      expect(reloads, 2);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets(
      '320 wide at 200 percent keeps onboarding, pages and settings usable',
      (tester) async {
    await tester.runAsync(() async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await open(tester);
      await tester.scrollUntilVisible(find.byType(TextField), 180,
          scrollable: find.byType(Scrollable).first);
      await tester.enterText(find.byType(TextField), 'نام ساختگی');
      await tap(tester,
          find.byType(DropdownButtonFormField<StandaloneProfileCategory>));
      await tap(tester, find.text('پسر').last);
      await tap(tester, find.text('شروع برنامهٔ من'));
      expect(tester.takeException(), isNull);
      await tap(
          tester,
          find.descendant(
              of: find.byType(NavigationBar), matching: find.text('هفته')));
      expect(tester.takeException(), isNull);
      await tap(
          tester,
          find.descendant(
              of: find.byType(NavigationBar), matching: find.text('تنظیمات')));
      await tap(tester, find.text('سبز نعنایی'));
      await tap(tester, find.text('ذخیرهٔ تغییرها'));
      expect((await store.profile())!.themeKey, 'mint');
      await tap(tester, find.text('مرجانی گرم'));
      await tap(tester, find.text('ذخیرهٔ تغییرها'));
      expect((await store.profile())!.themeKey, 'coral');
      expect(tester.takeException(), isNull);
      await tap(
          tester,
          find.descendant(
              of: find.byType(NavigationBar), matching: find.text('امروز')));
      await tap(tester, find.text('برنامهٔ تازه'));
      await chooseRepeat(tester, 'روزهای انتخابی هفته');
      await tap(tester, find.byKey(const Key('plan-weekday-6')));
      await tap(tester, find.text('ذخیرهٔ برنامه'));
      expect(find.text('یک عنوان برای برنامه بنویس.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
  testWidgets('resume reads committed plans before reminder reconciliation',
      (tester) async {
    await tester.runAsync(() async {
      await seedDaily();
      var resumed = 0;
      await tester.pumpWidget(StandaloneApp(
          openStore: () async => store,
          onResumed: (actual) async {
            expect(await actual.listPlans(), hasLength(1));
            resumed++;
          }));
      await idle(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await idle(tester);
      expect(resumed, 1);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('failed profile write restores reminders from unchanged SQLite',
      (tester) async {
    await tester.runAsync(() async {
      await profile();
      final db = await databaseFactoryFfiNoIsolate.openDatabase(path);
      await db.execute(
          "CREATE TRIGGER reject_profile BEFORE UPDATE ON local_profiles BEGIN SELECT RAISE(ABORT, 'synthetic write failure'); END");
      final events = <String>[];
      await open(tester,
          before: (_) async => events.add('suspend'),
          after: (actual) async =>
              events.add('restore:${(await actual.profile())!.displayName}'));
      await tap(
          tester,
          find.descendant(
              of: find.byType(NavigationBar), matching: find.text('تنظیمات')));
      await tester.enterText(find.byType(TextField).first, 'نام ذخیره نشده');
      await tap(tester, find.text('ذخیرهٔ تغییرها'));
      expect(events, ['suspend', 'restore:کاربر ساختگی']);
      expect((await store.profile())!.displayName, 'کاربر ساختگی');
      expect(find.textContaining('تغییرها ذخیره نشد'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
