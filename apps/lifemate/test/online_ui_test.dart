import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifemate/runtime_config.dart';
import 'package:lifemate/runtime_controller.dart';
import 'package:lifemate/session_store.dart';
import 'package:lifemate/offline_store.dart';
import 'package:lifemate/plan_sync.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate/api.dart';
import 'package:lifemate/main.dart';
import 'package:lifemate/phase3_ui.dart';
import 'package:lifemate/phase4_ui.dart';
import 'package:lifemate/sync_changes_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'app_test.dart' show FakeApi;

class _FailingProfileApi extends FakeApi {
  @override
  Future<Map<String, dynamic>> updateProfile(
          {String? displayName,
          String? birthDate,
          String? themePreference,
          String? profileCategory}) async =>
      throw const ApiException(500, 'server_failed');
}

class _MemorySession extends SessionStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String next) async {
    value = next;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}

class _ServerFailureApi extends FakeApi {
  @override
  Future<List<Map<String, dynamic>>> listPlanItems(
          {DateTime? from, DateTime? to, String? kind}) async =>
      throw const ApiException(500, 'server_failed');
}

class _PlannerWritesApi extends FakeApi {
  final mutations = <Map<String, dynamic>>[];
  @override
  Future<Map<String, dynamic>> submitSyncMutations(
      List<Map<String, dynamic>> changes) async {
    mutations.addAll(changes);
    return {
      'results': changes
          .map((m) => {
                'id': m['id'],
                'status': 'accepted',
                'item': {
                  'id': m['entityId'],
                  ...(m['payload'] as Map),
                  'version': (m['expectedVersion'] as int) + 1,
                  'status': 'planned'
                },
                'acceptedAt': '2026-10-08T10:00:00Z'
              })
          .toList()
    };
  }
}

class _CategoryApi extends FakeApi {
  _CategoryApi(this.category, {super.role});
  String category;
  @override
  Future<Map<String, dynamic>> getProfile() async =>
      {...await super.getProfile(), 'profile_category': category};
  @override
  Future<Map<String, dynamic>> updateProfile(
      {String? displayName,
      String? birthDate,
      String? themePreference,
      String? profileCategory}) async {
    if (profileCategory != null) category = profileCategory;
    return {
      ...await super.updateProfile(
          displayName: displayName,
          birthDate: birthDate,
          themePreference: themePreference),
      'profile_category': category
    };
  }
}

class _OfflinePlannerApi extends FakeApi {
  @override
  Future<List<Map<String, dynamic>>> listPlanItems(
          {DateTime? from, DateTime? to, String? kind}) async =>
      throw const ApiException(0, 'network_unavailable');
  @override
  Future<Map<String, dynamic>> submitSyncMutations(
          List<Map<String, dynamic>> changes) async =>
      throw const ApiException(0, 'network_unavailable');
}

class _CategoryWithoutFamiliesApi extends _CategoryApi {
  _CategoryWithoutFamiliesApi() : super('adult');
  @override
  Future<List<Map<String, dynamic>>> listFamilies() async =>
      throw const ApiException(500, 'server_failed');
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData({});
    String? pending;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('lifeguide/local_write_guard'), (call) async {
      if (call.method == 'getBlocked') return pending != null;
      if (call.method == 'beginWrite') return pending = 'owned-ui-test-token';
      if (call.method == 'completeWrite' && call.arguments == pending) {
        pending = null;
        return true;
      }
      throw PlatformException(code: 'local_storage_restart_required');
    });
  });

  testWidgets('empty runtime endpoints open setup before constructing an API',
      (tester) async {
    await tester.pumpWidget(LifeMateApp());
    await tester.pumpAndSettle();
    expect(find.text('اتصال لایف‌گاید'), findsOneWidget);
    expect(find.text('ورود'), findsNothing);
  });

  test('auth errors do not disclose an existing account', () {
    expect(errorText(const ApiException(409, 'account_exists')),
        'عملیات انجام نشد. دوباره تلاش کن.');
  });

  testWidgets('authenticated notification inbox is offered only in home drawer',
      (tester) async {
    await tester.pumpWidget(LifeMateApp(api: FakeApi()));
    await tester.pumpAndSettle();
    expect(find.text('اعلان‌های درون برنامه'), findsNothing);
    await tester.pumpWidget(MaterialApp(home: HomeShell(api: FakeApi())));
    await tester.pumpAndSettle();
    tester.firstState<ScaffoldState>(find.byType(Scaffold)).openDrawer();
    await tester.pumpAndSettle();
    expect(find.text('اعلان‌های درون برنامه'), findsOneWidget);
  });

  testWidgets('home drawer opens durable pending changes screen',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: HomeShell(api: FakeApi())));
    await tester.pumpAndSettle();
    tester.firstState<ScaffoldState>(find.byType(Scaffold)).openDrawer();
    await tester.pumpAndSettle();
    await tester.tap(find.text('تغییرهای معلق و تعارض‌ها'));
    await tester.pumpAndSettle();
    expect(find.byType(SyncChangesPage), findsOneWidget);
    expect(find.text('تغییر معلقی باقی نمانده است.'), findsOneWidget);
  });

  testWidgets('sensitive guide remains disabled in the online shell',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: HomeShell(api: FakeApi())));
    await tester.pumpAndSettle();
    tester.firstState<ScaffoldState>(find.byType(Scaffold)).openDrawer();
    await tester.pumpAndSettle();
    await tester.tap(find.text('همراه هوشمند'));
    await tester.pumpAndSettle();
    expect(find.byType(Phase4Hub), findsNothing);
    expect(find.textContaining('در این مرحله فعال نیست'), findsOneWidget);
  });

  testWidgets('online planner offers homework without school setup',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: PlannerPage(api: FakeApi())),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('جدید'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    expect(find.text('تکلیف'), findsOneWidget);
  });
  testWidgets('profile save failure is visible and dialog remains editable',
      (tester) async {
    await tester.pumpWidget(
        MaterialApp(home: ProfileFamilyPage(api: _FailingProfileApi())));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ذخیره'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('سرور پاسخ معتبر نداد'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
  });
  testWidgets(
      'configured authenticated runtime opens home and settings uses child navigator',
      (tester) async {
    final session = _MemorySession();
    final api = HttpIdentityApi(
        baseUrl: 'https://synthetic.example.test/service',
        sessionStore: session,
        client: MockClient((req) async {
          final value = req.url.path.endsWith('/me')
              ? {
                  'user_id': 'child',
                  'display_name': 'فرزند',
                  'theme_preference': 'girl_pink'
                }
              : req.url.path.endsWith('/families')
                  ? {'families': []}
                  : {'items': []};
          return http.Response(jsonEncode(value), 200,
              headers: {'content-type': 'application/json'});
        }))
      ..accessToken = 'synthetic-token'
      ..currentUserId = 'child';
    final runtime = RuntimeController(sessionStore: session)
      ..initialized = true
      ..config = RuntimeConfig(apiBaseUrl: api.baseUrl)
      ..api = api;
    await tester.pumpWidget(LifeMateApp(runtime: runtime));
    await tester.pumpAndSettle();
    expect(find.byType(HomeShell), findsOneWidget);
    expect(find.text('ورود'), findsNothing);
    tester.firstState<ScaffoldState>(find.byType(Scaffold)).openDrawer();
    await tester.pumpAndSettle();
    await tester.tap(find.text('تنظیم اتصال'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('اتصال لایف‌گاید'), findsOneWidget);
    await runtime.signOut();
    await tester.pumpAndSettle();
    expect(find.text('ورود'), findsOneWidget);
    expect(find.text('اتصال لایف‌گاید'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    runtime.dispose();
  });
  testWidgets('server failure never presents cached planner as live',
      (tester) async {
    final api = _ServerFailureApi();
    await OfflineStore.forApi(api).cachePlanner([
      {'id': 'old', 'title': 'نسخه قدیمی', 'kind': 'task', 'status': 'planned'}
    ]);
    await tester
        .pumpWidget(MaterialApp(home: Scaffold(body: PlannerPage(api: api))));
    await tester.pumpAndSettle();
    expect(find.text('نسخه قدیمی'), findsNothing);
    expect(find.textContaining('سرور پاسخ معتبر نداد'), findsOneWidget);
    expect(find.textContaining('نسخه ذخیره‌شده'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'homework sharing requires explicit family and sends planned time',
      (tester) async {
    final api = _PlannerWritesApi();
    await tester
        .pumpWidget(MaterialApp(home: Scaffold(body: PlannerPage(api: api))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('جدید'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'عنوان'), 'ریاضی');
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('تکلیف').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(SwitchListTile));
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ذخیره'));
    await tester.pumpAndSettle();
    expect(find.textContaining('خانواده‌ای را'), findsOneWidget);
    expect(api.mutations, isEmpty);
    await tester
        .ensureVisible(find.byType(DropdownButtonFormField<String>).last);
    await tester.tap(find.byType(DropdownButtonFormField<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('خانواده').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('ذخیره'));
    await tester.pumpAndSettle();
    final payload = api.mutations.single['payload'] as Map;
    expect(payload['kind'], 'assignment');
    expect(payload['familyId'], 'family-1');
    expect(payload['visibility'], 'parent_guardian');
    expect(payload['plannedDurationSeconds'], 1800);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'phone registration exposes actual unavailable SMS error without delivery claim',
      (tester) async {
    Map? payload;
    final api = HttpIdentityApi(
        baseUrl: 'https://synthetic.example.test',
        client: MockClient((req) async {
          payload = jsonDecode(req.body) as Map;
          return http.Response('{"error":"sms_unavailable"}', 503,
              headers: {'content-type': 'application/json'});
        }));
    await tester.pumpWidget(MaterialApp(home: RegistrationPage(api: api)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تلفن'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'نام'), 'فرزند');
    await tester.enterText(
        find.widgetWithText(TextField, 'شماره تلفن'), '+989123456789');
    await tester.enterText(
        find.widgetWithText(TextField, 'رمز عبور'), 'synthetic-password');
    await tester.enterText(
        find.widgetWithText(TextField, 'تکرار رمز عبور'), 'synthetic-password');
    await tester.tap(find.text('ثبت درخواست'));
    await tester.pumpAndSettle();
    expect(payload!['phone'], '+989123456789');
    expect(payload!.containsKey('email'), isFalse);
    expect(find.textContaining('سرویس پیامک فعال نیست'), findsOneWidget);
    expect(find.textContaining('درخواست بررسی شد'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    api.close();
  });
  testWidgets('profile category controls shell without granting family role',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: HomeShell(api: _CategoryApi('adult', role: 'teen_minor'))));
    await tester.pumpAndSettle();
    expect(find.text('برنامه‌ریز'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'offline homework can be edited while its create awaits acknowledgement',
      (tester) async {
    final api = _OfflinePlannerApi();
    await tester
        .pumpWidget(MaterialApp(home: Scaffold(body: PlannerPage(api: api))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('جدید'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'عنوان'), 'ریاضی');
    await tester.tap(find.text('ذخیره'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ویرایش'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'عنوان'), 'ریاضی جدید');
    await tester.tap(find.text('ذخیره'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('ریاضی جدید'), findsOneWidget);
    expect(await OfflineStore.forApi(api).pendingCount(), 2);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'email ownership verification requires explicit new password submission',
      (tester) async {
    Map? submitted;
    final api = HttpIdentityApi(
        baseUrl: 'https://synthetic.example.test',
        client: MockClient((req) async {
          submitted = jsonDecode(req.body) as Map;
          return http.Response('{}', 200,
              headers: {'content-type': 'application/json'});
        }));
    await tester.pumpWidget(
        MaterialApp(home: VerifyEmailPage(api: api, token: 'synthetic-proof')));
    await tester.pumpAndSettle();
    expect(submitted, isNull);
    await tester.enterText(
        find.widgetWithText(TextField, 'رمز عبور جدید'), 'synthetic-password');
    await tester.enterText(
        find.widgetWithText(TextField, 'تکرار رمز عبور'), 'synthetic-password');
    await tester.tap(find.text('تأیید و تعیین رمز عبور'));
    await tester.pumpAndSettle();
    expect(submitted,
        {'token': 'synthetic-proof', 'newPassword': 'synthetic-password'});
    expect(find.text('ایمیل تأیید شد'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    api.close();
  });
  testWidgets('editing a private task can explicitly change guardian sharing',
      (tester) async {
    final api = _PlannerWritesApi();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () => showDialog(
                        context: context,
                        builder: (_) => PlanItemDialog(api: api, item: {
                              'id': 'saved-plan',
                              'title': 'ریاضی',
                              'kind': 'assignment',
                              'status': 'planned',
                              'visibility': 'private',
                              'version': 1
                            })),
                    child: const Text('باز کردن'))))));
    await tester.tap(find.text('باز کردن'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(SwitchListTile));
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester
        .ensureVisible(find.byType(DropdownButtonFormField<String>).last);
    await tester.tap(find.byType(DropdownButtonFormField<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('خانواده').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('ذخیره'));
    await tester.pumpAndSettle();
    expect((api.mutations.single['payload'] as Map)['visibility'],
        'parent_guardian');
    expect(find.byType(AlertDialog), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('profile category routing does not depend on family availability',
      (tester) async {
    await tester.pumpWidget(
        MaterialApp(home: HomeShell(api: _CategoryWithoutFamiliesApi())));
    await tester.pumpAndSettle();
    expect(find.text('برنامه‌ریز'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'logout warns before discarding an unsent change and cancel preserves identity',
      (tester) async {
    final session = _MemorySession();
    final api = HttpIdentityApi(
        baseUrl: 'https://synthetic.example.test',
        sessionStore: session,
        client: MockClient((req) async => http.Response(
            jsonEncode(req.url.path.endsWith('/profile')
                ? {
                    'profile_category': 'adult',
                    'theme_preference': 'adult_blue'
                  }
                : req.url.path.endsWith('/families')
                    ? {'families': []}
                    : {'items': []}),
            200,
            headers: {'content-type': 'application/json'})))
      ..accessToken = 'synthetic-token'
      ..currentUserId = 'child';
    final runtime = RuntimeController(sessionStore: session)
      ..initialized = true
      ..config = RuntimeConfig(apiBaseUrl: api.baseUrl)
      ..api = api;
    await OfflineStore.forApi(api).enqueue({
      'id': '9f7b762c-905f-48a1-81b3-ded3ed72d3c0',
      'entityId': '3a940940-f482-4b5a-937a-d74cc9ef9daf',
      'entityType': 'plan_item',
      'operation': 'create',
      'expectedVersion': 0,
      'payload': {'kind': 'task', 'title': 'معلق'}
    });
    await tester.pumpWidget(LifeMateApp(runtime: runtime));
    await tester.pumpAndSettle();
    tester.firstState<ScaffoldState>(find.byType(Scaffold)).openDrawer();
    await tester.pumpAndSettle();
    await tester.tap(find.text('خروج از حساب'));
    await tester.pumpAndSettle();
    expect(find.textContaining('تغییر معلق'), findsOneWidget);
    expect(api.accessToken, isNotNull);
    await tester.tap(find.text('انصراف'));
    await tester.pumpAndSettle();
    expect(api.accessToken, isNotNull);
    expect(await OfflineStore.forApi(api).pendingCount(), 1);
    await tester.pumpWidget(const SizedBox());
    runtime.dispose();
  });
  testWidgets(
      'endpoint save warns before discard and cancel preserves endpoint and queue',
      (tester) async {
    final session = _MemorySession();
    final api = HttpIdentityApi(
        baseUrl: 'https://synthetic.example.test',
        sessionStore: session,
        client: MockClient((req) async => http.Response(
            jsonEncode(req.url.path.endsWith('/profile')
                ? {
                    'profile_category': 'adult',
                    'theme_preference': 'adult_blue'
                  }
                : req.url.path.endsWith('/families')
                    ? {'families': []}
                    : {'items': []}),
            200,
            headers: {'content-type': 'application/json'})))
      ..accessToken = 'synthetic-token'
      ..currentUserId = 'child';
    final runtime = RuntimeController(sessionStore: session)
      ..initialized = true
      ..config = RuntimeConfig(apiBaseUrl: api.baseUrl)
      ..api = api;
    await OfflineStore.forApi(api).enqueue({
      'id': '9f7b762c-905f-48a1-81b3-ded3ed72d3c0',
      'entityId': '3a940940-f482-4b5a-937a-d74cc9ef9daf',
      'entityType': 'plan_item',
      'operation': 'create',
      'expectedVersion': 0,
      'payload': {'kind': 'task', 'title': 'معلق'}
    });
    await tester.pumpWidget(LifeMateApp(runtime: runtime));
    await tester.pumpAndSettle();
    tester.firstState<ScaffoldState>(find.byType(Scaffold)).openDrawer();
    await tester.pumpAndSettle();
    await tester.tap(find.text('تنظیم اتصال'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'نشانی اصلی'),
        'https://other.synthetic.example.test');
    await tester.tap(find.text('ذخیره و ادامه'));
    await tester.pumpAndSettle();
    expect(find.textContaining('تغییر معلق'), findsOneWidget);
    await tester.tap(find.text('انصراف'));
    await tester.pumpAndSettle();
    expect(runtime.config.apiBaseUrl, 'https://synthetic.example.test');
    expect(api.accessToken, isNotNull);
    expect(await OfflineStore.forApi(api).pendingCount(), 1);
    await tester.pumpWidget(const SizedBox());
    runtime.dispose();
  });
  testWidgets(
      'offline planner fallback shows owned rows and hides shared child rows',
      (tester) async {
    final api = HttpIdentityApi(
        baseUrl: 'https://synthetic.example.test',
        client: MockClient((_) async =>
            throw http.ClientException('synthetic transport failure')))
      ..accessToken = 'synthetic-token'
      ..currentUserId = 'parent';
    await OfflineStore.forApi(api).cachePlanner([
      {
        'id': 'own',
        'owner_user_id': 'parent',
        'title': 'کار خودم',
        'kind': 'task',
        'status': 'planned'
      },
      {
        'id': 'shared-child',
        'owner_user_id': 'child',
        'title': 'داده فرزند',
        'kind': 'assignment',
        'status': 'planned'
      }
    ]);
    await tester
        .pumpWidget(MaterialApp(home: Scaffold(body: PlannerPage(api: api))));
    await tester.pumpAndSettle();
    expect(find.text('کار خودم'), findsOneWidget);
    expect(find.text('داده فرزند'), findsNothing);
    expect(find.textContaining('داده زنده نیست'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    api.close();
  });
  testWidgets(
      'offline owned pending create remains visible without a server owner field',
      (tester) async {
    final api = HttpIdentityApi(
        baseUrl: 'https://synthetic.example.test',
        client: MockClient((_) async =>
            throw http.ClientException('synthetic transport failure')))
      ..accessToken = 'synthetic-token'
      ..currentUserId = 'child';
    await PlanSync(api).create(
        {'kind': 'assignment', 'title': 'تکلیف خودم', 'visibility': 'private'});
    await tester
        .pumpWidget(MaterialApp(home: Scaffold(body: PlannerPage(api: api))));
    await tester.pumpAndSettle();
    expect(find.text('تکلیف خودم'), findsOneWidget);
    expect(find.textContaining('در انتظار تأیید سرور'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
    api.close();
  });
  testWidgets(
      'owner exam grade edit sends normalized points and current version',
      (tester) async {
    final api = _PlannerWritesApi();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () => showDialog(
                        context: context,
                        builder: (_) => PlanItemDialog(api: api, item: {
                              'id': 'saved-exam',
                              'title': 'امتحان ریاضی',
                              'kind': 'exam',
                              'status': 'planned',
                              'visibility': 'private',
                              'version': 4
                            })),
                    child: const Text('باز کردن'))))));
    await tester.tap(find.text('باز کردن'));
    await tester.pumpAndSettle();
    await tester
        .ensureVisible(find.widgetWithText(TextField, 'نمره (اختیاری)'));
    await tester.enterText(
        find.widgetWithText(TextField, 'نمره (اختیاری)'), '۱۵٫۵');
    await tester
        .ensureVisible(find.widgetWithText(TextField, 'سقف نمره (اختیاری)'));
    await tester.enterText(
        find.widgetWithText(TextField, 'سقف نمره (اختیاری)'), '۲۰');
    await tester.tap(find.text('ذخیره'));
    await tester.pumpAndSettle();
    expect(api.mutations.single['expectedVersion'], 4);
    expect((api.mutations.single['payload'] as Map)['gradePoints'], 15.5);
    expect((api.mutations.single['payload'] as Map)['gradeOutOf'], 20);
    expect(find.byType(AlertDialog), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
