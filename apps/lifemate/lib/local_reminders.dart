import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show StringCharacters;

final androidLocalReminders = AndroidLocalReminderPort();

final class LocalReminder {
  const LocalReminder(
      {required this.id,
      required this.planItemId,
      required this.scheduledAt,
      required this.companionName,
      required this.ownerUserId,
      required this.serverAcknowledged,
      this.pendingMutation = false});
  final String id, planItemId, companionName, ownerUserId;
  final DateTime scheduledAt;
  final bool serverAcknowledged, pendingMutation;
}

final class LocalReminderStatus {
  const LocalReminderStatus(
      {required this.supported,
      required this.permissionGranted,
      required this.active,
      required this.scheduledCount,
      this.timing = 'approximate',
      this.activeScope,
      this.validUntil,
      this.exactAlarmSupported = false,
      this.canScheduleExactAlarms = false});
  final bool supported,
      permissionGranted,
      active,
      exactAlarmSupported,
      canScheduleExactAlarms;
  final int scheduledCount;
  final String timing;
  final String? activeScope;
  final DateTime? validUntil;
}

abstract interface class LocalReminderPort {
  Future<void> activate(String scope, {required DateTime validUntil});
  Future<void> replace(String scope, List<LocalReminder> reminders,
      {required String currentUserId});
  Future<void> suppressPlanItems(String scope, Set<String> ids);
  Future<void> deactivate();
  Future<LocalReminderStatus> status();
  Future<LocalReminderStatus> requestPermission();
  Future<LocalReminderStatus> requestExactAlarmAccess();
}

/// One shared lifecycle boundary. Native storage contains no task text or tokens.
/// [LocalReminderStatus.active] means device opt-in, even after lease expiry.
final class AndroidLocalReminderPort implements LocalReminderPort {
  AndroidLocalReminderPort({MethodChannel? channel, DateTime Function()? now})
      : _channel = channel ?? const MethodChannel('lifeguide/local_reminders'),
        _now = now ?? DateTime.now;
  final MethodChannel _channel;
  final DateTime Function() _now;
  Future<void>? _tail;
  int _generation = 0;
  String? _scope;
  DateTime? _validUntil;
  bool get _native =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  static final _uuid = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$');
  static final _controls =
      RegExp(r'[\x00-\x1f\x7f-\x9f\u202a-\u202e\u2066-\u2069]');
  static const _unsupported = LocalReminderStatus(
      supported: false,
      permissionGranted: false,
      active: false,
      scheduledCount: 0);
  Future<void> _serial(Future<void> Function() work) async {
    final previous = _tail;
    final release = Completer<void>();
    _tail = release.future;
    if (previous != null) await previous;
    try {
      await work();
    } finally {
      if (identical(_tail, release.future)) _tail = null;
      release.complete();
    }
  }

  Future<void> _write(String method, [Map<String, Object>? arguments]) async {
    if (await _channel
            .invokeMethod<bool>(method, arguments)
            .timeout(const Duration(seconds: 5)) !=
        true) {
      throw StateError('Native reminder operation failed.');
    }
  }

  @override
  Future<void> activate(String scope, {required DateTime validUntil}) async {
    if (!_native) return;
    final now = _now().toUtc();
    if (scope.isEmpty ||
        scope.length > 1024 ||
        _controls.hasMatch(scope) ||
        !validUntil.isUtc ||
        !validUntil.isAfter(now) ||
        validUntil.difference(now) > const Duration(hours: 24)) {
      throw ArgumentError(
          'A future UTC lease of at most 24 hours is required.');
    }
    final generation = ++_generation;
    _scope = scope;
    _validUntil = validUntil;
    await _serial(() async {
      if (generation != _generation) return;
      try {
        await _write('activate', {
          'scope': scope,
          'validUntilEpochMs': validUntil.millisecondsSinceEpoch
        });
      } catch (_) {
        if (generation == _generation) {
          _scope = null;
          _validUntil = null;
        }
        rethrow;
      }
    });
  }

  @override
  Future<void> replace(String scope, List<LocalReminder> reminders,
      {required String currentUserId}) async {
    if (!_native) return;
    final until = _validUntil;
    if (_scope != scope || until == null || !until.isAfter(_now().toUtc())) {
      throw StateError('Reminder scope or lease no longer matches.');
    }
    if (!_uuid.hasMatch(currentUserId) || reminders.length > 128) {
      throw ArgumentError('Invalid owner or reminder count.');
    }
    final ids = <String>{}, payload = <Map<String, Object>>[];
    final now = _now().toUtc();
    for (final row in reminders) {
      if (!_uuid.hasMatch(row.id) ||
          !_uuid.hasMatch(row.planItemId) ||
          !ids.add(row.id) ||
          row.ownerUserId != currentUserId ||
          !row.serverAcknowledged ||
          row.pendingMutation ||
          !row.scheduledAt.isUtc ||
          row.companionName.trim().isEmpty ||
          row.companionName.characters.length > 40 ||
          row.companionName.length > 4096 ||
          _controls.hasMatch(row.companionName)) {
        throw ArgumentError(
            'Only acknowledged owner records may schedule reminders.');
      }
      if (!row.scheduledAt.isAfter(now) || row.scheduledAt.isAfter(until)) {
        continue;
      }
      payload.add({
        'id': row.id,
        'planItemId': row.planItemId,
        'scheduledAtEpochMs': row.scheduledAt.millisecondsSinceEpoch,
        'companionName': row.companionName.trim()
      });
    }
    final generation = _generation;
    await _serial(() async {
      if (generation != _generation || _scope != scope) return;
      await _write('replace', {'scope': scope, 'reminders': payload});
    });
  }

  @override
  Future<void> suppressPlanItems(String scope, Set<String> ids) async {
    if (!_native || ids.isEmpty) return;
    if (_scope != null && _scope != scope) {
      throw StateError('Reminder scope no longer matches.');
    }
    if (ids.length > 128 || ids.any((id) => !_uuid.hasMatch(id))) {
      throw ArgumentError('Invalid plan IDs.');
    }
    final generation = _generation;
    await _serial(() async {
      if (generation != _generation) return;
      try {
        await _write(
            'suppressPlanItems', {'scope': scope, 'planItemIds': ids.toList()});
      } on MissingPluginException {/* Older builds have no native reminders. */}
    });
  }

  @override
  Future<void> deactivate() async {
    ++_generation;
    _scope = null;
    _validUntil = null;
    if (!_native) return;
    await _serial(() async {
      try {
        await _write('deactivate');
      } on MissingPluginException {/* Older builds have no native reminders. */}
    });
  }

  Future<LocalReminderStatus> _status(String method) async {
    if (!_native) return _unsupported;
    try {
      final raw = await _channel
          .invokeMapMethod<String, dynamic>(method)
          .timeout(Duration(seconds: method == 'requestPermission' ? 90 : 5));
      if (raw == null ||
          raw['supported'] != true ||
          raw['permissionGranted'] is! bool ||
          raw['active'] is! bool ||
          raw['scheduledCount'] is! int ||
          (raw['scheduledCount'] as int) < 0 ||
          !['exact', 'approximate'].contains(raw['timing'])) {
        throw StateError('Invalid native reminder status.');
      }
      return LocalReminderStatus(
          supported: true,
          permissionGranted: raw['permissionGranted'] == true,
          active: raw['active'] == true,
          scheduledCount: raw['scheduledCount'] as int,
          timing: raw['timing'] as String,
          activeScope: raw['activeScope'] is String
              ? raw['activeScope'] as String
              : null,
          validUntil: raw['validUntilEpochMs'] is int
              ? DateTime.fromMillisecondsSinceEpoch(
                  raw['validUntilEpochMs'] as int,
                  isUtc: true)
              : null,
          exactAlarmSupported: raw['exactAlarmSupported'] == true,
          canScheduleExactAlarms: raw['canScheduleExactAlarms'] == true);
    } on MissingPluginException {
      return _unsupported;
    }
  }

  @override
  Future<LocalReminderStatus> status() => _status('status');
  @override
  Future<LocalReminderStatus> requestPermission() =>
      _status('requestPermission');
  @override
  Future<LocalReminderStatus> requestExactAlarmAccess() =>
      _status('requestExactAlarmAccess');
}
