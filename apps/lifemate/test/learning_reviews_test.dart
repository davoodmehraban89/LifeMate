import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifemate/api.dart';
import 'package:lifemate/learning_reviews_ui.dart';
import 'package:lifemate/offline_store.dart';
import 'package:lifemate/session_store.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

// HTTP/widget fixtures only; not real teaching, device or API/SQL acceptance.
const _unit = '00000000-0000-4000-8000-000000000101';
const _laterUnit = '00000000-0000-4000-8000-000000000102';
const _course = '00000000-0000-4000-8000-000000000103';
const _attemptId = '00000000-0000-4000-8000-000000000104';
const _mutationId = '00000000-0000-4000-8000-000000000105';
const _assessment = '00000000-0000-4000-8000-000000000106';
const _fetchedAt = '2026-10-11T05:00:00Z';

class _Session implements SessionStore {
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String value) async {}
  @override
  Future<void> clear() async {}
}

Map<String, dynamic> _attempt() => {
      'mutationId': _mutationId,
      'attemptId': _attemptId,
      'unitId': _unit,
      'assessmentId': _assessment,
      'assessmentVersion': 2,
      'correctCount': 1,
      'total': 2,
      'feedback': [
        {
          'questionId': 'q1',
          'objectiveId': 'o1',
          'correct': true,
          'explanationFa': 'توضیح درست صرفاً آزمایشی',
          'remediationFa': 'مرور اول صرفاً آزمایشی',
        },
        {
          'questionId': 'q2',
          'objectiveId': 'o2',
          'correct': false,
          'explanationFa': 'توضیح دوم صرفاً آزمایشی',
          'remediationFa': 'راهنمای تمرین صرفاً آزمایشی',
        },
      ],
      'resultLabel': 'needs_practice',
      'nextReviewAt': '2026-10-12T10:00:00Z',
      'schedulePolicy': 'pilot-1-or-3-days',
      'source': 'quiz_answers',
      'acceptedAt': '2026-10-10T10:00:00Z',
      'confidence': 'unsure',
    };

class _Fixture {
  _Fixture() {
    api = HttpIdentityApi(
        baseUrl: 'https://reviews.example.test/api',
        client: MockClient(handle),
        sessionStore: _Session())
      ..accessToken = 'synthetic-token'
      ..currentUserId = 'synthetic-review-learner-${next++}';
    store = OfflineStore.forNamespace(api.cacheNamespace!,
        session: OfflineSession());
  }
  static int next = 0;
  late final HttpIdentityApi api;
  late final OfflineStore store;
  final requests = <http.Request>[];
  bool offline = false;
  int? forbidden, locatorFailure;
  Completer<void>? delay;
  List<Map<String, dynamic>> reviews = [
    {
      'unitId': _unit,
      'nextReviewAt': '2025-01-01T10:00:00Z',
      'schedulePolicy': 'pilot-1-or-3-days',
    },
    {
      'unitId': _laterUnit,
      'nextReviewAt': '2050-01-01T10:00:00Z',
      'schedulePolicy': 'pilot-1-or-3-days',
    },
  ];
  List<Map<String, dynamic>> attempts = [_attempt()];
  String fetchedAt = _fetchedAt;

  http.Response response(Object value, [int status = 200]) =>
      http.Response(jsonEncode(value), status,
          headers: {'content-type': 'application/json; charset=utf-8'});

  Future<http.Response> handle(http.Request request) async {
    requests.add(request);
    if (delay != null) await delay!.future;
    if (offline) throw http.ClientException('synthetic offline');
    if (forbidden != null) {
      return response({'error': 'synthetic-session-refused'}, forbidden!);
    }
    if (request.url.path.endsWith('/me/learning-reviews')) {
      return response({'reviews': reviews, 'fetchedAt': fetchedAt});
    }
    if (request.url.path.endsWith('/me/learning-attempts')) {
      return response({'attempts': attempts, 'fetchedAt': fetchedAt});
    }
    if (request.url.path.contains('/education/units/')) {
      if (locatorFailure != null) {
        return response({'error': 'unit_not_found'}, locatorFailure!);
      }
      final id = request.url.path.split('/').last;
      return response({
        'unit': {
          'id': id,
          'titleFa': id == _unit ? 'جمع آزمایشی' : 'درس آینده آزمایشی',
          'courseId': _course,
        },
        'fetchedAt': _fetchedAt,
      });
    }
    throw StateError('Unexpected synthetic request ${request.url.path}');
  }
}

Widget _screen(_Fixture fixture,
        {Future<void> Function(BuildContext, String)? open}) =>
    MaterialApp(
        home: LearningReviewsPage(
            api: fixture.api, onOpenLesson: open ?? (_, __) async {}));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData({});
    String? write;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('lifeguide/local_write_guard'), (call) async {
      if (call.method == 'getBlocked') return write != null;
      if (call.method == 'beginWrite') return write = 'synthetic-review-write';
      if (call.method == 'completeWrite' && call.arguments == write) {
        write = null;
        return true;
      }
      throw PlatformException(code: 'local_storage_restart_required');
    });
  });

  testWidgets(
      'owner sees due reviews and server-only history with lesson names',
      (tester) async {
    final f = _Fixture();
    String? opened;
    await tester.pumpWidget(_screen(f, open: (_, id) async => opened = id));
    await tester.pumpAndSettle();
    expect(find.text('مرور و تاریخچه یادگیری'), findsOneWidget);
    expect(find.text('موعد رسیده'), findsOneWidget);
    expect(find.text('مرور آینده'), findsOneWidget);
    expect(find.text('جمع آزمایشی'), findsWidgets);
    expect(find.textContaining('به‌تنهایی اثبات تسلط نیست'), findsOneWidget);
    expect(f.requests.where((r) => r.url.path.contains('/education/units/')),
        hasLength(2),
        reason: 'Locator titles must be deduplicated');
    expect(f.requests.every((r) => r.method == 'GET'), true);
    expect(
        f.requests.every(
            (r) => r.headers['authorization'] == 'Bearer synthetic-token'),
        true);
    expect(f.requests.every((r) => r.url.query.isEmpty), true,
        reason: 'No child/owner override in private history requests');
    await tester.scrollUntilVisible(
        find.byKey(const Key('attempt-$_attemptId')), 250);
    expect(find.text('۱ پاسخ درست از ۲'), findsOneWidget);
    expect(find.textContaining('نیاز به تمرین'), findsOneWidget);
    expect(find.textContaining(_unit), findsNothing);
    await tester.scrollUntilVisible(
        find.byKey(const Key('review-$_unit')), -250);
    await tester.ensureVisible(find.byKey(const Key('open-review-$_unit')));
    await tester.tap(find.byKey(const Key('open-review-$_unit')));
    await tester.pumpAndSettle();
    expect(opened, _unit);
    await tester.pumpWidget(const SizedBox());
    f.api.close();
  });

  testWidgets(
      'pausing during lesson open does not leave resumed history locked',
      (tester) async {
    final f = _Fixture();
    final opening = Completer<void>();
    await tester.pumpWidget(_screen(f, open: (_, __) => opening.future));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('open-review-$_unit')));
    await tester.tap(find.byKey(const Key('open-review-$_unit')));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    opening.complete();
    await tester.pump();
    final beforeResume = f.requests.length;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(f.requests.length, greaterThan(beforeResume),
        reason:
            'A discarded open callback must not block a fresh resumed read');
    expect(find.text('جمع آزمایشی'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
    f.api.close();
  });

  testWidgets('same API object switching account discards prior receipts',
      (tester) async {
    final f = _Fixture();
    await tester.pumpWidget(_screen(f));
    await tester.pumpAndSettle();
    expect(find.text('جمع آزمایشی'), findsWidgets);
    f.api.currentUserId = 'another-synthetic-review-learner';
    f.reviews = [];
    f.attempts = [];
    await tester.pumpWidget(_screen(f));
    await tester.pumpAndSettle();
    expect(find.text('جمع آزمایشی'), findsNothing);
    expect(find.text('مروری ثبت نشده است.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    f.api.close();
  });

  for (final failure in [0, 401, 403, 500]) {
    testWidgets(
        'history clears private receipts after refresh failure $failure',
        (tester) async {
      final f = _Fixture();
      await tester.pumpWidget(_screen(f));
      await tester.pumpAndSettle();
      expect(find.text('جمع آزمایشی'), findsWidgets);
      if (failure == 0) {
        f.offline = true;
      } else {
        f.forbidden = failure;
      }
      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      expect(find.text('جمع آزمایشی'), findsNothing);
      expect(find.textContaining('تأیید تازه دریافت نشده'), findsOneWidget);
      expect(find.byKey(const Key('attempt-$_attemptId')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      f.api.close();
    });
  }

  testWidgets('pending answers survive reopen without appearing as graded work',
      (tester) async {
    final f = _Fixture();
    f.attempts = [];
    f.reviews = [];
    await f.store.enqueue({
      'id': _mutationId,
      'entityId': _assessment,
      'entityType': 'learning_attempt',
      'payload': {
        'answers': ['PRIVATE-UNSENT-ANSWER'],
        'unitId': _unit
      },
    });
    final before = jsonEncode(await f.store.readQueue());
    await tester.pumpWidget(_screen(f));
    await tester.pumpAndSettle();
    expect(find.textContaining('روی این دستگاه: ۱'), findsOneWidget);
    expect(
        find.text('هنوز نتیجه پذیرفته‌شده‌ای ثبت نشده است.'), findsOneWidget);
    expect(find.textContaining('PRIVATE-UNSENT-ANSWER'), findsNothing);
    expect(f.requests.every((r) => r.method == 'GET'), true);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_screen(f));
    await tester.pumpAndSettle();
    expect(find.textContaining('روی این دستگاه: ۱'), findsOneWidget);
    expect(jsonEncode(await f.store.readQueue()), before,
        reason: 'History never grades or acknowledges queued answers');
    await tester.pumpWidget(const SizedBox());
    f.api.close();
  });

  testWidgets('late old-account history cannot resurrect after API replacement',
      (tester) async {
    final first = _Fixture()..delay = Completer<void>();
    final second = _Fixture()
      ..reviews = []
      ..attempts = [];
    await tester.pumpWidget(_screen(first));
    await tester.pump();
    await tester.pumpWidget(_screen(second));
    await tester.pumpAndSettle();
    expect(find.text('مروری ثبت نشده است.'), findsOneWidget);
    first.delay!.complete();
    await tester.pumpAndSettle();
    expect(find.text('جمع آزمایشی'), findsNothing);
    expect(find.byKey(const Key('attempt-$_attemptId')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    first.api.close();
    second.api.close();
  });

  for (final corruption in ['wrong-total', 'duplicate-id', 'bad-time']) {
    testWidgets('malformed history $corruption never displays a graded receipt',
        (tester) async {
      final f = _Fixture();
      if (corruption == 'wrong-total') {
        f.attempts.single['total'] = 3;
      } else if (corruption == 'duplicate-id') {
        f.attempts.add(_attempt());
      } else {
        f.fetchedAt = 'not-a-server-timestamp';
      }
      await tester.pumpWidget(_screen(f));
      await tester.pumpAndSettle();
      expect(find.text('۱ پاسخ درست از ۲'), findsNothing);
      expect(find.textContaining('پاسخ معتبر دریافت نشد'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      f.api.close();
    });
  }

  testWidgets(
      'removed lesson keeps acknowledged receipt and reports unavailable',
      (tester) async {
    final f = _Fixture()..locatorFailure = 404;
    var opened = false;
    await tester.pumpWidget(_screen(f, open: (_, __) async => opened = true));
    await tester.pumpAndSettle();
    expect(find.text('درس از دسترس خارج شده'), findsWidgets);
    await tester.ensureVisible(find.byKey(const Key('open-review-$_unit')));
    await tester.tap(find.byKey(const Key('open-review-$_unit')));
    await tester.pumpAndSettle();
    expect(opened, false);
    await tester.scrollUntilVisible(
        find.textContaining('فعلاً در کتابخانه فعال در دسترس نیست'), -200);
    expect(find.textContaining('فعلاً در کتابخانه فعال در دسترس نیست'),
        findsOneWidget);
    await tester.scrollUntilVisible(
        find.byKey(const Key('attempt-$_attemptId')), 200);
    expect(find.text('۱ پاسخ درست از ۲'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    f.api.close();
  });
}
