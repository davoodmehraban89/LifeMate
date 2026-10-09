import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'session_store.dart';

class PlatformSessionStore implements SessionStore {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  @override
  Future<String?> read() => _storage.read(key: sessionStorageKey);
  @override
  Future<void> write(String value) =>
      _storage.write(key: sessionStorageKey, value: value);
  @override
  Future<void> clear() => _storage.delete(key: sessionStorageKey);
}
