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
    final suffix = params.isEmpty ? '' : '?${Uri(queryParameters: params).query}';
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
