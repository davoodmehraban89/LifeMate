import 'package:flutter/material.dart';

import 'api.dart';
import 'offline_store.dart';
import 'phase3_ui.dart' show uiErrorText;
import 'plan_sync.dart';
import 'study_coordinator.dart';
import 'learning_sync.dart';
import 'learning_feedback_ui.dart';
import 'learning_quiz_ui.dart';

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
        try {
          await LearningSync(api, store: store).flush();
        } catch (caught) {
          failure ??= caught;
        }
        try {
          await LearningFeedbackSync(api, store: store).flush();
        } catch (caught) {
          failure ??= caught;
        }
        try {
          await LearningQuizSync(api, store: store).flush();
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
      if (['learning_feedback', 'learning_attempt']
          .contains(mutation['entityType'])) {
        throw const ApiException(409, 'feedback_retry_or_edit_draft');
      }
      if (mutation['entityType'] == 'learning_progress') {
        if (!mounted) return;
        setState(() => dialogOpen = true);
        final accepted = await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
                    title: const Text('تعارض پیشرفت درس'),
                    content: Text(
                        'تغییر محلی: ${_details(mutation['payload'] as Map)}\n'
                        'با استفاده از سرور، تغییر محلی در سابقه بازیابی نگه داشته می‌شود و پیشرفت تازه سرور نمایش داده خواهد شد.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(dialogContext, false),
                          child: const Text('نگه‌داشتن تغییر محلی')),
                      FilledButton(
                          onPressed: () => Navigator.pop(dialogContext, true),
                          child: const Text('استفاده از نسخه سرور')),
                    ]));
        if (accepted == true && mounted) {
          await LearningSync(api, store: store).resolveUsingServer(id);
        }
        return;
      }
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

  String _entityTitle(Map<String, dynamic> mutation) =>
      switch (mutation['entityType']) {
        'study_session' => 'ثبت مطالعه',
        'learning_progress' => 'پیشرفت درس',
        'learning_attempt' => 'پاسخ آزمون',
        'learning_feedback' => 'بازخورد آموزشی',
        'learning_goal' => 'هدف یادگیری',
        'family_operation' => 'تغییر خانواده',
        'content_review' => 'بررسی بازخورد',
        'content_brief' => 'درخواست برنامه توسعه محتوا',
        'school_lifecycle_contexts' => 'فضای تحصیلی',
        'school_lifecycle_years' => 'سال تحصیلی',
        'school_lifecycle_terms' => 'نیم‌سال تحصیلی',
        _ => 'تغییر کار',
      };

  String? _manualRetryPage(Map<String, dynamic> mutation) =>
      switch (mutation['entityType']) {
        'learning_goal' => 'اهداف یادگیری',
        'family_operation' => 'مدیریت خانواده',
        'content_review' || 'content_brief' => 'بررسی محتوای آموزشی',
        'school_lifecycle_contexts' ||
        'school_lifecycle_years' ||
        'school_lifecycle_terms' =>
          'مدیریت فضای تحصیلی',
        _ => null,
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
                if (queue.any((row) => _manualRetryPage(row) != null))
                  const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                          'تغییرهای خانواده، اهداف و مدیریت محتوا یا تحصیل از صفحه مربوط بررسی و دوباره ارسال می‌شوند. این دکمه آن‌ها را ارسال نمی‌کند.')),
                if (queue.isEmpty)
                  const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('تغییر معلقی باقی نمانده است.')),
                for (final mutation in queue)
                  ListTile(
                    title: Text(hiddenEntities.contains(mutation['entityId'])
                        ? 'تغییر بدون دسترسی'
                        : (mutation['payload'] as Map)['title']?.toString() ??
                            _entityTitle(mutation)),
                    subtitle: Text([
                      _status(mutation['queueStatus']),
                      if (_manualRetryPage(mutation) case final page?)
                        'بررسی و ارسال از «$page»',
                    ].join('\n')),
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
                      'این تغییرها ارسال نمی‌شوند. اطلاعات آن‌ها برای بازیابی دستی در صفحه مربوط نگه داشته شده است.'),
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
