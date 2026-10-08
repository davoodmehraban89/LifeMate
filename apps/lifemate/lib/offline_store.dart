import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'local_write_guard.dart';

bool isOfflineFailure(Object error) =>
    error is TimeoutException ||
    error is http.ClientException ||
    (error is ApiException &&
        error.statusCode == 0 &&
        const {'network_unavailable', 'request_timeout'}.contains(error.code));

/// One isolate's serialization, with native protection across Android engines.
class OfflineSession {
  Future<void>? _tail;
  bool _uncertain = false;
  final _guard = const LocalWriteGuard();
  Future<void> available() async {
    try {
      if (!_uncertain) _uncertain = await _guard.getBlocked();
    } catch (_) {
      _uncertain = true;
    }
    if (_uncertain) {
      throw const ApiException(500, 'local_storage_restart_required');
    }
  }

  Future<T> run<T>(Future<T> Function() operation) {
    final previous = _tail;
    final release = Completer<void>();
    _tail = release.future;
    Future<T> execute() async {
      if (previous != null) await previous;
      try {
        await available();
        return await operation();
      } finally {
        if (identical(_tail, release.future)) _tail = null;
        release.complete();
      }
    }

    return execute();
  }

  Future<void> write(
      SharedPreferencesAsync prefs, String key, String raw) async {
    try {
      final token = await _guard.beginWrite();
      await prefs.setString(key, raw);
      await _guard.completeWrite(token);
    } catch (_) {
      _uncertain = true;
      throw const ApiException(500, 'local_storage_restart_required');
    }
  }
}

/// Cache and pending queue scoped to authenticated server and user.
/// Shared data and permissions remain server-authoritative.
class OfflineStore {
  OfflineStore.forNamespace(this.scope, {OfflineSession? session})
      : _session = session ?? _processSession,
        _generation = _generations[scope] ?? 0 {
    if (scope.isEmpty || scope.length > 4096) {
      throw ArgumentError('Invalid cache scope');
    }
  }
  factory OfflineStore.forApi(IdentityApi api) {
    if (api is HttpIdentityApi) {
      final scope = api.cacheNamespace;
      if (scope == null) {
        throw const ApiException(401, 'authenticated_cache_required');
      }
      return OfflineStore.forNamespace(scope);
    }
    return OfflineStore.forNamespace('injected-api:${identityHashCode(api)}');
  }
  static final _processSession = OfflineSession();
  static final _generations = <String, int>{};
  final int _generation;
  final OfflineSession _session;
  final String scope;
  String get _key =>
      'lifeguide.offline.v2.${base64Url.encode(utf8.encode(scope))}';
  static Future<void> clearNamespace(String scope) {
    // Invalidate old stores immediately, including futures waiting for the lock.
    _generations[scope] = (_generations[scope] ?? 0) + 1;
    final current = OfflineStore.forNamespace(scope);
    return current._session.run(() => current._save(current._empty()));
  }

  void _checkGeneration() {
    if ((_generations[scope] ?? 0) != _generation) {
      throw const ApiException(401, 'cache_scope_closed');
    }
  }

  Map<String, dynamic> _empty() => {
        'version': 2,
        'scope': scope,
        'caches': <String, dynamic>{},
        'queue': <dynamic>[],
        'lastSyncAt': null,
        'lastAckAt': null
      };
  Future<Map<String, dynamic>> _read() async {
    _checkGeneration();
    final String? raw;
    try {
      raw = await SharedPreferencesAsync().getString(_key);
    } catch (_) {
      throw const ApiException(500, 'local_storage_failed');
    }
    await _session.available();
    _checkGeneration();
    if (raw == null) return _empty();
    try {
      final doc = jsonDecode(raw) as Map<String, dynamic>;
      if (doc['version'] != 2 ||
          doc['scope'] != scope ||
          doc['caches'] is! Map ||
          doc['queue'] is! List) {
        throw const FormatException();
      }
      for (final entry in doc['queue'] as List) {
        if (entry is! Map ||
            entry['id'] is! String ||
            entry['payload'] is! Map ||
            entry['entityId'] is! String) {
          throw const FormatException();
        }
      }
      return doc;
    } catch (_) {
      throw const ApiException(500, 'local_data_corrupt');
    }
  }

  Future<void> _save(Map<String, dynamic> doc) async {
    _checkGeneration();
    final raw = jsonEncode(doc);
    if (utf8.encode(raw).length > 2 * 1024 * 1024 ||
        (doc['queue'] as List).length > 100) {
      throw const ApiException(413, 'offline_capacity_exceeded');
    }
    await _session.write(SharedPreferencesAsync(), _key, raw);
  }

  Future<T> _mutate<T>(T Function(Map<String, dynamic>) change) =>
      _session.run(() async {
        final doc = await _read();
        final result = change(doc);
        await _save(doc);
        return result;
      });
  Future<void> writeList(String key, List<Map<String, dynamic>> value) =>
      _mutate((doc) {
        (doc['caches'] as Map)[key] = key == 'planner' || key == 'today'
            ? _overlayPending(doc, value, todayOnly: key == 'today')
            : value;
        doc['lastSyncAt'] = DateTime.now().toUtc().toIso8601String();
      });
  Future<List<Map<String, dynamic>>> readList(String key) =>
      _session.run(() async {
        final doc = await _read();
        final list = (doc['caches'] as Map)[key] as List? ?? [];
        return list
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
      });
  Future<void> cacheToday(List<Map<String, dynamic>> items) =>
      writeList('today', items);
  Future<List<Map<String, dynamic>>> readToday() => readList('today');
  Future<void> cachePlanner(List<Map<String, dynamic>> items) =>
      writeList('planner', items);
  Future<List<Map<String, dynamic>>> readPlanner() => readList('planner');
  Future<void> cacheSchool(List<Map<String, dynamic>> items) =>
      writeList('school', items);
  Future<List<Map<String, dynamic>>> readSchool() => readList('school');
  Future<List<Map<String, dynamic>>> readQueue() =>
      _session.run(() async => ((await _read())['queue'] as List)
          .map((m) => Map<String, dynamic>.from(m as Map))
          .toList());
  Future<int> pendingCount() async => (await readQueue()).length;
  Future<DateTime?> _timestamp(String field) => _session.run(
      () async => DateTime.tryParse((await _read())[field] as String? ?? ''));
  Future<DateTime?> readLastSync() => _timestamp('lastSyncAt');
  Future<DateTime?> readLastAck() => _timestamp('lastAckAt');
  Future<void> enqueue(Map<String, dynamic> mutation,
          {Map<String, dynamic>? optimisticItem}) =>
      _mutate((doc) {
        final id = mutation['id'];
        if (id is! String ||
            !RegExp(r'^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')
                .hasMatch(id) ||
            mutation['entityId'] is! String ||
            mutation['payload'] is! Map) {
          throw const ApiException(400, 'invalid_offline_mutation');
        }
        final queue = doc['queue'] as List;
        final existing = queue.where((m) => (m as Map)['id'] == id);
        if (existing.isNotEmpty) {
          final prior = Map<String, dynamic>.from(existing.single as Map)
            ..remove('queueStatus')
            ..remove('queuedAt')
            ..remove('lastError');
          if (jsonEncode(prior) != jsonEncode(mutation)) {
            throw const ApiException(409, 'mutation_id_reused');
          }
          return;
        }
        queue.add({
          ...mutation,
          'queueStatus': 'queued',
          'queuedAt': DateTime.now().toUtc().toIso8601String()
        });
        if (optimisticItem != null) _saveOptimistic(doc, optimisticItem);
      });
  Future<void> markQueued(String id, String status, {String? error}) =>
      _mutate((doc) {
        for (final entry in doc['queue'] as List) {
          if ((entry as Map)['id'] == id) {
            entry['queueStatus'] = status;
            entry['lastError'] = error;
          }
        }
      });
  Future<void> removeQueued(Set<String> ids) => _mutate((doc) {
        doc['queue'] = (doc['queue'] as List)
            .where((m) => !ids.contains((m as Map)['id']))
            .toList();
      });
  Future<void> acknowledge(String id,
          {Map<String, dynamic>? item, String? acceptedAt, String? cacheKey}) =>
      _mutate((doc) {
        doc['queue'] = (doc['queue'] as List)
            .where((m) => (m as Map)['id'] != id)
            .toList();
        doc['lastAckAt'] =
            acceptedAt ?? DateTime.now().toUtc().toIso8601String();
        if (item != null) {
          for (final key
              in cacheKey == null ? ['planner', 'today'] : [cacheKey]) {
            final list = (doc['caches'] as Map)[key] as List? ?? [];
            final index =
                list.indexWhere((x) => (x as Map)['id'] == item['id']);
            if (index >= 0) {
              list[index] = item;
            } else if (key != 'today') {
              list.add(item);
            }
            (doc['caches'] as Map)[key] = key == 'planner' || key == 'today'
                ? _overlayPending(
                    doc,
                    list
                        .map((x) => Map<String, dynamic>.from(x as Map))
                        .toList(),
                    todayOnly: key == 'today')
                : list;
          }
        }
      });
  void _saveOptimistic(Map<String, dynamic> doc, Map<String, dynamic> item) {
    final list = (doc['caches'] as Map)['planner'] as List? ?? [];
    final index = list.indexWhere((x) => (x as Map)['id'] == item['id']);
    if (index >= 0) {
      list[index] = item;
    } else {
      list.add(item);
    }
    (doc['caches'] as Map)['planner'] = list;
  }

  Future<void> saveOptimisticItem(Map<String, dynamic> item) =>
      _mutate((doc) => _saveOptimistic(doc, item));
  List<Map<String, dynamic>> _overlayPending(
      Map<String, dynamic> doc, List<Map<String, dynamic>> items,
      {bool todayOnly = false}) {
    final result = items.map((x) => Map<String, dynamic>.from(x)).toList();
    final prior = ((doc['caches'] as Map)['planner'] as List? ?? [])
        .map((x) => Map<String, dynamic>.from(x as Map));
    for (final raw in doc['queue'] as List) {
      final mutation = raw as Map;
      if (mutation['entityType'] != 'plan_item' ||
          mutation['queueStatus'] == 'rejected') {
        continue;
      }
      final id = mutation['entityId'];
      final index = result.indexWhere((x) => x['id'] == id);
      final old = prior.where((x) => x['id'] == id).firstOrNull;
      final base =
          index < 0 ? old ?? <String, dynamic>{'id': id} : result[index];
      final overlay = optimisticPlanItem(base, mutation);
      if (todayOnly && index < 0) {
        final date = DateTime.tryParse(
            (overlay['due_at'] ?? overlay['starts_at'] ?? '').toString());
        final now = DateTime.now();
        if (date == null ||
            date.toLocal().year != now.year ||
            date.toLocal().month != now.month ||
            date.toLocal().day != now.day) {
          continue;
        }
      }
      if (index < 0) {
        result.add(overlay);
      } else {
        result[index] = overlay;
      }
    }
    return result;
  }

  Future<void> clear() => clearNamespace(scope);

  Future<List<Map<String, dynamic>>> readDiscardedChanges() =>
      _session.run(() async {
        final journal = (await _read())['discardedChanges'];
        if (journal == null) return [];
        if (journal is! List ||
            journal.any((m) => m is! Map || m['payload'] is! Map)) {
          throw const ApiException(500, 'local_data_corrupt');
        }
        return journal.map((m) => Map<String, dynamic>.from(m as Map)).toList();
      });

  Future<void> discardEntityChanges(String entityId,
          {Map<String, dynamic>? serverItem, String? cacheKey}) =>
      _mutate((doc) {
        if (serverItem != null &&
            (serverItem['id'] != entityId ||
                int.tryParse(serverItem['version'].toString()) == null)) {
          throw const ApiException(400, 'invalid_server_item');
        }
        final rawJournal = doc['discardedChanges'];
        if (rawJournal != null && rawJournal is! List) {
          throw const ApiException(500, 'local_data_corrupt');
        }
        final queue = doc['queue'] as List;
        final removed =
            queue.where((m) => (m as Map)['entityId'] == entityId).toList();
        if (removed.isEmpty) return;
        final title = removed.reversed
            .map((m) => (m as Map)['payload'] as Map)
            .map((p) => p['title'])
            .whereType<String>()
            .firstOrNull;
        final discardedAt = DateTime.now().toUtc().toIso8601String();
        doc['discardedChanges'] = [
          ...?rawJournal as List?,
          for (final mutation in removed)
            {
              ...mutation as Map,
              'discardedAt': discardedAt,
              'recoveryTitle': title
            }
        ];
        doc['queue'] =
            queue.where((m) => (m as Map)['entityId'] != entityId).toList();
        for (final key
            in cacheKey == null ? ['planner', 'today'] : [cacheKey]) {
          final list = (doc['caches'] as Map)[key] as List? ?? [];
          final hadItem = list.any((m) => (m as Map)['id'] == entityId);
          final replacement =
              list.where((m) => (m as Map)['id'] != entityId).toList();
          if (serverItem != null && (key != 'today' || hadItem)) {
            replacement.add(Map<String, dynamic>.from(serverItem));
          }
          (doc['caches'] as Map)[key] = replacement;
        }
      });
}

Map<String, dynamic> optimisticPlanItem(
    Map<String, dynamic> base, Map mutation) {
  final payload = Map<String, dynamic>.from(mutation['payload'] as Map);
  const columns = {
    'subjectId': 'subject_id',
    'durationMinutes': 'duration_minutes',
    'gradePoints': 'grade_points',
    'gradeOutOf': 'grade_out_of',
    'parentItemId': 'parent_item_id',
    'dueAt': 'due_at',
    'startsAt': 'starts_at',
    'endsAt': 'ends_at',
    'familyId': 'family_id',
    'schoolSubjectId': 'school_subject_id',
    'plannedDurationSeconds': 'planned_duration_seconds'
  };
  final expected = int.tryParse(mutation['expectedVersion'].toString()) ?? 0;
  return {
    ...base,
    for (final entry in payload.entries)
      columns[entry.key] ?? entry.key: entry.value,
    'version': mutation['operation'] == 'create' ? 1 : expected + 1,
    'pending_sync': true,
    'acknowledged': false,
    'sync_conflict': mutation['queueStatus'] == 'conflict'
  };
}
