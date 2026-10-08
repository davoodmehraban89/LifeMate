import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

/// Represents one native Android process, independent of Dart session instances.
final class MockNativeLocalWriteGuard {
  String? _pending;
  int _sequence = 0;

  bool get blocked => _pending != null;

  String beginWrite() {
    if (blocked) {
      throw PlatformException(code: 'local_storage_restart_required');
    }
    return _pending = 'mock-owned-token-${++_sequence}';
  }

  bool completeWrite(String? token) {
    if (token == null || token != _pending) return false;
    _pending = null;
    return true;
  }

  Future<Object?> handle(MethodCall call) async => switch (call.method) {
        'getBlocked' => blocked,
        'beginWrite' => beginWrite(),
        'completeWrite' => completeWrite(call.arguments as String?),
        _ => throw MissingPluginException(),
      };
}

/// Only tests can simulate killing the native process; the app has no reset API.
MockNativeLocalWriteGuard resetNativeLocalWriteGuard() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final native = MockNativeLocalWriteGuard();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
          const MethodChannel('lifeguide/local_write_guard'), native.handle);
  return native;
}

/// Unit/widget plugin substitutes only. Real Android integration never calls this.
void resetLocalPreferences([Map<String, Object> values = const {}]) {
  resetNativeLocalWriteGuard();
  SharedPreferences.setMockInitialValues(
      values); // legacy profile/production cache
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.withData(
          values); // local DataStore adapter
}
