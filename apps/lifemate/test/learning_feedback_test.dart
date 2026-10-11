import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifemate/api.dart';
import 'package:lifemate/learning_feedback_ui.dart';
import 'package:lifemate/offline_store.dart';
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
      if (call.method == 'beginWrite') return token = 'feedback-fixture';
      if (call.method == 'completeWrite' && call.arguments == token) {
        token = null;
        return true;
      }
      throw PlatformException(code: 'local_storage_restart_required');
    });
  });
  const mutationId = '81111111-1111-4111-8111-111111111111';
  const body = {
    'mutationId': mutationId,
    'unitId': null,
    'category': 'topic_request',
    'summary': 'درخواست تمرین بیشتر',
    'shareWithContentTeam': true
  };

  test(
      'explicit feedback survives reopening and retries the same consented summary',
      () async {
    var offline = true;
    final sent = <Map<String, dynamic>>[];
    final api = HttpIdentityApi(
        baseUrl: 'https://feedback.example.test/api',
        client: MockClient((request) async {
          expect(request.url.path, '/api/v1/education/feedback');
          if (offline) throw http.ClientException('synthetic offline');
          sent.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response(
              jsonEncode({
                'feedback': {
                  'id': '91111111-1111-4111-8111-111111111111',
                  'mutationId': mutationId,
                  'unitId': null,
                  'category': 'topic_request',
                  'summary': 'درخواست تمرین بیشتر',
                  'shareWithContentTeam': true,
                  'withdrawnAt': null,
                  'status': 'received',
                  'version': 1,
                  'updatedAt': '2026-10-09T10:00:00Z',
                  'createdAt': '2026-10-09T10:00:00Z'
                },
                'acknowledgement': {
                  'mutationId': mutationId,
                  'feedbackId': '91111111-1111-4111-8111-111111111111',
                  'status': 'already_applied'
                }
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'});
        }))
      ..accessToken = 'synthetic-token'
      ..currentUserId = 'synthetic-owner';
    final scope = api.cacheNamespace!;
    expect((await LearningFeedbackSync(api).submit(body))['queued'], true);
    final saved = await OfflineStore.forNamespace(scope).readQueue();
    expect(saved.single['payload'], body);
    offline = false;
    await LearningFeedbackSync(api, store: OfflineStore.forNamespace(scope))
        .flush();
    await LearningFeedbackSync(api).flush();
    expect(sent, [body]);
    expect(await OfflineStore.forNamespace(scope).readQueue(), isEmpty);
    expect(await OfflineStore.forNamespace(scope).readPlanner(), isEmpty);
    expect(await OfflineStore.forNamespace(scope).readLastAck(), isNotNull);
    api.close();
  });

  test('wrong feedback acknowledgement cannot remove an unsent summary',
      () async {
    final api = HttpIdentityApi(
        baseUrl: 'https://feedback.example.test/api',
        client: MockClient((request) async => http.Response(
            jsonEncode({
              'feedback': {
                'id': '91111111-1111-4111-8111-111111111111',
                'mutationId': mutationId,
                'unitId': null,
                'category': 'topic_request',
                'summary': 'درخواست تمرین بیشتر',
                'shareWithContentTeam': true,
                'withdrawnAt': null,
                'status': 'received',
                'version': 1,
                'updatedAt': '2026-10-09T10:00:00Z',
                'createdAt': '2026-10-09T10:00:00Z'
              },
              'acknowledgement': {
                'mutationId': mutationId,
                'feedbackId': 'different-receipt',
                'status': 'accepted'
              }
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'})))
      ..accessToken = 'synthetic-token'
      ..currentUserId = 'synthetic-owner';
    await expectLater(
        LearningFeedbackSync(api).submit(body), throwsA(isA<ApiException>()));
    expect(
        (await OfflineStore.forApi(api).readQueue()).single['payload'], body);
    api.close();
  });

  testWidgets('a delayed history response cannot restore a withdrawn summary',
      (tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final delayed = Completer<http.Response>();
    var reads = 0, withdrawn = false;
    final row = <String, dynamic>{
      'id': '91111111-1111-4111-8111-111111111111',
      'mutationId': mutationId,
      'unitId': null,
      'category': 'topic_request',
      'summary': body['summary'],
      'shareWithContentTeam': true,
      'withdrawnAt': null,
      'status': 'received',
      'version': 1,
      'updatedAt': '2026-10-09T10:00:00Z',
      'createdAt': '2026-10-09T10:00:00Z'
    };
    http.Response response(Object value, [int status = 200]) =>
        http.Response(jsonEncode(value), status,
            headers: {'content-type': 'application/json; charset=utf-8'});
    final api = HttpIdentityApi(
        baseUrl: 'https://feedback.example.test/api',
        client: MockClient((request) async {
          if (request.method == 'GET') {
            if (++reads == 1) return delayed.future;
            return response({
              'feedback': withdrawn ? [] : [row]
            });
          }
          if (request.method == 'DELETE') {
            withdrawn = true;
            return http.Response('', 204);
          }
          final sent = jsonDecode(request.body) as Map;
          row['mutationId'] = sent['mutationId'];
          return response({
            'feedback': row,
            'acknowledgement': {
              'mutationId': sent['mutationId'],
              'feedbackId': row['id'],
              'status': 'accepted'
            }
          }, 201);
        }))
      ..accessToken = 'synthetic-token'
      ..currentUserId = 'synthetic-owner';
    await tester.pumpWidget(MaterialApp(home: LearningFeedbackPage(api: api)));
    await tester.pump();
    await tester.enterText(find.byType(TextField), body['summary'] as String);
    await tester.tap(find.byType(Checkbox));
    await tester.tap(find.text('ارسال بازخورد'));
    await tester.pumpAndSettle();
    expect(find.text(body['summary'] as String), findsOneWidget);
    await tester.tap(find.text('پس‌گرفتن رضایت'));
    await tester.pumpAndSettle();
    expect(withdrawn, true);
    delayed.complete(response({
      'feedback': [row]
    }));
    await tester.pumpAndSettle();
    expect(find.text(body['summary'] as String), findsNothing);
    await tester.pumpWidget(const SizedBox());
    api.close();
  });
}
