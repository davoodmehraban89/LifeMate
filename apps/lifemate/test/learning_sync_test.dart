import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifemate/api.dart';
import 'package:lifemate/learning_sync.dart';
import 'package:lifemate/offline_store.dart';
import 'package:lifemate/session_store.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

const _unit = '00000000-0000-4000-8000-000000000101';
const _otherUnit = '00000000-0000-4000-8000-000000000102';
const _course = '00000000-0000-4000-8000-000000000200';
const _time = '2026-10-09T10:00:00Z';

class _Session implements SessionStore {
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String value) async {}
  @override
  Future<void> clear() async {}
}

class _Fixture {
  _Fixture({String endpoint = 'https://api.test', String? user}) {
    api = HttpIdentityApi(
      baseUrl: endpoint,
      client: MockClient(handle),
      sessionStore: _Session(),
    )
      ..accessToken = 'synthetic-test-token'
      ..currentUserId = user ?? 'learner-${next++}';
    store = OfflineStore.forNamespace(api.cacheNamespace!, session: session);
    sync = LearningSync(api, store: store);
  }
  static var next = 0;
  final session = OfflineSession();
  late HttpIdentityApi api;
  late OfflineStore store;
  late LearningSync sync;
  bool offline = false;
  int? errorStatus;
  bool appliedThenDisconnect = false;
  Future<void>? delay;
  final requests = <http.Request>[];
  final applied = <String, Map<String, dynamic>>{};
  final progress = <String, Map<String, dynamic>>{};
  Map<String, dynamic> Function(Map<String, dynamic>)? alterAck;
  Map<String, dynamic> Function(Map<String, dynamic>)? alterCourse;

  Map<String, dynamic> get course => {
        'id': _course,
        'titleFa': 'ریاضی آزمایشی',
        'units': [
          for (final id in [_unit, _otherUnit])
            {
              'id': id,
              'titleFa': 'درس آزمایشی',
              'progress': progress[id] ??
                  {
                    'unitId': id,
                    'status': 'not_started',
                    'source': 'self_reported',
                    'version': 0,
                    'updatedAt': null
                  }
            }
        ]
      };

  Future<http.Response> handle(http.Request request) async {
    requests.add(request);
    expect(request.headers['authorization'], 'Bearer synthetic-test-token');
    if (delay != null) await delay;
    if (offline) throw http.ClientException('offline substitute');
    if (errorStatus != null) {
      return http.Response(
          jsonEncode({'error': 'synthetic_failure'}), errorStatus!);
    }
    if (request.method == 'GET' && request.url.path.contains('/courses/')) {
      final value = alterCourse == null ? course : alterCourse!(course);
      return http.Response(jsonEncode({'course': value}), 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    }
    if (request.method == 'GET' &&
        request.url.path == '/v1/me/learning-progress') {
      return http.Response(
          jsonEncode({'progress': progress.values.toList()}), 200);
    }
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    final id = request.url.path.split('/').last;
    final mutationId = body['mutationId'] as String;
    if (!applied.containsKey(mutationId)) {
      final row = progress[id];
      if ((row?['version'] ?? 0) != body['expectedVersion']) {
        return http.Response(jsonEncode({'error': 'version_conflict'}), 409);
      }
      final ack = <String, dynamic>{
        'mutationId': mutationId,
        'unitId': id,
        'status': body['status'],
        'source': body['source'],
        'version': (body['expectedVersion'] as int) + 1,
        'updatedAt': _time,
        'acceptedAt': _time
      };
      applied[mutationId] = ack;
      progress[id] = {...ack}..remove('mutationId');
    }
    if (appliedThenDisconnect) {
      appliedThenDisconnect = false;
      throw http.ClientException('acknowledgement lost after synthetic commit');
    }
    var ack = {...applied[mutationId]!};
    if (alterAck != null) ack = alterAck!(ack);
    return http.Response(jsonEncode(ack), 200);
  }

  LearningSync reopen() => LearningSync(api,
      store: OfflineStore.forNamespace(store.scope, session: session));
}

Matcher _code(String code) =>
    throwsA(isA<ApiException>().having((e) => e.code, 'code', code));

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
      if (call.method == 'beginWrite') return pending = 'synthetic-owned-write';
      if (call.method == 'completeWrite' && call.arguments == pending) {
        pending = null;
        return true;
      }
      throw PlatformException(code: 'local_storage_restart_required');
    });
  });

  test('reading a lesson never completes it and cache survives a fresh handle',
      () async {
    final f = _Fixture();
    final course = await f.sync.readCourse(_course);
    expect(course['offline'], false);
    expect(
        (course['units'] as List).first['progress']['status'], 'not_started');
    expect(f.requests.where((r) => r.method == 'PUT'), isEmpty);
    f.offline = true;
    final cached = await f.reopen().readCourse(_course);
    expect(cached['offline'], true);
    expect(cached['titleFa'], 'ریاضی آزمایشی');
    expect(
        (cached['units'] as List).first['progress']['status'], 'not_started');
  });

  test('enqueue precedes PUT and acknowledgement updates only progress cache',
      () async {
    final f = _Fixture();
    final original = f.api;
    f.api = HttpIdentityApi(
        baseUrl: original.baseUrl,
        sessionStore: _Session(),
        client: MockClient((request) async {
          expect(await f.store.readQueue(), hasLength(1));
          return f.handle(request);
        }))
      ..accessToken = 'synthetic-test-token'
      ..currentUserId = original.currentUserId;
    final result = await LearningSync(f.api, store: f.store)
        .setProgress(_unit, 'in_progress', 0);
    expect(result['queued'], false);
    expect(result['progress']['version'], 1);
    expect(await f.store.readQueue(), isEmpty);
    expect(await f.store.readPlanner(), isEmpty);
    expect(await f.store.readToday(), isEmpty);
    expect(
        (await f.store.readList('learning_progress')).single['unitId'], _unit);
  });

  test('offline report survives reopening and stable retry has no duplicate',
      () async {
    final f = _Fixture()..offline = true;
    await f.sync.readCourse(_course).catchError((_) => <String, dynamic>{});
    final result = await f.sync.setProgress(_unit, 'completed', 0);
    expect(result['queued'], true);
    expect(result['progress']['pending_sync'], true);
    expect(result['progress']['version'], 0);
    final queue = await f.store.readQueue();
    final payload = Map<String, dynamic>.from(queue.single['payload'] as Map);
    f.offline = false;
    await f.reopen().flush();
    await f.reopen().flush();
    expect(f.applied, hasLength(1));
    expect(f.applied.keys.single, payload['mutationId']);
    final sent = f.requests.where((r) => r.method == 'PUT').last;
    expect(jsonDecode(sent.body), payload);
    expect(await f.store.readQueue(), isEmpty);
  });

  test('lost acknowledgement retries exact body after synthetic server commit',
      () async {
    final f = _Fixture()..appliedThenDisconnect = true;
    final queued = await f.sync.setProgress(_unit, 'completed', 0);
    expect(queued['queued'], true);
    final firstBody = f.requests.single.body;
    await f.reopen().flush();
    expect(f.requests.last.body, firstBody);
    expect(f.applied, hasLength(1));
    expect((await f.store.readList('learning_progress')).single['version'], 1);
  });

  test('one unresolved mutation per unit, including concurrent handles',
      () async {
    final f = _Fixture()..offline = true;
    final first = f.sync.setProgress(_unit, 'in_progress', 0);
    final second = f.reopen().setProgress(_unit, 'completed', 0);
    expect((await first)['queued'], true);
    await expectLater(second, _code('sync_pending'));
    expect(await f.sync.pendingFor(_unit), hasLength(1));
    await f.sync.setProgress(_otherUnit, 'in_progress', 0);
    expect(await f.store.readQueue(), hasLength(2));
  });

  test('malformed acknowledgements retain exact durable mutation', () async {
    final mutations = <Map<String, dynamic> Function(Map<String, dynamic>)>[
      (a) => a..['mutationId'] = 'wrong',
      (a) => a..['unitId'] = _otherUnit,
      (a) => a..['status'] = 'completed',
      (a) => a..['source'] = 'timer',
      (a) => a..['version'] = 0,
      (a) => a..['version'] = 2,
      (a) => a..['version'] = '1',
      (a) => a..['acceptedAt'] = 'not-a-date',
      (a) => a..['updatedAt'] = null,
    ];
    for (final corrupt in mutations) {
      final f = _Fixture()..alterAck = corrupt;
      await expectLater(f.sync.setProgress(_unit, 'in_progress', 0),
          _code('invalid_sync_acknowledgement'));
      expect(await f.store.readQueue(), hasLength(1));
      expect(await f.store.readList('learning_progress'), isEmpty);
      final body = (await f.store.readQueue()).single['payload'];
      f.alterAck = null;
      await f.reopen().flush();
      expect(jsonDecode(f.requests.last.body), body);
    }
  });

  test('refresh overlays pending report without calling it acknowledged',
      () async {
    final f = _Fixture();
    await f.sync.readCourse(_course);
    f.offline = true;
    await f.sync.setProgress(_unit, 'completed', 0);
    f.offline = false;
    final live = await f.reopen().readCourse(_course);
    final row = (live['units'] as List).first['progress'];
    expect(row['status'], 'completed');
    expect(row['pending_sync'], true);
    expect(row['acknowledged'], false);
    expect(row['version'], 0);
    expect(await f.store.readQueue(), hasLength(1));
  });

  test('409 retains conflict; explicit server choice journals before removing',
      () async {
    final f = _Fixture()..offline = true;
    await f.sync.setProgress(_unit, 'completed', 0);
    final original = (await f.store.readQueue()).single;
    f.progress[_unit] = {
      'unitId': _unit,
      'status': 'in_progress',
      'source': 'self_reported',
      'version': 2,
      'updatedAt': _time,
    };
    f.offline = false;
    await expectLater(f.sync.flush(), _code('version_conflict'));
    expect((await f.store.readQueue()).single['queueStatus'], 'conflict');
    await expectLater(f.sync.flush(), _code('sync_conflict'));
    await f.sync.resolveUsingServer(_unit);
    expect(await f.store.readQueue(), isEmpty);
    final journal = await f.store.readDiscardedChanges();
    expect(journal.single['payload'], original['payload']);
    expect(journal.single['discardedAt'], isNotNull);
    expect((await f.store.readList('learning_progress')).single['status'],
        'in_progress');
    expect(await f.store.readPlanner(), isEmpty);
  });

  test('permission/server failures are not offline success or stale live reads',
      () async {
    for (final status in [403, 422, 500, 503]) {
      final f = _Fixture();
      await f.sync.readCourse(_course);
      f.errorStatus = status;
      await expectLater(f.sync.readCourse(_course), _code('synthetic_failure'));
      await expectLater(f.sync.setProgress(_unit, 'completed', 0),
          _code('synthetic_failure'));
      expect(await f.store.readQueue(), hasLength(1));
    }
  });

  test('account and API namespace never share metadata or unsent progress',
      () async {
    final child = _Fixture(user: 'child');
    await child.sync.readCourse(_course);
    child.offline = true;
    await child.sync.setProgress(_unit, 'completed', 0);
    final parent = _Fixture(user: 'parent')..offline = true;
    final other = _Fixture(user: 'child', endpoint: 'https://other.test')
      ..offline = true;
    for (final outsider in [parent, other]) {
      expect(await outsider.sync.pendingFor(_unit), isEmpty);
      await expectLater(
          outsider.sync.readCourse(_course), _code('network_unavailable'));
      expect(await outsider.store.readList('learning_progress'), isEmpty);
    }
  });

  test(
      'closed scope cannot acknowledge late response or erase quarantined work',
      () async {
    final f = _Fixture()..offline = true;
    await f.sync.setProgress(_unit, 'completed', 0);
    final original = (await f.store.readQueue()).single['payload'];
    f.offline = false;
    final delayed = Completer<void>();
    f.delay = delayed.future;
    final request = f.sync.flush();
    await Future<void>.delayed(Duration.zero);
    await OfflineStore.invalidateNamespace(f.store.scope);
    delayed.complete();
    await expectLater(request, _code('cache_scope_closed'));
    final reopened =
        OfflineStore.forNamespace(f.store.scope, session: f.session);
    expect((await reopened.readQueue()).single['payload'], original);
    expect(await reopened.readList('learning_progress'), isEmpty);
  });

  test('API identity change rejects old store without deleting its queue',
      () async {
    final f = _Fixture()..offline = true;
    await f.sync.setProgress(_unit, 'in_progress', 0);
    f.api.currentUserId = 'different-user';
    await expectLater(f.sync.flush(), _code('cache_scope_closed'));
    expect(await f.store.readQueue(), hasLength(1));
  });

  test('identity changed during offline response cannot return old progress',
      () async {
    final f = _Fixture();
    final delayed = Completer<void>();
    f.delay = delayed.future;
    f.offline = true;
    final request = f.sync.setProgress(_unit, 'completed', 0);
    while (f.requests.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    f.api.currentUserId = 'replacement-user';
    delayed.complete();
    await expectLater(request, _code('cache_scope_closed'));
    expect(await f.store.readQueue(), hasLength(1));
  });

  test('malformed course response cannot replace last valid cached metadata',
      () async {
    final f = _Fixture();
    await f.sync.readCourse(_course);
    f.alterCourse = (value) => value
      ..['units'] = [
        {'id': 'wrong'}
      ];
    await expectLater(
        f.sync.readCourse(_course), _code('invalid_learning_course'));
    f.offline = true;
    final cached = await f.sync.readCourse(_course);
    expect(cached['offline'], true);
    expect((cached['units'] as List).first['id'], _unit);
  });

  test('missing server progress never silently discards unresolved report',
      () async {
    final f = _Fixture()..offline = true;
    await f.sync.setProgress(_unit, 'completed', 0);
    final payload = (await f.store.readQueue()).single['payload'];
    f.offline = false;
    await expectLater(
        f.sync.resolveUsingServer(_unit), _code('invalid_learning_progress'));
    expect((await f.store.readQueue()).single['payload'], payload);
    expect(await f.store.readDiscardedChanges(), isEmpty);
  });

  test('server choice does not discard an independent entity with same UUID',
      () async {
    final f = _Fixture()..offline = true;
    await f.sync.setProgress(_unit, 'completed', 0);
    await f.store.enqueue({
      'id': '00000000-0000-4000-8000-000000000300',
      'entityId': _unit,
      'entityType': 'plan_item',
      'operation': 'update',
      'payload': {'title': 'synthetic independent planner change'},
    });
    f.progress[_unit] = {
      'unitId': _unit,
      'status': 'in_progress',
      'source': 'self_reported',
      'version': 1,
      'updatedAt': _time,
    };
    f.offline = false;
    await expectLater(
        f.sync.resolveUsingServer(_unit), _code('sync_entity_collision'));
    expect(await f.store.readQueue(), hasLength(2));
    expect(await f.store.readDiscardedChanges(), isEmpty);
  });
}
