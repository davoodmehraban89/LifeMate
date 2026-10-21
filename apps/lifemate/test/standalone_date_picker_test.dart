import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate/standalone/personal_date_picker.dart';

void main() {
  Future<void> choose(WidgetTester tester, String field, String text,
      {double delta = -180}) async {
    final input = find.byKey(ValueKey('personal-date-$field'));
    await tester.ensureVisible(input);
    await tester.tap(input);
    await tester.pumpAndSettle();
    final option = find.text(text);
    if (option.evaluate().isEmpty) {
      await tester.scrollUntilVisible(option, delta,
          scrollable: find.byType(Scrollable).last, maxScrolls: 100);
    }
    await tester.ensureVisible(option.last);
    await tester.tap(option.last);
    await tester.pumpAndSettle();
  }

  Future<void> launch(
      WidgetTester tester, DateTime initial, ValueChanged<DateTime?> result,
      {DateTime? first, DateTime? last}) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('fa'),
      supportedLocales: const [Locale('fa')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Builder(
          builder: (context) => Scaffold(
              body: FilledButton(
                  onPressed: () async => result(await showPersonalDatePicker(
                      context: context,
                      initialDate: initial,
                      firstDate: first ?? DateTime(2020),
                      lastDate: last ?? DateTime(2100))),
                  child: const Text('باز کردن')))),
    ));
    await tester.tap(find.text('باز کردن'));
    await tester.pumpAndSettle();
  }

  Future<void> confirm(WidgetTester tester) async {
    await tester.tap(find.text('انتخاب تاریخ'));
    await tester.pumpAndSettle();
  }

  testWidgets('leap Esfand day30 becomes29 when year changes to nonleap',
      (tester) async {
    DateTime? selected;
    await launch(tester, DateTime(2025, 3, 20), (value) => selected = value);
    expect(find.text('۳۰ اسفند ۱۴۰۳ شمسی'), findsOneWidget);
    await choose(tester, 'year', '۱۴۰۴');
    expect(find.text('۲۹ اسفند ۱۴۰۴ شمسی'), findsOneWidget);
    await confirm(tester);
    expect(selected, DateTime(2026, 3, 20));
    expect(selected!.isUtc, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('day31 changes to30 in a thirty-day Persian month',
      (tester) async {
    DateTime? selected;
    await launch(tester, DateTime(2026, 9, 22), (value) => selected = value);
    expect(find.text('۳۱ شهریور ۱۴۰۵ شمسی'), findsOneWidget);
    await choose(tester, 'month', 'مهر', delta: 180);
    expect(find.text('۳۰ مهر ۱۴۰۵ شمسی'), findsOneWidget);
    await confirm(tester);
    expect(selected, DateTime(2026, 10, 22));
    expect(tester.takeException(), isNull);
  });

  testWidgets('partial first and last month bounds remain inclusive',
      (tester) async {
    DateTime? selected;
    await launch(tester, DateTime(2025, 1, 1), (value) => selected = value,
        first: DateTime(2025, 1, 1), last: DateTime(2025, 1, 2));
    expect(find.text('۱۲ دی ۱۴۰۳ شمسی'), findsOneWidget);
    await choose(tester, 'day', '۱۳', delta: 180);
    await confirm(tester);
    expect(selected, DateTime(2025, 1, 2));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'existing2020to2100 bounds clamp initial dates without leaving range',
      (tester) async {
    for (final pair in [
      (DateTime(2019, 12, 31), DateTime(2020)),
      (DateTime(2100, 1, 2), DateTime(2100)),
    ]) {
      DateTime? selected;
      await launch(tester, pair.$1, (value) => selected = value);
      await confirm(tester);
      expect(selected, pair.$2);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }
  });
}
