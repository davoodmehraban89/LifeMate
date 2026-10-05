import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

void main() => runApp(const LifeMateApp());

enum MemberRole { teen, parent, adult }
enum ProfileTheme { girlPink, boyBlue, adultBlue }

class LifeMateApp extends StatelessWidget {
  const LifeMateApp({super.key});

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF4D86E8);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('fa'),
      supportedLocales: const [Locale('fa'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: accent, surface: Colors.white),
        scaffoldBackgroundColor: const Color(0xFFF8FAFD),
        useMaterial3: true,
      ),
      home: const Directionality(textDirection: TextDirection.rtl, child: SignInPage()),
    );
  }
}

class SignInPage extends StatefulWidget {
  const SignInPage({super.key});
  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final email = TextEditingController();
  final password = TextEditingController();

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: ListView(
                padding: const EdgeInsets.all(28),
                shrinkWrap: true,
                children: [
                  const Icon(Icons.route_rounded, size: 64),
                  const SizedBox(height: 16),
                  const Text('LifeMate', textAlign: TextAlign.center, style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700)),
                  const Text('همراه شخصی، تحصیلی و خانوادگی', textAlign: TextAlign.center),
                  const SizedBox(height: 32),
                  TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'ایمیل', border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  TextField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'رمز عبور', border: OutlineInputBorder())),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: () => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const HomeShell())), child: const Text('ورود')),
                  TextButton(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RecoveryPage())), child: const Text('رمز عبور را فراموش کرده‌ام')),
                  TextButton(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RegistrationPage())), child: const Text('ساخت حساب جدید')),
                ],
              ),
            ),
          ),
        ),
      );
}

class RegistrationPage extends StatelessWidget {
  const RegistrationPage({super.key});
  @override
  Widget build(BuildContext context) => const _FormScaffold(title: 'ساخت حساب', fields: ['نام', 'ایمیل', 'رمز عبور', 'تکرار رمز عبور'], action: 'ثبت‌نام و ارسال ایمیل تأیید');
}

class RecoveryPage extends StatelessWidget {
  const RecoveryPage({super.key});
  @override
  Widget build(BuildContext context) => const _FormScaffold(title: 'بازیابی رمز عبور', fields: ['ایمیل تأییدشده'], action: 'ارسال لینک بازیابی');
}

class ChangePasswordPage extends StatelessWidget {
  const ChangePasswordPage({super.key});
  @override
  Widget build(BuildContext context) => const _FormScaffold(title: 'تغییر رمز عبور', fields: ['رمز فعلی', 'رمز جدید', 'تکرار رمز جدید'], action: 'ذخیره رمز جدید');
}

class _FormScaffold extends StatelessWidget {
  const _FormScaffold({required this.title, required this.fields, required this.action});
  final String title;
  final List<String> fields;
  final String action;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 520), child: ListView(padding: const EdgeInsets.all(24), children: [
          ...fields.map((f) => Padding(padding: const EdgeInsets.only(bottom: 12), child: TextField(obscureText: f.contains('رمز'), decoration: InputDecoration(labelText: f, border: const OutlineInputBorder())))),
          FilledButton(onPressed: () {}, child: Text(action)),
        ]))),
      );
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int index = 0;
  static const destinations = ['امروز', 'برنامه', 'تقویم', 'کارها', 'امتحان‌ها', 'تمرکز', 'همراه هوشمند'];
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(destinations[index]), actions: [IconButton(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfileFamilyPage())), icon: const Icon(Icons.person_outline))]),
        body: Center(child: Text(destinations[index], style: Theme.of(context).textTheme.headlineMedium)),
        bottomNavigationBar: NavigationBar(
          selectedIndex: index > 4 ? 0 : index,
          onDestinationSelected: (i) => setState(() => index = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_outlined), label: 'امروز'),
            NavigationDestination(icon: Icon(Icons.schedule_outlined), label: 'برنامه'),
            NavigationDestination(icon: Icon(Icons.calendar_month_outlined), label: 'تقویم'),
            NavigationDestination(icon: Icon(Icons.task_alt_outlined), label: 'کارها'),
            NavigationDestination(icon: Icon(Icons.school_outlined), label: 'امتحان‌ها'),
          ],
        ),
        drawer: Drawer(child: SafeArea(child: ListView(children: [
          const ListTile(title: Text('LifeMate'), subtitle: Text('منو')),
          ...destinations.asMap().entries.map((e) => ListTile(title: Text(e.value), onTap: () { setState(() => index = e.key); Navigator.pop(context); })),
          const Divider(),
          ListTile(leading: const Icon(Icons.family_restroom), title: const Text('خانواده'), onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfileFamilyPage()))),
        ]))),
      );
}

class ProfileFamilyPage extends StatelessWidget {
  const ProfileFamilyPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('پروفایل و خانواده')),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          const Card(child: ListTile(leading: CircleAvatar(child: Icon(Icons.person)), title: Text('پروفایل من'), subtitle: Text('نقش، اطلاعات شخصی و تم'))),
          Card(child: Column(children: [
            const ListTile(leading: Icon(Icons.family_restroom), title: Text('Family Workspace'), subtitle: Text('اعضا، نقش‌ها و دسترسی‌ها')),
            ListTile(leading: const Icon(Icons.person_add_alt), title: const Text('دعوت عضو'), onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const _FormScaffold(title: 'دعوت به خانواده', fields: ['ایمیل', 'نقش'], action: 'ارسال دعوت')))),
          ])),
          ListTile(leading: const Icon(Icons.password), title: const Text('تغییر رمز عبور'), onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ChangePasswordPage()))),
          const ListTile(leading: Icon(Icons.privacy_tip_outlined), title: Text('حریم خصوصی و دسترسی‌ها'), subtitle: Text('خصوصی، اعضای منتخب، والد/سرپرست، خانواده، ایمنی')),
        ]),
      );
}
