import 'dart:async';
import 'package:flutter/material.dart';
import 'api.dart';
import 'offline_store.dart';
import 'plan_sync.dart';
import 'study_ui.dart';
import 'dashboard_ui.dart';

String faKind(String kind) => switch (kind) {
      'assignment' => 'تکلیف',
      'exam' => 'امتحان',
      'study_session' => 'مطالعه',
      'event' => 'رویداد',
      'routine' => 'روتین',
      'goal' => 'هدف',
      _ => 'کار',
    };
DateTime? parseDate(dynamic value) =>
    value == null ? null : DateTime.tryParse(value.toString())?.toLocal();
String shortDate(dynamic value) {
  final d = parseDate(value);
  return d == null
      ? ''
      : '${d.month}/${d.day} · ${d.hour}:${d.minute.toString().padLeft(2, '0')}';
}

String uiErrorText(Object error) {
  if (error is ApiException) {
    if (error.code == 'local_storage_restart_required') {
      return 'وضعیت ذخیره نامشخص است. برنامه را از تنظیمات دستگاه «توقف اجباری» کن و دوباره باز کن.';
    }
    if (error.code == 'local_storage_failed' ||
        error.code == 'local_data_corrupt') {
      return 'خواندن یا ذخیره داده دستگاه انجام نشد. تغییر تأیید نشده است.';
    }
    if (error.statusCode == 401) return 'نشست ورود معتبر نیست. دوباره وارد شو.';
    if (error.statusCode == 403) {
      return 'برای این اطلاعات یا عملیات دسترسی نداری.';
    }
    if (error.code == 'sync_conflict' || error.code == 'version_conflict') {
      return 'نسخه داده تغییر کرده است. تغییر معلق نگه داشته شد؛ ابتدا اطلاعات سرور را بررسی کن.';
    }
    if (error.code == 'sync_pending') {
      return 'تغییر قبلی هنوز تأیید نشده است. ابتدا همگام‌سازی را دوباره امتحان کن.';
    }
    if (error.code == 'sms_unavailable') {
      return 'سرویس پیامک فعال نیست. ارسال کد تأیید نشده است.';
    }
    if (error.code == 'invalid_or_expired_otp') {
      return 'کد معتبر نیست یا منقضی شده است.';
    }
    if (error.code == 'rate_limited') {
      return 'درخواست‌ها زیاد است. کمی صبر کن و دوباره تلاش کن.';
    }
    if (error.statusCode >= 500) {
      return 'سرور پاسخ معتبر نداد. اطلاعات تازه دریافت نشده است.';
    }
  }
  if (isOfflineFailure(error)) {
    return 'اتصال برقرار نیست. اطلاعات تازه دریافت نشده است.';
  }
  return 'عملیات انجام نشد. دوباره تلاش کن.';
}

Future<List<Map<String, dynamic>>> ownedPlanFallback(
    IdentityApi api, OfflineStore store,
    {required bool today}) async {
  final rows = today ? await store.readToday() : await store.readPlanner();
  if (api is! HttpIdentityApi) return rows;
  final userId = api.currentUserId;
  if (userId == null) {
    throw const ApiException(401, 'authenticated_cache_required');
  }
  // Only locally generated creates can establish ownership before an ACK.
  final ownPending = (await store.readQueue())
      .where((m) =>
          m['entityType'] == 'plan_item' &&
          m['operation'] == 'create' &&
          m['queueStatus'] != 'rejected')
      .map((m) => m['entityId'])
      .toSet();
  return rows
      .where((row) =>
          row['owner_user_id'] == userId ||
          row['ownerUserId'] == userId ||
          ownPending.contains(row['id']))
      .toList();
}

String numberInput(String value) {
  const digits = '۰۱۲۳۴۵۶۷۸۹٠١٢٣٤٥٦٧٨٩';
  return value
      .trim()
      .split('')
      .map((c) {
        final i = digits.indexOf(c);
        return i < 0 ? c : (i % 10).toString();
      })
      .join()
      .replaceAll('٫', '.')
      .replaceAll('٬', '');
}

class Phase3HomeContent extends StatelessWidget {
  const Phase3HomeContent(
      {super.key,
      required this.api,
      required this.page,
      required this.adultShell});
  final IdentityApi api;
  final String page;
  final bool adultShell;
  @override
  Widget build(BuildContext context) {
    if (page == 'امروز') return TodayPage(api: api);
    if (['برنامه‌ریز', 'برنامه هفتگی', 'تقویم', 'تکالیف و کارها']
        .contains(page)) {
      return PlannerPage(api: api);
    }
    if (page == 'خانواده') return ParentFamilyDashboard(api: api);
    if (page == 'تمرکز') return StudyHub(api: api);
    if (page == 'امتحان‌ها و نمرات') return SchoolPage(api: api);
    return const CoreNotice(
        title: 'لایف‌گاید', subtitle: 'این بخش در این مرحله فعال نیست.');
  }
}

class CoreNotice extends StatelessWidget {
  const CoreNotice({super.key, required this.title, required this.subtitle});
  final String title, subtitle;
  @override
  Widget build(BuildContext context) => Center(
      child: Card(
          margin: const EdgeInsets.all(20),
          child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(title, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(subtitle, textAlign: TextAlign.center)
              ]))));
}

class LoadError extends StatelessWidget {
  const LoadError({super.key, required this.error, required this.retry});
  final Object error;
  final VoidCallback retry;
  @override
  Widget build(BuildContext context) => Center(
      child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(uiErrorText(error), textAlign: TextAlign.center),
            TextButton(onPressed: retry, child: const Text('تلاش دوباره'))
          ])));
}

class SyncNotice extends StatelessWidget {
  const SyncNotice(
      {super.key, required this.offline, required this.pending, this.syncedAt});
  final bool offline;
  final int pending;
  final DateTime? syncedAt;
  @override
  Widget build(BuildContext context) => Card(
      child: ListTile(
          leading: Icon(
              offline ? Icons.cloud_off_outlined : Icons.cloud_done_outlined),
          title: Text(offline
              ? 'نسخه ذخیره‌شده؛ داده زنده نیست'
              : 'آخرین دریافت از سرور'),
          subtitle: Text(
              '${syncedAt == null ? 'زمان دریافت نامشخص' : shortDate(syncedAt!.toIso8601String())}${pending > 0 ? '\n$pending تغییر در انتظار تأیید سرور' : ''}')));
}

class TodayPage extends StatelessWidget {
  const TodayPage({super.key, required this.api});
  final IdentityApi api;
  @override
  Widget build(BuildContext context) => _PlanList(api: api, today: true);
}

class PlannerPage extends StatelessWidget {
  const PlannerPage({super.key, required this.api});
  final IdentityApi api;
  @override
  Widget build(BuildContext context) => _PlanList(api: api, today: false);
}

class _PlanList extends StatefulWidget {
  const _PlanList({required this.api, required this.today});
  final IdentityApi api;
  final bool today;
  @override
  State<_PlanList> createState() => _PlanListState();
}

class _PlanListState extends State<_PlanList> with WidgetsBindingObserver {
  late Future<LoadResult> future;
  Timer? poll;
  bool loading = false;
  String? busyId;
  String? operationError;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    future = load();
    startPoll();
  }

  void startPoll() {
    poll?.cancel();
    poll = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!loading && busyId == null) reload();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      startPoll();
      reload();
    } else {
      poll?.cancel();
    }
  }

  @override
  void dispose() {
    poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<LoadResult> load() async {
    loading = true;
    try {
      final store = OfflineStore.forApi(widget.api);
      await PlanSync(widget.api, store: store).flush();
      final now = DateTime.now();
      final from = DateTime(now.year, now.month, now.day);
      final to = from.add(const Duration(days: 1));
      List<Map<String, dynamic>> items;
      var reminders = <Map<String, dynamic>>[];
      bool offline = false;
      try {
        items = widget.today
            ? await widget.api.getToday(from: from, to: to)
            : await widget.api.listPlanItems();
        if (widget.today) reminders = await widget.api.claimDueReminders();
        // The store merges queued mutations atomically with each fresh cache.
        if (widget.today) {
          await store.cacheToday(items);
          items = await store.readToday();
        } else {
          await store.cachePlanner(items);
          items = await store.readPlanner();
        }
      } catch (error) {
        if (!isOfflineFailure(error)) rethrow;
        offline = true;
        items = await ownedPlanFallback(widget.api, store, today: widget.today);
      }
      return LoadResult(
          items.where((i) => i['status'] != 'cancelled').toList(), offline,
          pending: await store.pendingCount(),
          syncedAt: await store.readLastSync(),
          reminders: reminders);
    } finally {
      loading = false;
    }
  }

  Future<void> reload() async {
    if (!mounted) return;
    setState(() {
      future = load();
    });
    try {
      await future;
    } catch (_) {/* FutureBuilder renders the error. */}
  }

  Future<void> edit([Map<String, dynamic>? item]) async {
    final outcome = await showDialog<MutationOutcome>(
        context: context,
        builder: (_) => PlanItemDialog(api: widget.api, item: item));
    if (outcome != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(outcome.queued
              ? 'تغییر روی دستگاه ثبت شد؛ در انتظار تأیید سرور.'
              : 'تغییر توسط سرور تأیید شد.')));
      await reload();
    }
  }

  Future<void> action(Map<String, dynamic> item, String action) async {
    if (busyId != null) return;
    if (action == 'edit') {
      await edit(item);
      return;
    }
    if (action == 'study') {
      if (item['pending_sync'] == true) {
        setState(() => operationError =
            'تکلیف هنوز در سرور تأیید نشده است؛ تایمر پس از همگام‌سازی فعال می‌شود.');
        return;
      }
      if (widget.api is! HttpIdentityApi) {
        setState(() => operationError = 'اتصال مطالعه در دسترس نیست.');
        return;
      }
      await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) =>
              StudyTimerPage(api: widget.api as HttpIdentityApi, item: item)));
      if (mounted) await reload();
      return;
    }
    if (action == 'archive') {
      final confirmed = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
                  title: const Text('بایگانی مورد'),
                  content: Text('«${item['title']}» بایگانی شود؟'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(c, false),
                        child: const Text('انصراف')),
                    FilledButton(
                        onPressed: () => Navigator.pop(c, true),
                        child: const Text('بایگانی'))
                  ]));
      if (confirmed != true || !mounted) return;
    }
    setState(() {
      busyId = item['id'].toString();
      operationError = null;
    });
    try {
      final sync = PlanSync(widget.api);
      final outcome = action == 'archive'
          ? await sync.archive(item)
          : await sync.complete(item);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(outcome.queued
                ? 'تغییر در انتظار تأیید سرور است.'
                : 'سرور تغییر را تأیید کرد.')));
        await reload();
      }
    } catch (error) {
      if (mounted) setState(() => operationError = uiErrorText(error));
    } finally {
      if (mounted) setState(() => busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<LoadResult>(
      future: future,
      builder: (context, s) {
        if (s.hasError) return LoadError(error: s.error!, retry: reload);
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        final data = s.data!;
        return RefreshIndicator(
            onRefresh: reload,
            child: ListView(padding: const EdgeInsets.all(16), children: [
              ...data.reminders.map((r) => Card(
                  child: ListTile(
                      leading: const Icon(Icons.notifications_active_outlined),
                      title: Text('یادآوری · ${r['title'] ?? 'برنامه'}'),
                      subtitle:
                          const Text('موعد این مورد رسیده یا نزدیک است.')))),
              SyncNotice(
                  offline: data.offline,
                  pending: data.pending,
                  syncedAt: data.syncedAt),
              if (operationError != null)
                Card(
                    child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(operationError!,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error)))),
              Row(children: [
                Expanded(
                    child: Text(widget.today ? 'امروز' : 'برنامه‌ریز',
                        style: Theme.of(context).textTheme.headlineSmall)),
                if (!widget.today)
                  FilledButton.icon(
                      onPressed: busyId == null ? () => edit() : null,
                      icon: const Icon(Icons.add),
                      label: const Text('جدید'))
              ]),
              if (data.items.isEmpty)
                const EmptyCard(
                    icon: Icons.task_alt,
                    title: 'موردی در این برنامه نیست',
                    subtitle: 'از برنامه‌ریز کار یا تکلیف جدید اضافه کن.'),
              ...data.items.map((item) => Card(
                      child: ListTile(
                    leading: Icon(item['status'] == 'completed'
                        ? Icons.check_circle_outline
                        : Icons.radio_button_unchecked),
                    title: Text(item['title']?.toString() ?? ''),
                    subtitle: Text(
                        '${faKind(item['kind']?.toString() ?? 'task')} · ${shortDate(item['startsAt'] ?? item['starts_at'] ?? item['dueAt'] ?? item['due_at'])}${item['pending_sync'] == true ? '\nدر انتظار تأیید سرور' : ''}'),
                    trailing: busyId == item['id']
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator())
                        : PopupMenuButton<String>(
                            onSelected: (v) => action(item, v),
                            itemBuilder: (_) => [
                                  const PopupMenuItem(
                                      value: 'edit', child: Text('ویرایش')),
                                  const PopupMenuItem(
                                      value: 'complete',
                                      child: Text('انجام شد')),
                                  if (item['pending_sync'] != true &&
                                      widget.api is HttpIdentityApi &&
                                      ['assignment', 'task', 'study_session']
                                          .contains(item['kind']))
                                    const PopupMenuItem(
                                        value: 'study',
                                        child: Text('تایمر مطالعه')),
                                  const PopupMenuItem(
                                      value: 'archive', child: Text('بایگانی')),
                                ]),
                  ))),
            ]));
      });
}

class PlanItemDialog extends StatefulWidget {
  const PlanItemDialog(
      {super.key,
      required this.api,
      this.item,
      this.initialKind = 'task',
      this.subjects = const []});
  final IdentityApi api;
  final Map<String, dynamic>? item;
  final String initialKind;
  final List<Map<String, dynamic>> subjects;
  @override
  State<PlanItemDialog> createState() => _PlanItemDialogState();
}

class _PlanItemDialogState extends State<PlanItemDialog> {
  late final TextEditingController title, notes, minutes, points, outOf;
  late String kind;
  String priority = 'normal', status = 'planned';
  late DateTime when;
  bool shared = false, busy = false, sharingChanged = false;
  String originalVisibility = 'private';
  String? subjectId;
  String? familyId, error;
  List<Map<String, dynamic>> families = [];
  @override
  void initState() {
    super.initState();
    final i = widget.item;
    title = TextEditingController(text: i?['title']?.toString() ?? '');
    notes = TextEditingController(text: i?['notes']?.toString() ?? '');
    points = TextEditingController(
        text: (i?['grade_points'] ?? i?['gradePoints'])?.toString() ?? '');
    outOf = TextEditingController(
        text: (i?['grade_out_of'] ?? i?['gradeOutOf'])?.toString() ?? '');
    minutes = TextEditingController(
        text: (((i?['planned_duration_seconds'] ??
                    i?['plannedDurationSeconds'] ??
                    1800) as num) ~/
                60)
            .toString());
    kind = i?['kind']?.toString() ?? widget.initialKind;
    priority = i?['priority']?.toString() ?? 'normal';
    status = i?['status']?.toString() ?? 'planned';
    when = parseDate(i?['due_at'] ?? i?['dueAt'] ?? i?['starts_at']) ??
        DateTime.now().add(const Duration(hours: 1));
    originalVisibility = i?['visibility']?.toString() ?? 'private';
    shared = originalVisibility != 'private';
    subjectId = i?['subject_id']?.toString() ?? i?['subjectId']?.toString();
    if (subjectId == null && widget.subjects.isNotEmpty) {
      subjectId = widget.subjects.first['id'].toString();
    }
    familyId = i?['family_id']?.toString() ?? i?['familyId']?.toString();
    loadFamilies();
  }

  Future<void> loadFamilies() async {
    try {
      final rows = await widget.api.listFamilies();
      if (mounted) setState(() => families = rows);
    } catch (e) {
      if (mounted) setState(() => error = uiErrorText(e));
    }
  }

  @override
  void dispose() {
    title.dispose();
    notes.dispose();
    minutes.dispose();
    points.dispose();
    outOf.dispose();
    super.dispose();
  }

  Future<void> pickDate() async {
    final date = await showDatePicker(
        context: context,
        initialDate: when,
        firstDate: DateTime(2020),
        lastDate: DateTime(2100));
    if (date == null || !mounted) return;
    final time = await showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(when));
    if (time != null && mounted) {
      setState(() => when =
          DateTime(date.year, date.month, date.day, time.hour, time.minute));
    }
  }

  Future<void> save() async {
    if (busy) return;
    if (title.text.trim().isEmpty) {
      setState(() => error = 'عنوان را وارد کن.');
      return;
    }
    final duration = int.tryParse(numberInput(minutes.text));
    if (duration == null || duration < 0 || duration > 1440) {
      setState(
          () => error = 'زمان برنامه‌ریزی‌شده باید بین صفر و ۱۴۴۰ دقیقه باشد.');
      return;
    }
    final graded = ['assignment', 'exam'].contains(kind);
    final hasGrade =
        points.text.trim().isNotEmpty || outOf.text.trim().isNotEmpty;
    final gradePoints = num.tryParse(numberInput(points.text)),
        gradeOutOf = num.tryParse(numberInput(outOf.text));
    if (graded &&
        hasGrade &&
        (gradePoints == null ||
            gradeOutOf == null ||
            !gradePoints.isFinite ||
            !gradeOutOf.isFinite ||
            gradePoints < 0 ||
            gradeOutOf <= 0 ||
            gradePoints > gradeOutOf ||
            gradeOutOf > 999999.99)) {
      setState(() => error =
          'نمره و سقف نمره را با هم وارد کن؛ نمره باید بین صفر و سقف باشد.');
      return;
    }
    if (shared && familyId == null) {
      setState(() => error = 'خانواده‌ای را برای اشتراک با والد انتخاب کن.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final item = widget.item;
      final visibility = widget.item != null && !sharingChanged
          ? originalVisibility
          : shared
              ? 'parent_guardian'
              : 'private';
      final payload = <String, dynamic>{
        'kind': kind,
        'title': title.text.trim(),
        'priority': priority,
        'status': status,
        'notes': notes.text.trim(),
        'dueAt': when.toUtc().toIso8601String(),
        'plannedDurationSeconds': duration * 60,
        'visibility': visibility,
        'familyId': visibility != 'private' ? familyId : null,
        if (subjectId != null) 'subjectId': subjectId,
        if (graded &&
            (hasGrade ||
                widget.item?['grade_points'] != null ||
                widget.item?['gradePoints'] != null)) ...{
          'gradePoints': hasGrade ? gradePoints : null,
          'gradeOutOf': hasGrade ? gradeOutOf : null
        }
      };
      final sync = PlanSync(widget.api);
      final result = item == null
          ? await sync.create(payload)
          : await sync.update(item, payload);
      if (mounted) Navigator.pop(context, result);
    } catch (e) {
      if (mounted) setState(() => error = uiErrorText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !busy,
      child: AlertDialog(
          title: Text(widget.item == null ? 'مورد جدید' : 'ویرایش مورد'),
          content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                    controller: title,
                    enabled: !busy,
                    decoration: const InputDecoration(labelText: 'عنوان')),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                    initialValue: kind,
                    decoration: const InputDecoration(labelText: 'نوع'),
                    items: [
                      for (final k in [
                        'task',
                        'assignment',
                        'exam',
                        'event',
                        'routine',
                        'goal',
                        'study_session'
                      ])
                        DropdownMenuItem(value: k, child: Text(faKind(k)))
                    ],
                    onChanged:
                        busy ? null : (v) => setState(() => kind = v ?? kind)),
                if (widget.subjects.isNotEmpty)
                  DropdownButtonFormField<String>(
                      initialValue: subjectId,
                      decoration: const InputDecoration(labelText: 'درس'),
                      items: widget.subjects
                          .map((row) => DropdownMenuItem(
                              value: row['id'].toString(),
                              child: Text(row['name']?.toString() ?? 'درس')))
                          .toList(),
                      onChanged:
                          busy ? null : (v) => setState(() => subjectId = v)),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                    initialValue: priority,
                    decoration: const InputDecoration(labelText: 'اولویت'),
                    items: const [
                      DropdownMenuItem(value: 'low', child: Text('کم')),
                      DropdownMenuItem(value: 'normal', child: Text('معمولی')),
                      DropdownMenuItem(value: 'high', child: Text('زیاد')),
                      DropdownMenuItem(value: 'urgent', child: Text('فوری'))
                    ],
                    onChanged: busy
                        ? null
                        : (v) => setState(() => priority = v ?? priority)),
                if (widget.item != null)
                  DropdownButtonFormField<String>(
                      initialValue: status,
                      decoration: const InputDecoration(labelText: 'وضعیت'),
                      items: const [
                        DropdownMenuItem(
                            value: 'planned', child: Text('برنامه‌ریزی‌شده')),
                        DropdownMenuItem(
                            value: 'in_progress', child: Text('در حال انجام')),
                        DropdownMenuItem(
                            value: 'completed', child: Text('انجام‌شده'))
                      ],
                      onChanged: busy
                          ? null
                          : (v) => setState(() => status = v ?? status)),
                const SizedBox(height: 12),
                TextField(
                    controller: minutes,
                    enabled: !busy,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'زمان برنامه‌ریزی‌شده (دقیقه)')),
                if (['assignment', 'exam'].contains(kind)) ...[
                  TextField(
                      controller: points,
                      enabled: !busy,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration:
                          const InputDecoration(labelText: 'نمره (اختیاری)')),
                  TextField(
                      controller: outOf,
                      enabled: !busy,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                          labelText: 'سقف نمره (اختیاری)')),
                ],
                TextButton.icon(
                    onPressed: busy ? null : pickDate,
                    icon: const Icon(Icons.calendar_month),
                    label: Text('موعد · ${shortDate(when.toIso8601String())}')),
                TextField(
                    controller: notes,
                    enabled: !busy,
                    maxLines: 2,
                    decoration: const InputDecoration(
                        labelText: 'یادداشت خصوصی',
                        helperText:
                            'یادداشت در گزارش والد نمایش داده نمی‌شود.')),
                SwitchListTile(
                    title: const Text('اشتراک تکلیف با والد / سرپرست'),
                    subtitle: const Text(
                        'عنوان، وضعیت و زمان ثبت‌شده برای سرپرست مجاز دیده می‌شود.'),
                    value: shared,
                    onChanged: busy
                        ? null
                        : (v) => setState(() {
                              shared = v;
                              sharingChanged = true;
                            })),
                if (widget.item != null &&
                    !['private', 'parent_guardian']
                        .contains(originalVisibility) &&
                    !sharingChanged)
                  const Text(
                      'دامنه اشتراک فعلی با ذخیره حفظ می‌شود؛ تغییر کلید، آن را به والد یا خصوصی تغییر می‌دهد.'),
                if (shared)
                  DropdownButtonFormField<String>(
                      initialValue: familyId,
                      decoration: const InputDecoration(labelText: 'خانواده'),
                      items: families
                          .map((f) => DropdownMenuItem(
                              value: f['id'].toString(),
                              child: Text(f['name']?.toString() ?? 'خانواده')))
                          .toList(),
                      onChanged:
                          busy ? null : (v) => setState(() => familyId = v)),
                if (error != null)
                  Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error))),
              ]))),
          actions: [
            TextButton(
                onPressed: busy ? null : () => Navigator.pop(context),
                child: const Text('انصراف')),
            FilledButton(
                onPressed: busy ? null : save,
                child: Text(busy ? 'در حال ثبت...' : 'ذخیره'))
          ]));
}

class SchoolPage extends StatefulWidget {
  const SchoolPage({super.key, required this.api});
  final IdentityApi api;
  @override
  State<SchoolPage> createState() => _SchoolPageState();
}

class _SchoolPageState extends State<SchoolPage> {
  late Future<SchoolLoad> future;
  bool writing = false;
  String? writeError;
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
      await OfflineStore.forApi(widget.api).cacheSchool([
        {'userId': userId, 'overview': overview}
      ]);
      return SchoolLoad(userId, overview, false);
    } catch (failure) {
      if (!isOfflineFailure(failure)) rethrow;
      final cached = await OfflineStore.forApi(widget.api).readSchool();
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
    setState(() {
      future = load();
    });
    try {
      await future;
    } catch (_) {/* FutureBuilder renders retry failure. */}
  }

  Future<void> quickSetup() async {
    if (writing) return;
    setState(() {
      writing = true;
      writeError = null;
    });
    try {
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
        'title': 'سال تحصیلی ${now.year}-${now.year + 1}',
        'startsOn': '${now.year}-09-01',
        'endsOn': '${now.year + 1}-06-30',
      });
      final term = await widget.api.createAcademicTerm(year['id'].toString(), {
        'title': 'نیمسال اول',
        'startsOn': '${now.year}-09-01',
        'endsOn': '${now.year + 1}-01-31',
      });
      await widget.api.createSubject(term['id'].toString(), {'name': 'ریاضی'});
      await reload();
    } catch (error) {
      if (mounted) setState(() => writeError = uiErrorText(error));
    } finally {
      if (mounted) setState(() => writing = false);
    }
  }

  Future<void> addSchoolItem(String kind) async {
    try {
      final overview = await future;
      if (!mounted) return;
      final subjects = (overview.overview['subjects'] as List? ?? [])
          .map((raw) => Map<String, dynamic>.from(raw as Map))
          .toList();
      final saved = await showDialog<MutationOutcome>(
          context: context,
          builder: (_) => PlanItemDialog(
              api: widget.api, initialKind: kind, subjects: subjects));
      if (saved != null && mounted) await reload();
    } catch (error) {
      if (mounted) setState(() => writeError = uiErrorText(error));
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<SchoolLoad>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return LoadError(error: snapshot.error!, retry: reload);
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
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
              if (writing) const LinearProgressIndicator(),
              if (writeError != null) Text(writeError!),
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
                    onPressed: writing ? null : quickSetup,
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
                            Chip(label: Text('${subjects.length} درس')),
                            Chip(
                                label:
                                    Text('${workload.length} کار درسی پیش‌رو')),
                            Chip(label: Text('${grades.length} نمره')),
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
                    subtitle: Text(
                        '${faKind(row['kind']?.toString() ?? '')} · ${shortDate(row['due_at'] ?? row['starts_at'])}'),
                  ));
                }),
              ],
            ],
          );
        },
      );
}

class EmptyCard extends StatelessWidget {
  const EmptyCard(
      {super.key,
      required this.icon,
      required this.title,
      required this.subtitle,
      this.action});
  final IconData icon;
  final String title, subtitle;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Card(
      child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(children: [
            Icon(icon, size: 42),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(subtitle, textAlign: TextAlign.center),
            if (action != null) action!
          ])));
}

class LoadResult {
  const LoadResult(this.items, this.offline,
      {this.pending = 0, this.syncedAt, this.reminders = const []});
  final List<Map<String, dynamic>> items, reminders;
  final bool offline;
  final int pending;
  final DateTime? syncedAt;
}

class SchoolLoad {
  const SchoolLoad(this.userId, this.overview, this.offline);
  final String userId;
  final Map<String, dynamic> overview;
  final bool offline;
}
