import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

String normalizeApiUrl(String value, {Uri? webOrigin}) {
  var uri = Uri.tryParse(value.trim());
  if (uri != null &&
      !uri.hasScheme &&
      value.trim().startsWith('/') &&
      !value.trim().startsWith('//') &&
      webOrigin != null) {
    uri = webOrigin.resolve(value.trim());
  }
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment) {
    throw ArgumentError(
        'API address must be HTTPS without credentials, query or fragment.');
  }
  uri = uri.normalizePath();
  return uri.toString().replaceFirst(RegExp(r'/+$'), '');
}

class RuntimeConfig {
  RuntimeConfig(
      {String? apiBaseUrl,
      List<String> apiFallbackUrls = const [],
      Uri? webOrigin})
      : apiBaseUrl = apiBaseUrl == null || apiBaseUrl.trim().isEmpty
            ? null
            : normalizeApiUrl(apiBaseUrl, webOrigin: webOrigin),
        apiFallbackUrls = List.unmodifiable(apiFallbackUrls
            .map((url) => normalizeApiUrl(url, webOrigin: webOrigin))
            .toSet()) {
    if (this.apiBaseUrl == null && this.apiFallbackUrls.isNotEmpty ||
        endpoints.length > 6) {
      throw ArgumentError(
          'Choose a primary API and at most five alternatives.');
    }
  }
  final String? apiBaseUrl;
  final List<String> apiFallbackUrls;
  bool get isConfigured => apiBaseUrl != null;
  List<String> get endpoints => [
        if (apiBaseUrl != null) apiBaseUrl!,
        ...apiFallbackUrls.where((url) => url != apiBaseUrl)
      ];
  Map<String, dynamic> toJson() =>
      {'apiBaseUrl': apiBaseUrl, 'apiFallbackUrls': apiFallbackUrls};
  factory RuntimeConfig.fromJson(Map<String, dynamic> json, {Uri? webOrigin}) {
    final base = json['apiBaseUrl'];
    final fallback = json['apiFallbackUrls'] ?? const <String>[];
    if ((base != null && base is! String) ||
        fallback is! List ||
        fallback.any((item) => item is! String)) {
      throw const FormatException('Invalid runtime config.');
    }
    return RuntimeConfig(
        apiBaseUrl: base as String?,
        apiFallbackUrls: fallback.cast<String>(),
        webOrigin: webOrigin);
  }
}

class RuntimeConfigStore {
  RuntimeConfigStore(
      {http.Client? client,
      bool? web,
      Uri? webOrigin,
      SharedPreferencesAsync? preferences})
      : _client = client ?? http.Client(),
        _web = web ?? kIsWeb,
        _origin = webOrigin ?? Uri.base,
        _preferences = preferences;
  static const key = 'lifeguide.api_endpoints.v1';
  final http.Client _client;
  final bool _web;
  final Uri _origin;
  final SharedPreferencesAsync? _preferences;
  SharedPreferencesAsync get preferences =>
      _preferences ?? SharedPreferencesAsync();

  Future<RuntimeConfig> load() async {
    if (!_web) {
      final raw = await preferences.getString(key);
      return raw == null
          ? RuntimeConfig()
          : RuntimeConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    }
    if (_origin.scheme != 'https') {
      throw StateError('LifeGuide web startup requires HTTPS.');
    }
    final uri = _origin.resolve('/config.json').replace(queryParameters: {
      'fresh': DateTime.now().microsecondsSinceEpoch.toString()
    });
    final response = await _client.get(uri, headers: {
      'Cache-Control': 'no-store'
    }).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200 || response.body.length > 16384) {
      throw const FormatException('Runtime configuration is unavailable.');
    }
    return RuntimeConfig.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
        webOrigin: _origin);
  }

  Future<void> saveAndroid(RuntimeConfig config) async {
    if (_web) throw StateError('Web configuration is managed by config.json.');
    await preferences.setString(key, jsonEncode(config.toJson()));
  }
}
