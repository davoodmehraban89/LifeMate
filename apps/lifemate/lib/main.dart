import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'api.dart';
import 'iran_hub.dart';
import 'phase3_ui.dart';
import 'runtime_controller.dart';
import 'endpoint_settings.dart';
import 'offline_store.dart';
import 'notifications_ui.dart';
import 'sync_changes_ui.dart';
import 'package:flutter/foundation.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const LifeMateApp());
}

class LifeMateApp extends StatefulWidget {
  const LifeMateApp({super.key, this.api, this.runtime});
  final IdentityApi? api;
  final RuntimeController? runtime;

  @override
  State<LifeMateApp> createState() => _LifeMateAppState();
}

class _LifeMateAppState extends State<LifeMateApp> {
  RuntimeController? runtime;
  bool invitationAccepted = false;
  GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  Object? navigatorScope;

  @override
  void initState() {
    super.initState();
    if (widget.api == null) {
      runtime = widget.runtime ??
          RuntimeController(onScopeDiscarded: OfflineStore.clearNamespace);
      if (!runtime!.initialized) runtime!.initialize();
    }
  }

  @override
  void dispose() {
    if (widget.runtime == null) runtime?.dispose();
    super.dispose();
  }

  Future<void> editEndpoints() async {
    final controller = runtime!;
    await navigatorKey.currentState!.push(MaterialPageRoute(
      builder: (_) => EndpointSettingsPage(
        initialConfig: controller.config,
        onSaved: (next) async {
          final api = controller.api;
          if (api?.accessToken != null &&
              !await confirmScopeDiscard(
                  navigatorKey.currentState!.overlay!.context, api!)) {
            return;
          }
          await controller.updateEndpoints(next);
        },
      ),
    ));
  }

  Widget entry(IdentityApi api, {bool managed = false}) {
    final uri = Uri.base;
    final token = uri.queryParameters['token'];
    final invitation =
        token != null && uri.path.contains('accept-invitation') ? token : null;
    if (api.accessToken != null) {
      if (managed && invitation != null && !invitationAccepted) {
        return _InvitationGate(
            api: api,
            token: invitation,
            onAccepted: () {
              if (mounted) setState(() => invitationAccepted = true);
            });
      }
      return HomeShell(
          api: api,
          onSignOut: managed ? runtime!.signOut : null,
          onEndpointSettings: managed ? editEndpoints : null);
    }
    if (token != null && uri.path.contains('verify-email')) {
      return VerifyEmailPage(api: api, token: token);
    }
    if (token != null && uri.path.contains('reset-password')) {
      return ResetPasswordPage(api: api, token: token);
    }
    return SignInPage(
        api: api,
        invitationToken: invitation,
        runtimeManaged: managed,
        onEndpointSettings: managed ? editEndpoints : null);
  }

  Widget app(Widget home, {Object? scope}) {
    if (navigatorScope != scope) {
      navigatorScope = scope;
      navigatorKey = GlobalKey<NavigatorState>();
      invitationAccepted = false;
    }
    return MaterialApp(
      navigatorKey: navigatorKey,
      key: ValueKey(scope),
      title: 'LifeGuide · لایف‌گاید',
      debugShowCheckedModeBanner: false,
      locale: const Locale('fa'),
      supportedLocales: const [Locale('fa'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        fontFamily: 'LifeGuidePersian',
        fontFamilyFallback: const ['LifeGuideLatin', 'LifeGuideEmoji'],
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4D86E8)),
        scaffoldBackgroundColor: const Color(0xFFF8FAFD),
        inputDecorationTheme:
            const InputDecorationTheme(border: OutlineInputBorder()),
        useMaterial3: true,
      ),
      home: Directionality(textDirection: TextDirection.rtl, child: home),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.api != null) return app(entry(widget.api!));
    return AnimatedBuilder(
        animation: runtime!,
        builder: (_, __) {
          final controller = runtime!;
          Widget home;
          if (!controller.initialized) {
            home = const Scaffold(
                body: Center(child: CircularProgressIndicator()));
          } else if (kIsWeb && controller.error != null) {
            home = Scaffold(
                appBar: AppBar(title: const Text('اتصال لایف‌گاید')),
                body: LoadError(
                    error: controller.error!, retry: controller.initialize));
          } else if (!controller.config.isConfigured ||
              controller.api == null) {
            home = EndpointSettingsPage(
                initialConfig: controller.config,
                onSaved: controller.updateEndpoints);
          } else if (controller.error != null &&
              controller.api!.accessToken == null) {
            home = Scaffold(
              appBar: AppBar(title: const Text('اتصال لایف‌گاید')),
              body: Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('بازیابی اتصال یا ورود انجام نشد.'),
                Text(errorText(controller.error!)),
                TextButton(
                    onPressed: controller.initialize,
                    child: const Text('تلاش دوباره')),
                TextButton(
                    onPressed: editEndpoints, child: const Text('تنظیم اتصال')),
              ])),
            );
          } else {
            home = entry(controller.api!, managed: true);
          }
          return app(home,
              scope:
                  '${controller.config.apiBaseUrl}|${controller.cacheNamespace ?? 'signed-out'}');
        });
  }
}

class _InvitationGate extends StatefulWidget {
  const _InvitationGate(
      {required this.api, required this.token, required this.onAccepted});
  final IdentityApi api;
  final String token;
  final VoidCallback onAccepted;
  @override
  State<_InvitationGate> createState() => _InvitationGateState();
}

class _InvitationGateState extends State<_InvitationGate> {
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    accept();
  }

  Future<void> accept() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.api.acceptInvitation(widget.token);
      if (mounted) widget.onAccepted();
    } catch (failure) {
      if (mounted) setState(() => error = errorText(failure));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('پذیرش دعوت خانواده')),
        body: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (busy) const CircularProgressIndicator(),
          if (error != null) Text(error!),
          if (!busy)
            TextButton(onPressed: accept, child: const Text('تلاش دوباره')),
        ])),
      );
}

Future<bool> confirmScopeDiscard(BuildContext context, IdentityApi api) async {
  int? pending;
  try {
    pending = await OfflineStore.forApi(api).pendingCount();
  } catch (_) {
    /* Unknown storage must also require an explicit discard choice. */
  }
  if (pending == 0) return true;
  if (!context.mounted) return false;
  return await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
                  title: const Text('تغییرهای تأییدنشده'),
                  content: Text(pending == null
                      ? 'وضعیت تغییر معلق دستگاه قابل خواندن نیست. خروج یا تغییر سرویس، داده و تغییرهای تأییدنشده این حساب را از دستگاه حذف می‌کند.'
                      : '$pending تغییر معلق هنوز در سرور تأیید نشده است. خروج یا تغییر سرویس، این تغییرها و نسخه ذخیره‌شده حساب را از دستگاه حذف می‌کند.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(c, false),
                        child: const Text('انصراف')),
                    FilledButton(
                        onPressed: () => Navigator.pop(c, true),
                        child: const Text('ادامه و حذف تغییرها'))
                  ])) ??
      false;
}

String errorText(Object error) {
  if (error is ApiException) {
    if (error.code.startsWith('local_') ||
        error.statusCode == 0 ||
        error.statusCode >= 500 ||
        error.statusCode == 403 ||
        [
          'sync_conflict',
          'version_conflict',
          'sms_unavailable',
          'invalid_or_expired_otp',
          'rate_limited'
        ].contains(error.code)) {
      return uiErrorText(error);
    }
    switch (error.code) {
      case 'invalid_credentials':
        return 'ایمیل یا رمز عبور صحیح نیست.';
      case 'email_not_verified':
        return 'ابتدا ایمیل حساب را تأیید کن.';
      case 'account_exists':
        return 'عملیات انجام نشد. دوباره تلاش کن.';
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
  const SignInPage(
      {super.key,
      required this.api,
      this.invitationToken,
      this.runtimeManaged = false,
      this.onEndpointSettings});
  final IdentityApi api;
  final String? invitationToken;
  final bool runtimeManaged;
  final Future<void> Function()? onEndpointSettings;
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
      if (!widget.runtimeManaged && widget.invitationToken != null) {
        await widget.api.acceptInvitation(widget.invitationToken!);
      }
      if (!mounted || widget.runtimeManaged) return;
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
                  const Text('LifeGuide',
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(fontSize: 32, fontWeight: FontWeight.w700)),
                  const Text('لایف‌گاید · همراه تحصیلی و خانوادگی',
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
                    decoration:
                        const InputDecoration(labelText: 'ایمیل یا شماره تلفن'),
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
                  if (widget.api is HttpIdentityApi) ...[
                    TextButton(
                        onPressed: busy
                            ? null
                            : () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => PhoneOtpPage(
                                        api: widget.api as HttpIdentityApi))),
                        child: const Text('ورود با کد پیامکی')),
                    TextButton(
                        onPressed: busy
                            ? null
                            : () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => ResendVerificationPage(
                                        api: widget.api as HttpIdentityApi))),
                        child: const Text('ارسال دوباره ایمیل تأیید')),
                  ],
                  if (widget.onEndpointSettings != null && !kIsWeb)
                    TextButton(
                        onPressed: busy ? null : widget.onEndpointSettings,
                        child: const Text('تنظیم اتصال')),
                ],
              ),
            ),
          ),
        ),
      );
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }
}

class RegistrationPage extends StatefulWidget {
  const RegistrationPage({super.key, required this.api});
  final IdentityApi api;
  @override
  State<RegistrationPage> createState() => _RegistrationPageState();
}

class _RegistrationPageState extends State<RegistrationPage> {
  final name = TextEditingController(),
      contact = TextEditingController(),
      password = TextEditingController(),
      confirm = TextEditingController();
  bool phone = false, busy = false;
  String? error, message;
  Future<void> submit() async {
    if (busy) return;
    if (name.text.trim().isEmpty || contact.text.trim().isEmpty) {
      setState(() => error = 'نام و یک راه تماس را وارد کن.');
      return;
    }
    if (password.text != confirm.text) {
      setState(() => error = 'تکرار رمز عبور یکسان نیست.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
      message = null;
    });
    try {
      if (widget.api is HttpIdentityApi) {
        await (widget.api as HttpIdentityApi).registerContact(
            displayName: name.text.trim(),
            password: password.text,
            email: phone ? null : contact.text.trim(),
            phone: phone ? contact.text.trim() : null);
      } else {
        await widget.api.register(
            displayName: name.text.trim(),
            email: contact.text.trim(),
            password: password.text);
      }
      if (mounted) {
        setState(() => message = phone
            ? 'درخواست بررسی شد. تحویل پیامک تنها پس از پاسخ سرویس ارسال مشخص می‌شود.'
            : 'درخواست بررسی شد. اگر این راه تماس واجد شرایط باشد، پیام تأیید ارسال می‌شود؛ تحویل ایمیل تأیید نشده است.');
      }
    } catch (e) {
      if (mounted) setState(() => error = errorText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    name.dispose();
    contact.dispose();
    password.dispose();
    confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SimpleFormPage(
          title: 'ساخت حساب',
          busy: busy,
          error: error,
          action: 'ثبت درخواست',
          onPressed: submit,
          fields: [
            TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'نام')),
            if (widget.api is HttpIdentityApi)
              SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('ایمیل')),
                    ButtonSegment(value: true, label: Text('تلفن'))
                  ],
                  selected: {
                    phone
                  },
                  onSelectionChanged:
                      busy ? null : (v) => setState(() => phone = v.first)),
            TextField(
                controller: contact,
                keyboardType:
                    phone ? TextInputType.phone : TextInputType.emailAddress,
                decoration: InputDecoration(
                    labelText: phone ? 'شماره تلفن' : 'ایمیل',
                    helperText: 'فقط یک راه تماس برای این حساب ثبت می‌شود.')),
            TextField(
                controller: password,
                obscureText: true,
                decoration: const InputDecoration(
                    labelText: 'رمز عبور', helperText: 'حداقل ۱۰ کاراکتر')),
            TextField(
                controller: confirm,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'تکرار رمز عبور')),
            if (message != null) Text(message!),
            if (message != null && phone && widget.api is HttpIdentityApi)
              TextButton(
                  onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => PhoneOtpPage(
                              api: widget.api as HttpIdentityApi,
                              initialPhone: contact.text,
                              purpose: 'verify'))),
                  child: const Text('تأیید شماره تلفن')),
          ]);
}

class ResendVerificationPage extends StatefulWidget {
  const ResendVerificationPage({super.key, required this.api});
  final HttpIdentityApi api;
  @override
  State<ResendVerificationPage> createState() => _ResendVerificationPageState();
}

class _ResendVerificationPageState extends State<ResendVerificationPage> {
  final email = TextEditingController();
  bool busy = false;
  String? error, message;
  Future<void> send() async {
    setState(() {
      busy = true;
      error = null;
      message = null;
    });
    try {
      await widget.api.resendVerification(email.text.trim());
      if (mounted) {
        setState(() => message =
            'درخواست بررسی شد. اگر این ایمیل واجد شرایط باشد، پیام تأیید ارسال می‌شود؛ تحویل آن تأیید نشده است.');
      }
    } catch (e) {
      if (mounted) setState(() => error = errorText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SimpleFormPage(
          title: 'ارسال دوباره ایمیل تأیید',
          busy: busy,
          error: error,
          action: 'ثبت درخواست ارسال',
          onPressed: send,
          fields: [
            TextField(
                controller: email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'ایمیل')),
            if (message != null) Text(message!)
          ]);
}

class PhoneOtpPage extends StatefulWidget {
  const PhoneOtpPage(
      {super.key,
      required this.api,
      this.initialPhone = '',
      this.purpose = 'login'});
  final HttpIdentityApi api;
  final String initialPhone, purpose;
  @override
  State<PhoneOtpPage> createState() => _PhoneOtpPageState();
}

class _PhoneOtpPageState extends State<PhoneOtpPage> {
  late final TextEditingController phone;
  final code = TextEditingController(), password = TextEditingController();
  String? challenge, error, message;
  bool busy = false;
  String purpose = 'login';
  @override
  void initState() {
    super.initState();
    phone = TextEditingController(text: widget.initialPhone);
    purpose = widget.purpose;
  }

  Future<void> request() async {
    setState(() {
      busy = true;
      error = null;
      message = null;
      challenge = null;
    });
    try {
      final response =
          await widget.api.requestPhoneOtp(phone.text.trim(), purpose: purpose);
      final id = response['challengeId'];
      if (id is! String || id.isEmpty) {
        throw const ApiException(502, 'invalid_otp_response');
      }
      if (mounted) {
        setState(() {
          challenge = id;
          message = 'درخواست کد پذیرفته شد. تحویل پیامک تأیید نشده است.';
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = errorText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> verify() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.api.verifyPhoneOtp(challenge!, code.text.trim(),
          newPassword: password.text.isEmpty ? null : password.text);
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) setState(() => error = errorText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    phone.dispose();
    code.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SimpleFormPage(
          title: 'ورود و تأیید تلفن',
          busy: busy,
          error: error,
          action: challenge == null ? 'درخواست کد' : 'تأیید کد',
          onPressed: challenge == null ? request : verify,
          fields: [
            if (challenge == null)
              DropdownButtonFormField<String>(
                  initialValue: purpose,
                  decoration: const InputDecoration(labelText: 'هدف درخواست'),
                  items: const [
                    DropdownMenuItem(value: 'login', child: Text('ورود')),
                    DropdownMenuItem(
                        value: 'verify', child: Text('تأیید شماره')),
                    DropdownMenuItem(
                        value: 'recovery', child: Text('بازیابی رمز'))
                  ],
                  onChanged: busy
                      ? null
                      : (v) => setState(() => purpose = v ?? purpose)),
            TextField(
                controller: phone,
                enabled: challenge == null && !busy,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'شماره تلفن')),
            if (challenge != null)
              TextField(
                  controller: code,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'کد پیامکی')),
            if (challenge != null)
              TextField(
                  controller: password,
                  obscureText: true,
                  decoration: const InputDecoration(
                      labelText: 'رمز عبور جدید',
                      helperText:
                          'برای تأیید اولیه و بازیابی، حداقل ۱۰ کاراکتر لازم است.')),
            if (message != null) Text(message!),
            if (challenge != null)
              TextButton(
                  onPressed: busy ? null : request,
                  child: const Text('درخواست کد تازه')),
          ]);
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
        action: sent ? 'درخواست بررسی شد' : 'ارسال لینک بازیابی',
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
  final password = TextEditingController(), confirm = TextEditingController();
  bool busy = false, done = false;
  String? error;
  Future<void> verify() async {
    if (password.text != confirm.text) {
      setState(() => error = 'تکرار رمز عبور یکسان نیست.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.api.verifyEmail(widget.token, newPassword: password.text);
      if (mounted) setState(() => done = true);
    } catch (e) {
      if (mounted) setState(() => error = errorText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    password.dispose();
    confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SimpleFormPage(
          title: 'تأیید مالکیت ایمیل',
          busy: busy,
          error: error,
          action: done ? 'ایمیل تأیید شد' : 'تأیید و تعیین رمز عبور',
          onPressed: done ? null : verify,
          fields: [
            const Text(
                'برای تکمیل مالکیت این حساب، رمز عبور جدید خودت را تعیین کن.'),
            TextField(
                controller: password,
                obscureText: true,
                decoration: const InputDecoration(
                    labelText: 'رمز عبور جدید',
                    helperText: 'حداقل ۱۰ کاراکتر')),
            TextField(
                controller: confirm,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'تکرار رمز عبور'))
          ]);
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
  const HomeShell(
      {super.key, required this.api, this.onSignOut, this.onEndpointSettings});
  final IdentityApi api;
  final Future<void> Function()? onSignOut;
  final Future<void> Function()? onEndpointSettings;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int index = 0;
  String themePreference = 'adult_blue';
  bool adultShell = false;
  String? contextError;

  static const studentPages = [
    'امروز',
    'برنامه هفتگی',
    'تقویم',
    'تکالیف و کارها',
    'امتحان‌ها و نمرات',
    'تمرکز',
    'همراه هوشمند',
  ];

  static const adultPages = [
    'امروز',
    'برنامه‌ریز',
    'خانواده',
    'راهنما',
    'من',
  ];

  @override
  void initState() {
    super.initState();
    loadContext();
  }

  Future<void> loadContext() async {
    try {
      final profile = await widget.api.getProfile();
      if (mounted) {
        setState(() {
          themePreference =
              profile['theme_preference']?.toString() ?? 'adult_blue';
          final category = profile['profile_category']?.toString();
          adultShell = category == 'adult' ||
              (!['girl_minor', 'boy_minor'].contains(category) &&
                  !['girl_pink', 'boy_blue'].contains(themePreference));
          contextError = null;
          if (index >= pages.length) index = pages.length - 1;
        });
      }
    } catch (error) {
      if (mounted) setState(() => contextError = errorText(error));
    }
  }

  List<String> get pages => adultShell ? adultPages : studentPages;

  Color get accent => themePreference == 'girl_pink'
      ? const Color(0xFFE58FB0)
      : const Color(0xFF4D86E8);

  List<NavigationDestination> get destinations => adultShell
      ? const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            label: 'امروز',
          ),
          NavigationDestination(
            icon: Icon(Icons.event_note_outlined),
            label: 'برنامه‌ریز',
          ),
          NavigationDestination(
            icon: Icon(Icons.family_restroom_outlined),
            label: 'خانواده',
          ),
          NavigationDestination(
            icon: Icon(Icons.assistant_outlined),
            label: 'راهنما',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            label: 'من',
          ),
        ]
      : const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            label: 'امروز',
          ),
          NavigationDestination(
            icon: Icon(Icons.schedule_outlined),
            label: 'برنامه',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            label: 'تقویم',
          ),
          NavigationDestination(
            icon: Icon(Icons.task_alt_outlined),
            label: 'کارها',
          ),
          NavigationDestination(
            icon: Icon(Icons.school_outlined),
            label: 'امتحان‌ها',
          ),
        ];

  void selectPage(int next) {
    setState(() => index = next);
  }

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
                onPressed: () async {
                  await Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => ProfileFamilyPage(api: widget.api)));
                  if (mounted) await loadContext();
                },
                icon: const Icon(Icons.person_outline),
              ),
            ],
          ),
          body: Column(children: [
            if (contextError != null)
              MaterialBanner(content: Text(contextError!), actions: [
                TextButton(
                    onPressed: loadContext, child: const Text('تلاش دوباره'))
              ]),
            Expanded(
                child: pages[index] == 'من'
                    ? ProfileFamilyPage(api: widget.api)
                    : (pages[index] == 'همراه هوشمند' ||
                            pages[index] == 'راهنما')
                        ? const CoreNotice(
                            title: 'همراه هوشمند',
                            subtitle:
                                'در این مرحله فعال نیست؛ داده سلامت و گفت‌وگو به سرویس هوشمند ارسال نمی‌شود.')
                        : Phase3HomeContent(
                            api: widget.api,
                            page: pages[index],
                            adultShell: adultShell,
                          ))
          ]),
          bottomNavigationBar: NavigationBar(
            selectedIndex: index > 4 ? 0 : index,
            onDestinationSelected: selectPage,
            destinations: destinations,
          ),
          drawer: Drawer(
            child: SafeArea(
              child: ListView(
                children: [
                  const ListTile(
                    title: Text('LifeGuide'),
                    subtitle: Text('منوی اصلی'),
                  ),
                  ...pages.asMap().entries.map(
                        (entry) => ListTile(
                          title: Text(entry.value),
                          onTap: () {
                            selectPage(entry.key);
                            Navigator.pop(context);
                          },
                        ),
                      ),
                  ListTile(
                      leading: const Icon(Icons.notifications_outlined),
                      title: const Text('اعلان‌های درون برنامه'),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) =>
                                NotificationInboxPage(api: widget.api)));
                      }),
                  ListTile(
                      leading: const Icon(Icons.sync_problem_outlined),
                      title: const Text('تغییرهای معلق و تعارض‌ها'),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => SyncChangesPage(api: widget.api)));
                      }),
                  if (widget.onEndpointSettings != null && !kIsWeb)
                    ListTile(
                        leading: const Icon(Icons.settings_ethernet),
                        title: const Text('تنظیم اتصال'),
                        onTap: () {
                          Navigator.pop(context);
                          widget.onEndpointSettings!();
                        }),
                  if (widget.onSignOut != null)
                    ListTile(
                        leading: const Icon(Icons.logout),
                        title: const Text('خروج از حساب'),
                        onTap: () async {
                          Navigator.pop(context);
                          try {
                            if (!await confirmScopeDiscard(
                                context, widget.api)) {
                              return;
                            }
                            await widget.onSignOut!();
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(errorText(e))));
                            }
                          }
                        }),
                  if (!adultShell) ...[
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.family_restroom),
                      title: const Text('خانواده'),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ProfileFamilyPage(api: widget.api),
                        ),
                      ),
                    ),
                  ],
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
    final saved = await showDialog<bool>(
        context: context,
        builder: (_) =>
            _AccountDialog(api: widget.api, mode: 'profile', profile: profile));
    if (saved == true && mounted) {
      setState(() {
        data = load();
      });
    }
  }

  Future<void> createFamily() async {
    final saved = await showDialog<bool>(
        context: context,
        builder: (_) => _AccountDialog(api: widget.api, mode: 'family'));
    if (saved == true && mounted) {
      setState(() {
        data = load();
      });
    }
  }

  Future<void> invite(String familyId) async {
    final saved = await showDialog<bool>(
        context: context,
        builder: (_) => _AccountDialog(
            api: widget.api, mode: 'invite', familyId: familyId));
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('درخواست دعوت پذیرفته شد؛ تحویل پیام تأیید نشده است.')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('پروفایل و خانواده')),
        body: FutureBuilder<List<dynamic>>(
          future: data,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return LoadError(
                  error: snapshot.error!,
                  retry: () {
                    setState(() {
                      data = load();
                    });
                  });
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
                          onPressed: createFamily, icon: const Icon(Icons.add)),
                    ),
                  )
                else
                  ...families.map((family) => Card(
                        child: ListTile(
                          leading: const Icon(Icons.family_restroom),
                          title: Text(family['name']?.toString() ?? 'خانواده'),
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
                              onPressed: family['is_admin'] == true
                                  ? () => invite(family['id'].toString())
                                  : null,
                              icon: const Icon(Icons.person_add_alt)),
                        ),
                      )),
                ListTile(
                  leading: const Icon(Icons.public),
                  title: const Text('خانواده و یادگیری ایران'),
                  subtitle: const Text(
                      'نقش‌ها، پایه تحصیلی، کتاب‌ها، تقویم و یادآوری'),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) =>
                        IranianFamilyLearningHub(identity: widget.api),
                  )),
                ),
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
    if (!items.any((m) => m['role'] == 'parent_guardian') ||
        !items.any((m) => m['role'] == 'teen_minor')) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('برای ثبت سرپرستی، حداقل یک والد و یک فرزند لازم است.')));
      return;
    }
    await showDialog<bool>(
        context: context,
        builder: (_) => _AccountDialog(
            api: widget.api,
            mode: 'guardian',
            familyId: widget.familyId,
            members: items));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.familyName)),
        body: FutureBuilder<List<Map<String, dynamic>>>(
          future: members,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return LoadError(
                  error: snapshot.error!,
                  retry: () {
                    setState(() {
                      members = widget.api.listFamilyMembers(widget.familyId);
                    });
                  });
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
                      title: Text(member['display_name']?.toString() ?? 'عضو'),
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

class _AccountDialog extends StatefulWidget {
  const _AccountDialog(
      {required this.api,
      required this.mode,
      this.profile,
      this.familyId,
      this.members = const []});
  final IdentityApi api;
  final String mode;
  final Map<String, dynamic>? profile;
  final String? familyId;
  final List<Map<String, dynamic>> members;
  @override
  State<_AccountDialog> createState() => _AccountDialogState();
}

class _AccountDialogState extends State<_AccountDialog> {
  late final TextEditingController name;
  String theme = 'adult_blue', choice = 'daughter', category = 'adult';
  bool phoneInvitation = false;
  String? invitationLink;
  String? guardian, minor, error;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    name = TextEditingController(
        text: widget.profile?['display_name']?.toString() ?? '');
    theme = widget.profile?['theme_preference']?.toString() ?? theme;
    category = widget.profile?['profile_category']?.toString() ??
        (theme == 'girl_pink'
            ? 'girl_minor'
            : theme == 'boy_blue'
                ? 'boy_minor'
                : 'adult');
    final gs = widget.members.where((m) => m['role'] == 'parent_guardian');
    final ms = widget.members.where((m) => m['role'] == 'teen_minor');
    guardian = gs.isEmpty ? null : gs.first['user_id'].toString();
    minor = ms.isEmpty ? null : ms.first['user_id'].toString();
  }

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (busy) return;
    if (widget.mode != 'guardian' && name.text.trim().isEmpty) {
      setState(() => error = 'این فیلد را وارد کن.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      switch (widget.mode) {
        case 'profile':
          await widget.api.updateProfile(
              displayName: name.text.trim(),
              themePreference: theme,
              profileCategory: category);
        case 'family':
          await widget.api
              .createFamily(name.text.trim(), role: 'parent_guardian');
        case 'invite':
          final role = choice == 'parent'
              ? 'parent_guardian'
              : choice == 'adult'
                  ? 'adult_member'
                  : 'teen_minor';
          final memberTheme = choice == 'daughter'
              ? 'girl_pink'
              : choice == 'son'
                  ? 'boy_blue'
                  : 'adult_blue';
          if (widget.api is HttpIdentityApi) {
            final result = await (widget.api as HttpIdentityApi)
                .createFamilyInvitation(
                    familyId: widget.familyId!,
                    email: phoneInvitation ? null : name.text.trim(),
                    phone: phoneInvitation ? name.text.trim() : null,
                    role: role,
                    themePreference: memberTheme);
            final link = result['invitationLink'];
            if (link is! String || link.isEmpty) {
              throw const ApiException(502, 'invalid_invitation_response');
            }
            if (mounted) setState(() => invitationLink = link);
          } else {
            await widget.api.inviteMember(
                familyId: widget.familyId!,
                email: name.text.trim(),
                role: role,
                themePreference: memberTheme);
          }
        case 'guardian':
          await widget.api.setGuardian(
              familyId: widget.familyId!,
              guardianUserId: guardian!,
              minorUserId: minor!);
      }
      if (mounted && invitationLink == null) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = errorText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !busy,
      child: AlertDialog(
          title: Text(switch (widget.mode) {
            'profile' => 'ویرایش پروفایل',
            'family' => 'ساخت فضای خانواده',
            'invite' => 'دعوت فرزند / عضو',
            _ => 'رابطه والد و فرزند'
          }),
          content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (invitationLink != null) ...[
                  const Text(
                      'پیوند دعوت آماده شد. تحویل ایمیل یا پیامک تأیید نشده است؛ پیوند را خودت به عضو موردنظر برسان.'),
                  SelectableText(invitationLink!),
                  TextButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(
                            ClipboardData(text: invitationLink!));
                      },
                      icon: const Icon(Icons.copy),
                      label: const Text('کپی پیوند دعوت'))
                ],
                if (invitationLink == null &&
                    widget.mode == 'invite' &&
                    widget.api is HttpIdentityApi)
                  SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: false, label: Text('ایمیل')),
                        ButtonSegment(value: true, label: Text('تلفن'))
                      ],
                      selected: {
                        phoneInvitation
                      },
                      onSelectionChanged: busy
                          ? null
                          : (v) => setState(() => phoneInvitation = v.first)),
                if (invitationLink == null && widget.mode != 'guardian')
                  TextField(
                      controller: name,
                      enabled: !busy,
                      decoration: InputDecoration(
                          labelText: widget.mode == 'invite'
                              ? (phoneInvitation ? 'شماره تلفن' : 'ایمیل')
                              : widget.mode == 'family'
                                  ? 'نام خانواده'
                                  : 'نام')),
                if (widget.mode == 'profile') ...[
                  DropdownButtonFormField<String>(
                      initialValue: category,
                      decoration:
                          const InputDecoration(labelText: 'نوع پروفایل'),
                      items: const [
                        DropdownMenuItem(
                            value: 'girl_minor', child: Text('دختر / نوجوان')),
                        DropdownMenuItem(
                            value: 'boy_minor', child: Text('پسر / نوجوان')),
                        DropdownMenuItem(value: 'adult', child: Text('بزرگسال'))
                      ],
                      onChanged: busy
                          ? null
                          : (v) => setState(() => category = v ?? category)),
                  const Text(
                      'نوع پروفایل، نقش یا اجازه سرپرستی خانواده ایجاد نمی‌کند.')
                ],
                if (widget.mode == 'profile')
                  DropdownButtonFormField<String>(
                      initialValue: theme,
                      decoration: const InputDecoration(labelText: 'تم'),
                      items: const [
                        DropdownMenuItem(
                            value: 'girl_pink', child: Text('سفید / صورتی')),
                        DropdownMenuItem(
                            value: 'boy_blue',
                            child: Text('سفید / آبی نوجوان')),
                        DropdownMenuItem(
                            value: 'adult_blue',
                            child: Text('سفید / آبی بزرگسال'))
                      ],
                      onChanged: busy
                          ? null
                          : (v) => setState(() => theme = v ?? theme)),
                if (invitationLink == null && widget.mode == 'invite')
                  DropdownButtonFormField<String>(
                      initialValue: choice,
                      decoration: const InputDecoration(labelText: 'نوع عضو'),
                      items: const [
                        DropdownMenuItem(
                            value: 'daughter',
                            child: Text('فرزند دختر — سفید / صورتی')),
                        DropdownMenuItem(
                            value: 'son',
                            child: Text('فرزند پسر — سفید / آبی')),
                        DropdownMenuItem(
                            value: 'parent',
                            child: Text('والد / سرپرست — سفید / آبی')),
                        DropdownMenuItem(
                            value: 'adult',
                            child: Text('عضو بزرگسال — سفید / آبی'))
                      ],
                      onChanged: busy
                          ? null
                          : (v) => setState(() => choice = v ?? choice)),
                if (widget.mode == 'guardian') ...[
                  DropdownButtonFormField<String>(
                      initialValue: guardian,
                      decoration:
                          const InputDecoration(labelText: 'والد / سرپرست'),
                      items: widget.members
                          .where((m) => m['role'] == 'parent_guardian')
                          .map((m) => DropdownMenuItem(
                              value: m['user_id'].toString(),
                              child: Text(
                                  m['display_name']?.toString() ?? 'والد')))
                          .toList(),
                      onChanged:
                          busy ? null : (v) => setState(() => guardian = v)),
                  DropdownButtonFormField<String>(
                      initialValue: minor,
                      decoration: const InputDecoration(labelText: 'فرزند'),
                      items: widget.members
                          .where((m) => m['role'] == 'teen_minor')
                          .map((m) => DropdownMenuItem(
                              value: m['user_id'].toString(),
                              child: Text(
                                  m['display_name']?.toString() ?? 'فرزند')))
                          .toList(),
                      onChanged:
                          busy ? null : (v) => setState(() => minor = v)),
                  const Text(
                      'ثبت رابطه فقط پس از بررسی مجوز سرور انجام می‌شود.'),
                ],
                if (error != null)
                  Text(error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
              ]))),
          actions: [
            TextButton(
                onPressed: busy ? null : () => Navigator.pop(context, false),
                child: const Text('انصراف')),
            FilledButton(
                onPressed: busy
                    ? null
                    : invitationLink != null
                        ? () => Navigator.pop(context, true)
                        : save,
                child: Text(busy
                    ? 'در حال ثبت...'
                    : invitationLink != null
                        ? 'بستن'
                        : 'ذخیره'))
          ]));
}
