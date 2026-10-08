import 'dart:async';
import 'package:flutter/material.dart';
import 'api.dart';
import 'notification_delivery.dart';

class NotificationInboxPage extends StatefulWidget {
  const NotificationInboxPage({super.key, required this.api, this.delivery});
  final IdentityApi api;
  final NotificationDeliveryPort? delivery;
  @override
  State<NotificationInboxPage> createState() => _NotificationInboxPageState();
}

class _NotificationInboxPageState extends State<NotificationInboxPage>
    with WidgetsBindingObserver {
  Timer? timer;
  List<Map<String, dynamic>> items = [];
  Object? error;
  DateTime? refreshedAt;
  bool loading = false;
  late final NotificationDeliveryPort? delivery;
  @override
  void initState() {
    super.initState();
    delivery = widget.delivery ??
        (widget.api is HttpIdentityApi
            ? PollingInAppNotificationDelivery(widget.api as HttpIdentityApi)
            : null);
    WidgetsBinding.instance.addObserver(this);
    reload();
    timer = Timer.periodic(const Duration(seconds: 30), (_) => reload());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    timer?.cancel();
    if (state == AppLifecycleState.resumed) {
      reload();
      timer = Timer.periodic(const Duration(seconds: 30), (_) => reload());
    }
  }

  Future<void> reload() async {
    if (loading) return;
    setState(() => loading = true);
    try {
      if (delivery == null) {
        throw const ApiException(503, 'notification_provider_unavailable');
      }
      final next = await delivery!.fetch();
      if (!mounted) return;
      setState(() {
        items = next;
        error = null;
        refreshedAt = DateTime.now();
      });
    } catch (failure) {
      if (mounted) setState(() => error = failure);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('یادآوری‌های لایف‌گاید'), actions: [
          IconButton(
              onPressed: loading ? null : reload,
              icon: const Icon(Icons.refresh))
        ]),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          const Text(
              'این یادآوری‌ها هنگام باز بودن برنامه تازه می‌شوند. اعلان پس‌زمینه فعال نیست.'),
          if (loading) const LinearProgressIndicator(),
          if (error != null)
            const Text(
                'تازه‌سازی انجام نشد؛ موارد زیر آخرین داده دریافت‌شده‌اند، زنده نیستند.'),
          if (refreshedAt != null)
            Text('آخرین دریافت: ${refreshedAt!.toLocal()}'),
          if (!loading && items.isEmpty) const Text('یادآوری دریافت نشده است.'),
          ...items.map((item) {
            final payload =
                item['payload'] is Map ? item['payload'] as Map : const {};
            return Card(
                child: ListTile(
                    title:
                        Text(payload['title']?.toString() ?? 'یادآوری برنامه'),
                    subtitle: Text(item['created_at']?.toString() ?? '')));
          }),
        ]),
      );
}
