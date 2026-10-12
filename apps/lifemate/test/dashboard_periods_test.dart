import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifemate/api.dart';
import 'package:lifemate/dashboard_ui.dart';
import 'package:lifemate/session_store.dart';

class _MemorySession extends SessionStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String next) async => value = next;
  @override
  Future<void> clear() async => value = null;
}

http.Response _response(Map<String, dynamic> body) =>
    http.Response(jsonEncode(body), 200,
        headers: {'content-type': 'application/json'});
DateTime _rangeEnd() {
  final now = DateTime.now().toUtc().add(const Duration(hours: 3, minutes: 30));
  return DateTime.utc(now.year, now.month, now.day + 1)
      .subtract(const Duration(hours: 3, minutes: 30));
}

Map<String, dynamic> _report(String taskTitle) => {
      'metrics': {
        'totalTasks': 99,
        'completedTasks': 90,
        'completionPercent': 91,
        'plannedDurationSeconds': 60000,
        'recordedDurationSeconds': 1500
      },
      'allTimeTaskMetrics': {'totalTasks': 99, 'completedTasks': 90},
      'periodMetrics': {
        'totalTasks': 2,
        'completedTasks': 1,
        'completionPercent': 50,
        'overdueTasks': 0,
        'plannedDurationSeconds': 1800,
        'recordedDurationSeconds': 1500,
        'examCount': 1,
        'gradedExamCount': 1,
        'gradePercent': 75
      },
      'items': [
        {
          'id': 'period-plan',
          'title': taskTitle,
          'kind': 'assignment',
          'taskInRange': true,
          'recordedDurationSeconds': 600
        },
        {
          'id': 'old-plan',
          'title': 'خارج از بازه بدون زمان',
          'kind': 'assignment',
          'taskInRange': false,
          'recordedDurationSeconds': 0
        },
        {
          'id': 'recorded-old-plan',
          'title': 'تکلیف قدیمی با زمان این بازه',
          'kind': 'assignment',
          'taskInRange': false,
          'recordedDurationSeconds': 900
        },
      ],
      'daily': [],
      'subjects': [
        {'subjectName': 'درس تاریخی', 'totalTasks': 99}
      ],
      'periodSubjects': [
        {
          'subjectId': 'subject-a',
          'subjectName': 'ریاضی',
          'totalTasks': 2,
          'completedTasks': 1,
          'recordedDurationSeconds': 1500,
          'gradePercent': 75,
          'gradedExamCount': 1
        }
      ],
      'periodExams': [
        {
          'id': 'exam',
          'title': 'امتحان مجاز',
          'kind': 'exam',
          'gradePoints': 15,
          'gradeOutOf': 20,
          'dueAt': '2026-10-10T10:00:00Z'
        }
      ],
      'asOf': '2026-10-11T10:00:00Z',
      'lastSyncAt': '2026-10-11T09:00:00Z',
      'from': _rangeEnd().subtract(const Duration(days: 7)).toIso8601String(),
      'to': _rangeEnd().toIso8601String(),
      'timezone': 'Asia/Tehran',
      'taskDatePolicy': 'due_at_then_starts_at',
      'rangeConvention': 'inclusive_from_exclusive_to',
      'completionBasis': 'current_status_of_period_tasks',
    };

HttpIdentityApi _api(Future<http.Response> Function(http.Request) handler) =>
    HttpIdentityApi(
        baseUrl: 'https://synthetic.example.test',
        client: MockClient(handler),
        sessionStore: _MemorySession())
      ..accessToken = 'synthetic-token'
      ..currentUserId = 'synthetic-parent';
Widget _page(HttpIdentityApi api, {String childId = 'child'}) => MaterialApp(
    home: LearningReportPage(
        api: api, familyId: 'family', childId: childId, childName: 'فرزند'));

void main() {
  for (final entry in <int, String>{
    0: '0 دقیقه',
    4: '4 ثانیه',
    29: '29 ثانیه',
    30: '30 ثانیه',
    59: '59 ثانیه',
    60: '1 دقیقه',
    61: '1 دقیقه و 1 ثانیه',
    90: '1 دقیقه و 30 ثانیه',
    1500: '25 دقیقه',
  }.entries) {
    testWidgets('recorded ${entry.key} seconds keeps exact parent report time',
        (tester) async {
      final report = _report('تکلیف با زمان دقیق');
      (report['periodMetrics'] as Map)['recordedDurationSeconds'] = entry.key;
      final api = _api((_) async => _response(report));
      await tester.pumpWidget(_page(api));
      await tester.pumpAndSettle();
      expect(find.text('زمان ثبت‌شده: ${entry.value}'), findsOneWidget);
      expect(find.text('زمان برنامه‌ریزی‌شده: 30 دقیقه'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      api.close();
    });
  }

  testWidgets('short duration remains exact in daily, subject and task rows',
      (tester) async {
    final report = _report('تکلیف چهارثانیه‌ای');
    (report['periodMetrics'] as Map)['recordedDurationSeconds'] = 4;
    report['daily'] = [
      {'date': '2026-10-11', 'recordedDurationSeconds': 4}
    ];
    (report['periodSubjects'] as List).single['recordedDurationSeconds'] = 4;
    report['items'] = [
      {
        'id': 'short-task',
        'title': 'تکلیف چهارثانیه‌ای',
        'kind': 'assignment',
        'taskInRange': true,
        'plannedDurationSeconds': 1800,
        'recordedDurationSeconds': 4
      }
    ];
    final api = _api((_) async => _response(report));
    await tester.pumpWidget(_page(api));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('4 ثانیه'), 200);
    expect(find.text('4 ثانیه'), findsOneWidget);
    await tester.scrollUntilVisible(
        find.textContaining('1/2 تکمیل تکلیف‌های بازه · 4 ثانیه'), 200);
    expect(find.textContaining('1/2 تکمیل تکلیف‌های بازه · 4 ثانیه'),
        findsOneWidget);
    await tester.scrollUntilVisible(
        find.textContaining('برنامه 30 دقیقه · ثبت 4 ثانیه'), 200);
    expect(
        find.textContaining('برنامه 30 دقیقه · ثبت 4 ثانیه'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    api.close();
  });

  testWidgets('legacy report preserves planned seconds without rounding',
      (tester) async {
    final report = _report('تکلیف سرور قبلی')
      ..remove('periodMetrics')
      ..remove('periodSubjects')
      ..remove('periodExams');
    (report['metrics'] as Map)
      ..['plannedDurationSeconds'] = 95
      ..['recordedDurationSeconds'] = 4;
    final api = _api((_) async => _response(report));
    await tester.pumpWidget(_page(api));
    await tester.pumpAndSettle();
    expect(
        find.text('زمان برنامه‌ریزی‌شده: 1 دقیقه و 35 ثانیه'), findsOneWidget);
    expect(find.text('زمان ثبت‌شده: 4 ثانیه'), findsOneWidget);
    expect(find.textContaining('سرور آمار تکلیف‌های بازه را ارائه نکرده'),
        findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    api.close();
  });

  testWidgets('mixed duration fits a narrow RTL daily report', (tester) async {
    tester.view.physicalSize = const Size(320, 960);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final report = _report('تکلیف نیم‌دقیقه اضافه');
    report['daily'] = [
      {'date': '2026-10-11', 'recordedDurationSeconds': 90}
    ];
    final api = _api((_) async => _response(report));
    await tester.pumpWidget(MaterialApp(
        home: Directionality(
            textDirection: TextDirection.rtl,
            child: LearningReportPage(
                api: api,
                familyId: 'family',
                childId: 'child',
                childName: 'فرزند'))));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('1 دقیقه و 30 ثانیه'), 200);
    expect(find.text('1 دقیقه و 30 ثانیه'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    api.close();
  });

  testWidgets(
      'range dashboard uses period counters and preserves explicitly labelled history',
      (tester) async {
    final api = _api((_) async => _response(_report('تکلیف بازه')));
    await tester.pumpWidget(_page(api));
    await tester.pumpAndSettle();
    expect(find.text('2 تکلیف در بازه'), findsOneWidget);
    expect(find.text('50٪ تکمیل تکلیف‌های بازه'), findsOneWidget);
    expect(find.textContaining('کل سابقه مجاز: 99 تکلیف'), findsOneWidget);
    expect(find.text('زمان برنامه‌ریزی‌شده: 30 دقیقه'), findsOneWidget);
    expect(find.text('زمان ثبت‌شده: 25 دقیقه'), findsOneWidget);
    expect(find.text('خارج از بازه بدون زمان'), findsNothing);
    expect(find.text('درس تاریخی'), findsNothing);
    await tester.scrollUntilVisible(
        find.text('تکلیف قدیمی با زمان این بازه'), 250);
    expect(find.text('تکلیف قدیمی با زمان این بازه'), findsOneWidget);
    expect(
        find.textContaining('موعد این تکلیف خارج از بازه است'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    api.close();
  });

  testWidgets(
      'older server counters are clearly historical and do not claim period completion',
      (tester) async {
    final data = _report('تکلیف تاریخی')
      ..remove('periodMetrics')
      ..remove('periodSubjects')
      ..remove('periodExams');
    final api = _api((_) async => _response(data));
    await tester.pumpWidget(_page(api));
    await tester.pumpAndSettle();
    expect(find.textContaining('سرور آمار تکلیف‌های بازه را ارائه نکرده'),
        findsOneWidget);
    expect(find.text('99 تکلیف در کل سابقه مجاز'), findsOneWidget);
    expect(find.text('91٪ تکمیل تکلیف‌های بازه'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    api.close();
  });

  testWidgets(
      'delayed previous-child report cannot overwrite the newly selected child',
      (tester) async {
    final first = Completer<http.Response>();
    var calls = 0;
    final api = _api((request) {
      calls++;
      return request.url.path.contains('/children/first/')
          ? first.future
          : Future.value(_response(_report('گزارش فرزند دوم')));
    });
    await tester.pumpWidget(_page(api, childId: 'first'));
    await tester.pump();
    await tester.pumpWidget(_page(api, childId: 'second'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    await tester.scrollUntilVisible(find.text('گزارش فرزند دوم'), 250);
    first.complete(_response(_report('گزارش فرزند اول قدیمی')));
    await tester.pumpAndSettle();
    expect(find.text('گزارش فرزند اول قدیمی'), findsNothing);
    expect(find.text('گزارش فرزند دوم'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    api.close();
  });

  testWidgets('signed-out report never requests or exposes a child report',
      (tester) async {
    var calls = 0;
    final api = _api((_) async {
      calls++;
      return _response(_report('اطلاعات خصوصی بدون حساب'));
    })
      ..accessToken = null;
    await tester.pumpWidget(_page(api));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.text('اطلاعات خصوصی بدون حساب'), findsNothing);
    expect(find.textContaining('نشست ورود معتبر نیست'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    api.close();
  });

  testWidgets(
      'malformed period response is refused instead of fabricated zeroes',
      (tester) async {
    final data = _report('پاسخ نامعتبر')
      ..['periodMetrics'] = {'totalTasks': -1};
    final api = _api((_) async => _response(data));
    await tester.pumpWidget(_page(api));
    await tester.pumpAndSettle();
    expect(find.text('-1 تکلیف در بازه'), findsNothing);
    expect(find.text('0٪ تکمیل تکلیف‌های بازه'), findsNothing);
    expect(find.textContaining('پاسخ معتبر نداد'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    api.close();
  });

  testWidgets(
      'failed refresh clears period metrics without old permission proof',
      (tester) async {
    var fail = false;
    final api = _api((_) async => fail
        ? http.Response('{"error":"synthetic_failed"}', 500,
            headers: {'content-type': 'application/json'})
        : _response(_report('تکلیف مجاز قبلی')));
    await tester.pumpWidget(_page(api));
    await tester.pumpAndSettle();
    expect(find.text('2 تکلیف در بازه'), findsOneWidget);
    fail = true;
    await tester.pump(const Duration(seconds: 15));
    await tester.pumpAndSettle();
    expect(find.text('2 تکلیف در بازه'), findsNothing);
    expect(find.textContaining('اطلاعات فرزند بدون تأیید مجوز فعلی'),
        findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    api.close();
  });

  testWidgets('family dashboard clears prior account while replacement waits',
      (tester) async {
    final second = Completer<http.Response>();
    final firstApi =
        _api((request) async => _response(request.url.path.endsWith('/members')
            ? {
                'members': [
                  {
                    'user_id': 'first-child',
                    'role': 'teen_minor',
                    'display_name': 'فرزند حساب پیشین'
                  }
                ]
              }
            : {
                'families': [
                  {
                    'id': 'family',
                    'role': 'parent_guardian',
                    'name': 'خانواده اول'
                  }
                ]
              }));
    final secondApi = _api((_) => second.future)
      ..currentUserId = 'second-synthetic-parent';
    Widget family(HttpIdentityApi api) =>
        MaterialApp(home: Scaffold(body: ParentFamilyDashboard(api: api)));
    await tester.pumpWidget(family(firstApi));
    await tester.pumpAndSettle();
    expect(find.text('فرزند حساب پیشین'), findsOneWidget);
    await tester.pumpWidget(family(secondApi));
    await tester.pump();
    expect(find.text('فرزند حساب پیشین'), findsNothing);
    second.complete(_response({'families': []}));
    await tester.pumpAndSettle();
    expect(find.text('فرزند متصل نمایش داده نشد'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    firstApi.close();
    secondApi.close();
  });

  testWidgets(
      'pausing clears a report and resumed fetch must freshly authorize',
      (tester) async {
    final delayed = Completer<http.Response>();
    var calls = 0;
    final api = _api((_) {
      calls++;
      return calls == 1
          ? Future.value(_response(_report('داده مجاز قبلی')))
          : delayed.future;
    });
    await tester.pumpWidget(_page(api));
    await tester.pumpAndSettle();
    expect(find.text('2 تکلیف در بازه'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(find.text('2 تکلیف در بازه'), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('2 تکلیف در بازه'), findsNothing);
    delayed.complete(_response(_report('داده تازه مجاز')));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('2 تکلیف در بازه'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    api.close();
  });

  for (final field in ['from', 'familyId', 'childId']) {
    testWidgets('report rejects mismatched requested $field', (tester) async {
      final data = _report('گزارش خارج از درخواست');
      data[field] =
          field == 'from' ? '2025-01-01T00:00:00Z' : 'another-synthetic-id';
      final api = _api((_) async => _response(data));
      await tester.pumpWidget(_page(api));
      await tester.pumpAndSettle();
      expect(find.text('2 تکلیف در بازه'), findsNothing);
      expect(find.textContaining('پاسخ معتبر نداد'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      api.close();
    });
  }

  testWidgets('same API account switch requests new report immediately',
      (tester) async {
    var calls = 0;
    final api = _api((_) async {
      calls++;
      return _response(
          _report(calls == 1 ? 'گزارش حساب اول' : 'گزارش حساب دوم'));
    });
    await tester.pumpWidget(_page(api));
    await tester.pumpAndSettle();
    expect(calls, 1);
    api.currentUserId = 'another-synthetic-parent';
    await tester.pumpWidget(_page(api));
    await tester.pumpAndSettle();
    expect(calls, 2);
    await tester.scrollUntilVisible(find.text('گزارش حساب دوم'), 200);
    expect(find.text('گزارش حساب اول'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    api.close();
  });
}
