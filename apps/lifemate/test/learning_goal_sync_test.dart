import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifemate/api.dart';
import 'package:lifemate/learning_goal_sync.dart';
import 'package:lifemate/offline_store.dart';
import 'package:lifemate/session_store.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

const userId = '10000000-0000-4000-8000-000000000001';
const otherUserId = '10000000-0000-4000-8000-000000000002';
const goalId = '20000000-0000-4000-8000-000000000001';
const at = '2026-10-11T12:00:00Z';

class MemorySession implements SessionStore {
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String value) async {}
  @override
  Future<void> clear() async {}
}

http.Response response(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json; charset=utf-8'});

Map<String, dynamic> goal(
        {String id = goalId,
        int version = 1,
        String title = 'هدف خصوصی آزمایشی',
        String status = 'active',
        String owner = userId}) =>
    {
      'id': id,
      'owner_user_id': owner,
      'subject_id': null,
      'title': title,
      'target': null,
      'status': status,
      'version': version,
      'created_at': at,
      'updated_at': at,
      'archived_at': status == 'archived' ? at : null,
    };

class GoalFixture {
  GoalFixture(
      {String endpoint = 'https://goals.test/api', String user = userId}) {
    api = HttpIdentityApi(
        baseUrl: endpoint,
        client: MockClient(handle),
        sessionStore: MemorySession())
      ..accessToken = 'synthetic-token'
      ..currentUserId = user;
    store = OfflineStore.forNamespace(api.cacheNamespace!,
        session: OfflineSession());
    sync = LearningGoalSync(api, store: store);
  }
  late HttpIdentityApi api;
  late OfflineStore store;
  late LearningGoalSync sync;
  final goals = <String, Map<String, dynamic>>{};
  final receipts = <String, Map<String, dynamic>>{};
  final requests = <http.Request>[];
  bool offline = false, commitThenDisconnect = false;
  int? errorCode;
  Completer<void>? delay;
  Map<String, dynamic> Function(Map<String, dynamic>)? alterResponse;
  final retainedCheckins = <Map<String, dynamic>>[
    {'goalId': goalId, 'note': 'private synthetic history'}
  ];

  Future<http.Response> handle(http.Request request) async {
    requests.add(request);
    if (delay != null) await delay!.future;
    if (offline) throw http.ClientException('synthetic offline');
    if (errorCode != null) {
      return response({'error': 'synthetic_denial'}, errorCode!);
    }
    if (request.method == 'GET') {
      if (request.url.path.endsWith('/goals')) {
        return response({
          'items':
              goals.values.where((g) => g['status'] != 'archived').toList(),
          'fetchedAt': at
        });
      }
      final row = goals[request.url.path.split('/').last];
      return response(
          row ?? {'error': 'goal_not_found'}, row == null ? 404 : 200);
    }
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    final id = request.method == 'POST'
        ? body['id'] as String
        : request.url.path.split('/').last;
    final operation = request.method == 'POST'
        ? 'create'
        : request.method == 'PATCH'
            ? 'update'
            : 'archive';
    final mutationId = body['mutationId'] as String;
    expect(
        (await store.readQueue()).any((m) =>
            m['id'] == mutationId &&
            m['payload'].toString() == body.toString()),
        isTrue);
    final old = receipts[mutationId];
    if (old == null) {
      if ((goals[id]?['version'] ?? 0) != body['expectedVersion']) {
        return response({'error': 'version_conflict'}, 409);
      }
      goals[id] = {
        ...goal(
            id: id,
            version: (body['expectedVersion'] as int) + 1,
            title: body['title'] as String? ??
                goals[id]?['title'] as String? ??
                '',
            status: operation == 'archive'
                ? 'archived'
                : body['status'] as String? ??
                    goals[id]?['status'] as String? ??
                    'active',
            owner: api.currentUserId!),
        'target':
            body.containsKey('target') ? body['target'] : goals[id]?['target'],
        'subject_id': body.containsKey('subjectId')
            ? body['subjectId']
            : goals[id]?['subject_id'],
      };
      receipts[mutationId] = {
        'mutationId': mutationId,
        'goalId': id,
        'operation': operation,
        'appliedVersion': body['expectedVersion'] + 1,
        'acceptedAt': at,
      };
    }
    if (commitThenDisconnect) {
      commitThenDisconnect = false;
      throw http.ClientException('synthetic receipt lost after commit');
    }
    var result = <String, dynamic>{
      'goal': {...goals[id]!},
      'acknowledgement': {
        ...receipts[mutationId]!,
        'status': old == null ? 'accepted' : 'already_applied'
      }
    };
    if (alterResponse != null) result = alterResponse!(result);
    return response(
        result, request.method == 'POST' && old == null ? 201 : 200);
  }

  LearningGoalSync reopen() => LearningGoalSync(api,
      store: OfflineStore.forNamespace(store.scope, session: OfflineSession()));
}

Matcher code(String value) =>
    throwsA(isA<ApiException>().having((e) => e.code, 'code', value));

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
      if (call.method == 'beginWrite') return token = 'goal-sync-test';
      if (call.method == 'completeWrite' && call.arguments == token) {
        token = null;
        return true;
      }
      throw PlatformException(code: 'local_storage_restart_required');
    });
  });

  test(
      'create, fresh handle read, edit, complete and archive retain history and server versions',
      () async {
    final f = GoalFixture();
    final created =
        await f.sync.create(title: '  هدف ریاضی  ', target: '  حل تمرین  ');
    expect(created['queued'], false);
    final id = created['goal']['id'] as String;
    expect(created['goal']['title'], 'هدف ریاضی');
    f.offline = true;
    final reopened = await f.reopen().read();
    expect(reopened['offline'], true);
    expect((reopened['items'] as List).single['id'], id);
    f.offline = false;
    final edited =
        await f.sync.update(id, 1, {'title': 'تمرین جمع', 'target': null});
    expect(edited['goal']['version'], 2);
    expect(edited['goal']['target'], isNull);
    await f.reopen().update(id, 2, {'status': 'completed'});
    expect((await f.sync.read())['items'].single['status'], 'completed');
    await f.sync.archive(id, 3);
    f.offline = true;
    expect((await f.reopen().read())['items'], isEmpty);
    expect(f.goals[id]?['status'], 'archived');
    expect(f.retainedCheckins, hasLength(1));
    expect(await f.store.readQueue(), isEmpty);
    f.api.close();
  });

  test(
      'offline create survives fresh handle and retries one stable UUID with one server row',
      () async {
    final f = GoalFixture()..offline = true;
    final created = await f.sync.create(title: 'هدف آفلاین');
    expect(created['queued'], true);
    final queued = (await f.store.readQueue()).single;
    final reopened = f.reopen();
    expect((await reopened.read())['items'].single['pending_sync'], true);
    expect((await reopened.read())['fetchedAt'], isNull);
    f.offline = false;
    await reopened.flush();
    await reopened.flush();
    expect(f.goals, hasLength(1));
    expect(f.receipts.keys.single, queued['id']);
    expect(await f.store.readQueue(), isEmpty);
    f.api.close();
  });

  test(
      'lost create acknowledgement replays exact bytes and current archive dominates old receipt',
      () async {
    final f = GoalFixture()..commitThenDisconnect = true;
    expect((await f.sync.create(title: 'هدف آزمایشی'))['queued'], true);
    final saved = (await f.store.readQueue()).single;
    final id = saved['entityId'] as String;
    f.goals[id] = {
      ...f.goals[id]!,
      'status': 'archived',
      'version': 3,
      'archived_at': at
    };
    await f.reopen().flush();
    final writes = f.requests.where((r) => r.method == 'POST').toList();
    expect(writes, hasLength(2));
    expect(writes.first.body, writes.last.body);
    expect(f.receipts, hasLength(1));
    expect(await f.store.readQueue(), isEmpty);
    f.offline = true;
    expect((await f.reopen().read())['items'], isEmpty);
    f.api.close();
  });

  for (final corrupt in [
    'id',
    'mutation',
    'version',
    'operation',
    'title',
    'acceptedAt'
  ]) {
    test('malformed $corrupt receipt cannot erase a goal intent', () async {
      final f = GoalFixture();
      f.alterResponse = (raw) {
        final row = {...raw['goal'] as Map};
        final ack = {...raw['acknowledgement'] as Map};
        if (corrupt == 'id') row['id'] = goalId;
        if (corrupt == 'mutation') ack['mutationId'] = goalId;
        if (corrupt == 'version') ack['appliedVersion'] = 2;
        if (corrupt == 'operation') ack['operation'] = 'archive';
        if (corrupt == 'title') row['title'] = 'متن متفاوت';
        if (corrupt == 'acceptedAt') ack['acceptedAt'] = 'yesterday';
        return {'goal': row, 'acknowledgement': ack};
      };
      await expectLater(f.sync.create(title: 'هدف واقعی'),
          code('invalid_goal_acknowledgement'));
      expect(await f.store.readQueue(), hasLength(1));
      f.api.close();
    });
  }

  test(
      'version conflict stays queued until explicit server recovery, with local intent journalled',
      () async {
    final f = GoalFixture();
    f.goals[goalId] = goal();
    await f.sync.read();
    f.goals[goalId] = goal(version: 2, title: 'نسخه دیگر دستگاه');
    await expectLater(f.sync.update(goalId, 1, {'title': 'نسخه محلی'}),
        code('version_conflict'));
    expect((await f.store.readQueue()).single['queueStatus'], 'conflict');
    await expectLater(f.reopen().flush(), code('goal_version_conflict'));
    await f.reopen().useServer(goalId);
    expect(await f.store.readQueue(), isEmpty);
    expect(jsonEncode(await f.store.readDiscardedChanges()),
        contains('نسخه محلی'));
    f.offline = true;
    expect(
        (await f.reopen().read())['items'].single['title'], 'نسخه دیگر دستگاه');
    f.api.close();
  });

  test('403 clears private goal cache without deleting an offline intent',
      () async {
    final f = GoalFixture();
    f.goals[goalId] = goal();
    await f.sync.read();
    f.offline = true;
    await f.sync.update(goalId, 1, {'title': 'تغییر ارسال‌نشده'});
    f.offline = false;
    f.errorCode = 403;
    await expectLater(f.sync.read(), throwsA(isA<ApiException>()));
    expect(await f.store.readList('learning_goals'), isEmpty);
    expect(await f.store.readList('learning_goals_received'), isEmpty);
    expect(await f.store.readQueue(), hasLength(1));
    f.api.close();
  });

  test(
      'account change while receiving a goal blocks acknowledgement and isolates caches',
      () async {
    final f = GoalFixture()..delay = Completer<void>();
    final pending = f.sync.create(title: 'حساب نخست');
    await Future<void>.delayed(Duration.zero);
    f.api.currentUserId = otherUserId;
    f.delay!.complete();
    await expectLater(pending, throwsA(isA<ApiException>()));
    expect(await OfflineStore.forApi(f.api).readQueue(), isEmpty);
    expect(await f.store.readQueue(), hasLength(1));
    f.api.close();
  });

  for (final invalid in [
    {'expectedVersion': 0, 'title': 'new'},
    {'expectedVersion': -1, 'title': 'new'},
    {'expectedVersion': 1, 'title': 'bad\u0000title'},
    {'expectedVersion': 1, 'unknown': true},
    {'expectedVersion': 1},
  ]) {
    test('invalid update $invalid is rejected before enqueue or HTTP',
        () async {
      final f = GoalFixture();
      final version = invalid['expectedVersion'] as int;
      final changes = {...invalid}..remove('expectedVersion');
      await expectLater(
          f.sync.update(goalId, version, changes), code('invalid_goal_input'));
      expect(await f.store.readQueue(), isEmpty);
      expect(f.requests, isEmpty);
      f.api.close();
    });
  }

  test('foreign-owner cached row is never rendered as private offline data',
      () async {
    final f = GoalFixture()..offline = true;
    await f.store.writeList('learning_goals', [goal(owner: otherUserId)]);
    await expectLater(f.sync.read(), code('invalid_learning_goal'));
    f.api.close();
  });
}
