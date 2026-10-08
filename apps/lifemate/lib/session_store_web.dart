import 'dart:js_interop';
import 'session_store.dart';

@JS('localStorage')
external _Storage get _storage;
extension type _Storage(JSObject _) implements JSObject {
  external String? getItem(String key);
  external void setItem(String key, String value);
  external void removeItem(String key);
}

/// One opaque refresh token, bound to its configured HTTPS endpoint. Access
/// tokens stay in memory. This requires the host's HTTPS and strict CSP gates.
class PlatformSessionStore implements SessionStore {
  @override
  Future<String?> read() async => _storage.getItem(sessionStorageKey);
  @override
  Future<void> write(String value) async =>
      _storage.setItem(sessionStorageKey, value);
  @override
  Future<void> clear() async => _storage.removeItem(sessionStorageKey);
}
