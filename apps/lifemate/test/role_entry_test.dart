import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate/role_entry_main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('first run offers exactly girl child, boy child, and adult', (tester) async {
    await tester.pumpWidget(const LifeGuideRoleTestApp());
    await tester.pumpAndSettle();

    expect(find.text('Life Guide'), findsOneWidget);
    expect(find.text('چه کسی وارد می‌شود؟'), findsOneWidget);
    expect(find.text('فرزند دختر'), findsOneWidget);
    expect(find.text('فرزند پسر'), findsOneWidget);
    expect(find.text('بزرگسال'), findsOneWidget);
    expect(find.text('فرزند / دانش‌آموز'), findsNothing);
    expect(find.text('مادر'), findsNothing);
    expect(find.text('پدر'), findsNothing);
    expect(find.text('ورود'), findsNothing);
  });

  test('local profile store persists category and edited display name', () async {
    final store = LocalTestProfileStore();
    await store.save(const LocalTestProfile(
      category: 'girl_minor',
      displayName: 'آرام',
    ));

    final restored = await LocalTestProfileStore().load();
    expect(restored?.category, 'girl_minor');
    expect(restored?.displayName, 'آرام');
  });

  test('local profile rejects an empty display name', () async {
    final store = LocalTestProfileStore();
    expect(
      () => store.save(const LocalTestProfile(
        category: 'girl_minor',
        displayName: '   ',
      )),
      throwsArgumentError,
    );
  });
}
