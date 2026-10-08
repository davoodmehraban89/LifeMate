import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

/// Unit/widget plugin substitutes only. Real Android integration never calls this.
void resetLocalPreferences([Map<String, Object> values = const {}]) {
  SharedPreferences.setMockInitialValues(
      values); // legacy profile/production cache
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.withData(
          values); // local DataStore adapter
}
