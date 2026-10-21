import 'package:flutter/material.dart';

import 'reminder_coordinator.dart';
import 'reminders.dart';
import 'store.dart';

class StandaloneReminderSettings extends StatefulWidget {
  const StandaloneReminderSettings(
      {super.key, required this.store, required this.coordinator});
  final StandaloneStore store;
  final StandaloneReminderCoordinator coordinator;
  @override
  State<StandaloneReminderSettings> createState() =>
      _StandaloneReminderSettingsState();
}

class _StandaloneReminderSettingsState extends State<StandaloneReminderSettings>
    with WidgetsBindingObserver {
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _run(() => widget.coordinator.refresh(widget.store));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_busy) {
      _run(() => widget.coordinator.refresh(widget.store));
    }
  }

  Future<void> _run(Future<void> Function() work) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await work();
    } catch (_) {/* Coordinator shows a safe Persian error. */} finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: widget.coordinator,
      builder: (context, _) {
        final state = widget.coordinator.status;
        return Scaffold(
          appBar: AppBar(title: const Text('یادآوری‌های من')),
          body: SafeArea(
              child: ListView(padding: const EdgeInsets.all(20), children: [
            const Text('یادآوری روی همین گوشی',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            const Text(
                'وقتی زمان برنامه‌ات برسد، همراهت یادت می‌اندازد. با اجازهٔ تو، نام همراه و یک پیام عمومی نمایش داده می‌شود؛ عنوان خصوصی برنامه روی اعلان نمی‌آید. اینترنت و سرور لازم نیست.'),
            const SizedBox(height: 16),
            if (widget.coordinator.error != null)
              Card(
                  child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(widget.coordinator.error!))),
            if (_busy)
              const LinearProgressIndicator(
                  semanticsLabel: 'در حال بررسی یادآوری'),
            if (state != null && !state.supported)
              const Text(
                  'یادآوری در این محیط در دسترس نیست؛ برنامه‌ها همچنان روی گوشی ذخیره می‌شوند.'),
            if (state != null && state.supported) ...[
              SwitchListTile.adaptive(
                title: const Text('اعلان برنامه‌های من'),
                subtitle: Text(
                    state.enabled ? 'انتخاب تو: روشن' : 'انتخاب تو: خاموش'),
                value: state.enabled,
                onChanged: _busy
                    ? null
                    : (value) => _run(() => value
                        ? widget.coordinator.enable(widget.store)
                        : widget.coordinator.disable(widget.store)),
              ),
              Text(state.permissionGranted
                  ? 'مجوز اعلان: داده شده'
                  : 'مجوز اعلان: داده نشده. اجازهٔ اعلان را از تنظیمات اندروید بررسی کن.'),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                  key: const Key('personal-notification-system-settings'),
                  style:
                      OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
                  onPressed: _busy
                      ? null
                      : () => _run(widget.coordinator.openNotificationSettings),
                  icon: const Icon(Icons.volume_up_outlined),
                  label: const Text('تنظیم صدا و اعلان در اندروید')),
              const Text(
                  'صدایی را انتخاب کن که دوست داری. تنظیم صدا و لرزش در اندروید انجام می‌شود؛ پس از برگشت، اجازهٔ اعلان دوباره بررسی می‌شود.'),
              const SizedBox(height: 12),
              Text('یادآوری آیندهٔ زمان‌بندی‌شده: ${state.scheduledCount}'),
              Text(state.timing == 'exact'
                  ? 'زمان‌بندی دقیق در دسترس است.'
                  : 'زمان‌بندی تقریبی است؛ ممکن است اندروید اعلان را با تأخیر نشان دهد.'),
              if (state.exactAlarmSupported && !state.canScheduleExactAlarms)
                OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _run(() => widget.coordinator
                            .requestExactAccess(widget.store)),
                    icon: const Icon(Icons.alarm),
                    label: const Text('بررسی اجازهٔ زمان‌بندی دقیق')),
            ],
            const SizedBox(height: 20),
            const Text('پوشش یادآوری',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Text(
                'تا ۲۸ روز آینده و حداکثر ۱۲۸ نوبت نزدیک‌تر آماده می‌شود. برنامه را مرتب باز کن تا روزهای بعد هم آماده شوند. برای هر برنامه، زمان یادآوری را جدا انتخاب کن.'),
            if (state != null &&
                state.eligibleCount > StandaloneReminderStatus.maximumReminders)
              const Text(
                  'تعداد نوبت‌ها بیشتر از ظرفیت است؛ فعلاً فقط ۱۲۸ نوبت نزدیک‌تر آماده شده‌اند.'),
            const SizedBox(height: 12),
            const Text(
                'خاموش‌کردن اجباری برنامه، تنظیم باتری، بی‌صدا بودن گوشی و مجوزهای اندروید می‌توانند اعلان یا صدای آن را متوقف کنند. اعلان زمان‌بندی‌شده تضمین شنیدن آلارم نیست.'),
            const SizedBox(height: 16),
            OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () =>
                        _run(() => widget.coordinator.refresh(widget.store)),
                icon: const Icon(Icons.refresh),
                label: const Text('بررسی دوباره')),
          ])),
        );
      });
}
