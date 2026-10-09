import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifemate/api.dart';
import 'package:lifemate/offline_store.dart';
import 'package:lifemate/plan_sync.dart';
import 'package:lifemate/runtime_config.dart';
import 'package:lifemate/runtime_controller.dart';
import 'package:lifemate/session_store.dart';
import 'package:lifemate/main.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

class _SessionStore implements SessionStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String next) async => value = next;
  @override
  Future<void> clear() async => value = null;
}

class _ConfigStore extends RuntimeConfigStore {
  _ConfigStore(this.value);
  RuntimeConfig value;
  @override
  Future<RuntimeConfig> load() async => value;
  @override
  Future<void> saveAndroid(RuntimeConfig next) async => value = next;
}

http.Response _tokens(String user) => http.Response(
    jsonEncode({
      'accessToken': 'synthetic.${base64Url.encode(utf8.encode(jsonEncode({
            'sub': user
          })))}.synthetic',
      'refreshToken': 'synthetic-refresh-$user'
    }),
    200);

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
      if (call.method == 'beginWrite') return pending = 'synthetic-write';
      if (call.method == 'completeWrite' && call.arguments == pending) {
        pending = null;
        return true;
      }
      throw PlatformException(code: 'local_storage_restart_required');
    });
  });

  for (final status in [401, 403]) {
    test(
        'forced refresh $status seals rather than erases the pending namespace',
        () async {
      const endpoint = 'https://family.example.test/api';
      const user = 'synthetic-owner';
      const scope = '$endpoint|$user';
      final credentials = _SessionStore()
        ..value = jsonEncode({
          'endpoint': endpoint,
          'refreshToken': 'synthetic-lost-rotation',
          'userId': user
        });
      final store = OfflineStore.forNamespace(scope);
      const mutation = {
        'id': '11111111-1111-4111-8111-111111111111',
        'entityId': '22222222-2222-4222-8222-222222222222',
        'entityType': 'plan_item',
        'operation': 'create',
        'expectedVersion': 0,
        'clientUpdatedAt': '2026-10-09T01:00:00Z',
        'payload': {'kind': 'assignment', 'title': 'synthetic private work'}
      };
      await store.enqueue(mutation);
      final before = await store.readQueue();
      final sent = <Map<String, dynamic>>[];
      var authenticatingUser = user;
      final api = HttpIdentityApi(
          baseUrl: endpoint,
          sessionStore: credentials,
          onScopeDiscarded: OfflineStore.clearNamespace,
          onScopeQuarantined: OfflineStore.invalidateNamespace,
          client: MockClient((request) async {
            if (request.url.path.endsWith('/auth/refresh')) {
              return http.Response('{"error":"invalid_refresh_token"}', status);
            }
            if (request.url.path.endsWith('/auth/login')) {
              return _tokens(authenticatingUser);
            }
            if (request.url.path.endsWith('/sync/mutations')) {
              final changes =
                  (jsonDecode(request.body)['mutations'] as List).cast<Map>();
              sent.addAll(changes.map(Map<String, dynamic>.from));
              return http.Response(
                  jsonEncode({
                    'results': changes
                        .map((change) => {
                              'id': change['id'],
                              'status': 'accepted',
                              'acceptedAt': '2026-10-09T01:01:00Z',
                              'item': {
                                'id': change['entityId'],
                                'version': 1,
                                'kind': 'assignment',
                                'title': 'synthetic private work'
                              }
                            })
                        .toList()
                  }),
                  200);
            }
            throw StateError('Unexpected synthetic request');
          }));
      addTearDown(api.close);
      expect(await api.restoreSession(), false);
      expect(credentials.value, isNull);
      expect(api.accessToken, isNull);
      expect(api.cacheNamespace, isNull);
      final sealed = OfflineStore.forNamespace(scope);
      expect(await sealed.readQueue(), before,
          reason: 'Forced expiry must preserve every original queued payload');
      await expectLater(
          store.readQueue(),
          throwsA(isA<ApiException>()
              .having((e) => e.code, 'code', 'cache_scope_closed')));
      expect(() => OfflineStore.forApi(api), throwsA(isA<ApiException>()));

      authenticatingUser = 'synthetic-other-account';
      await api.login('other@example.test', 'synthetic-password');
      expect(await OfflineStore.forApi(api).readQueue(), isEmpty);
      await PlanSync(api).flush();
      expect(sent, isEmpty);
      expect(await sealed.readQueue(), before);
      await api.logout(revoke: false);

      authenticatingUser = user;
      await api.login('owner@example.test', 'synthetic-password');
      expect(await OfflineStore.forApi(api).readQueue(), before);
      await PlanSync(api).flush();
      await PlanSync(api).flush();
      expect(sent, hasLength(1));
      expect(sent.single['id'], mutation['id']);
      expect(sent.single['entityId'], mutation['entityId']);
      expect(sent.single['payload'], mutation['payload']);
      expect(await OfflineStore.forApi(api).pendingCount(), 0);
    });
  }

  test('deliberate sign-out and endpoint changes still discard active work',
      () async {
    for (final switchServer in [false, true]) {
      final credentials = _SessionStore();
      final controller = RuntimeController(
          configStore: _ConfigStore(
              RuntimeConfig(apiBaseUrl: 'https://family.example.test/api')),
          sessionStore: credentials,
          onScopeDiscarded: OfflineStore.clearNamespace,
          onScopeQuarantined: OfflineStore.invalidateNamespace,
          apiFactory: (config) => HttpIdentityApi(
              baseUrl: config.apiBaseUrl,
              sessionStore: credentials,
              client: MockClient((request) async =>
                  request.url.path.endsWith('/auth/logout')
                      ? http.Response('', 204)
                      : _tokens('synthetic-owner'))));
      await controller.initialize();
      await controller.api!.login('owner@example.test', 'synthetic-password');
      final scope = controller.cacheNamespace!;
      final previous = OfflineStore.forApi(controller.api!);
      await previous.enqueue({
        'id': '11111111-1111-4111-8111-111111111111',
        'entityId': '22222222-2222-4222-8222-222222222222',
        'payload': {'title': 'synthetic private work'}
      });
      if (switchServer) {
        await controller.updateEndpoints(
            RuntimeConfig(apiBaseUrl: 'https://new.example.test/api'));
      } else {
        await controller.signOut();
      }
      expect(credentials.value, isNull);
      expect(controller.cacheNamespace, isNull);
      expect(await OfflineStore.forNamespace(scope).pendingCount(), 0);
      await expectLater(previous.readQueue(), throwsA(isA<ApiException>()));
      controller.dispose();
    }
  });

  testWidgets('forced expiry returns to login with only a retained-work notice',
      (tester) async {
    const endpoint = 'https://family.example.test/api';
    const scope = '$endpoint|synthetic-owner';
    final credentials = _SessionStore()
      ..value = jsonEncode({
        'endpoint': endpoint,
        'refreshToken': 'synthetic-revoked',
        'userId': 'synthetic-owner'
      });
    await OfflineStore.forNamespace(scope).enqueue({
      'id': '11111111-1111-4111-8111-111111111111',
      'entityId': '22222222-2222-4222-8222-222222222222',
      'payload': {'title': 'DO NOT DISPLAY SYNTHETIC PRIVATE TITLE'}
    });
    final controller = RuntimeController(
        configStore: _ConfigStore(RuntimeConfig(apiBaseUrl: endpoint)),
        sessionStore: credentials,
        onScopeDiscarded: OfflineStore.clearNamespace,
        onScopeQuarantined: OfflineStore.invalidateNamespace,
        apiFactory: (config) => HttpIdentityApi(
            baseUrl: config.apiBaseUrl,
            sessionStore: credentials,
            client: MockClient((_) async =>
                http.Response('{"error":"invalid_refresh_token"}', 401))));
    await tester.runAsync(controller.initialize);
    await tester.pumpWidget(LifeMateApp(runtime: controller));
    await tester.pumpAndSettle();
    expect(find.textContaining('تغییرهای ارسال‌نشده این دستگاه حذف نشده‌اند'),
        findsOneWidget);
    expect(find.text('DO NOT DISPLAY SYNTHETIC PRIVATE TITLE'), findsNothing);
    expect(find.byType(HomeShell), findsNothing);
    expect(controller.api!.accessToken, isNull);
    expect(await OfflineStore.forNamespace(scope).pendingCount(), 1);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}
