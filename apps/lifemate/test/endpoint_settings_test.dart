import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate/endpoint_settings.dart';
import 'package:lifemate/runtime_config.dart';

void main() {
  testWidgets('fresh install explains setup and cannot save an empty endpoint',
      (tester) async {
    var saved = false;
    await tester.pumpWidget(MaterialApp(
        home: EndpointSettingsPage(
            initialConfig: RuntimeConfig(),
            onSaved: (_) async => saved = true)));
    expect(find.text('راه‌اندازی نسخه آزمایشی'), findsOneWidget);
    expect(find.textContaining('نشانی کامل API'), findsOneWidget);
    expect(find.textContaining('رمز عبور، کلید یا توکن وارد نکنید'),
        findsOneWidget);
    expect(find.textContaining('به معنی برقرارشدن اتصال نیست'), findsOneWidget);
    final save = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(save.onPressed, isNull);
    expect(saved, isFalse);
    expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        isEmpty);
  });
  testWidgets('an operator endpoint is normalized and saved only on submission',
      (tester) async {
    final saved = <RuntimeConfig>[];
    await tester.pumpWidget(MaterialApp(
        home: EndpointSettingsPage(
            initialConfig: RuntimeConfig(),
            onSaved: (config) async => saved.add(config))));
    await tester.enterText(
        find.byType(TextField).first, '  https://operator.example.test/api/  ');
    await tester.pump();
    expect(saved, isEmpty);
    await tester.ensureVisible(find.text('ذخیره و ادامه'));
    await tester.tap(find.text('ذخیره و ادامه'));
    await tester.pumpAndSettle();
    expect(saved.single.apiBaseUrl, 'https://operator.example.test/api');
    expect(saved.single.apiFallbackUrls, isEmpty);
  });
  testWidgets('editing a saved server warns about unsent changes',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: EndpointSettingsPage(
            initialConfig:
                RuntimeConfig(apiBaseUrl: 'https://operator.example.test/api'),
            onSaved: (_) async {})));
    expect(find.text('تنظیم اتصال'), findsOneWidget);
    expect(find.textContaining('تغییر سرویس شما را از حساب قبلی خارج می‌کند'),
        findsOneWidget);
    expect(find.textContaining('داده‌های ارسال‌نشده'), findsOneWidget);
  });
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
    await tester.pump();
    await tester.ensureVisible(find.text('ذخیره و ادامه'));
    await tester.tap(find.text('ذخیره و ادامه'));
    await tester.pumpAndSettle();
    expect(saved, isFalse);
    expect(find.textContaining('نشانی HTTPS معتبر'), findsOneWidget);
  });
}
