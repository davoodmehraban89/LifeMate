import 'package:flutter/material.dart';
import 'runtime_config.dart';

class EndpointSettingsPage extends StatefulWidget {
  const EndpointSettingsPage(
      {super.key, required this.initialConfig, required this.onSaved});
  final RuntimeConfig initialConfig;
  final Future<void> Function(RuntimeConfig) onSaved;
  @override
  State<EndpointSettingsPage> createState() => _EndpointSettingsState();
}

class _EndpointSettingsState extends State<EndpointSettingsPage> {
  late final TextEditingController primary =
      TextEditingController(text: widget.initialConfig.apiBaseUrl);
  late final TextEditingController fallback = TextEditingController(
      text: widget.initialConfig.apiFallbackUrls.join('\n'));
  bool busy = false;
  String? error;
  void selectFallback(String selected) {
    final alternatives = <String>[
      primary.text.trim(),
      ...fallback.text.split('\n').map((line) => line.trim())
    ].where((url) => url.isNotEmpty && url != selected).toSet();
    setState(() {
      primary.text = selected;
      fallback.text = alternatives.join('\n');
      error = null;
    });
  }

  Future<void> save() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final config = RuntimeConfig(
          apiBaseUrl: primary.text,
          apiFallbackUrls: fallback.text
              .split('\n')
              .map((line) => line.trim())
              .where((line) => line.isNotEmpty)
              .toList());
      if (!config.isConfigured) {
        throw ArgumentError('Primary endpoint is required.');
      }
      await widget.onSaved(config);
    } on ArgumentError {
      if (mounted) {
        setState(() => error =
            'نشانی HTTPS معتبر وارد کنید؛ بدون نام کاربری، رمز یا پارامتر اضافی.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = 'تنظیمات ذخیره نشد. دوباره تلاش کنید.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    primary.dispose();
    fallback.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('اتصال لایف‌گاید')),
        body: SafeArea(
            child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Center(
                  child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                                'نشانی سرویس خانواده را وارد کنید. تغییر سرویس شما را از حساب قبلی خارج می‌کند.'),
                            const SizedBox(height: 16),
                            TextField(
                                controller: primary,
                                textDirection: TextDirection.ltr,
                                keyboardType: TextInputType.url,
                                autocorrect: false,
                                decoration: const InputDecoration(
                                    labelText: 'نشانی اصلی',
                                    hintText: 'https://…')),
                            const SizedBox(height: 16),
                            TextField(
                                controller: fallback,
                                textDirection: TextDirection.ltr,
                                maxLines: 4,
                                autocorrect: false,
                                decoration: const InputDecoration(
                                    labelText: 'نشانی‌های جایگزین (اختیاری)',
                                    helperText:
                                        'هر نشانی در یک سطر؛ انتخاب سرویس جایگزین با تأیید شما انجام می‌شود.')),
                            for (final endpoint
                                in widget.initialConfig.apiFallbackUrls)
                              Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: OutlinedButton(
                                      onPressed: busy
                                          ? null
                                          : () => selectFallback(endpoint),
                                      child: Text(endpoint,
                                          textDirection: TextDirection.ltr))),
                            if (error != null)
                              Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  child: Text(error!,
                                      style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .error))),
                            const SizedBox(height: 20),
                            FilledButton(
                                onPressed: busy ? null : save,
                                child: Text(
                                    busy ? 'در حال ذخیره…' : 'ذخیره و ادامه')),
                          ])),
                ))),
      );
}
