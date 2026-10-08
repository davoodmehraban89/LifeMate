// ignore_for_file: prefer_interpolation_to_compose_strings, curly_braces_in_flow_control_structures, use_build_context_synchronously

import 'dart:math';
import 'package:flutter/material.dart';
import 'api.dart';
import 'offline_store.dart';

String faKind(String kind) {
  switch (kind) {
    case 'assignment':
      return 'تکلیف';
    case 'exam':
      return 'امتحان';
    case 'study_session':
      return 'مطالعه';
    case 'event':
      return 'رویداد';
    case 'routine':
      return 'روتین';
    case 'goal':
      return 'هدف';
    default:
      return 'کار';
  }
}

DateTime? parseDate(dynamic value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString())?.toLocal();
}

String shortDate(dynamic value) {
  final d = parseDate(value);
  if (d == null) return '';
  final minute = d.minute.toString().padLeft(2, '0');
  return d.month.toString() +
      '/' +
      d.day.toString() +
      ' · ' +
      d.hour.toString() +
      ':' +
      minute;
}

class Phase3HomeContent extends StatelessWidget {
  const Phase3HomeContent({
    super.key,
    required this.api,
    required this.page,
    required this.adultShell,
    this.localOnly = false,
  });
  final IdentityApi api;
  final String page;
  final bool adultShell;
  final bool localOnly;

  @override
  Widget build(BuildContext context) {
    if (page == 'امروز') return TodayPage(api: api, localOnly: localOnly);
    if (page == 'برنامه‌ریز' ||
        page == 'برنامه هفتگی' ||
        page == 'تقویم' ||
        page == 'تکالیف و کارها') {
      return PlannerPage(api: api, localOnly: localOnly);
    }
    if (localOnly) return const LocalFeaturesNotice();
    if (page == 'خانواده') return ParentFamilyDashboard(api: api);
    if (page == 'امتحان‌ها و نمرات') return SchoolPage(api: api);
    if (page == 'تمرکز') {
      return const CoreNotice(
        title: 'تمرکز',
        subtitle:
            'جلسه مطالعه در برنامه‌ریز فعال است؛ تایمر پیشرفته در فاز بعد اضافه می‌شود.',
      );
    }
    if (page == 'همراه هوشمند' || page == 'راهنما') {
      return const CoreNotice(
        title: 'راهنمای هوشمند',
        subtitle:
            'هسته برنامه‌ریزی این فاز مستقل از AI است و راهنمای هوشمند در فاز ۴ فعال می‌شود.',
      );
    }
    return SchoolPage(api: api);
  }
}

class CoreNotice extends StatelessWidget {
  const CoreNotice({super.key, required this.title, required this.subtitle});
  final String title;
  final String subtitle;
  @override
  Widget build(BuildContext context) => Center(
        child: Card(
          margin: const EdgeInsets.all(20),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(title, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(subtitle, textAlign: TextAlign.center),
            ]),
          ),
        ),
      );
}

String localDataErrorText(Object error) {
  if (error is ApiException) {
    switch (error.code) {
      case 'local_storage_restart_required':
        return 'وضعیت ذخیره نامشخص است. برنامه را از تنظیمات دستگاه «توقف اجباری» کن و دوباره باز کن.';
      case 'local_storage_failed':
        return 'ذخیره روی دستگاه انجام نشد. دوباره تلاش کن.';
      case 'local_data_corrupt':
        return 'اطلاعات ذخیره‌شده روی دستگاه خراب است؛ داده قبلی حفظ شده است.';
      case 'local_invalid_item':
        return 'عنوان، نوع یا زمان برنامه معتبر نیست.';
      case 'local_invalid_profile':
        return 'نام و تم پروفایل را بررسی کن.';
      case 'local_item_not_found':
        return 'این مورد در اطلاعات دستگاه پیدا نشد.';
      case 'local_feature_unavailable':
        return 'این قابلیت در حالت محلی فعال نیست.';
    }
  }
  return 'دسترسی به اطلاعات روی دستگاه انجام نشد. دوباره تلاش کن.';
}

String _planErrorText(Object error, bool localOnly) {
  if (localOnly || (error is ApiException && error.code.startsWith('local_'))) {
    return localDataErrorText(error);
  }
  return 'عملیات انجام نشد. دوباره تلاش کن.';
}

class LocalDataNotice extends StatelessWidget {
  const LocalDataNotice({super.key});

  @override
  Widget build(BuildContext context) => const Card(
        child: ListTile(
          leading: Icon(Icons.phone_android_outlined),
          title: Text('حالت محلی · فقط روی این دستگاه'),
          subtitle: Text(
            'همگام‌سازی و پشتیبان سرور ندارد؛ حذف برنامه ممکن است اطلاعات را پاک کند.',
          ),
        ),
      );
}

class LocalFeaturesNotice extends StatelessWidget {
  const LocalFeaturesNotice({super.key});

  @override
  Widget build(BuildContext context) => const Card(
        child: ListTile(
          leading: Icon(Icons.info_outline),
          title: Text('قابلیت‌های غیرفعال در حالت محلی'),
          subtitle: Text(
            'خانواده، آموزش ساختاریافته، ثبت حال و یادگیری، و همراه هوشمند فعال نیستند.',
          ),
        ),
      );
}

class _OperationErrorCard extends StatelessWidget {
  const _OperationErrorCard({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(message,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 8),
              TextButton(
                onPressed: onRetry,
                child: const Text('تلاش دوباره'),
              ),
            ],
          ),
        ),
      );
}

class TodayPage extends StatefulWidget {
  const TodayPage({super.key, required this.api, this.localOnly = false});
  final IdentityApi api;
  final bool localOnly;
  @override
  State<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends State<TodayPage> {
  late Future<LoadResult> future;
  final busyItems = <String>{};
  String? operationError;
  VoidCallback? retryOperation;

  @override
  void initState() {
    super.initState();
    future = load();
  }

  Future<LoadResult> load() async {
    final now = DateTime.now();
    final from = DateTime(now.year, now.month, now.day);
    final to = from.add(const Duration(days: 1));
    try {
      final items = await widget.api.getToday(from: from, to: to);
      if (widget.localOnly) return LoadResult(items, false);
      final reminders = await widget.api.claimDueReminders();
      await OfflineStore.instance.cacheToday(items);
      return LoadResult(items, false, reminders: reminders);
    } catch (error) {
      if (widget.localOnly) return LoadResult(const [], false, error: error);
      return LoadResult(await OfflineStore.instance.readToday(), true);
    }
  }

  Future<void> refresh() async {
    if (!mounted) return;
    setState(() {
      future = load();
    });
    await future;
  }

  Future<void> complete(Map<String, dynamic> item) async {
    final id = item['id'].toString();
    if (busyItems.contains(id)) return;
    setState(() {
      busyItems.add(id);
      operationError = null;
      retryOperation = null;
    });
    try {
      await widget.api.updatePlanItem(id, {'status': 'completed'});
      await refresh();
    } catch (error) {
      if (widget.localOnly) {
        if (mounted) {
          setState(() {
            operationError = localDataErrorText(error);
            retryOperation = () => complete(item);
          });
        }
      } else {
        try {
          await OfflineStore.instance.enqueue({
            'id':
                '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(99999)}',
            'entityType': 'plan_item',
            'entityId': item['id'],
            'operation': 'complete',
            'clientUpdatedAt': DateTime.now().toUtc().toIso8601String(),
            'payload': {'status': 'completed'},
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('آفلاین هستی؛ تغییر برای همگام‌سازی ذخیره شد.'),
            ));
          }
        } catch (queueError) {
          if (mounted) {
            setState(() {
              operationError = _planErrorText(queueError, false);
              retryOperation = () => complete(item);
            });
          }
        }
      }
    } finally {
      if (mounted) setState(() => busyItems.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<LoadResult>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _OperationErrorCard(
              message: _planErrorText(snapshot.error!, widget.localOnly),
              onRetry: refresh,
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final result = snapshot.data!;
          if (result.error != null) {
            return ListView(children: [
              _OperationErrorCard(
                message: localDataErrorText(result.error!),
                onRetry: refresh,
              ),
            ]);
          }
          return RefreshIndicator(
            onRefresh: refresh,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (operationError != null)
                  _OperationErrorCard(
                    message: operationError!,
                    onRetry: retryOperation!,
                  ),
                if (result.offline)
                  const Card(
                      child: ListTile(
                    leading: Icon(Icons.cloud_off_outlined),
                    title: Text('نمایش نسخه آفلاین'),
                  )),
                ...result.reminders.map((reminder) => Card(
                      child: ListTile(
                        leading:
                            const Icon(Icons.notifications_active_outlined),
                        title:
                            Text('یادآوری · ${reminder['title'] ?? 'برنامه'}'),
                        subtitle:
                            const Text('زمان این مورد رسیده یا نزدیک است.'),
                      ),
                    )),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('امروز',
                            style: Theme.of(context).textTheme.headlineSmall),
                        const SizedBox(height: 6),
                        Text('${result.items.length} مورد در برنامه امروز'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                if (result.items.isEmpty)
                  const EmptyCard(
                    icon: Icons.check_circle_outline,
                    title: 'امروز خلوت است',
                    subtitle:
                        'از برنامه‌ریز یک کار، تکلیف یا جلسه مطالعه اضافه کن.',
                  )
                else
                  ...result.items.map((item) => Card(
                        child: ListTile(
                          leading: const Icon(Icons.radio_button_unchecked),
                          title: Text(item['title']?.toString() ?? ''),
                          subtitle: Text(
                            '${faKind(item['kind']?.toString() ?? 'task')} · ${shortDate(item['starts_at'] ?? item['due_at'])}',
                          ),
                          trailing: IconButton(
                            tooltip: 'انجام شد',
                            onPressed: busyItems.contains(item['id'].toString())
                                ? null
                                : () => complete(item),
                            icon: busyItems.contains(item['id'].toString())
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2))
                                : const Icon(Icons.check_circle_outline),
                          ),
                        ),
                      )),
              ],
            ),
          );
        },
      );
}

class PlannerPage extends StatefulWidget {
  const PlannerPage({super.key, required this.api, this.localOnly = false});
  final IdentityApi api;
  final bool localOnly;
  @override
  State<PlannerPage> createState() => _PlannerPageState();
}

class _PlannerPageState extends State<PlannerPage> {
  late Future<LoadResult> future;
  final busyItems = <String>{};
  bool openingForm = false;
  String? operationError;
  VoidCallback? retryOperation;

  @override
  void initState() {
    super.initState();
    future = load();
    if (!widget.localOnly) flushQueue();
  }

  Future<void> flushQueue() async {
    try {
      final queue = await OfflineStore.instance.readQueue();
      if (queue.isEmpty) return;
      final result = await widget.api.submitSyncMutations(queue);
      final applied = <String>{};
      for (final raw in (result['results'] as List<dynamic>? ?? const [])) {
        final row = Map<String, dynamic>.from(raw as Map);
        if (row['status'] == 'accepted' || row['status'] == 'already_applied') {
          applied.add(row['id'].toString());
        }
      }
      await OfflineStore.instance.removeQueued(applied);
    } catch (_) {}
  }

  Future<LoadResult> load() async {
    final now = DateTime.now();
    final from = DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: 1));
    final to = from.add(const Duration(days: 15));
    try {
      final items = widget.localOnly
          ? await widget.api.listPlanItems()
          : await widget.api.listPlanItems(from: from, to: to);
      if (!widget.localOnly) await OfflineStore.instance.cachePlanner(items);
      return LoadResult(items, false);
    } catch (error) {
      if (widget.localOnly) return LoadResult(const [], false, error: error);
      return LoadResult(await OfflineStore.instance.readPlanner(), true);
    }
  }

  Future<void> reload() async {
    if (!mounted) return;
    setState(() {
      future = load();
    });
    await future;
  }

  Future<void> showItemForm({Map<String, dynamic>? item}) async {
    if (openingForm) return;
    setState(() {
      openingForm = true;
      operationError = null;
      retryOperation = null;
    });
    try {
      String? familyId;
      if (!widget.localOnly && item == null) {
        final families = await widget.api.listFamilies();
        familyId = families.isEmpty ? null : families.first['id']?.toString();
      }
      if (!mounted) return;
      final saved = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _PlanItemDialog(
          api: widget.api,
          localOnly: widget.localOnly,
          item: item,
          familyId: familyId,
        ),
      );
      if (saved == true) await reload();
    } catch (error) {
      if (mounted) {
        setState(() {
          operationError = _planErrorText(error, widget.localOnly);
          retryOperation = () => showItemForm(item: item);
        });
      }
    } finally {
      if (mounted) setState(() => openingForm = false);
    }
  }

  Future<void> mutate(
    Map<String, dynamic> item,
    Map<String, dynamic> data, {
    String? offlineOperation,
  }) async {
    final id = item['id'].toString();
    if (busyItems.contains(id)) return;
    setState(() {
      busyItems.add(id);
      operationError = null;
      retryOperation = null;
    });
    try {
      await widget.api.updatePlanItem(id, data);
      await reload();
    } catch (error) {
      var message = _planErrorText(error, widget.localOnly);
      if (!widget.localOnly && offlineOperation != null) {
        try {
          await OfflineStore.instance.enqueue({
            'id':
                '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(99999)}',
            'entityType': 'plan_item',
            'entityId': item['id'],
            'operation': offlineOperation,
            'clientUpdatedAt': DateTime.now().toUtc().toIso8601String(),
            'payload': data,
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('آفلاین هستی؛ تغییر برای همگام‌سازی ذخیره شد.'),
            ));
          }
          return;
        } catch (queueError) {
          message = _planErrorText(queueError, false);
        }
      }
      if (mounted) {
        setState(() {
          operationError = message;
          retryOperation =
              () => mutate(item, data, offlineOperation: offlineOperation);
        });
      }
    } finally {
      if (mounted) setState(() => busyItems.remove(id));
    }
  }

  Future<void> reschedule(Map<String, dynamic> item) async {
    final start = parseDate(item['starts_at']);
    final due = parseDate(item['due_at']);
    final data = <String, dynamic>{
      if (start != null)
        'startsAt':
            start.add(const Duration(days: 1)).toUtc().toIso8601String(),
      if (due != null)
        'dueAt': due.add(const Duration(days: 1)).toUtc().toIso8601String(),
      if (start == null && due == null)
        'dueAt': DateTime.now()
            .add(const Duration(days: 1))
            .toUtc()
            .toIso8601String(),
    };
    await mutate(item, data, offlineOperation: 'reschedule');
  }

  Future<void> archive(Map<String, dynamic> item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('بایگانی مورد'),
        content:
            Text('«${item['title'] ?? ''}» از امروز و برنامه کنار گذاشته شود؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('انصراف')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('بایگانی')),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await mutate(item, {'status': 'cancelled'});
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<LoadResult>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _OperationErrorCard(
              message: _planErrorText(snapshot.error!, widget.localOnly),
              onRetry: reload,
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final result = snapshot.data!;
          return Scaffold(
            backgroundColor: Colors.transparent,
            floatingActionButton: result.error == null
                ? FloatingActionButton.extended(
                    onPressed: openingForm ? null : () => showItemForm(),
                    icon: const Icon(Icons.add),
                    label: const Text('جدید'),
                  )
                : null,
            body: RefreshIndicator(
              onRefresh: reload,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                children: [
                  if (result.error != null)
                    _OperationErrorCard(
                      message: localDataErrorText(result.error!),
                      onRetry: reload,
                    )
                  else ...[
                    if (operationError != null)
                      _OperationErrorCard(
                        message: operationError!,
                        onRetry: retryOperation!,
                      ),
                    if (result.offline)
                      const Card(
                          child: ListTile(
                        leading: Icon(Icons.cloud_off_outlined),
                        title: Text('حالت آفلاین'),
                        subtitle:
                            Text('آخرین برنامه ذخیره‌شده نمایش داده می‌شود.'),
                      )),
                    if (result.items.isEmpty)
                      const EmptyCard(
                        icon: Icons.event_note_outlined,
                        title: 'هنوز برنامه‌ای نداری',
                        subtitle:
                            'کار، تکلیف، رویداد، روتین، هدف یا جلسه مطالعه اضافه کن.',
                      )
                    else
                      ...result.items.map((item) => Card(
                            child: ListTile(
                              title: Text(item['title']?.toString() ?? ''),
                              subtitle: Text(
                                '${faKind(item['kind']?.toString() ?? 'task')} · ${shortDate(item['starts_at'] ?? item['due_at'])}',
                              ),
                              trailing: busyItems
                                      .contains(item['id'].toString())
                                  ? const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2))
                                  : PopupMenuButton<String>(
                                      tooltip: 'عملیات برنامه',
                                      onSelected: (value) async {
                                        switch (value) {
                                          case 'edit':
                                            await showItemForm(item: item);
                                          case 'complete':
                                            await mutate(
                                                item, {'status': 'completed'});
                                          case 'tomorrow':
                                            await reschedule(item);
                                          case 'archive':
                                            await archive(item);
                                        }
                                      },
                                      itemBuilder: (_) => [
                                        const PopupMenuItem(
                                            value: 'edit',
                                            child: Text('ویرایش عنوان')),
                                        const PopupMenuItem(
                                            value: 'complete',
                                            child: Text('انجام شد')),
                                        const PopupMenuItem(
                                            value: 'tomorrow',
                                            child: Text('انتقال به فردا')),
                                        if (widget.localOnly)
                                          const PopupMenuItem(
                                              value: 'archive',
                                              child: Text('بایگانی')),
                                      ],
                                    ),
                            ),
                          )),
                  ],
                ],
              ),
            ),
          );
        },
      );
}

class _PlanItemDialog extends StatefulWidget {
  const _PlanItemDialog(
      {required this.api, required this.localOnly, this.item, this.familyId});
  final IdentityApi api;
  final bool localOnly;
  final Map<String, dynamic>? item;
  final String? familyId;

  @override
  State<_PlanItemDialog> createState() => _PlanItemDialogState();
}

class _PlanItemDialogState extends State<_PlanItemDialog> {
  late final TextEditingController title;
  String kind = 'task';
  String visibility = 'private';
  bool saving = false;
  String? error;

  @override
  void initState() {
    super.initState();
    title =
        TextEditingController(text: widget.item?['title']?.toString() ?? '');
    kind = widget.item?['kind']?.toString() ?? 'task';
  }

  @override
  void dispose() {
    title.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (saving) return;
    if (title.text.trim().isEmpty) {
      setState(() => error = 'عنوان را وارد کن.');
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      if (widget.item != null) {
        await widget.api.updatePlanItem(widget.item!['id'].toString(), {
          'title': title.text.trim(),
        });
      } else {
        final when = DateTime.now().add(const Duration(hours: 1));
        await widget.api.createPlanItem({
          'kind': kind,
          'title': title.text.trim(),
          'startsAt': when.toUtc().toIso8601String(),
          'dueAt': when.add(const Duration(hours: 1)).toUtc().toIso8601String(),
          'visibility': widget.localOnly ? 'private' : visibility,
          if (!widget.localOnly &&
              visibility != 'private' &&
              widget.familyId != null)
            'familyId': widget.familyId,
          if (!widget.localOnly) 'reminderMinutesBefore': [15],
        });
      }
      if (mounted) Navigator.pop(context, true);
    } catch (failure) {
      if (mounted)
        setState(() => error = _planErrorText(failure, widget.localOnly));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !saving,
        child: AlertDialog(
          title: Text(widget.item == null ? 'مورد جدید' : 'ویرایش عنوان'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                key: const Key('plan-title'),
                controller: title,
                enabled: !saving,
                decoration: const InputDecoration(labelText: 'عنوان'),
              ),
              if (widget.item == null) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: const Key('plan-kind'),
                  initialValue: kind,
                  decoration: const InputDecoration(labelText: 'نوع'),
                  items: const [
                    DropdownMenuItem(value: 'task', child: Text('کار')),
                    DropdownMenuItem(value: 'assignment', child: Text('تکلیف')),
                    DropdownMenuItem(value: 'event', child: Text('رویداد')),
                    DropdownMenuItem(value: 'routine', child: Text('روتین')),
                    DropdownMenuItem(value: 'goal', child: Text('هدف')),
                    DropdownMenuItem(
                        value: 'study_session', child: Text('جلسه مطالعه')),
                  ],
                  onChanged: saving
                      ? null
                      : (value) {
                          if (value != null) setState(() => kind = value);
                        },
                ),
                if (!widget.localOnly) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: visibility,
                    decoration: const InputDecoration(labelText: 'اشتراک'),
                    items: const [
                      DropdownMenuItem(value: 'private', child: Text('خصوصی')),
                      DropdownMenuItem(value: 'family', child: Text('خانواده')),
                      DropdownMenuItem(
                          value: 'parent_guardian',
                          child: Text('والد / سرپرست')),
                    ],
                    onChanged: saving
                        ? null
                        : (value) {
                            if (value != null)
                              setState(() => visibility = value);
                          },
                  ),
                ],
              ],
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
            ]),
          ),
          actions: [
            TextButton(
                onPressed: saving ? null : () => Navigator.pop(context, false),
                child: const Text('انصراف')),
            FilledButton(
                onPressed: saving ? null : save,
                child: Text(saving ? 'در حال ذخیره...' : 'ذخیره')),
          ],
        ),
      );
}

class SchoolPage extends StatefulWidget {
  const SchoolPage({super.key, required this.api});
  final IdentityApi api;
  @override
  State<SchoolPage> createState() => _SchoolPageState();
}

class _SchoolPageState extends State<SchoolPage> {
  late Future<SchoolLoad> future;
  @override
  void initState() {
    super.initState();
    future = load();
  }

  Future<SchoolLoad> load() async {
    final profile = await widget.api.getProfile();
    final userId = profile['user_id']?.toString() ?? '';
    if (userId.isEmpty) return SchoolLoad(userId, const {}, false);
    try {
      final overview = await widget.api.getSchoolOverview(userId);
      await OfflineStore.instance.cacheSchool([
        {'userId': userId, 'overview': overview}
      ]);
      return SchoolLoad(userId, overview, false);
    } catch (_) {
      final cached = await OfflineStore.instance.readSchool();
      if (cached.isNotEmpty) {
        return SchoolLoad(
          cached.first['userId']?.toString() ?? userId,
          Map<String, dynamic>.from(
              cached.first['overview'] as Map? ?? const {}),
          true,
        );
      }
      return SchoolLoad(userId, const {}, true);
    }
  }

  Future<void> reload() async {
    setState(() => future = load());
    await future;
  }

  Future<void> quickSetup() async {
    var contexts = await widget.api.listLifeContexts();
    Map<String, dynamic>? student;
    for (final row in contexts) {
      if (row['kind'] == 'student') {
        student = row;
        break;
      }
    }
    student ??=
        await widget.api.createLifeContext(kind: 'student', title: 'مدرسه');
    final now = DateTime.now();
    final year = await widget.api.createAcademicYear({
      'lifeContextId': student['id'],
      'title':
          'سال تحصیلی ' + now.year.toString() + '-' + (now.year + 1).toString(),
      'startsOn': now.year.toString() + '-09-01',
      'endsOn': (now.year + 1).toString() + '-06-30',
    });
    final term = await widget.api.createAcademicTerm(year['id'].toString(), {
      'title': 'نیمسال اول',
      'startsOn': now.year.toString() + '-09-01',
      'endsOn': (now.year + 1).toString() + '-01-31',
    });
    await widget.api.createSubject(term['id'].toString(), {'name': 'ریاضی'});
    await reload();
  }

  Future<void> addSchoolItem(String kind) async {
    final data = await future;
    final subjects = data.overview['subjects'] as List<dynamic>? ?? const [];
    if (subjects.isEmpty) return;
    final title = TextEditingController();
    final first = Map<String, dynamic>.from(subjects.first as Map);
    final selected = ValueNotifier<String>(first['id'].toString());
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(kind == 'exam' ? 'امتحان جدید' : 'تکلیف جدید'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: title,
              decoration: const InputDecoration(labelText: 'عنوان')),
          const SizedBox(height: 12),
          ValueListenableBuilder<String>(
            valueListenable: selected,
            builder: (_, value, __) => DropdownButtonFormField<String>(
              initialValue: value,
              decoration: const InputDecoration(labelText: 'درس'),
              items: subjects.map((raw) {
                final row = Map<String, dynamic>.from(raw as Map);
                return DropdownMenuItem<String>(
                  value: row['id'].toString(),
                  child: Text(row['name']?.toString() ?? ''),
                );
              }).toList(),
              onChanged: (v) {
                if (v != null) selected.value = v;
              },
            ),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('انصراف')),
          FilledButton(
            onPressed: () async {
              if (title.text.trim().isEmpty) return;
              final due = DateTime.now().add(const Duration(days: 2));
              await widget.api.createPlanItem({
                'kind': kind,
                'title': title.text.trim(),
                'subjectId': selected.value,
                'dueAt': due.toUtc().toIso8601String(),
                'visibility': 'private',
                'reminderMinutesBefore': [60, 1440],
              });
              if (dialogContext.mounted) Navigator.pop(dialogContext, true);
            },
            child: const Text('ذخیره'),
          ),
        ],
      ),
    );
    title.dispose();
    selected.dispose();
    if (saved == true && mounted) await reload();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<SchoolLoad>(
        future: future,
        builder: (context, snapshot) {
          if (!snapshot.hasData)
            return const Center(child: CircularProgressIndicator());
          final data = snapshot.data!;
          final years = data.overview['years'] as List<dynamic>? ?? const [];
          final subjects =
              data.overview['subjects'] as List<dynamic>? ?? const [];
          final workload =
              data.overview['workload'] as List<dynamic>? ?? const [];
          final grades = data.overview['grades'] as List<dynamic>? ?? const [];
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (data.offline)
                const Card(
                    child: ListTile(
                        leading: Icon(Icons.cloud_off_outlined),
                        title: Text('اطلاعات مدرسه از کش نمایش داده می‌شود'))),
              if (years.isEmpty)
                EmptyCard(
                  icon: Icons.school_outlined,
                  title: 'مدرسه را آماده کن',
                  subtitle:
                      'سال تحصیلی، نیمسال و اولین درس را با شروع سریع بساز.',
                  action: FilledButton.icon(
                    onPressed: quickSetup,
                    icon: const Icon(Icons.auto_fix_high),
                    label: const Text('شروع سریع'),
                  ),
                )
              else ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('مدرسه',
                              style: Theme.of(context).textTheme.headlineSmall),
                          const SizedBox(height: 10),
                          Wrap(spacing: 8, runSpacing: 8, children: [
                            Chip(
                                label:
                                    Text(subjects.length.toString() + ' درس')),
                            Chip(
                                label: Text(workload.length.toString() +
                                    ' کار درسی پیش‌رو')),
                            Chip(
                                label:
                                    Text(grades.length.toString() + ' نمره')),
                          ]),
                          const SizedBox(height: 12),
                          Row(children: [
                            Expanded(
                                child: FilledButton.icon(
                              onPressed: () => addSchoolItem('assignment'),
                              icon: const Icon(Icons.assignment_add),
                              label: const Text('تکلیف'),
                            )),
                            const SizedBox(width: 8),
                            Expanded(
                                child: OutlinedButton.icon(
                              onPressed: () => addSchoolItem('exam'),
                              icon: const Icon(Icons.quiz_outlined),
                              label: const Text('امتحان'),
                            )),
                          ]),
                        ]),
                  ),
                ),
                const SizedBox(height: 12),
                Text('درس‌ها', style: Theme.of(context).textTheme.titleMedium),
                ...subjects.map((raw) {
                  final row = Map<String, dynamic>.from(raw as Map);
                  return Card(
                      child: ListTile(
                    leading: const Icon(Icons.menu_book_outlined),
                    title: Text(row['name']?.toString() ?? ''),
                    subtitle: Text(row['teacher_name']?.toString() ??
                        row['term_title']?.toString() ??
                        ''),
                  ));
                }),
                const SizedBox(height: 12),
                Text('کارهای درسی پیش‌رو',
                    style: Theme.of(context).textTheme.titleMedium),
                ...workload.map((raw) {
                  final row = Map<String, dynamic>.from(raw as Map);
                  return Card(
                      child: ListTile(
                    title: Text(row['title']?.toString() ?? ''),
                    subtitle: Text(faKind(row['kind']?.toString() ?? '') +
                        ' · ' +
                        shortDate(row['due_at'] ?? row['starts_at'])),
                  ));
                }),
              ],
            ],
          );
        },
      );
}

class ParentFamilyDashboard extends StatefulWidget {
  const ParentFamilyDashboard({super.key, required this.api});
  final IdentityApi api;
  @override
  State<ParentFamilyDashboard> createState() => _ParentFamilyDashboardState();
}

class _ParentFamilyDashboardState extends State<ParentFamilyDashboard> {
  late Future<List<Map<String, dynamic>>> families;
  @override
  void initState() {
    super.initState();
    families = widget.api.listFamilies();
  }

  @override
  Widget build(BuildContext context) =>
      FutureBuilder<List<Map<String, dynamic>>>(
        future: families,
        builder: (context, snapshot) {
          if (!snapshot.hasData)
            return const Center(child: CircularProgressIndicator());
          if (snapshot.data!.isEmpty) {
            return const EmptyCard(
              icon: Icons.family_restroom,
              title: 'خانواده‌ای متصل نیست',
              subtitle: 'از بخش پروفایل فضای خانواده بساز یا به آن بپیوند.',
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: snapshot.data!
                .map((family) =>
                    FamilyDashboardCard(api: widget.api, family: family))
                .toList(),
          );
        },
      );
}

class FamilyDashboardCard extends StatefulWidget {
  const FamilyDashboardCard(
      {super.key, required this.api, required this.family});
  final IdentityApi api;
  final Map<String, dynamic> family;
  @override
  State<FamilyDashboardCard> createState() => _FamilyDashboardCardState();
}

class _FamilyDashboardCardState extends State<FamilyDashboardCard> {
  late Future<List<Map<String, dynamic>>> members;
  @override
  void initState() {
    super.initState();
    members = widget.api.listFamilyMembers(widget.family['id'].toString());
  }

  Future<void> openFamilyGuidance(
    String familyId,
    String childId,
    String childName,
  ) async {
    final question = TextEditingController();
    String? advice;
    bool busy = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: Text('مشورت درباره $childName'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'راهنما فقط از خلاصه‌های مجاز استفاده می‌کند و متن خصوصی فرزند را نمی‌بیند.',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: question,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'سؤال شما',
                    hintText:
                        'مثلاً چطور بدون فشار درباره امتحان‌ها با او صحبت کنم؟',
                  ),
                ),
                if (advice != null) ...[
                  const SizedBox(height: 14),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      advice!,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(dialogContext),
              child: const Text('بستن'),
            ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      if (question.text.trim().isEmpty) return;
                      setLocalState(() => busy = true);
                      try {
                        final result = await widget.api.requestFamilyGuidance(
                          familyId,
                          childId,
                          question.text.trim(),
                        );
                        setLocalState(() {
                          advice = result['advice']?.toString() ??
                              'پیشنهادی دریافت نشد.';
                        });
                      } catch (_) {
                        setLocalState(() {
                          advice =
                              'دریافت راهنمایی انجام نشد. دوباره تلاش کنید.';
                        });
                      } finally {
                        setLocalState(() => busy = false);
                      }
                    },
              child: Text(busy ? 'در حال بررسی...' : 'دریافت راهنمایی'),
            ),
          ],
        ),
      ),
    );
    question.dispose();
  }

  Future<void> openChild(Map<String, dynamic> child) async {
    final familyId = widget.family['id'].toString();
    final childId = child['user_id'].toString();
    final summary = await widget.api.getChildSupportSummary(familyId, childId);
    Map<String, dynamic>? wellbeing;
    try {
      wellbeing =
          await widget.api.getGuardianWellbeingSummary(familyId, childId);
    } catch (_) {
      wellbeing = null;
    }
    if (!mounted) return;
    final metrics =
        Map<String, dynamic>.from(summary['metrics'] as Map? ?? const {});
    final upcoming = summary['upcoming'] as List<dynamic>? ?? const [];
    final wellbeingSummary = wellbeing == null
        ? const <String, dynamic>{}
        : Map<String, dynamic>.from(
            wellbeing['summary'] as Map? ?? const <String, dynamic>{},
          );
    final safety = wellbeing == null
        ? const <String, dynamic>{}
        : Map<String, dynamic>.from(
            wellbeing['safety'] as Map? ?? const <String, dynamic>{},
          );
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
            'خلاصه حمایت · ' + (child['display_name']?.toString() ?? 'فرزند')),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    Chip(
                        label: Text((metrics['overdue'] ?? 0).toString() +
                            ' عقب‌افتاده')),
                    Chip(
                        label: Text(
                            (metrics['completedLast7Days'] ?? 0).toString() +
                                ' انجام‌شده')),
                    Chip(
                        label: Text(
                            (metrics['studyMinutesLast7Days'] ?? 0).toString() +
                                ' دقیقه مطالعه')),
                    if (metrics['gradePercent'] != null)
                      Chip(
                          label: Text('میانگین ' +
                              metrics['gradePercent'].toString() +
                              '٪')),
                  ]),
                  if (wellbeing != null) ...[
                    const SizedBox(height: 14),
                    Text('خلاصه حال خوب',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      Chip(
                        label: Text(
                          (wellbeingSummary['checkin_count'] ?? 0).toString() +
                              ' ثبت مجاز',
                        ),
                      ),
                      if (wellbeingSummary['mood_average'] != null)
                        Chip(
                          label: Text(
                            'حال ' +
                                wellbeingSummary['mood_average'].toString() +
                                '/5',
                          ),
                        ),
                      if (wellbeingSummary['stress_average'] != null)
                        Chip(
                          label: Text(
                            'استرس ' +
                                wellbeingSummary['stress_average'].toString() +
                                '/5',
                          ),
                        ),
                      if ((safety['open_urgent_count'] ?? 0) != 0)
                        Chip(
                          avatar:
                              const Icon(Icons.warning_amber_rounded, size: 18),
                          label: Text(
                            safety['open_urgent_count'].toString() +
                                ' هشدار ایمنی نیازمند توجه',
                          ),
                        ),
                    ]),
                    const SizedBox(height: 6),
                    const Text(
                      'این بخش فقط خلاصه مجاز و سیگنال ایمنی را نشان می‌دهد؛ متن خصوصی گفت‌وگو یا یادداشت نمایش داده نمی‌شود.',
                    ),
                  ],
                  const SizedBox(height: 10),
                  const Text('موارد پیش‌رو'),
                  ...upcoming.take(8).map((raw) {
                    final row = Map<String, dynamic>.from(raw as Map);
                    return ListTile(
                      dense: true,
                      title: Text(row['title']?.toString() ?? ''),
                      subtitle: Text(faKind(row['kind']?.toString() ?? '') +
                          ' · ' +
                          shortDate(row['due_at'] ?? row['starts_at'])),
                    );
                  }),
                ]),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('بستن'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(dialogContext);
              openFamilyGuidance(
                familyId,
                childId,
                child['display_name']?.toString() ?? 'فرزند',
              );
            },
            icon: const Icon(Icons.psychology_alt_outlined),
            label: const Text('مشورت با راهنمای خانواده'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(widget.family['name']?.toString() ?? 'خانواده',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: members,
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const LinearProgressIndicator();
                final children = snapshot.data!
                    .where((row) => row['role'] == 'teen_minor')
                    .toList();
                if (children.isEmpty)
                  return const Text(
                      'هنوز فرزند/نوجوانی به این خانواده متصل نیست.');
                return Column(
                  children: children
                      .map((child) => ListTile(
                            leading: const CircleAvatar(
                                child: Icon(Icons.school_outlined)),
                            title: Text(
                                child['display_name']?.toString() ?? 'فرزند'),
                            subtitle: const Text(
                                'برنامه، تکالیف، امتحان‌ها و پیشرفت مجاز'),
                            trailing: const Icon(Icons.chevron_left),
                            onTap: () => openChild(child),
                          ))
                      .toList(),
                );
              },
            ),
          ]),
        ),
      );
}

class EmptyCard extends StatelessWidget {
  const EmptyCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(children: [
            Icon(icon, size: 42),
            const SizedBox(height: 10),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(subtitle, textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 14), action!],
          ]),
        ),
      );
}

class LoadResult {
  const LoadResult(this.items, this.offline,
      {this.reminders = const [], this.error});
  final List<Map<String, dynamic>> items;
  final bool offline;
  final List<Map<String, dynamic>> reminders;
  final Object? error;
}

class SchoolLoad {
  const SchoolLoad(this.userId, this.overview, this.offline);
  final String userId;
  final Map<String, dynamic> overview;
  final bool offline;
}
