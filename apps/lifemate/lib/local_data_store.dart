import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';

/// One local runtime session: shared by all production stores in this isolate.
/// A failed native write leaves the session unavailable until a real app restart.
class LocalDataSession {
  bool _uncertain = false;
  // All instances share the writer lock: read/modify/write cannot lose a record.
  Future<void>? _tail;

  Future<T> _run<T>(Future<T> Function() operation) {
    final previous = _tail;
    final release = Completer<void>();
    _tail = release.future;
    Future<T> run() async {
      if (previous != null) await previous;
      try {
        if (_uncertain) {
          throw const ApiException(500, 'local_storage_restart_required');
        }
        return await operation();
      } finally {
        // Don't retain a completed future and its caller's async zone forever.
        if (identical(_tail, release.future)) _tail = null;
        release.complete();
      }
    }

    return run();
  }
}

/// Device-only data for the explicitly separate, unauthenticated test entrypoint.
/// Never used as an authorization boundary or as a production sync cache.
class LocalDataStore {
  LocalDataStore(
      {required this.category,
      required this.displayName,
      LocalDataSession? session})
      : session = session ?? _processSession;

  final String category;
  final String displayName;
  static const key = 'lifeguide.local_data.v1';
  static const categories = {'girl_minor', 'boy_minor', 'adult'};
  static const themes = {'girl_pink', 'boy_blue', 'adult_blue'};
  static const kinds = {
    'task',
    'assignment',
    'exam',
    'event',
    'routine',
    'goal',
    'study_session'
  };
  static const statuses = {'planned', 'in_progress', 'completed', 'cancelled'};
  static const priorities = {'low', 'normal', 'high', 'urgent'};
  static final _processSession = LocalDataSession();
  final LocalDataSession session;

  Future<T> _locked<T>(Future<T> Function() operation) =>
      session._run(operation);

  static String newId() {
    final random = Random.secure();
    return List.generate(
            16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'))
        .join();
  }

  static Map<String, dynamic> _copy(Map<String, dynamic> value) =>
      jsonDecode(jsonEncode(value)) as Map<String, dynamic>;

  static Map<String, dynamic> _decode(String raw) {
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final profile = data['profile'] as Map<String, dynamic>;
      final items = data['items'] as List<dynamic>;
      if (data['version'] != 1 ||
          !categories.contains(profile['profile_category']) ||
          profile['user_id'] is! String ||
          (profile['user_id'] as String).isEmpty ||
          profile['display_name'] is! String ||
          (profile['display_name'] as String).trim().isEmpty ||
          (profile['display_name'] as String).trim().length > 120 ||
          !themes.contains(profile['theme_preference'])) {
        throw const FormatException();
      }
      final ids = <String>{};
      for (final rawItem in items) {
        final item = rawItem as Map<String, dynamic>;
        if (item['id'] is! String ||
            (item['id'] as String).isEmpty ||
            !ids.add(item['id'] as String) ||
            item['owner_user_id'] != profile['user_id'] ||
            item['title'] is! String ||
            (item['title'] as String).trim().isEmpty ||
            (item['title'] as String).trim().length > 240 ||
            !kinds.contains(item['kind']) ||
            !statuses.contains(item['status']) ||
            !priorities.contains(item['priority']) ||
            (item['notes'] != null &&
                (item['notes'] is! String ||
                    (item['notes'] as String).length > 10000)) ||
            item['visibility'] != 'private') {
          throw const FormatException();
        }
        for (final field in ['starts_at', 'due_at']) {
          if (item[field] != null &&
              (item[field] is! String ||
                  DateTime.tryParse(item[field] as String) == null)) {
            throw const FormatException();
          }
        }
        final start = DateTime.tryParse(item['starts_at'] as String? ?? '');
        final due = DateTime.tryParse(item['due_at'] as String? ?? '');
        if (start != null && due != null && due.isBefore(start)) {
          throw const FormatException();
        }
      }
      return data;
    } catch (_) {
      throw const ApiException(500, 'local_data_corrupt');
    }
  }

  static Future<SharedPreferencesAsync> _preferences() async {
    try {
      // Android default is transactional DataStore. No legacy native/Dart cache.
      return SharedPreferencesAsync();
    } catch (_) {
      throw const ApiException(500, 'local_storage_failed');
    }
  }

  static Future<String?> _raw(SharedPreferencesAsync prefs) async {
    try {
      return await prefs.getString(key);
    } catch (_) {
      throw const ApiException(500, 'local_storage_failed');
    }
  }

  Future<void> _write(
      SharedPreferencesAsync prefs, Map<String, dynamic> data) async {
    final raw = jsonEncode(data);
    // Prevalidation does not attempt native I/O and must not poison the session.
    if (utf8.encode(raw).length > 1024 * 1024) {
      throw const ApiException(500, 'local_storage_failed');
    }
    try {
      await prefs.setString(key, raw);
    } catch (_) {
      // Even DataStore may have published a native cache before a rename error.
      // Prevent later reads/writes from treating that uncertain value as durable.
      session._uncertain = true;
      throw const ApiException(500, 'local_storage_restart_required');
    }
  }

  static Future<Map<String, dynamic>?> readSavedProfile() =>
      _processSession._run(() async {
        final prefs = await _preferences();
        final raw = await _raw(prefs);
        if (raw == null) return null;
        return _copy(_decode(raw)['profile'] as Map<String, dynamic>);
      });

  Future<Map<String, dynamic>> _load(String? raw) async {
    if (raw != null) return _decode(raw);
    if (!categories.contains(category) ||
        displayName.trim().isEmpty ||
        displayName.trim().length > 120) {
      throw const ApiException(400, 'local_invalid_profile');
    }
    return {
      'version': 1,
      'profile': {
        'user_id': newId(),
        'profile_category': category,
        'display_name': displayName.trim(),
        'theme_preference': category == 'girl_minor'
            ? 'girl_pink'
            : category == 'boy_minor'
                ? 'boy_blue'
                : 'adult_blue',
      },
      'items': <Map<String, dynamic>>[],
    };
  }

  Future<Map<String, dynamic>> read() => _locked(() async {
        final prefs = await _preferences();
        final raw = await _raw(prefs);
        final missing = raw == null;
        final data = await _load(raw);
        if (missing) await _write(prefs, data);
        return _copy(data);
      });

  Future<T> mutate<T>(T Function(Map<String, dynamic> data) change) =>
      _locked(() async {
        final prefs = await _preferences();
        final data = await _load(await _raw(prefs));
        final result = change(data);
        await _write(prefs, data);
        return result;
      });
}
