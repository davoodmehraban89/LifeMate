import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import 'aparat_player_policy.dart';
import 'aparat_player_port.dart';
import 'aparat_player_fullscreen.dart';

const AparatPlayerPort defaultAparatPlayerPort = _NativePlayerPort();

class _NativePlayerPort implements AparatPlayerPort {
  const _NativePlayerPort();

  @override
  bool get isSupported =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  @override
  Widget buildFrame(BuildContext context,
          {required Uri uri,
          required String title,
          required VoidCallback onFrameReady,
          required ValueChanged<String> onError}) =>
      _AparatWebView(uri: uri, onFrameReady: onFrameReady, onError: onError);
}

class _AparatWebView extends StatefulWidget {
  const _AparatWebView(
      {required this.uri, required this.onFrameReady, required this.onError});

  final Uri uri;
  final VoidCallback onFrameReady;
  final ValueChanged<String> onError;

  @override
  State<_AparatWebView> createState() => _AparatWebViewState();
}

class _AparatWebViewState extends State<_AparatWebView> {
  WebViewController? _controller;
  Timer? _timeout;
  bool _failed = false;
  AparatFullscreenPresenter? _fullscreen;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  void _fail(String code) {
    if (!mounted || _failed) return;
    _failed = true;
    _timeout?.cancel();
    widget.onError(code);
  }

  Future<void> _initialize() async {
    try {
      final hash = widget.uri.pathSegments[4];
      if (!isAllowedAparatNavigation(widget.uri.toString(), hash)) {
        _fail('invalid_frame_address');
        return;
      }
      final controller = WebViewController(
          onPermissionRequest: (request) => unawaited(request.deny()));
      _controller = controller;
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      if (controller.platform is AndroidWebViewController) {
        final android = controller.platform as AndroidWebViewController;
        await android.setMediaPlaybackRequiresUserGesture(true);
        await android.setGeolocationEnabled(false);
        await android.setMixedContentMode(MixedContentMode.neverAllow);
        final cookies = WebViewCookieManager();
        await (cookies.platform as AndroidWebViewCookieManager)
            .setAcceptThirdPartyCookies(android, false);
        await android.setCustomWidgetCallbacks(
            onShowCustomWidget: (view, returnNativeView) {
              if (!mounted) {
                returnNativeView();
                return;
              }
              _fullscreen ??=
                  AparatFullscreenPresenter(navigator: Navigator.of(context));
              _fullscreen!.show(view, returnNativeView);
            },
            onHideCustomWidget: () => _fullscreen?.hide());
      }
      await controller.setNavigationDelegate(NavigationDelegate(
          onNavigationRequest: (request) => !request.isMainFrame ||
                  isAllowedAparatNavigation(request.url, hash)
              ? NavigationDecision.navigate
              : NavigationDecision.prevent,
          onPageFinished: (url) {
            if (!mounted || _failed || !isAllowedAparatNavigation(url, hash)) {
              return;
            }
            _timeout?.cancel();
            widget.onFrameReady();
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame == true ||
                (error.isForMainFrame == null &&
                    error.url == widget.uri.toString())) {
              _fail('frame_load_failed');
            }
          },
          onHttpError: (error) {
            if (error.request?.uri == widget.uri) {
              _fail('frame_http_error');
            }
          },
          onSslAuthError: (error) => unawaited(error.cancel())));
      if (!mounted) return;
      setState(() {});
      _timeout =
          Timer(const Duration(seconds: 30), () => _fail('frame_load_timeout'));
      // This is the only controller-initiated remote load; no app headers,
      // JavaScript bridge, cached auth or service-issued media URL is added.
      await controller.loadRequest(widget.uri);
      if (!mounted) await controller.loadHtmlString('');
    } catch (_) {
      _fail('frame_initialization_failed');
    }
  }

  @override
  Widget build(BuildContext context) => _controller == null
      ? const Center(child: Text('در حال بارگذاری قاب آپارات…'))
      : WebViewWidget(controller: _controller!);

  @override
  void dispose() {
    _timeout?.cancel();
    _fullscreen?.dispose();
    // Blank the external document as the native platform view is removed.
    // Controller loads are not navigation-delegate redirects.
    unawaited(_controller?.loadHtmlString('').catchError((_) {}));
    super.dispose();
  }
}
