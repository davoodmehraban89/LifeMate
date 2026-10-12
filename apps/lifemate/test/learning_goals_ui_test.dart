import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifemate/api.dart';
import 'package:lifemate/phase4_ui.dart';
import 'package:lifemate/learning_goals_ui.dart';
import 'learning_goal_sync_test.dart' as support;
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData({});
    String? token;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('lifeguide/local_write_guard'), (call) async {
      if (call.method == 'getBlocked') return token != null;
      if (call.method == 'beginWrite') return token = 'goal-widget-test';
      if (call.method == 'completeWrite' && call.arguments == token) {
        token = null;
        return true;
      }
      throw PlatformException(code: 'local_storage_restart_required');
    });
  });
  testWidgets(
      'HTTP hub opens private goal CRUD screen with truthful server freshness',
      (tester) async {
    final api = HttpIdentityApi(
        baseUrl: 'https://goals.example.test/api',
        client: MockClient((request) async => http.Response(
            jsonEncode({'items': [], 'fetchedAt': '2026-10-11T10:00:00Z'}), 200,
            headers: {'content-type': 'application/json; charset=utf-8'})))
      ..accessToken = 'synthetic'
      ..currentUserId = '10000000-0000-4000-8000-000000000001';
    await tester.pumpWidget(MaterialApp(
        home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(body: Phase4Hub(api: api)))));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('مدیریت هدف‌های یادگیری'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('مدیریت هدف‌های یادگیری'));
    await tester.pumpAndSettle();
    expect(find.text('هدف‌های یادگیری'), findsOneWidget);
    expect(find.text('هدف جدید'), findsOneWidget);
    expect(find.textContaining('خصوصی'), findsOneWidget);
    expect(find.textContaining('آخرین دریافت سرور:'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    api.close();
  });
  Future<void> showPage(WidgetTester tester, HttpIdentityApi api) async {
    await tester.pumpWidget(MaterialApp(
        home: Directionality(
            textDirection: TextDirection.rtl,
            child: LearningGoalsPage(api: api))));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'goal creation, edit, completion and confirmed archive use versioned API operations',
      (tester) async {
    final f = support.GoalFixture();
    await showPage(tester, f.api);
    await tester.tap(find.text('هدف جدید'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'هدف ریاضی');
    await tester.enterText(find.byType(TextField).at(1), 'جمع با درک مفهوم');
    await tester.tap(find.text('ذخیره'));
    await tester.pumpAndSettle();
    expect(find.text('هدف ریاضی'), findsOneWidget);
    expect(find.text('تغییر ارسال‌نشده: 0'), findsOneWidget);
    await tester.tap(find.text('ویرایش'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'تمرین جمع');
    await tester.tap(find.text('ذخیره'));
    await tester.pumpAndSettle();
    expect(find.text('هدف ریاضی'), findsNothing);
    expect(find.text('تمرین جمع'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'تکمیل طبق گزارش من'));
    await tester.pumpAndSettle();
    expect(find.text('فعال‌کردن دوباره'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'بایگانی'));
    await tester.pumpAndSettle();
    expect(find.text('بایگانی هدف؟'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'انصراف'));
    await tester.pumpAndSettle();
    expect(f.goals.values.single['status'], 'completed');
    await tester.tap(find.widgetWithText(TextButton, 'بایگانی'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'بایگانی'));
    await tester.pumpAndSettle();
    expect(find.text('تمرین جمع'), findsNothing);
    expect(f.goals.values.single['status'], 'archived');
    expect(f.goals.values.single['version'], 4);
    expect(f.receipts, hasLength(4));
    await tester.pumpWidget(const SizedBox());
    f.api.close();
  });

  testWidgets(
      'offline goal intent remains pending after page reopen and becomes live only after acknowledgement',
      (tester) async {
    final f = support.GoalFixture()..offline = true;
    await showPage(tester, f.api);
    await tester.tap(find.text('هدف جدید'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'هدف بدون اینترنت');
    await tester.tap(find.text('ذخیره'));
    await tester.pumpAndSettle();
    expect(find.text('تغییر در انتظار تأیید سرور'), findsOneWidget);
    expect(find.text('تغییر ارسال‌نشده: 1'), findsOneWidget);
    expect(find.textContaining('آخرین ثبت سرور:'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await showPage(tester, f.api);
    expect(find.text('هدف بدون اینترنت'), findsOneWidget);
    expect(find.text('تغییر ارسال‌نشده: 1'), findsOneWidget);
    f.offline = false;
    await tester.tap(find.text('همگام‌سازی و تازه‌سازی'));
    await tester.pumpAndSettle();
    expect(find.text('تغییر ارسال‌نشده: 0'), findsOneWidget);
    expect(find.textContaining('آخرین ثبت سرور:'), findsOneWidget);
    expect(f.goals, hasLength(1));
    await tester.pumpWidget(const SizedBox());
    f.api.close();
  });

  testWidgets('denied refresh removes private goal text and actions',
      (tester) async {
    final f = support.GoalFixture();
    f.goals[support.goalId] = support.goal();
    await showPage(tester, f.api);
    expect(find.text('هدف خصوصی آزمایشی'), findsOneWidget);
    f.errorCode = 403;
    await tester.tap(find.text('همگام‌سازی و تازه‌سازی'));
    await tester.pumpAndSettle();
    expect(find.text('هدف خصوصی آزمایشی'), findsNothing);
    expect(find.text('ویرایش'), findsNothing);
    expect(find.textContaining('دسترسی'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    f.api.close();
  });

  testWidgets(
      'failed response labels retained goals as stale instead of a live snapshot',
      (tester) async {
    final f = support.GoalFixture();
    f.goals[support.goalId] = support.goal();
    await showPage(tester, f.api);
    f.errorCode = 502;
    await tester.tap(find.text('همگام‌سازی و تازه‌سازی'));
    await tester.pumpAndSettle();
    expect(find.text('هدف خصوصی آزمایشی'), findsOneWidget);
    expect(find.text('تازه‌سازی ناموفق؛ این داده ممکن است قدیمی باشد.'),
        findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    f.api.close();
  });

  testWidgets(
      'backgrounding clears private goal view and resume revalidates before display',
      (tester) async {
    final f = support.GoalFixture();
    f.goals[support.goalId] = support.goal();
    await showPage(tester, f.api);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(find.text('هدف خصوصی آزمایشی'), findsNothing);
    f.errorCode = 403;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('هدف خصوصی آزمایشی'), findsNothing);
    expect(find.textContaining('دسترسی'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    f.api.close();
  });

  testWidgets(
      'denied edit closes private text dialog and never restores cached goals',
      (tester) async {
    final f = support.GoalFixture();
    f.goals[support.goalId] = support.goal();
    await showPage(tester, f.api);
    await tester.tap(find.text('ویرایش'));
    await tester.pumpAndSettle();
    f.errorCode = 403;
    await tester.tap(find.text('ذخیره'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(find.text('هدف خصوصی آزمایشی'), findsNothing);
    expect(find.textContaining('دسترسی'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    f.api.close();
  });
  testWidgets(
      'goal-linked private reflection history supports create, edit and safe archive',
      (tester) async {
    final f = _HistoryFixture();
    await tester.pumpWidget(MaterialApp(
        home: LearningGoalHistoryPage(api: f.api, goalId: support.goalId)));
    await tester.pumpAndSettle();
    expect(find.text('ثبت بازتاب'), findsOneWidget);
    await tester.tap(find.text('ثبت بازتاب'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'جمع را بهتر فهمیدم');
    await tester.tap(find.text('ذخیره'));
    await tester.pumpAndSettle();
    expect(find.text('جمع را بهتر فهمیدم'), findsOneWidget);
    expect(find.textContaining('اثبات یادگیری'), findsWidgets);
    await tester.tap(find.widgetWithText(TextButton, 'ویرایش بازتاب'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'نیاز به تمرین بیشتر دارم');
    await tester.tap(find.text('ذخیره'));
    await tester.pumpAndSettle();
    expect(find.text('جمع را بهتر فهمیدم'), findsNothing);
    expect(find.text('نیاز به تمرین بیشتر دارم'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'بایگانی بازتاب'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تأیید بایگانی'));
    await tester.pumpAndSettle();
    expect(find.text('نیاز به تمرین بیشتر دارم'), findsNothing);
    expect(f.posts, 1);
    expect(f.patches, 1);
    expect(f.archives, 1);
    expect(f.rows.single['archived_at'], support.at);
    await tester.pumpWidget(const SizedBox());
    f.api.close();
  });

  testWidgets(
      'reflection receipt loss refreshes history without automatically repeating non-idempotent creation',
      (tester) async {
    final f = _HistoryFixture()..loseReceipt = true;
    await tester.pumpWidget(MaterialApp(
        home: LearningGoalHistoryPage(api: f.api, goalId: support.goalId)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ثبت بازتاب'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'بازتاب نامشخص آزمایشی');
    await tester.tap(find.text('ذخیره'));
    await tester.pumpAndSettle();
    expect(f.posts, 1);
    expect(find.text('بازتاب نامشخص آزمایشی'), findsOneWidget);
    expect(find.textContaining('نتیجه ثبت قبلی ممکن است نامشخص باشد'),
        findsOneWidget);
    await tester.tap(find.text('تازه‌سازی سابقه'));
    await tester.pumpAndSettle();
    expect(f.posts, 1);
    expect(f.rows, hasLength(1));
    await tester.pumpWidget(const SizedBox());
    f.api.close();
  });

  testWidgets('denied reflection reads clear note text and mutation controls',
      (tester) async {
    final f = _HistoryFixture()
      ..rows.add(_HistoryFixture.row('یادداشت خصوصی آزمایشی'));
    await tester.pumpWidget(MaterialApp(
        home: LearningGoalHistoryPage(api: f.api, goalId: support.goalId)));
    await tester.pumpAndSettle();
    expect(find.text('یادداشت خصوصی آزمایشی'), findsOneWidget);
    f.denied = true;
    await tester.tap(find.text('تازه‌سازی سابقه'));
    await tester.pumpAndSettle();
    expect(find.text('یادداشت خصوصی آزمایشی'), findsNothing);
    expect(find.text('ویرایش بازتاب'), findsNothing);
    expect(find.textContaining('دسترسی'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    f.api.close();
  });

  testWidgets(
      'failed online-only reflection fetch never claims an unsent local record exists',
      (tester) async {
    final f = _HistoryFixture();
    await tester.pumpWidget(MaterialApp(
        home: LearningGoalHistoryPage(api: f.api, goalId: support.goalId)));
    await tester.pumpAndSettle();
    f.offlineRead = true;
    await tester.tap(find.text('تازه‌سازی سابقه'));
    await tester.pumpAndSettle();
    expect(find.textContaining('تغییر ذخیره‌شده'), findsNothing);
    expect(find.text('اتصال برقرار نیست؛ دریافت بازتاب‌ها به سرور نیاز دارد.'),
        findsOneWidget);
    expect(f.posts, 0);
    expect(find.textContaining('آخرین دریافت سابقه:'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    f.api.close();
  });

  testWidgets(
      'denied reflection edit clears private text and closes the editor safely',
      (tester) async {
    final f = _HistoryFixture()
      ..rows.add(_HistoryFixture.row('یادداشت پیشین خصوصی'));
    await tester.pumpWidget(MaterialApp(
        home: LearningGoalHistoryPage(api: f.api, goalId: support.goalId)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ویرایش بازتاب'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'متن ویرایش‌شده خصوصی');
    f.denied = true;
    await tester.tap(find.text('ذخیره'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(find.text('یادداشت پیشین خصوصی'), findsNothing);
    expect(find.text('متن ویرایش‌شده خصوصی'), findsNothing);
    expect(find.textContaining('دسترسی'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    f.api.close();
  });
}

class _HistoryFixture {
  _HistoryFixture() {
    api = HttpIdentityApi(
        baseUrl: 'https://history.example.test/api', client: MockClient(handle))
      ..accessToken = 'synthetic-token'
      ..currentUserId = support.userId;
  }
  late final HttpIdentityApi api;
  final rows = <Map<String, dynamic>>[];
  int posts = 0, patches = 0, archives = 0;
  bool loseReceipt = false, denied = false, offlineRead = false;
  static Map<String, dynamic> row(String note) => {
        'id': '30000000-0000-4000-8000-000000000001',
        'owner_user_id': support.userId,
        'learning_goal_id': support.goalId,
        'confidence': 3,
        'difficulty': 3,
        'note': note,
        'source': 'self_reported',
        'isEvidenceOfStudy': false,
        'occurred_at': support.at,
        'created_at': support.at,
        'updated_at': support.at,
        'archived_at': null,
      };
  Future<http.Response> handle(http.Request request) async {
    if (denied) return support.response({'error': 'forbidden'}, 403);
    if (request.method == 'GET') {
      if (offlineRead) throw http.ClientException('synthetic offline read');
      return request.url.path.contains('/goals/')
          ? support.response(support.goal())
          : support.response(
              {'items': rows.where((r) => r['archived_at'] == null).toList()});
    }
    if (request.method == 'DELETE') {
      archives++;
      rows.single['archived_at'] = support.at;
      return http.Response('', 204);
    }
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    if (request.method == 'POST') {
      posts++;
      rows.add({
        ...row(body['note'] as String),
        'confidence': body['confidence'],
        'difficulty': body['difficulty']
      });
      if (loseReceipt) {
        throw http.ClientException('synthetic receipt lost after commit');
      }
      return support.response(rows.last, 201);
    }
    patches++;
    rows.single.addAll({
      'confidence': body['confidence'],
      'difficulty': body['difficulty'],
      'note': body['note']
    });
    return support.response(rows.single);
  }
}
