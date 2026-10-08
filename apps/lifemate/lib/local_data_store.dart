import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';

/// Device-only data for the explicitly separate, unauthenticated test entrypoint.
/// Never used as an authorization boundary or as a production sync cache.
class LocalDataStore {
  LocalDataStore({required this.category, required this.displayName});

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
  // All instances share the writer lock: read/modify/write cannot lose a record.
  static Future<void> _tail = Future.value();

  static Future<T> _locked<T>(Future<T> Function() operation) {
    final task = _tail.then((_) => operation());
    _tail = task.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return task;
  }

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
            !kinds.contains(item['kind']) ||
            !statuses.contains(item['status']) ||
            item['visibility'] != 'private') throw const FormatException();
        for (final field in ['starts_at', 'due_at']) {
          if (item[field] != null &&
              DateTime.tryParse(item[field].toString()) == null) {
            throw const FormatException();
          }
        }
      }
      return data;
    } catch (_) {
      throw const ApiException(500, 'local_data_corrupt');
    }
  }

  static Future<SharedPreferences> _preferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Legacy SharedPreferences caches a value even if the platform write fails.
      // Always reload the durable platform state before reading it.
      await prefs.reload();
      return prefs;
    } catch (_) {
      throw const ApiException(500, 'local_storage_failed');
    }
  }

  static Future<void> _write(
      SharedPreferences prefs, Map<String, dynamic> data) async {
    try {
      final raw = jsonEncode(data);
      // Bounded test storage; fail explicitly rather than risk silent truncation.
      if (utf8.encode(raw).length > 1024 * 1024 ||
          !await prefs.setString(key, raw)) {
        throw const ApiException(500, 'local_storage_failed');
      }
    } catch (_) {
      throw const ApiException(500, 'local_storage_failed');
    }
  }

  static Future<Map<String, dynamic>?> readSavedProfile() => _locked(() async {
        final prefs = await _preferences();
        final raw = prefs.getString(key);
        if (raw == null) return null;
        return _copy(_decode(raw)['profile'] as Map<String, dynamic>);
      });

  Future<Map<String, dynamic>> _load(SharedPreferences prefs) async {
    final raw = prefs.getString(key);
    if (raw != null) return _decode(raw);
    if (!categories.contains(category) || displayName.trim().isEmpty) {
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
        final missing = prefs.getString(key) == null;
        final data = await _load(prefs);
        if (missing) await _write(prefs, data);
        return _copy(data);
      });

  Future<T> mutate<T>(T Function(Map<String, dynamic> data) change) =>
      _locked(() async {
        final prefs = await _preferences();
        final data = await _load(prefs);
        final result = change(data);
        await _write(prefs, data);
        return result;
      });
}
