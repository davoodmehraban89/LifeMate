import 'package:flutter/material.dart';

import 'model.dart';
import 'store.dart';

const _localNotice =
    'نسخهٔ شخصی این گوشی · بدون حساب و سرور\nبرنامه‌ها فقط روی همین گوشی نگه‌داری می‌شوند. همگام‌سازی، مشاهدهٔ خانواده و بازیابی از سرور ندارد. حذف برنامه یا پاک کردن داده‌های آن، برنامه‌های ذخیره‌شده را از بین می‌برد.';

String categoryLabel(StandaloneProfileCategory category) => switch (category) {
      StandaloneProfileCategory.girlMinor => 'دختر',
      StandaloneProfileCategory.boyMinor => 'پسر',
      StandaloneProfileCategory.adult => 'بزرگسال',
    };

class StandaloneOnboarding extends StatefulWidget {
  const StandaloneOnboarding(
      {super.key, required this.store, required this.onSaved});
  final StandaloneStore store;
  final Future<void> Function() onSaved;

  @override
  State<StandaloneOnboarding> createState() => _StandaloneOnboardingState();
}

class _StandaloneOnboardingState extends State<StandaloneOnboarding> {
  final _name = TextEditingController();
  StandaloneProfileCategory? _category;
  bool _busy = false;
  bool _committed = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    if (_name.text.trim().isEmpty || _category == null) {
      setState(() => _error = 'نام دلخواه و گروه خودت را انتخاب کن.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!_committed) {
        await widget.store.createProfile(
            displayName: _name.text.trim(), category: _category!);
        _committed = true;
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'نام روی این گوشی ذخیره نشد. فضای خالی گوشی را بررسی کن و دوباره تلاش کن.');
      }
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    try {
      await widget.onSaved();
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'نام روی این گوشی ذخیره شد؛ باز کردن برنامه انجام نشد. دوباره تلاش کن.');
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  const SizedBox(height: 24),
                  Icon(Icons.spa_outlined,
                      size: 56, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(height: 20),
                  Text('جای کوچکی برای برنامه‌های تو',
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  const Text(
                      'قدم‌های امروزت را بنویس و هر کدام را که انجام دادی تیک بزن.',
                      textAlign: TextAlign.center),
                  const SizedBox(height: 24),
                  const _LocalNoticeCard(),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _name,
                    enabled: !_busy && !_committed,
                    maxLength: 60,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                        labelText: 'دوست داری چه صدایت کنیم؟',
                        hintText: 'نام دلخواه'),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<StandaloneProfileCategory>(
                    initialValue: _category,
                    itemHeight: null,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'گروه من'),
                    items: StandaloneProfileCategory.values
                        .map((category) => DropdownMenuItem(
                            value: category,
                            child: Text(categoryLabel(category))))
                        .toList(),
                    onChanged: _busy || _committed
                        ? null
                        : (value) => setState(() => _category = value),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                      'این انتخاب فقط برای شخصی‌سازی است؛ نقش خانوادگی یا حساب کاربری ایجاد نمی‌کند.'),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(_error!,
                        key: const Key('onboarding-error'),
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _busy ? null : _save,
                    child: Text(_busy
                        ? 'در حال ذخیره…'
                        : _committed
                            ? 'باز کردن برنامهٔ من'
                            : 'شروع برنامهٔ من'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class StandaloneSettings extends StatefulWidget {
  const StandaloneSettings({
    super.key,
    required this.store,
    required this.profile,
    required this.onSaved,
    this.reminderSettings,
    this.onBeforeChange,
    this.onAfterChange,
  });
  final StandaloneStore store;
  final StandaloneProfile profile;
  final Future<void> Function() onSaved;
  final Widget? reminderSettings;
  final Future<void> Function()? onBeforeChange;
  final Future<void> Function()? onAfterChange;

  @override
  State<StandaloneSettings> createState() => _StandaloneSettingsState();
}

class _StandaloneSettingsState extends State<StandaloneSettings> {
  late final TextEditingController _name;
  late final TextEditingController _companion;
  late StandaloneProfileCategory _category;
  late String _theme;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.profile.displayName);
    _companion = TextEditingController(text: widget.profile.companionName);
    _category = widget.profile.category;
    _theme = StandaloneProfile.themeKeys.contains(widget.profile.themeKey)
        ? widget.profile.themeKey
        : 'violet';
  }

  @override
  void dispose() {
    _name.dispose();
    _companion.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'نام دلخواهت را بنویس.');
      return;
    }
    if (_companion.text.trim().isEmpty) {
      setState(() => _error = 'یک نام برای همراه انتخاب کن.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onBeforeChange?.call();
      await widget.store.updateProfile(
        displayName: _name.text.trim(),
        companionName: _companion.text.trim(),
        category: _category,
        themeKey: _theme,
      );
    } catch (_) {
      try {
        await widget.onAfterChange?.call();
      } catch (_) {/* Original save error remains visible. */}
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'تغییرها ذخیره نشد. فضای گوشی را بررسی کن و دوباره تلاش کن.';
        });
      }
      return;
    }
    // A reminder failure after the durable write must never invite duplicate saves.
    bool reminderFailed = false;
    try {
      await widget.onAfterChange?.call();
    } catch (_) {
      reminderFailed = true;
    }
    bool refreshFailed = false;
    try {
      await widget.onSaved();
    } catch (_) {
      refreshFailed = true;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(refreshFailed
            ? 'تغییرها ذخیره شد؛ برای دیدن تغییرها برنامه را دوباره باز کن.'
            : reminderFailed
                ? 'تغییرها ذخیره شد؛ وضعیت یادآوری را در تنظیمات بررسی کن.'
                : 'تغییرها روی این گوشی ذخیره شد.')));
  }

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('تنظیمات من', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          const _LocalNoticeCard(),
          const SizedBox(height: 24),
          TextField(
              controller: _name,
              enabled: !_busy,
              maxLength: 60,
              decoration: const InputDecoration(labelText: 'نام من')),
          const SizedBox(height: 16),
          TextField(
              controller: _companion,
              enabled: !_busy,
              maxLength: 40,
              decoration: const InputDecoration(
                  labelText: 'نام دلخواه همراه',
                  helperText: 'فقط یک نام شخصی روی همین گوشی است.')),
          const SizedBox(height: 16),
          DropdownButtonFormField<StandaloneProfileCategory>(
            initialValue: _category,
            itemHeight: null,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'گروه من'),
            items: StandaloneProfileCategory.values
                .map((category) => DropdownMenuItem(
                    value: category, child: Text(categoryLabel(category))))
                .toList(),
            onChanged:
                _busy ? null : (value) => setState(() => _category = value!),
          ),
          const SizedBox(height: 20),
          const Text('رنگ دلخواه؛ برای همهٔ گروه‌ها'),
          const SizedBox(height: 8),
          Wrap(spacing: 12, runSpacing: 8, children: [
            ChoiceChip(
                avatar: const CircleAvatar(backgroundColor: Color(0xff76609a)),
                label: const Text('بنفش آرام'),
                selected: _theme == 'violet',
                onSelected:
                    _busy ? null : (_) => setState(() => _theme = 'violet')),
            ChoiceChip(
                avatar: const CircleAvatar(backgroundColor: Color(0xff276e83)),
                label: const Text('آبی دریا'),
                selected: _theme == 'blue',
                onSelected:
                    _busy ? null : (_) => setState(() => _theme = 'blue')),
            ChoiceChip(
                avatar: const CircleAvatar(backgroundColor: Color(0xff397b65)),
                label: const Text('سبز نعنایی'),
                selected: _theme == 'mint',
                onSelected:
                    _busy ? null : (_) => setState(() => _theme = 'mint')),
            ChoiceChip(
                avatar: const CircleAvatar(backgroundColor: Color(0xffad5c4c)),
                label: const Text('مرجانی گرم'),
                selected: _theme == 'coral',
                onSelected:
                    _busy ? null : (_) => setState(() => _theme = 'coral')),
          ]),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 20),
          FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(_busy ? 'در حال ذخیره…' : 'ذخیرهٔ تغییرها')),
          const SizedBox(height: 24),
          if (widget.reminderSettings != null) widget.reminderSettings!,
          const SizedBox(height: 24),
          const Text(
              'تغییر نام، گروه یا رنگ، برنامه‌های قبلی را پاک نمی‌کند. برای حفظ داده‌ها، برنامه یا داده‌های آن را از تنظیمات گوشی حذف نکن.'),
        ],
      );
}

class _LocalNoticeCard extends StatelessWidget {
  const _LocalNoticeCard();

  @override
  Widget build(BuildContext context) => Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.phone_android_outlined,
                color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 12),
            const Expanded(child: Text(_localNotice)),
          ]),
        ),
      );
}
