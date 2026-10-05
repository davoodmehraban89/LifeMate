import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate/api.dart';
import 'package:lifemate/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeApi implements IdentityApi {
  FakeApi({
    this.role = 'teen_minor',
    this.themePreference = 'girl_pink',
  });

  final String role;
  final String themePreference;

  @override
  String? accessToken;

  @override
  Future<void> login(String email, String password) async {
    accessToken = 'test-token';
  }

  @override
  Future<void> register({
    required String displayName,
    required String email,
    required String password,
  }) async {}

  @override
  Future<void> verifyEmail(String token) async {}

  @override
  Future<void> forgotPassword(String email) async {}

  @override
  Future<void> resetPassword(String token, String newPassword) async {}

  @override
  Future<void> changePassword(
    String currentPassword,
    String newPassword,
  ) async {}

  @override
  Future<Map<String, dynamic>> getProfile() async => {
        'display_name': role == 'teen_minor' ? 'آرام' : 'والد',
        'email_normalized': 'user@example.test',
        'user_id': role == 'teen_minor' ? 'teen-1' : 'parent-1',
        'theme_preference': themePreference,
      };

  @override
  Future<Map<String, dynamic>> updateProfile({
    String? displayName,
    String? birthDate,
    String? themePreference,
  }) async =>
      {
        'display_name': displayName ?? 'والد',
        'theme_preference': themePreference ?? 'adult_blue',
      };

  @override
  Future<List<Map<String, dynamic>>> listFamilies() async => [
        {
          'id': 'family-1',
          'name': 'خانواده',
          'role': role,
          'is_admin': role == 'parent_guardian',
        }
      ];

  @override
  Future<List<Map<String, dynamic>>> listFamilyMembers(String familyId) async =>
      [];

  @override
  Future<Map<String, dynamic>> createFamily(
    String name, {
    String? role,
  }) async =>
      {'id': 'family-1', 'name': name};

  @override
  Future<void> inviteMember({
    required String familyId,
    required String email,
    required String role,
    String? themePreference,
  }) async {}

  @override
  Future<void> acceptInvitation(String token) async {}

  @override
  Future<void> setGuardian({
    required String familyId,
    required String guardianUserId,
    required String minorUserId,
  }) async {}

  @override
  Future<List<Map<String, dynamic>>> getToday({
    required DateTime from,
    required DateTime to,
  }) async => [
        {
          'id': 'today-1',
          'kind': 'task',
          'title': 'مرور برنامه امروز',
          'status': 'planned',
          'due_at': DateTime.now().add(const Duration(hours: 1)).toUtc().toIso8601String(),
        }
      ];

  @override
  Future<List<Map<String, dynamic>>> listPlanItems({
    DateTime? from,
    DateTime? to,
    String? kind,
  }) async => [
        {
          'id': 'plan-1',
          'kind': 'task',
          'title': 'تکمیل تمرین',
          'status': 'planned',
          'due_at': DateTime.now().add(const Duration(days: 1)).toUtc().toIso8601String(),
        }
      ];

  @override
  Future<Map<String, dynamic>> createPlanItem(Map<String, dynamic> data) async =>
      {'id': 'new-plan', ...data};

  @override
  Future<Map<String, dynamic>> updatePlanItem(
    String itemId,
    Map<String, dynamic> data,
  ) async =>
      {'id': itemId, ...data};

  @override
  Future<List<Map<String, dynamic>>> listLifeContexts() async => [];

  @override
  Future<Map<String, dynamic>> createLifeContext({
    required String kind,
    required String title,
  }) async =>
      {'id': 'ctx-1', 'kind': kind, 'title': title};

  @override
  Future<Map<String, dynamic>> createAcademicYear(
    Map<String, dynamic> data,
  ) async =>
      {'id': 'year-1', ...data};

  @override
  Future<Map<String, dynamic>> createAcademicTerm(
    String yearId,
    Map<String, dynamic> data,
  ) async =>
      {'id': 'term-1', ...data};

  @override
  Future<Map<String, dynamic>> createSubject(
    String termId,
    Map<String, dynamic> data,
  ) async =>
      {'id': 'subject-1', ...data};

  @override
  Future<Map<String, dynamic>> createClassSession(
    String subjectId,
    Map<String, dynamic> data,
  ) async =>
      {'id': 'class-1', ...data};

  @override
  Future<Map<String, dynamic>> setGrade(
    String itemId, {
    required num points,
    required num outOf,
  }) async =>
      {
        'id': itemId,
        'grade_points': points,
        'grade_out_of': outOf,
      };

  @override
  Future<List<Map<String, dynamic>>> claimDueReminders() async => [];

  @override
  Future<Map<String, dynamic>> getSchoolOverview(String studentUserId) async => {
        'years': [
          {'id': 'year-1', 'title': 'سال تحصیلی'}
        ],
        'subjects': [
          {'id': 'subject-1', 'name': 'ریاضی', 'term_title': 'نیمسال اول'}
        ],
        'workload': const [],
        'grades': const [],
      };

  @override
  Future<List<Map<String, dynamic>>> getTimetable(String studentUserId) async =>
      [];

  @override
  Future<List<Map<String, dynamic>>> getFamilyCalendar(String familyId) async =>
      [];

  @override
  Future<Map<String, dynamic>> getChildSupportSummary(
    String familyId,
    String studentUserId,
  ) async =>
      {
        'upcoming': const [],
        'metrics': {
          'completedLast7Days': 3,
          'overdue': 1,
          'studyMinutesLast7Days': 90,
          'gradePercent': 85,
        }
      };

  @override
  Future<Map<String, dynamic>> submitSyncMutations(
    List<Map<String, dynamic>> mutations,
  ) async =>
      {
        'results': mutations
            .map((m) => {'id': m['id'], 'status': 'accepted'})
            .toList(),
      };
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('starts in Persian RTL with identity actions', (tester) async {
    await tester.pumpWidget(LifeMateApp(api: FakeApi()));

    expect(find.text('LifeMate'), findsOneWidget);
    expect(find.text('ورود'), findsOneWidget);
    expect(find.text('رمز عبور را فراموش کرده‌ام'), findsOneWidget);

    final directionality =
        tester.widget<Directionality>(find.byType(Directionality).last);
    expect(directionality.textDirection, TextDirection.rtl);
  });

  testWidgets('opens recovery flow', (tester) async {
    await tester.pumpWidget(LifeMateApp(api: FakeApi()));

    await tester.tap(find.text('رمز عبور را فراموش کرده‌ام'));
    await tester.pumpAndSettle();

    expect(find.text('بازیابی رمز عبور'), findsOneWidget);
    expect(find.text('ارسال لینک بازیابی'), findsOneWidget);
  });

  testWidgets('teen login opens MyStudyLife-inspired student shell',
      (tester) async {
    await tester.pumpWidget(
      LifeMateApp(
        api: FakeApi(role: 'teen_minor', themePreference: 'girl_pink'),
      ),
    );

    await tester.enterText(
      find.widgetWithText(TextField, 'ایمیل'),
      'parent@example.test',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'رمز عبور'),
      'StrongPass!123',
    );
    await tester.tap(find.text('ورود'));
    await tester.pumpAndSettle();

    expect(find.text('امروز'), findsWidgets);
    expect(find.text('برنامه'), findsOneWidget);
    expect(find.text('تقویم'), findsOneWidget);
    expect(find.text('کارها'), findsOneWidget);
    expect(find.text('امتحان‌ها'), findsOneWidget);
  });

  testWidgets('parent login opens parent-focused family shell', (tester) async {
  await tester.pumpWidget(
    LifeMateApp(
      api: FakeApi(
        role: 'parent_guardian',
        themePreference: 'adult_blue',
      ),
    ),
  );

  await tester.enterText(
    find.widgetWithText(TextField, 'ایمیل'),
    'parent@example.test',
  );
  await tester.enterText(
    find.widgetWithText(TextField, 'رمز عبور'),
    'StrongPass!123',
  );
  await tester.tap(find.text('ورود'));
  await tester.pumpAndSettle();

  expect(find.text('امروز'), findsWidgets);
  expect(find.text('برنامه‌ریز'), findsOneWidget);
  expect(find.text('خانواده'), findsOneWidget);
  expect(find.text('راهنما'), findsOneWidget);
  expect(find.text('من'), findsOneWidget);
  expect(find.text('امتحان‌ها'), findsNothing);
  });
}
