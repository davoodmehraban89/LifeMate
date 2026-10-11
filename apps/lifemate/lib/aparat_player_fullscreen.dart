import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Owns one native custom-view route. Provider hide events must never pop an
/// unrelated app route, and a user Back/close must return the native view.
class AparatFullscreenPresenter {
  AparatFullscreenPresenter({required this.navigator});

  final NavigatorState navigator;
  Route<void>? _route;
  VoidCallback? _returnNativeView;
  bool _disposed = false;

  void show(Widget view, VoidCallback returnNativeView) {
    if (_disposed || !navigator.mounted) {
      returnNativeView();
      return;
    }
    _dismiss(notifyNative: true);
    late final Route<void> route;
    route = MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => Scaffold(
            backgroundColor: Colors.black,
            body: SafeArea(
                child: Stack(fit: StackFit.expand, children: [
              view,
              Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton.filled(
                      tooltip: 'خروج از تمام‌صفحه',
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        if (_route == route) _dismiss(notifyNative: true);
                      }))
            ]))));
    _route = route;
    _returnNativeView = returnNativeView;
    navigator.push(route).then((_) {
      // System Back already removed this route. A later provider hide cannot
      // remove the app page beneath it.
      if (_route != route) return;
      final callback = _returnNativeView;
      _route = null;
      _returnNativeView = null;
      callback?.call();
    });
  }

  /// The provider has already hidden the native custom view.
  void hide() => _dismiss(notifyNative: false);

  void _dismiss({required bool notifyNative}) {
    final route = _route;
    final callback = _returnNativeView;
    _route = null;
    _returnNativeView = null;
    if (notifyNative) callback?.call();
    if (route == null) return;
    void removeOwnedRoute() {
      if (navigator.mounted && route.isActive) navigator.removeRoute(route);
    }

    // View disposal can happen during a build/lifecycle update. Route removal
    // then waits for that frame, while ownership is revoked immediately.
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => removeOwnedRoute());
    } else {
      removeOwnedRoute();
    }
  }

  void dispose() {
    _disposed = true;
    _dismiss(notifyNative: true);
  }
}
