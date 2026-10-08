import 'package:flutter_test/flutter_test.dart';
import 'dart:convert';
import 'local_test_preferences.dart';
import 'package:lifemate/local_only_api.dart';
import 'package:lifemate/api.dart';
import 'package:lifemate/local_data_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

final class FailedWrites extends InMemorySharedPreferencesAsync {
  FailedWrites(super.data) : super.withData();
  @override
  Future<bool> setString(
      String key, String value, SharedPreferencesOptions options) async {
    await super.setString(key, value, options);
    throw StateError('Synthetic native cache publication then rename failure');
  }
}

final class NativeWriteDuringRead extends InMemorySharedPreferencesAsync {
  NativeWriteDuringRead(super.data, this.guard) : super.withData();
  final MockNativeLocalWriteGuard guard;

  @override
  Future<String?> getString(
      String key, SharedPreferencesOptions options) async {
    final raw = await super.getString(key, options);
    guard.beginWrite();
    return raw;
  }
}

class FailedNativeCommit extends InMemorySharedPreferencesStore {
  FailedNativeCommit(super.data) : super.withData();
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    await super.setValue(type, key, value);
    return false; // Android legacy commit can publish memory before disk fails.
  }
}

void main() {
  late LocalDataSession session;
  setUp(() {
    resetLocalPreferences();
    session = LocalDataSession();
  });

  LocalOnlyApi open() => LocalOnlyApi(
      displayName: 'آرام',
      category: 'girl_minor',
      store: LocalDataStore(
          category: 'girl_minor', displayName: 'آرام', session: session));

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

  test('today uses start time when a deadline is on another day', () async {
    final from = DateTime.utc(2026, 10, 8);
    await open().createPlanItem({
      'kind': 'assignment',
      'title': 'امروز',
      'startsAt': from.add(const Duration(hours: 10)).toIso8601String(),
      'dueAt': from.add(const Duration(days: 1)).toIso8601String(),
    });
    expect(
        await open()
            .getToday(from: from, to: from.add(const Duration(days: 1))),
        hasLength(1));
  });

  test('numeric dates are rejected instead of coerced into strings', () async {
    await expectLater(
        open().createPlanItem({
          'kind': 'task',
          'title': 'زمان نامعتبر',
          'dueAt': 20261008,
        }),
        throwsA(isA<ApiException>()));
  });

  test('valid JSON with corrupt fields cannot be read or overwritten',
      () async {
    await open().createPlanItem({'kind': 'task', 'title': 'اول'});
    final original = await open().store.read();
    for (final corrupt in <Map<String, dynamic>>[
      {'notes': <String, dynamic>{}},
      {'priority': 'wrong'},
      {'due_at': 20261008},
      {'starts_at': '2026-10-09T10:00:00Z', 'due_at': '2026-10-08T10:00:00Z'},
    ]) {
      final data = jsonDecode(jsonEncode(original)) as Map<String, dynamic>;
      (data['items'] as List).first.addAll(corrupt);
      final raw = jsonEncode(data);
      resetLocalPreferences({LocalDataStore.key: raw});
      await expectLater(
          open().listPlanItems(),
          throwsA(isA<ApiException>()
              .having((e) => e.code, 'code', 'local_data_corrupt')));
      await expectLater(open().updateProfile(displayName: 'دوم'),
          throwsA(isA<ApiException>()));
      expect(await SharedPreferencesAsync().getString(LocalDataStore.key), raw);
    }
  });

  test('corrupt data raises error and is never overwritten', () async {
    const bad = '{invalid';
    resetLocalPreferences({LocalDataStore.key: bad});
    await expectLater(
        open().listPlanItems(),
        throwsA(isA<ApiException>()
            .having((e) => e.code, 'code', 'local_data_corrupt')));
    await expectLater(open().createPlanItem({'kind': 'task', 'title': 'new'}),
        throwsA(isA<ApiException>()));
    expect(await SharedPreferencesAsync().getString(LocalDataStore.key), bad);
  });

  test('failed native write requires restart and blocks further operations',
      () async {
    final item = await open().createPlanItem({'kind': 'task', 'title': 'اول'});
    final raw = (await SharedPreferencesAsync().getString(LocalDataStore.key))!;
    SharedPreferencesAsyncPlatform.instance =
        FailedWrites({LocalDataStore.key: raw});
    await expectLater(
        open().updatePlanItem(item['id'] as String, {'title': 'دوم'}),
        throwsA(isA<ApiException>()
            .having((e) => e.code, 'code', 'local_storage_restart_required')));
    await expectLater(
        open().listPlanItems(),
        throwsA(isA<ApiException>()
            .having((e) => e.code, 'code', 'local_storage_restart_required')));
    final uncertain = jsonDecode(
        (await SharedPreferencesAsync().getString(LocalDataStore.key))!) as Map;
    expect((uncertain['items'] as List).first['title'], 'دوم');
    // Flutter engine recreation replaces Dart state, but retains native caches.
    session = LocalDataSession();
    await expectLater(
        open().listPlanItems(),
        throwsA(isA<ApiException>()
            .having((e) => e.code, 'code', 'local_storage_restart_required')));
    await expectLater(
        open().updatePlanItem(item['id'] as String, {'title': 'سوم'}),
        throwsA(isA<ApiException>()
            .having((e) => e.code, 'code', 'local_storage_restart_required')));
    resetLocalPreferences({
      LocalDataStore.key: raw
    }); // simulate native process restart + disk read
    await expectLater(open().listPlanItems(), throwsA(isA<ApiException>()));
    session = LocalDataSession();
    expect((await open().listPlanItems()).single['title'], 'اول');
  });

  test('reads never trust legacy memory published by a failed commit',
      () async {
    await open().createPlanItem({'kind': 'task', 'title': 'اول'});
    final original = await open().store.read();
    final raw = jsonEncode(original);
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData({LocalDataStore.key: raw});
    SharedPreferencesStorePlatform.instance =
        FailedNativeCommit({'flutter.${LocalDataStore.key}': raw});
    (original['items'] as List).first['title'] = 'ذخیره ناموفق';
    final prefs = await SharedPreferences.getInstance();
    expect(await prefs.setString(LocalDataStore.key, jsonEncode(original)),
        isFalse);
    expect((await open().listPlanItems()).single['title'], 'اول');
  });

  test('a native write beginning during a read blocks the returned snapshot',
      () async {
    await open().createPlanItem({'kind': 'task', 'title': 'ثبت‌شده'});
    final raw = (await SharedPreferencesAsync().getString(LocalDataStore.key))!;
    final guard = resetNativeLocalWriteGuard();
    SharedPreferencesAsyncPlatform.instance =
        NativeWriteDuringRead({LocalDataStore.key: raw}, guard);
    await expectLater(
        open().listPlanItems(),
        throwsA(isA<ApiException>()
            .having((e) => e.code, 'code', 'local_storage_restart_required')));
  });

  test('oversized mutation does not start a native write or replace saved data',
      () async {
    final item = await open().createPlanItem({'kind': 'task', 'title': 'اول'});
    final guard = resetNativeLocalWriteGuard();
    await expectLater(
        open().store.mutate((data) {
          data['items'] = List.generate(
              200,
              (index) => {
                    ...item,
                    'id': 'synthetic-capacity-item-$index',
                    'notes': 'x' * 6000,
                  });
        }),
        throwsA(isA<ApiException>()
            .having((e) => e.code, 'code', 'local_storage_failed')));
    expect(guard.blocked, isFalse);
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
