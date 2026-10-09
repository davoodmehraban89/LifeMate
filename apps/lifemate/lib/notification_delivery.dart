import 'api.dart';

/// Delivery is replaceable; correctness never depends on FCM or an external SDK.
abstract interface class NotificationDeliveryPort {
  bool get supportsBackgroundPush;
  Future<List<Map<String, dynamic>>> fetch();
}

class PollingInAppNotificationDelivery implements NotificationDeliveryPort {
  PollingInAppNotificationDelivery(this.api);
  final HttpIdentityApi api;
  @override
  bool get supportsBackgroundPush => false;
  @override
  Future<List<Map<String, dynamic>>> fetch() async {
    final response = await api.requestJson('GET', '/v1/notification-outbox');
    final entries = response['notifications'];
    if (entries is! List) {
      throw const ApiException(502, 'invalid_notification_response');
    }
    return entries
        .map((entry) => Map<String, dynamic>.from(entry as Map))
        .toList();
  }
}
