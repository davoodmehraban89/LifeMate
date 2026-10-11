import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifemate/api.dart';
import 'package:lifemate/learning_quiz_ui.dart';
import 'package:lifemate/offline_store.dart';
import 'package:lifemate/session_store.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

// SYNTHETIC reviewed-bank substitutes only. No real questions are published.
const _unit = '00000000-0000-4000-8000-000000000101';
const _assessment = '00000000-0000-4000-8000-000000000102';
const _mutation = '00000000-0000-4000-8000-000000000103';
const _attempt = '00000000-0000-4000-8000-000000000104';

Map<String, dynamic> _body() => {
      'mutationId': _mutation,
      'assessmentId': _assessment,
      'assessmentVersion': 2,
      'answers': [
        {'questionId': 'q1', 'choiceId': 'a'}
      ],
      'confidence': 'unsure',
    };

Map<String, dynamic> _bank() => {
      'id': _assessment,
      'unitId': _unit,
      'version': 2,
      'questions': [
        {
          'id': 'q1',
          'objectiveId': 'objective-1',
          'promptFa': 'پرسش صرفاً آزمایشی',
          'choices': [
            {'id': 'a', 'textFa': 'گزینه آزمایشی الف'},
            {'id': 'b', 'textFa': 'گزینه آزمایشی ب'},
          ],
        }
      ],
    };

class _Session implements SessionStore {
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String value) async {}
  @override
  Future<void> clear() async {}
}

class _Fixture {
  _Fixture() {
    api = HttpIdentityApi(
      baseUrl: 'https://quiz.test',
      client: MockClient(handle),
      sessionStore: _Session(),
    )
      ..accessToken = 'synthetic-token'
      ..currentUserId = 'synthetic-learner-${next++}';
    store = OfflineStore.forNamespace(api.cacheNamespace!,
        session: OfflineSession());
    sync = LearningQuizSync(api, store: store);
  }
  static int next = 0;
  late final HttpIdentityApi api;
  late final OfflineStore store;
  late final LearningQuizSync sync;
  bool offline = false, loseAcknowledgement = false, reviewed = true;
  int? failure;
  Future<void>? delay;
  final posts = <Map<String, dynamic>>[];
  final applied = <String, Map<String, dynamic>>{};
  Map<String, dynamic> Function(Map<String, dynamic>)? alterAck;

  Future<http.Response> handle(http.Request request) async {
    if (request.method == 'GET') {
      return http.Response(
          jsonEncode({
            'assessment': reviewed ? _bank() : null,
            if (!reviewed) 'reason': 'review_pending'
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    }
    expect(request.method, 'POST');
    expect(request.url.path, '/v1/me/learning-attempts');
    final body = Map<String, dynamic>.from(jsonDecode(request.body) as Map);
    posts.add(body);
    if (delay != null) await delay;
    if (offline) throw http.ClientException('synthetic offline transport');
    if (failure != null) {
      return http.Response(
          jsonEncode({'error': 'synthetic_rejection'}), failure!);
    }
    final id = body['mutationId'] as String;
    applied.putIfAbsent(
        id,
        () => {
              'mutationId': id,
              'attemptId': _attempt,
              'unitId': _unit,
              'assessmentId': _assessment,
              'assessmentVersion': 2,
              'correctCount': 1,
              'total': 1,
              'feedback': [
                {
                  'questionId': 'q1',
                  'objectiveId': 'objective-1',
                  'correct': true,
                  'explanationFa': 'توضیح صرفاً آزمایشی',
                  'remediationFa': 'مرور صرفاً آزمایشی',
                }
              ],
              'resultLabel': 'answered_correctly',
              'nextReviewAt': '2026-10-12T10:00:00Z',
              'schedulePolicy': 'pilot-1-or-3-days',
              'source': 'quiz_answers',
              'acceptedAt': '2026-10-09T10:00:00Z',
            });
    if (loseAcknowledgement) {
      loseAcknowledgement = false;
      throw http.ClientException('synthetic response lost after commit');
    }
    final ack = Map<String, dynamic>.from(applied[id]!);
    return http.Response(jsonEncode(alterAck?.call(ack) ?? ack), 201,
        headers: {'content-type': 'application/json; charset=utf-8'});
  }

  LearningQuizSync reopen() => LearningQuizSync(api,
      store: OfflineStore.forNamespace(store.scope, session: OfflineSession()));
}

Matcher _error(String code) =>
    throwsA(isA<ApiException>().having((e) => e.code, 'code', code));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var blocked = false;
  setUp(() {
    blocked = false;
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData({});
    String? token;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('lifeguide/local_write_guard'), (call) async {
      if (call.method == 'getBlocked') return blocked || token != null;
      if (call.method == 'beginWrite') return token = 'synthetic-quiz-write';
      if (call.method == 'completeWrite' && call.arguments == token) {
        token = null;
        return true;
      }
      throw PlatformException(code: 'local_storage_restart_required');
    });
  });

  test(
      'durable before POST, lost acknowledgement replays exact attempt after reopen',
      () async {
    final blockedFixture = _Fixture();
    blocked = true;
    await expectLater(
        blockedFixture.sync.submit(_body(), _unit), throwsA(anything));
    expect(blockedFixture.posts, isEmpty);
    blocked = false;
    final f = _Fixture();
    f.loseAcknowledgement = true;
    expect((await f.sync.submit(_body(), _unit))['queued'], true);
    final pending = (await f.store.readQueue()).single;
    expect(pending['unitId'], _unit);
    expect(pending['payload'], _body());
    expect(f.posts.single.containsKey('unitId'), false);
    await f.reopen().flush();
    expect(f.posts, [_body(), _body()]);
    expect(f.applied.length, 1);
    expect(await f.store.readQueue(), isEmpty);
    expect(
        (await f.store.readList('learning_attempts')).single['id'], _attempt);
    expect(await f.store.readList('learning_progress'), isEmpty);
    expect(await f.store.readPlanner(), isEmpty);
  });

  test(
      'wrong acknowledgements retain answers; permanent rejection is recoverable',
      () async {
    for (final alter in <Map<String, dynamic> Function(Map<String, dynamic>)>[
      (ack) => ack..['assessmentVersion'] = 3,
      (ack) => ack..['unitId'] = _assessment,
      (ack) => ack..['source'] = 'timer',
      (ack) => ack..['correctCount'] = 0,
      (ack) => ack..['nextReviewAt'] = '2026-10-10T10:00:00Z',
      (ack) => ack..['feedback'] = [],
    ]) {
      final f = _Fixture()..alterAck = alter;
      await expectLater(f.sync.submit(_body(), _unit),
          _error('invalid_sync_acknowledgement'));
      expect((await f.store.readQueue()).single['payload'], _body());
      expect(await f.store.readList('learning_attempts'), isEmpty);
    }
    for (final status in [409, 400]) {
      final f = _Fixture()..failure = status;
      await expectLater(
          f.sync.submit(_body(), _unit), _error('synthetic_rejection'));
      expect((await f.store.readQueue()).single['queueStatus'],
          status == 409 ? 'conflict' : 'rejected');
      await f.sync.cancelPending(_mutation);
      expect(await f.store.readQueue(), isEmpty);
      expect((await f.store.readDiscardedChanges()).single['payload'], _body());
    }
  });

  test('late response after account switch cannot acknowledge the old queue',
      () async {
    final f = _Fixture();
    final release = Completer<void>();
    f.delay = release.future;
    final request = f.sync.submit(_body(), _unit);
    final failed = expectLater(request, throwsA(isA<ApiException>()));
    while (f.posts.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    f.api.currentUserId = 'another-synthetic-account';
    release.complete();
    await failed;
    expect((await f.store.readQueue()).single['payload'], _body());
    expect(await f.store.readList('learning_attempts'), isEmpty);
    final other = OfflineStore.forNamespace(f.api.cacheNamespace!);
    expect(await other.readQueue(), isEmpty);
    await expectLater(f.reopen().flush(), _error('cache_scope_closed'));
    expect(f.posts.length, 1);
  });

  testWidgets('no reviewed bank means no placeholder questions or submission',
      (tester) async {
    final f = _Fixture()..reviewed = false;
    await tester.pumpWidget(
        MaterialApp(home: LearningQuizPage(api: f.api, unitId: _unit)));
    await tester.pumpAndSettle();
    expect(find.textContaining('در انتظار بازبینی'), findsOneWidget);
    expect(find.byKey(const Key('quiz-submit')), findsNothing);
    expect(find.text('پرسش صرفاً آزمایشی'), findsNothing);
    expect(f.posts, isEmpty);
  });

  testWidgets(
      'explicit answers and confidence; reopen locks pending answers and retries',
      (tester) async {
    final f = _Fixture()..offline = true;
    await tester.pumpWidget(
        MaterialApp(home: LearningQuizPage(api: f.api, unitId: _unit)));
    await tester.pumpAndSettle();
    FilledButton submit() =>
        tester.widget(find.byKey(const Key('quiz-submit')));
    expect(submit().onPressed, isNull);
    await tester.tap(find.byKey(const Key('quiz-choice-q1-a')));
    await tester.pump();
    expect(submit().onPressed, isNull);
    await tester.tap(find.byKey(const Key('quiz-confidence-unsure')));
    await tester.pump();
    expect(submit().onPressed, isNotNull);
    await tester.ensureVisible(find.byKey(const Key('quiz-submit')));
    await tester.tap(find.byKey(const Key('quiz-submit')));
    await tester.pumpAndSettle();
    final sent = f.posts.single;
    expect(sent.containsKey('unitId'), false);
    expect(find.textContaining('روی این دستگاه'), findsOneWidget);
    expect(find.textContaining('پاسخ درست'), findsNothing);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pumpWidget(
        MaterialApp(home: LearningQuizPage(api: f.api, unitId: _unit)));
    await tester.pumpAndSettle();
    final choice =
        tester.widget<ChoiceChip>(find.byKey(const Key('quiz-choice-q1-a')));
    expect(choice.selected, true);
    expect(choice.onSelected, isNull);
    f.offline = false;
    await tester.ensureVisible(find.byKey(const Key('quiz-retry')));
    await tester.tap(find.byKey(const Key('quiz-retry')));
    await tester.pumpAndSettle();
    expect(f.posts, [sent, sent]);
    expect(find.text('توضیح صرفاً آزمایشی'), findsOneWidget);
    expect(find.text('مرور صرفاً آزمایشی'), findsOneWidget);
    expect(find.textContaining('پیشنهاد آزمایشی'), findsOneWidget);
    expect(await f.store.readQueue(), isEmpty);
    expect(f.posts.every((p) => p.keys.length == 5), true);
  });
}
