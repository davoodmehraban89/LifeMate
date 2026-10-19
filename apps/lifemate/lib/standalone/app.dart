import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'model.dart';
import 'planner_ui.dart';
import 'settings_ui.dart';
import 'store.dart';

typedef StandaloneStoreOpener = Future<StandaloneStore> Function();
typedef StandaloneReminderSettingsBuilder = Widget Function(
    BuildContext context, StandaloneStore store);

/// This entry point is intentionally independent from identity and HTTP APIs.
class StandaloneApp extends StatefulWidget {
  const StandaloneApp({
    super.key,
    required this.openStore,
    this.reminderSettingsBuilder,
    this.onPlansChanged,
    this.onBeforePlansChange,
    this.onResumed,
  });

  final StandaloneStoreOpener openStore;
  final StandaloneReminderSettingsBuilder? reminderSettingsBuilder;
  final Future<void> Function(StandaloneStore store)? onPlansChanged;
  final Future<void> Function(StandaloneStore store)? onBeforePlansChange;
  final Future<void> Function(StandaloneStore store)? onResumed;

  @override
  State<StandaloneApp> createState() => _StandaloneAppState();
}

class _StandaloneAppState extends State<StandaloneApp> {
  StandaloneStore? _store;
  StandaloneProfile? _profile;
  bool _loading = true;
  bool _failed = false;
  int _attempt = 0;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    final attempt = ++_attempt;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final store = _store ?? await widget.openStore();
      if (!mounted || attempt != _attempt) return;
      _store = store;
      final profile = await store.profile();
      if (!mounted || attempt != _attempt) return;
      setState(() {
        _profile = profile;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || attempt != _attempt) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  Future<void> _profileSaved() async {
    final profile = await _store!.profile();
    if (mounted) setState(() => _profile = profile);
  }

  @override
  Widget build(BuildContext context) {
    final seed = switch (_profile?.themeKey) {
      'blue' => const Color(0xff276e83),
      'mint' => const Color(0xff397b65),
      'coral' => const Color(0xffad5c4c),
      _ => const Color(0xff76609a),
    };
    final colors = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.light,
    );
    return MaterialApp(
      title: 'LifeGuide · برنامهٔ من',
      debugShowCheckedModeBanner: false,
      locale: const Locale('fa'),
      supportedLocales: const [Locale('fa'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'LifeGuidePersian',
        fontFamilyFallback: const ['LifeGuideLatin', 'LifeGuideEmoji'],
        colorScheme: colors,
        scaffoldBackgroundColor: colors.surface,
        textTheme: const TextTheme(
          bodySmall: TextStyle(fontSize: 13, height: 1.7),
          bodyMedium: TextStyle(fontSize: 15, height: 1.7),
          bodyLarge: TextStyle(fontSize: 16, height: 1.7),
          labelSmall: TextStyle(fontSize: 12),
          labelMedium: TextStyle(fontSize: 13),
          labelLarge: TextStyle(fontSize: 14),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
          filled: true,
          fillColor: colors.surface,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(48, 52),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(minimumSize: const Size(48, 50)),
        ),
        iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
        ),
      ),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: _loading
            ? const Scaffold(
                body: Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                CircularProgressIndicator(),
                SizedBox(height: 20),
                Text('در حال باز کردن برنامهٔ این گوشی…'),
              ])))
            : _failed
                ? Scaffold(
                    body: SafeArea(
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(28),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.folder_off_outlined, size: 48),
                              const SizedBox(height: 20),
                              const Text('برنامه‌های این گوشی باز نشد.',
                                  textAlign: TextAlign.center),
                              const SizedBox(height: 12),
                              const Text(
                                'ممکن است فضای گوشی کافی نباشد یا فایل ذخیره‌سازی خوانده نشود. کمی فضا آزاد کنید و دوباره تلاش کنید. داده‌ها خودکار پاک نمی‌شوند.',
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 24),
                              FilledButton(
                                onPressed: _open,
                                child: const Text('تلاش دوباره'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  )
                : _profile == null
                    ? StandaloneOnboarding(
                        store: _store!, onSaved: _profileSaved)
                    : StandalonePlannerShell(
                        store: _store!,
                        profile: _profile!,
                        onProfileSaved: _profileSaved,
                        reminderSettingsBuilder: widget.reminderSettingsBuilder,
                        onPlansChanged: widget.onPlansChanged,
                        onBeforePlansChange: widget.onBeforePlansChange,
                        onResumed: widget.onResumed,
                      ),
      ),
    );
  }
}
