import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate/role_entry_main.dart';

void main() {
  testWidgets('role-first test build starts without login form', (tester) async {
    await tester.pumpWidget(const LifeGuideRoleTestApp());
    expect(find.text('Life Guide'), findsOneWidget);
    expect(find.text('چه کسی وارد می‌شود؟'), findsOneWidget);
    expect(find.text('فرزند / دانش‌آموز'), findsOneWidget);
    expect(find.text('مادر'), findsOneWidget);
    expect(find.text('پدر'), findsOneWidget);
    expect(find.text('ورود'), findsNothing);
  });
}
