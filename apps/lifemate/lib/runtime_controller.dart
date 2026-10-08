import 'package:flutter/foundation.dart';
import 'api.dart';
import 'runtime_config.dart';
import 'session_store.dart';

class RuntimeController extends ChangeNotifier {
  RuntimeController(
      {RuntimeConfigStore? configStore,
      SessionStore? sessionStore,
      this.onScopeDiscarded,
      HttpIdentityApi Function(RuntimeConfig)? apiFactory})
      : _configStore = configStore ?? RuntimeConfigStore(),
        _sessionStore = sessionStore ?? createSessionStore(),
        _apiFactory = apiFactory;
  final RuntimeConfigStore _configStore;
  final SessionStore _sessionStore;
  final Future<void> Function(String)? onScopeDiscarded;
  final HttpIdentityApi Function(RuntimeConfig)? _apiFactory;
  RuntimeConfig config = RuntimeConfig();
  HttpIdentityApi? api;
  Object? error;
  bool initialized = false;
  bool _disposed = false;
  int _generation = 0;
  String? get cacheNamespace => api?.cacheNamespace;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  HttpIdentityApi _createApi(RuntimeConfig config) {
    final next = _apiFactory?.call(config) ??
        HttpIdentityApi(
            baseUrl: config.apiBaseUrl!, sessionStore: _sessionStore);
    next.onSessionChanged = _notify;
    next.onScopeDiscarded = onScopeDiscarded;
    return next;
  }

  Future<void> initialize() async {
    if (_disposed) return;
    final generation = ++_generation;
    error = null;
    api?.close();
    api = null;
    try {
      final loaded = await _configStore.load();
      if (_disposed || generation != _generation) return;
      config = loaded;
      if (config.isConfigured) {
        api = _createApi(config);
        await api!.restoreSession();
      }
    } catch (failure) {
      if (_disposed || generation != _generation) return;
      error = failure;
    }
    if (_disposed || generation != _generation) return;
    initialized = true;
    _notify();
  }

  /// Server switches invalidate the session before any new endpoint is used.
  /// Caller discards its previous user/endpoint cache and queued mutations.
  Future<void> updateEndpoints(RuntimeConfig next) async {
    if (_disposed) return;
    _generation++;
    try {
      await api?.logout(revoke: false);
      await _sessionStore.clear();
      api?.close();
      api = null;
      await _configStore.saveAndroid(next);
      config = next;
      error = null;
      if (next.isConfigured && !_disposed) {
        api = _createApi(next);
      }
    } catch (failure) {
      error = failure;
      rethrow;
    } finally {
      _notify();
    }
  }

  Future<void> signOut() async {
    try {
      await api?.logout();
      error = null;
    } catch (failure) {
      error = failure;
      rethrow;
    } finally {
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    api?.close();
    super.dispose();
  }
}
