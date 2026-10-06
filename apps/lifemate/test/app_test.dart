import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate/api.dart';
import 'package:lifemate/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeApi implements IdentityApi {
  FakeApi({this.role = 'teen_minor', this.themePreference = 'girl_pink'});
  final String role;
  final String themePreference;
  @override String? accessToken;
  @override Future<void> login(String email, String password) async { accessToken = 'test-token'; }
  @override Future<void> register({required String displayName, required String email, required String password}) async {}
  @override Future<void> verifyEmail(String token) async {}
  @override Future<void> forgotPassword(String email) async {}
  @override Future<void> resetPassword(String token, String newPassword) async {}
  @override Future<void> changePassword(String currentPassword, String newPassword) async {}
  @override Future<Map<String,dynamic>> getProfile() async => {'display_name': role == 'teen_minor' ? 'آرام' : 'والد','email_normalized':'user@example.test','user_id':role == 'teen_minor' ? 'teen-1':'parent-1','theme_preference':themePreference};
  @override Future<Map<String,dynamic>> updateProfile({String? displayName,String? birthDate,String? themePreference}) async => {'display_name':displayName ?? 'والد','theme_preference':themePreference ?? 'adult_blue'};
  @override Future<List<Map<String,dynamic>>> listFamilies() async => [{'id':'family-1','name':'خانواده','role':role,'is_admin':role == 'parent_guardian'}];
  @override Future<List<Map<String,dynamic>>> listFamilyMembers(String familyId) async => [];
  @override Future<Map<String,dynamic>> createFamily(String name,{String? role}) async => {'id':'family-1','name':name};
  @override Future<void> inviteMember({required String familyId,required String email,required String role,String? themePreference}) async {}
  @override Future<void> acceptInvitation(String token) async {}
  @override Future<void> setGuardian({required String familyId,required String guardianUserId,required String minorUserId}) async {}
  @override Future<List<Map<String,dynamic>>> getToday({required DateTime from,required DateTime to}) async => [];
  @override Future<List<Map<String,dynamic>>> listPlanItems({DateTime? from,DateTime? to,String? kind}) async => [];
  @override Future<Map<String,dynamic>> createPlanItem(Map<String,dynamic> data) async => {'id':'new-plan',...data};
  @override Future<Map<String,dynamic>> updatePlanItem(String itemId,Map<String,dynamic> data) async => {'id':itemId,...data};
  @override Future<List<Map<String,dynamic>>> listLifeContexts() async => [];
  @override Future<Map<String,dynamic>> createLifeContext({required String kind,required String title}) async => {'id':'ctx-1','kind':kind,'title':title};
  @override Future<Map<String,dynamic>> createAcademicYear(Map<String,dynamic> data) async => {'id':'year-1',...data};
  @override Future<Map<String,dynamic>> createAcademicTerm(String yearId,Map<String,dynamic> data) async => {'id':'term-1',...data};
  @override Future<Map<String,dynamic>> createSubject(String termId,Map<String,dynamic> data) async => {'id':'subject-1',...data};
  @override Future<Map<String,dynamic>> createClassSession(String subjectId,Map<String,dynamic> data) async => {'id':'class-1',...data};
  @override Future<Map<String,dynamic>> setGrade(String itemId,{required num points,required num outOf}) async => {'id':itemId};
  @override Future<List<Map<String,dynamic>>> claimDueReminders() async => [];
  @override Future<Map<String,dynamic>> getSchoolOverview(String studentUserId) async => {'years':[],'subjects':[],'workload':[],'grades':[]};
  @override Future<List<Map<String,dynamic>>> getTimetable(String studentUserId) async => [];
  @override Future<List<Map<String,dynamic>>> getFamilyCalendar(String familyId) async => [];
  @override Future<Map<String,dynamic>> getChildSupportSummary(String familyId,String studentUserId) async => {'upcoming':[],'metrics':{}};
  @override Future<Map<String,dynamic>> submitSyncMutations(List<Map<String,dynamic>> mutations) async => {'results':[]};
  @override Future<Map<String,dynamic>> createLearningGoal({required String title,String? target,String? subjectId}) async => {'id':'goal-1','title':title};
  @override Future<List<Map<String,dynamic>>> listLearningGoals() async => [];
  @override Future<Map<String,dynamic>> createLearningCheckin({String? learningGoalId,required int confidence,required int difficulty,String? note}) async => {'id':'checkin-1'};
  @override Future<Map<String,dynamic>> createWellbeingCheckin({required int mood,required int energy,required int stress,String? note,String visibility='private'}) async => {'id':'wellbeing-1'};
  @override Future<List<Map<String,dynamic>>> listWellbeingCheckins() async => [];
  @override Future<Map<String,dynamic>> createAiSession(String kind) async => {'id':'session-1'};
  @override Future<Map<String,dynamic>> sendAiMessage(String sessionId,String message) async => {'id':'message-1','body':'پاسخ آزمایشی همراه هوشمند'};
  @override Future<Map<String,dynamic>> getGuardianWellbeingSummary(String familyId,String minorUserId) async => {'summary':{},'safety':{},'rawNotesIncluded':false,'rawConversationIncluded':false};
  @override Future<Map<String,dynamic>> requestFamilyGuidance(String familyId,String minorUserId,String question) async => {'advice':'پیشنهاد آزمایشی','advisory':true,'medicalDiagnosis':false};
}

void main() {
  setUp(() { SharedPreferences.setMockInitialValues({}); });

  testWidgets('starts in Persian RTL with identity actions', (tester) async {
    await tester.pumpWidget(LifeMateApp(api: FakeApi()));
    expect(find.text('LifeMate'), findsOneWidget);
    expect(find.text('ورود'), findsOneWidget);
    expect(find.text('رمز عبور را فراموش کرده‌ام'), findsOneWidget);
  });

  testWidgets('registration explains 10-character password requirement', (tester) async {
    await tester.pumpWidget(LifeMateApp(api: FakeApi()));
    await tester.tap(find.text('ساخت حساب جدید'));
    await tester.pumpAndSettle();
    expect(find.text('حداقل ۱۰ کاراکتر'), findsOneWidget);
  });
}
