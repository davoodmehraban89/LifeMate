import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifemate/api.dart';
import 'package:lifemate/offline_store.dart';
import 'package:lifemate/sync_changes_ui.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

class _ConflictApi extends HttpIdentityApi {
  _ConflictApi({this.denied = false})
      : super(
            baseUrl: 'https://conflict.example.test',
            client: MockClient((_) async => http.Response('', 503))) {
    accessToken = 'synthetic-token';
    currentUserId = denied ? 'denied-user' : 'test-owner';
  }
  final bool denied;
  int reads = 0;
  @override
  Future<Map<String, dynamic>> requestJson(String method, String path,
      {Map<String, dynamic>? body, bool auth = true}) async {
    reads++;
    if (denied) throw const ApiException(403, 'forbidden');
    return {
      'id': path.split('/').last,
      'title': 'Server current',
      'version': 7
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
      if (call.method == 'beginWrite') return pending = 'test-owned';
      if (call.method == 'completeWrite' && call.arguments == pending) {
        pending = null;
        return true;
      }
      throw PlatformException(code: 'local_storage_restart_required');
    });
  });

  Map<String, dynamic> mutation(int id, String entity,
          {String operation = 'update'}) =>
      {
        'id': '00000000-0000-4000-8000-${id.toString().padLeft(12, '0')}',
        'entityType': 'plan_item',
        'entityId': entity,
        'operation': operation,
        'expectedVersion': id,
        'payload': {'title': 'Local $id', 'notes': 'Private draft $id'}
      };

  test(
      'explicit discard journals the complete entity chain and preserves unrelated changes',
      () async {
    final store = OfflineStore.forNamespace('discard|owner');
    const target = '00000000-0000-4000-8000-000000000100';
    const other = '00000000-0000-4000-8000-000000000200';
    final first = mutation(1, target),
        dependent = mutation(2, target),
        unrelated = mutation(3, other);
    await store.enqueue(first,
        optimisticItem: {'id': target, 'title': 'Local first', 'version': 2});
    await store.markQueued(first['id'] as String, 'conflict');
    await store.enqueue(dependent,
        optimisticItem: {'id': target, 'title': 'Local latest', 'version': 3});
    await store.enqueue(unrelated,
        optimisticItem: {'id': other, 'title': 'Unrelated', 'version': 4});
    await store.cacheToday([
      {'id': target, 'title': 'Server old', 'version': 1}
    ]);
    final canonical = {'id': target, 'title': 'Server current', 'version': 9};
    await store.discardEntityChanges(target, serverItem: canonical);
    expect((await store.readQueue()).map((m) => m['id']), [unrelated['id']]);
    final reopened = OfflineStore.forNamespace(store.scope);
    final journal = await reopened.readDiscardedChanges();
    expect(journal, hasLength(2));
    expect(journal.map((m) => m['id']), [first['id'], dependent['id']]);
    expect(journal.first['payload'], first['payload']);
    expect(journal.last['payload'], dependent['payload']);
    expect(
        journal.every(
            (m) => DateTime.tryParse(m['discardedAt'] as String) != null),
        isTrue);
    expect((await reopened.readPlanner()).firstWhere((m) => m['id'] == target),
        canonical);
    expect((await reopened.readToday()).single, canonical);
    expect(await reopened.readLastAck(), isNull);
  });

  test(
      'discarding an unsent creation removes its optimistic item and retains recovery payload',
      () async {
    final store = OfflineStore.forNamespace('discard-new|owner');
    const id = '00000000-0000-4000-8000-000000000100';
    final create = mutation(1, id, operation: 'create');
    await store.enqueue(create,
        optimisticItem: {'id': id, 'title': 'Never sent', 'version': 1});
    await store.discardEntityChanges(id);
    expect(await store.readQueue(), isEmpty);
    expect(await store.readPlanner(), isEmpty);
    expect((await store.readDiscardedChanges()).single['payload'],
        create['payload']);
    expect(await store.readLastAck(), isNull);
  });

  test(
      'a mismatched server entity cannot discard the queue or create a journal',
      () async {
    final store = OfflineStore.forNamespace('discard-invalid|owner');
    const id = '00000000-0000-4000-8000-000000000100';
    await store.enqueue(mutation(1, id));
    await expectLater(
        store.discardEntityChanges(id,
            serverItem: {'id': 'other', 'version': 1}),
        throwsA(isA<Exception>()));
    expect(await store.readQueue(), hasLength(1));
    expect(await store.readDiscardedChanges(), isEmpty);
  });

  testWidgets(
      'conflict dialog preserves local changes until explicit use-server choice',
      (tester) async {
    final api = _ConflictApi();
    final store = OfflineStore.forApi(api);
    const id = '00000000-0000-4000-8000-000000000100';
    final pending = mutation(1, id);
    await store.enqueue(pending);
    await store.markQueued(pending['id'] as String, 'conflict');
    await tester.pumpWidget(MaterialApp(home: SyncChangesPage(api: api)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('بررسی و انتخاب'));
    await tester.pumpAndSettle();
    expect(find.text('نسخه سرور 7: Server current'), findsOneWidget);
    expect(await store.readQueue(), hasLength(1));
    await tester.tap(find.text('نگه‌داشتن تغییر محلی'));
    await tester.pumpAndSettle();
    expect(await store.readDiscardedChanges(), isEmpty);
    await tester.tap(find.text('بررسی و انتخاب'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('استفاده از نسخه سرور'));
    await tester.pumpAndSettle();
    expect(await store.readQueue(), isEmpty);
    expect((await store.readDiscardedChanges()).single['payload'],
        pending['payload']);
    expect((await store.readPlanner()).single['version'], 7);
    expect(find.text('Private draft 1'), findsNothing);
    expect(await store.readLastAck(), isNull);
  });

  testWidgets(
      '403 shows no comparison or cached title and retains every pending payload',
      (tester) async {
    final api = _ConflictApi(denied: true);
    final store = OfflineStore.forApi(api);
    const id = '00000000-0000-4000-8000-000000000100';
    final pending = mutation(1, id);
    await store.enqueue(pending,
        optimisticItem: {'id': id, 'title': 'Cached forbidden title'});
    await store.markQueued(pending['id'] as String, 'conflict');
    await tester.pumpWidget(MaterialApp(home: SyncChangesPage(api: api)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('بررسی و انتخاب'));
    await tester.pumpAndSettle();
    expect(
        find.text('برای این اطلاعات یا عملیات دسترسی نداری.'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Cached forbidden title'), findsNothing);
    expect(find.text('Local 1'), findsNothing);
    expect(await store.readQueue(), hasLength(1));
    expect(await store.readDiscardedChanges(), isEmpty);
  });
}
