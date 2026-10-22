// Never distribute. Reuses the ordinary planner UI and DEFAULT SQLite database.
// Only the fresh-emulator host harness may seed fictional data before launch.
import 'package:flutter/foundation.dart';

import 'package:lifemate/standalone_main.dart' as personal;

void main() {
  if (!kDebugMode ||
      kIsWeb ||
      defaultTargetPlatform != TargetPlatform.android ||
      !const bool.fromEnvironment('LIFEGUIDE_STANDALONE') ||
      !const bool.fromEnvironment('LIFEGUIDE_PERSONAL_RECOVERY_QA')) {
    throw StateError('Synthetic Android recovery QA only.');
  }
  personal.main();
}
