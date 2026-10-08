import 'package:flutter/foundation.dart';
import 'package:http/browser_client.dart';

BrowserClient createClient() {
  const publicCa = String.fromEnvironment('LIFEGUIDE_DEBUG_CA_BASE64');
  if (publicCa.isNotEmpty && !kDebugMode) {
    throw StateError('Development CA is forbidden in release.');
  }
  return BrowserClient();
}
