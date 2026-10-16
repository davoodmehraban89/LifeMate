import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifemate/api.dart';
import 'package:lifemate/phase3_ui.dart';
import 'package:lifemate/plan_sync.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'app_test.dart' show FakeApi;

// Explicit API fixtures for widget behavior; local PostgreSQL acceptance is separate.
class TaskApi extends FakeApi {
  bool offline = false;
  final items = <Map<String, dynamic>>[
    {
      'id': '30000000-0000-4000-8000-000000000001',
      'title': 'تکلیف اول',
      'kind': 'assignment',
      'status': 'planned',
      'visibility': 'private',
      'planned_duration_seconds': 1500,
      'version': 1
    },
    {
      'id': '30000000-0000-4000-8000-000000000002',
      'title': 'تکلیف دوم',
      'kind': 'assignment',
      'status': 'planned',
      'visibility': 'selected_members',
      'planned_duration_seconds': 900,
      'version': 1
    },
  ];
  @override
  Future<List<Map<String, dynamic>>> listPlanItems(
      {DateTime? from, DateTime? to, String? kind}) async {
    if (offline) throw const ApiException(0, 'network_unavailable');
    return items
        .where((r) => r['status'] != 'cancelled')
        .map((r) => Map<String, dynamic>.from(r))
        .toList();
  }

  @override
  Future<Map<String, dynamic>> submitSyncMutations(
      List<Map<String, dynamic>> mutations) async {
    if (offline) throw const ApiException(0, 'network_unavailable');
    return {
      'results': mutations.map((m) {
        final item = items.firstWhere((r) => r['id'] == m['entityId']);
        item.addAll(Map<String, dynamic>.from(m['payload'] as Map));
        item['version'] = (m['expectedVersion'] as int) + 1;
        return {
          'id': m['id'],
          'status': 'accepted',
          'item': {...item},
          'acceptedAt': '2026-10-16T10:00:00Z'
        };
      }).toList()
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    WidgetController.hitTestWarningShouldBeFatal = true;
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData({});
    String? token;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('lifeguide/local_write_guard'), (call) async {
      if (call.method == 'getBlocked') return token != null;
      if (call.method == 'beginWrite') return token = 'synthetic-detail-write';
      if (call.method == 'completeWrite' && call.arguments == token) {
        token = null;
        return true;
      }
      throw PlatformException(code: 'local_storage_restart_required');
    });
  });
  Future<void> planner(WidgetTester tester, IdentityApi api) async {
    await tester.pumpWidget(MaterialApp(
        home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(body: PlannerPage(api: api)))));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'second task opens its own detail and complete uses acknowledged sync',
      (tester) async {
    final api = TaskApi();
    await planner(tester, api);
    await tester.tap(find.text('تکلیف دوم'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('plan-details')), findsOneWidget);
    expect(find.text('تکلیف دوم'), findsOneWidget);
    expect(find.text('اعضای انتخاب‌شده'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('detail-complete')));
    await tester.pumpAndSettle();
    expect(api.items[1]['status'], 'completed');
    expect(find.text('توسط سرور تأیید شد'), findsOneWidget);
    expect(find.textContaining('انجام‌شده'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('detail edits preserve sharing and archive requires confirmation',
      (tester) async {
    final api = TaskApi();
    await planner(tester, api);
    await tester.tap(find.text('تکلیف اول'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('detail-edit')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'عنوان'), 'تکلیف ویرایش‌شده');
    await tester.tap(find.text('ذخیره'));
    await tester.pumpAndSettle();
    expect(find.text('تکلیف ویرایش‌شده'), findsOneWidget);
    expect(api.items.first['visibility'], 'private');
    await tester.pump(const Duration(seconds: 5));
    await tester.ensureVisible(find.byKey(const ValueKey('detail-archive')));
    await tester.tap(find.byKey(const ValueKey('detail-archive')));
    await tester.pumpAndSettle();
    expect(api.items.first['status'], 'planned');
    await tester.tap(find.text('بایگانی').last);
    await tester.pumpAndSettle();
    expect(api.items.first['status'], 'cancelled');
    expect(find.byKey(const ValueKey('plan-details')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('offline completion is pending rather than server confirmed',
      (tester) async {
    final api = TaskApi();
    await planner(tester, api);
    await tester.tap(find.text('تکلیف اول'));
    await tester.pumpAndSettle();
    api.offline = true;
    await tester.tap(find.byKey(const ValueKey('detail-complete')));
    await tester.pumpAndSettle();
    expect(find.text('در انتظار تأیید سرور'), findsOneWidget);
    expect(find.text('توسط سرور تأیید شد'), findsNothing);
    expect(api.items.first['status'], 'planned');
    expect(find.byKey(const ValueKey('detail-study')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('a scoped offline create remains editable and cannot start study',
      (tester) async {
    final api = HttpIdentityApi(
        baseUrl: 'https://pending-detail.example.test/api',
        client: MockClient(
            (_) async => throw http.ClientException('synthetic offline')))
      ..accessToken = 'synthetic-token'
      ..currentUserId = 'synthetic-owner';
    await PlanSync(api).create({
      'title': 'تکلیف آفلاین ساختگی',
      'kind': 'assignment',
      'visibility': 'private'
    });
    await planner(tester, api);
    await tester.tap(find.text('تکلیف آفلاین ساختگی'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('detail-edit')), findsOneWidget);
    expect(find.byKey(const ValueKey('detail-study')), findsNothing);
    expect(find.text('در انتظار تأیید سرور'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    api.close();
  });
  testWidgets(
      'return from study refreshes changed server version before completion',
      (tester) async {
    var version = 1;
    int? sentVersion;
    final item = {
      'id': '30000000-0000-4000-8000-000000000004',
      'owner_user_id': 'synthetic-owner',
      'title': 'کار با تایمر',
      'kind': 'assignment',
      'status': 'planned',
      'visibility': 'private'
    };
    final api = HttpIdentityApi(
        baseUrl: 'https://timer-detail.example.test/api',
        client: MockClient((req) async {
          Object body;
          if (req.url.path.endsWith('/study/sessions')) {
            body = {'sessions': []};
          } else if (req.method == 'POST') {
            final mutation =
                (jsonDecode(req.body)['mutations'] as List).single as Map;
            sentVersion = mutation['expectedVersion'];
            body = {
              'results': [
                {
                  'id': mutation['id'],
                  'status': 'accepted',
                  'acceptedAt': '2026-10-16T11:00:00Z',
                  'item': {
                    ...item,
                    'version': version + 1,
                    'status': 'completed'
                  }
                }
              ]
            };
          } else {
            body = {
              'items': [
                {...item, 'version': version}
              ]
            };
          }
          return http.Response(jsonEncode(body), 200,
              headers: {'content-type': 'application/json; charset=utf-8'});
        }))
      ..accessToken = 'synthetic-token'
      ..currentUserId = 'synthetic-owner';
    await planner(tester, api);
    await tester.tap(find.text('کار با تایمر'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('detail-study')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    version = 2; // server version advanced while study route was open
    await tester.tap(find.byType(BackButton).last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('detail-complete')));
    await tester.pumpAndSettle();
    expect(sentVersion, 2);
    await tester.pumpWidget(const SizedBox());
    api.close();
  });
  testWidgets('revoked shared details disappear on polling', (tester) async {
    bool visible = true;
    final api = HttpIdentityApi(
        baseUrl: 'https://visibility-detail.example.test/api',
        client: MockClient((req) async => http.Response(
            jsonEncode({
              'items': visible
                  ? [
                      {
                        'id': '30000000-0000-4000-8000-000000000005',
                        'owner_user_id': 'other-owner',
                        'title': 'اشتراک موقت ساختگی',
                        'kind': 'assignment',
                        'status': 'planned',
                        'visibility': 'family',
                        'version': 1
                      }
                    ]
                  : []
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'})))
      ..accessToken = 'synthetic-token'
      ..currentUserId = 'synthetic-reader';
    await planner(tester, api);
    await tester.tap(find.text('اشتراک موقت ساختگی'));
    await tester.pumpAndSettle();
    visible = false;
    await tester.pump(const Duration(seconds: 16));
    await tester.pumpAndSettle();
    expect(find.text('اشتراک موقت ساختگی'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    api.close();
  });
  testWidgets('shared snapshot is hidden across background and resume',
      (tester) async {
    final api = HttpIdentityApi(
        baseUrl: 'https://background-detail.example.test/api',
        client: MockClient((req) async => http.Response(
            jsonEncode({
              'items': [
                {
                  'id': '30000000-0000-4000-8000-000000000006',
                  'owner_user_id': 'other-owner',
                  'title': 'اشتراک پس‌زمینه ساختگی',
                  'kind': 'assignment',
                  'status': 'planned',
                  'visibility': 'family',
                  'version': 1
                }
              ]
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'})))
      ..accessToken = 'synthetic-token'
      ..currentUserId = 'synthetic-reader';
    await planner(tester, api);
    await tester.tap(find.text('اشتراک پس‌زمینه ساختگی'));
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(find.text('اشتراک پس‌زمینه ساختگی'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    api.close();
  });
  testWidgets('shared non-owner detail is read-only and has no timer',
      (tester) async {
    final api = HttpIdentityApi(
        baseUrl: 'https://detail.example.test/api',
        client: MockClient((req) async => http.Response(
            jsonEncode({
              'items': [
                {
                  'id': '30000000-0000-4000-8000-000000000003',
                  'owner_user_id': 'other-owner',
                  'title': 'کار مشترک',
                  'kind': 'assignment',
                  'status': 'planned',
                  'visibility': 'family',
                  'version': 1
                }
              ]
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'})))
      ..accessToken = 'synthetic-token'
      ..currentUserId = 'synthetic-reader';
    await planner(tester, api);
    await tester.tap(find.text('کار مشترک'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('plan-details')), findsOneWidget);
    expect(find.byKey(const ValueKey('detail-edit')), findsNothing);
    expect(find.byKey(const ValueKey('detail-complete')), findsNothing);
    expect(find.byKey(const ValueKey('detail-archive')), findsNothing);
    expect(find.byKey(const ValueKey('detail-study')), findsNothing);
    expect(find.textContaining('فقط مشاهده'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    api.close();
  });
}
