import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifemate/api.dart';
import 'package:lifemate/offline_store.dart';
import 'package:lifemate/planner_series.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

const owner = '10000000-0000-4000-8000-000000000001';
const seriesId = '20000000-0000-4000-8000-000000000001';
const payload = <String, dynamic>{
  'title': 'برنامه ساختگی مدرسه',
  'kind': 'event',
  'timezone': 'Asia/Tehran',
  'startsOn': '2026-10-18',
  'frequency': 'weekly',
  'intervalDays': 1,
  'slots': [
    {'weekday': 6, 'start': '08:00', 'end': '12:00'}
  ],
  'reminderMinutes': [5]
};

class Fixture {
  Fixture() {
    api = HttpIdentityApi(
        baseUrl: 'https://weekly.test/api', client: MockClient(handle))
      ..accessToken = 'synthetic-token'
      ..currentUserId = owner;
    store = OfflineStore.forNamespace(api.cacheNamespace!,
        session: OfflineSession());
  }
  late final HttpIdentityApi api;
  late final OfflineStore store;
  bool offline = false, loseReceipt = false, badOwner = false;
  int? status;
  int commits = 0;
  final requests = <String>[];
  final rows = <String, Map<String, dynamic>>{};
  PlannerSeriesSync reopen() => PlannerSeriesSync(api,
      store: OfflineStore.forNamespace(store.scope, session: OfflineSession()));
  Future<http.Response> handle(http.Request request) async {
    requests.add(request.body);
    if (offline) throw http.ClientException('synthetic offline');
    if (status != null) {
      return http.Response('{"error":"synthetic_rejection"}', status!);
    }
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    expect((await store.readQueue()).single['payload'], body);
    final id = body['id'] as String;
    rows.putIfAbsent(id, () {
      commits++;
      return {
        'id': id,
        'owner_user_id': owner,
        'version': 1,
        'title': body['title'],
      };
    });
    if (loseReceipt) {
      loseReceipt = false;
      throw http.ClientException('synthetic lost receipt');
    }
    return http.Response(
        jsonEncode({
          'series': {
            ...rows[id]!,
            if (badOwner) 'owner_user_id': 'other-owner'
          },
          'items': [
            {
              'id': '30000000-0000-4000-8000-000000000001',
              'series_id': id,
              'owner_user_id': owner,
              'title': body['title'],
              'version': 1,
              'status': 'planned'
            }
          ]
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'});
  }
}

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
      if (call.method == 'beginWrite') return token = 'synthetic-series-write';
      if (call.method == 'completeWrite' && call.arguments == token) {
        token = null;
        return true;
      }
      throw PlatformException(code: 'local_storage_restart_required');
    });
  });
  test('offline durable draft reopens and synchronizes exact ID once',
      () async {
    final f = Fixture()..offline = true;
    expect((await f.reopen().create(payload, id: seriesId)).queued, true);
    expect((await f.store.readQueue()).single['entityId'], seriesId);
    expect(await f.store.readPlanner(), isEmpty);
    f.offline = false;
    await f.reopen().flush();
    expect(f.commits, 1);
    expect(await f.store.readQueue(), isEmpty);
    expect((await f.store.readPlanner()).single['series_id'], seriesId);
    expect((await f.store.readList('planner_series')).single['id'], seriesId);
    expect(f.requests.first, f.requests.last);
  });
  test('response lost after commit retries same UUID without duplicate',
      () async {
    final f = Fixture()..loseReceipt = true;
    expect((await f.reopen().create(payload, id: seriesId)).queued, true);
    expect((await f.reopen().create(payload, id: seriesId)).queued, false);
    expect(f.commits, 1);
    expect(f.requests.toSet().length, 1);
  });
  test('terminal 400 is retained and retry never reports queued success',
      () async {
    final f = Fixture()..status = 400;
    await expectLater(
        f.reopen().create(payload, id: seriesId), throwsA(isA<ApiException>()));
    expect((await f.store.readQueue()).single['queueStatus'], 'rejected');
    f.status = null;
    await expectLater(
        f.reopen().create(payload, id: seriesId),
        throwsA(
            isA<ApiException>().having((e) => e.statusCode, 'status', 422)));
    expect(f.requests.length, 1);
  });
  test('ambiguous server error keeps exact frozen request for retry', () async {
    final f = Fixture()..status = 500;
    await expectLater(
        f.reopen().create(payload, id: seriesId), throwsA(isA<ApiException>()));
    expect((await f.store.readQueue()).single['queueStatus'], 'queued');
    await expectLater(
        f.reopen().create({...payload, 'title': 'changed'}, id: seriesId),
        throwsA(isA<ApiException>()
            .having((e) => e.code, 'code', 'mutation_id_reused')));
    f.status = null;
    expect((await f.reopen().create(payload, id: seriesId)).queued, false);
    expect(f.requests.toSet().length, 1);
  });
  test('foreign owner acknowledgement cannot remove private draft', () async {
    final f = Fixture()..badOwner = true;
    await expectLater(
        f.reopen().create(payload, id: seriesId),
        throwsA(isA<ApiException>()
            .having((e) => e.code, 'code', 'invalid_series_acknowledgement')));
    expect((await f.store.readQueue()).length, 1);
    expect(await f.store.readPlanner(), isEmpty);
  });
  test('old service cannot send after identity changes', () async {
    final f = Fixture();
    final sync = f.reopen();
    f.api.currentUserId = 'other-synthetic-user';
    await expectLater(
        sync.create(payload, id: seriesId), throwsA(isA<ApiException>()));
    expect(f.requests, isEmpty);
  });
  test('rejected draft does not block other sync and keeps recoverable journal',
      () async {
    final f = Fixture()..status = 400;
    await expectLater(
        f.reopen().create(payload, id: seriesId), throwsA(isA<ApiException>()));
    f.status = null;
    await f.reopen().flush();
    expect(f.requests.length, 1);
    await f.store.discardEntityChanges(seriesId,
        entityType: 'planner_series', cacheKey: 'planner_series');
    expect(await f.store.readQueue(), isEmpty);
    expect((await f.store.readDiscardedChanges()).single['entityType'],
        'planner_series');
  });
  test('acknowledged UUID cannot silently accept edited payload', () async {
    final f = Fixture();
    await f.reopen().create(payload, id: seriesId);
    await expectLater(
        f.reopen().create({...payload, 'title': 'changed'}, id: seriesId),
        throwsA(isA<ApiException>()
            .having((e) => e.code, 'code', 'mutation_id_reused')));
    expect(f.requests.length, 1);
  });
  test('Saturday week and dates retain selected calendar day', () {
    final days = plannerWeekDays(DateTime(2026, 10, 18));
    expect(days.first.weekday, DateTime.saturday);
    expect(plannerDate(days.first), '2026-10-17');
    expect(days.last.weekday, DateTime.friday);
  });
}
