import 'api.dart';
import 'local_reminders.dart';
import 'offline_store.dart';
import 'plan_sync.dart';
import 'device_reminder_preferences.dart';

/// Online owner-only reminder reconciliation. Cached data never renews a lease.
final class DeviceReminderCoordinator {
  DeviceReminderCoordinator(this.api,
      {LocalReminderPort? port, DateTime Function()? now, OfflineStore? store})
      : port = port ?? androidLocalReminders,
        _now = now ?? DateTime.now,
        _store = store;
  final HttpIdentityApi api;
  final LocalReminderPort port;
  final DateTime Function() _now;
  final OfflineStore? _store;
  static int _intentEpoch = 0;
  static final _uuid = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$');

  @override
  String toString() =>
      'DeviceReminderCoordinator'; // Never include scope or credentials.

  Future<LocalReminderStatus> status() => port.status();
  Future<LocalReminderStatus> disable() async {
    ++_intentEpoch;
    await port.deactivate();
    return port.status();
  }

  Future<LocalReminderStatus> requestExactAlarmAccess() =>
      port.requestExactAlarmAccess();

  Future<LocalReminderStatus> enable({String? companionName}) async {
    final intent = ++_intentEpoch;
    final allowed = await port.requestPermission();
    if (!allowed.supported || !allowed.permissionGranted) {
      throw const ApiException(0, 'device_notifications_not_allowed');
    }
    return _load(companionName, intent);
  }

  Future<LocalReminderStatus> reconcile({String? companionName}) async {
    final intent = _intentEpoch;
    final current = await port.status();
    if (!current.active || current.activeScope != api.cacheNamespace) {
      return current;
    }
    return _load(companionName, intent);
  }

  Future<LocalReminderStatus> _load(String? companionName, int intent) async {
    final scope = api.cacheNamespace;
    final owner = api.currentUserId;
    final token = api.accessToken;
    final revision = api.sessionRevision;
    if (scope == null || owner == null || token == null) {
      throw const ApiException(401, 'authenticated_cache_required');
    }
    void requireSameSession() {
      if (intent != _intentEpoch) {
        throw const ApiException(409, 'device_notification_intent_changed');
      }
      if (api.cacheNamespace != scope ||
          api.currentUserId != owner ||
          api.sessionRevision != revision ||
          api.accessToken == null) {
        throw const ApiException(401, 'session_expired');
      }
    }

    final nickname =
        companionName ?? await DeviceReminderPreferences().read(scope);
    requireSameSession();
    final from = _now().toUtc();
    final path = Uri(path: '/v1/planner-reminders', queryParameters: {
      'from': from.toIso8601String(),
      'to': from.add(const Duration(hours: 24)).toIso8601String(),
    }).toString();
    final result = await api.requestJson('GET', path);
    requireSameSession();
    final received = _now().toUtc();
    final asOf = result['asOf'] is String
        ? DateTime.tryParse(result['asOf'] as String)
        : null;
    final raw = result['reminders'];
    if (asOf == null ||
        asOf.isBefore(received.subtract(const Duration(minutes: 2))) ||
        asOf.isAfter(received.add(const Duration(minutes: 1))) ||
        raw is! List ||
        raw.length > 128) {
      throw const ApiException(502, 'invalid_api_response');
    }
    final rows = <LocalReminder>[];
    final ids = <String>{};
    for (final entry in raw) {
      if (entry is! Map ||
          entry['id'] is! String ||
          entry['plan_item_id'] is! String ||
          !_uuid.hasMatch(entry['id'] as String) ||
          !_uuid.hasMatch(entry['plan_item_id'] as String) ||
          !ids.add(entry['id'] as String) ||
          entry['owner_user_id'] != owner ||
          entry['scheduled_for'] is! String) {
        throw const ApiException(502, 'invalid_api_response');
      }
      final at = DateTime.tryParse(entry['scheduled_for'] as String);
      if (at == null) throw const ApiException(502, 'invalid_api_response');
      rows.add(LocalReminder(
          id: entry['id'] as String,
          planItemId: entry['plan_item_id'] as String,
          scheduledAt: at.toUtc(),
          companionName: nickname,
          ownerUserId: owner,
          serverAcknowledged: true));
    }
    final store = _store ?? OfflineStore.forApi(api);
    await PlanSync(api, store: store, reminders: port)
        .withLocalMutationLock(() async {
      requireSameSession();
      final pending =
          (await store.readQueue()).map((entry) => entry['entityId']).toSet();
      requireSameSession();
      final until = _now().toUtc().add(const Duration(hours: 24));
      await port.activate(scope, validUntil: until);
      requireSameSession();
      await port.replace(scope,
          rows.where((row) => !pending.contains(row.planItemId)).toList(),
          currentUserId: owner);
    });
    requireSameSession();
    return port.status();
  }
}
