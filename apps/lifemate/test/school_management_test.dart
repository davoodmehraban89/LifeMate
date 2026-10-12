import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifemate/api.dart';
import 'package:lifemate/phase3_ui.dart';
import 'package:lifemate/school_management_ui.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData({});
    String? guard;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('lifeguide/local_write_guard'), (call) async {
      if (call.method == 'getBlocked') return guard != null;
      if (call.method == 'beginWrite') return guard = 'school-test-guard';
      if (call.method == 'completeWrite' && call.arguments == guard) {
        guard = null;
        return true;
      }
      throw PlatformException(code: 'local_storage_restart_required');
    });
  });
  testWidgets(
      'school entry replaces hardcoded quick setup with explicit management',
      (tester) async {
    final paths = <String>[];
    final api = HttpIdentityApi(
        baseUrl: 'https://school.example.test/api',
        client: MockClient((request) async {
          paths.add('${request.method} ${request.url.path}');
          return http.Response(
              jsonEncode(request.url.path.endsWith('/profile')
                  ? {'user_id': '10000000-0000-4000-8000-000000000001'}
                  : {
                      'years': [],
                      'subjects': [],
                      'workload': [],
                      'grades': []
                    }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'});
        }))
      ..accessToken = 'synthetic'
      ..currentUserId = '10000000-0000-4000-8000-000000000001';
    await tester
        .pumpWidget(MaterialApp(home: Scaffold(body: SchoolPage(api: api))));
    await tester.pumpAndSettle();
    expect(find.text('مدیریت مدرسه'), findsOneWidget);
    expect(find.text('شروع سریع'), findsNothing);
    expect(paths.where((p) => p.startsWith('POST')), isEmpty);
    await tester.pumpWidget(const SizedBox());
    api.close();
  });
  testWidgets(
      'explicit editor has empty user-picked year dates and never sends quick setup writes',
      (tester) async {
    final posts = <String>[];
    final api = HttpIdentityApi(
        baseUrl: 'https://school-date.test/api',
        client: MockClient((request) async {
          if (request.method != 'GET') posts.add(request.body);
          final data = request.url.path.endsWith('/lifecycle')
              ? schoolSnapshot()
              : request.url.path.endsWith('/timetable')
                  ? {'classes': []}
                  : {'subjects': [], 'years': [], 'workload': [], 'grades': []};
          return jsonResponse(data);
        }))
      ..accessToken = 'synthetic'
      ..currentUserId = schoolOwner;
    await tester.pumpWidget(MaterialApp(home: SchoolManagementPage(api: api)));
    await tester.pumpAndSettle();
    final createYear = find.widgetWithText(TextButton, 'ایجاد').at(1);
    await tester.ensureVisible(createYear);
    await tester.tap(createYear);
    await tester.pumpAndSettle();
    expect(find.textContaining('تاریخ میلادی: YYYY-MM-DD'), findsOneWidget);
    final fields =
        tester.widgetList<TextField>(find.byType(TextField)).toList();
    expect(
        fields.map((field) => field.controller!.text), everyElement(isEmpty));
    expect(find.byIcon(Icons.calendar_month), findsNWidgets(2));
    expect(posts, isEmpty);
    await tester.tap(find.text('انصراف'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    api.close();
  });

  testWidgets(
      'uncertain non-idempotent subject create refetches once and never auto retries',
      (tester) async {
    final subjects = <Map<String, dynamic>>[], writes = <String>[];
    var readsAfterWrite = 0;
    final api = HttpIdentityApi(
        baseUrl: 'https://school-subject.test/api',
        client: MockClient((request) async {
          if (request.method == 'POST') {
            writes.add(request.body);
            final data = jsonDecode(request.body) as Map;
            subjects.add({
              'id': '40000000-0000-4000-8000-000000000001',
              'name': data['name'],
              'teacher_name': data['teacherName'],
              'academic_term_id': schoolTermId
            });
            throw http.ClientException('synthetic lost ACK after commit');
          }
          if (writes.isNotEmpty) readsAfterWrite++;
          final data = request.url.path.endsWith('/lifecycle')
              ? schoolSnapshot()
              : request.url.path.endsWith('/timetable')
                  ? {'classes': []}
                  : {
                      'subjects': subjects,
                      'years': [],
                      'workload': [],
                      'grades': []
                    };
          return jsonResponse(data);
        }))
      ..accessToken = 'synthetic'
      ..currentUserId = schoolOwner;
    await tester.pumpWidget(MaterialApp(home: SchoolManagementPage(api: api)));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('درس جدید'), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('درس جدید'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'درس انتخابی');
    await tester.tap(find.text('نیمسال فعال'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('نیمسال انتخابی').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('ثبت'));
    await tester.pumpAndSettle();
    expect(writes, hasLength(1));
    expect(subjects, hasLength(1));
    expect(readsAfterWrite, greaterThanOrEqualTo(3));
    await tester.drag(find.byType(ListView).first, const Offset(0, 1800));
    await tester.pumpAndSettle();
    expect(find.textContaining('نتیجه ارسال نامشخص است'), findsOneWidget);
    await tester.tap(find.byTooltip('تازه‌کردن'));
    await tester.pumpAndSettle();
    expect(writes, hasLength(1));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(MaterialApp(home: SchoolManagementPage(api: api)));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('درس انتخابی'), 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('درس انتخابی'), findsOneWidget);
    expect(writes, hasLength(1));
    await tester.pumpWidget(const SizedBox());
    api.close();
  });
}

const schoolOwner = '10000000-0000-4000-8000-000000000001';
const schoolContextId = '20000000-0000-4000-8000-000000000001';
const schoolYearId = '30000000-0000-4000-8000-000000000001';
const schoolTermId = '30000000-0000-4000-8000-000000000002';
const schoolAt = '2026-10-11T12:00:00Z';
http.Response jsonResponse(Object body) => http.Response(jsonEncode(body), 200,
    headers: {'content-type': 'application/json; charset=utf-8'});
Map<String, dynamic> schoolSnapshot() => {
      'contexts': [
        {
          'id': schoolContextId,
          'user_id': schoolOwner,
          'kind': 'student',
          'title': 'مدرسه انتخابی',
          'active': true,
          'version': 1,
          'created_at': schoolAt,
          'updated_at': schoolAt
        }
      ],
      'years': [
        {
          'id': schoolYearId,
          'student_user_id': schoolOwner,
          'life_context_id': schoolContextId,
          'title': 'سال انتخابی',
          'starts_on': '2026-08-12',
          'ends_on': '2027-07-05',
          'active': true,
          'version': 1,
          'created_at': schoolAt,
          'updated_at': schoolAt
        }
      ],
      'terms': [
        {
          'id': schoolTermId,
          'academic_year_id': schoolYearId,
          'title': 'نیمسال انتخابی',
          'starts_on': '2026-08-15',
          'ends_on': '2027-02-10',
          'active': true,
          'version': 1,
          'created_at': schoolAt,
          'updated_at': schoolAt
        }
      ],
      'fetchedAt': schoolAt
    };
