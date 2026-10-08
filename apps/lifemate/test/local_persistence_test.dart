import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate/local_only_api.dart';
import 'package:lifemate/api.dart';
import 'package:lifemate/local_data_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

class FailedWrites extends InMemorySharedPreferencesStore {
  FailedWrites(Map<String, Object> data) : super.withData(data);

  @override
  Future<bool> setValue(String valueType, String key, Object value) async =>
      false;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  LocalOnlyApi open() =>
      LocalOnlyApi(displayName: 'آرام', category: 'girl_minor');

  test('assignment survives recreation, update and safe archive', () async {
    final created = await open().createPlanItem({
      'kind': 'assignment',
      'title': 'تمرین ریاضی',
      'dueAt': DateTime.now().toUtc().toIso8601String(),
      'visibility': 'private',
    });
    final reopened = open();
    final records = await reopened.listPlanItems();
    expect(records, hasLength(1));
    expect(records.single['id'], created['id']);
    expect(records.single['title'], 'تمرین ریاضی');
    await reopened
        .updatePlanItem(created['id'].toString(), {'title': 'تمرین علوم'});
    expect((await open().listPlanItems()).single['title'], 'تمرین علوم');
    await open()
        .updatePlanItem(created['id'].toString(), {'status': 'cancelled'});
    expect(await open().listPlanItems(), isEmpty);
  });

  test('edited profile is restored by a new API', () async {
    await open()
        .updateProfile(displayName: 'سارا', themePreference: 'boy_blue');
    final restored = await open().getProfile();
    expect(restored['display_name'], 'سارا');
    expect(restored['theme_preference'], 'boy_blue');
  });

  test('concurrent writers retain every item with unique identifiers',
      () async {
    final records = await Future.wait(List.generate(
        20,
        (i) => open().createPlanItem({
              'kind': 'task',
              'title': 'کار $i',
            })));
    expect(records.map((item) => item['id']).toSet(), hasLength(20));
    expect(await open().listPlanItems(), hasLength(20));
  });

  test('invalid changes do not replace persisted records', () async {
    final item =
        await open().createPlanItem({'kind': 'assignment', 'title': 'علوم'});
    for (final change in <Map<String, dynamic>>[
      {'title': ' '},
      {'status': 'wrong'},
      {'visibility': 'family'},
      {'dueAt': 'not-a-date'},
      {'id': 'spoofed'},
    ]) {
      await expectLater(open().updatePlanItem(item['id'] as String, change),
          throwsA(isA<ApiException>()));
    }
    expect((await open().listPlanItems()).single['title'], 'علوم');
    await expectLater(open().updatePlanItem('missing', {'title': 'x'}),
        throwsA(isA<ApiException>()));
    await expectLater(
        open().updateProfile(displayName: ' '), throwsA(isA<ApiException>()));
  });

  test('date window includes due boundary and excludes upper boundary',
      () async {
    final from = DateTime.utc(2026, 10, 8);
    final to = from.add(const Duration(days: 1));
    await open().createPlanItem({
      'kind': 'assignment',
      'title': 'داخل',
      'dueAt': from.toIso8601String()
    });
    await open().createPlanItem(
        {'kind': 'task', 'title': 'بعد', 'dueAt': to.toIso8601String()});
    final result = await open().getToday(from: from, to: to);
    expect(result.map((item) => item['title']), ['داخل']);
    await open()
        .updatePlanItem(result.single['id'] as String, {'status': 'completed'});
    expect(await open().getToday(from: from, to: to), isEmpty);
  });

  test('corrupt data raises error and is never overwritten', () async {
    const bad = '{invalid';
    SharedPreferences.setMockInitialValues({LocalDataStore.key: bad});
    await expectLater(
        open().listPlanItems(),
        throwsA(isA<ApiException>()
            .having((e) => e.code, 'code', 'local_data_corrupt')));
    await expectLater(open().createPlanItem({'kind': 'task', 'title': 'new'}),
        throwsA(isA<ApiException>()));
    expect(
        (await SharedPreferences.getInstance()).getString(LocalDataStore.key),
        bad);
  });

  test('failed write reports error and preserves last durable version',
      () async {
    final item = await open().createPlanItem({'kind': 'task', 'title': 'اول'});
    final raw =
        (await SharedPreferences.getInstance()).getString(LocalDataStore.key)!;
    SharedPreferencesStorePlatform.instance =
        FailedWrites({'flutter.${LocalDataStore.key}': raw});
    await expectLater(
        open().updatePlanItem(item['id'] as String, {'title': 'دوم'}),
        throwsA(isA<ApiException>()
            .having((e) => e.code, 'code', 'local_storage_failed')));
    expect((await open().listPlanItems()).single['title'], 'اول');
  });

  test('unimplemented server features cannot fabricate success', () async {
    expect(open().accessToken, isNull);
    expect(
        () => open().createAiSession('study'),
        throwsA(isA<ApiException>()
            .having((e) => e.code, 'code', 'local_feature_unavailable')));
    expect(() => open().createFamily('خانواده'), throwsA(isA<ApiException>()));
  });
}
