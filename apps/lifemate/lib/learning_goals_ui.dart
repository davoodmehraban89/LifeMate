import 'package:flutter/material.dart';

import 'api.dart';
import 'learning_goal_sync.dart';
import 'offline_store.dart' show isOfflineFailure;

bool _goalAuthFailure(Object error) =>
    error is ApiException &&
    (error.statusCode == 401 || error.statusCode == 403);

String _goalError(Object error) {
  if (isOfflineFailure(error)) {
    return 'اتصال برقرار نیست؛ تغییر ذخیره‌شده هنوز تأیید سرور ندارد.';
  }
  if (_goalAuthFailure(error)) {
    return 'نشست یا دسترسی معتبر نیست؛ هدف‌های خصوصی قبلی از صفحه پاک شدند.';
  }
  if (error is ApiException && error.statusCode == 409) {
    return 'این هدف یک تغییر معلق یا تعارض نسخه دارد؛ ابتدا همگام‌سازی و نسخه سرور را بررسی کن.';
  }
  return 'عملیات با پاسخ معتبر سرور تأیید نشد؛ وضعیت را تازه کن.';
}

class LearningGoalsPage extends StatefulWidget {
  const LearningGoalsPage({super.key, required this.api});
  final HttpIdentityApi api;
  @override
  State<LearningGoalsPage> createState() => _LearningGoalsPageState();
}

class _LearningGoalsPageState extends State<LearningGoalsPage>
    with WidgetsBindingObserver {
  late final LearningGoalSync sync;
  Map<String, dynamic>? snapshot;
  String? error;
  bool busy = false, editing = false, active = true, stale = false;
  int epoch = 0;
  BuildContext? privateDialog;

  bool current(int request) => mounted && active && epoch == request;
  @override
  void initState() {
    super.initState();
    sync = LearningGoalSync(widget.api);
    WidgetsBinding.instance.addObserver(this);
    load();
  }

  @override
  void dispose() {
    ++epoch;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void closePrivateDialog() {
    final dialog = privateDialog;
    privateDialog = null;
    if (dialog?.mounted != true) return;
    final route = ModalRoute.of(dialog!);
    if (route != null && route.isActive) {
      Navigator.of(dialog).removeRoute(route);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    active = state == AppLifecycleState.resumed;
    ++epoch;
    if (!active) closePrivateDialog();
    if (mounted) {
      setState(() {
        snapshot = null;
        busy = false;
        editing = false;
        stale = false;
      });
    }
    if (active) load();
  }

  Future<void> load({bool retry = false}) async {
    if (busy || editing || !active) return;
    final request = ++epoch;
    setState(() => busy = true);
    try {
      if (retry) await sync.flush();
      final value = await sync.read();
      if (current(request)) {
        setState(() {
          snapshot = value;
          error = null;
          stale = false;
        });
      }
    } catch (e) {
      if (current(request)) {
        setState(() {
          if (_goalAuthFailure(e)) snapshot = null;
          stale = snapshot != null;
          error = _goalError(e);
        });
      }
    } finally {
      if (current(request)) setState(() => busy = false);
    }
  }

  Future<void> edit([Map<String, dynamic>? goal]) async {
    if (busy || editing || !active) return;
    final request = ++epoch;
    setState(() => editing = true);
    final result = await showDialog<Map<String, dynamic>>(
        context: context,
        barrierDismissible: false,
        builder: (dialog) {
          privateDialog = dialog;
          return _LearningGoalEditor(
              sync: sync,
              goal: goal,
              onAuthFailure: (e) {
                if (!current(request)) return;
                setState(() {
                  snapshot = null;
                  error = _goalError(e);
                  stale = false;
                });
                closePrivateDialog();
              });
        });
    privateDialog = null;
    if (!mounted || !current(request)) return;
    setState(() => editing = false);
    if (result == null) {
      if (snapshot != null) await load();
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result['queued'] == true
            ? 'هدف روی دستگاه نگه‌داری شد؛ تأیید سرور هنوز دریافت نشده است.'
            : 'هدف در سرور ثبت و تأیید شد.')));
    await load();
  }

  Future<bool> confirm(String title, String description, String action) async =>
      await showDialog<bool>(
          context: context,
          builder: (dialog) => Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                  title: Text(title),
                  content: Text(description),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(dialog, false),
                        child: const Text('انصراف')),
                    FilledButton(
                        onPressed: () => Navigator.pop(dialog, true),
                        child: Text(action))
                  ]))) ==
      true;

  Future<void> change(Map<String, dynamic> goal, {bool archive = false}) async {
    if (busy || editing || !active) return;
    if (archive &&
        !await confirm(
            'بایگانی هدف؟',
            'هدف از فهرست جاری کنار می‌رود؛ سابقه پیشرفت مرتبط نگه‌داری می‌شود.',
            'بایگانی')) {
      return;
    }
    if (!mounted || !active || busy) return;
    final request = ++epoch;
    setState(() => busy = true);
    Object? failed;
    try {
      final result = archive
          ? await sync.archive(goal['id'] as String, goal['version'] as int)
          : await sync.update(goal['id'] as String, goal['version'] as int, {
              'status': goal['status'] == 'completed' ? 'active' : 'completed'
            });
      if (mounted && current(request)) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(result['queued'] == true
                ? 'تغییر ذخیره شد؛ هنوز به تأیید سرور نرسیده است.'
                : 'تغییر در سرور تأیید شد.')));
      }
    } catch (e) {
      failed = e;
    }
    if (!current(request)) return;
    setState(() => busy = false);
    if (failed == null || !_goalAuthFailure(failed)) await load();
    if (failed != null && mounted && active) {
      setState(() {
        if (_goalAuthFailure(failed!)) snapshot = null;
        stale = snapshot != null;
        error = _goalError(failed);
      });
    }
  }

  Future<void> useServer(Map<String, dynamic> goal) async {
    if (busy ||
        !active ||
        !await confirm(
            'استفاده از نسخه سرور؟',
            'تغییر محلی در سابقه بازیابی نگه‌داری می‌شود و نسخه فعلی سرور جای آن را می‌گیرد.',
            'استفاده از سرور')) {
      return;
    }
    if (!mounted || !active || busy) return;
    final request = ++epoch;
    setState(() => busy = true);
    try {
      await sync.useServer(goal['id'] as String);
    } catch (e) {
      if (current(request)) {
        setState(() {
          if (_goalAuthFailure(e)) snapshot = null;
          error = _goalError(e);
          stale = snapshot != null;
        });
      }
      return;
    } finally {
      if (current(request)) setState(() => busy = false);
    }
    if (current(request)) await load();
  }

  @override
  Widget build(BuildContext context) {
    final goals = (snapshot?['items'] as List? ?? []).whereType<Map>().toList();
    final pending = snapshot?['pendingCount'] ??
        goals.where((g) => g['pending_sync'] == true).length;
    final unlisted =
        (snapshot?['unlistedPending'] as List? ?? []).whereType<Map>();
    return Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
            appBar: AppBar(title: const Text('هدف‌های یادگیری')),
            body: ListView(padding: const EdgeInsets.all(16), children: [
              const Text(
                  'هدف‌ها و نتیجه مورد نظر خصوصی‌اند؛ عضویت خانواده اجازه دیدن آن‌ها را ایجاد نمی‌کند.'),
              const Text('تکمیل هدف، گزارش خودت است و اثبات یادگیری نیست.'),
              if (busy) const LinearProgressIndicator(),
              if (error != null) Text(error!),
              if (stale)
                const Text('تازه‌سازی ناموفق؛ این داده ممکن است قدیمی باشد.'),
              if (snapshot?['offline'] == true)
                const Text('آفلاین؛ داده ذخیره‌شده ممکن است قدیمی باشد.'),
              if (snapshot?['fetchedAt'] != null)
                Text('آخرین دریافت سرور: ${snapshot!['fetchedAt']}'),
              if (snapshot != null) Text('تغییر ارسال‌نشده: $pending'),
              FilledButton.icon(
                  onPressed: busy || editing || !active ? null : () => edit(),
                  icon: const Icon(Icons.add),
                  label: const Text('هدف جدید')),
              OutlinedButton(
                  onPressed: busy || editing || !active
                      ? null
                      : () => load(retry: true),
                  child: const Text('همگام‌سازی و تازه‌سازی')),
              if (!busy && snapshot != null && goals.isEmpty)
                const Text('هنوز هدف جاری ثبت نشده است.'),
              ...unlisted.map((row) => ListTile(
                  title: const Text('تغییر معلق برای هدف خارج از فهرست جاری'),
                  subtitle: const Text(
                      'درخواست محلی حفظ شده است؛ بازیابی نسخه سرور به انتخاب شما نیاز دارد.'),
                  trailing: TextButton(
                      onPressed: busy
                          ? null
                          : () => useServer(Map<String, dynamic>.from(row)),
                      child: const Text('بررسی نسخه سرور')))),
              ...goals.map((raw) {
                final goal = Map<String, dynamic>.from(raw);
                final blocked =
                    busy || !active || stale || goal['pending_sync'] == true;
                return Card(
                    child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(goal['title']?.toString() ?? '',
                                  style:
                                      Theme.of(context).textTheme.titleMedium),
                              if (goal['target'] != null)
                                Text(goal['target'].toString()),
                              Text(goal['status'] == 'completed'
                                  ? 'تکمیل طبق گزارش من'
                                  : 'هدف فعال'),
                              if (goal['pending_sync'] == true)
                                Text(goal['pending_archive'] == true
                                    ? 'بایگانی در انتظار تأیید سرور'
                                    : 'تغییر در انتظار تأیید سرور'),
                              if (goal['updated_at'] != null &&
                                  goal['pending_sync'] != true)
                                Text('آخرین ثبت سرور: ${goal['updated_at']}'),
                              if (goal['queueStatus'] == 'conflict')
                                TextButton(
                                    onPressed:
                                        busy ? null : () => useServer(goal),
                                    child: const Text('حل تعارض با نسخه سرور')),
                              Wrap(spacing: 8, children: [
                                TextButton(
                                    onPressed: blocked
                                        ? null
                                        : () => Navigator.of(context).push(
                                            MaterialPageRoute(
                                                builder: (_) =>
                                                    LearningGoalHistoryPage(
                                                        api: widget.api,
                                                        goalId: goal['id']
                                                            as String))),
                                    child:
                                        const Text('بازتاب و سابقه یادگیری')),
                                TextButton(
                                    onPressed:
                                        blocked ? null : () => edit(goal),
                                    child: const Text('ویرایش')),
                                TextButton(
                                    onPressed:
                                        blocked ? null : () => change(goal),
                                    child: Text(goal['status'] == 'completed'
                                        ? 'فعال‌کردن دوباره'
                                        : 'تکمیل طبق گزارش من')),
                                TextButton(
                                    onPressed: blocked
                                        ? null
                                        : () => change(goal, archive: true),
                                    child: const Text('بایگانی')),
                              ])
                            ])));
              })
            ])));
  }
}

/// The dialog owns its controllers until its route has actually unmounted.
/// Disposing them when showDialog's result resolves is too early during pop.
class _LearningGoalEditor extends StatefulWidget {
  const _LearningGoalEditor(
      {required this.sync, required this.goal, required this.onAuthFailure});
  final LearningGoalSync sync;
  final Map<String, dynamic>? goal;
  final void Function(Object error) onAuthFailure;
  @override
  State<_LearningGoalEditor> createState() => _LearningGoalEditorState();
}

class _LearningGoalEditorState extends State<_LearningGoalEditor> {
  late final TextEditingController title, target;
  bool saving = false;
  String? failure;
  @override
  void initState() {
    super.initState();
    title =
        TextEditingController(text: widget.goal?['title']?.toString() ?? '');
    target =
        TextEditingController(text: widget.goal?['target']?.toString() ?? '');
  }

  @override
  void dispose() {
    title.dispose();
    target.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (saving) return;
    if (title.text.trim().isEmpty) {
      setState(() => failure = 'عنوان هدف را بنویس.');
      return;
    }
    setState(() {
      saving = true;
      failure = null;
    });
    try {
      final goal = widget.goal;
      final result = goal == null
          ? await widget.sync.create(title: title.text, target: target.text)
          : await widget.sync.update(
              goal['id'] as String,
              goal['version'] as int,
              {'title': title.text, 'target': target.text});
      if (mounted) Navigator.pop(context, result);
    } catch (e) {
      if (!mounted) return;
      if (_goalAuthFailure(e)) {
        widget.onAuthFailure(e);
        return;
      }
      setState(() {
        failure = _goalError(e);
        saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !saving,
      child: Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
              title: Text(widget.goal == null ? 'هدف جدید' : 'ویرایش هدف'),
              content: SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                    controller: title,
                    maxLength: 240,
                    enabled: !saving,
                    decoration: const InputDecoration(labelText: 'عنوان هدف')),
                TextField(
                    controller: target,
                    maxLength: 1000,
                    maxLines: 3,
                    enabled: !saving,
                    decoration: const InputDecoration(
                        labelText: 'نتیجه مورد نظر (اختیاری)')),
                if (failure != null) Text(failure!)
              ])),
              actions: [
                TextButton(
                    onPressed: saving ? null : () => Navigator.pop(context),
                    child: const Text('انصراف')),
                FilledButton(
                    onPressed: saving ? null : save,
                    child: Text(saving ? 'در حال ذخیره…' : 'ذخیره'))
              ])));
}

/// Existing owner-only check-in API. These legacy writes are online-only and
/// have no durable idempotency receipt; an unknown result is explicitly reviewed.
String _reflectionError(Object error) {
  if (isOfflineFailure(error)) {
    return 'اتصال برقرار نیست؛ دریافت بازتاب‌ها به سرور نیاز دارد.';
  }
  if (_goalAuthFailure(error)) {
    return 'نشست یا دسترسی معتبر نیست؛ بازتاب‌های خصوصی قبلی از صفحه پاک شدند.';
  }
  if (error is ApiException && error.statusCode == 409) {
    return 'وضعیت بازتاب در سرور تغییر کرده است؛ سابقه را تازه کن.';
  }
  return 'عملیات با پاسخ معتبر سرور تأیید نشد؛ سابقه را تازه کن.';
}

class LearningGoalHistoryPage extends StatefulWidget {
  const LearningGoalHistoryPage(
      {super.key, required this.api, required this.goalId});
  final HttpIdentityApi api;
  final String goalId;
  @override
  State<LearningGoalHistoryPage> createState() =>
      _LearningGoalHistoryPageState();
}

class _LearningGoalHistoryPageState extends State<LearningGoalHistoryPage>
    with WidgetsBindingObserver {
  late final String scope;
  List<Map<String, dynamic>> rows = [];
  String? error;
  String? notice;
  DateTime? received;
  bool loading = false, editing = false, active = true;
  bool archivedGoal = true, uncertain = false;
  int epoch = 0;
  BuildContext? editorContext;
  static final uuid = RegExp(r'^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$',
      caseSensitive: false);
  bool current(int request) => mounted && active && epoch == request;
  @override
  void initState() {
    super.initState();
    scope = widget.api.cacheNamespace ?? '';
    WidgetsBinding.instance.addObserver(this);
    load();
  }

  @override
  void dispose() {
    ++epoch;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void closeEditor() {
    final dialog = editorContext;
    editorContext = null;
    if (dialog?.mounted != true) return;
    final route = ModalRoute.of(dialog!);
    if (route != null && route.isActive) {
      Navigator.of(dialog).removeRoute(route);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    active = state == AppLifecycleState.resumed;
    ++epoch;
    if (!active) closeEditor();
    if (mounted) {
      setState(() {
        rows = [];
        received = null;
        loading = false;
        editing = false;
      });
    }
    if (active) load();
  }

  void checkScope() {
    if (scope.isEmpty || scope != widget.api.cacheNamespace) {
      throw const ApiException(401, 'cache_scope_closed');
    }
  }

  Future<Map<String, dynamic>> request(String method, String path,
      {Map<String, dynamic>? body}) async {
    checkScope();
    final value = await widget.api.requestJson(method, path, body: body);
    checkScope();
    return value;
  }

  bool timestamp(dynamic value) =>
      value is String &&
      RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(value) &&
      DateTime.tryParse(value) != null;
  Map<String, dynamic> validateRow(Map value) {
    if (value['id'] is! String ||
        !uuid.hasMatch(value['id'] as String) ||
        value['owner_user_id'] != widget.api.currentUserId ||
        (value['learning_goal_id'] != null &&
            (value['learning_goal_id'] is! String ||
                !uuid.hasMatch(value['learning_goal_id'] as String))) ||
        ![1, 2, 3, 4, 5].contains(value['confidence']) ||
        ![1, 2, 3, 4, 5].contains(value['difficulty']) ||
        (value['note'] != null &&
            (value['note'] is! String ||
                (value['note'] as String).length > 2000)) ||
        value['source'] != 'self_reported' ||
        value['isEvidenceOfStudy'] != false ||
        !timestamp(value['occurred_at']) ||
        !timestamp(value['created_at']) ||
        !timestamp(value['updated_at']) ||
        (value['archived_at'] != null && !timestamp(value['archived_at']))) {
      throw const ApiException(502, 'invalid_learning_checkin');
    }
    return {
      'id': value['id'],
      'learning_goal_id': value['learning_goal_id'],
      'confidence': value['confidence'],
      'difficulty': value['difficulty'],
      'note': value['note'],
      'occurred_at': value['occurred_at'],
      'updated_at': value['updated_at'],
      'archived_at': value['archived_at'],
    };
  }

  Future<void> load() async {
    if (!active || editing) return;
    final requestId = ++epoch;
    setState(() {
      rows = [];
      received = null;
      error = null;
      loading = true;
      archivedGoal = true;
    });
    try {
      if (!uuid.hasMatch(widget.goalId)) {
        throw const ApiException(400, 'invalid_goal_input');
      }
      final goal = await request('GET', '/v1/learning/goals/${widget.goalId}');
      if (goal['id'] != widget.goalId ||
          goal['owner_user_id'] != widget.api.currentUserId ||
          !['active', 'completed', 'archived'].contains(goal['status'])) {
        throw const ApiException(502, 'invalid_learning_goal');
      }
      final result = await request('GET', '/v1/learning/checkins');
      if (result['items'] is! List) {
        throw const ApiException(502, 'invalid_learning_checkins');
      }
      final values = <Map<String, dynamic>>[];
      final ids = <String>{};
      for (final raw in result['items'] as List) {
        if (raw is! Map) {
          throw const ApiException(502, 'invalid_learning_checkins');
        }
        final row = validateRow(Map<String, dynamic>.from(raw));
        if (!ids.add(row['id'] as String) || row['archived_at'] != null) {
          throw const ApiException(502, 'invalid_learning_checkins');
        }
        if (row['learning_goal_id'] == widget.goalId) values.add(row);
      }
      if (!current(requestId)) return;
      setState(() {
        rows = values;
        received = DateTime.now();
        archivedGoal = goal['status'] == 'archived';
      });
    } catch (e) {
      if (current(requestId)) setState(() => error = _reflectionError(e));
    } finally {
      if (current(requestId)) setState(() => loading = false);
    }
  }

  Future<void> edit([Map<String, dynamic>? row]) async {
    if (!active ||
        loading ||
        editing ||
        uncertain ||
        (row == null && archivedGoal)) {
      return;
    }
    final requestId = ++epoch;
    setState(() => editing = true);
    final result = await showDialog<Map<String, dynamic>>(
        context: context,
        barrierDismissible: false,
        builder: (dialog) {
          editorContext = dialog;
          return _LearningCheckinEditor(
              row: row,
              save: (body) async {
                final value = await request(row == null ? 'POST' : 'PATCH',
                    '/v1/learning/checkins${row == null ? '' : '/${row['id']}'}',
                    body: {
                      if (row == null) 'learningGoalId': widget.goalId,
                      ...body,
                    });
                final confirmed = validateRow(value);
                if (confirmed['learning_goal_id'] != widget.goalId ||
                    confirmed['archived_at'] != null ||
                    (row != null && confirmed['id'] != row['id']) ||
                    ['confidence', 'difficulty', 'note']
                        .any((key) => confirmed[key] != body[key])) {
                  throw const ApiException(502, 'invalid_learning_checkin');
                }
              },
              onAuthFailure: (e) {
                if (!current(requestId)) return;
                setState(() {
                  rows = [];
                  received = null;
                  error = _reflectionError(e);
                });
                closeEditor();
              });
        });
    editorContext = null;
    if (!mounted || !current(requestId)) return;
    setState(() => editing = false);
    if (result == null) return;
    if (result['uncertain'] == true) {
      setState(() {
        uncertain = true;
        notice =
            'نتیجه ثبت قبلی ممکن است نامشخص باشد؛ سابقه تازه را بررسی کن. ثبت دوباره خودکار انجام نمی‌شود.';
      });
    } else {
      setState(() => notice =
          'بازتاب در سرور ثبت شد؛ این گزارش شخصی است و اثبات یادگیری نیست.');
    }
    await load();
  }

  Future<void> archive(Map<String, dynamic> row) async {
    if (!active || loading || editing || uncertain) return;
    final accepted = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
                title: const Text('بایگانی بازتاب؟'),
                content: const Text(
                    'این بازتاب از فهرست جاری کنار می‌رود؛ هدف و سایر سوابق حذف نمی‌شوند.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialog, false),
                      child: const Text('انصراف')),
                  FilledButton(
                      onPressed: () => Navigator.pop(dialog, true),
                      child: const Text('تأیید بایگانی'))
                ]));
    if (!mounted || !active || accepted != true) return;
    setState(() {
      loading = true;
      rows = [];
      received = null;
    });
    Object? failure;
    try {
      await request('DELETE', '/v1/learning/checkins/${row['id']}');
    } catch (e) {
      failure = e;
    }
    if (!mounted || !active) return;
    setState(() => loading = false);
    await load();
    if (!mounted || !active) return;
    if (failure != null) {
      setState(() {
        notice =
            'نتیجه بایگانی ممکن است نامشخص باشد؛ سابقه تازه را بررسی کن. تلاش خودکار انجام نمی‌شود.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
          appBar: AppBar(title: const Text('بازتاب یادگیری')),
          body: ListView(padding: const EdgeInsets.all(16), children: [
            const Text(
                'این سابقه و یادداشت‌ها خصوصی‌اند و فقط با حساب صاحب آن دریافت می‌شوند.'),
            const Text(
                'اعتماد و سختی، گزارش شخصی شما هستند؛ اثبات یادگیری یا زمان مطالعه نیستند.'),
            const Text(
                'ثبت و ویرایش این بازتاب‌ها به اتصال سرور نیاز دارد؛ این صفحه ذخیره آفلاین ندارد.'),
            if (loading) const LinearProgressIndicator(),
            if (error != null) Text(error!),
            if (notice != null) Text(notice!),
            if (received != null)
              Text(
                  'آخرین دریافت سابقه: ${received!.toUtc().toIso8601String()}'),
            if (uncertain && received != null)
              OutlinedButton(
                  onPressed: () => setState(() {
                        uncertain = false;
                        notice = null;
                      }),
                  child: const Text('سابقه را بررسی کردم')),
            FilledButton(
                onPressed:
                    loading || editing || !active || archivedGoal || uncertain
                        ? null
                        : () => edit(),
                child: const Text('ثبت بازتاب')),
            OutlinedButton(
                onPressed: editing || !active ? null : load,
                child: const Text('تازه‌سازی سابقه')),
            if (received != null && rows.isEmpty)
              const Text('هنوز بازتاب جاری برای این هدف ثبت نشده است.'),
            ...rows.map((row) => Card(
                child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              'اعتماد به یادگیری: ${row['confidence']} از ۵ · سختی: ${row['difficulty']} از ۵'),
                          if (row['note'] != null) Text(row['note'] as String),
                          Text('زمان ثبت: ${row['occurred_at']}'),
                          Wrap(spacing: 8, children: [
                            TextButton(
                                onPressed: loading || editing || uncertain
                                    ? null
                                    : () => edit(row),
                                child: const Text('ویرایش بازتاب')),
                            TextButton(
                                onPressed: loading || editing || uncertain
                                    ? null
                                    : () => archive(row),
                                child: const Text('بایگانی بازتاب'))
                          ])
                        ]))))
          ])));
}

class _LearningCheckinEditor extends StatefulWidget {
  const _LearningCheckinEditor(
      {required this.row, required this.save, required this.onAuthFailure});
  final Map<String, dynamic>? row;
  final Future<void> Function(Map<String, dynamic> body) save;
  final void Function(Object error) onAuthFailure;
  @override
  State<_LearningCheckinEditor> createState() => _LearningCheckinEditorState();
}

class _LearningCheckinEditorState extends State<_LearningCheckinEditor> {
  late final TextEditingController note;
  late int confidence, difficulty;
  bool saving = false;
  String? error;
  @override
  void initState() {
    super.initState();
    note = TextEditingController(text: widget.row?['note'] as String? ?? '');
    confidence = widget.row?['confidence'] as int? ?? 3;
    difficulty = widget.row?['difficulty'] as int? ?? 3;
  }

  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (saving) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.save({
        'confidence': confidence,
        'difficulty': difficulty,
        'note': note.text.trim().isEmpty ? null : note.text.trim()
      });
      if (mounted) Navigator.pop(context, {'uncertain': false});
    } catch (e) {
      if (!mounted) return;
      if (_goalAuthFailure(e)) {
        widget.onAuthFailure(e);
        return;
      }
      if (isOfflineFailure(e) || (e is ApiException && e.statusCode >= 500)) {
        Navigator.pop(context, {'uncertain': true});
        return;
      }
      setState(() {
        saving = false;
        error = _reflectionError(e);
      });
    }
  }

  Widget scale(String label, int value, void Function(int value) change) =>
      DropdownButtonFormField<int>(
          initialValue: value,
          decoration: InputDecoration(labelText: label),
          items: [
            for (var i = 1; i <= 5; i++)
              DropdownMenuItem(value: i, child: Text('$i از ۵'))
          ],
          onChanged: saving ? null : (value) => setState(() => change(value!)));
  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !saving,
      child: Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
              title: Text(widget.row == null ? 'بازتاب جدید' : 'ویرایش بازتاب'),
              content: SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                scale('اعتماد به یادگیری', confidence, (v) => confidence = v),
                scale('سختی یادگیری', difficulty, (v) => difficulty = v),
                TextField(
                    controller: note,
                    maxLength: 2000,
                    maxLines: 3,
                    enabled: !saving,
                    decoration: const InputDecoration(
                        labelText: 'یادداشت خصوصی (اختیاری)')),
                if (error != null) Text(error!)
              ])),
              actions: [
                TextButton(
                    onPressed: saving ? null : () => Navigator.pop(context),
                    child: const Text('انصراف')),
                FilledButton(
                    onPressed: saving ? null : save,
                    child: Text(saving ? 'در حال ثبت…' : 'ذخیره'))
              ])));
}
