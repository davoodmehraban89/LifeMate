import 'dart:async';

import 'api.dart';
import 'offline_store.dart';
import 'plan_sync.dart' show newMutationId;

/// Explicit personal reports, never inferred from playback or elapsed time.
/// Pending writes are scoped to the authenticated API/account and persisted
/// before delivery. Only a matching server acknowledgement removes a write.
class LearningSync {
  LearningSync(this.api, {OfflineStore? store})
      : store = store ?? OfflineStore.forApi(api);

  final HttpIdentityApi api;
  final OfflineStore store;
  static final _tails = <String, Future<void>>{};
  static const _statuses = {'not_started', 'in_progress', 'completed'};
  static const _progressCache = 'learning_progress';
  static final _uuid =
      RegExp(r'^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$');

  void _checkScope() {
    if (api.cacheNamespace != store.scope) {
      throw const ApiException(401, 'cache_scope_closed');
    }
  }

  Future<T> _serial<T>(Future<T> Function() operation) {
    final previous = _tails[store.scope];
    final release = Completer<void>();
    _tails[store.scope] = release.future;
    return (() async {
      if (previous != null) await previous;
      try {
        _checkScope();
        // Verify the handle generation before making an authenticated request.
        await store.readQueue();
        _checkScope();
        final result = await operation();
        _checkScope();
        return result;
      } finally {
        if (identical(_tails[store.scope], release.future)) {
          _tails.remove(store.scope);
        }
        release.complete();
      }
    })();
  }

  static bool _timestamp(dynamic value) =>
      value is String &&
      RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(value) &&
      DateTime.tryParse(value) != null;

  static Map<String, dynamic> _initialProgress(String unitId) => {
        'id': unitId,
        'unitId': unitId,
        'status': 'not_started',
        'source': 'self_reported',
        'version': 0,
        'updatedAt': null,
        'pending_sync': false,
        'acknowledged': false,
      };

  static Map<String, dynamic> _serverProgress(dynamic raw, String unitId) {
    if (raw is! Map ||
        raw['unitId'] != unitId ||
        !_statuses.contains(raw['status']) ||
        raw['source'] != 'self_reported' ||
        raw['version'] is! int ||
        raw['version'] < 0 ||
        (raw['version'] > 0 && !_timestamp(raw['updatedAt']))) {
      throw const ApiException(502, 'invalid_learning_progress');
    }
    return {
      ...Map<String, dynamic>.from(raw),
      'id': unitId,
      'pending_sync': false,
      'acknowledged': raw['version'] > 0,
    };
  }

  Future<List<Map<String, dynamic>>> pendingFor(String unitId) async {
    _checkScope();
    final pending = (await store.readQueue())
        .where((m) =>
            m['entityType'] == 'learning_progress' && m['entityId'] == unitId)
        .toList();
    _checkScope();
    return pending;
  }

  Future<Map<String, dynamic>> readCourse(String id) => _serial(() async {
        if (!_uuid.hasMatch(id)) {
          throw const ApiException(400, 'invalid_course_id');
        }
        final key = 'learning.course:$id';
        Map<String, dynamic> course;
        var offline = false;
        try {
          final response = await api.requestJson(
              'GET', '/v1/education/courses/${Uri.encodeComponent(id)}');
          _checkScope();
          final raw = response['course'] ?? response;
          if (raw is! Map || raw['id'] != id || raw['units'] is! List) {
            throw const ApiException(502, 'invalid_learning_course');
          }
          course = Map<String, dynamic>.from(raw);
          final known = await store.readList(_progressCache);
          final ids = <String>{};
          for (final rawUnit in course['units'] as List) {
            if (rawUnit is! Map ||
                rawUnit['id'] is! String ||
                !_uuid.hasMatch(rawUnit['id']) ||
                !ids.add(rawUnit['id'])) {
              throw const ApiException(502, 'invalid_learning_course');
            }
            final unitId = rawUnit['id'] as String;
            final progress = rawUnit['progress'];
            final server = progress == null
                ? _initialProgress(unitId)
                : _serverProgress(progress, unitId);
            known.removeWhere((p) => p['id'] == unitId);
            known.add(server);
          }
          await store.writeList(_progressCache, known);
          await store.writeList(key, [course]);
        } catch (error) {
          _checkScope();
          if (!isOfflineFailure(error)) rethrow;
          final cached = await store.readList(key);
          if (cached.length != 1) rethrow;
          course = cached.single;
          offline = true;
        }
        _checkScope();
        return {
          ...course,
          'offline': offline,
          'units': await _overlayUnits(course['units'] as List),
        };
      });

  Future<List<Map<String, dynamic>>> _overlayUnits(List units) async {
    final known = await store.readList(_progressCache);
    final pending = await store.readQueue();
    return [
      for (final raw in units)
        {
          ...Map<String, dynamic>.from(raw as Map),
          'progress': _overlayProgress(
              raw['id'] as String,
              known.where((p) => p['unitId'] == raw['id']).firstOrNull ??
                  _initialProgress(raw['id'] as String),
              pending),
        }
    ];
  }

  static Map<String, dynamic> _overlayProgress(
      String id, Map<String, dynamic> base, List<Map<String, dynamic>> queue) {
    final mutation = queue
        .where((m) =>
            m['entityType'] == 'learning_progress' && m['entityId'] == id)
        .firstOrNull;
    if (mutation == null) return Map<String, dynamic>.from(base);
    final payload = mutation['payload'] as Map;
    return {
      ...base,
      'id': id,
      'unitId': id,
      'status': payload['status'],
      'source': 'self_reported',
      // Retain the acknowledged version; an unsent change has no new version.
      'version': payload['expectedVersion'],
      'pending_sync': true,
      'acknowledged': false,
      'mutationId': mutation['id'],
      'queueStatus': mutation['queueStatus'],
      'sync_conflict': mutation['queueStatus'] == 'conflict',
      'lastError': mutation['lastError'],
      'queuedAt': mutation['queuedAt'],
    };
  }

  Future<Map<String, dynamic>> setProgress(
          String unitId, String status, int expectedVersion) =>
      _serial(() async {
        if (!_uuid.hasMatch(unitId) ||
            !_statuses.contains(status) ||
            expectedVersion < 0) {
          throw const ApiException(400, 'invalid_learning_progress');
        }
        if ((await pendingFor(unitId)).isNotEmpty) {
          throw const ApiException(409, 'sync_pending');
        }
        final mutationId = newMutationId();
        final mutation = <String, dynamic>{
          'id': mutationId,
          'entityId': unitId,
          'entityType': 'learning_progress',
          'operation': 'set_progress',
          'expectedVersion': expectedVersion,
          'payload': {
            'status': status,
            'source': 'self_reported',
            'mutationId': mutationId,
            'expectedVersion': expectedVersion,
          },
        };
        // Do not use optimisticItem: that helper writes planner caches.
        await store.enqueue(mutation);
        try {
          final accepted = await _send(mutation);
          return {'queued': false, 'progress': accepted};
        } catch (error) {
          _checkScope();
          if (!isOfflineFailure(error)) rethrow;
          final known = await store.readList(_progressCache);
          return {
            'queued': true,
            'progress': _overlayProgress(
                unitId,
                known.where((p) => p['unitId'] == unitId).firstOrNull ??
                    _initialProgress(unitId),
                await store.readQueue()),
          };
        }
      });

  Future<Map<String, dynamic>> _send(Map<String, dynamic> mutation) async {
    _checkScope();
    final payload = Map<String, dynamic>.from(mutation['payload'] as Map);
    final unitId = mutation['entityId'] as String;
    final expected = payload['expectedVersion'];
    if (mutation['entityType'] != 'learning_progress' ||
        mutation['operation'] != 'set_progress' ||
        !_uuid.hasMatch(unitId) ||
        payload['mutationId'] != mutation['id'] ||
        expected is! int ||
        expected < 0 ||
        payload['source'] != 'self_reported' ||
        !_statuses.contains(payload['status'])) {
      throw const ApiException(422, 'invalid_learning_mutation');
    }
    final Map<String, dynamic> ack;
    try {
      ack = await api.requestJson(
          'PUT', '/v1/me/learning-progress/${Uri.encodeComponent(unitId)}',
          body: payload);
      _checkScope();
    } catch (error) {
      _checkScope();
      if (error is ApiException && error.statusCode == 409) {
        await store.markQueued(mutation['id'] as String, 'conflict',
            error: error.code);
      }
      rethrow;
    }
    if (ack['mutationId'] != mutation['id'] ||
        ack['unitId'] != unitId ||
        ack['status'] != payload['status'] ||
        ack['source'] != 'self_reported' ||
        ack['version'] is! int ||
        ack['version'] != expected + 1 ||
        !_timestamp(ack['updatedAt']) ||
        !_timestamp(ack['acceptedAt'])) {
      throw const ApiException(502, 'invalid_sync_acknowledgement');
    }
    final progress = _serverProgress(ack, unitId);
    await store.acknowledge(mutation['id'] as String,
        item: progress,
        acceptedAt: ack['acceptedAt'] as String,
        cacheKey: _progressCache);
    return progress;
  }

  Future<void> flush() => _serial(() async {
        for (final pending in await store.readQueue()) {
          if (pending['entityType'] != 'learning_progress') continue;
          if (pending['queueStatus'] == 'conflict') {
            throw const ApiException(409, 'sync_conflict');
          }
          if (pending['queueStatus'] != 'queued') continue;
          try {
            await _send(pending);
          } catch (error) {
            if (isOfflineFailure(error)) return;
            rethrow;
          }
        }
      });

  /// User-selected server value; preserve the rejected report in the durable
  /// recovery journal in the same write that removes it from the queue.
  Future<void> resolveUsingServer(String unitId) => _serial(() async {
        if ((await pendingFor(unitId)).isEmpty) return;
        final response =
            await api.requestJson('GET', '/v1/me/learning-progress');
        _checkScope();
        final list = response['progress'];
        if (list is! List || list.any((p) => p is! Map)) {
          throw const ApiException(502, 'invalid_learning_progress');
        }
        final matches = list.where((p) => p['unitId'] == unitId).toList();
        if (matches.length != 1) {
          throw const ApiException(502, 'invalid_learning_progress');
        }
        final progress = _serverProgress(matches.single, unitId);
        // The shared store's legacy journal helper filters by entity ID. Do
        // not let an independently named planner/session record be discarded
        // by a choice that concerns only lesson progress.
        final queue = await store.readQueue();
        if (queue.any((m) =>
            m['entityId'] == unitId &&
            m['entityType'] != 'learning_progress')) {
          throw const ApiException(409, 'sync_entity_collision');
        }
        await store.discardEntityChanges(unitId,
            serverItem: progress, cacheKey: _progressCache);
      });
}
