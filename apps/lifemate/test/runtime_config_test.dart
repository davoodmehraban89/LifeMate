import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifemate/api.dart';
import 'package:lifemate/runtime_config.dart';
import 'package:lifemate/runtime_controller.dart';
import 'package:lifemate/session_store.dart';

class MemorySessionStore implements SessionStore {
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

class MemoryConfigStore extends RuntimeConfigStore {
  MemoryConfigStore(this.value);
  RuntimeConfig value;
  final saved = <RuntimeConfig>[];
  @override
  Future<RuntimeConfig> load() async => value;
  @override
  Future<void> saveAndroid(RuntimeConfig next) async {
    saved.add(next);
    value = next;
  }
}

class DelayedConfigStore extends RuntimeConfigStore {
  final result = Completer<RuntimeConfig>();
  @override
  Future<RuntimeConfig> load() => result.future;
}

class FailingClearSessionStore extends MemorySessionStore {
  @override
  Future<void> clear() async => throw StateError('storage unavailable');
}

String token(String user, String version) =>
    'header.${base64Url.encode(utf8.encode(jsonEncode({
          'sub': user,
          'version': version
        })))}.signature';
http.Response tokens(
        String user, String version, String refresh) =>
    http.Response(
        jsonEncode(
            {'accessToken': token(user, version), 'refreshToken': refresh}),
        200);

void main() {
  test('an insecure web page cannot load configuration or persisted sessions',
      () async {
    var requested = false;
    final store = RuntimeConfigStore(
        web: true,
        webOrigin: Uri.parse('http://family.example.test/'),
        client: MockClient((_) async {
          requested = true;
          return http.Response(
              '{"apiBaseUrl":"https://api.example.test","apiFallbackUrls":[]}',
              200);
        }));
    await expectLater(store.load(), throwsStateError);
    expect(requested, isFalse);
  });
  test(
      'failed cache clear blocks endpoint activation and exposes storage error',
      () async {
    final store = MemorySessionStore();
    final configStore = MemoryConfigStore(
        RuntimeConfig(apiBaseUrl: 'https://old.example.test'));
    final controller = RuntimeController(
        configStore: configStore,
        sessionStore: store,
        onScopeDiscarded: (_) async =>
            throw StateError('cache write uncertain'),
        apiFactory: (config) => HttpIdentityApi(
            baseUrl: config.apiBaseUrl,
            sessionStore: store,
            client: MockClient(
                (_) async => tokens('user-1', '1', 'fixture-refresh'))));
    await controller.initialize();
    await controller.api!.login('fixture@example.test', 'fixture-password');
    await expectLater(
        controller.updateEndpoints(
            RuntimeConfig(apiBaseUrl: 'https://new.example.test')),
        throwsStateError);
    expect(controller.error, isA<StateError>());
    expect(controller.api!.accessToken, isNull);
    expect(controller.config.apiBaseUrl, 'https://old.example.test');
    expect(configStore.saved, isEmpty);
    controller.dispose();
  });
  test('account changes discard the old authenticated cache scope', () async {
    final scopes = <String>[];
    var loginCount = 0;
    final api = HttpIdentityApi(
        baseUrl: 'https://api.example.test',
        sessionStore: MemorySessionStore(),
        onScopeDiscarded: (scope) async => scopes.add(scope),
        client: MockClient((_) async {
          loginCount++;
          return tokens(
              'user-$loginCount', '$loginCount', 'refresh-$loginCount');
        }));
    await api.login('first@example.test', 'fixture-password');
    await api.login('second@example.test', 'fixture-password');
    expect(scopes, ['https://api.example.test|user-1']);
    expect(api.cacheNamespace, 'https://api.example.test|user-2');
  });
  test('logout notifies signed-out UI and clears cache even when storage fails',
      () async {
    final store = FailingClearSessionStore();
    final discarded = <String>[];
    final api = HttpIdentityApi(
        baseUrl: 'https://api.example.test',
        sessionStore: store,
        onScopeDiscarded: (scope) async => discarded.add(scope),
        client:
            MockClient((_) async => tokens('user-1', '1', 'fixture-refresh')));
    await api.login('fixture@example.test', 'fixture-password');
    var notified = false;
    api.onSessionChanged = () {
      notified = true;
      expect(api.accessToken, isNull);
    };
    await expectLater(api.logout(revoke: false), throwsStateError);
    expect(notified, isTrue);
    expect(api.cacheNamespace, isNull);
    expect(discarded, ['https://api.example.test|user-1']);
  });
  test('disposed startup never constructs a new client or notifies listeners',
      () async {
    final store = DelayedConfigStore();
    var constructed = 0;
    final controller = RuntimeController(
        configStore: store,
        sessionStore: MemorySessionStore(),
        apiFactory: (_) {
          constructed++;
          throw StateError('Must not construct after disposal.');
        });
    final loading = controller.initialize();
    controller.dispose();
    store.result
        .complete(RuntimeConfig(apiBaseUrl: 'https://api.example.test'));
    await loading;
    expect(constructed, 0);
    expect(controller.api, isNull);
  });
  test('endpoint changes clear old credentials and scope before using new API',
      () async {
    final store = MemorySessionStore();
    final configStore = MemoryConfigStore(
        RuntimeConfig(apiBaseUrl: 'https://old.example.test'));
    final discarded = <String>[];
    final requestedHosts = <String>[];
    final controller = RuntimeController(
        configStore: configStore,
        sessionStore: store,
        onScopeDiscarded: (scope) async {
          expect(store.value, isNull);
          discarded.add(scope);
        },
        apiFactory: (config) => HttpIdentityApi(
            baseUrl: config.apiBaseUrl,
            sessionStore: store,
            client: MockClient((request) async {
              requestedHosts.add(request.url.host);
              return tokens('user-1', '1', 'old-refresh');
            })));
    await controller.initialize();
    await controller.api!.login('fixture@example.test', 'fixture-password');
    await controller
        .updateEndpoints(RuntimeConfig(apiBaseUrl: 'https://new.example.test'));
    expect(discarded, ['https://old.example.test|user-1']);
    expect(store.value, isNull);
    expect(controller.cacheNamespace, isNull);
    expect(controller.api!.baseUrl, 'https://new.example.test');
    expect(configStore.saved.single.apiBaseUrl, 'https://new.example.test');
    expect(requestedHosts, ['old.example.test']);
    controller.dispose();
  });
  test('HTTP and embedded credentials are rejected before client use', () {
    for (final address in [
      'http://api.example.test',
      'https://user:pass@api.example.test',
      'https://api.example.test?q=1',
      'https://api.example.test#token'
    ]) {
      expect(() => HttpIdentityApi(baseUrl: address), throwsArgumentError);
    }
    expect(() => HttpIdentityApi(), throwsArgumentError);
  });
  test('HTTPS same-origin config resolves and fallback URLs are deduplicated',
      () {
    final config = RuntimeConfig.fromJson({
      'apiBaseUrl': '/api',
      'apiFallbackUrls': [
        'https://backup.example.test/',
        'https://backup.example.test'
      ]
    }, webOrigin: Uri.parse('https://family.example.test/'));
    expect(config.endpoints,
        ['https://family.example.test/api', 'https://backup.example.test']);
    expect(
        () => RuntimeConfig(
            apiBaseUrl: '/api',
            webOrigin: Uri.parse('http://family.example.test/')),
        throwsArgumentError);
    expect(RuntimeConfig().isConfigured, isFalse);
  });
  test('runtime web config is fetched fresh from hosting origin', () async {
    final store = RuntimeConfigStore(
        web: true,
        webOrigin: Uri.parse(
            'https://family.example.test/reset-password?token=private'),
        client: MockClient((request) async {
          expect(request.url.path, '/config.json');
          expect(request.url.queryParameters.containsKey('fresh'), isTrue);
          expect(request.headers['Cache-Control'], 'no-store');
          expect(request.url.query, isNot(contains('private')));
          return http.Response(
              '{"apiBaseUrl":"/api","apiFallbackUrls":[]}', 200);
        }));
    expect((await store.load()).apiBaseUrl, 'https://family.example.test/api');
  });
  test('refresh token survives API recreation and rotates before logout',
      () async {
    final store = MemorySessionStore();
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      if (request.url.path.endsWith('/login')) {
        return tokens('user-1', '1', 'opaque-old');
      }
      if (request.url.path.endsWith('/refresh')) {
        expect(jsonDecode(request.body)['refreshToken'], 'opaque-old');
        return tokens('user-1', '2', 'opaque-new');
      }
      if (request.url.path.endsWith('/logout')) return http.Response('', 204);
      return http.Response('{"user_id":"user-1"}', 200);
    });
    final first = HttpIdentityApi(
        baseUrl: 'https://api.example.test/api',
        client: client,
        sessionStore: store);
    await first.login('name@example.test', 'fixture-password');
    expect(store.value, isNot(contains(token('user-1', '1'))));
    expect(first.cacheNamespace, 'https://api.example.test/api|user-1');
    final reopened = HttpIdentityApi(
        baseUrl: first.baseUrl, client: client, sessionStore: store);
    expect(reopened.cacheNamespace, isNull);
    expect(await reopened.restoreSession(), isTrue);
    expect(reopened.accessToken, token('user-1', '2'));
    await reopened.getProfile();
    expect(requests.last.headers['authorization'],
        'Bearer ${token('user-1', '2')}');
    final cleared = <String>[];
    reopened.onScopeDiscarded = (scope) async {
      cleared.add(scope);
    };
    await reopened.logout();
    expect(store.value, isNull);
    expect(reopened.cacheNamespace, isNull);
    expect(cleared, ['https://api.example.test/api|user-1']);
  });
  test('a stored session is never sent to another configured server', () async {
    final store = MemorySessionStore()
      ..value = jsonEncode({
        'endpoint': 'https://old.example.test',
        'refreshToken': 'old-refresh',
        'userId': 'user-1'
      });
    var sent = 0;
    final discarded = <String>[];
    final api = HttpIdentityApi(
        baseUrl: 'https://new.example.test',
        sessionStore: store,
        onScopeDiscarded: (scope) async {
          discarded.add(scope);
        },
        client: MockClient((_) async {
          sent++;
          return http.Response('{}', 200);
        }));
    expect(await api.restoreSession(), isFalse);
    expect(sent, 0);
    expect(store.value, isNull);
    expect(discarded, ['https://old.example.test|user-1']);
  });
  test(
      'revoked refresh token clears the old cache scope without anonymous access',
      () async {
    final store = MemorySessionStore()
      ..value = jsonEncode({
        'endpoint': 'https://api.example.test',
        'refreshToken': 'revoked',
        'userId': 'user-1'
      });
    final discarded = <String>[];
    final api = HttpIdentityApi(
        baseUrl: 'https://api.example.test',
        sessionStore: store,
        onScopeDiscarded: (scope) async {
          discarded.add(scope);
        },
        client: MockClient((_) async =>
            http.Response('{"error":"invalid_refresh_token"}', 401)));
    expect(await api.restoreSession(), isFalse);
    expect(store.value, isNull);
    expect(api.cacheNamespace, isNull);
    expect(discarded, ['https://api.example.test|user-1']);
  });
  test('late refresh after logout cannot revive or overwrite a new session',
      () async {
    final store = MemorySessionStore()
      ..value = jsonEncode({
        'endpoint': 'https://old.example.test',
        'refreshToken': 'old-refresh',
        'userId': 'old-user'
      });
    final entered = Completer<void>();
    final response = Completer<http.Response>();
    final old = HttpIdentityApi(
        baseUrl: 'https://old.example.test',
        sessionStore: store,
        client: MockClient((_) {
          entered.complete();
          return response.future;
        }));
    final restoring = old.restoreSession();
    await entered.future;
    await old.logout(revoke: false);
    final next = HttpIdentityApi(
        baseUrl: 'https://new.example.test',
        sessionStore: store,
        client:
            MockClient((_) async => tokens('new-user', '1', 'new-refresh')));
    await next.login('next@example.test', 'fixture-password');
    response.complete(tokens('old-user', '2', 'late-old-refresh'));
    expect(await restoring, isFalse);
    expect(old.accessToken, isNull);
    expect(jsonDecode(store.value!)['endpoint'], 'https://new.example.test');
    expect(jsonDecode(store.value!)['refreshToken'], 'new-refresh');
  });
  test('transport failure does not retry a mutation on a fallback server',
      () async {
    var requests = 0;
    final config = RuntimeConfig(
        apiBaseUrl: 'https://primary.example.test',
        apiFallbackUrls: ['https://backup.example.test']);
    final api = HttpIdentityApi(
        baseUrl: config.apiBaseUrl,
        sessionStore: MemorySessionStore(),
        client: MockClient((request) async {
          requests++;
          expect(request.url.host, 'primary.example.test');
          if (request.url.path.endsWith('/login')) {
            return tokens('user-1', '1', 'fixture-refresh');
          }
          throw http.ClientException('offline');
        }));
    await api.login('name@example.test', 'fixture-password');
    await expectLater(
        api.createPlanItem({'kind': 'task', 'title': 'Durable queued task'}),
        throwsA(isA<ApiException>()
            .having((error) => error.code, 'code', 'network_unavailable')));
    expect(requests, 2);
  });
}
