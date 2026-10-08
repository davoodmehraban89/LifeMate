import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'runtime_config.dart';
import 'runtime_http_client.dart';
import 'session_store.dart';

abstract class IdentityApi {
  String? get accessToken;

  Future<void> register({
    required String displayName,
    required String email,
    required String password,
  });

  Future<void> verifyEmail(String token, {required String newPassword});
  Future<void> login(String email, String password);
  Future<void> forgotPassword(String email);
  Future<void> resetPassword(String token, String newPassword);
  Future<void> changePassword(String currentPassword, String newPassword);
  Future<Map<String, dynamic>> getProfile();
  Future<Map<String, dynamic>> updateProfile({
    String? displayName,
    String? birthDate,
    String? themePreference,
    String? profileCategory,
  });
  Future<List<Map<String, dynamic>>> listFamilies();
  Future<List<Map<String, dynamic>>> listFamilyMembers(String familyId);
  Future<Map<String, dynamic>> createFamily(String name, {String? role});
  Future<void> inviteMember({
    required String familyId,
    required String email,
    required String role,
    String? themePreference,
  });
  Future<void> acceptInvitation(String token);
  Future<void> setGuardian({
    required String familyId,
    required String guardianUserId,
    required String minorUserId,
  });

  Future<List<Map<String, dynamic>>> getToday({
    required DateTime from,
    required DateTime to,
  });
  Future<List<Map<String, dynamic>>> listPlanItems({
    DateTime? from,
    DateTime? to,
    String? kind,
  });
  Future<Map<String, dynamic>> createPlanItem(Map<String, dynamic> data);
  Future<Map<String, dynamic>> updatePlanItem(
    String itemId,
    Map<String, dynamic> data,
  );
  Future<List<Map<String, dynamic>>> listLifeContexts();
  Future<Map<String, dynamic>> createLifeContext({
    required String kind,
    required String title,
  });
  Future<Map<String, dynamic>> createAcademicYear(Map<String, dynamic> data);
  Future<Map<String, dynamic>> createAcademicTerm(
    String yearId,
    Map<String, dynamic> data,
  );
  Future<Map<String, dynamic>> createSubject(
    String termId,
    Map<String, dynamic> data,
  );
  Future<Map<String, dynamic>> createClassSession(
    String subjectId,
    Map<String, dynamic> data,
  );
  Future<Map<String, dynamic>> getSchoolOverview(String studentUserId);
  Future<List<Map<String, dynamic>>> getTimetable(String studentUserId);
  Future<Map<String, dynamic>> setGrade(
    String itemId, {
    required num points,
    required num outOf,
  });
  Future<List<Map<String, dynamic>>> claimDueReminders();
  Future<List<Map<String, dynamic>>> getFamilyCalendar(String familyId);
  Future<Map<String, dynamic>> getChildSupportSummary(
    String familyId,
    String studentUserId,
  );
  Future<Map<String, dynamic>> submitSyncMutations(
    List<Map<String, dynamic>> mutations,
  );

  Future<Map<String, dynamic>> createLearningGoal({
    required String title,
    String? target,
    String? subjectId,
  });
  Future<List<Map<String, dynamic>>> listLearningGoals();
  Future<Map<String, dynamic>> createLearningCheckin({
    String? learningGoalId,
    required int confidence,
    required int difficulty,
    String? note,
  });
  Future<Map<String, dynamic>> createWellbeingCheckin({
    required int mood,
    required int energy,
    required int stress,
    String? note,
    String visibility,
  });
  Future<List<Map<String, dynamic>>> listWellbeingCheckins();
  Future<Map<String, dynamic>> createAiSession(String kind);
  Future<Map<String, dynamic>> sendAiMessage(
    String sessionId,
    String message,
  );
  Future<Map<String, dynamic>> getGuardianWellbeingSummary(
    String familyId,
    String minorUserId,
  );
  Future<Map<String, dynamic>> requestFamilyGuidance(
    String familyId,
    String minorUserId,
    String question,
  );
}

class ApiException implements Exception {
  const ApiException(this.statusCode, this.code, {this.details = const {}});
  final int statusCode;
  final String code;
  final Map<String, dynamic> details;

  @override
  String toString() => 'ApiException($statusCode, $code)';
}

class HttpIdentityApi implements IdentityApi {
  HttpIdentityApi({
    String? baseUrl,
    http.Client? client,
    SessionStore? sessionStore,
    this.onSessionChanged,
    this.onScopeDiscarded,
  })  : baseUrl = normalizeApiUrl(
            baseUrl ?? (throw ArgumentError('API configuration is required.'))),
        _client = client ?? createRuntimeHttpClient(),
        _sessionStore = sessionStore == null
            ? createSessionStore()
            : sessionStore is SerializedSessionStore
                ? sessionStore
                : SerializedSessionStore(sessionStore);

  final String baseUrl;
  final http.Client _client;
  final SessionStore _sessionStore;
  void Function()? onSessionChanged;
  Future<void> Function(String)? onScopeDiscarded;
  Future<void>? _refreshing;
  int _sessionGeneration = 0;
  String? currentUserId;
  String get endpointIdentity => baseUrl;
  String? get cacheNamespace => accessToken == null || currentUserId == null
      ? null
      : '$endpointIdentity|$currentUserId';

  @override
  String? accessToken;
  String? _refreshToken;

  Uri _uri(String path) {
    if (!path.startsWith('/') ||
        path.startsWith('//') ||
        path.contains('://')) {
      throw ArgumentError('Requests must use a path on the configured API.');
    }
    return Uri.parse('$baseUrl$path');
  }

  Future<Map<String, dynamic>> requestJson(String method, String path,
          {Map<String, dynamic>? body, bool auth = true}) =>
      _json(method, path, body: body, auth: auth);

  void close() {
    _sessionGeneration++;
    _client.close();
  }

  Future<void> _acceptTokens(Map<String, dynamic> result,
      {int? generation}) async {
    if (generation != null && generation != _sessionGeneration) {
      throw const ApiException(401, 'session_expired');
    }
    final access = result['accessToken'];
    final refresh = result['refreshToken'];
    String? userId;
    try {
      final claims = jsonDecode(utf8.decode(base64Url.decode(
          base64Url.normalize((access as String).split('.')[1])))) as Map;
      userId = claims['sub'] as String?;
    } catch (_) {
      throw const ApiException(502, 'invalid_api_response');
    }
    if (refresh is! String ||
        refresh.isEmpty ||
        userId == null ||
        userId.isEmpty) {
      throw const ApiException(502, 'invalid_api_response');
    }
    if (currentUserId != null && currentUserId != userId) {
      await _clearSession();
    }
    if (generation != null && generation != _sessionGeneration) {
      throw const ApiException(401, 'session_expired');
    }
    await _sessionStore.write(jsonEncode({
      'endpoint': endpointIdentity,
      'refreshToken': refresh,
      'userId': userId
    }));
    if (generation != null && generation != _sessionGeneration) {
      throw const ApiException(401, 'session_expired');
    }
    accessToken = access;
    _refreshToken = refresh;
    currentUserId = userId;
    onSessionChanged?.call();
  }

  Future<bool> restoreSession() async {
    final raw = await _sessionStore.read();
    if (raw == null) return false;
    late Map<String, dynamic> session;
    try {
      session = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      await logout(revoke: false);
      return false;
    }
    if (session['endpoint'] != endpointIdentity ||
        session['refreshToken'] is! String ||
        (session['refreshToken'] as String).isEmpty ||
        session['userId'] is! String) {
      if (session['endpoint'] is String && session['userId'] is String) {
        await onScopeDiscarded
            ?.call('${session['endpoint']}|${session['userId']}');
      }
      await logout(revoke: false);
      return false;
    }
    _refreshToken = session['refreshToken'] as String;
    currentUserId = session['userId'] as String;
    try {
      await _refresh();
      return true;
    } on ApiException catch (error) {
      if (error.statusCode == 401 || error.statusCode == 403) return false;
      rethrow;
    }
  }

  Future<void> logout({bool revoke = true}) async {
    final token = _refreshToken;
    _sessionGeneration++;
    await _clearSession();
    if (revoke && token != null) {
      try {
        await _json('POST', '/v1/auth/logout',
            body: {'refreshToken': token}, retry: false);
      } catch (_) {/* Local credentials are cleared even when offline. */}
    }
  }

  Future<void> _clearSession() async {
    final scope =
        currentUserId == null ? null : '$endpointIdentity|$currentUserId';
    accessToken = null;
    _refreshToken = null;
    currentUserId = null;
    onSessionChanged?.call();
    Object? failure;
    StackTrace? failureStack;
    try {
      await _sessionStore.clear();
    } catch (error, stack) {
      failure = error;
      failureStack = stack;
    }
    try {
      if (scope != null) await onScopeDiscarded?.call(scope);
    } catch (error, stack) {
      failure ??= error;
      failureStack ??= stack;
    }
    if (failure != null) {
      Error.throwWithStackTrace(failure, failureStack!);
    }
  }

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
    final requestGeneration = _sessionGeneration;
    if (auth && accessToken == null) {
      throw const ApiException(401, 'session_expired');
    }
    final request = http.Request(method, _uri(path))
      ..headers.addAll(_headers(auth: auth));
    if (body != null) request.body = jsonEncode(body);

    late http.Response response;
    try {
      response = await (() async =>
              http.Response.fromStream(await _client.send(request)))()
          .timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw const ApiException(0, 'request_timeout');
    } on http.ClientException {
      throw const ApiException(0, 'network_unavailable');
    }

    if (auth && requestGeneration != _sessionGeneration) {
      throw const ApiException(401, 'session_changed');
    }

    if (response.statusCode == 401 && auth && retry && _refreshToken != null) {
      await _refresh();
      return _json(method, path, body: body, auth: auth, retry: false);
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (response.statusCode == 401 && auth) await logout(revoke: false);
      var code = 'request_failed';
      var details = <String, dynamic>{};
      if (response.body.isNotEmpty) {
        try {
          details = jsonDecode(response.body) as Map<String, dynamic>;
          code = details['error']?.toString() ?? code;
        } catch (_) {}
      }
      throw ApiException(response.statusCode, code, details: details);
    }

    if (response.body.isEmpty) return <String, dynamic>{};
    try {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw const ApiException(502, 'invalid_api_response');
    }
  }

  Future<void> _refresh() =>
      _refreshing ??= _performRefresh().whenComplete(() => _refreshing = null);

  Future<void> _performRefresh() async {
    final token = _refreshToken;
    if (token == null) throw const ApiException(401, 'session_expired');
    final generation = _sessionGeneration;
    try {
      final result = await _json(
        'POST',
        '/v1/auth/refresh',
        body: {'refreshToken': token},
        retry: false,
      );
      await _acceptTokens(result, generation: generation);
    } on ApiException catch (error) {
      if (generation == _sessionGeneration &&
          (error.statusCode == 401 || error.statusCode == 403)) {
        await logout(revoke: false);
      }
      rethrow;
    }
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
  Future<void> verifyEmail(String token, {required String newPassword}) async {
    await _json('POST', '/v1/auth/verify-email',
        body: {'token': token, 'newPassword': newPassword});
  }

  @override
  Future<void> login(String email, String password) async {
    final generation = ++_sessionGeneration;
    final result = await _json('POST', '/v1/auth/login', body: {
      'identifier': email,
      'password': password,
    });
    await _acceptTokens(result, generation: generation);
  }

  Future<Map<String, dynamic>> registerContact(
      {required String displayName,
      required String password,
      String? email,
      String? phone}) {
    return _json('POST', '/v1/auth/register', body: {
      'displayName': displayName,
      'password': password,
      if (email != null) 'email': email,
      if (phone != null) 'phone': phone
    });
  }

  Future<Map<String, dynamic>> authCapabilities() =>
      _json('GET', '/v1/auth/capabilities');
  Future<Map<String, dynamic>> resendVerification(String email) =>
      _json('POST', '/v1/auth/resend-verification', body: {'email': email});
  Future<Map<String, dynamic>> requestPhoneOtp(String phone,
          {String purpose = 'login'}) =>
      _json('POST', '/v1/auth/phone/request-otp',
          body: {'phone': phone, 'purpose': purpose});
  Future<void> verifyPhoneOtp(String challengeId, String code,
      {String? newPassword}) async {
    final generation = ++_sessionGeneration;
    final result = await _json('POST', '/v1/auth/phone/verify-otp', body: {
      'challengeId': challengeId,
      'code': code,
      if (newPassword != null) 'newPassword': newPassword
    });
    await _acceptTokens(result, generation: generation);
  }

  Future<Map<String, dynamic>> startStudySession(Map<String, dynamic> body) =>
      requestJson('POST', '/v1/study/sessions', body: body);
  Future<Map<String, dynamic>> recordStudySessionEvent(
          String id, Map<String, dynamic> body) =>
      requestJson(
          'POST', '/v1/study/sessions/${Uri.encodeComponent(id)}/events',
          body: body);
  Future<List<Map<String, dynamic>>> listStudySessions(
      {String? planItemId}) async {
    final suffix = planItemId == null
        ? ''
        : '?${Uri(queryParameters: {'planItemId': planItemId}).query}';
    final result = await requestJson('GET', '/v1/study/sessions$suffix');
    return (result['sessions'] as List)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  Future<Map<String, dynamic>> getStudySession(String id) async =>
      Map<String, dynamic>.from((await requestJson('GET',
          '/v1/study/sessions/${Uri.encodeComponent(id)}'))['session'] as Map);
  Future<Map<String, dynamic>> archiveStudySession(
          String id, Map<String, dynamic> body) =>
      requestJson('DELETE', '/v1/study/sessions/${Uri.encodeComponent(id)}',
          body: body);
  Future<Map<String, dynamic>> recordActivityState(
          String id, Map<String, dynamic> body) =>
      requestJson(
          'POST', '/v1/plan-items/${Uri.encodeComponent(id)}/activity-state',
          body: body);
  Future<Map<String, dynamic>> getActivityState(String id) => requestJson(
      'GET', '/v1/plan-items/${Uri.encodeComponent(id)}/activity-state');
  Future<Map<String, dynamic>> updateStudySession(
          String id, Map<String, dynamic> body) =>
      requestJson('PATCH', '/v1/study/sessions/${Uri.encodeComponent(id)}',
          body: body);
  Future<Map<String, dynamic>> getLearningReport(
      String familyId, String childId,
      {DateTime? from, DateTime? to}) {
    final params = <String, String>{
      if (from != null) 'from': from.toUtc().toIso8601String(),
      if (to != null) 'to': to.toUtc().toIso8601String()
    };
    final suffix =
        params.isEmpty ? '' : '?${Uri(queryParameters: params).query}';
    return requestJson('GET',
        '/v1/families/${Uri.encodeComponent(familyId)}/children/${Uri.encodeComponent(childId)}/learning-report$suffix');
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
    String? profileCategory,
  }) =>
      _json('PATCH', '/v1/profile', auth: true, body: {
        if (displayName != null) 'displayName': displayName,
        if (birthDate != null) 'birthDate': birthDate,
        if (themePreference != null) 'themePreference': themePreference,
        if (profileCategory != null) 'profileCategory': profileCategory,
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
  Future<List<Map<String, dynamic>>> listFamilyMembers(String familyId) async {
    final result = await _json(
      'GET',
      '/v1/families/$familyId/members',
      auth: true,
    );
    final members = (result['members'] as List<dynamic>? ?? const []);
    return members
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
    String? themePreference,
  }) async {
    await _json(
      'POST',
      '/v1/families/$familyId/invitations',
      auth: true,
      body: {
        'email': email,
        'role': role,
        if (themePreference != null) 'themePreference': themePreference,
      },
    );
  }

  Future<Map<String, dynamic>> createFamilyInvitation({
    required String familyId,
    String? email,
    String? phone,
    required String role,
    String? themePreference,
  }) =>
      requestJson(
          'POST', '/v1/families/${Uri.encodeComponent(familyId)}/invitations',
          body: {
            if (email != null) 'email': email,
            if (phone != null) 'phone': phone,
            'role': role,
            if (themePreference != null) 'themePreference': themePreference,
          });

  @override
  Future<void> acceptInvitation(String token) async {
    await _json(
      'POST',
      '/v1/invitations/accept',
      auth: true,
      body: {'token': token},
    );
  }

  @override
  Future<void> setGuardian({
    required String familyId,
    required String guardianUserId,
    required String minorUserId,
  }) async {
    await _json(
      'POST',
      '/v1/families/$familyId/guardians',
      auth: true,
      body: {
        'guardianUserId': guardianUserId,
        'minorUserId': minorUserId,
      },
    );
  }

  @override
  Future<List<Map<String, dynamic>>> getToday({
    required DateTime from,
    required DateTime to,
  }) async {
    final result = await _json(
      'GET',
      '/v1/today?from=${Uri.encodeQueryComponent(from.toUtc().toIso8601String())}&to=${Uri.encodeQueryComponent(to.toUtc().toIso8601String())}',
      auth: true,
    );
    return (result['items'] as List<dynamic>? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  @override
  Future<List<Map<String, dynamic>>> listPlanItems({
    DateTime? from,
    DateTime? to,
    String? kind,
  }) async {
    final params = <String, String>{};
    if (from != null) params['from'] = from.toUtc().toIso8601String();
    if (to != null) params['to'] = to.toUtc().toIso8601String();
    if (kind != null) params['kind'] = kind;
    final suffix =
        params.isEmpty ? '' : '?${Uri(queryParameters: params).query}';
    final result = await _json('GET', '/v1/plan-items$suffix', auth: true);
    return (result['items'] as List<dynamic>? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  @override
  Future<Map<String, dynamic>> createPlanItem(Map<String, dynamic> data) =>
      _json('POST', '/v1/plan-items', auth: true, body: data);

  @override
  Future<Map<String, dynamic>> updatePlanItem(
    String itemId,
    Map<String, dynamic> data,
  ) =>
      _json('PATCH', '/v1/plan-items/$itemId', auth: true, body: data);

  @override
  Future<List<Map<String, dynamic>>> listLifeContexts() async {
    final result = await _json('GET', '/v1/life-contexts', auth: true);
    return (result['contexts'] as List<dynamic>? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  @override
  Future<Map<String, dynamic>> createLifeContext({
    required String kind,
    required String title,
  }) =>
      _json(
        'POST',
        '/v1/life-contexts',
        auth: true,
        body: {'kind': kind, 'title': title},
      );

  @override
  Future<Map<String, dynamic>> createAcademicYear(
    Map<String, dynamic> data,
  ) =>
      _json('POST', '/v1/school/years', auth: true, body: data);

  @override
  Future<Map<String, dynamic>> createAcademicTerm(
    String yearId,
    Map<String, dynamic> data,
  ) =>
      _json(
        'POST',
        '/v1/school/years/$yearId/terms',
        auth: true,
        body: data,
      );

  @override
  Future<Map<String, dynamic>> createSubject(
    String termId,
    Map<String, dynamic> data,
  ) =>
      _json(
        'POST',
        '/v1/school/terms/$termId/subjects',
        auth: true,
        body: data,
      );

  @override
  Future<Map<String, dynamic>> createClassSession(
    String subjectId,
    Map<String, dynamic> data,
  ) =>
      _json(
        'POST',
        '/v1/school/subjects/$subjectId/classes',
        auth: true,
        body: data,
      );

  @override
  Future<Map<String, dynamic>> getSchoolOverview(String studentUserId) =>
      _json('GET', '/v1/school/$studentUserId/overview', auth: true);

  @override
  Future<List<Map<String, dynamic>>> getTimetable(String studentUserId) async {
    final result = await _json(
      'GET',
      '/v1/school/$studentUserId/timetable',
      auth: true,
    );
    return (result['classes'] as List<dynamic>? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  @override
  Future<Map<String, dynamic>> setGrade(
    String itemId, {
    required num points,
    required num outOf,
  }) =>
      _json(
        'PATCH',
        '/v1/school/plan-items/$itemId/grade',
        auth: true,
        body: {'points': points, 'outOf': outOf},
      );

  @override
  Future<List<Map<String, dynamic>>> claimDueReminders() async {
    final result = await _json(
      'POST',
      '/v1/reminders/claim-due',
      auth: true,
      body: {'limit': 20},
    );
    return (result['reminders'] as List<dynamic>? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  @override
  Future<List<Map<String, dynamic>>> getFamilyCalendar(String familyId) async {
    final result = await _json(
      'GET',
      '/v1/families/$familyId/calendar',
      auth: true,
    );
    return (result['items'] as List<dynamic>? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  @override
  Future<Map<String, dynamic>> getChildSupportSummary(
    String familyId,
    String studentUserId,
  ) =>
      _json(
        'GET',
        '/v1/families/$familyId/children/$studentUserId/support-summary',
        auth: true,
      );

  @override
  Future<Map<String, dynamic>> submitSyncMutations(
    List<Map<String, dynamic>> mutations,
  ) =>
      _json(
        'POST',
        '/v1/sync/mutations',
        auth: true,
        body: {'mutations': mutations},
      );

  @override
  Future<Map<String, dynamic>> createLearningGoal({
    required String title,
    String? target,
    String? subjectId,
  }) =>
      _json('POST', '/v1/learning/goals', auth: true, body: {
        'title': title,
        if (target != null) 'target': target,
        if (subjectId != null) 'subjectId': subjectId,
      });

  @override
  Future<List<Map<String, dynamic>>> listLearningGoals() async {
    final result = await _json('GET', '/v1/learning/goals', auth: true);
    return (result['items'] as List<dynamic>? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  @override
  Future<Map<String, dynamic>> createLearningCheckin({
    String? learningGoalId,
    required int confidence,
    required int difficulty,
    String? note,
  }) =>
      _json('POST', '/v1/learning/checkins', auth: true, body: {
        if (learningGoalId != null) 'learningGoalId': learningGoalId,
        'confidence': confidence,
        'difficulty': difficulty,
        if (note != null) 'note': note,
      });

  @override
  Future<Map<String, dynamic>> createWellbeingCheckin({
    required int mood,
    required int energy,
    required int stress,
    String? note,
    String visibility = 'private',
  }) =>
      _json('POST', '/v1/wellbeing/checkins', auth: true, body: {
        'mood': mood,
        'energy': energy,
        'stress': stress,
        if (note != null) 'note': note,
        'visibility': visibility,
      });

  @override
  Future<List<Map<String, dynamic>>> listWellbeingCheckins() async {
    final result = await _json('GET', '/v1/wellbeing/checkins', auth: true);
    return (result['items'] as List<dynamic>? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  @override
  Future<Map<String, dynamic>> createAiSession(String kind) =>
      _json('POST', '/v1/ai/sessions', auth: true, body: {'kind': kind});

  @override
  Future<Map<String, dynamic>> sendAiMessage(
    String sessionId,
    String message,
  ) =>
      _json(
        'POST',
        '/v1/ai/sessions/$sessionId/messages',
        auth: true,
        body: {'message': message},
      );

  @override
  Future<Map<String, dynamic>> getGuardianWellbeingSummary(
    String familyId,
    String minorUserId,
  ) =>
      _json(
        'GET',
        '/v1/families/$familyId/children/$minorUserId/wellbeing-summary',
        auth: true,
      );

  @override
  Future<Map<String, dynamic>> requestFamilyGuidance(
    String familyId,
    String minorUserId,
    String question,
  ) =>
      _json(
        'POST',
        '/v1/families/$familyId/children/$minorUserId/family-guidance',
        auth: true,
        body: {'question': question},
      );
}
