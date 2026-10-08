import 'dart:async';
import 'dart:math';
import 'api.dart';
import 'offline_store.dart';

String newMutationId() {
  final random = Random.secure();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((n) => n.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

class MutationOutcome {
  const MutationOutcome({required this.queued, this.item});
  final bool queued;
  final Map<String, dynamic>? item;
}

class PlanSync {
  PlanSync(this.api, {OfflineStore? store})
      : store = store ?? OfflineStore.forApi(api);
  final IdentityApi api;
  final OfflineStore store;
  static final _tails = <String, Future<void>>{};
  Future<T> _serial<T>(Future<T> Function() operation) {
    final previous = _tails[store.scope];
    final release = Completer<void>();
    _tails[store.scope] = release.future;
    return (() async {
      if (previous != null) await previous;
      try {
        return await operation();
      } finally {
        if (identical(_tails[store.scope], release.future)) {
          _tails.remove(store.scope);
        }
        release.complete();
      }
    })();
  }

  Future<MutationOutcome> create(Map<String, dynamic> payload) {
    final item = <String, dynamic>{
      'id': newMutationId(),
      'kind': payload['kind'] ?? 'task',
      'title': payload['title'],
      'status': 'planned',
      'visibility': payload['visibility'] ?? 'private',
      'due_at': payload['dueAt'],
      'starts_at': payload['startsAt'],
      'version': 0,
      'pending_sync': true,
      'acknowledged': false
    };
    return _change('create', item, payload);
  }

  Future<MutationOutcome> update(
          Map<String, dynamic> item, Map<String, dynamic> changes) =>
      _change('update', item, changes);
  Future<MutationOutcome> complete(Map<String, dynamic> item) =>
      _change('complete', item, {'status': 'completed'});
  Future<MutationOutcome> archive(Map<String, dynamic> item) =>
      _change('archive', item, {'status': 'cancelled'});
  Future<MutationOutcome> _change(String operation, Map<String, dynamic> item,
          Map<String, dynamic> payload) =>
      _serial(() async {
        final expected = int.tryParse(item['version'].toString()) ?? 0;
        final mutation = <String, dynamic>{
          'id': newMutationId(),
          'entityType': 'plan_item',
          'entityId': item['id'],
          'operation': operation,
          'expectedVersion': expected,
          'clientUpdatedAt': DateTime.now().toUtc().toIso8601String(),
          'payload': payload
        };
        final optimistic = optimisticPlanItem(item, mutation);
        await store.enqueue(mutation, optimisticItem: optimistic);
        try {
          await _flushQueue();
          final pending =
              (await store.readQueue()).any((m) => m['id'] == mutation['id']);
          final cached = (await store.readPlanner())
              .where((m) => m['id'] == item['id'])
              .firstOrNull;
          return MutationOutcome(queued: pending, item: cached ?? optimistic);
        } catch (error) {
          if (isOfflineFailure(error)) {
            return MutationOutcome(queued: true, item: optimistic);
          }
          rethrow;
        }
      });

  Future<MutationOutcome> _send(Map<String, dynamic> mutation) async {
    final response = await api.submitSyncMutations([mutation]);
    final results = response['results'];
    if (results is! List ||
        results.length != 1 ||
        results.single is! Map ||
        (results.single as Map)['id'] != mutation['id']) {
      throw const ApiException(502, 'invalid_sync_acknowledgement');
    }
    final result = results.single as Map;
    if (result['status'] == 'accepted' ||
        result['status'] == 'already_applied') {
      final rawItem = result['item'];
      final version =
          rawItem is Map ? int.tryParse(rawItem['version'].toString()) : null;
      final expected =
          int.tryParse(mutation['expectedVersion'].toString()) ?? 0;
      final acceptedAt = result['acceptedAt'];
      if (rawItem is! Map ||
          rawItem['id'] != mutation['entityId'] ||
          version == null ||
          version < expected + 1 ||
          acceptedAt is! String ||
          DateTime.tryParse(acceptedAt) == null) {
        throw const ApiException(502, 'invalid_sync_acknowledgement');
      }
      final item = Map<String, dynamic>.from(rawItem);
      await store.acknowledge(mutation['id'] as String,
          item: item, acceptedAt: result['acceptedAt'] as String?);
      return MutationOutcome(queued: false, item: item);
    }
    final conflict = result['status'] == 'conflict';
    await store.markQueued(
        mutation['id'] as String, conflict ? 'conflict' : 'rejected',
        error: result['error']?.toString());
    throw ApiException(
        conflict ? 409 : 422,
        conflict
            ? 'sync_conflict'
            : (result['error']?.toString() ?? 'sync_rejected'));
  }

  Future<void> flush() => _serial(_flushQueue);
  Future<void> _flushQueue() async {
    for (final queued in await store.readQueue()) {
      if (queued['entityType'] != 'plan_item') continue;
      if (queued['queueStatus'] == 'conflict') {
        throw const ApiException(409, 'sync_conflict');
      }
      if (queued['queueStatus'] != 'queued') continue;
      final mutation = Map<String, dynamic>.from(queued)
        ..remove('queuedAt')
        ..remove('queueStatus')
        ..remove('lastError');
      try {
        await _send(mutation);
      } catch (error) {
        if (isOfflineFailure(error)) return;
        rethrow;
      }
    }
  }
}
