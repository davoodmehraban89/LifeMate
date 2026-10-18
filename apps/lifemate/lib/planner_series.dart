import 'dart:async';
import 'dart:convert';

import 'api.dart';
import 'offline_store.dart';
import 'plan_sync.dart' show newMutationId;

class PlannerSeriesOutcome {
  const PlannerSeriesOutcome({required this.queued, required this.id});
  final bool queued;
  final String id;
}

/// An unsent series is a durable draft, never a fabricated server occurrence.
/// The UUID and frozen payload survive a lost response and process restart.
class PlannerSeriesSync {
  PlannerSeriesSync(this.api, {OfflineStore? store})
      : store = store ?? OfflineStore.forApi(api),
        _scope = api.cacheNamespace;
  final HttpIdentityApi api;
  final OfflineStore store;
  final String? _scope;
  static final _tails = <String, Future<void>>{};

  void _checkScope() {
    if (_scope == null || api.cacheNamespace != _scope) {
      throw const ApiException(401, 'cache_scope_closed');
    }
  }

  Future<T> _serial<T>(Future<T> Function() action) async {
    final previous = _tails[store.scope];
    final release = Completer<void>();
    _tails[store.scope] = release.future;
    if (previous != null) await previous;
    try {
      _checkScope();
      return await action();
    } finally {
      if (identical(_tails[store.scope], release.future)) {
        _tails.remove(store.scope);
      }
      release.complete();
    }
  }

  Future<PlannerSeriesOutcome> create(Map<String, dynamic> payload,
          {String? id}) =>
      _serial(() async {
        final seriesId = id ?? newMutationId();
        final body = <String, dynamic>{...payload, 'id': seriesId};
        final existing = (await store.readQueue())
            .where((m) =>
                m['entityType'] == 'planner_series' &&
                m['entityId'] == seriesId)
            .firstOrNull;
        if (existing != null) {
          if (_canonical(existing['payload']) != _canonical(body)) {
            throw const ApiException(409, 'mutation_id_reused');
          }
          _throwTerminal(existing);
        } else {
          // An already acknowledged retry cannot create another series.
          final accepted = (await store.readList('planner_series'))
              .where((s) => s['id'] == seriesId)
              .firstOrNull;
          if (accepted != null) {
            if (_canonical(accepted['_create_payload']) != _canonical(body)) {
              throw const ApiException(409, 'mutation_id_reused');
            }
            return PlannerSeriesOutcome(queued: false, id: seriesId);
          }
          await store.enqueue({
            'id': seriesId,
            'entityType': 'planner_series',
            'entityId': seriesId,
            'operation': 'create',
            'payload': body,
          });
        }
        await _flush();
        return PlannerSeriesOutcome(
            queued: (await store.readQueue()).any((m) => m['id'] == seriesId),
            id: seriesId);
      });

  Future<void> flush() => _serial(_flush);

  void _throwTerminal(Map<String, dynamic> queued) {
    if (queued['queueStatus'] == 'conflict' ||
        queued['queueStatus'] == 'rejected') {
      throw ApiException(queued['queueStatus'] == 'conflict' ? 409 : 422,
          queued['lastError']?.toString() ?? 'sync_rejected');
    }
  }

  Future<void> _flush() async {
    for (final queued in await store.readQueue()) {
      if (queued['entityType'] != 'planner_series') continue;
      // A rejected draft stays visible in the recovery journal; it must not
      // prevent unrelated plans from loading or other drafts from syncing.
      if (queued['queueStatus'] == 'conflict' ||
          queued['queueStatus'] == 'rejected') {
        continue;
      }
      _checkScope();
      try {
        final response = await api.requestJson('POST', '/v1/planner-series',
            body: Map<String, dynamic>.from(queued['payload'] as Map));
        _checkScope();
        final series = response['series'];
        final items = response['items'];
        if (series is! Map ||
            series['id'] != queued['entityId'] ||
            series['owner_user_id'] != api.currentUserId ||
            (int.tryParse(series['version'].toString()) ?? 0) < 1 ||
            items is! List ||
            items.any((item) =>
                item is! Map ||
                item['id'] is! String ||
                item['series_id'] != series['id'] ||
                item['owner_user_id'] != api.currentUserId)) {
          throw const ApiException(502, 'invalid_series_acknowledgement');
        }
        await store.acknowledge(queued['id'] as String,
            item: {
              ...Map<String, dynamic>.from(series),
              '_create_payload': queued['payload']
            },
            cacheKey: 'planner_series');
        // Fresh occurrence rows merge with other queued item edits in the store.
        final planner = await store.readPlanner();
        final byId = {for (final row in planner) row['id']: row};
        for (final row in items) {
          byId[row['id']] = Map<String, dynamic>.from(row);
        }
        await store.cachePlanner(byId.values.toList());
      } catch (error) {
        if (isOfflineFailure(error)) return;
        if (error is ApiException &&
            error.statusCode >= 400 &&
            error.statusCode < 500 &&
            error.statusCode != 401 &&
            error.statusCode != 429) {
          await store.markQueued(queued['id'] as String,
              error.statusCode == 409 ? 'conflict' : 'rejected',
              error: error.code);
        }
        rethrow;
      }
    }
  }

  /// Repeated materialization only fills missing dates; occurrence edits stay.
  Future<void> materialize(DateTime from, DateTime to) async {
    _checkScope();
    final response = await api.requestJson('GET', '/v1/planner-series');
    _checkScope();
    final series = response['series'];
    if (series is! List) {
      throw const ApiException(502, 'invalid_series_response');
    }
    for (final row in series) {
      if (row is! Map ||
          row['id'] is! String ||
          row['owner_user_id'] != api.currentUserId) {
        throw const ApiException(502, 'invalid_series_response');
      }
      if (row['status'] == 'archived' || row['archived_at'] != null) continue;
      await api.requestJson(
          'POST', '/v1/planner-series/${row['id']}/materialize',
          body: {'from': plannerDate(from), 'to': plannerDate(to)});
      _checkScope();
    }
  }
}

String _canonical(dynamic value) => jsonEncode(_sorted(value));
dynamic _sorted(dynamic value) {
  if (value is Map) {
    final keys = value.keys.map((k) => k.toString()).toList()..sort();
    return {for (final key in keys) key: _sorted(value[key])};
  }
  if (value is List) return value.map(_sorted).toList();
  return value;
}

String plannerDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

List<DateTime> plannerWeekDays(DateTime date) {
  final day = DateTime(date.year, date.month, date.day);
  final saturday = day.subtract(Duration(days: (day.weekday + 1) % 7));
  return List.generate(7, (i) => saturday.add(Duration(days: i)));
}
