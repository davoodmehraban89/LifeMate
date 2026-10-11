import 'package:flutter/material.dart';

import 'aparat_player_native.dart'
    if (dart.library.js_interop) 'aparat_player_web.dart' as platform;
import 'aparat_player_policy.dart';
import 'aparat_player_port.dart';

export 'aparat_player_policy.dart';
export 'aparat_player_port.dart';
export 'aparat_player_fullscreen.dart';

/// Click-to-load official Aparat frame. Frame readiness never records study
/// progress, completion or evidence that a video was watched.
class AparatPlayer extends StatefulWidget {
  const AparatPlayer({super.key, required this.videoHash, required this.title});

  final String videoHash;
  final String title;

  @override
  State<AparatPlayer> createState() => _AparatPlayerState();
}

class _AparatPlayerState extends State<AparatPlayer>
    with WidgetsBindingObserver {
  bool _loaded = false;
  String? _error;
  int _attempt = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(AparatPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoHash != widget.videoHash) {
      _reset();
    }
  }

  void _reset() {
    _attempt++;
    _loaded = false;
    _error = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_loaded &&
        (state == AppLifecycleState.paused ||
            state == AppLifecycleState.hidden ||
            state == AppLifecycleState.detached)) {
      setState(_reset);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uri = aparatEmbedUri(widget.videoHash);
    final port = AparatPlayerPortScope.maybeOf(context) ??
        platform.defaultAparatPlayerPort;
    final attempt = _attempt;
    return Directionality(
        textDirection: TextDirection.rtl,
        child: Card(
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: SingleChildScrollView(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(widget.title,
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  const Text(
                      'این ویدئو از سرویس آپارات بیرون از برنامه پخش می‌شود. با بارگذاری، '
                      'نشانی اینترنتی دستگاه و اطلاعات فنی اتصال برای آپارات '
                      'ارسال می‌شود؛ حریم خصوصی، کوکی‌ها و تبلیغات تابع این سرویس '
                      'است. اطلاعات حساب لایف‌گاید ارسال نمی‌شود.'),
                  const SizedBox(height: 12),
                  if (uri == null)
                    const Text('شناسهٔ ویدئو معتبر نیست؛ پخش‌کننده باز نشد.')
                  else if (_loaded) ...[
                    TextButton(
                        onPressed: () => setState(_reset),
                        child: const Text('بستن پخش‌کننده')),
                    AspectRatio(
                        aspectRatio: 16 / 9,
                        child: KeyedSubtree(
                            key: ValueKey('${widget.videoHash}:$attempt'),
                            child: port.buildFrame(context,
                                uri: uri,
                                title: widget.title,
                                onFrameReady: () {}, onError: (_) {
                              if (!mounted || attempt != _attempt) return;
                              setState(() {
                                _loaded = false;
                                _error = 'بارگذاری آپارات انجام نشد. اتصال '
                                    'اینترنت یا دسترسی به سرویس را بررسی کنید.';
                              });
                            }))),
                  ] else ...[
                    if (_error != null)
                      Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(_error!,
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.error))),
                    FilledButton.icon(
                        onPressed: () => setState(() {
                              if (!port.isSupported) {
                                _error = 'پخش در این نسخه پشتیبانی نمی‌شود؛ '
                                    'از نسخهٔ وب یا اندروید لایف‌گاید استفاده کنید.';
                                return;
                              }
                              _attempt++;
                              _error = null;
                              _loaded = true;
                            }),
                        icon: const Icon(Icons.play_circle_outline),
                        label: Text(_error == null
                            ? 'بارگذاری ویدئو از آپارات'
                            : 'تلاش دوباره')),
                  ],
                  const SizedBox(height: 8),
                  const Text(
                      'پخش خودکار فعال نیست؛ برای پخش از دکمهٔ داخل قاب استفاده '
                      'کنید. باز شدن قاب یا زمان ویدئو، اثبات مطالعه نیست.'),
                ])))));
  }
}
