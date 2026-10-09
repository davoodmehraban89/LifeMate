import 'session_store_native.dart'
    if (dart.library.js_interop) 'session_store_web.dart' as platform;

abstract class SessionStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> clear();
}

SessionStore createSessionStore() =>
    SerializedSessionStore(platform.PlatformSessionStore());
const sessionStorageKey = 'lifeguide.refresh_session.v1';

class SerializedSessionStore implements SessionStore {
  SerializedSessionStore(this.inner);
  final SessionStore inner;
  static Future<void> _tail = Future.value();
  Future<T> _locked<T>(Future<T> Function() operation) {
    final next = _tail.then((_) => operation());
    _tail = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  @override
  Future<String?> read() => _locked(inner.read);
  @override
  Future<void> write(String value) => _locked(() => inner.write(value));
  @override
  Future<void> clear() => _locked(inner.clear);
}
