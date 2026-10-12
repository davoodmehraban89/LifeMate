import 'dart:async';
import 'dart:convert';

import 'api.dart';
import 'offline_store.dart';
import 'plan_sync.dart' show newMutationId;

/// Private goal intent is persisted before delivery, scoped to API+account.
/// Acknowledgement and current server state are distinct on an old retry.
class LearningGoalSync {
  LearningGoalSync(this.api, {OfflineStore? store})
      : store = store ?? OfflineStore.forApi(api);
  final HttpIdentityApi api;
  final OfflineStore store;
  static final _tails = <String, Future<void>>{};
  static const _cache = 'learning_goals';
  static const _meta = 'learning_goals_received';
  static final _uuid = RegExp(r'^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$',
      caseSensitive: false);
  void _scope() {
    if (api.cacheNamespace != store.scope) {
      throw const ApiException(401, 'cache_scope_closed');
    }
  }

  Future<T> _serial<T>(Future<T> Function() run) {
    final previous = _tails[store.scope], release = Completer<void>();
    _tails[store.scope] = release.future;
    return (() async {
      if (previous != null) await previous;
      try {
        _scope();
        await store.readQueue();
        _scope();
        final result = await run();
        _scope();
        return result;
      } finally {
        if (identical(_tails[store.scope], release.future)) {
          _tails.remove(store.scope);
        }
        release.complete();
      }
    })();
  }

  static bool _time(dynamic value) =>
      value is String &&
      RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(value) &&
      DateTime.tryParse(value) != null;
  Map<String, dynamic> _goal(dynamic raw) {
    if (raw is! Map ||
        raw['id'] is! String ||
        !_uuid.hasMatch(raw['id']) ||
        raw['owner_user_id'] != api.currentUserId ||
        raw['title'] is! String ||
        (raw['title'] as String).trim().isEmpty ||
        (raw['title'] as String).length > 240 ||
        (raw['title'] as String).contains('\u0000') ||
        (raw['target'] != null &&
            (raw['target'] is! String ||
                (raw['target'] as String).length > 1000 ||
                (raw['target'] as String).contains('\u0000'))) ||
        (raw['subject_id'] != null &&
            (raw['subject_id'] is! String ||
                !_uuid.hasMatch(raw['subject_id'] as String))) ||
        raw['version'] is! int ||
        raw['version'] < 1 ||
        !['active', 'completed', 'archived'].contains(raw['status']) ||
        !_time(raw['created_at']) ||
        !_time(raw['updated_at']) ||
        (raw['status'] == 'archived'
            ? !_time(raw['archived_at'])
            : raw['archived_at'] != null)) {
      throw const ApiException(502, 'invalid_learning_goal');
    }
    return {...Map<String, dynamic>.from(raw), 'pending_sync': false};
  }

  Future<List<Map<String, dynamic>>> pending() async {
    _scope();
    final queue = await store.readQueue();
    _scope();
    return queue.where((m) => m['entityType'] == 'learning_goal').toList();
  }

  Future<Map<String, dynamic>> read() => _serial(() async {
        var offline = false;
        late List<Map<String, dynamic>> goals;
        try {
          final response = await api.requestJson('GET', '/v1/learning/goals');
          _scope();
          if (response['items'] is! List || !_time(response['fetchedAt'])) {
            throw const ApiException(502, 'invalid_learning_goals');
          }
          goals = (response['items'] as List).map(_goal).toList();
          if (goals.map((g) => g['id']).toSet().length != goals.length ||
              goals.any((g) => g['status'] == 'archived')) {
            throw const ApiException(502, 'invalid_learning_goals');
          }
          await store.writeList(_cache, goals);
          await store.writeList(_meta, [
            {'fetchedAt': response['fetchedAt']}
          ]);
        } catch (error) {
          _scope();
          if (error is ApiException && error.statusCode == 403) {
            // A denied read must never fall back to yesterday's private list.
            // Retain intent in the shared journal for explicit recovery.
            await store.writeList(_cache, []);
            await store.writeList(_meta, []);
            _scope();
          }
          if (!isOfflineFailure(error)) rethrow;
          goals = (await store.readList(_cache)).map(_goal).toList();
          offline = true;
        }
        final byId = {
          for (final g in goals) g['id']: Map<String, dynamic>.from(g)
        };
        final mutations = await pending();
        for (final mutation in mutations) {
          _validateMutation(mutation);
          final body = Map<String, dynamic>.from(mutation['payload'] as Map);
          final id = mutation['entityId'];
          final previous = byId[id];
          if (previous == null && mutation['operation'] != 'create') continue;
          byId[id] = {
            ...?previous,
            'id': id,
            'owner_user_id': api.currentUserId,
            'title': body['title'] ?? previous?['title'],
            'target': body.containsKey('target')
                ? body['target']
                : previous?['target'],
            'status': body['status'] ?? previous?['status'] ?? 'active',
            'version': body['expectedVersion'],
            'pending_sync': true,
            'pending_archive': mutation['operation'] == 'archive',
            'queueStatus': mutation['queueStatus'],
          };
        }
        final meta = await store.readList(_meta);
        _scope();
        final visible =
            byId.values.where((g) => g['status'] != 'archived').toList();
        final visibleIds = visible.map((g) => g['id']).toSet();
        return {
          'items': visible,
          'offline': offline,
          'fetchedAt': meta.firstOrNull?['fetchedAt'],
          'pendingCount': mutations.length,
          'unlistedPending': [
            for (final mutation in mutations)
              if (!visibleIds.contains(mutation['entityId']))
                {
                  'id': mutation['entityId'],
                  'operation': mutation['operation'],
                  'queueStatus': mutation['queueStatus']
                }
          ]
        };
      });
  Future<Map<String, dynamic>> create(
      {required String title, String? target, String? subjectId}) {
    final id = newMutationId();
    return _mutate(id, 'create', {
      'id': id,
      'title': title,
      'target': target,
      'subjectId': subjectId,
      'expectedVersion': 0
    });
  }

  Future<Map<String, dynamic>> update(
          String id, int version, Map<String, dynamic> changes) =>
      _mutate(id, 'update', {...changes, 'expectedVersion': version});
  Future<Map<String, dynamic>> archive(String id, int version) =>
      _mutate(id, 'archive', {'expectedVersion': version});
  Future<Map<String, dynamic>> _mutate(
      String id, String operation, Map<String, dynamic> raw) {
    id = id.toLowerCase();
    final normalized = {...raw};
    if (normalized['title'] is String) {
      normalized['title'] = (normalized['title'] as String).trim();
    }
    if (normalized['target'] is String) {
      final target = (normalized['target'] as String).trim();
      normalized['target'] = target.isEmpty ? null : target;
    }
    if (normalized['subjectId'] is String) {
      normalized['subjectId'] =
          (normalized['subjectId'] as String).toLowerCase();
    }
    final body =
        jsonDecode(jsonEncode({...normalized, 'mutationId': newMutationId()}))
            as Map<String, dynamic>;
    return _serial(() async {
      _validateBody(id, operation, body);
      if ((await pending()).any((m) => m['entityId'] == id)) {
        throw const ApiException(409, 'goal_sync_pending');
      }
      final mutation = {
        'id': body['mutationId'],
        'entityId': id,
        'entityType': 'learning_goal',
        'operation': operation,
        'expectedVersion': body['expectedVersion'],
        'payload': body
      };
      await store.enqueue(mutation);
      try {
        return {'queued': false, 'goal': await _send(mutation)};
      } catch (error) {
        _scope();
        if (!isOfflineFailure(error)) rethrow;
        return {'queued': true, 'goalId': id};
      }
    });
  }

  void _validateBody(String id, String operation, Map body,
      {String code = 'invalid_goal_input'}) {
    final allowed = {
      'mutationId',
      'expectedVersion',
      if (operation == 'create') 'id',
      if (operation != 'archive') ...['title', 'target', 'subjectId', 'status'],
    };
    final version = body['expectedVersion'];
    if (!_uuid.hasMatch(id) ||
        !['create', 'update', 'archive'].contains(operation) ||
        body.keys.any((key) => !allowed.contains(key)) ||
        body['mutationId'] is! String ||
        !_uuid.hasMatch(body['mutationId'] as String) ||
        version is! int ||
        version < 0 ||
        version >= 2147483647 ||
        (operation == 'create'
            ? (version != 0 || body['id'] != id || !body.containsKey('title'))
            : version == 0) ||
        (operation == 'update' &&
            !['title', 'target', 'subjectId', 'status']
                .any(body.containsKey)) ||
        (body.containsKey('title') &&
            (body['title'] is! String ||
                (body['title'] as String).trim().isEmpty ||
                (body['title'] as String).length > 240 ||
                (body['title'] as String).contains('\u0000'))) ||
        (body['target'] != null &&
            (body['target'] is! String ||
                (body['target'] as String).length > 1000 ||
                (body['target'] as String).contains('\u0000'))) ||
        (body['subjectId'] != null &&
            (body['subjectId'] is! String ||
                !_uuid.hasMatch(body['subjectId'] as String))) ||
        (body.containsKey('status') &&
            !['active', 'completed'].contains(body['status']))) {
      throw ApiException(400, code);
    }
  }

  void _validateMutation(Map<String, dynamic> mutation) {
    if (mutation['entityType'] != 'learning_goal' ||
        mutation['entityId'] is! String ||
        mutation['operation'] is! String ||
        mutation['payload'] is! Map ||
        mutation['payload']['mutationId'] != mutation['id'] ||
        mutation['payload']['expectedVersion'] != mutation['expectedVersion']) {
      throw const ApiException(422, 'invalid_goal_mutation');
    }
    _validateBody(mutation['entityId'] as String,
        mutation['operation'] as String, mutation['payload'] as Map,
        code: 'invalid_goal_mutation');
  }

  Future<Map<String, dynamic>> _send(Map<String, dynamic> mutation) async {
    _validateMutation(mutation);
    final body = Map<String, dynamic>.from(mutation['payload'] as Map);
    final id = mutation['entityId'], operation = mutation['operation'];
    if (mutation['entityType'] != 'learning_goal' ||
        !['create', 'update', 'archive'].contains(operation) ||
        body['mutationId'] != mutation['id'] ||
        id is! String ||
        !_uuid.hasMatch(id) ||
        body['expectedVersion'] is! int ||
        body['expectedVersion'] != mutation['expectedVersion'] ||
        (operation == 'create' &&
            (body['id'] != id || body['expectedVersion'] != 0))) {
      throw const ApiException(422, 'invalid_goal_mutation');
    }
    late Map<String, dynamic> response;
    try {
      response = await api.requestJson(
          operation == 'create'
              ? 'POST'
              : operation == 'update'
                  ? 'PATCH'
                  : 'DELETE',
          '/v1/learning/goals${operation == 'create' ? '' : '/$id'}',
          body: body);
      _scope();
    } catch (error) {
      _scope();
      if (error is ApiException && error.statusCode == 403) {
        await store.writeList(_cache, []);
        await store.writeList(_meta, []);
        _scope();
      }
      if (error is ApiException && error.statusCode == 409) {
        await store.markQueued(mutation['id'] as String, 'conflict',
            error: error.code);
      }
      rethrow;
    }
    final ack = response['acknowledgement'];
    final goal = _goal(response['goal']);
    if (goal['id'] != id ||
        ack is! Map ||
        ack['mutationId'] != mutation['id'] ||
        ack['goalId'] != id ||
        ack['operation'] != operation ||
        ack['appliedVersion'] != body['expectedVersion'] + 1 ||
        goal['version'] < ack['appliedVersion'] ||
        !_time(ack['acceptedAt']) ||
        !['accepted', 'already_applied'].contains(ack['status'])) {
      throw const ApiException(502, 'invalid_goal_acknowledgement');
    }
    if (goal['version'] == ack['appliedVersion']) {
      if ((operation == 'archive' && goal['status'] != 'archived') ||
          ['title', 'target', 'subjectId', 'status'].any((key) =>
              body.containsKey(key) &&
              goal[key == 'subjectId' ? 'subject_id' : key] != body[key])) {
        throw const ApiException(502, 'invalid_goal_acknowledgement');
      }
    }
    await store.acknowledge(mutation['id'] as String,
        item: goal, acceptedAt: ack['acceptedAt'] as String, cacheKey: _cache);
    _scope();
    return goal;
  }

  Future<void> flush() => _serial(() async {
        for (final mutation in await pending()) {
          if (mutation['queueStatus'] == 'conflict') {
            throw const ApiException(409, 'goal_version_conflict');
          }
          await _send(mutation);
        }
      });
  Future<void> useServer(String id) => _serial(() async {
        final response = await api.requestJson('GET', '/v1/learning/goals/$id');
        _scope();
        final server = _goal(response);
        if (server['id'] != id ||
            (await store.readQueue()).any((m) =>
                m['entityId'] == id && m['entityType'] != 'learning_goal')) {
          throw const ApiException(409, 'sync_entity_collision');
        }
        await store.discardEntityChanges(id,
            serverItem: server, cacheKey: _cache, entityType: 'learning_goal');
        _scope();
      });
}
