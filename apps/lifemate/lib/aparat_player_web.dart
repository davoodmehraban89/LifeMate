import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

import 'aparat_player_port.dart';

const AparatPlayerPort defaultAparatPlayerPort = _WebPlayerPort();

class _WebPlayerPort implements AparatPlayerPort {
  const _WebPlayerPort();

  @override
  bool get isSupported => true;

  @override
  Widget buildFrame(BuildContext context,
          {required Uri uri,
          required String title,
          required VoidCallback onFrameReady,
          required ValueChanged<String> onError}) =>
      _AparatFrame(
          uri: uri, title: title, onFrameReady: onFrameReady, onError: onError);
}

class _AparatFrame extends StatefulWidget {
  const _AparatFrame(
      {required this.uri,
      required this.title,
      required this.onFrameReady,
      required this.onError});

  final Uri uri;
  final String title;
  final VoidCallback onFrameReady;
  final ValueChanged<String> onError;

  @override
  State<_AparatFrame> createState() => _AparatFrameState();
}

class _AparatFrameState extends State<_AparatFrame> {
  web.HTMLIFrameElement? _frame;
  Timer? _timeout;

  @override
  Widget build(BuildContext context) => HtmlElementView.fromTagName(
      tagName: 'iframe',
      onElementCreated: (element) {
        final frame = element as web.HTMLIFrameElement;
        _frame = frame;
        // Set all restrictions before attachment and before assigning src.
        frame.title = widget.title;
        frame.referrerPolicy = 'no-referrer';
        frame.setAttribute('sandbox', 'allow-scripts allow-same-origin');
        frame.setAttribute('allow',
            "fullscreen; autoplay 'none'; camera 'none'; microphone 'none'; geolocation 'none'; payment 'none'");
        frame.allowFullscreen = true;
        frame.style
          ..width = '100%'
          ..height = '100%'
          ..border = '0';
        frame.onload = ((web.Event event) {
          _timeout?.cancel();
          if (mounted) widget.onFrameReady();
        }).toJS;
        frame.onerror = ((web.Event event) {
          _timeout?.cancel();
          if (mounted) widget.onError('frame_load_failed');
        }).toJS;
        _timeout = Timer(const Duration(seconds: 30), () {
          if (mounted) widget.onError('frame_load_timeout');
        });
        frame.src = widget.uri.toString();
      });

  @override
  void dispose() {
    _timeout?.cancel();
    final frame = _frame;
    if (frame != null) {
      frame.onload = null;
      frame.onerror = null;
      frame.remove();
    }
    super.dispose();
  }
}
