import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/io_client.dart';

IOClient createClient() {
  const publicCa = String.fromEnvironment('LIFEGUIDE_DEBUG_CA_BASE64');
  if (publicCa.isNotEmpty && !kDebugMode) {
    throw StateError(
        'Custom development CA is forbidden outside debug builds.');
  }
  final context = SecurityContext(withTrustedRoots: true);
  if (publicCa.isNotEmpty) {
    final bytes = base64Decode(publicCa);
    if (bytes.length > 65536) {
      throw ArgumentError('Public development CA exceeds 64 KiB.');
    }
    if (utf8.decode(bytes).contains('PRIVATE KEY')) {
      throw ArgumentError('Only a public CA certificate may be supplied.');
    }
    context.setTrustedCertificatesBytes(bytes);
  }
  return IOClient(HttpClient(context: context)
    ..connectionTimeout = const Duration(seconds: 15));
}
