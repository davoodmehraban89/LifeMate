import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate/api.dart';
import 'package:lifemate/phase4_ui.dart';

class StubApi extends HttpIdentityApi {
  @override
  Future<List<Map<String, dynamic>>> listLearningGoals() async => [];
}

void main() {
  testWidgets('phase4 hub exposes advisory privacy and non diagnosis copy',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Phase4Hub(api: StubApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('یادگیری و حال خوب'), findsOneWidget);
    expect(
      find.textContaining('تصمیم و اجرای تغییرها با خودت است'),
      findsOneWidget,
    );
    expect(find.textContaining('حریم خصوصی'), findsOneWidget);
    expect(find.text('همراه حال خوب'), findsOneWidget);
  });
}
