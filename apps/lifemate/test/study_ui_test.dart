import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifemate/api.dart';
import 'package:lifemate/session_store.dart';
import 'package:lifemate/study_coordinator.dart';
import 'package:lifemate/study_ui.dart';
import 'package:lifemate/dashboard_ui.dart';
import 'package:lifemate/phase3_ui.dart' show shortDate;
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

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

HttpIdentityApi apiFor(Future<http.Response> Function(http.Request) handler) =>
    HttpIdentityApi(
        baseUrl: 'https://synthetic.example.test/service',
        client: MockClient(handler),
        sessionStore: _MemorySession())
      ..accessToken = 'synthetic-token'
      ..currentUserId = 'synthetic-child';
http.Response jsonResponse(Map<String, dynamic> json, [int status = 200]) =>
    http.Response(jsonEncode(json), status,
        headers: {'content-type': 'application/json'});
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData({});
    String? pending;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('lifeguide/local_write_guard'), (call) async {
      if (call.method == 'getBlocked') return pending != null;
      if (call.method == 'beginWrite') return pending = 'study-test-token';
      if (call.method == 'completeWrite' && call.arguments == pending) {
        pending = null;
        return true;
      }
      throw PlatformException(code: 'local_storage_restart_required');
    });
  });
  test('study acknowledgement for another session retains exact queued event',
      () async {
    final api = apiFor((req) async {
      final body = jsonDecode(req.body) as Map;
      return jsonResponse({
        'session': {'id': 'different-session', 'version': 1},
        'acknowledgement': {
          'mutationId': body['mutationId'],
          'status': 'accepted',
          'acceptedAt': '2026-10-08T10:00:00Z'
        }
      });
    });
    final sync = StudySync(api);
    await expectLater(sync.start('owned-plan'), throwsA(isA<ApiException>()));
    expect(await sync.store.readQueue(), hasLength(1));
    api.close();
  });
  test('offline study start reopens and retries the same body once', () async {
    bool offline = true;
    final sent = <Map<String, dynamic>>[];
    final api = apiFor((req) async {
      final body = Map<String, dynamic>.from(jsonDecode(req.body) as Map);
      sent.add(body);
      if (offline) throw http.ClientException('synthetic transport failure');
      return jsonResponse({
        'session': {
          'id': body['id'],
          'planItemId': body['planItemId'],
          'status': 'running',
          'version': 1,
          'recordedDurationSeconds': 0,
          'intervals': []
        },
        'acknowledgement': {
          'mutationId': body['mutationId'],
          'status': 'accepted',
          'acceptedAt': '2026-10-08T10:00:00Z'
        }
      });
    });
    final first = await StudySync(api).start('owned-plan');
    expect(first.queued, isTrue);
    final reopened = StudySync(api);
    final retained = await reopened.store.readQueue();
    expect(retained, hasLength(1));
    offline = false;
    await reopened.flush();
    expect(sent[1], sent[0]);
    expect(await reopened.store.readQueue(), isEmpty);
    expect((await reopened.store.readList('study.sessions')).single['status'],
        'running');
    api.close();
  });
  testWidgets(
      'timer restores a running server session and labels recorded time',
      (tester) async {
    final api = apiFor((req) async => jsonResponse({
          'sessions': [
            {
              'id': 'server-session',
              'planItemId': 'owned-plan',
              'status': 'running',
              'version': 3,
              'recordedDurationSeconds': 120,
              'intervals': [],
              'isEvidenceOfStudy': false
            }
          ],
          'asOf': '2026-10-08T10:00:00Z'
        }));
    await tester.pumpWidget(MaterialApp(
        home: StudyTimerPage(
            api: api, item: {'id': 'owned-plan', 'title': 'ریاضی'})));
    await tester.pumpAndSettle();
    expect(find.text('مکث'), findsOneWidget);
    expect(find.text('پایان'), findsOneWidget);
    expect(find.text('2:00'), findsOneWidget);
    expect(find.textContaining('اثبات مطالعه نیست'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    api.close();
  });
  testWidgets('parent polling failure labels previous report stale',
      (tester) async {
    var fail = false;
    var calls = 0;
    final api = apiFor((req) async {
      calls++;
      return fail
          ? jsonResponse({'error': 'server_failed'}, 500)
          : jsonResponse({
              'metrics': {
                'totalTasks': 1,
                'completedTasks': 0,
                'overdueTasks': 0,
                'completionPercent': 0,
                'plannedDurationSeconds': 1800,
                'recordedDurationSeconds': 120
              },
              'items': [
                {
                  'id': 'plan',
                  'title': 'ریاضی',
                  'kind': 'assignment',
                  'activityState': 'started',
                  'activitySource': 'timer'
                }
              ],
              'daily': [],
              'subjects': [],
              'asOf': '2026-10-08T10:00:00Z',
              'lastSyncAt': '2026-10-08T09:00:00Z'
            });
    });
    await tester.pumpWidget(MaterialApp(
        home: LearningReportPage(
            api: api,
            familyId: 'family',
            childId: 'child',
            childName: 'فرزند')));
    await tester.pumpAndSettle();
    expect(find.text('ریاضی'), findsOneWidget);
    fail = true;
    await tester.pump(const Duration(seconds: 15));
    await tester.pumpAndSettle();
    expect(find.textContaining('داده قبلی به‌روز نیست'), findsOneWidget);
    expect(find.text('ریاضی'), findsOneWidget);
    expect(calls, 2);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
    expect(calls, 2);
    api.close();
  });
  for (final denial in [401, 403, 0]) {
    testWidgets(
        'parent refresh failure $denial clears previously displayed child data',
        (tester) async {
      var fail = false;
      final api = apiFor((req) async {
        if (fail) {
          if (denial == 0) {
            throw http.ClientException('synthetic transport failure');
          }
          return jsonResponse({'error': 'forbidden'}, denial);
        }
        return jsonResponse({
          'metrics': {},
          'items': [
            {
              'id': 'plan',
              'title': 'اطلاعات فرزند',
              'kind': 'assignment',
              'activityState': 'started',
              'activitySource': 'timer'
            }
          ],
          'daily': [],
          'subjects': [],
          'asOf': '2026-10-08T10:00:00Z'
        });
      });
      await tester.pumpWidget(MaterialApp(
          home: LearningReportPage(
              api: api,
              familyId: 'family',
              childId: 'child',
              childName: 'فرزند')));
      await tester.pumpAndSettle();
      expect(find.text('اطلاعات فرزند'), findsOneWidget);
      fail = true;
      await tester.pump(const Duration(seconds: 15));
      await tester.pumpAndSettle();
      expect(find.text('اطلاعات فرزند'), findsNothing);
      expect(
          find.textContaining(denial == 401
              ? 'نشست ورود'
              : denial == 403
                  ? 'دسترسی نداری'
                  : 'اتصال برقرار نیست'),
          findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      api.close();
    });
  }

  testWidgets('weekly and monthly reports include the rest of today in Tehran',
      (tester) async {
    final now = DateTime.now().toUtc();
    final tehran = now.add(const Duration(hours: 3, minutes: 30));
    final dayEnd = DateTime.utc(tehran.year, tehran.month, tehran.day + 1)
        .subtract(const Duration(hours: 3, minutes: 30));
    final laterToday = now.add(dayEnd.difference(now) ~/ 2);
    final windows = <Map<String, DateTime>>[];
    final api = apiFor((request) async {
      final from = DateTime.parse(request.url.queryParameters['from']!);
      final to = DateTime.parse(request.url.queryParameters['to']!);
      windows.add({'from': from, 'to': to});
      final included = !laterToday.isBefore(from) && laterToday.isBefore(to);
      return jsonResponse({
        'metrics': {
          'plannedDurationSeconds': 1800,
          'plannedInRangeDurationSeconds': included ? 1800 : 0,
          'recordedDurationSeconds': 1500
        },
        'items': [
          {
            'id': 'today-plan',
            'title': 'ریاضی امروز',
            'kind': 'assignment',
            'dueAt': laterToday.toIso8601String(),
            'plannedDurationSeconds': 1800,
          }
        ],
        'daily': [],
        'subjects': [],
        'asOf': now.toIso8601String(),
      });
    });
    await tester.pumpWidget(MaterialApp(
        home: LearningReportPage(
            api: api,
            familyId: 'family',
            childId: 'child',
            childName: 'فرزند')));
    await tester.pumpAndSettle();
    expect(windows.single['to'], dayEnd);
    expect(windows.single['from'], dayEnd.subtract(const Duration(days: 7)));
    expect(find.text('زمان برنامه‌ریزی‌شده: 30 دقیقه'), findsOneWidget);
    expect(find.text('زمان ثبت‌شده: 25 دقیقه'), findsOneWidget);
    expect(
        find.textContaining('دریافت سرور: ${shortDate(now)}'), findsOneWidget);
    await tester.tap(find.text('ماهانه'));
    await tester.pumpAndSettle();
    expect(windows.last['to'], dayEnd);
    expect(windows.last['from'], dayEnd.subtract(const Duration(days: 30)));
    expect(find.text('زمان برنامه‌ریزی‌شده: 30 دقیقه'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    api.close();
  });
}
