import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate/api.dart';
import 'package:lifemate/main.dart';

class FakeApi implements IdentityApi {
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
        'display_name': 'والد',
        'email_normalized': 'parent@example.test',
        'theme_preference': 'adult_blue',
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
  Future<List<Map<String, dynamic>>> listFamilies() async => [];

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
}

void main() {
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

  testWidgets('successful login opens MyStudyLife-inspired home shell',
      (tester) async {
    await tester.pumpWidget(LifeMateApp(api: FakeApi()));

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
}
