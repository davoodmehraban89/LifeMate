import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:lifemate/api.dart';
import 'package:lifemate/local_reminders.dart';
import 'package:lifemate/offline_store.dart';
import 'package:lifemate/plan_sync.dart';
import 'package:lifemate/session_store.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

class _Session implements SessionStore {
  final List<String> events;
  _Session(this.events);
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String value) async {}
  @override
  Future<void> clear() async {
    events.add('credential-clear');
  }
}

class _Port implements LocalReminderPort {
  final List<String> events;
  final OfflineStore store;
  _Port(this.events, this.store);
  @override
  Future<void> suppressPlanItems(String scope, Set<String> ids) async {
    expect(scope, store.scope);
    expect(ids, {'22222222-2222-4222-8222-222222222222'});
    expect(await store.pendingCount(), 1);
    events.add('suppress');
  }

  @override
  Future<void> deactivate() async {
    events.add('deactivate');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _OfflineApi implements IdentityApi {
  final List<String> events;
  _OfflineApi(this.events);
  @override
  Future<Map<String, dynamic>> submitSyncMutations(
      List<Map<String, dynamic>> values) async {
    events.add('send');
    throw const ApiException(0, 'network_unavailable');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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
      if (call.method == 'beginWrite') return pending = 'synthetic';
      if (call.method == 'completeWrite' && call.arguments == pending) {
        pending = null;
        return true;
      }
      throw PlatformException(code: 'local_storage_restart_required');
    });
  });
  test(
      'offline completion suppresses old alarm after durable enqueue before send',
      () async {
    final events = <String>[],
        store = OfflineStore.forNamespace('synthetic-reminder-scope');
    final result = await PlanSync(_OfflineApi(events),
            store: store, reminders: _Port(events, store))
        .complete({
      'id': '22222222-2222-4222-8222-222222222222',
      'title': 'برنامهٔ ساختگی',
      'status': 'planned',
      'version': 1
    });
    expect(result.queued, isTrue);
    expect(events, ['suppress', 'send']);
  });
  test('logout starts alarm cancellation before clearing credentials',
      () async {
    final events = <String>[];
    final gate = Completer<void>();
    final api = HttpIdentityApi(
        baseUrl: 'https://fixture.invalid/api',
        client: MockClient((_) async => throw StateError('Unexpected network')),
        sessionStore: _Session(events),
        onSessionDeactivating: () async {
          events.add('cancel-start');
          await gate.future;
          events.add('cancel-finish');
        })
      ..accessToken = 'synthetic-access'
      ..currentUserId = '11111111-1111-4111-8111-111111111111';
    final signingOut = api.logout(revoke: false);
    await Future<void>.delayed(Duration.zero);
    expect(events.first, 'cancel-start');
    expect(api.accessToken, isNull);
    gate.complete();
    await signingOut;
    expect(events.indexOf('cancel-finish'),
        lessThan(events.indexOf('credential-clear')));
  });
  test(
      'alarm cancellation failure still clears credentials and reports failure',
      () async {
    final events = <String>[];
    final api = HttpIdentityApi(
        baseUrl: 'https://fixture.invalid/api',
        client: MockClient((_) async => throw StateError('Unexpected network')),
        sessionStore: _Session(events),
        onSessionDeactivating: () async {
          throw StateError('synthetic device failure');
        })
      ..accessToken = 'synthetic-access'
      ..currentUserId = '11111111-1111-4111-8111-111111111111';
    await expectLater(api.logout(revoke: false), throwsStateError);
    expect(api.accessToken, isNull);
    expect(api.currentUserId, isNull);
    expect(events, ['credential-clear']);
  });
}
