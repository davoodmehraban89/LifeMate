import 'dart:async';
import 'package:flutter/material.dart';
import 'api.dart';
import 'phase3_ui.dart';
import 'offline_store.dart';

class ParentFamilyDashboard extends StatefulWidget {
  const ParentFamilyDashboard({super.key, required this.api});
  final IdentityApi api;
  @override
  State<ParentFamilyDashboard> createState() => _ParentFamilyDashboardState();
}

class _ParentFamilyDashboardState extends State<ParentFamilyDashboard> {
  late Future<List<Map<String, dynamic>>> data;
  @override
  void initState() {
    super.initState();
    data = load();
  }

  Future<List<Map<String, dynamic>>> load() async {
    final rows = <Map<String, dynamic>>[];
    for (final f in await widget.api.listFamilies()) {
      if (f['role'] != 'parent_guardian') continue;
      for (final child
          in await widget.api.listFamilyMembers(f['id'].toString())) {
        if (child['role'] == 'teen_minor') {
          rows.add({...child, 'familyId': f['id'], 'familyName': f['name']});
        }
      }
    }
    return rows;
  }

  void reload() {
    setState(() {
      data = load();
    });
  }

  @override
  Widget build(BuildContext context) =>
      FutureBuilder<List<Map<String, dynamic>>>(
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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    startPoll();
    load();
  }

  void startPoll() {
    poll?.cancel();
    poll = Timer.periodic(const Duration(seconds: 15), (_) => load());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) {
      startPoll();
      load();
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

  Future<void> load() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final tehranNow =
          DateTime.now().toUtc().add(const Duration(hours: 3, minutes: 30));
      final to =
          DateTime.utc(tehranNow.year, tehranNow.month, tehranNow.day + 1)
              .subtract(const Duration(hours: 3, minutes: 30));
      final result = await widget.api.getLearningReport(
          widget.familyId, widget.childId,
          from: to.subtract(Duration(days: days)), to: to);
      if (mounted) {
        setState(() {
          report = result;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = uiErrorText(e);
          if (isOfflineFailure(e) ||
              (e is ApiException &&
                  e.statusCode >= 400 &&
                  e.statusCode < 500)) {
            report = null;
          }
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String minutes(dynamic seconds) =>
      '${((seconds as num? ?? 0) / 60).round()} دقیقه';
  @override
  Widget build(BuildContext context) {
    final r = report;
    final m = r?['metrics'] as Map? ?? {};
    final items = r?['items'] as List? ?? [];
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
            Wrap(spacing: 8, children: [
              Chip(label: Text('$todayCount مورد امروز (تهران)')),
              Chip(label: Text('${m['totalTasks'] ?? 0} تکلیف')),
              Chip(label: Text('${m['completedTasks'] ?? 0} انجام‌شده')),
              Chip(label: Text('${m['overdueTasks'] ?? 0} عقب‌افتاده')),
              Chip(label: Text('${m['completionPercent'] ?? 0}٪ تکمیل'))
            ]),
            Text(
                'زمان برنامه‌ریزی‌شده: ${minutes(m['plannedInRangeDurationSeconds'] ?? m['plannedDurationSeconds'])}'),
            Text('زمان ثبت‌شده: ${minutes(m['recordedDurationSeconds'])}'),
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
            Text('درس‌ها', style: Theme.of(context).textTheme.titleLarge),
            ...(r['subjects'] as List? ?? []).map((raw) {
              final row = raw as Map;
              return ListTile(
                  title: Text(row['subjectName']?.toString() ?? 'بدون درس'),
                  subtitle: Text(
                      '${row['completedTasks']}/${row['totalTasks']} تکمیل · ${minutes(row['recordedDurationSeconds'])}'));
            }),
            Text('تکلیف‌ها و امتحان‌ها',
                style: Theme.of(context).textTheme.titleLarge),
            ...items.map((raw) {
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
                          '${faKind(i['kind']?.toString() ?? 'task')} · $state\nآخرین ثبت وضعیت: ${shortDate(i['activityAt'])}\nموعد: ${shortDate(i['dueAt'] ?? i['startsAt'])}\nبرنامه ${minutes(i['plannedDurationSeconds'])} · ثبت ${minutes(i['recordedDurationSeconds'])}${i['gradePoints'] == null ? '' : '\nنمره ${i['gradePoints']}/${i['gradeOutOf']}'}')));
            }),
          ],
          TextButton(
              onPressed: busy ? null : load,
              child: const Text('تازه‌سازی گزارش')),
        ]));
  }
}
