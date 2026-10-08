import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android process lifetime protection, independent of a Flutter engine/isolate.
/// An unconfirmed write can only be recovered by killing the Android process.
final class LocalWriteGuard {
  const LocalWriteGuard();

  static const _channel = MethodChannel('lifeguide/local_write_guard');
  bool get _native =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<bool> getBlocked() async {
    if (!_native) return false;
    // A missing/invalid native response must never grant access to cached data.
    return await _channel.invokeMethod<bool>('getBlocked') ?? true;
  }

  Future<String?> beginWrite() async {
    if (!_native) return null;
    final token = await _channel.invokeMethod<String>('beginWrite');
    if (token == null || token.isEmpty) {
      throw StateError('Native local write guard did not grant ownership');
    }
    return token;
  }

  Future<void> completeWrite(String? token) async {
    if (!_native) return;
    if (token == null ||
        await _channel.invokeMethod<bool>('completeWrite', token) != true) {
      throw StateError('Native local write guard did not confirm completion');
    }
  }
}
