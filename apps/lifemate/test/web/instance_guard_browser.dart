// Browser-only focused tests of the actual Dart access paths. The test runner
// supplies controlled ownership; production ownership comes from Web Locks.
import 'dart:js_interop';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifemate/api.dart';
import 'package:lifemate/local_write_guard.dart';
import 'package:lifemate/offline_store.dart';
import 'package:lifemate/session_store.dart';

@JS('lifeguideInstanceOwned')
external set _owned(bool value);

@JS('localStorage')
external _Storage get _storage;
extension type _Storage(JSObject _) implements JSObject {
  external String? getItem(String key);
  external void setItem(String key, String value);
  external void removeItem(String key);
}

void main() {
  setUp(() {
    _owned = false;
    _storage.setItem(sessionStorageKey, 'synthetic-existing-session');
  });
  tearDown(() {
    _storage.removeItem(sessionStorageKey);
    _owned = false;
  });

  test('unowned web session cannot read, replace or erase owner credentials',
      () async {
    final store = createSessionStore();
    await expectLater(store.read(), throwsStateError);
    await expectLater(store.write('synthetic-replacement'), throwsStateError);
    await expectLater(store.clear(), throwsStateError);
    expect(_storage.getItem(sessionStorageKey), 'synthetic-existing-session');
    _owned = true;
    expect(await store.read(), 'synthetic-existing-session');
  });

  test(
      'unowned web API never sends a request; late response cannot be accepted',
      () async {
    var requests = 0;
    final api = HttpIdentityApi(
        baseUrl: 'https://family.example.test/api',
        client: MockClient((request) async {
          requests++;
          // Simulate document suspension while an owned request was in flight.
          _owned = false;
          return http.Response('{"synthetic":true}', 200);
        }));
    addTearDown(api.close);
    await expectLater(
        api.requestJson('GET', '/v1/profile', auth: false), throwsStateError);
    expect(requests, 0);
    _owned = true;
    await expectLater(
        api.requestJson('GET', '/v1/profile', auth: false), throwsStateError);
    expect(requests, 1);
  });

  test('unowned personal-cache read and write fail before storage access',
      () async {
    const guard = LocalWriteGuard();
    await expectLater(guard.getBlocked(), throwsStateError);
    await expectLater(guard.beginWrite(), throwsStateError);
    final store = OfflineStore.forNamespace('synthetic-owner-cache',
        session: OfflineSession());
    final blocked = isA<ApiException>().having(
        (error) => error.code, 'code', 'local_storage_restart_required');
    await expectLater(store.readList('planner'), throwsA(blocked));
    await expectLater(
        store.writeList('planner', [
          {'id': 'synthetic-item', 'title': 'synthetic'}
        ]),
        throwsA(blocked));
    expect(
        isOfflineFailure(
            const ApiException(500, 'local_storage_restart_required')),
        false);
  });
}
