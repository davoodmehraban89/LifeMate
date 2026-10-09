import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifemate/api.dart';
import 'package:lifemate/notification_delivery.dart';
import 'package:lifemate/session_store.dart';

class _MemorySession implements SessionStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String next) async {
    value = next;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}

void main() {
  test('polling uses the configured authenticated API, with no push SDK',
      () async {
    final requests = <http.Request>[];
    final token = 'header.${base64Url.encode(utf8.encode(jsonEncode({
          'sub': 'synthetic-child'
        })))}.signature';
    final client = MockClient((request) async {
      requests.add(request);
      if (request.url.path.endsWith('/login')) {
        return http.Response(
            jsonEncode({'accessToken': token, 'refreshToken': 'synthetic'}),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }
      return http.Response(
          jsonEncode({
            'notifications': [
              {
                'id': 'notification',
                'payload': {'title': 'ریاضی'}
              }
            ]
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    });
    final api = HttpIdentityApi(
        baseUrl: 'https://lan.test/api',
        client: client,
        sessionStore: _MemorySession());
    await api.login('synthetic@example.test', 'SyntheticPass!123');
    final port = PollingInAppNotificationDelivery(api);
    expect(port.supportsBackgroundPush, isFalse);
    expect((await port.fetch()).single['id'], 'notification');
    expect(requests.last.url.toString(),
        'https://lan.test/api/v1/notification-outbox');
    expect(requests.last.headers['authorization'], 'Bearer $token');
    api.close();
  });
}
