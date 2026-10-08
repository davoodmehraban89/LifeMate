import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate/endpoint_settings.dart';
import 'package:lifemate/runtime_config.dart';

void main() {
  testWidgets('fallback selection requires save and preserves the old primary',
      (tester) async {
    RuntimeConfig? saved;
    await tester.pumpWidget(MaterialApp(
        home: EndpointSettingsPage(
            initialConfig: RuntimeConfig(
                apiBaseUrl: 'https://primary.example.test/api',
                apiFallbackUrls: ['https://backup.example.test/api']),
            onSaved: (config) async => saved = config)));
    await tester.ensureVisible(find.byType(OutlinedButton));
    await tester.tap(find.byType(OutlinedButton));
    await tester.pump();
    expect(saved, isNull);
    expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'https://backup.example.test/api');
    await tester.ensureVisible(find.text('ذخیره و ادامه'));
    await tester.tap(find.text('ذخیره و ادامه'));
    await tester.pumpAndSettle();
    expect(saved!.apiBaseUrl, 'https://backup.example.test/api');
    expect(saved!.apiFallbackUrls, ['https://primary.example.test/api']);
  });
  testWidgets('invalid HTTPS address never reaches the saved callback',
      (tester) async {
    var saved = false;
    await tester.pumpWidget(MaterialApp(
        home: EndpointSettingsPage(
            initialConfig: RuntimeConfig(),
            onSaved: (_) async => saved = true)));
    await tester.enterText(
        find.byType(TextField).first, 'https://user:password@api.example.test');
    await tester.tap(find.text('ذخیره و ادامه'));
    await tester.pumpAndSettle();
    expect(saved, isFalse);
    expect(find.textContaining('نشانی HTTPS معتبر'), findsOneWidget);
  });
}
