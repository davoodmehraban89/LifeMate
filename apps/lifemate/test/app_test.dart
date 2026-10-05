import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate/main.dart';

void main() {
  testWidgets('starts in Persian RTL with identity actions', (tester) async {
    await tester.pumpWidget(const LifeMateApp());
    expect(find.text('LifeMate'), findsOneWidget);
    expect(find.text('ورود'), findsOneWidget);
    expect(find.text('رمز عبور را فراموش کرده‌ام'), findsOneWidget);
    final directionality = tester.widget<Directionality>(find.byType(Directionality).last);
    expect(directionality.textDirection, TextDirection.rtl);
  });

  testWidgets('opens recovery flow', (tester) async {
    await tester.pumpWidget(const LifeMateApp());
    await tester.tap(find.text('رمز عبور را فراموش کرده‌ام'));
    await tester.pumpAndSettle();
    expect(find.text('بازیابی رمز عبور'), findsOneWidget);
    expect(find.text('ارسال لینک بازیابی'), findsOneWidget);
  });
}
