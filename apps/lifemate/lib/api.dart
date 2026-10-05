import 'dart:convert';

import 'package:http/http.dart' as http;

abstract class IdentityApi {
  String? get accessToken;

  Future<void> register({
    required String displayName,
    required String email,
    required String password,
  });

  Future<void> verifyEmail(String token);
  Future<void> login(String email, String password);
  Future<void> forgotPassword(String email);
  Future<void> resetPassword(String token, String newPassword);
  Future<void> changePassword(String currentPassword, String newPassword);
  Future<Map<String, dynamic>> getProfile();
  Future<Map<String, dynamic>> updateProfile({
    String? displayName,
    String? birthDate,
    String? themePreference,
  });
  Future<List<Map<String, dynamic>>> listFamilies();
  Future<Map<String, dynamic>> createFamily(String name, {String? role});
  Future<void> inviteMember({
    required String familyId,
    required String email,
    required String role,
  });
  Future<void> acceptInvitation(String token);
}

class ApiException implements Exception {
  const ApiException(this.statusCode, this.code);
  final int statusCode;
  final String code;

  @override
  String toString() => 'ApiException($statusCode, $code)';
}

class HttpIdentityApi implements IdentityApi {
  HttpIdentityApi({
    String? baseUrl,
    http.Client? client,
  })  : baseUrl = baseUrl ??
            const String.fromEnvironment(
              'LIFEMATE_API_URL',
              defaultValue: 'http://localhost:8080',
            ),
        _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  @override
  String? accessToken;
  String? _refreshToken;

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  Map<String, String> _headers({bool auth = false}) => {
        'content-type': 'application/json',
        if (auth && accessToken != null) 'authorization': 'Bearer $accessToken',
      };

  Future<Map<String, dynamic>> _json(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool auth = false,
    bool retry = true,
  }) async {
    final request = http.Request(method, _uri(path))
      ..headers.addAll(_headers(auth: auth));
    if (body != null) request.body = jsonEncode(body);

    final streamed = await _client.send(request);
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode == 401 && auth && retry && _refreshToken != null) {
      await _refresh();
      return _json(method, path, body: body, auth: auth, retry: false);
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      var code = 'request_failed';
      if (response.body.isNotEmpty) {
        try {
          code = (jsonDecode(response.body) as Map<String, dynamic>)['error']
                  ?.toString() ??
              code;
        } catch (_) {}
      }
      throw ApiException(response.statusCode, code);
    }

    if (response.body.isEmpty) return <String, dynamic>{};
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<void> _refresh() async {
    final token = _refreshToken;
    if (token == null) throw const ApiException(401, 'session_expired');
    final result = await _json(
      'POST',
      '/v1/auth/refresh',
      body: {'refreshToken': token},
      retry: false,
    );
    accessToken = result['accessToken']?.toString();
    _refreshToken = result['refreshToken']?.toString();
  }

  @override
  Future<void> register({
    required String displayName,
    required String email,
    required String password,
  }) async {
    await _json('POST', '/v1/auth/register', body: {
      'displayName': displayName,
      'email': email,
      'password': password,
    });
  }

  @override
  Future<void> verifyEmail(String token) async {
    await _json('POST', '/v1/auth/verify-email', body: {'token': token});
  }

  @override
  Future<void> login(String email, String password) async {
    final result = await _json('POST', '/v1/auth/login', body: {
      'email': email,
      'password': password,
    });
    accessToken = result['accessToken']?.toString();
    _refreshToken = result['refreshToken']?.toString();
  }

  @override
  Future<void> forgotPassword(String email) async {
    await _json('POST', '/v1/auth/forgot-password', body: {'email': email});
  }

  @override
  Future<void> resetPassword(String token, String newPassword) async {
    await _json('POST', '/v1/auth/reset-password', body: {
      'token': token,
      'newPassword': newPassword,
    });
  }

  @override
  Future<void> changePassword(
    String currentPassword,
    String newPassword,
  ) async {
    await _json('POST', '/v1/auth/change-password', auth: true, body: {
      'currentPassword': currentPassword,
      'newPassword': newPassword,
    });
  }

  @override
  Future<Map<String, dynamic>> getProfile() =>
      _json('GET', '/v1/profile', auth: true);

  @override
  Future<Map<String, dynamic>> updateProfile({
    String? displayName,
    String? birthDate,
    String? themePreference,
  }) =>
      _json('PATCH', '/v1/profile', auth: true, body: {
        if (displayName != null) 'displayName': displayName,
        if (birthDate != null) 'birthDate': birthDate,
        if (themePreference != null) 'themePreference': themePreference,
      });

  @override
  Future<List<Map<String, dynamic>>> listFamilies() async {
    final result = await _json('GET', '/v1/families', auth: true);
    final families = (result['families'] as List<dynamic>? ?? const []);
    return families
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  @override
  Future<Map<String, dynamic>> createFamily(
    String name, {
    String? role,
  }) =>
      _json('POST', '/v1/families', auth: true, body: {
        'name': name,
        if (role != null) 'role': role,
      });

  @override
  Future<void> inviteMember({
    required String familyId,
    required String email,
    required String role,
  }) async {
    await _json(
      'POST',
      '/v1/families/$familyId/invitations',
      auth: true,
      body: {'email': email, 'role': role},
    );
  }

  @override
  Future<void> acceptInvitation(String token) async {
    await _json(
      'POST',
      '/v1/invitations/accept',
      auth: true,
      body: {'token': token},
    );
  }
}
