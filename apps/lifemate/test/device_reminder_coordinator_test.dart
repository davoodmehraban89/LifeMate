import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifemate/api.dart';
import 'package:lifemate/device_reminder_coordinator.dart';
import 'package:lifemate/local_reminders.dart';
import 'package:lifemate/offline_store.dart';
import 'package:lifemate/plan_sync.dart';
import 'package:lifemate/device_reminder_preferences.dart';
import 'package:lifemate/session_store.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

class MemoryReminderSession implements SessionStore {
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String value) async {}
  @override
  Future<void> clear() async {}
}

class RecordingReminders implements LocalReminderPort {
  String? scope;
  DateTime? until;
  bool granted = true;
  final calls = <String>[];
  List<LocalReminder> rows = [];
  Completer<void>? replaceEntered, replaceRelease;
  @override
  Future<LocalReminderStatus> status() async => LocalReminderStatus(
      supported: true,
      permissionGranted: granted,
      active: scope != null,
      activeScope: scope,
      validUntil: until,
      scheduledCount: rows.length);
  @override
  Future<LocalReminderStatus> requestPermission() async {
    calls.add('permission');
    return status();
  }

  @override
  Future<LocalReminderStatus> requestExactAlarmAccess() async {
    calls.add('exact');
    return status();
  }

  @override
  Future<void> activate(String value, {required DateTime validUntil}) async {
    calls.add('activate');
    scope = value;
    until = validUntil;
  }

  @override
  Future<void> replace(String scope, List<LocalReminder> reminders,
      {required String currentUserId}) async {
    calls.add('replace');
    replaceEntered?.complete();
    await replaceRelease?.future;
    rows = reminders;
  }

  @override
  Future<void> suppressPlanItems(String scope, Set<String> ids) async {
    calls.add('suppress');
    rows = rows.where((r) => !ids.contains(r.planItemId)).toList();
  }

  @override
  Future<void> deactivate() async {
    calls.add('deactivate');
    scope = null;
    until = null;
    rows = [];
  }
}

class _OfflineMutationApi implements IdentityApi {
  @override
  Future<Map<String, dynamic>> submitSyncMutations(
          List<Map<String, dynamic>> mutations) async =>
      throw const ApiException(0, 'network_unavailable');
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const owner = '11111111-1111-4111-8111-111111111111',
      item = '22222222-2222-4222-8222-222222222222',
      reminder = '33333333-3333-4333-8333-333333333333';
  final now = DateTime.utc(2026, 10, 18, 8);
  late RecordingReminders port;
  late HttpIdentityApi api;
  late OfflineStore store;
  late DeviceReminderCoordinator coordinator;
  var requests = 0;
  Object? networkFailure;
  Completer<void>? responseGate;
  late Map<String, dynamic> response;
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
    port = RecordingReminders();
    requests = 0;
    networkFailure = null;
    responseGate = null;
    response = {
      'asOf': now.toIso8601String(),
      'reminders': [
        {
          'id': reminder,
          'plan_item_id': item,
          'scheduled_for': now.add(const Duration(hours: 1)).toIso8601String(),
          'owner_user_id': owner
        }
      ]
    };
    api = HttpIdentityApi(
        baseUrl: 'https://fixture.invalid/api',
        sessionStore: MemoryReminderSession(),
        client: MockClient((req) async {
          requests++;
          expect(req.url.path, '/api/v1/planner-reminders');
          expect(req.headers['authorization'], 'Bearer synthetic-access');
          expect(
              DateTime.parse(req.url.queryParameters['to']!)
                  .difference(DateTime.parse(req.url.queryParameters['from']!)),
              const Duration(hours: 24));
          await responseGate?.future;
          if (networkFailure != null) throw networkFailure!;
          return http.Response(jsonEncode(response), 200,
              headers: {'content-type': 'application/json; charset=utf-8'});
        }))
      ..accessToken = 'synthetic-access'
      ..currentUserId = owner;
    store = OfflineStore.forApi(api);
    coordinator = DeviceReminderCoordinator(api,
        port: port, store: store, now: () => now);
  });
  test('freshness reconciliation never opts a new account into alarms',
      () async {
    final status = await coordinator.reconcile();
    expect(status.active, isFalse);
    expect(requests, 0);
    expect(port.calls, isEmpty);
  });
  test('explicit enable schedules only fresh owner API records', () async {
    final result = await coordinator.enable(companionName: 'همراه من');
    expect(requests, 1);
    expect(port.calls, ['permission', 'activate', 'replace']);
    expect(result.scheduledCount, 1);
    expect(port.rows.single.companionName, 'همراه من');
    expect(port.rows.single.serverAcknowledged, isTrue);
    expect(result.validUntil, now.add(const Duration(hours: 24)));
  });
  test('default reconciliation reads only this scope companion nickname',
      () async {
    await DeviceReminderPreferences().write(api.cacheNamespace!, 'همراه من');
    await coordinator.enable();
    expect(port.rows.single.companionName, 'همراه من');
  });

  test('offline edit waits for native replacement then cancels its alarm',
      () async {
    port.replaceEntered = Completer<void>();
    port.replaceRelease = Completer<void>();
    final enabling = coordinator.enable();
    await port.replaceEntered!.future;
    final changing =
        PlanSync(_OfflineMutationApi(), store: store, reminders: port)
            .complete({
      'id': item,
      'title': 'برنامهٔ ساختگی',
      'status': 'planned',
      'version': 1,
    });
    await Future<void>.delayed(Duration.zero);
    expect(await store.pendingCount(), 0);
    port.replaceRelease!.complete();
    await enabling;
    await changing;
    expect(port.calls, ['permission', 'activate', 'replace', 'suppress']);
    expect(port.rows, isEmpty);
    expect(await store.pendingCount(), 1);
  });

  test('pending offline edits cannot recreate the old native alarm', () async {
    await store.enqueue({
      'id': '44444444-4444-4444-8444-444444444444',
      'entityType': 'plan_item',
      'entityId': item,
      'operation': 'complete',
      'expectedVersion': 1,
      'clientUpdatedAt': now.toIso8601String(),
      'payload': {'status': 'completed'}
    });
    await coordinator.enable();
    expect(port.rows, isEmpty);
  });
  test('foreign owner and stale server timestamps never extend lease',
      () async {
    (response['reminders'] as List).single['owner_user_id'] =
        '55555555-5555-4555-8555-555555555555';
    await expectLater(coordinator.enable(), throwsA(isA<ApiException>()));
    expect(port.calls, ['permission']);
    response['reminders'] = [];
    response['asOf'] =
        now.subtract(const Duration(minutes: 10)).toIso8601String();
    await expectLater(coordinator.enable(), throwsA(isA<ApiException>()));
    expect(port.calls, ['permission', 'permission']);
  });
  test('offline refresh leaves the previous lease unchanged', () async {
    await coordinator.enable();
    final before = port.until;
    port.calls.clear();
    networkFailure = http.ClientException('synthetic offline');
    await expectLater(coordinator.reconcile(), throwsA(isA<ApiException>()));
    expect(port.until, before);
    expect(port.calls, isEmpty);
  });
  test('logout while reminder read is pending cannot reactivate alarms',
      () async {
    await coordinator.enable();
    port.calls.clear();
    responseGate = Completer<void>();
    final pending = coordinator.reconcile();
    await Future<void>.delayed(Duration.zero);
    api.accessToken = null;
    api.currentUserId = null;
    await port.deactivate();
    responseGate!.complete();
    await expectLater(pending, throwsA(isA<ApiException>()));
    expect(port.calls, ['deactivate']);
  });
  test('disable from another coordinator defeats a delayed refresh', () async {
    await coordinator.enable();
    port.calls.clear();
    responseGate = Completer<void>();
    final pending = coordinator.reconcile();
    await Future<void>.delayed(Duration.zero);
    await DeviceReminderCoordinator(api,
            port: port, now: () => now, store: store)
        .disable();
    responseGate!.complete();
    await expectLater(
        pending,
        throwsA(isA<ApiException>().having(
            (e) => e.code, 'code', 'device_notification_intent_changed')));
    expect(port.calls, ['deactivate']);
    expect(port.rows, isEmpty);
    expect(port.scope, isNull);
  });
}
