import 'dart:convert';
import 'package:flutter/widgets.dart' show StringCharacters;
import 'package:shared_preferences/shared_preferences.dart';

/// Harmless display preferences; never an identity, permission or task cache.
final class DeviceReminderPreferences {
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();
  static final _controls =
      RegExp(r'[\x00-\x1f\x7f-\x9f\u202a-\u202e\u2066-\u2069]');
  String _key(String scope) {
    if (scope.isEmpty || scope.length > 4096) {
      throw ArgumentError('Invalid preference scope.');
    }
    return 'lifeguide.reminder_companion.v1.${base64Url.encode(utf8.encode(scope))}';
  }

  static bool valid(String value) =>
      value.length <= 4096 &&
      value.characters.length <= 40 &&
      !_controls.hasMatch(value);
  Future<String> read(String scope) async {
    final value = await _preferences.getString(_key(scope));
    if (value == null || !valid(value) || value.trim().isEmpty) {
      return 'LifeGuide';
    }
    return value.trim();
  }

  Future<void> write(String scope, String nickname) async {
    if (!valid(nickname)) throw ArgumentError('Invalid companion nickname.');
    await _preferences.setString(_key(scope), nickname.trim());
  }
}
