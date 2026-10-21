import 'package:flutter/foundation.dart';

import 'model.dart';
import 'reminders.dart';
import 'store.dart';

/// Reads authoritative SQLite before installing any device-only alarms.
class StandaloneReminderCoordinator extends ChangeNotifier {
  StandaloneReminderCoordinator(
      {StandaloneReminderPort? port, DateTime Function()? now})
      : _port = port ?? StandaloneReminderPort(),
        _now = now ?? DateTime.now;
  final StandaloneReminderPort _port;
  final DateTime Function() _now;
  StandaloneReminderStatus? status;
  String? error;
  int _revision = 0;
  bool _changing = false;

  Future<(StandaloneProfile, List<LocalPersonalReminder>)> _read(
      StandaloneStore store) async {
    final profile = await store.profile();
    if (profile == null) throw StateError('Create the local profile first.');
    final now = _now();
    final records = await store.pendingReminders(
        from: now, through: now.add(const Duration(days: 28)));
    return (
      profile,
      records
          .map((row) => LocalPersonalReminder(
              id: row.id,
              planItemId: row.id,
              profileId: profile.id,
              scheduledAt: row.remindAt!.toUtc(),
              completed: row.completed,
              archived: row.archived))
          .toList()
    );
  }

  Future<void> _guard(Future<void> Function() work) async {
    try {
      await work();
      error = null;
    } catch (_) {
      status = null;
      error =
          'وضعیت یادآوری تأیید نشد. تنظیمات و مجوز اعلان را بررسی کن و دوباره تلاش کن.';
      try {
        await _port.cancelOnStorageFailure();
      } catch (_) {/* Error remains visible. */}
      rethrow;
    } finally {
      notifyListeners();
    }
  }

  Future<void> refresh(StandaloneStore store) => _guard(() async {
        if (_changing) return;
        final revision = _revision;
        final profile = await store.profile();
        if (_changing || revision != _revision) return;
        if (profile == null) {
          await _port.suspendUntilReconcile();
          status = await _port.status();
          return;
        }
        final (owner, rows) = await _read(store);
        if (_changing || revision != _revision) return;
        status = await _port.reconcile(rows,
            companionName: owner.companionName, profileId: owner.id);
      });

  Future<void> beforeChange(StandaloneStore store) {
    _changing = true;
    ++_revision;
    return _guard(() async {
      final profile = await store.profile();
      await _port.suspendUntilReconcile(profileId: profile?.id);
      status = null;
    });
  }

  Future<void> afterChange(StandaloneStore store) {
    _changing = false;
    ++_revision;
    return refresh(store);
  }

  Future<void> enable(StandaloneStore store) => _guard(() async {
        if (_changing) throw StateError('A planner write is in progress.');
        final (owner, rows) = await _read(store);
        status = await _port.enable(rows,
            companionName: owner.companionName, profileId: owner.id);
      });

  Future<void> disable(StandaloneStore store) => _guard(() async {
        final profile = await store.profile();
        if (profile == null) throw StateError('No local profile.');
        await _port.disable(profileId: profile.id);
        status = await _port.status(profileId: profile.id);
      });

  Future<void> requestExactAccess(StandaloneStore store) => _guard(() async {
        await _port.requestExactAlarmAccess();
        // Returning from Android settings triggers another fresh read on resume.
        await refresh(store);
      });

  /// A settings-screen failure is not a storage failure. Keep the existing
  /// choice and schedule; lifecycle resume performs the authoritative refresh.
  Future<void> openNotificationSettings() async {
    try {
      await _port.openNotificationSettings();
      error = null;
    } catch (_) {
      error =
          'تنظیمات اعلان باز نشد. از تنظیمات گوشی، بخش اعلان‌های لایف‌گاید را باز کن.';
      rethrow;
    } finally {
      notifyListeners();
    }
  }

  Future<void> cancelOnStorageFailure() => _port.cancelOnStorageFailure();
}
