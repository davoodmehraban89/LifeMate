import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'api.dart';
import 'main.dart' show HomeShell;

void main() => runApp(const LifeGuideRoleTestApp());

class LifeGuideRoleTestApp extends StatelessWidget {
  const LifeGuideRoleTestApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('fa'),
        supportedLocales: const [Locale('fa'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4D86E8)),
          scaffoldBackgroundColor: const Color(0xFFF8FAFD),
          inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
          useMaterial3: true,
        ),
        home: const Directionality(textDirection: TextDirection.rtl, child: RoleEntryPage()),
      );
}

class RoleEntryPage extends StatelessWidget {
  const RoleEntryPage({super.key});

  void enter(BuildContext context, String role, String label) {
    final api = LocalRoleTestApi(role: role, label: label);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => HomeShell(api: api)),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.all(28),
                children: [
                  const Icon(Icons.route_rounded, size: 72),
                  const SizedBox(height: 16),
                  const Text('Life Guide', textAlign: TextAlign.center, style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  const Text('چه کسی وارد می‌شود؟', textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 28),
                  _RoleButton(icon: Icons.school_rounded, title: 'فرزند / دانش‌آموز', subtitle: 'ورود به فضای شخصی و تحصیلی', onTap: () => enter(context, 'teen_minor', 'فرزند')),
                  const SizedBox(height: 12),
                  _RoleButton(icon: Icons.woman_rounded, title: 'مادر', subtitle: 'ورود به فضای والد و خانواده', onTap: () => enter(context, 'parent_guardian', 'مادر')),
                  const SizedBox(height: 12),
                  _RoleButton(icon: Icons.man_rounded, title: 'پدر', subtitle: 'ورود به فضای والد و خانواده', onTap: () => enter(context, 'parent_guardian', 'پدر')),
                  const SizedBox(height: 20),
                  const Text('نسخه آزمایشی: ورود ایمیل/رمز موقتاً غیرفعال است.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ),
        ),
      );
}

class _RoleButton extends StatelessWidget {
  const _RoleButton({required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          leading: Icon(icon, size: 36),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_left_rounded),
          onTap: onTap,
        ),
      );
}

class LocalRoleTestApi implements IdentityApi {
  LocalRoleTestApi({required this.role, required this.label});
  final String role;
  final String label;
  bool familyCreated = false;
  String familyName = 'خانواده من';
  @override String? accessToken = 'local-role-test';
  @override Future<void> login(String email, String password) async {}
  @override Future<void> register({required String displayName, required String email, required String password}) async {}
  @override Future<void> verifyEmail(String token) async {}
  @override Future<void> forgotPassword(String email) async {}
  @override Future<void> resetPassword(String token, String newPassword) async {}
  @override Future<void> changePassword(String currentPassword, String newPassword) async {}
  @override Future<Map<String,dynamic>> getProfile() async => {'display_name': label, 'email_normalized':'test@lifeguide.local', 'user_id': role == 'teen_minor' ? 'student-test' : 'parent-test', 'theme_preference': role == 'teen_minor' ? 'girl_pink' : 'adult_blue'};
  @override Future<Map<String,dynamic>> updateProfile({String? displayName,String? birthDate,String? themePreference}) async => {'display_name':displayName ?? label,'theme_preference':themePreference ?? 'adult_blue'};
  @override Future<List<Map<String,dynamic>>> listFamilies() async => familyCreated ? [{'id':'family-test','name':familyName,'role':role,'is_admin':role == 'parent_guardian'}] : [];
  @override Future<List<Map<String,dynamic>>> listFamilyMembers(String familyId) async => [];
  @override Future<Map<String,dynamic>> createFamily(String name,{String? role}) async { familyCreated=true; familyName=name; return {'id':'family-test','name':name}; }
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
  @override Future<Map<String,dynamic>> sendAiMessage(String sessionId,String message) async => {'id':'message-1','body':'پاسخ آزمایشی Life Guide'};
  @override Future<Map<String,dynamic>> getGuardianWellbeingSummary(String familyId,String minorUserId) async => {'summary':{},'safety':{},'rawNotesIncluded':false,'rawConversationIncluded':false};
  @override Future<Map<String,dynamic>> requestFamilyGuidance(String familyId,String minorUserId,String question) async => {'advice':'پیشنهاد آزمایشی','advisory':true,'medicalDiagnosis':false};
}
