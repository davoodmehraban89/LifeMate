import 'dart:async';
import 'package:flutter/material.dart';
import 'api.dart';
import 'phase3_ui.dart';

class ParentFamilyDashboard extends StatefulWidget {
  const ParentFamilyDashboard({super.key, required this.api});
  final IdentityApi api;
  @override
  State<ParentFamilyDashboard> createState() => _ParentFamilyDashboardState();
}

class _ParentFamilyDashboardState extends State<ParentFamilyDashboard>
    with WidgetsBindingObserver {
  late Future<List<Map<String, dynamic>>> data;
  Object? accountScope;
  int loadEpoch = 0;
  bool active = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    accountScope = scopeFor(widget.api);
    data = load();
  }

  Object? scopeFor(IdentityApi api) =>
      api is HttpIdentityApi ? api.cacheNamespace : api;

  @override
  void didUpdateWidget(covariant ParentFamilyDashboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.api != widget.api || accountScope != scopeFor(widget.api)) {
      accountScope = scopeFor(widget.api);
      loadEpoch++;
      data = load();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    setState(() {
      loadEpoch++;
      active = state == AppLifecycleState.resumed;
      if (active) {
        accountScope = scopeFor(widget.api);
        data = load();
      }
    });
  }

  @override
  void dispose() {
    loadEpoch++;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> load() async {
    final api = widget.api;
    final scope = scopeFor(api);
    final epoch = loadEpoch;
    void current() {
      if (scope == null ||
          scope != scopeFor(widget.api) ||
          api != widget.api ||
          epoch != loadEpoch) {
        throw const ApiException(401, 'family_dashboard_scope_changed');
      }
    }

    current();
    final rows = <Map<String, dynamic>>[];
    final families = await api.listFamilies();
    current();
    for (final f in families) {
      if (f['role'] != 'parent_guardian') continue;
      final members = await api.listFamilyMembers(f['id'].toString());
      current();
      for (final child in members) {
        if (child['role'] == 'teen_minor') {
          rows.add({...child, 'familyId': f['id'], 'familyName': f['name']});
        }
      }
    }
    return rows;
  }

  void reload() {
    setState(() {
      loadEpoch++;
      accountScope = scopeFor(widget.api);
      data = load();
    });
  }

  @override
  Widget build(BuildContext context) => !active
      ? const Center(
          child: Text('برای دریافت مجوز و اطلاعات تازه به برنامه برگردید.'))
      : FutureBuilder<List<Map<String, dynamic>>>(
          key: ValueKey(loadEpoch),
          future: data,
          builder: (context, s) {
            if (s.hasError) return LoadError(error: s.error!, retry: reload);
            if (!s.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            return ListView(padding: const EdgeInsets.all(16), children: [
              const Text(
                  'فقط اطلاعاتی که سرور طبق رابطه سرپرستی و اشتراک هر تکلیف مجاز بداند نمایش داده می‌شود.'),
              if (s.data!.isEmpty)
                const EmptyCard(
                    icon: Icons.family_restroom,
                    title: 'فرزند متصل نمایش داده نشد',
                    subtitle:
                        'عضویت خانواده و رابطه سرپرستی را در پروفایل بررسی کن.'),
              ...s.data!.map((child) => Card(
                  child: ListTile(
                      title: Text(child['display_name']?.toString() ?? 'فرزند'),
                      subtitle: Text(child['familyName']?.toString() ?? ''),
                      trailing: const Icon(Icons.chevron_left),
                      onTap: () {
                        if (widget.api is HttpIdentityApi) {
                          Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => LearningReportPage(
                                      api: widget.api as HttpIdentityApi,
                                      familyId: child['familyId'].toString(),
                                      childId: child['user_id'].toString(),
                                      childName:
                                          child['display_name']?.toString() ??
                                              'فرزند')));
                        }
                      }))),
              TextButton(onPressed: reload, child: const Text('تازه‌سازی اعضا'))
            ]);
          });
}

class LearningReportPage extends StatefulWidget {
  const LearningReportPage(
      {super.key,
      required this.api,
      required this.familyId,
      required this.childId,
      required this.childName});
  final HttpIdentityApi api;
  final String familyId, childId, childName;
  @override
  State<LearningReportPage> createState() => _LearningReportPageState();
}

class _LearningReportPageState extends State<LearningReportPage>
    with WidgetsBindingObserver {
  Map<String, dynamic>? report;
  bool busy = false;
  String? error;
  int days = 7;
  Timer? poll;
  int loadEpoch = 0;
  String? reportNamespace;
  String? boundNamespace;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    boundNamespace = widget.api.cacheNamespace;
    startPoll();
    load();
  }

  void startPoll() {
    poll?.cancel();
    poll = Timer.periodic(const Duration(seconds: 15), (_) => load());
  }

  @override
  void didUpdateWidget(covariant LearningReportPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.api != widget.api ||
        oldWidget.familyId != widget.familyId ||
        oldWidget.childId != widget.childId ||
        boundNamespace != widget.api.cacheNamespace) {
      loadEpoch++;
      boundNamespace = widget.api.cacheNamespace;
      report = null;
      reportNamespace = null;
      error = null;
      busy = false;
      load();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) {
      startPoll();
      load();
    } else {
      poll?.cancel();
      loadEpoch++;
      setState(() {
        busy = false;
        report = null;
        reportNamespace = null;
      });
    }
  }

  @override
  void dispose() {
    poll?.cancel();
    loadEpoch++;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> load() async {
    if (busy) return;
    final epoch = ++loadEpoch;
    final namespace = widget.api.cacheNamespace;
    setState(() {
      busy = true;
      report = null;
      reportNamespace = null;
    });
    try {
      final tehranNow =
          DateTime.now().toUtc().add(const Duration(hours: 3, minutes: 30));
      final to =
          DateTime.utc(tehranNow.year, tehranNow.month, tehranNow.day + 1)
              .subtract(const Duration(hours: 3, minutes: 30));
      final from = to.subtract(Duration(days: days));
      final result = await widget.api.getLearningReport(
          widget.familyId, widget.childId,
          from: from, to: to);
      validateReport(result, from: from, to: to);
      if (mounted &&
          epoch == loadEpoch &&
          namespace == widget.api.cacheNamespace) {
        setState(() {
          report = result;
          reportNamespace = namespace;
          error = null;
        });
      }
    } catch (e) {
      if (mounted && epoch == loadEpoch) {
        setState(() {
          error = uiErrorText(e);
          report = null;
          reportNamespace = null;
        });
      }
    } finally {
      if (mounted && epoch == loadEpoch) setState(() => busy = false);
    }
  }

  /// A missing modern period contract is explicitly historical. A present,
  /// malformed period contract must never be interpreted as zero completion.
  void validateReport(Map<String, dynamic> response,
      {required DateTime from, required DateTime to}) {
    Never invalid() => throw const ApiException(502, 'invalid_learning_report');
    bool count(dynamic value) => value is int && value >= 0;
    bool percent(dynamic value) =>
        value is num && value.isFinite && value >= 0 && value <= 100;
    bool instant(dynamic value) =>
        value is String &&
        RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(value) &&
        DateTime.tryParse(value) != null;
    if (response['items'] is! List ||
        response['daily'] is! List ||
        response['subjects'] is! List ||
        response['metrics'] is! Map ||
        !instant(response['asOf']) ||
        (response['familyId'] != null &&
            response['familyId'] != widget.familyId) ||
        (response['childId'] != null &&
            response['childId'] != widget.childId)) {
      invalid();
    }
    if (!response.containsKey('periodMetrics')) return;
    final metrics = response['periodMetrics'];
    if (metrics is! Map ||
        response['periodSubjects'] is! List ||
        response['periodExams'] is! List ||
        !instant(response['from']) ||
        !instant(response['to']) ||
        DateTime.parse(response['from'] as String) != from ||
        DateTime.parse(response['to'] as String) != to ||
        response['timezone'] != 'Asia/Tehran' ||
        response['taskDatePolicy'] != 'due_at_then_starts_at' ||
        response['rangeConvention'] != 'inclusive_from_exclusive_to' ||
        response['completionBasis'] != 'current_status_of_period_tasks') {
      invalid();
    }
    for (final key in const [
      'totalTasks',
      'completedTasks',
      'overdueTasks',
      'plannedDurationSeconds',
      'recordedDurationSeconds',
      'examCount',
      'gradedExamCount',
    ]) {
      if (!count(metrics[key])) invalid();
    }
    if (!percent(metrics['completionPercent']) ||
        metrics['completedTasks'] > metrics['totalTasks'] ||
        metrics['overdueTasks'] > metrics['totalTasks'] ||
        metrics['examCount'] > metrics['totalTasks'] ||
        metrics['gradedExamCount'] > metrics['examCount'] ||
        metrics['completionPercent'] !=
            (metrics['totalTasks'] == 0
                ? 0
                : ((metrics['completedTasks'] as int) *
                        100 /
                        (metrics['totalTasks'] as int))
                    .round()) ||
        (metrics['gradePercent'] != null &&
            !percent(metrics['gradePercent']))) {
      invalid();
    }
    for (final item in response['items'] as List) {
      if (item is! Map ||
          item['taskInRange'] is! bool ||
          !count(item['recordedDurationSeconds'])) {
        invalid();
      }
    }
    for (final subject in response['periodSubjects'] as List) {
      if (subject is! Map ||
          !count(subject['totalTasks']) ||
          !count(subject['completedTasks']) ||
          subject['completedTasks'] > subject['totalTasks'] ||
          !count(subject['recordedDurationSeconds']) ||
          (subject['gradePercent'] != null &&
              !percent(subject['gradePercent']))) {
        invalid();
      }
    }
    for (final exam in response['periodExams'] as List) {
      if (exam is! Map || exam['kind'] != 'exam') invalid();
    }
  }

  String minutes(dynamic seconds) =>
      '${((seconds as num? ?? 0) / 60).round()} دقیقه';
  @override
  Widget build(BuildContext context) {
    final r = reportNamespace == widget.api.cacheNamespace ? report : null;
    final hasPeriod = r?['periodMetrics'] is Map;
    final m =
        (hasPeriod ? (r?['periodMetrics']) : (r?['metrics'])) as Map? ?? {};
    final allTime = r?['allTimeTaskMetrics'] as Map?;
    final items = (r?['items'] as List? ?? []).where((raw) {
      final item = raw as Map;
      return !hasPeriod ||
          item['taskInRange'] == true ||
          (item['recordedDurationSeconds'] as num? ?? 0) > 0;
    }).toList();
    final subjects =
        (hasPeriod ? (r?['periodSubjects']) : (r?['subjects'])) as List? ?? [];
    final exams = r?['periodExams'] as List? ?? [];
    final daily = r?['daily'] as List? ?? [];
    final max = daily.fold<num>(
        1,
        (v, row) => (row['recordedDurationSeconds'] as num? ?? 0) > v
            ? row['recordedDurationSeconds'] as num
            : v);
    final tehranNow =
        DateTime.now().toUtc().add(const Duration(hours: 3, minutes: 30));
    final todayCount = items.where((raw) {
      final i = raw as Map;
      final at =
          DateTime.tryParse((i['dueAt'] ?? i['startsAt'] ?? '').toString())
              ?.toUtc()
              .add(const Duration(hours: 3, minutes: 30));
      return at != null &&
          at.year == tehranNow.year &&
          at.month == tehranNow.month &&
          at.day == tehranNow.day;
    }).length;
    return Scaffold(
        appBar: AppBar(title: Text('گزارش یادگیری · ${widget.childName}')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          const Text(
              'زمان ثبت‌شده، گزارش شخصی است و اثبات مطالعه نیست. تأیید سرپرست فقط در صورت ثبت صریح سرور نمایش داده می‌شود.'),
          SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 7, label: Text('هفتگی')),
                ButtonSegment(value: 30, label: Text('ماهانه'))
              ],
              selected: {
                days
              },
              onSelectionChanged: busy
                  ? null
                  : (v) {
                      setState(() => days = v.first);
                      report = null;
                      reportNamespace = null;
                      error = null;
                      load();
                    }),
          if (busy) const LinearProgressIndicator(),
          if (error != null)
            Card(
                child: ListTile(
                    leading: const Icon(Icons.warning_amber),
                    title: Text(error!),
                    subtitle: Text(report == null
                        ? 'اطلاعات فرزند بدون تأیید مجوز فعلی نمایش داده نمی‌شود.'
                        : 'داده قبلی به‌روز نیست؛ وضعیت زنده تأیید نشده است.'))),
          if (r != null) ...[
            Text(
                'دریافت سرور: ${shortDate(r['asOf'])} · آخرین ثبت: ${shortDate(r['lastSyncAt'])}'),
            if (hasPeriod) ...[
              Text('بازه $days روز اخیر تا پایان امروز (تهران)',
                  style: Theme.of(context).textTheme.titleMedium),
              const Text(
                  'شمارش تکلیف‌ها بر اساس موعد و سپس زمان شروع است؛ تکلیف بی‌تاریخ در شمارش بازه نیست. تکمیل، وضعیت فعلی همین تکلیف‌هاست و به معنی یادگیری تأییدشده نیست.'),
            ] else
              const Text(
                  'سرور آمار تکلیف‌های بازه را ارائه نکرده؛ شمارش تکلیف‌ها مربوط به کل سابقه مجاز است.'),
            Wrap(spacing: 8, children: [
              Chip(label: Text('$todayCount مورد امروز (تهران)')),
              Chip(
                  label: Text(
                      '${m['totalTasks'] ?? 0} تکلیف ${hasPeriod ? 'در بازه' : 'در کل سابقه مجاز'}')),
              Chip(
                  label: Text(
                      '${m['completedTasks'] ?? 0} انجام‌شده ${hasPeriod ? 'در بازه' : 'در کل سابقه مجاز'}')),
              Chip(
                  label: Text(
                      '${m['overdueTasks'] ?? 0} عقب‌افتاده ${hasPeriod ? 'در بازه' : 'در کل سابقه مجاز'}')),
              Chip(
                  label: Text(
                      '${m['completionPercent'] ?? 0}٪ تکمیل ${hasPeriod ? 'تکلیف‌های بازه' : 'کل سابقه مجاز'}'))
            ]),
            if (hasPeriod && allTime != null)
              Text(
                  'کل سابقه مجاز: ${allTime['totalTasks'] ?? 0} تکلیف · ${allTime['completedTasks'] ?? 0} انجام‌شده'),
            Text(
                'زمان برنامه‌ریزی‌شده: ${minutes(m['plannedInRangeDurationSeconds'] ?? m['plannedDurationSeconds'])}'),
            if (!hasPeriod && m['plannedInRangeDurationSeconds'] == null)
              const Text(
                  'زمان برنامه‌ریزی‌شده مربوط به کل سابقه مجاز است؛ زمان بازه جداگانه از سرور دریافت نشده است.'),
            Text('زمان ثبت‌شده: ${minutes(m['recordedDurationSeconds'])}'),
            const Text(
                'زمان ثبت‌شده فقط بخش جلسه‌های مجاز داخل بازه است؛ ممکن است به تکلیفی با موعد خارج از بازه مربوط باشد.'),
            Text('روند زمان ثبت‌شده',
                style: Theme.of(context).textTheme.titleLarge),
            ...daily.map((raw) {
              final row = raw as Map;
              return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    SizedBox(width: 100, child: Text(row['date'].toString())),
                    Expanded(
                        child: LinearProgressIndicator(
                            value:
                                (row['recordedDurationSeconds'] as num? ?? 0) /
                                    max)),
                    const SizedBox(width: 8),
                    Text(minutes(row['recordedDurationSeconds']))
                  ]));
            }),
            Text(hasPeriod ? 'درس‌ها در بازه' : 'درس‌ها در کل سابقه مجاز',
                style: Theme.of(context).textTheme.titleLarge),
            ...subjects.map((raw) {
              final row = raw as Map;
              return ListTile(
                  title: Text(row['subjectName']?.toString() ?? 'بدون درس'),
                  subtitle: Text(
                      '${row['completedTasks']}/${row['totalTasks']} تکمیل ${hasPeriod ? 'تکلیف‌های بازه' : 'کل سابقه'} · ${minutes(row['recordedDurationSeconds'])}${hasPeriod && row['gradePercent'] != null ? '\nنمره وزنی امتحان‌های مجاز: ${row['gradePercent']}٪ (${row['gradedExamCount']} امتحان)' : ''}'));
            }),
            if (hasPeriod) ...[
              Text('امتحان‌های مجاز در بازه',
                  style: Theme.of(context).textTheme.titleLarge),
              const Text(
                  'این نمره‌ها مربوط به امتحان‌های ثبت‌شده مدرسه‌اند. نتیجه کوییز درس در تاریخچه خصوصی یادگیری است و در این گزارش جمع نمی‌شود.'),
              Text(
                  '${m['examCount'] ?? 0} امتحان · ${m['gradedExamCount'] ?? 0} نمره ثبت‌شده${m['gradePercent'] == null ? '' : ' · نمره وزنی ${m['gradePercent']}٪'}'),
              if (exams.isEmpty)
                const Text('امتحان مجازی برای این بازه ثبت نشده است.'),
              ...exams.map((raw) {
                final exam = raw as Map;
                return ListTile(
                    title: Text(exam['title']?.toString() ?? ''),
                    subtitle: Text(
                        'موعد: ${shortDate(exam['scheduledAt'] ?? exam['dueAt'] ?? exam['startsAt'])}\n${exam['gradePoints'] == null ? 'نمره ثبت نشده' : 'نمره ثبت‌شده ${exam['gradePoints']}/${exam['gradeOutOf']}؛ گزارش ثبت‌شده، تأیید مستقل نیست.'}'));
              }),
            ],
            Text(
                hasPeriod
                    ? 'تکلیف‌ها و زمان‌های ثبت‌شده'
                    : 'تکلیف‌ها و امتحان‌ها',
                style: Theme.of(context).textTheme.titleLarge),
            ...items
                .where((raw) =>
                    !hasPeriod ||
                    (raw as Map)['kind'] != 'exam' ||
                    raw['taskInRange'] != true)
                .map((raw) {
              final i = raw as Map;
              final verified = i['activityState'] == 'verified' &&
                  i['activitySource'] == 'guardian_confirmation';
              final state = verified
                  ? 'تأیید صریح سرپرست'
                  : switch (i['activityState']) {
                      'started' => 'شروع ثبت‌شده',
                      'paused' => 'مکث ثبت‌شده',
                      'completed' => 'انجام‌شده به گزارش فرزند',
                      _ => 'برنامه‌ریزی‌شده'
                    };
              return Card(
                  child: ListTile(
                      title: Text(i['title']?.toString() ?? ''),
                      subtitle: Text(
                          '${faKind(i['kind']?.toString() ?? 'task')} · $state\nآخرین ثبت وضعیت: ${shortDate(i['activityAt'])}\nموعد: ${shortDate(i['dueAt'] ?? i['startsAt'])}\nبرنامه ${minutes(i['plannedDurationSeconds'])} · ثبت ${minutes(i['recordedDurationSeconds'])}${hasPeriod && i['taskInRange'] != true ? '\nموعد این تکلیف خارج از بازه است؛ فقط زمان ثبت‌شده در بازه نمایش داده می‌شود.' : ''}${i['gradePoints'] == null ? '' : '\nنمره ${i['gradePoints']}/${i['gradeOutOf']}'}')));
            }),
          ],
          TextButton(
              onPressed: busy ? null : load,
              child: const Text('تازه‌سازی گزارش')),
        ]));
  }
}
