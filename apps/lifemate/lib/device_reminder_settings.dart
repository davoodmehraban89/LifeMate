import 'package:flutter/material.dart';
import 'api.dart';
import 'device_reminder_coordinator.dart';
import 'device_reminder_preferences.dart';
import 'local_reminders.dart';

class DeviceReminderSettingsPage extends StatefulWidget {
  const DeviceReminderSettingsPage(
      {super.key, required this.api, this.coordinator});
  final HttpIdentityApi api;
  final DeviceReminderCoordinator? coordinator;
  @override
  State<DeviceReminderSettingsPage> createState() =>
      _DeviceReminderSettingsPageState();
}

class _DeviceReminderSettingsPageState extends State<DeviceReminderSettingsPage>
    with WidgetsBindingObserver {
  final _nickname = TextEditingController();
  final _preferences = DeviceReminderPreferences();
  LocalReminderStatus? _status;
  String? _error;
  bool _busy = true;
  DeviceReminderCoordinator get _coordinator =>
      widget.coordinator ?? DeviceReminderCoordinator(widget.api);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _run(_load);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _nickname.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_busy) _run(_refresh);
  }

  Future<void> _load() async {
    final scope = widget.api.cacheNamespace;
    if (scope == null) throw const ApiException(401, 'session_expired');
    final name = await _preferences.read(scope);
    final status = await _coordinator.status();
    if (!mounted || widget.api.cacheNamespace != scope) return;
    _nickname.text = name;
    _status = status;
  }

  Future<void> _refresh() async {
    _status = await _coordinator.reconcile();
  }

  Future<void> _run(Future<void> Function() work) async {
    if (mounted) {
      setState(() {
        _busy = true;
        _error = null;
      });
    }
    try {
      await work();
    } catch (error) {
      if (mounted) {
        _error = error is ArgumentError
            ? 'نام همراه باید حداکثر ۴۰ نویسه باشد و کاراکتر کنترلی نداشته باشد.'
            : error is ApiException && error.statusCode == 429
                ? 'درخواست‌ها زیاد است؛ کمی بعد دوباره تلاش کنید.'
                : error is ApiException && error.statusCode == 401
                    ? 'نشست پایان یافته؛ دوباره وارد شوید.'
                    : 'یادآوری آماده نشد. اتصال، مجوز اعلان و تنظیمات دستگاه را بررسی کنید؛ مهلت قبلی تمدید نشد.';
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _saveNickname() async {
    final scope = widget.api.cacheNamespace;
    if (scope == null) throw const ApiException(401, 'session_expired');
    await _preferences.write(scope, _nickname.text);
    _status = await _coordinator.reconcile();
  }

  String _localTime(DateTime value) {
    final local = value.toLocal();
    String two(int n) => '$n'.padLeft(2, '0');
    return '${local.year}/${two(local.month)}/${two(local.day)}، ${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final owned = status?.activeScope == widget.api.cacheNamespace;
    final enabled = status?.active == true && owned;
    final supported = status?.supported == true;
    return Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          appBar: AppBar(title: const Text('یادآوری و نام همراه')),
          body: ListView(padding: const EdgeInsets.all(16), children: [
            const Text('همراهِ خودت',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
            const SizedBox(height: 12),
            TextField(
                key: const ValueKey('companion-nickname'),
                controller: _nickname,
                maxLength: 40,
                enabled: !_busy,
                decoration: const InputDecoration(
                    labelText: 'نام همراه',
                    hintText: 'LifeGuide',
                    helperText:
                        'این نام بالای یادآوری می‌آید؛ نام رسمی برنامه لایف‌گاید می‌ماند.')),
            Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                    onPressed: _busy ? null : () => _run(_saveNickname),
                    child: const Text('ذخیرهٔ نام همراه'))),
            const Divider(height: 32),
            SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('یادآوری روی همین دستگاه'),
                subtitle: const Text(
                    'فعال‌سازی با اجازهٔ شما؛ عنوان و یادداشت خصوصی در اعلان نمایش داده نمی‌شود.'),
                value: enabled,
                onChanged: _busy || !supported
                    ? null
                    : (value) => _run(() async {
                          _status = value
                              ? await _coordinator.enable(
                                  companionName: _nickname.text.trim().isEmpty
                                      ? 'LifeGuide'
                                      : _nickname.text.trim())
                              : await _coordinator.disable();
                        })),
            if (status != null && !supported)
              const Text('اعلان پس‌زمینه در این دستگاه پشتیبانی نمی‌شود.'),
            if (supported && !status!.permissionGranted)
              const Text(
                  'مجوز اعلان یا کانال یادآوری در تنظیمات دستگاه بسته است.'),
            if (supported)
              Text(enabled
                  ? '${status!.scheduledCount} یادآوری برای این دستگاه آماده است.'
                  : 'یادآوری این حساب روی این دستگاه خاموش است.'),
            if (enabled && status?.validUntil != null)
              Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                      'مهلت یادآوری: ${_localTime(status!.validUntil!)}\nتمدید فقط با اتصال و دریافت تازه از سرور؛ دادهٔ آفلاین مهلت را تمدید نمی‌کند.')),
            if (supported)
              Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(status!.timing == 'exact'
                      ? 'مجوز زمان‌بندی دقیق برقرار است. تنظیمات باتری، بی‌صدا و مزاحم نشوید همچنان اثر دارند.'
                      : 'زمان‌بندی تقریبی است و ممکن است اعلان دیر برسد.')),
            if (supported &&
                status!.exactAlarmSupported &&
                !status.canScheduleExactAlarms)
              OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                            _status =
                                await _coordinator.requestExactAlarmAccess();
                          }),
                  child: const Text('اجازهٔ زمان‌بندی دقیق')),
            if (supported)
              OutlinedButton.icon(
                  onPressed: _busy ? null : () => _run(_refresh),
                  icon: const Icon(Icons.refresh),
                  label: const Text('دریافت تازه و آماده‌سازی یادآوری')),
            const SizedBox(height: 16),
            const Text(
                'بستن اجباری برنامه (Force stop)، خاموشی گوشی یا محدودیت باتری می‌تواند اعلان را متوقف کند. صدا و نمایش روی قفل در کنترل تنظیمات گوشی است. لمس اعلان، خانهٔ برنامه را باز می‌کند؛ برای تیک انجام، برنامه را باز کنید.'),
            if (_busy)
              const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator())),
            if (_error != null)
              Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(_error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error))),
          ]),
        ));
  }
}
