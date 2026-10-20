import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show StringCharacters;
import 'package:shared_preferences/shared_preferences.dart';

/// A committed record from this device's personal planner, never a server ACK.
final class LocalPersonalReminder {
  const LocalPersonalReminder(
      {required this.id,
      required this.planItemId,
      required this.profileId,
      required this.scheduledAt,
      this.completed = false,
      this.archived = false});
  final String id, planItemId, profileId;
  final DateTime scheduledAt;
  final bool completed, archived;
}

final class StandaloneReminderStatus {
  const StandaloneReminderStatus(
      {required this.supported,
      required this.permissionGranted,
      required this.active,
      required this.scheduledCount,
      this.enabled = false,
      this.timing = 'approximate',
      this.activeScope,
      this.validUntil,
      this.exactAlarmSupported = false,
      this.canScheduleExactAlarms = false,
      this.eligibleCount = 0,
      this.selectedCount = 0});
  final bool supported, permissionGranted, active, enabled;
  final bool exactAlarmSupported, canScheduleExactAlarms;
  final int scheduledCount, eligibleCount, selectedCount;
  final String timing;
  final String? activeScope;
  final DateTime? validUntil;
  static const coverageDays = 28;
  static const maximumReminders = 128;
}

/// Dedicated device edition port. Opening/reconciling never grants consent or
/// requests permission. Only [enable] can turn the two persisted choices ON.
final class StandaloneReminderPort {
  StandaloneReminderPort(
      {MethodChannel? channel,
      SharedPreferencesAsync? preferences,
      DateTime Function()? now})
      : _channel = channel ??
            const MethodChannel('lifeguide/device_planner_reminders'),
        _preferences = preferences ?? SharedPreferencesAsync(),
        _now = now ?? DateTime.now;

  final MethodChannel _channel;
  final SharedPreferencesAsync _preferences;
  final DateTime Function() _now;
  Future<void>? _tail;
  int _generation = 0;
  String? _profileId;
  int _eligibleCount = 0, _selectedCount = 0;
  static final _uuid = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$');
  static final _controls =
      RegExp(r'[\x00-\x1f\x7f-\x9f\u202a-\u202e\u2066-\u2069]');
  static const _unsupported = StandaloneReminderStatus(
      supported: false,
      permissionGranted: false,
      active: false,
      scheduledCount: 0);
  bool get _native =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  String _scope(String id) {
    if (!_uuid.hasMatch(id)) throw ArgumentError('Invalid local profile ID.');
    return 'device-planner:v1:$id';
  }

  String _key(String id) {
    _scope(id);
    return 'lifeguide.device_planner.reminders_enabled.v1.$id';
  }

  Future<T> _serial<T>(Future<T> Function() work) async {
    final previous = _tail;
    final release = Completer<void>();
    _tail = release.future;
    if (previous != null) await previous;
    try {
      return await work();
    } finally {
      if (identical(_tail, release.future)) _tail = null;
      release.complete();
    }
  }

  Future<void> _write(String method, [Map<String, Object>? args]) async {
    if (!_native) return;
    final result = await _channel
        .invokeMethod<dynamic>(method, args)
        .timeout(const Duration(seconds: 5));
    if (result is Map && result['supported'] == false) {
      throw UnsupportedError('Device planner reminders are unavailable.');
    }
    if (result != true) throw StateError('Device reminder operation failed.');
  }

  Future<void> _deactivate() async {
    try {
      await _write('deactivate');
    } on MissingPluginException {
      /* No native alarms exist in older builds. */
    } on UnsupportedError {/* The online edition cannot own these alarms. */}
  }

  Future<StandaloneReminderStatus> _nativeStatus(
      [String method = 'status']) async {
    if (!_native) return _unsupported;
    try {
      final raw = await _channel
          .invokeMapMethod<String, dynamic>(method)
          .timeout(Duration(seconds: method == 'requestPermission' ? 90 : 5));
      if (raw == null || raw['supported'] == false) return _unsupported;
      if (raw['supported'] != true ||
          raw['enabled'] is! bool ||
          raw['permissionGranted'] is! bool ||
          raw['active'] is! bool ||
          raw['scheduledCount'] is! int ||
          (raw['scheduledCount'] as int) < 0 ||
          (raw['scheduledCount'] as int) > 128 ||
          !['exact', 'approximate'].contains(raw['timing'])) {
        throw StateError('Invalid device reminder status.');
      }
      return StandaloneReminderStatus(
          supported: true,
          enabled: raw['enabled'] == true,
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

  StandaloneReminderStatus _view(StandaloneReminderStatus raw, bool enabled) =>
      StandaloneReminderStatus(
          supported: raw.supported,
          enabled: enabled && raw.enabled,
          permissionGranted: raw.permissionGranted,
          active: raw.active,
          scheduledCount: raw.scheduledCount,
          timing: raw.timing,
          activeScope: raw.activeScope,
          validUntil: raw.validUntil,
          exactAlarmSupported: raw.exactAlarmSupported,
          canScheduleExactAlarms: raw.canScheduleExactAlarms,
          eligibleCount: _eligibleCount,
          selectedCount: _selectedCount);
  Future<StandaloneReminderStatus> _readStatus(String? id,
      [String method = 'status']) async {
    final raw = await _nativeStatus(method);
    final enabled = id != null && await _preferences.getBool(_key(id)) == true;
    return _view(raw, enabled);
  }

  Future<StandaloneReminderStatus> status({String? profileId}) {
    if (profileId != null) {
      _scope(profileId);
      _profileId = profileId;
    }
    return _serial(() => _readStatus(profileId ?? _profileId));
  }

  Future<StandaloneReminderStatus> requestPermission() =>
      _serial(() => _readStatus(_profileId, 'requestPermission'));
  Future<StandaloneReminderStatus> requestExactAlarmAccess() =>
      _serial(() => _readStatus(_profileId, 'requestExactAlarmAccess'));

  List<Map<String, Object>> _select(
      List<LocalPersonalReminder> rows, String name, String profileId) {
    _scope(profileId);
    final trimmed = name.trim();
    if (trimmed.isEmpty ||
        name.length > 4096 ||
        name.characters.length > 40 ||
        _controls.hasMatch(name)) {
      throw ArgumentError('Invalid companion name.');
    }
    final now = _now().toUtc();
    final through = now.add(const Duration(days: 28));
    final ids = <String>{}, eligible = <LocalPersonalReminder>[];
    for (final row in rows) {
      if (!_uuid.hasMatch(row.id) ||
          !_uuid.hasMatch(row.planItemId) ||
          !ids.add(row.id) ||
          row.profileId != profileId ||
          !row.scheduledAt.isUtc) {
        throw ArgumentError(
            'Only committed records of this local profile may schedule.');
      }
      if (!row.completed &&
          !row.archived &&
          row.scheduledAt.isAfter(now) &&
          !row.scheduledAt.isAfter(through)) {
        eligible.add(row);
      }
    }
    eligible.sort((a, b) {
      final time = a.scheduledAt.compareTo(b.scheduledAt);
      return time != 0 ? time : a.id.compareTo(b.id);
    });
    _eligibleCount = eligible.length;
    final selected = eligible.take(128).toList();
    _selectedCount = selected.length;
    return selected
        .map((row) => <String, Object>{
              'id': row.id,
              'planItemId': row.planItemId,
              'scheduledAtEpochMs': row.scheduledAt.millisecondsSinceEpoch,
              'companionName': trimmed
            })
        .toList();
  }

  Future<void> _schedule(List<Map<String, Object>> payload, String profileId,
      int generation) async {
    if (generation != _generation) return;
    await _deactivate();
    if (generation != _generation) return;
    await _write('activate', {
      'scope': _scope(profileId),
      'validUntilEpochMs':
          _now().toUtc().add(const Duration(days: 31)).millisecondsSinceEpoch
    });
    if (generation != _generation) return;
    await _write('replace', {'scope': _scope(profileId), 'reminders': payload});
  }

  Future<StandaloneReminderStatus> enable(List<LocalPersonalReminder> rows,
      {required String companionName, required String profileId}) {
    final payload = _select(rows, companionName, profileId);
    _profileId = profileId;
    final generation = ++_generation;
    return _serial(() async {
      if (generation != _generation) return _readStatus(profileId);
      final initial = await _nativeStatus('requestPermission');
      if (!initial.supported ||
          !initial.permissionGranted ||
          generation != _generation) {
        return _view(initial, false);
      }
      try {
        await _write('setEnabled', {'enabled': true});
        if (generation != _generation) return await _readStatus(profileId);
        await _preferences.setBool(_key(profileId), true);
        await _schedule(payload, profileId, generation);
      } catch (error, stack) {
        try {
          await _write('setEnabled', {'enabled': false});
        } catch (_) {
          await _deactivate();
        }
        try {
          await _preferences.setBool(_key(profileId), false);
        } catch (_) {/* Surface the original failure. */}
        Error.throwWithStackTrace(error, stack);
      }
      return _readStatus(profileId);
    });
  }

  /// Call only with a fresh, successful read of the committed local store.
  Future<StandaloneReminderStatus> reconcile(List<LocalPersonalReminder> rows,
      {required String companionName, required String profileId}) {
    _scope(profileId);
    _profileId = profileId;
    final generation = ++_generation;
    return _serial(() async {
      final raw = await _nativeStatus();
      final optedIn = await _preferences.getBool(_key(profileId)) == true;
      if (generation != _generation) return _view(raw, optedIn);
      if (!raw.supported) return _unsupported;
      if (!optedIn || !raw.enabled) {
        _eligibleCount = 0;
        _selectedCount = 0;
        if (!optedIn && raw.enabled) {
          await _write('setEnabled', {'enabled': false});
        } else {
          await _deactivate();
        }
        return _readStatus(profileId);
      }
      try {
        final payload = _select(rows, companionName, profileId);
        await _schedule(payload, profileId, generation);
      } catch (error, stack) {
        await _deactivate();
        Error.throwWithStackTrace(error, stack);
      }
      return _readStatus(profileId);
    });
  }

  /// Invalidate queued work before a store write. Consent survives suspension;
  /// only a fresh committed-store reconciliation can install alarms again.
  Future<void> suspendUntilReconcile({String? profileId}) {
    if (profileId != null) {
      _scope(profileId);
      _profileId = profileId;
    }
    ++_generation;
    _selectedCount = 0;
    return _serial(_deactivate);
  }

  Future<void> cancelOnStorageFailure({String? profileId}) =>
      suspendUntilReconcile(profileId: profileId);

  Future<void> disable({required String profileId}) {
    _scope(profileId);
    _profileId = profileId;
    ++_generation;
    _eligibleCount = 0;
    _selectedCount = 0;
    return _serial(() async {
      Object? failure;
      StackTrace? trace;
      try {
        await _write('setEnabled', {'enabled': false});
      } on MissingPluginException {
        /* Unsupported older build. */
      } on UnsupportedError {/* Online edition. */} catch (error, stack) {
        failure = error;
        trace = stack;
      }
      // Cancellation is attempted independently of either preference write.
      try {
        await _deactivate();
      } catch (error, stack) {
        failure ??= error;
        trace ??= stack;
      }
      try {
        await _preferences.setBool(_key(profileId), false);
      } catch (error, stack) {
        failure ??= error;
        trace ??= stack;
      }
      if (failure != null) Error.throwWithStackTrace(failure, trace!);
    });
  }
}
