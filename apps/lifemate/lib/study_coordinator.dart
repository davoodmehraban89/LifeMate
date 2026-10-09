import 'api.dart';
import 'offline_store.dart';
import 'plan_sync.dart';

/// Mutations are persisted before sending. Pending events retain their exact
/// body and version, and must be acknowledged before another event is sent.
class StudySync {
  StudySync(this.api, {OfflineStore? store})
      : store = store ?? OfflineStore.forApi(api);
  final HttpIdentityApi api;
  final OfflineStore store;
  Future<void>? _flush;
  Future<MutationOutcome> start(String planItemId) async {
    final sessionId = newMutationId();
    final mutationId = newMutationId();
    return _change(
        'study_start',
        sessionId,
        {
          'id': sessionId,
          'mutationId': mutationId,
          'planItemId': planItemId,
          'source': 'timer',
          'startedAt': DateTime.now().toUtc().toIso8601String()
        },
        mutationId,
        0);
  }

  Future<MutationOutcome> event(
      Map<String, dynamic> session, String action) async {
    final id = newMutationId();
    final version = int.tryParse(session['version'].toString()) ?? 0;
    return _change(
        'study_event',
        session['id'].toString(),
        {
          'mutationId': id,
          'expectedVersion': version,
          'action': action,
          'occurredAt': DateTime.now().toUtc().toIso8601String()
        },
        id,
        version);
  }

  Future<MutationOutcome> archive(Map<String, dynamic> session) async {
    final id = newMutationId();
    final version = int.tryParse(session['version'].toString()) ?? 0;
    return _change('study_archive', session['id'].toString(),
        {'mutationId': id, 'expectedVersion': version}, id, version);
  }

  Future<MutationOutcome> _change(String operation, String entityId,
      Map<String, dynamic> payload, String id, int version) async {
    if ((await store.readQueue())
        .any((m) => m['entityType'] == 'study_session')) {
      throw const ApiException(409, 'sync_pending');
    }
    final mutation = <String, dynamic>{
      'id': id,
      'entityType': 'study_session',
      'entityId': entityId,
      'operation': operation,
      'payload': payload,
      'expectedVersion': version
    };
    await store.enqueue(mutation);
    try {
      return await _send(mutation);
    } catch (error) {
      if (isOfflineFailure(error)) return const MutationOutcome(queued: true);
      rethrow;
    }
  }

  Future<MutationOutcome> _send(Map<String, dynamic> mutation) async {
    final body = Map<String, dynamic>.from(mutation['payload'] as Map);
    final id = mutation['entityId'].toString();
    Map<String, dynamic> response;
    try {
      response = switch (mutation['operation']) {
        'study_start' => await api.startStudySession(body),
        'study_event' => await api.recordStudySessionEvent(id, body),
        'study_archive' => await api.archiveStudySession(id, body),
        _ => throw const ApiException(422, 'invalid_study_mutation'),
      };
    } catch (error) {
      if (error is ApiException && error.statusCode == 409) {
        await store.markQueued(mutation['id'].toString(), 'conflict',
            error: error.code);
      }
      rethrow;
    }
    final ack = response['acknowledgement'];
    if (ack is! Map ||
        ack['mutationId'] != mutation['id'] ||
        !['accepted', 'already_applied'].contains(ack['status'])) {
      throw const ApiException(502, 'invalid_sync_acknowledgement');
    }
    final raw = response['session'];
    final acceptedAt = ack['acceptedAt'];
    final expected = int.tryParse(mutation['expectedVersion'].toString()) ?? 0;
    if (raw is! Map ||
        raw['id'] != mutation['entityId'] ||
        raw['version'] is! int ||
        raw['version'] < expected + 1 ||
        acceptedAt is! String ||
        DateTime.tryParse(acceptedAt) == null) {
      throw const ApiException(502, 'invalid_sync_acknowledgement');
    }
    final session = Map<String, dynamic>.from(raw);
    await store.acknowledge(mutation['id'].toString(),
        item: session, acceptedAt: acceptedAt, cacheKey: 'study.sessions');
    return MutationOutcome(queued: false, item: session);
  }

  Future<void> flush() =>
      _flush ??= _flushQueue().whenComplete(() => _flush = null);
  Future<void> _flushQueue() async {
    for (final m in await store.readQueue()) {
      if (m['entityType'] != 'study_session') continue;
      if (m['queueStatus'] == 'conflict') {
        throw const ApiException(409, 'sync_conflict');
      }
      if (m['queueStatus'] != 'queued') continue;
      try {
        await _send(m);
      } catch (error) {
        if (isOfflineFailure(error)) return;
        rethrow;
      }
    }
  }
}
