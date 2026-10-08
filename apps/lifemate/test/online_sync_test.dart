import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:lifemate/api.dart';
import 'package:lifemate/offline_store.dart';
import 'package:lifemate/plan_sync.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

class _SyncApi implements IdentityApi {
  bool offline = true;
  bool conflict = false;
  String? malformedAck;
  final sent = <Map<String, dynamic>>[];
  final items = <String, Map<String, dynamic>>{};
  final applied = <String>{};
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  @override
  Future<Map<String, dynamic>> submitSyncMutations(
      List<Map<String, dynamic>> mutations) async {
    if (offline) throw const ApiException(0, 'network_unavailable');
    return {
      'results': mutations.map((m) {
        sent.add(Map<String, dynamic>.from(m));
        if (conflict) {
          return {
            'id': m['id'],
            'status': 'conflict',
            'error': 'version_conflict'
          };
        }
        if (m['operation'] != 'create' && !items.containsKey(m['entityId'])) {
          return {'id': m['id'], 'status': 'rejected', 'error': 'not_found'};
        }
        final item = items.putIfAbsent(
            m['entityId'] as String,
            () => {
                  'id': m['entityId'],
                  'title': (m['payload'] as Map)['title'],
                  'kind': 'assignment',
                  'status': 'planned',
                  'visibility': 'private',
                  'version': 1,
                });
        if (applied.add(m['id'] as String) && m['operation'] != 'create') {
          if (item['version'] != m['expectedVersion']) {
            return {
              'id': m['id'],
              'status': 'conflict',
              'error': 'version_conflict'
            };
          }
          item.addAll(Map<String, dynamic>.from(m['payload'] as Map));
          item['version'] = (item['version'] as int) + 1;
        }
        return {
          'id': m['id'],
          'status': 'accepted',
          if (malformedAck != 'missing')
            'item': {
              ...item,
              if (malformedAck == 'wrong') 'id': 'wrong-entity'
            },
          'acceptedAt': '2026-10-08T10:00:00Z'
        };
      }).toList()
    };
  }
}

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
      if (call.method == 'beginWrite') return pending = 'owned-test-token';
      if (call.method == 'completeWrite' && call.arguments == pending) {
        pending = null;
        return true;
      }
      throw PlatformException(code: 'local_storage_restart_required');
    });
  });

  test(
      'offline create survives reopening then acknowledges once with stable IDs',
      () async {
    final api = _SyncApi();
    final store = OfflineStore.forNamespace('test|child');
    final result = await PlanSync(api, store: store)
        .create({'kind': 'assignment', 'title': 'ریاضی'});
    expect(result.queued, isTrue);
    final reopened = OfflineStore.forNamespace('test|child');
    final queue = await reopened.readQueue();
    expect(queue, hasLength(1));
    expect(queue.single['id'], matches(RegExp(r'^[a-f0-9-]{36}$')));
    expect(queue.single['entityId'], result.item!['id']);
    api.offline = false;
    await PlanSync(api, store: reopened).flush();
    await PlanSync(api, store: reopened).flush();
    expect(api.sent, hasLength(1));
    expect(api.sent.single['id'], queue.single['id']);
    expect(await reopened.pendingCount(), 0);
    expect(await reopened.readLastAck(), isNotNull);
  });

  test('separate account/server scopes never share cache or pending changes',
      () async {
    final first = OfflineStore.forNamespace('https://one.test/api|child');
    final parent = OfflineStore.forNamespace('https://one.test/api|parent');
    final other = OfflineStore.forNamespace('https://two.test/api|child');
    await first.cachePlanner([
      {'id': 'private', 'notes': 'synthetic private note'}
    ]);
    expect(await parent.readPlanner(), isEmpty);
    expect(await other.readPlanner(), isEmpty);
    await first.clear();
    expect(await OfflineStore.forNamespace(first.scope).readPlanner(), isEmpty);
    await expectLater(
        first.cachePlanner([
          {'id': 'stale'}
        ]),
        throwsA(isA<ApiException>()));
  });

  test('offline create then complete survives restart and both acknowledge',
      () async {
    final api = _SyncApi();
    final store = OfflineStore.forNamespace('chain|child');
    final created = await PlanSync(api, store: store)
        .create({'kind': 'assignment', 'title': 'ریاضی'});
    await PlanSync(api, store: store).complete(created.item!);
    api.offline = false;
    final reopened = OfflineStore.forNamespace(store.scope);
    await PlanSync(api, store: reopened).flush();
    expect(await reopened.pendingCount(), 0);
    expect(api.items.values.single['status'], 'completed');
    expect(api.items.values.single['version'], 2);
  });

  test('reconnection drains the pending create before a new completion',
      () async {
    final api = _SyncApi();
    final store = OfflineStore.forNamespace('reconnect|child');
    final created =
        await PlanSync(api, store: store).create({'title': 'ریاضی'});
    api.offline = false;
    await PlanSync(api, store: store).complete(created.item!);
    expect(api.sent.map((m) => m['operation']), ['create', 'complete']);
    expect(await store.pendingCount(), 0);
  });

  test('malformed acknowledgement never removes the pending change', () async {
    for (final malformed in ['missing', 'wrong']) {
      final api = _SyncApi()
        ..offline = false
        ..malformedAck = malformed;
      final store = OfflineStore.forNamespace('ack-$malformed|child');
      await expectLater(
          PlanSync(api, store: store).create({'title': 'ریاضی'}),
          throwsA(isA<ApiException>()
              .having((e) => e.code, 'code', 'invalid_sync_acknowledgement')));
      expect(await store.pendingCount(), 1);
    }
  });

  test('fresh server cache does not erase an unsent optimistic update',
      () async {
    final api = _SyncApi();
    final store = OfflineStore.forNamespace('overlay|child');
    await store.cachePlanner([
      {
        'id': '00000000-0000-4000-8000-000000000111',
        'title': 'old',
        'version': 1
      }
    ]);
    await PlanSync(api, store: store)
        .update((await store.readPlanner()).single, {'title': 'offline edit'});
    await store.cachePlanner([
      {
        'id': '00000000-0000-4000-8000-000000000111',
        'title': 'old',
        'version': 1
      }
    ]);
    expect((await store.readPlanner()).single['title'], 'offline edit');
    expect((await store.readPlanner()).single['pending_sync'], isTrue);
  });

  test('conflicts retain the change and never become an offline success',
      () async {
    final api = _SyncApi();
    final store = OfflineStore.forNamespace('test|child');
    await PlanSync(api, store: store)
        .create({'kind': 'assignment', 'title': 'ریاضی'});
    api.offline = false;
    api.conflict = true;
    await expectLater(
        PlanSync(api, store: store).flush(),
        throwsA(isA<ApiException>()
            .having((e) => e.code, 'code', 'sync_conflict')));
    expect(await store.pendingCount(), 1);
    expect((await store.readQueue()).single['queueStatus'], 'conflict');
  });

  test('HTTP permission, validation, server and storage errors are not offline',
      () {
    for (final status in [401, 403, 409, 422, 500, 503]) {
      expect(isOfflineFailure(ApiException(status, 'failure')), isFalse);
    }
    expect(
        isOfflineFailure(const ApiException(0, 'network_unavailable')), isTrue);
    expect(isOfflineFailure(const ApiException(0, 'local_storage_failed')),
        isFalse);
  });
}
