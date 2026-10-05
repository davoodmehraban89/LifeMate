import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'api.dart';

void main() => runApp(LifeMateApp());

class LifeMateApp extends StatelessWidget {
  LifeMateApp({super.key, IdentityApi? api}) : api = api ?? HttpIdentityApi();
  final IdentityApi api;

  @override
  Widget build(BuildContext context) {
    final uri = Uri.base;
    final token = uri.queryParameters['token'];
    Widget entry = SignInPage(
      api: api,
      invitationToken:
          token != null && uri.path.contains('accept-invitation') ? token : null,
    );
    if (token != null && uri.path.contains('verify-email')) {
      entry = VerifyEmailPage(api: api, token: token);
    } else if (token != null && uri.path.contains('reset-password')) {
      entry = ResetPasswordPage(api: api, token: token);
    }
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
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4D86E8)),
        scaffoldBackgroundColor: const Color(0xFFF8FAFD),
        inputDecorationTheme:
            const InputDecorationTheme(border: OutlineInputBorder()),
        useMaterial3: true,
      ),
      home: Directionality(textDirection: TextDirection.rtl, child: entry),
    );
  }
}

String errorText(Object error) {
  if (error is ApiException) {
    switch (error.code) {
      case 'invalid_credentials':
        return 'ایمیل یا رمز عبور صحیح نیست.';
      case 'email_not_verified':
        return 'ابتدا ایمیل حساب را تأیید کن.';
      case 'account_exists':
        return 'برای این ایمیل قبلاً حساب ساخته شده است.';
      case 'invalid_password':
        return 'رمز عبور باید حداقل ۱۰ کاراکتر باشد.';
      case 'invalid_current_password':
        return 'رمز فعلی صحیح نیست.';
      case 'invalid_or_expired_token':
        return 'لینک منقضی شده یا معتبر نیست.';
      case 'forbidden':
        return 'برای این عملیات دسترسی نداری.';
    }
  }
  return 'عملیات انجام نشد. دوباره تلاش کن.';
}

class SignInPage extends StatefulWidget {
  const SignInPage({super.key, required this.api, this.invitationToken});
  final IdentityApi api;
  final String? invitationToken;
  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final email = TextEditingController();
  final password = TextEditingController();
  bool busy = false;
  String? error;

  Future<void> submit() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.api.login(email.text, password.text);
      if (widget.invitationToken != null) {
        await widget.api.acceptInvitation(widget.invitationToken!);
      }
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => HomeShell(api: widget.api)),
      );
    } catch (e) {
      if (mounted) setState(() => error = errorText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

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
                  const Text('LifeMate',
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(fontSize: 32, fontWeight: FontWeight.w700)),
                  const Text('همراه شخصی، تحصیلی و خانوادگی',
                      textAlign: TextAlign.center),
                  const SizedBox(height: 28),
                  if (widget.invitationToken != null) ...[
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(12),
                        child: Text(
                            'برای قبول دعوت خانواده، با همان ایمیل دعوت‌شده وارد شو.'),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    controller: email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'ایمیل'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: password,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'رمز عبور'),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    Text(error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: busy ? null : submit,
                    child: Text(busy ? 'در حال ورود...' : 'ورود'),
                  ),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => RecoveryPage(api: widget.api))),
                    child: const Text('رمز عبور را فراموش کرده‌ام'),
                  ),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => RegistrationPage(api: widget.api))),
                    child: const Text('ساخت حساب جدید'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class RegistrationPage extends StatefulWidget {
  const RegistrationPage({super.key, required this.api});
  final IdentityApi api;
  @override
  State<RegistrationPage> createState() => _RegistrationPageState();
}

class _RegistrationPageState extends State<RegistrationPage> {
  final name = TextEditingController();
  final email = TextEditingController();
  final password = TextEditingController();
  final confirm = TextEditingController();
  bool busy = false;
  String? error;

  Future<void> submit() async {
    if (password.text != confirm.text) {
      setState(() => error = 'تکرار رمز عبور یکسان نیست.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.api.register(
          displayName: name.text, email: email.text, password: password.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('حساب ساخته شد. ایمیل تأیید را بررسی کن.')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => error = errorText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SimpleFormPage(
        title: 'ساخت حساب',
        busy: busy,
        error: error,
        action: 'ثبت‌نام و ارسال ایمیل تأیید',
        onPressed: submit,
        fields: [
          TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'نام')),
          TextField(
              controller: email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'ایمیل')),
          TextField(
              controller: password,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'رمز عبور')),
          TextField(
              controller: confirm,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'تکرار رمز عبور')),
        ],
      );
}

class RecoveryPage extends StatefulWidget {
  const RecoveryPage({super.key, required this.api});
  final IdentityApi api;
  @override
  State<RecoveryPage> createState() => _RecoveryPageState();
}

class _RecoveryPageState extends State<RecoveryPage> {
  final email = TextEditingController();
  bool busy = false;
  bool sent = false;
  String? error;

  Future<void> submit() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.api.forgotPassword(email.text);
      if (mounted) setState(() => sent = true);
    } catch (e) {
      if (mounted) setState(() => error = errorText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SimpleFormPage(
        title: 'بازیابی رمز عبور',
        busy: busy,
        error: error,
        action: sent ? 'لینک ارسال شد' : 'ارسال لینک بازیابی',
        onPressed: sent ? null : submit,
        fields: [
          TextField(
              controller: email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'ایمیل تأییدشده')),
          if (sent)
            const Text(
                'اگر حسابی با این ایمیل وجود داشته باشد، لینک بازیابی ارسال می‌شود.'),
        ],
      );
}

class VerifyEmailPage extends StatefulWidget {
  const VerifyEmailPage({super.key, required this.api, required this.token});
  final IdentityApi api;
  final String token;
  @override
  State<VerifyEmailPage> createState() => _VerifyEmailPageState();
}

class _VerifyEmailPageState extends State<VerifyEmailPage> {
  String message = 'در حال تأیید ایمیل...';
  @override
  void initState() {
    super.initState();
    verify();
  }

  Future<void> verify() async {
    try {
      await widget.api.verifyEmail(widget.token);
      if (mounted) setState(() => message = 'ایمیل با موفقیت تأیید شد.');
    } catch (e) {
      if (mounted) setState(() => message = errorText(e));
    }
  }

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Center(child: Text(message)));
}

class ResetPasswordPage extends StatefulWidget {
  const ResetPasswordPage({super.key, required this.api, required this.token});
  final IdentityApi api;
  final String token;
  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  final password = TextEditingController();
  final confirm = TextEditingController();
  bool busy = false;
  bool done = false;
  String? error;

  Future<void> submit() async {
    if (password.text != confirm.text) {
      setState(() => error = 'تکرار رمز عبور یکسان نیست.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.api.resetPassword(widget.token, password.text);
      if (mounted) setState(() => done = true);
    } catch (e) {
      if (mounted) setState(() => error = errorText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SimpleFormPage(
        title: 'ساخت رمز جدید',
        busy: busy,
        error: error,
        action: done ? 'رمز تغییر کرد' : 'ذخیره رمز جدید',
        onPressed: done ? null : submit,
        fields: [
          TextField(
              controller: password,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'رمز جدید')),
          TextField(
              controller: confirm,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'تکرار رمز جدید')),
        ],
      );
}

class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({super.key, required this.api});
  final IdentityApi api;
  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final current = TextEditingController();
  final next = TextEditingController();
  final confirm = TextEditingController();
  bool busy = false;
  String? error;

  Future<void> submit() async {
    if (next.text != confirm.text) {
      setState(() => error = 'تکرار رمز عبور یکسان نیست.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.api.changePassword(current.text, next.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('رمز عبور تغییر کرد.')));
      Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => error = errorText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SimpleFormPage(
        title: 'تغییر رمز عبور',
        busy: busy,
        error: error,
        action: 'ذخیره رمز جدید',
        onPressed: submit,
        fields: [
          TextField(
              controller: current,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'رمز فعلی')),
          TextField(
              controller: next,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'رمز جدید')),
          TextField(
              controller: confirm,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'تکرار رمز جدید')),
        ],
      );
}

class SimpleFormPage extends StatelessWidget {
  const SimpleFormPage({
    super.key,
    required this.title,
    required this.fields,
    required this.action,
    required this.onPressed,
    this.busy = false,
    this.error,
  });
  final String title;
  final List<Widget> fields;
  final String action;
  final VoidCallback? onPressed;
  final bool busy;
  final String? error;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                for (final field in fields)
                  Padding(
                      padding: const EdgeInsets.only(bottom: 12), child: field),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  ),
                FilledButton(
                    onPressed: busy ? null : onPressed,
                    child: Text(busy ? 'لطفاً صبر کن...' : action)),
              ],
            ),
          ),
        ),
      );
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.api});
  final IdentityApi api;
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int index = 0;
  String themePreference = 'adult_blue';
  static const pages = [
    'امروز',
    'برنامه هفتگی',
    'تقویم',
    'تکالیف و کارها',
    'امتحان‌ها و نمرات',
    'تمرکز',
    'همراه هوشمند'
  ];

  @override
  void initState() {
    super.initState();
    loadTheme();
  }

  Future<void> loadTheme() async {
    try {
      final profile = await widget.api.getProfile();
      if (mounted) {
        setState(() => themePreference =
            profile['theme_preference']?.toString() ?? 'adult_blue');
      }
    } catch (_) {}
  }

  Color get accent => themePreference == 'girl_pink'
      ? const Color(0xFFE58FB0)
      : const Color(0xFF4D86E8);

  @override
  Widget build(BuildContext context) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: ColorScheme.fromSeed(seedColor: accent),
          scaffoldBackgroundColor: Colors.white,
        ),
        child: Scaffold(
          appBar: AppBar(
            title: Text(pages[index]),
            actions: [
              IconButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => ProfileFamilyPage(api: widget.api))),
                icon: const Icon(Icons.person_outline),
              ),
            ],
          ),
          body: Center(
              child: Text(pages[index],
                  style: Theme.of(context).textTheme.headlineMedium)),
          bottomNavigationBar: NavigationBar(
            selectedIndex: index > 4 ? 0 : index,
            onDestinationSelected: (i) => setState(() => index = i),
            destinations: const [
              NavigationDestination(
                  icon: Icon(Icons.home_outlined), label: 'امروز'),
              NavigationDestination(
                  icon: Icon(Icons.schedule_outlined), label: 'برنامه'),
              NavigationDestination(
                  icon: Icon(Icons.calendar_month_outlined), label: 'تقویم'),
              NavigationDestination(
                  icon: Icon(Icons.task_alt_outlined), label: 'کارها'),
              NavigationDestination(
                  icon: Icon(Icons.school_outlined), label: 'امتحان‌ها'),
            ],
          ),
          drawer: Drawer(
            child: SafeArea(
              child: ListView(
                children: [
                  const ListTile(
                      title: Text('LifeMate'), subtitle: Text('منوی اصلی')),
                  ...pages.asMap().entries.map((entry) => ListTile(
                        title: Text(entry.value),
                        onTap: () {
                          setState(() => index = entry.key);
                          Navigator.pop(context);
                        },
                      )),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.family_restroom),
                    title: const Text('خانواده'),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => ProfileFamilyPage(api: widget.api))),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class ProfileFamilyPage extends StatefulWidget {
  const ProfileFamilyPage({super.key, required this.api});
  final IdentityApi api;
  @override
  State<ProfileFamilyPage> createState() => _ProfileFamilyPageState();
}

class _ProfileFamilyPageState extends State<ProfileFamilyPage> {
  late Future<List<dynamic>> data;
  @override
  void initState() {
    super.initState();
    data = load();
  }

  Future<List<dynamic>> load() async =>
      [await widget.api.getProfile(), await widget.api.listFamilies()];

  Future<void> editProfile(Map<String, dynamic> profile) async {
    final name = TextEditingController(
        text: profile['display_name']?.toString() ?? '');
    final theme = ValueNotifier<String>(
        profile['theme_preference']?.toString() ?? 'adult_blue');
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('ویرایش پروفایل'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'نام')),
          const SizedBox(height: 12),
          ValueListenableBuilder<String>(
            valueListenable: theme,
            builder: (_, value, __) => DropdownButtonFormField<String>(
              initialValue: value,
              decoration: const InputDecoration(labelText: 'تم'),
              items: const [
                DropdownMenuItem(
                    value: 'girl_pink', child: Text('سفید / صورتی')),
                DropdownMenuItem(
                    value: 'boy_blue', child: Text('سفید / آبی نوجوان')),
                DropdownMenuItem(
                    value: 'adult_blue', child: Text('سفید / آبی بزرگسال')),
              ],
              onChanged: (v) {
                if (v != null) theme.value = v;
              },
            ),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('انصراف')),
          FilledButton(
            onPressed: () async {
              await widget.api.updateProfile(
                  displayName: name.text.trim(),
                  themePreference: theme.value);
              if (dialogContext.mounted) Navigator.pop(dialogContext, true);
            },
            child: const Text('ذخیره'),
          ),
        ],
      ),
    );
    name.dispose();
    theme.dispose();
    if (saved == true && mounted) setState(() => data = load());
  }

  Future<void> createFamily() async {
    final name = TextEditingController();
    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('ساخت فضای خانواده'),
        content: TextField(
            controller: name,
            decoration: const InputDecoration(labelText: 'نام خانواده')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('انصراف')),
          FilledButton(
            onPressed: () async {
              if (name.text.trim().isEmpty) return;
              await widget.api
                  .createFamily(name.text.trim(), role: 'parent_guardian');
              if (dialogContext.mounted) Navigator.pop(dialogContext, true);
            },
            child: const Text('ساخت'),
          ),
        ],
      ),
    );
    name.dispose();
    if (created == true && mounted) setState(() => data = load());
  }

  Future<void> invite(String familyId) async {
    final email = TextEditingController();
    final choice = ValueNotifier<String>('daughter');
    final sent = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('دعوت فرزند / عضو'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'ایمیل')),
          const SizedBox(height: 12),
          ValueListenableBuilder<String>(
            valueListenable: choice,
            builder: (_, value, __) => DropdownButtonFormField<String>(
              initialValue: value,
              decoration: const InputDecoration(labelText: 'نوع عضو'),
              items: const [
                DropdownMenuItem(
                    value: 'daughter', child: Text('فرزند دختر — سفید / صورتی')),
                DropdownMenuItem(
                    value: 'son', child: Text('فرزند پسر — سفید / آبی')),
                DropdownMenuItem(
                    value: 'parent', child: Text('والد / سرپرست — سفید / آبی')),
                DropdownMenuItem(
                    value: 'adult', child: Text('عضو بزرگسال — سفید / آبی')),
              ],
              onChanged: (v) {
                if (v != null) choice.value = v;
              },
            ),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('انصراف')),
          FilledButton(
            onPressed: () async {
              final selected = choice.value;
              final role = selected == 'parent'
                  ? 'parent_guardian'
                  : selected == 'adult'
                      ? 'adult_member'
                      : 'teen_minor';
              final theme = selected == 'daughter'
                  ? 'girl_pink'
                  : selected == 'son'
                      ? 'boy_blue'
                      : 'adult_blue';
              await widget.api.inviteMember(
                  familyId: familyId,
                  email: email.text,
                  role: role,
                  themePreference: theme);
              if (dialogContext.mounted) Navigator.pop(dialogContext, true);
            },
            child: const Text('ارسال دعوت'),
          ),
        ],
      ),
    );
    email.dispose();
    choice.dispose();
    if (sent == true && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('دعوت ارسال شد.')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('پروفایل و خانواده')),
        body: FutureBuilder<List<dynamic>>(
          future: data,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(child: Text(errorText(snapshot.error!)));
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final profile = snapshot.data![0] as Map<String, dynamic>;
            final families = snapshot.data![1] as List<Map<String, dynamic>>;
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Card(
                  child: ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.person)),
                    title: Text(
                        profile['display_name']?.toString() ?? 'پروفایل من'),
                    subtitle:
                        Text(profile['email_normalized']?.toString() ?? ''),
                    trailing: IconButton(
                        onPressed: () => editProfile(profile),
                        icon: const Icon(Icons.edit_outlined)),
                  ),
                ),
                const SizedBox(height: 12),
                if (families.isEmpty)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.family_restroom),
                      title: const Text('هنوز فضای خانواده ساخته نشده'),
                      trailing: IconButton(
                          onPressed: createFamily,
                          icon: const Icon(Icons.add)),
                    ),
                  )
                else
                  ...families.map((family) => Card(
                        child: ListTile(
                          leading: const Icon(Icons.family_restroom),
                          title:
                              Text(family['name']?.toString() ?? 'خانواده'),
                          subtitle: Text(
                              '${family['is_admin'] == true ? 'مدیر خانواده · ' : ''}${family['role'] ?? ''}'),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => FamilyMembersPage(
                                api: widget.api,
                                familyId: family['id'].toString(),
                                familyName:
                                    family['name']?.toString() ?? 'خانواده',
                                isAdmin: family['is_admin'] == true,
                              ),
                            ),
                          ),
                          trailing: IconButton(
                              onPressed: () => invite(family['id'].toString()),
                              icon: const Icon(Icons.person_add_alt)),
                        ),
                      )),
                ListTile(
                  leading: const Icon(Icons.password),
                  title: const Text('تغییر رمز عبور'),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => ChangePasswordPage(api: widget.api))),
                ),
                const ListTile(
                  leading: Icon(Icons.privacy_tip_outlined),
                  title: Text('حریم خصوصی و دسترسی‌ها'),
                  subtitle:
                      Text('خصوصی، اعضای منتخب، والد/سرپرست، خانواده، ایمنی'),
                ),
              ],
            );
          },
        ),
        floatingActionButton: FloatingActionButton.extended(
            onPressed: createFamily,
            icon: const Icon(Icons.add),
            label: const Text('خانواده')),
      );
}

class FamilyMembersPage extends StatefulWidget {
  const FamilyMembersPage({
    super.key,
    required this.api,
    required this.familyId,
    required this.familyName,
    required this.isAdmin,
  });
  final IdentityApi api;
  final String familyId;
  final String familyName;
  final bool isAdmin;
  @override
  State<FamilyMembersPage> createState() => _FamilyMembersPageState();
}

class _FamilyMembersPageState extends State<FamilyMembersPage> {
  late Future<List<Map<String, dynamic>>> members;
  @override
  void initState() {
    super.initState();
    members = widget.api.listFamilyMembers(widget.familyId);
  }

  String roleLabel(String role) => switch (role) {
        'parent_guardian' => 'والد / سرپرست',
        'teen_minor' => 'فرزند / نوجوان',
        'adult_member' => 'عضو بزرگسال',
        _ => role,
      };

  Future<void> configureGuardian(List<Map<String, dynamic>> items) async {
    final guardians =
        items.where((m) => m['role'] == 'parent_guardian').toList();
    final minors = items.where((m) => m['role'] == 'teen_minor').toList();
    if (guardians.isEmpty || minors.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('برای ثبت سرپرستی، حداقل یک والد و یک فرزند لازم است.')));
      return;
    }
    final guardianId =
        ValueNotifier<String>(guardians.first['user_id'].toString());
    final minorId = ValueNotifier<String>(minors.first['user_id'].toString());
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('رابطه والد و فرزند'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          ValueListenableBuilder<String>(
            valueListenable: guardianId,
            builder: (_, value, __) => DropdownButtonFormField<String>(
              initialValue: value,
              decoration: const InputDecoration(labelText: 'والد / سرپرست'),
              items: guardians
                  .map((m) => DropdownMenuItem(
                      value: m['user_id'].toString(),
                      child: Text(m['display_name']?.toString() ?? 'والد')))
                  .toList(),
              onChanged: (v) {
                if (v != null) guardianId.value = v;
              },
            ),
          ),
          const SizedBox(height: 12),
          ValueListenableBuilder<String>(
            valueListenable: minorId,
            builder: (_, value, __) => DropdownButtonFormField<String>(
              initialValue: value,
              decoration: const InputDecoration(labelText: 'فرزند'),
              items: minors
                  .map((m) => DropdownMenuItem(
                      value: m['user_id'].toString(),
                      child: Text(m['display_name']?.toString() ?? 'فرزند')))
                  .toList(),
              onChanged: (v) {
                if (v != null) minorId.value = v;
              },
            ),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('انصراف')),
          FilledButton(
            onPressed: () async {
              await widget.api.setGuardian(
                  familyId: widget.familyId,
                  guardianUserId: guardianId.value,
                  minorUserId: minorId.value);
              if (dialogContext.mounted) Navigator.pop(dialogContext, true);
            },
            child: const Text('ثبت رابطه'),
          ),
        ],
      ),
    );
    guardianId.dispose();
    minorId.dispose();
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('رابطه سرپرستی ثبت شد.')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.familyName)),
        body: FutureBuilder<List<Map<String, dynamic>>>(
          future: members,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(child: Text(errorText(snapshot.error!)));
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final items = snapshot.data!;
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                for (final member in items)
                  Card(
                    child: ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.person)),
                      title:
                          Text(member['display_name']?.toString() ?? 'عضو'),
                      subtitle:
                          Text(roleLabel(member['role']?.toString() ?? '')),
                      trailing: member['is_admin'] == true
                          ? const Chip(label: Text('مدیر'))
                          : null,
                    ),
                  ),
                if (widget.isAdmin) ...[
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => configureGuardian(items),
                    icon: const Icon(Icons.supervisor_account_outlined),
                    label: const Text('تنظیم رابطه والد و فرزند'),
                  ),
                ],
              ],
            );
          },
        ),
      );
}
