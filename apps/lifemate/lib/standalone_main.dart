import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'standalone/app.dart';
import 'standalone/reminder_coordinator.dart';
import 'standalone/reminder_settings.dart';
import 'standalone/store.dart';

/// Separate debug-only device edition. No HTTP/auth/runtime-URL imports.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (!const bool.fromEnvironment('LIFEGUIDE_STANDALONE') ||
      !kDebugMode ||
      kIsWeb ||
      defaultTargetPlatform != TargetPlatform.android) {
    runApp(const MaterialApp(
        home: Scaffold(
            body: Center(
                child: Text(
                    'این ورودی فقط برای بستهٔ آزمایشی لایف‌گاید شخصی است.')))));
    return;
  }
  final reminders = StandaloneReminderCoordinator();
  runApp(StandaloneApp(
    openStore: () async {
      StandaloneStore store;
      try {
        store = await StandaloneStore.open();
      } catch (_) {
        try {
          await reminders.cancelOnStorageFailure();
        } catch (_) {/* No success claimed. */}
        rethrow;
      }
      try {
        await reminders.refresh(store);
      } catch (_) {/* Planner remains usable; settings shows the failure. */}
      return store;
    },
    onBeforePlansChange: reminders.beforeChange,
    onPlansChanged: reminders.afterChange,
    onResumed: reminders.refresh,
    reminderSettingsBuilder: (context, store) =>
        StandaloneReminderSettings(store: store, coordinator: reminders),
  ));
}
