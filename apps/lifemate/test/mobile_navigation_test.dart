import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate/main.dart';
import 'package:lifemate/api.dart';
import 'package:lifemate/phase3_ui.dart';
import 'package:lifemate/education_ui.dart';
import 'package:lifemate/study_ui.dart';
import 'package:lifemate/dashboard_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'app_test.dart' show FakeApi;

class MenuApi extends FakeApi {
  MenuApi({this.category = 'girl_minor'});
  final String category;
  bool failProfile = false;
  @override
  Future<Map<String, dynamic>> getProfile() async {
    if (failProfile) throw const ApiException(503, 'profile_unavailable');
    return {
      'user_id': 'synthetic-menu-user',
      'display_name': 'کاربر نمونه',
      'profile_category': category,
      'theme_preference': 'adult_blue',
    };
  }

  @override
  Future<List<Map<String, dynamic>>> listFamilies() async => [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final fonts = FontLoader('LifeGuidePersian')
      ..addFont(rootBundle.load('assets/fonts/LifeGuidePersian.ttf'));
    await fonts.load();
    WidgetController.hitTestWarningShouldBeFatal = true;
  });

  setUp(() {
    String? token;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('lifeguide/local_write_guard'), (call) async {
      if (call.method == 'getBlocked') return token != null;
      if (call.method == 'beginWrite') return token = 'synthetic-menu-write';
      if (call.method == 'completeWrite' && call.arguments == token) {
        token = null;
        return true;
      }
      throw PlatformException(code: 'local_storage_restart_required');
    });
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData({});
  });
  Future<void> shell(WidgetTester tester, MenuApi api) async {
    await tester.pumpWidget(MaterialApp(
        theme: ThemeData(fontFamily: 'LifeGuidePersian'),
        home: Directionality(
            textDirection: TextDirection.rtl, child: HomeShell(api: api))));
    await tester.pumpAndSettle();
  }

  for (final size in [const Size(390, 844), const Size(320, 740)]) {
    testWidgets(
        'compact home menus open separate destinations and back at $size',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await shell(tester, MenuApi());
      expect(find.textContaining('کاربر نمونه'), findsOneWidget);
      for (final entry in {
        'plan': PlannerPage,
        'courses': EducationLibraryPage,
        'focus': StudyHub,
        'family': ProfileFamilyPage
      }.entries) {
        final menu = find.byKey(ValueKey('home-${entry.key}'));
        expect(menu.hitTestable(), findsOneWidget);
        expect(tester.getRect(menu).bottom, lessThan(size.height - 50));
        await tester.tap(menu);
        await tester.pumpAndSettle();
        expect(find.byType(entry.value), findsOneWidget);
        expect(find.byKey(const ValueKey('home-plan')), findsNothing);
        await tester.tap(find.byTooltip('برگشت به خانه'));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('home-plan')), findsOneWidget);
      }
      for (final key in ['report', 'reminders']) {
        expect(find.byKey(ValueKey('home-$key')).hitTestable(), findsOneWidget);
        await tester.tap(find.byKey(ValueKey('home-$key')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('home-plan')), findsNothing);
        await tester.tap(find.byTooltip('برگشت به خانه'));
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets('large text remains reachable without layout overflow',
      (tester) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        theme: ThemeData(fontFamily: 'LifeGuidePersian'),
        home: MediaQuery(
            data: const MediaQueryData(
                size: Size(320, 740), textScaler: TextScaler.linear(1.6)),
            child: Directionality(
                textDirection: TextDirection.rtl,
                child: HomeShell(api: MenuApi())))));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('home-reminders')), 150,
        scrollable: find
            .descendant(
                of: find.byKey(const ValueKey('home-scroll')),
                matching: find.byType(Scrollable))
            .first);
    expect(find.byKey(const ValueKey('home-reminders')).hitTestable(),
        findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'adult home does not depend on family membership or grant parent access',
      (tester) async {
    await shell(tester, MenuApi(category: 'adult'));
    expect(find.byKey(const ValueKey('home-family')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-report')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-courses')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('home-report')));
    await tester.pumpAndSettle();
    expect(find.byType(ParentFamilyDashboard), findsOneWidget);
    expect(find.byType(LearningReportPage), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'profile failure does not guess a child or parent home and can retry',
      (tester) async {
    final api = MenuApi()..failProfile = true;
    await shell(tester, api);
    expect(find.byKey(const ValueKey('home-plan')), findsNothing);
    api.failProfile = false;
    await tester.tap(find.text('تلاش دوباره').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-plan')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
