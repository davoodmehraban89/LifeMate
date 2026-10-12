import 'dart:convert';
import 'dart:ui' show SemanticsRole;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifemate/api.dart';
import 'package:lifemate/education_ui.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

// Explicit HTTP/widget fixtures, not evidence of a live curriculum or playback.
const courseId = '10000000-0000-4000-8000-000000000001';
const firstId = '20000000-0000-4000-8000-000000000001';
const lastId = '20000000-0000-4000-8000-000000000002';

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
      if (call.method == 'beginWrite') {
        return token = 'education-widget-fixture';
      }
      if (call.method == 'completeWrite' && call.arguments == token) {
        token = null;
        return true;
      }
      throw PlatformException(code: 'local_storage_restart_required');
    });
  });

  Widget screen(Widget child) => MaterialApp(
      home: Scaffold(
          body:
              Directionality(textDirection: TextDirection.rtl, child: child)));
  http.Response response(Object data) => http.Response(jsonEncode(data), 200,
      headers: {'content-type': 'application/json; charset=utf-8'});
  HttpIdentityApi makeApi(
          Future<http.Response> Function(http.Request) handler) =>
      HttpIdentityApi(
          baseUrl: 'https://education.example.test/api',
          client: MockClient(handler))
        ..accessToken = 'synthetic-fixture-token'
        ..currentUserId = 'synthetic-learner';

  Future<void> showProgress(WidgetTester tester) async {
    await tester.scrollUntilVisible(find.textContaining('پیشرفت شخصی:'), 100,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
  }

  void expectProgressAnnouncement(WidgetTester tester, String label) {
    final announcement = find.bySemanticsLabel(label);
    expect(announcement, findsOneWidget);
    expect(
        tester.getSemantics(announcement),
        matchesSemantics(
            label: label,
            role: kIsWeb ? SemanticsRole.status : SemanticsRole.none,
            isLiveRegion: !kIsWeb,
            textDirection: TextDirection.rtl));
  }

  testWidgets(
      'progress live region announces acknowledged status and timestamp after update and reopen',
      (tester) async {
    final semantics = tester.ensureSemantics();
    Map<String, dynamic>? progress;
    final api = makeApi((request) async {
      if (request.method == 'PUT') {
        final submitted = jsonDecode(request.body) as Map<String, dynamic>;
        progress = {
          ...submitted,
          'unitId': firstId,
          'version': 1,
          'updatedAt': '2026-10-11T10:00:00Z',
          'acceptedAt': '2026-10-11T10:00:00Z'
        };
        return response(progress!);
      }
      return response({
        'id': courseId,
        'titleFa': 'کتاب آزمایشی',
        'units': [
          {
            'id': firstId,
            'titleFa': 'درس آزمایشی',
            'videos': [],
            'progress': progress
          }
        ]
      });
    });
    Widget lesson() => screen(
        LearningLessonPage(api: api, courseId: courseId, unitId: firstId));
    await tester.pumpWidget(lesson());
    await tester.pumpAndSettle();
    await showProgress(tester);
    expectProgressAnnouncement(tester, 'پیشرفت شخصی: شروع نشده');
    await tester.tap(find.text('در حال یادگیری'));
    await tester.pumpAndSettle();
    await showProgress(tester);
    const accepted =
        'پیشرفت شخصی: در حال یادگیری\nآخرین ثبت سرور: 2026-10-11T10:00:00Z';
    expectProgressAnnouncement(tester, accepted);
    expect(find.bySemanticsLabel('پیشرفت شخصی: شروع نشده'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await tester.pumpWidget(lesson());
    await tester.pumpAndSettle();
    await showProgress(tester);
    expectProgressAnnouncement(tester, accepted);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    semantics.dispose();
    api.close();
  });

  testWidgets(
      'pending progress announcement preserves the prior server timestamp',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final api = makeApi((request) async {
      if (request.method == 'PUT') {
        throw http.ClientException('synthetic offline');
      }
      return response({
        'id': courseId,
        'titleFa': 'کتاب آزمایشی',
        'units': [
          {
            'id': firstId,
            'titleFa': 'درس آزمایشی',
            'videos': [],
            'progress': {
              'unitId': firstId,
              'status': 'in_progress',
              'source': 'self_reported',
              'version': 1,
              'updatedAt': '2026-10-11T09:00:00Z'
            }
          }
        ]
      });
    });
    await tester.pumpWidget(screen(
        LearningLessonPage(api: api, courseId: courseId, unitId: firstId)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('طبق گزارش من تکمیل شد'));
    await tester.pumpAndSettle();
    await showProgress(tester);
    expectProgressAnnouncement(tester,
        'پیشرفت شخصی: تکمیل طبق گزارش من\nتغییر روی دستگاه ذخیره شده؛ تأیید سرور دریافت نشده است.\nآخرین ثبت سرور: 2026-10-11T09:00:00Z');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    semantics.dispose();
    api.close();
  });

  testWidgets(
      'no education profile asks selection without silently choosing grade7',
      (tester) async {
    final api = makeApi((request) async => response({
          'education': null,
          'courses': [],
          'fetchedAt': '2026-10-09T10:00:00Z'
        }));
    await tester.pumpWidget(screen(EducationLibraryPage(api: api)));
    await tester.pumpAndSettle();
    expect(find.textContaining('پایه تحصیلی را انتخاب کن'), findsOneWidget);
    expect(find.textContaining('پایه 7'), findsNothing);
    expect(tester.takeException(), isNull);
    api.close();
  });

  testWidgets(
      'grade and upper track are saved through real API contract, not a display-only preference',
      (tester) async {
    Map<String, dynamic>? saved;
    final api = makeApi((request) async {
      if (request.method == 'PUT') {
        expect(request.url.path, '/api/v1/me/education');
        saved = jsonDecode(request.body) as Map<String, dynamic>;
        return response(saved!);
      }
      return response({
        'education': {
          'nationalGrade': 10,
          'trackCode': 'math',
          'schoolYear': '1405-1406'
        },
        'courses': []
      });
    });
    await tester.pumpWidget(screen(EducationLibraryPage(api: api)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('انتخاب پایه و رشته'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('education-track')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('علوم تجربی').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('ذخیره'));
    await tester.pumpAndSettle();
    expect(saved, {
      'nationalGrade': 10,
      'trackCode': 'experimental',
      'schoolYear': '1405-1406'
    });
    expect(tester.takeException(), isNull);
    api.close();
  });

  testWidgets(
      'midyear last lesson opens in same app with no video load or automatic completion',
      (tester) async {
    var writes = 0;
    final api = makeApi((request) async {
      if (request.method != 'GET') writes++;
      expect(request.url.path, '/api/v1/education/courses/$courseId');
      return response({
        'id': courseId,
        'titleFa': 'کتاب آزمایشی',
        'schoolYear': null,
        'alignmentNotesFa': 'تطابق نسخه تأیید نشده',
        'fetchedAt': '2026-10-09T10:00:00Z',
        'units': [
          {
            'id': firstId,
            'titleFa': 'بخش آغاز',
            'orderIndex': 1,
            'videos': [],
            'progress': null
          },
          {
            'id': lastId,
            'titleFa': 'بخش میانه سال',
            'orderIndex': 2,
            'progress': null,
            'videos': [
              {
                'aparatId': 'rod03i6',
                'titleFa': 'منبع آزمایشی قاب',
                'creatorName': 'مدرس نمونه',
                'creatorUrl': 'https://www.aparat.com/example',
                'freeAccess': true
              }
            ]
          }
        ]
      });
    });
    await tester
        .pumpWidget(screen(LearningCoursePage(api: api, courseId: courseId)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('بخش میانه سال'));
    await tester.pumpAndSettle();
    expect(find.text('بارگذاری ویدئو از آپارات'), findsOneWidget);
    await tester.scrollUntilVisible(find.textContaining('پیشرفت شخصی:'), 100,
        scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('پیشرفت شخصی: شروع نشده'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('بخش قبلی'), 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('بخش قبلی'), findsOneWidget);
    expect(writes, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    api.close();
  });

  testWidgets(
      'permission denial removes previously displayed personal progress',
      (tester) async {
    final semantics = tester.ensureSemantics();
    var denied = false;
    final api = makeApi((request) async {
      if (denied) return http.Response('{"error":"forbidden"}', 403);
      return response({
        'id': courseId,
        'titleFa': 'کتاب خصوصی آزمایشی',
        'units': [
          {
            'id': firstId,
            'titleFa': 'درس خصوصی آزمایشی',
            'videos': [],
            'progress': {
              'unitId': firstId,
              'status': 'completed',
              'source': 'self_reported',
              'version': 1,
              'updatedAt': '2026-10-09T10:00:00Z'
            }
          }
        ]
      });
    });
    await tester.pumpWidget(screen(
        LearningLessonPage(api: api, courseId: courseId, unitId: firstId)));
    await tester.pumpAndSettle();
    expect(find.textContaining('تکمیل طبق گزارش من'), findsOneWidget);
    await showProgress(tester);
    expectProgressAnnouncement(tester,
        'پیشرفت شخصی: تکمیل طبق گزارش من\nآخرین ثبت سرور: 2026-10-09T10:00:00Z');
    denied = true;
    await tester.scrollUntilVisible(find.text('همگام‌سازی و تازه‌سازی'), 250,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('همگام‌سازی و تازه‌سازی'));
    await tester.pumpAndSettle();
    expect(find.textContaining('تکمیل طبق گزارش من'), findsNothing);
    expect(
        find.bySemanticsLabel(
            RegExp('تکمیل طبق گزارش من|2026-10-09T10:00:00Z')),
        findsNothing);
    expect(find.text('درس خصوصی آزمایشی'), findsNothing);
    expect(find.textContaining('نشست معتبر لازم است'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    semantics.dispose();
    api.close();
  });

  testWidgets('rejected progress remains visible after a successful read',
      (tester) async {
    final api = makeApi((request) async {
      if (request.method == 'PUT') {
        return http.Response('{"error":"version_conflict"}', 409);
      }
      return response({
        'id': courseId,
        'titleFa': 'کتاب آزمایشی',
        'units': [
          {
            'id': firstId,
            'titleFa': 'درس آزمایشی',
            'videos': [],
            'progress': null
          }
        ]
      });
    });
    await tester.pumpWidget(screen(
        LearningLessonPage(api: api, courseId: courseId, unitId: firstId)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('در حال یادگیری'));
    await tester.pumpAndSettle();
    expect(find.textContaining('تغییر معلق یا تعارض'), findsOneWidget);
    expect(find.text('حل تعارض با پیشرفت سرور'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    api.close();
  });
}
