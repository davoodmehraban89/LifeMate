import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifemate/api.dart';
import 'package:lifemate/content_review_sync.dart';
import 'package:lifemate/content_review_ui.dart';
import 'package:lifemate/offline_store.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

const feedbackId = '81111111-1111-4111-8111-111111111111';
const mutationId = '91111111-1111-4111-8111-111111111111';
const created = '2026-10-11T10:00:00Z';
const briefId = 'a1111111-1111-4111-8111-111111111111';
Map<String, dynamic> validBrief() => {
      'id': briefId,
      'title': 'پیشنهاد بررسی و توسعه محتوای آموزشی',
      'createdAt': created,
      'sourceCount': 1,
      'categories': [
        {'category': 'topic_request', 'count': 1}
      ],
      'units': [],
      'tasks': [
        'نسخه رسمی کتاب و هدف یادگیری این درس را بررسی کنید.',
        'محتوای پیشنهادی و سؤال‌های تمرینی را به‌طور کامل بازبینی کنید.',
        'برای تغییر پیشنهادی معیار پذیرش، آزمون و PR مستقل تهیه کنید.',
        'انتشار محتوا و استقرار فقط پس از بازبینی و مجوز جداگانه انجام شود.'
      ],
      'notice':
          'این پیشنهاد ساختاری فاقد متن بازخورد و اطلاعات خصوصی است؛ تأیید محتوا یا دستور انتشار نیست.'
    };
Map<String, dynamic> feedback({String status = 'received', int version = 1}) =>
    {
      'id': feedbackId,
      'unitId': null,
      'category': 'topic_request',
      'summary': 'تمرین جمع به روش تصویری',
      'status': status,
      'version': version,
      'createdAt': created,
      'updatedAt': created,
    };
http.Response jsonResponse(Object value, [int status = 200]) =>
    http.Response(jsonEncode(value), status,
        headers: {'content-type': 'application/json; charset=utf-8'});
HttpIdentityApi apiWith(Future<http.Response> Function(http.Request) handler,
        {String actor = 'synthetic-reviewer'}) =>
    HttpIdentityApi(
        baseUrl: 'https://review.example.test/api', client: MockClient(handler))
      ..accessToken = 'synthetic-token'
      ..currentUserId = actor;

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
      if (call.method == 'beginWrite') return token = 'review-write';
      if (call.method == 'completeWrite' && call.arguments == token) {
        token = null;
        return true;
      }
      throw PlatformException(code: 'local_storage_restart_required');
    });
  });

  test(
      'lost review acknowledgement keeps only metadata and retries exact body after reopen',
      () async {
    var lost = true;
    final sent = <String>[];
    final api = apiWith((request) async {
      if (request.url.path.endsWith('/content-capabilities')) {
        return jsonResponse({
          'permissions': ['feedback.read', 'feedback.review']
        });
      }
      sent.add(request.body);
      if (lost) throw http.ClientException('synthetic lost receipt');
      return jsonResponse({
        'feedback': feedback(status: 'triaged', version: 2),
        'acknowledgement': {
          'mutationId': mutationId,
          'feedbackId': feedbackId,
          'status': 'already_applied'
        }
      });
    });
    final body = {
      'mutationId': mutationId,
      'expectedVersion': 1,
      'status': 'triaged'
    };
    await expectLater(ContentReviewSync(api).review(feedbackId, body),
        throwsA(predicate(isOfflineFailure)));
    final durable = await OfflineStore.forApi(api).readQueue();
    expect(durable.single['payload'], body);
    expect(jsonEncode(durable), isNot(contains('تمرین جمع')));
    expect(await OfflineStore.forApi(api).readList('content_review'), isEmpty);
    lost = false;
    await ContentReviewSync(api).retry(durable.single);
    expect(sent.length, 2);
    expect(sent[0], sent[1]);
    expect(await OfflineStore.forApi(api).readQueue(), isEmpty);
    api.close();
  });

  test(
      'wrong receipt leaves pending metadata and another account cannot retry it',
      () async {
    final api = apiWith((request) async => request.method == 'GET'
        ? jsonResponse({
            'permissions': ['feedback.read', 'feedback.review']
          })
        : jsonResponse({
            'feedback': feedback(status: 'triaged', version: 2),
            'acknowledgement': {
              'mutationId': 'wrong',
              'feedbackId': feedbackId,
              'status': 'accepted'
            }
          }));
    final sync = ContentReviewSync(api);
    await expectLater(
        sync.review(feedbackId, {
          'mutationId': mutationId,
          'expectedVersion': 1,
          'status': 'triaged'
        }),
        throwsA(isA<ApiException>()));
    final pending = (await sync.pending()).single;
    api.currentUserId = 'other-account';
    await expectLater(sync.retry(pending), throwsA(isA<ApiException>()));
    expect(await OfflineStore.forApi(api).readQueue(), isEmpty);
    api.close();
  });

  test('offline capability check never creates a reviewer mutation', () async {
    final api =
        apiWith((request) async => throw http.ClientException('offline'));
    await expectLater(
        ContentReviewSync(api).review(feedbackId, {
          'mutationId': mutationId,
          'expectedVersion': 1,
          'status': 'triaged'
        }),
        throwsA(predicate(isOfflineFailure)));
    expect(await OfflineStore.forApi(api).readQueue(), isEmpty);
    api.close();
  });

  test(
      'lost brief receipt retries immutable metadata and never exports a summary',
      () async {
    var lost = true;
    final sent = <String>[];
    final api = apiWith((request) async {
      if (request.url.path.endsWith('/content-capabilities')) {
        return jsonResponse({
          'permissions': ['feedback.read', 'brief.prepare']
        });
      }
      sent.add(request.body);
      if (lost) throw http.ClientException('lost response');
      return jsonResponse({
        'brief': validBrief(),
        'acknowledgement': {
          'mutationId': mutationId,
          'briefId': briefId,
          'status': 'already_applied'
        }
      });
    });
    final body = <String, dynamic>{
      'mutationId': mutationId,
      'feedback': [
        {'id': feedbackId, 'expectedVersion': 3}
      ]
    };
    final result = ContentReviewSync(api).prepareBrief(body);
    (body['feedback'] as List).single['expectedVersion'] = 999;
    await expectLater(result, throwsA(predicate(isOfflineFailure)));
    final saved = (await ContentReviewSync(api).pending()).single;
    expect((saved['payload'] as Map)['feedback'], [
      {'id': feedbackId, 'expectedVersion': 3}
    ]);
    expect(jsonEncode(saved), isNot(contains('summary')));
    lost = false;
    final accepted = await ContentReviewSync(api).retry(saved);
    expect(sent[0], sent[1]);
    expect(accepted['brief'], validBrief());
    expect(await OfflineStore.forApi(api).readQueue(), isEmpty);
    api.close();
  });

  test(
      'current newer state can acknowledge an applied review but wrong accepted transition cannot',
      () async {
    var replay = false;
    final api = apiWith((request) async {
      if (request.method == 'GET') {
        return jsonResponse({
          'permissions': ['feedback.read', 'feedback.review']
        });
      }
      return jsonResponse({
        'feedback': feedback(status: 'planned', version: 3),
        'acknowledgement': {
          'mutationId': mutationId,
          'feedbackId': feedbackId,
          'status': replay ? 'already_applied' : 'accepted'
        }
      });
    });
    final sync = ContentReviewSync(api);
    await expectLater(
        sync.review(feedbackId, {
          'mutationId': mutationId,
          'expectedVersion': 1,
          'status': 'triaged'
        }),
        throwsA(isA<ApiException>()));
    expect(await sync.pending(), hasLength(1));
    replay = true;
    await sync.retry((await sync.pending()).single);
    expect(await sync.pending(), isEmpty);
    api.close();
  });

  test(
      'inbox rejects injected private fields and preserves actual paging/filter query',
      () async {
    final api = apiWith((request) async {
      expect(request.url.queryParameters,
          {'limit': '20', 'cursor': feedbackId, 'status': 'planned'});
      return jsonResponse({
        'feedback': [
          {
            ...feedback(status: 'planned'),
            'ownerEmail': 'synthetic@example.test'
          }
        ],
        'nextCursor': null,
        'total': 1
      });
    });
    await expectLater(
        ContentReviewSync(api).inbox(status: 'planned', cursor: feedbackId),
        throwsA(isA<ApiException>()));
    expect(await OfflineStore.forApi(api).readList('content_review'), isEmpty);
    api.close();
  });

  test('revoked scope discards a delayed inbox response', () async {
    final delayed = Completer<http.Response>();
    final api = apiWith((request) => delayed.future);
    final sync = ContentReviewSync(api);
    final request = sync.inbox();
    await Future<void>.delayed(Duration.zero);
    await OfflineStore.invalidateNamespace(api.cacheNamespace!);
    delayed.complete(jsonResponse({
      'feedback': [feedback()],
      'nextCursor': null,
      'total': 1
    }));
    await expectLater(request, throwsA(isA<ApiException>()));
    api.close();
  });

  testWidgets(
      'read-only reviewer sees Persian status but no moderation buttons, and network failure clears summaries',
      (tester) async {
    var failing = false;
    final api = apiWith((request) async {
      if (failing) throw http.ClientException('synthetic offline');
      if (request.url.path.endsWith('/content-capabilities')) {
        return jsonResponse({
          'permissions': ['feedback.read']
        });
      }
      return jsonResponse({
        'feedback': [feedback()],
        'nextCursor': null,
        'total': 1
      });
    });
    await tester.pumpWidget(MaterialApp(home: ContentReviewPage(api: api)));
    await tester.pumpAndSettle();
    expect(find.text('تمرین جمع به روش تصویری'), findsOneWidget);
    expect(find.textContaining('دریافت‌شده'), findsWidgets);
    expect(find.byKey(const Key('review-status-$feedbackId')), findsNothing);
    failing = true;
    await tester.tap(find.byKey(const Key('content-refresh')));
    await tester.pumpAndSettle();
    expect(find.text('تمرین جمع به روش تصویری'), findsNothing);
    expect(find.textContaining('اتصال'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
    api.close();
  });

  testWidgets(
      'late inbox response cannot expose summaries after newer permission revocation',
      (tester) async {
    final delayed = Completer<http.Response>();
    var capabilityReads = 0;
    final api = apiWith((request) async {
      if (request.url.path.endsWith('/content-capabilities')) {
        capabilityReads++;
        return jsonResponse({
          'permissions': capabilityReads == 1 ? ['feedback.read'] : []
        });
      }
      return delayed.future;
    });
    await tester.pumpWidget(MaterialApp(home: ContentReviewPage(api: api)));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byKey(const Key('content-refresh')));
    await tester.pumpAndSettle();
    delayed.complete(jsonResponse({
      'feedback': [feedback()],
      'nextCursor': null,
      'total': 1
    }));
    await tester.pumpAndSettle();
    expect(find.text('تمرین جمع به روش تصویری'), findsNothing);
    expect(find.textContaining('مجوز'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
    api.close();
  });

  testWidgets(
      'withdrawn brief is revalidated before clipboard and never copied',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final clipboardWrites = <Object?>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboardWrites.add(call.arguments);
      }
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    var revalidated = false;
    final api = apiWith((request) async {
      if (request.url.path.endsWith('/content-capabilities')) {
        return jsonResponse({
          'permissions': ['feedback.read', 'brief.prepare']
        });
      }
      if (request.method == 'POST') {
        final body = jsonDecode(request.body) as Map;
        expect(body['feedback'], [
          {'id': feedbackId, 'expectedVersion': 3}
        ]);
        return jsonResponse({
          'brief': validBrief(),
          'acknowledgement': {
            'mutationId': body['mutationId'],
            'briefId': briefId,
            'status': 'accepted'
          }
        });
      }
      if (request.url.path.endsWith('/briefs/$briefId')) {
        revalidated = true;
        return jsonResponse({'error': 'brief_invalidated'}, 409);
      }
      return jsonResponse({
        'feedback': [feedback(status: 'planned', version: 3)],
        'nextCursor': null,
        'total': 1
      });
    });
    await tester.pumpWidget(MaterialApp(home: ContentReviewPage(api: api)));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تهیه پیشنهاد توسعه، بدون متن بازخورد'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('copy-content-brief')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('copy-content-brief')));
    await tester.tap(find.byKey(const Key('copy-content-brief')));
    await tester.pumpAndSettle();
    expect(revalidated, true);
    expect(clipboardWrites, isEmpty);
    expect(find.byKey(const Key('copy-content-brief')), findsNothing);
    expect(find.text('تمرین جمع به روش تصویری'), findsNothing);
    expect(find.textContaining('نسخه یا رضایت'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    api.close();
  });
}
