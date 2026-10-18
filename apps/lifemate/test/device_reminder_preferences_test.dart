import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate/device_reminder_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData({});
  });
  test('nickname persists in its user and API scope only', () async {
    final store = DeviceReminderPreferences();
    await store.write('https://one.invalid|synthetic-user-a', 'همراه من');
    expect(
        await DeviceReminderPreferences()
            .read('https://one.invalid|synthetic-user-a'),
        'همراه من');
    expect(
        await store.read('https://one.invalid|synthetic-user-b'), 'LifeGuide');
    expect(
        await store.read('https://two.invalid|synthetic-user-a'), 'LifeGuide');
  });
  test(
      'nickname validation retains joined emoji and rejects controls or excess',
      () async {
    final store = DeviceReminderPreferences();
    final joined = List.filled(40, '👩‍🔬').join();
    await store.write('synthetic-scope', joined);
    expect(await store.read('synthetic-scope'), joined);
    for (final invalid in ['$joined!', 'bad\nname']) {
      await expectLater(
          store.write('synthetic-scope', invalid), throwsArgumentError);
    }
    expect(await store.read('synthetic-scope'), joined);
  });
}
