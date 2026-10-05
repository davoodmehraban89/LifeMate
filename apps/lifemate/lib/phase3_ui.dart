import 'dart:math';
import 'package:flutter/material.dart';
import 'api.dart';
import 'offline_store.dart';

String faKind(String kind) {
  switch (kind) {
    case 'assignment': return 'تکلیف';
    case 'exam': return 'امتحان';
    case 'study_session': return 'مطالعه';
    case 'event': return 'رویداد';
    case 'routine': return 'روتین';
    case 'goal': return 'هدف';
    default: return 'کار';
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
  return d.month.toString() + '/' + d.day.toString() + ' · ' +
      d.hour.toString() + ':' + minute;
}

class Phase3HomeContent extends StatelessWidget {
  const Phase3HomeContent({
    super.key,
    required this.api,
    required this.page,
    required this.adultShell,
  });
  final IdentityApi api;
  final String page;
  final bool adultShell;

  @override
  Widget build(BuildContext context) {
    if (page == 'امروز') return TodayPage(api: api);
    if (page == 'برنامه‌ریز' || page == 'برنامه هفتگی' || page == 'تقویم' || page == 'تکالیف و کارها') {
      return PlannerPage(api: api);
    }
    if (page == 'خانواده') return ParentFamilyDashboard(api: api);
    if (page == 'امتحان‌ها و نمرات') return SchoolPage(api: api);
    if (page == 'تمرکز') {
      return const CoreNotice(
        title: 'تمرکز',
        subtitle: 'جلسه مطالعه در برنامه‌ریز فعال است؛ تایمر پیشرفته در فاز بعد اضافه می‌شود.',
      );
    }
    if (page == 'همراه هوشمند' || page == 'راهنما') {
      return const CoreNotice(
        title: 'راهنمای هوشمند',
        subtitle: 'هسته برنامه‌ریزی این فاز مستقل از AI است و راهنمای هوشمند در فاز ۴ فعال می‌شود.',
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

class TodayPage extends StatefulWidget {
  const TodayPage({super.key, required this.api});
  final IdentityApi api;
  @override
  State<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends State<TodayPage> {
  late Future<LoadResult> future;
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
      await OfflineStore.instance.cacheToday(items);
      return LoadResult(items, false);
    } catch (_) {
      return LoadResult(await OfflineStore.instance.readToday(), true);
    }
  }

  Future<void> refresh() async {
    setState(() => future = load());
    await future;
  }

  Future<void> complete(Map<String, dynamic> item) async {
    try {
      await widget.api.updatePlanItem(item['id'].toString(), {'status': 'completed'});
      await refresh();
    } catch (_) {
      await OfflineStore.instance.enqueue({
        'id': DateTime.now().microsecondsSinceEpoch.toString() + '-' + Random().nextInt(99999).toString(),
        'entityType': 'plan_item',
        'entityId': item['id'],
        'operation': 'complete',
        'clientUpdatedAt': DateTime.now().toUtc().toIso8601String(),
        'payload': {'status': 'completed'},
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('آفلاین هستی؛ تغییر برای همگام‌سازی ذخیره شد.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<LoadResult>(
        future: future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final result = snapshot.data!;
          return RefreshIndicator(
            onRefresh: refresh,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (result.offline)
                  const Card(child: ListTile(
                    leading: Icon(Icons.cloud_off_outlined),
                    title: Text('نمایش نسخه آفلاین'),
                  )),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Text('امروز', style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: 6),
                      Text(result.items.length.toString() + ' مورد در برنامه امروز'),
                    ]),
                  ),
                ),
                const SizedBox(height: 8),
                if (result.items.isEmpty)
                  const EmptyCard(
                    icon: Icons.check_circle_outline,
                    title: 'امروز خلوت است',
                    subtitle: 'از برنامه‌ریز یک کار، رویداد یا جلسه مطالعه اضافه کن.',
                  )
                else
                  ...result.items.map((item) => Card(
                    child: ListTile(
                      leading: const Icon(Icons.radio_button_unchecked),
                      title: Text(item['title']?.toString() ?? ''),
                      subtitle: Text(
                        faKind(item['kind']?.toString() ?? 'task') +
                        (shortDate(item['starts_at'] ?? item['due_at']).isEmpty ? '' : ' · ' + shortDate(item['starts_at'] ?? item['due_at'])),
                      ),
                      trailing: IconButton(
                        onPressed: () => complete(item),
                        icon: const Icon(Icons.check_circle_outline),
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
  const PlannerPage({super.key, required this.api});
  final IdentityApi api;
  @override
  State<PlannerPage> createState() => _PlannerPageState();
}

class _PlannerPageState extends State<PlannerPage> {
  late Future<LoadResult> future;
  @override
  void initState() {
    super.initState();
    future = load();
    flushQueue();
  }

  Future<void> flushQueue() async {
    final queue = await OfflineStore.instance.readQueue();
    if (queue.isEmpty) return;
    try {
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
    final from = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 1));
    final to = from.add(const Duration(days: 15));
    try {
      final items = await widget.api.listPlanItems(from: from, to: to);
      await OfflineStore.instance.cachePlanner(items);
      return LoadResult(items, false);
    } catch (_) {
      return LoadResult(await OfflineStore.instance.readPlanner(), true);
    }
  }

  Future<void> reload() async {
    setState(() => future = load());
    await future;
  }

  Future<void> createItem() async {
    final title = TextEditingController();
    final kind = ValueNotifier<String>('task');
    final visibility = ValueNotifier<String>('private');
    final families = await widget.api.listFamilies();
    final familyId = families.isEmpty ? null : families.first['id']?.toString();
    final when = DateTime.now().add(const Duration(hours: 1));

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('مورد جدید'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: title, decoration: const InputDecoration(labelText: 'عنوان')),
          const SizedBox(height: 12),
          ValueListenableBuilder<String>(
            valueListenable: kind,
            builder: (_, value, __) => DropdownButtonFormField<String>(
              initialValue: value,
              decoration: const InputDecoration(labelText: 'نوع'),
              items: const [
                DropdownMenuItem(value: 'task', child: Text('کار')),
                DropdownMenuItem(value: 'event', child: Text('رویداد')),
                DropdownMenuItem(value: 'routine', child: Text('روتین')),
                DropdownMenuItem(value: 'goal', child: Text('هدف')),
                DropdownMenuItem(value: 'study_session', child: Text('جلسه مطالعه')),
              ],
              onChanged: (v) { if (v != null) kind.value = v; },
            ),
          ),
          const SizedBox(height: 12),
          ValueListenableBuilder<String>(
            valueListenable: visibility,
            builder: (_, value, __) => DropdownButtonFormField<String>(
              initialValue: value,
              decoration: const InputDecoration(labelText: 'اشتراک'),
              items: const [
                DropdownMenuItem(value: 'private', child: Text('خصوصی')),
                DropdownMenuItem(value: 'family', child: Text('خانواده')),
                DropdownMenuItem(value: 'parent_guardian', child: Text('والد / سرپرست')),
              ],
              onChanged: (v) { if (v != null) visibility.value = v; },
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('انصراف')),
          FilledButton(
            onPressed: () async {
              if (title.text.trim().isEmpty) return;
              final shared = visibility.value != 'private';
              await widget.api.createPlanItem({
                'kind': kind.value,
                'title': title.text.trim(),
                'startsAt': when.toUtc().toIso8601String(),
                'dueAt': when.add(const Duration(hours: 1)).toUtc().toIso8601String(),
                'visibility': visibility.value,
                if (shared && familyId != null) 'familyId': familyId,
                'reminderMinutesBefore': [15],
              });
              if (dialogContext.mounted) Navigator.pop(dialogContext, true);
            },
            child: const Text('ذخیره'),
          ),
        ],
      ),
    );
    title.dispose();
    kind.dispose();
    visibility.dispose();
    if (saved == true && mounted) await reload();
  }

  Future<void> reschedule(Map<String, dynamic> item) async {
    final base = parseDate(item['due_at'] ?? item['starts_at']) ?? DateTime.now();
    final next = base.add(const Duration(days: 1));
    try {
      await widget.api.updatePlanItem(item['id'].toString(), {
        if (item['starts_at'] != null) 'startsAt': next.toUtc().toIso8601String(),
        if (item['due_at'] != null) 'dueAt': next.toUtc().toIso8601String(),
      });
      await reload();
    } catch (_) {
      await OfflineStore.instance.enqueue({
        'id': DateTime.now().microsecondsSinceEpoch.toString() + '-' + Random().nextInt(99999).toString(),
        'entityType': 'plan_item',
        'entityId': item['id'],
        'operation': 'reschedule',
        'clientUpdatedAt': DateTime.now().toUtc().toIso8601String(),
        'payload': {'dueAt': next.toUtc().toIso8601String()},
      });
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<LoadResult>(
        future: future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final result = snapshot.data!;
          return Scaffold(
            backgroundColor: Colors.transparent,
            floatingActionButton: FloatingActionButton.extended(
              onPressed: createItem,
              icon: const Icon(Icons.add),
              label: const Text('جدید'),
            ),
            body: RefreshIndicator(
              onRefresh: reload,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                children: [
                  if (result.offline)
                    const Card(child: ListTile(
                      leading: Icon(Icons.cloud_off_outlined),
                      title: Text('حالت آفلاین'),
                      subtitle: Text('آخرین برنامه ذخیره‌شده نمایش داده می‌شود.'),
                    )),
                  if (result.items.isEmpty)
                    const EmptyCard(
                      icon: Icons.event_note_outlined,
                      title: 'هنوز برنامه‌ای نداری',
                      subtitle: 'کار، رویداد، روتین، هدف یا جلسه مطالعه اضافه کن.',
                    )
                  else
                    ...result.items.map((item) => Card(
                      child: ListTile(
                        title: Text(item['title']?.toString() ?? ''),
                        subtitle: Text(
                          faKind(item['kind']?.toString() ?? 'task') +
                          (shortDate(item['starts_at'] ?? item['due_at']).isEmpty ? '' : ' · ' + shortDate(item['starts_at'] ?? item['due_at'])),
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (value) async {
                            if (value == 'complete') {
                              await widget.api.updatePlanItem(item['id'].toString(), {'status': 'completed'});
                              await reload();
                            } else if (value == 'tomorrow') {
                              await reschedule(item);
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'complete', child: Text('انجام شد')),
                            PopupMenuItem(value: 'tomorrow', child: Text('انتقال به فردا')),
                          ],
                        ),
                      ),
                    )),
                ],
              ),
            ),
          );
        },
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
      await OfflineStore.instance.cacheSchool([{'userId': userId, 'overview': overview}]);
      return SchoolLoad(userId, overview, false);
    } catch (_) {
      final cached = await OfflineStore.instance.readSchool();
      if (cached.isNotEmpty) {
        return SchoolLoad(
          cached.first['userId']?.toString() ?? userId,
          Map<String, dynamic>.from(cached.first['overview'] as Map? ?? const {}),
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
      if (row['kind'] == 'student') { student = row; break; }
    }
    student ??= await widget.api.createLifeContext(kind: 'student', title: 'مدرسه');
    final now = DateTime.now();
    final year = await widget.api.createAcademicYear({
      'lifeContextId': student['id'],
      'title': 'سال تحصیلی ' + now.year.toString() + '-' + (now.year + 1).toString(),
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
          TextField(controller: title, decoration: const InputDecoration(labelText: 'عنوان')),
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
              onChanged: (v) { if (v != null) selected.value = v; },
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('انصراف')),
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
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final data = snapshot.data!;
          final years = data.overview['years'] as List<dynamic>? ?? const [];
          final subjects = data.overview['subjects'] as List<dynamic>? ?? const [];
          final workload = data.overview['workload'] as List<dynamic>? ?? const [];
          final grades = data.overview['grades'] as List<dynamic>? ?? const [];
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (data.offline)
                const Card(child: ListTile(leading: Icon(Icons.cloud_off_outlined), title: Text('اطلاعات مدرسه از کش نمایش داده می‌شود'))),
              if (years.isEmpty)
                EmptyCard(
                  icon: Icons.school_outlined,
                  title: 'مدرسه را آماده کن',
                  subtitle: 'سال تحصیلی، نیمسال و اولین درس را با شروع سریع بساز.',
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
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Text('مدرسه', style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: 10),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        Chip(label: Text(subjects.length.toString() + ' درس')),
                        Chip(label: Text(workload.length.toString() + ' کار درسی پیش‌رو')),
                        Chip(label: Text(grades.length.toString() + ' نمره')),
                      ]),
                      const SizedBox(height: 12),
                      Row(children: [
                        Expanded(child: FilledButton.icon(
                          onPressed: () => addSchoolItem('assignment'),
                          icon: const Icon(Icons.assignment_add),
                          label: const Text('تکلیف'),
                        )),
                        const SizedBox(width: 8),
                        Expanded(child: OutlinedButton.icon(
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
                  return Card(child: ListTile(
                    leading: const Icon(Icons.menu_book_outlined),
                    title: Text(row['name']?.toString() ?? ''),
                    subtitle: Text(row['teacher_name']?.toString() ?? row['term_title']?.toString() ?? ''),
                  ));
                }),
                const SizedBox(height: 12),
                Text('کارهای درسی پیش‌رو', style: Theme.of(context).textTheme.titleMedium),
                ...workload.map((raw) {
                  final row = Map<String, dynamic>.from(raw as Map);
                  return Card(child: ListTile(
                    title: Text(row['title']?.toString() ?? ''),
                    subtitle: Text(faKind(row['kind']?.toString() ?? '') + ' · ' + shortDate(row['due_at'] ?? row['starts_at'])),
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
  Widget build(BuildContext context) => FutureBuilder<List<Map<String, dynamic>>>(
        future: families,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          if (snapshot.data!.isEmpty) {
            return const EmptyCard(
              icon: Icons.family_restroom,
              title: 'خانواده‌ای متصل نیست',
              subtitle: 'از بخش پروفایل فضای خانواده بساز یا به آن بپیوند.',
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: snapshot.data!.map((family) => FamilyDashboardCard(api: widget.api, family: family)).toList(),
          );
        },
      );
}

class FamilyDashboardCard extends StatefulWidget {
  const FamilyDashboardCard({super.key, required this.api, required this.family});
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

  Future<void> openChild(Map<String, dynamic> child) async {
    final summary = await widget.api.getChildSupportSummary(
      widget.family['id'].toString(),
      child['user_id'].toString(),
    );
    if (!mounted) return;
    final metrics = Map<String, dynamic>.from(summary['metrics'] as Map? ?? const {});
    final upcoming = summary['upcoming'] as List<dynamic>? ?? const [];
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('خلاصه حمایت · ' + (child['display_name']?.toString() ?? 'فرزند')),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Wrap(spacing: 8, runSpacing: 8, children: [
                Chip(label: Text((metrics['overdue'] ?? 0).toString() + ' عقب‌افتاده')),
                Chip(label: Text((metrics['completedLast7Days'] ?? 0).toString() + ' انجام‌شده')),
                Chip(label: Text((metrics['studyMinutesLast7Days'] ?? 0).toString() + ' دقیقه مطالعه')),
                if (metrics['gradePercent'] != null) Chip(label: Text('میانگین ' + metrics['gradePercent'].toString() + '٪')),
              ]),
              const SizedBox(height: 10),
              const Text('موارد پیش‌رو'),
              ...upcoming.take(8).map((raw) {
                final row = Map<String, dynamic>.from(raw as Map);
                return ListTile(
                  dense: true,
                  title: Text(row['title']?.toString() ?? ''),
                  subtitle: Text(faKind(row['kind']?.toString() ?? '') + ' · ' + shortDate(row['due_at'] ?? row['starts_at'])),
                );
              }),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('بستن')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(widget.family['name']?.toString() ?? 'خانواده', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: members,
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const LinearProgressIndicator();
                final children = snapshot.data!.where((row) => row['role'] == 'teen_minor').toList();
                if (children.isEmpty) return const Text('هنوز فرزند/نوجوانی به این خانواده متصل نیست.');
                return Column(
                  children: children.map((child) => ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.school_outlined)),
                    title: Text(child['display_name']?.toString() ?? 'فرزند'),
                    subtitle: const Text('برنامه، تکالیف، امتحان‌ها و پیشرفت مجاز'),
                    trailing: const Icon(Icons.chevron_left),
                    onTap: () => openChild(child),
                  )).toList(),
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
  const LoadResult(this.items, this.offline);
  final List<Map<String, dynamic>> items;
  final bool offline;
}

class SchoolLoad {
  const SchoolLoad(this.userId, this.overview, this.offline);
  final String userId;
  final Map<String, dynamic> overview;
  final bool offline;
}
