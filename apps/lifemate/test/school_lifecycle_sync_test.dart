import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifemate/api.dart';
import 'package:lifemate/offline_store.dart';
import 'package:lifemate/school_management_ui.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

const owner = '10000000-0000-4000-8000-000000000001';
const secondOwner = '10000000-0000-4000-8000-000000000002';
const stamp = '2026-10-11T12:00:00Z';
const contextId = '20000000-0000-4000-8000-000000000001';
http.Response response(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json; charset=utf-8'});
Map<String, dynamic> entity(String id,
        {int version = 1, String title = 'مدرسه', bool active = true}) =>
    {
      'id': id,
      'title': title,
      'kind': 'student',
      'user_id': owner,
      'active': active,
      'version': version,
      'created_at': stamp,
      'updated_at': stamp
    };

class Fixture {
  Fixture({String endpoint = 'https://school.test/api', String user = owner}) {
    api = HttpIdentityApi(baseUrl: endpoint, client: MockClient(handle))
      ..accessToken = 'synthetic'
      ..currentUserId = user;
    store = OfflineStore.forApi(api);
    sync = SchoolLifecycleSync(api, store: store);
  }
  late final HttpIdentityApi api;
  late final OfflineStore store;
  late final SchoolLifecycleSync sync;
  final rows = <String, Map<String, dynamic>>{};
  final receipts = <String, Map<String, dynamic>>{};
  final posts = <String>[];
  bool offline = false,
      loseAck = false,
      malformedAck = false,
      conflict = false,
      forged = false;
  Future<http.Response> handle(http.Request request) async {
    if (offline) throw http.ClientException('synthetic offline');
    if (request.method == 'GET') {
      return response({
        'contexts': rows.values.toList(),
        'years': [],
        'terms': [],
        'fetchedAt': stamp
      });
    }
    posts.add(request.body);
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    if (conflict) return response({'error': 'school_version_conflict'}, 409);
    final type = request.url.path.split('/').reversed.skip(1).first;
    if (!receipts.containsKey(body['mutationId'])) {
      final old = rows[body['entityId']];
      final data = body['data'] as Map;
      final row = entity(body['entityId'],
          version: body['expectedVersion'] + 1,
          title: data['title'] ?? old?['title'] ?? 'مدرسه',
          active: body['operation'] != 'archive');
      rows[row['id']] = row;
      receipts[body['mutationId']] = {
        'mutationId': body['mutationId'],
        'entityId': body['entityId'],
        'entityType': type,
        'operation': body['operation'],
        'status': 'accepted',
        'appliedVersion': row['version'],
        'acceptedAt': stamp
      };
    }
    if (loseAck) {
      loseAck = false;
      throw http.ClientException('ACK lost after synthetic commit');
    }
    final ack = {
      ...receipts[body['mutationId']]!,
      'status': posts
                  .where(
                      (p) => jsonDecode(p)['mutationId'] == body['mutationId'])
                  .length >
              1
          ? 'already_applied'
          : 'accepted'
    };
    if (malformedAck) ack['entityId'] = contextId;
    final row = {...rows[body['entityId']]!};
    if (forged) row['user_id'] = secondOwner;
    return response({'entity': row, 'acknowledgement': ack});
  }
}

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
      if (call.method == 'beginWrite') return guard = 'school-sync';
      if (call.method == 'completeWrite' && call.arguments == guard) {
        guard = null;
        return true;
      }
      throw PlatformException(code: 'local_storage_restart_required');
    });
  });
  test(
      'lost ACK is durably retained and reopened helper sends exact bytes once without a duplicate',
      () async {
    final f = Fixture()..loseAck = true;
    final result = await f.sync
        .mutate('contexts', 'create', {'title': ' مدرسه ', 'kind': 'student'});
    expect(result['queued'], true);
    expect(f.rows.length, 1);
    expect((await f.store.readQueue()).length, 1);
    final reopened =
        SchoolLifecycleSync(f.api, store: OfflineStore.forApi(f.api));
    await reopened.flush();
    expect(f.posts.length, 2);
    expect(f.posts[1], f.posts[0]);
    expect(f.rows.length, 1);
    expect(await f.store.readQueue(), isEmpty);
    expect((await reopened.read())['contexts'], hasLength(1));
    f.api.close();
  });
  test(
      'malformed or foreign-owner ACK does not erase pending intent or acknowledge a create',
      () async {
    for (final forged in [false, true]) {
      final f = Fixture(
          endpoint: 'https://${forged ? 'forged' : 'malformed'}.test/api')
        ..malformedAck = !forged
        ..forged = forged;
      await expectLater(
          f.sync.mutate(
              'contexts', 'create', {'title': 'مدرسه', 'kind': 'student'}),
          throwsA(
              isA<ApiException>().having((e) => e.statusCode, 'status', 502)));
      expect((await f.store.readQueue()).length, 1);
      expect(await f.store.readLastAck(), isNull);
      final id = (await f.store.readQueue()).single['entityId'] as String;
      await expectLater(
          f.sync.mutate(
              'contexts', 'create', {'title': 'مدرسه', 'kind': 'student'},
              entityId: id),
          throwsA(
              isA<ApiException>().having((e) => e.statusCode, 'status', 409)));
      expect(f.posts.length, 1);
      f.api.close();
    }
  });
  test(
      'conflict remains until explicit server choice journals the local intent',
      () async {
    final f = Fixture()..conflict = true;
    f.rows[contextId] = entity(contextId, version: 2, title: 'نسخه سرور');
    await expectLater(
        f.sync.mutate('contexts', 'update', {'title': 'نسخه محلی'},
            entityId: contextId, expectedVersion: 1),
        throwsA(
            isA<ApiException>().having((e) => e.statusCode, 'status', 409)));
    expect((await f.store.readQueue()).single['queueStatus'], 'conflict');
    await expectLater(f.sync.flush(), throwsA(isA<ApiException>()));
    expect(f.posts.length, 1);
    f.conflict = false;
    await f.sync.useServer('contexts', contextId);
    expect(await f.store.readQueue(), isEmpty);
    expect(
        (await f.store.readDiscardedChanges()).single['payload']['data']
            ['title'],
        'نسخه محلی');
    expect((await f.sync.read())['contexts'].single['title'], 'نسخه سرور');
    f.api.close();
  });
  test(
      'account and endpoint changes cannot replay previous school intent or cache',
      () async {
    final f = Fixture()..offline = true;
    await f.sync
        .mutate('contexts', 'create', {'title': 'خصوصی', 'kind': 'student'});
    final other = Fixture(user: secondOwner);
    expect(await other.sync.pending(), isEmpty);
    final endpoint = Fixture(endpoint: 'https://other-school.test/api');
    expect(await endpoint.sync.pending(), isEmpty);
    f.api.currentUserId = secondOwner;
    await expectLater(
        f.sync.flush(),
        throwsA(
            isA<ApiException>().having((e) => e.statusCode, 'status', 401)));
    expect(f.posts, isEmpty);
    f.api.close();
    other.api.close();
    endpoint.api.close();
  });
  test(
      'offline school cache preserves server freshness and never declares cached data live',
      () async {
    final f = Fixture();
    f.rows[contextId] = entity(contextId);
    final online = await f.sync.read();
    expect(online['offline'], false);
    f.offline = true;
    final stale = await f.sync.read();
    expect(stale['offline'], true);
    expect(stale['fetchedAt'], stamp);
    expect(stale['contexts'], hasLength(1));
    f.api.close();
  });
  test(
      'invalid dates and owner-controlled fields never enter queue or reach API',
      () async {
    final f = Fixture();
    for (final data in [
      {
        'title': 'year',
        'startsOn': '2026-02-30',
        'endsOn': '2027-01-01',
        'lifeContextId': contextId
      },
      {
        'title': 'year',
        'startsOn': '2027-01-01',
        'endsOn': '2026-01-01',
        'lifeContextId': contextId
      },
      {
        'title': 'year',
        'startsOn': '2026-09-01',
        'endsOn': '2027-01-01',
        'lifeContextId': contextId,
        'active': false
      }
    ]) {
      expect(() => f.sync.mutate('years', 'create', data),
          throwsA(isA<ApiException>()));
    }
    expect(await f.store.readQueue(), isEmpty);
    expect(f.posts, isEmpty);
    f.api.close();
  });
}
