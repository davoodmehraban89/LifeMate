import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate/api.dart';
import 'package:lifemate/local_data_store.dart';
import 'package:lifemate/local_only_api.dart';
import 'package:lifemate/main.dart';
import 'package:lifemate/phase3_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'app_test.dart' show FakeApi;
import 'local_test_preferences.dart' show resetNativeLocalWriteGuard;

// This simulates the preferences plugin boundary, not Android process restart.
final class _ControlledWrites extends InMemorySharedPreferencesAsync {
  _ControlledWrites(super.data) : super.withData();
  bool failWrites = false;
  Completer<void>? pendingWrite;

  @override
  Future<bool> setString(
      String key, String value, SharedPreferencesOptions options) async {
    if (pendingWrite != null) await pendingWrite!.future;
    if (failWrites) throw StateError('simulated persistent storage failure');
    return super.setString(key, value, options);
  }
}

late LocalDataSession _testSession;
const _restartMessage =
    'وضعیت ذخیره نامشخص است. برنامه را از تنظیمات دستگاه «توقف اجباری» کن و دوباره باز کن.';

LocalOnlyApi _open(
        {String category = 'girl_minor', LocalDataSession? session}) =>
    LocalOnlyApi(
      category: category,
      displayName: 'آرام مهرآیین',
      store: LocalDataStore(
          category: category,
          displayName: 'آرام مهرآیین',
          session: session ?? _testSession),
    );

// This inspects the simulated native snapshot independently of a poisoned API.
Future<Map<String, dynamic>> _nativeSnapshot() async =>
    jsonDecode((await SharedPreferencesAsync().getString(LocalDataStore.key))!)
        as Map<String, dynamic>;

Future<LocalOnlyApi> _restartProcessMock() async {
  // This plugin mock fails before publishing, so its snapshot is confirmed disk.
  // Replace both native process state and the preferences adapter explicitly.
  final raw = await SharedPreferencesAsync().getString(LocalDataStore.key);
  resetNativeLocalWriteGuard();
  SharedPreferencesAsyncPlatform.instance =
      _ControlledWrites({if (raw != null) LocalDataStore.key: raw});
  return _open(session: LocalDataSession());
}

Future<void> _expectRestartRequired(Future<Object?> operation) async {
  await expectLater(
      operation,
      throwsA(isA<ApiException>().having(
        (error) => error.code,
        'code',
        'local_storage_restart_required',
      )));
}

Future<_ControlledWrites> _controlWrites(
    WidgetTester tester, LocalOnlyApi api) async {
  await api.getProfile();
  return SharedPreferencesAsyncPlatform.instance! as _ControlledWrites;
}

class _RoleChangingApi extends FakeApi {
  String currentRole = 'teen_minor';

  @override
  Future<List<Map<String, dynamic>>> listFamilies() async => [
        {'id': 'family-1', 'name': 'خانواده', 'role': currentRole},
      ];
}

class _ProductionItemApi extends FakeApi {
  @override
  Future<List<Map<String, dynamic>>> listPlanItems({
    DateTime? from,
    DateTime? to,
    String? kind,
  }) async =>
      [
        {'id': 'server-item', 'kind': 'task', 'title': 'کار سرور'},
      ];
}

Future<void> _planner(WidgetTester tester, LocalOnlyApi api) async {
  await tester.pumpWidget(MaterialApp(
    key: UniqueKey(),
    home: Scaffold(body: PlannerPage(api: api, localOnly: true)),
  ));
  await tester.pumpAndSettle();
}

Future<void> _createForm(WidgetTester tester,
    {String title = 'تمرین ریاضی'}) async {
  await tester.tap(find.text('جدید'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('plan-title')), title);
}

Future<void> _itemMenu(WidgetTester tester, String action) async {
  await tester.tap(find.byType(PopupMenuButton<String>));
  await tester.pumpAndSettle();
  await tester.tap(find.text(action));
  await tester.pumpAndSettle();
}

void _localWidgetTest(String name, Future<void> Function(WidgetTester) body) {
  testWidgets(name, (tester) async {
    await tester.runAsync(() => body(tester));
  });
}

void main() {
  setUp(() {
    resetNativeLocalWriteGuard();
    _testSession = LocalDataSession();
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesAsyncPlatform.instance = _ControlledWrites({});
  });

  test('restart-required storage errors describe full process recovery', () {
    expect(
        localDataErrorText(
            const ApiException(500, 'local_storage_restart_required')),
        _restartMessage);
  });

  _localWidgetTest('saved assignment survives recreated planner UI',
      (tester) async {
    await _planner(tester, _open());
    await _createForm(tester);
    await tester.tap(find.byKey(const Key('plan-kind')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تکلیف').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('ذخیره'));
    await tester.pumpAndSettle();

    await _planner(tester, _open());
    expect(find.text('تمرین ریاضی'), findsOneWidget);
    expect((await _open().listPlanItems()).single['kind'], 'assignment');
  });

  _localWidgetTest('planner requires a title before saving', (tester) async {
    await _planner(tester, _open());
    await _createForm(tester, title: '   ');
    await tester.tap(find.text('ذخیره'));
    await tester.pumpAndSettle();

    expect(find.text('عنوان را وارد کن.'), findsOneWidget);
    expect(await _open().listPlanItems(), isEmpty);
  });

  _localWidgetTest('local planner keeps older and future saved items visible',
      (tester) async {
    await _open().createPlanItem({
      'kind': 'assignment',
      'title': 'تکلیف قبلی',
      'dueAt': DateTime.now()
          .subtract(const Duration(days: 40))
          .toUtc()
          .toIso8601String(),
    });
    await _open().createPlanItem({
      'kind': 'task',
      'title': 'کار آینده',
      'dueAt': DateTime.now()
          .add(const Duration(days: 40))
          .toUtc()
          .toIso8601String(),
    });
    await _planner(tester, _open());

    expect(find.text('تکلیف قبلی'), findsOneWidget);
    expect(find.text('کار آینده'), findsOneWidget);
  });

  _localWidgetTest('edited title survives recreated planner UI',
      (tester) async {
    await _open().createPlanItem({
      'kind': 'assignment',
      'title': 'تمرین ریاضی',
      'dueAt': DateTime.now().toUtc().toIso8601String(),
    });
    await _planner(tester, _open());
    await _itemMenu(tester, 'ویرایش عنوان');
    await tester.enterText(find.byKey(const Key('plan-title')), 'تمرین علوم');
    await tester.tap(find.text('ذخیره'));
    await tester.pumpAndSettle();

    await _planner(tester, _open());
    expect(find.text('تمرین علوم'), findsOneWidget);
    expect(find.text('تمرین ریاضی'), findsNothing);
  });

  _localWidgetTest('archive requires confirmation and survives recreated UI',
      (tester) async {
    await _open().createPlanItem({
      'kind': 'assignment',
      'title': 'تمرین ریاضی',
      'dueAt': DateTime.now().toUtc().toIso8601String(),
    });
    await _planner(tester, _open());
    await _itemMenu(tester, 'بایگانی');
    expect(find.text('بایگانی مورد'), findsOneWidget);
    await tester.tap(find.text('انصراف'));
    await tester.pumpAndSettle();
    expect(find.text('تمرین ریاضی'), findsOneWidget);

    await _itemMenu(tester, 'بایگانی');
    await tester.tap(find.widgetWithText(FilledButton, 'بایگانی'));
    await tester.pumpAndSettle();
    await _planner(tester, _open());
    expect(find.text('تمرین ریاضی'), findsNothing);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: TodayPage(api: _open(), localOnly: true)),
    ));
    await tester.pumpAndSettle();
    expect(find.text('تمرین ریاضی'), findsNothing);
  });

  _localWidgetTest(
      'uncertain local save needs full process restart without sync queue',
      (tester) async {
    final api = _open();
    final platform = await _controlWrites(tester, api);
    await _planner(tester, api);
    platform.failWrites = true;
    await _createForm(tester);
    await tester.tap(find.text('ذخیره'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text(_restartMessage), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect((await _nativeSnapshot())['items'], isEmpty);
    await _expectRestartRequired(_open().listPlanItems());
    expect(
        (await SharedPreferences.getInstance())
            .containsKey('phase3.sync.queue'),
        isFalse);

    platform.failWrites = false;
    await tester.tap(find.text('ذخیره'));
    await tester.pumpAndSettle();
    expect(find.text(_restartMessage), findsOneWidget);
    expect((await _nativeSnapshot())['items'], isEmpty);
    await _expectRestartRequired(api.listPlanItems());

    final restarted = await _restartProcessMock();
    expect(await restarted.listPlanItems(), isEmpty);
    await _planner(tester, restarted);
    await _createForm(tester);
    await tester.tap(find.text('ذخیره'));
    await tester.pumpAndSettle();
    expect((await restarted.listPlanItems()).single['title'], 'تمرین ریاضی');
  });

  _localWidgetTest('save button stays disabled until durable write completes',
      (tester) async {
    final api = _open();
    final platform = await _controlWrites(tester, api);
    await _planner(tester, api);
    await _createForm(tester);
    platform.pendingWrite = Completer<void>();
    await tester.tap(find.text('ذخیره'));
    await tester.pump();

    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'در حال ذخیره...'),
    );
    expect(button.onPressed, isNull);
    platform.pendingWrite!.complete();
    platform.pendingWrite = null;
    await tester.pumpAndSettle();
    expect(await _open().listPlanItems(), hasLength(1));
  });

  _localWidgetTest(
      'uncertain Today completion stays visible without server cache or queue',
      (tester) async {
    final api = _open();
    await api.createPlanItem({
      'kind': 'assignment',
      'title': 'تمرین ریاضی',
      'dueAt': DateTime.now().toUtc().toIso8601String(),
    });
    final platform = await _controlWrites(tester, api);
    const serverCache = '[{"id":"server-item","title":"نسخه سرور"}]';
    SharedPreferences.setMockInitialValues({'phase3.today.cache': serverCache});
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: TodayPage(api: api, localOnly: true)),
    ));
    await tester.pumpAndSettle();
    expect(find.text('تمرین ریاضی'), findsOneWidget);
    expect(find.text('نسخه سرور'), findsNothing);
    platform.failWrites = true;
    await tester.tap(find.byTooltip('انجام شد'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text(_restartMessage), findsOneWidget);
    expect(find.text('تمرین ریاضی'), findsOneWidget);
    final legacy = await SharedPreferences.getInstance();
    expect(legacy.getString('phase3.today.cache'), serverCache);
    expect(legacy.containsKey('phase3.sync.queue'), isFalse);
    expect(((await _nativeSnapshot())['items'] as List).single['status'],
        'planned');
    platform.failWrites = false;
    await tester.tap(find.text('تلاش دوباره'));
    await tester.pumpAndSettle();
    expect(find.text(_restartMessage), findsOneWidget);
    expect(find.text('تمرین ریاضی'), findsOneWidget);
    await _expectRestartRequired(api.listPlanItems());

    final restarted = await _restartProcessMock();
    expect((await restarted.listPlanItems()).single['status'], 'planned');
    await tester.pumpWidget(MaterialApp(
      key: UniqueKey(),
      home: Scaffold(body: TodayPage(api: restarted, localOnly: true)),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('انجام شد'));
    await tester.pumpAndSettle();
    expect(find.text('تمرین ریاضی'), findsNothing);
  });

  _localWidgetTest(
      'uncertain reschedule preserves confirmed data until full process restart',
      (tester) async {
    final api = _open();
    final start = DateTime.now();
    final due = start.add(const Duration(hours: 2));
    await api.createPlanItem({
      'kind': 'assignment',
      'title': 'تمرین ریاضی',
      'startsAt': start.toUtc().toIso8601String(),
      'dueAt': due.toUtc().toIso8601String(),
    });
    final platform = await _controlWrites(tester, api);
    await _planner(tester, api);
    platform.failWrites = true;
    await _itemMenu(tester, 'انتقال به فردا');

    expect(tester.takeException(), isNull);
    expect(find.text(_restartMessage), findsOneWidget);
    expect(((await _nativeSnapshot())['items'] as List).single['starts_at'],
        start.toUtc().toIso8601String());
    expect(
        (await SharedPreferences.getInstance())
            .containsKey('phase3.sync.queue'),
        isFalse);
    platform.failWrites = false;
    await tester.tap(find.text('تلاش دوباره'));
    await tester.pumpAndSettle();
    expect(find.text(_restartMessage), findsOneWidget);
    await _expectRestartRequired(api.listPlanItems());

    final restarted = await _restartProcessMock();
    expect((await restarted.listPlanItems()).single['starts_at'],
        start.toUtc().toIso8601String());
    await _planner(tester, restarted);
    await _itemMenu(tester, 'انتقال به فردا');
    final restored = (await restarted.listPlanItems()).single;
    expect(restored['starts_at'],
        start.add(const Duration(days: 1)).toUtc().toIso8601String());
    expect(restored['due_at'],
        due.add(const Duration(days: 1)).toUtc().toIso8601String());
  });

  _localWidgetTest(
      'local read error is visible and retries without cached server data',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'phase3.planner.cache': jsonEncode([
        {'id': 'server-item', 'title': 'نسخه سرور', 'kind': 'task'},
      ]),
    });
    await SharedPreferencesAsync().setString(LocalDataStore.key, '{invalid');
    await _planner(tester, _open());
    expect(find.textContaining('اطلاعات ذخیره‌شده روی دستگاه خراب است'),
        findsOneWidget);
    expect(find.text('هنوز برنامه‌ای نداری'), findsNothing);
    expect(find.text('نسخه سرور'), findsNothing);
    expect(find.text('جدید'), findsNothing);

    await SharedPreferencesAsync().remove(LocalDataStore.key);
    await _open().createPlanItem({
      'kind': 'task',
      'title': 'بعد از بازیابی',
      'dueAt': DateTime.now().toUtc().toIso8601String(),
    });
    await tester.tap(find.text('تلاش دوباره'));
    await tester.pumpAndSettle();
    expect(find.text('بعد از بازیابی'), findsOneWidget);
  });

  for (final category in ['girl_minor', 'boy_minor', 'adult']) {
    _localWidgetTest('$category routes by profile category without a family',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: HomeShell(
            api: _open(category: category),
            localOnly: true,
            profileCategory: category),
      ));
      await tester.pumpAndSettle();
      expect(find.byType(NavigationDestination), findsNWidgets(3));
      expect(find.text('حالت محلی · فقط روی این دستگاه'), findsOneWidget);
      expect(find.text('آرام مهرآیین'), findsOneWidget);
      expect(find.byType(SchoolPage), findsNothing);
      await tester
          .tap(find.text(category == 'adult' ? 'برنامه‌ریز' : 'برنامه'));
      await tester.pumpAndSettle();
      expect(find.text(category == 'adult' ? 'برنامه‌ریز' : 'برنامه هفتگی'),
          findsWidgets);
      expect(find.byType(PlannerPage), findsOneWidget);
    });
  }

  _localWidgetTest('local profile exposes only name and theme editing',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: HomeShell(
          api: _open(), localOnly: true, profileCategory: 'girl_minor'),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('پروفایل'));
    await tester.pumpAndSettle();

    expect(find.text('آرام مهرآیین'), findsOneWidget);
    expect(find.text('قابلیت‌های غیرفعال در حالت محلی'), findsOneWidget);
    expect(find.text('خانواده'), findsNothing);
    expect(find.text('تغییر رمز عبور'), findsNothing);
  });

  _localWidgetTest(
      'local profile edit persists full name and theme after returning home',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: HomeShell(
          api: _open(), localOnly: true, profileCategory: 'girl_minor'),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('پروفایل'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'سارا مهرآیین');
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('سفید / آبی نوجوان').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('ذخیره'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('سارا مهرآیین'), findsOneWidget);
    expect(Theme.of(tester.element(find.byType(TodayPage))).colorScheme.primary,
        ColorScheme.fromSeed(seedColor: const Color(0xFF4D86E8)).primary);
    final restored = await _open().getProfile();
    expect(restored['display_name'], 'سارا مهرآیین');
    expect(restored['theme_preference'], 'boy_blue');
  });

  _localWidgetTest(
      'uncertain profile save preserves old name until full process restart',
      (tester) async {
    final api = _open();
    final platform = await _controlWrites(tester, api);
    await tester.pumpWidget(MaterialApp(
      home: HomeShell(api: api, localOnly: true, profileCategory: 'girl_minor'),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('پروفایل'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'سارا مهرآیین');
    platform.failWrites = true;
    await tester.tap(find.text('ذخیره'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text(_restartMessage), findsOneWidget);
    expect(
        (await _nativeSnapshot())['profile']['display_name'], 'آرام مهرآیین');
    await _expectRestartRequired(_open().getProfile());
    platform.failWrites = false;
    await tester.tap(find.text('ذخیره'));
    await tester.pumpAndSettle();
    expect(find.text(_restartMessage), findsOneWidget);
    expect(
        (await _nativeSnapshot())['profile']['display_name'], 'آرام مهرآیین');

    final restarted = await _restartProcessMock();
    expect((await restarted.getProfile())['display_name'], 'آرام مهرآیین');
  });

  _localWidgetTest('local profile cannot submit again during a durable write',
      (tester) async {
    final api = _open();
    final platform = await _controlWrites(tester, api);
    await tester.pumpWidget(MaterialApp(
      home: HomeShell(api: api, localOnly: true, profileCategory: 'girl_minor'),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('پروفایل'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'سارا مهرآیین');
    platform.pendingWrite = Completer<void>();
    await tester.tap(find.text('ذخیره'));
    await tester.pump();

    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'در حال ذخیره...'),
    );
    expect(button.onPressed, isNull);
    platform.pendingWrite!.complete();
    platform.pendingWrite = null;
    await tester.pumpAndSettle();
    expect((await _open().getProfile())['display_name'], 'سارا مهرآیین');
  });

  _localWidgetTest(
      'production shell keeps a valid page when family role changes',
      (tester) async {
    final api = _RoleChangingApi();
    await tester.pumpWidget(MaterialApp(home: HomeShell(api: api)));
    await tester.pumpAndSettle();
    tester.firstState<ScaffoldState>(find.byType(Scaffold)).openDrawer();
    await tester.pumpAndSettle();
    await tester.tap(find.text('همراه هوشمند'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('پروفایل'));
    await tester.pumpAndSettle();
    api.currentRole = 'parent_guardian';
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('من'), findsWidgets);
  });

  _localWidgetTest('production planner keeps local archive action unavailable',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: PlannerPage(api: _ProductionItemApi())),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();

    expect(find.text('بایگانی'), findsNothing);
  });
}
