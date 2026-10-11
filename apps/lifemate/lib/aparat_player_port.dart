import 'package:flutter/widgets.dart';

/// A platform boundary: only an already validated provider URI is passed here.
/// Fixtures can replace the platform view without contacting a video service.
abstract interface class AparatPlayerPort {
  bool get isSupported;

  Widget buildFrame(BuildContext context,
      {required Uri uri,
      required String title,
      required VoidCallback onFrameReady,
      required ValueChanged<String> onError});
}

class AparatPlayerPortScope extends InheritedWidget {
  const AparatPlayerPortScope(
      {super.key, required this.port, required super.child});

  final AparatPlayerPort port;

  static AparatPlayerPort? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AparatPlayerPortScope>()?.port;

  @override
  bool updateShouldNotify(AparatPlayerPortScope oldWidget) =>
      port != oldWidget.port;
}
