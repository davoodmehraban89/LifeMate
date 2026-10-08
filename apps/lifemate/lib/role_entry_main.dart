import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'local_data_store.dart';
import 'local_only_api.dart';
import 'main.dart' show HomeShell;
import 'phase3_ui.dart' show localDataErrorText;

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
          inputDecorationTheme:
              const InputDecorationTheme(border: OutlineInputBorder()),
          useMaterial3: true,
        ),
        home: const Directionality(
            textDirection: TextDirection.rtl, child: RoleEntryGate()),
      );
}

class LocalTestProfile {
  const LocalTestProfile({required this.category, required this.displayName});
  final String category;
  final String displayName;
}

class LocalTestProfileStore {
  static const _categoryKey = 'lifeguide.local_profile.category';
  static const _displayNameKey = 'lifeguide.local_profile.display_name';

  Future<LocalTestProfile?> load() async {
    final saved = await LocalDataStore.readSavedProfile();
    if (saved != null) {
      return LocalTestProfile(
          category: saved['profile_category'] as String,
          displayName: saved['display_name'] as String);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final category = prefs.getString(_categoryKey);
    final displayName = prefs.getString(_displayNameKey);
    if (!LocalDataStore.categories.contains(category) ||
        displayName == null ||
        displayName.trim().isEmpty) {
      return null;
    }
    return LocalTestProfile(category: category!, displayName: displayName);
  }

  Future<void> save(LocalTestProfile profile) async {
    final name = profile.displayName.trim();
    if (name.isEmpty) throw ArgumentError('displayName cannot be empty');
    if (!LocalDataStore.categories.contains(profile.category)) {
      throw ArgumentError('invalid profile category');
    }
    await LocalDataStore(category: profile.category, displayName: name)
        .mutate((data) {
      final saved = data['profile'] as Map<String, dynamic>;
      if (saved['profile_category'] != profile.category) {
        throw const ApiException(
            409, 'local_profile_change_requires_confirmation');
      }
      saved['display_name'] = name;
    });
  }
}

class RoleEntryGate extends StatefulWidget {
  const RoleEntryGate({super.key});

  @override
  State<RoleEntryGate> createState() => _RoleEntryGateState();
}

class _RoleEntryGateState extends State<RoleEntryGate> {
  final store = LocalTestProfileStore();
  LocalTestProfile? profile;
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final saved = await store.load();
      if (!mounted) return;
      setState(() {
        profile = saved;
        loading = false;
      });
    } catch (failure) {
      if (mounted) {
        setState(() {
          loading = false;
          error = localDataErrorText(failure);
        });
      }
    }
  }

  void _openHome(LocalTestProfile value) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => HomeShell(
          localOnly: true,
          profileCategory: value.category,
          api: LocalOnlyApi(
              category: value.category, displayName: value.displayName),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (error != null) {
      return Scaffold(
          body: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(error!, textAlign: TextAlign.center),
        TextButton(onPressed: _load, child: const Text('تلاش دوباره')),
      ])));
    }
    if (profile != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openHome(profile!);
      });
      return const Scaffold(body: SizedBox.shrink());
    }
    return RoleEntryPage(
      onComplete: (value) async {
        await store.save(value);
        if (mounted) _openHome(value);
      },
    );
  }
}

class RoleEntryPage extends StatefulWidget {
  const RoleEntryPage({super.key, required this.onComplete});
  final Future<void> Function(LocalTestProfile profile) onComplete;

  @override
  State<RoleEntryPage> createState() => _RoleEntryPageState();
}

class _RoleEntryPageState extends State<RoleEntryPage> {
  bool busy = false;

  Future<void> _choose(
      BuildContext context, String category, String fallbackName) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final name = await showDialog<String>(
          context: context,
          builder: (_) => _ProfileNameDialog(initialName: fallbackName));
      if (name == null || name.trim().isEmpty) return;
      await widget.onComplete(
          LocalTestProfile(category: category, displayName: name.trim()));
    } catch (failure) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(localDataErrorText(failure))),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
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
                  const Text('Life Guide',
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(fontSize: 32, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  const Text('چه کسی وارد می‌شود؟',
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  const Text(
                      'یک‌بار پروفایل را انتخاب و نام‌گذاری کن؛ دفعه‌های بعد مستقیم وارد فضای شخصی خودت می‌شوی.',
                      textAlign: TextAlign.center),
                  const SizedBox(height: 28),
                  _RoleButton(
                      icon: Icons.girl_rounded,
                      title: 'فرزند دختر',
                      subtitle: 'فضای شخصی و تحصیلی با تم دخترانه',
                      onTap: busy
                          ? null
                          : () => _choose(context, 'girl_minor', 'آرام')),
                  const SizedBox(height: 12),
                  _RoleButton(
                      icon: Icons.boy_rounded,
                      title: 'فرزند پسر',
                      subtitle: 'فضای شخصی و تحصیلی با تم پسرانه',
                      onTap: busy
                          ? null
                          : () => _choose(context, 'boy_minor', 'فرزند')),
                  const SizedBox(height: 12),
                  _RoleButton(
                      icon: Icons.person_rounded,
                      title: 'بزرگسال',
                      subtitle: 'فضای شخصی، خانواده و مدیریت',
                      onTap: busy
                          ? null
                          : () => _choose(context, 'adult', 'بزرگسال')),
                  const SizedBox(height: 20),
                  const Text('نسخه آزمایشی: ورود ایمیل/رمز موقتاً غیرفعال است.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ),
        ),
      );
}

class _RoleButton extends StatelessWidget {
  const _RoleButton(
      {required this.icon,
      required this.title,
      required this.subtitle,
      required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          leading: Icon(icon, size: 36),
          title:
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_left_rounded),
          onTap: onTap,
        ),
      );
}

class _ProfileNameDialog extends StatefulWidget {
  const _ProfileNameDialog({required this.initialName});
  final String initialName;
  @override
  State<_ProfileNameDialog> createState() => _ProfileNameDialogState();
}

class _ProfileNameDialogState extends State<_ProfileNameDialog> {
  final formKey = GlobalKey<FormState>();
  late final name = TextEditingController(text: widget.initialName);

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  void submit() {
    if (formKey.currentState!.validate()) {
      Navigator.pop(context, name.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('اسم این پروفایل چیست؟'),
        content: Form(
            key: formKey,
            child: TextFormField(
              controller: name,
              autofocus: true,
              maxLength: 120,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(labelText: 'نام نمایشی'),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'نام را وارد کن.'
                  : null,
              onFieldSubmitted: (_) => submit(),
            )),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('انصراف')),
          FilledButton(onPressed: submit, child: const Text('ادامه')),
        ],
      );
}
