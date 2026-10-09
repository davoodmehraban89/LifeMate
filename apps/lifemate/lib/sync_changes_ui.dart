import 'package:flutter/material.dart';

import 'api.dart';
import 'offline_store.dart';
import 'phase3_ui.dart' show uiErrorText;
import 'plan_sync.dart';
import 'study_coordinator.dart';

class SyncChangesPage extends StatefulWidget {
  const SyncChangesPage({super.key, required this.api});
  final IdentityApi api;

  @override
  State<SyncChangesPage> createState() => _SyncChangesPageState();
}

class _SyncChangesPageState extends State<SyncChangesPage> {
  late final OfflineStore store;
  List<Map<String, dynamic>> queue = [], journal = [];
  bool loading = true, busy = false, dialogOpen = false, storeReady = false;
  Object? error;
  final hiddenEntities = <String>{};

  @override
  void initState() {
    super.initState();
    try {
      store = OfflineStore.forApi(widget.api);
      storeReady = true;
      _load();
    } catch (failure) {
      error = failure;
      loading = false;
    }
  }

  Future<void> _load() async {
    try {
      final pending = await store.readQueue();
      final discarded = await store.readDiscardedChanges();
      if (!mounted) return;
      setState(() {
        queue = pending;
        journal = discarded;
        loading = false;
      });
    } catch (failure) {
      if (mounted) {
        setState(() {
          error = failure;
          loading = false;
        });
      }
    }
  }

  Future<void> _retry() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      Object? failure;
      try {
        await PlanSync(widget.api, store: store).flush();
      } catch (caught) {
        failure = caught;
      }
      final api = widget.api;
      if (api is HttpIdentityApi) {
        try {
          await StudySync(api, store: store).flush();
        } catch (caught) {
          failure ??= caught;
        }
      }
      if (failure != null) throw failure;
    } catch (failure) {
      if (mounted) setState(() => error = failure);
    } finally {
      await _load();
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _resolve(Map<String, dynamic> mutation) async {
    if (busy) return;
    final api = widget.api;
    if (api is! HttpIdentityApi) {
      setState(
          () => error = const ApiException(503, 'configured_api_required'));
      return;
    }
    final id = mutation['entityId'] as String;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      Map<String, dynamic>? serverItem;
      try {
        serverItem = await api.requestJson(
            'GET', '/v1/plan-items/${Uri.encodeComponent(id)}');
      } on ApiException catch (failure) {
        final isUnsent =
            queue.any((m) => m['entityId'] == id && m['operation'] == 'create');
        if (failure.statusCode != 404 || !isUnsent) rethrow;
      }
      if (serverItem != null &&
          (serverItem['id'] != id ||
              int.tryParse(serverItem['version'].toString()) == null)) {
        throw const ApiException(502, 'invalid_api_response');
      }
      if (!mounted) return;
      final payload = mutation['payload'] as Map;
      final local = _details(payload);
      setState(() => dialogOpen = true);
      final accepted = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
                title: const Text('بررسی تعارض'),
                content: SingleChildScrollView(
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text('تغییر محلی: $local'),
                      const SizedBox(height: 12),
                      Text(serverItem == null
                          ? 'این کار هنوز در سرور موجود نیست.'
                          : 'نسخه سرور ${serverItem['version']}: ${serverItem['title'] ?? ''}'),
                      if (serverItem != null)
                        Text(_details(serverItem, server: true)),
                      const SizedBox(height: 12),
                      const Text(
                          'با این انتخاب، تمام تغییرهای معلق همین کار از صف خارج می‌شوند. متن تغییرها در پیش‌نویس‌های نگه‌داری‌شده می‌ماند تا بعداً دستی ویرایش کنی.'),
                    ])),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: const Text('نگه‌داشتن تغییر محلی')),
                  FilledButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      child: Text(serverItem == null
                          ? 'خارج‌کردن از صف و نگه‌داشتن پیش‌نویس'
                          : 'استفاده از نسخه سرور')),
                ],
              ));
      if (mounted) setState(() => dialogOpen = false);
      if (accepted == true) {
        await store.discardEntityChanges(id, serverItem: serverItem);
      }
    } catch (failure) {
      if (mounted) {
        setState(() {
          error = failure;
          if (failure is ApiException &&
              (failure.statusCode == 403 || failure.statusCode == 401)) {
            hiddenEntities.add(id);
          }
        });
      }
    } finally {
      await _load();
      if (mounted) {
        setState(() {
          busy = false;
          dialogOpen = false;
        });
      }
    }
  }

  String _status(dynamic value) => switch (value) {
        'conflict' => 'تعارض؛ نیازمند انتخاب',
        'rejected' => 'سرور نپذیرفت',
        _ => 'در انتظار تأیید سرور',
      };

  String _details(Map row, {bool server = false}) {
    const labels = {
      'title': 'عنوان',
      'status': 'وضعیت',
      'visibility': 'اشتراک',
      'notes': 'یادداشت',
      'dueAt': 'مهلت',
      'startsAt': 'شروع',
      'endsAt': 'پایان',
      'plannedDurationSeconds': 'زمان برنامه‌ریزی‌شده (ثانیه)',
    };
    const columns = {
      'dueAt': 'due_at',
      'startsAt': 'starts_at',
      'endsAt': 'ends_at',
      'plannedDurationSeconds': 'planned_duration_seconds'
    };
    const values = {
      'planned': 'برنامه‌ریزی‌شده',
      'in_progress': 'در حال انجام',
      'completed': 'انجام‌شده',
      'cancelled': 'بایگانی‌شده',
      'private': 'خصوصی',
      'family': 'خانواده',
      'parent_guardians': 'سرپرستان',
      'selected_members': 'اعضای انتخابی'
    };
    return labels.entries
        .where((entry) => row
            .containsKey(server ? columns[entry.key] ?? entry.key : entry.key))
        .map((entry) {
      final value = row[server ? columns[entry.key] ?? entry.key : entry.key];
      return '${entry.value}: ${value == null ? 'خالی' : values[value] ?? value}';
    }).join('\n');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('تغییرهای معلق')),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(padding: const EdgeInsets.all(16), children: [
                if (busy && !dialogOpen) const LinearProgressIndicator(),
                if (error != null)
                  Text(uiErrorText(error!),
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                FilledButton.icon(
                    onPressed: busy || !storeReady ? null : _retry,
                    icon: const Icon(Icons.sync),
                    label: const Text('تلاش دوباره برای همگام‌سازی')),
                if (queue.isEmpty)
                  const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('تغییر معلقی باقی نمانده است.')),
                for (final mutation in queue)
                  ListTile(
                    title: Text(hiddenEntities.contains(mutation['entityId'])
                        ? 'تغییر بدون دسترسی'
                        : (mutation['payload'] as Map)['title']?.toString() ??
                            (mutation['entityType'] == 'study_session'
                                ? 'ثبت مطالعه'
                                : 'تغییر کار')),
                    subtitle: Text(_status(mutation['queueStatus'])),
                    trailing: mutation['entityType'] == 'plan_item' &&
                            ['conflict', 'rejected']
                                .contains(mutation['queueStatus']) &&
                            !hiddenEntities.contains(mutation['entityId'])
                        ? TextButton(
                            onPressed: busy ? null : () => _resolve(mutation),
                            child: const Text('بررسی و انتخاب'))
                        : null,
                  ),
                if (journal.isNotEmpty) ...[
                  const Divider(),
                  Text('پیش‌نویس‌های نگه‌داری‌شده',
                      style: Theme.of(context).textTheme.titleMedium),
                  const Text(
                      'این تغییرها ارسال نمی‌شوند. عنوان را برای بازیابی دستی در ویرایش کار نگه داشته‌ایم.'),
                  for (final entry in journal)
                    ListTile(
                        title: Text(
                            (entry['payload'] as Map)['title']?.toString() ??
                                entry['recoveryTitle']?.toString() ??
                                'تغییر وضعیت یا جزئیات'),
                        subtitle: const Text('پیش‌نویس محلی؛ تأیید سرور نیست')),
                ],
              ]),
      );
}
