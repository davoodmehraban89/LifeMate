import 'dart:async';
import 'dart:ui' show SemanticsRole;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'api.dart';
import 'aparat_player.dart';
import 'learning_sync.dart';
import 'learning_feedback_ui.dart';
import 'learning_quiz_ui.dart';
import 'offline_store.dart';
import 'plan_sync.dart';
import 'study_ui.dart';

const learningTracks = <String, String>{
  'common': 'عمومی',
  'math': 'ریاضی و فیزیک',
  'experimental': 'علوم تجربی',
  'humanities': 'علوم انسانی',
};
const learningBookVariants = <String, String>{
  'standard': 'نسخه معمول',
  'experimental': 'نسخه آزمایشی',
  'religious_variant': 'نسخه دینی متفاوت',
  'gifted': 'استعدادهای درخشان',
};

bool isLearningAuthFailure(Object error) =>
    error is ApiException &&
    (error.statusCode == 401 || error.statusCode == 403);

String learningError(Object error) {
  if (isOfflineFailure(error)) return 'اتصال برقرار نیست؛ دوباره تلاش کن.';
  if (error is ApiException) {
    if (error.statusCode == 401 || error.statusCode == 403) {
      return 'نشست معتبر لازم است؛ دوباره وارد حساب شو.';
    }
    if (error.statusCode == 409) {
      return 'این درس یک تغییر معلق یا تعارض دارد؛ ابتدا وضعیت همگام‌سازی را بررسی کن.';
    }
  }
  return 'عملیات تأیید نشد؛ داده را بررسی و دوباره تلاش کن.';
}

/// School is a selectable life context, never a role or permission grant.
class EducationLibraryPage extends StatefulWidget {
  const EducationLibraryPage({super.key, required this.api});
  final IdentityApi api;
  @override
  State<EducationLibraryPage> createState() => _EducationLibraryPageState();
}

class _EducationLibraryPageState extends State<EducationLibraryPage> {
  Map<String, dynamic>? library;
  String? error;
  String search = '';
  bool busy = false, offline = false;
  HttpIdentityApi? get api =>
      widget.api is HttpIdentityApi ? widget.api as HttpIdentityApi : null;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (api == null || busy) return;
    setState(() => busy = true);
    try {
      final value = await api!.requestJson('GET', '/v1/education/library');
      await OfflineStore.forApi(api!).writeList('education_library', [value]);
      if (mounted) {
        setState(() {
          library = value;
          error = null;
          offline = false;
        });
      }
    } catch (e) {
      if (isLearningAuthFailure(e) && mounted) {
        setState(() {
          library = null;
          offline = false;
        });
      }
      if (isOfflineFailure(e)) {
        try {
          final cached =
              await OfflineStore.forApi(api!).readList('education_library');
          if (mounted && cached.isNotEmpty) {
            setState(() {
              library = cached.single;
              offline = true;
            });
          }
        } catch (storageError) {
          if (mounted) setState(() => error = learningError(storageError));
          return;
        }
      }
      if (mounted) setState(() => error = learningError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> editEducation() async {
    if (api == null) return;
    final education = library?['education'];
    final saved = await showDialog<bool>(
        context: context,
        builder: (_) => _EducationDialog(
            api: api!,
            education: education is Map
                ? Map<String, dynamic>.from(education)
                : null));
    if (saved == true) await load();
  }

  @override
  Widget build(BuildContext context) {
    if (api == null) {
      return const Center(
          child: Text('کتابخانه آموزشی به حساب و API واقعی نیاز دارد.'));
    }
    final education = library?['education'];
    final courses = (library?['courses'] as List? ?? [])
        .whereType<Map>()
        .where((course) =>
            search.isEmpty ||
            '${course['titleFa']} ${course['bookCode']}'.contains(search))
        .toList();
    return ListView(padding: const EdgeInsets.all(16), children: [
      Card(
          child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('مدرسه من',
                        style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 8),
                    Text(education is Map
                        ? 'پایه ${education['nationalGrade']} · ${learningTracks[education['trackCode']] ?? 'رشته تعیین نشده'} · ${education['schoolYear'] ?? ''}'
                        : 'پایه تحصیلی را انتخاب کن تا کتاب‌های خودت نمایش داده شود.'),
                    const Text(
                        'از هر درس می‌توانی شروع کنی؛ تغییر پایه، برنامه و پیشرفت قبلی را پاک نمی‌کند.'),
                    TextButton.icon(
                        onPressed: busy ? null : editEducation,
                        icon: const Icon(Icons.school_outlined),
                        label: const Text('انتخاب پایه و رشته')),
                  ]))),
      if (busy) const LinearProgressIndicator(),
      if (error != null)
        ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(error!),
            trailing:
                TextButton(onPressed: load, child: const Text('تازه‌سازی'))),
      if (offline)
        const Text('فهرست ذخیره‌شده؛ اتصال و تازگی داده تأیید نشده است.'),
      if (library?['fetchedAt'] != null)
        Text('آخرین دریافت: ${library!['fetchedAt']}'),
      TextField(
          decoration: const InputDecoration(
              labelText: 'جستجوی کتاب', prefixIcon: Icon(Icons.search)),
          onChanged: (value) => setState(() => search = value.trim())),
      TextButton.icon(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => LearningFeedbackPage(api: api!))),
          icon: const Icon(Icons.feedback_outlined),
          label: const Text('بازخورد یا پیشنهاد آموزش')),
      const SizedBox(height: 12),
      if (!busy && courses.isEmpty)
        const Padding(
            padding: EdgeInsets.all(16),
            child: Text('برای این انتخاب، آموزش ثبت‌شده‌ای پیدا نشد.')),
      ...courses.map((course) => Card(
          child: ListTile(
              leading: const Icon(Icons.menu_book_outlined),
              title: Text(course['titleFa']?.toString() ?? 'کتاب'),
              subtitle: Text(
                  '${course['unitCount'] ?? 0} بخش فهرست‌شده · ${course['videoUnitCount'] ?? 0} بخش دارای ویدیو\n'
                  '${course['schoolYear'] ?? 'سال نسخه نامشخص'} · ${learningBookVariants[course['variant']] ?? 'نسخه نیازمند بررسی'}\n'
                  '${(course['unitCount'] ?? 0) == 0 ? 'آموزش این کتاب هنوز گردآوری نشده است.' : 'این شمارش، کامل‌بودن دوره یا کیفیت تدریس را تأیید نمی‌کند.'}'),
              isThreeLine: true,
              trailing: const Icon(Icons.chevron_left),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => LearningCoursePage(
                      api: api!, courseId: course['id'].toString())))))),
      const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Text(
              'منابع پژوهش فعلی از آپارات‌اند؛ تا بازبینی کامل تدریس و تطبیق با کتاب، پخش آموزشی منتشر نمی‌شود. پوشش همه کتاب‌ها و هنرستان‌ها هنوز تکمیل نشده است.')),
    ]);
  }
}

class _EducationDialog extends StatefulWidget {
  const _EducationDialog({required this.api, this.education});
  final HttpIdentityApi api;
  final Map<String, dynamic>? education;
  @override
  State<_EducationDialog> createState() => _EducationDialogState();
}

class _EducationDialogState extends State<_EducationDialog> {
  int? grade;
  String? track;
  late final TextEditingController year;
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    grade = int.tryParse('${widget.education?['nationalGrade']}');
    track = widget.education?['trackCode']?.toString();
    year = TextEditingController(
        text: widget.education?['schoolYear']?.toString() ?? '1405-1406');
  }

  @override
  void dispose() {
    year.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (grade == null || (grade! >= 10 && track == null)) {
      setState(() => error = 'پایه و رشته را انتخاب کن.');
      return;
    }
    setState(() => busy = true);
    try {
      await widget.api.requestJson('PUT', '/v1/me/education', body: {
        'nationalGrade': grade,
        'trackCode': grade! < 10 ? 'common' : track,
        'schoolYear': year.text.trim()
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = learningError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: const Text('پایه تحصیلی من'),
          content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<int>(
                key: const ValueKey('education-grade'),
                initialValue: grade,
                decoration: const InputDecoration(labelText: 'پایه'),
                items: List.generate(
                    12,
                    (index) => DropdownMenuItem(
                        value: index + 1, child: Text('پایه ${index + 1}'))),
                onChanged: busy
                    ? null
                    : (value) => setState(() {
                          grade = value;
                          if (grade! < 10) track = 'common';
                          if (grade! >= 10 && track == 'common') track = null;
                        })),
            if ((grade ?? 0) >= 10)
              DropdownButtonFormField<String>(
                  key: const ValueKey('education-track'),
                  initialValue: track == 'common' ? null : track,
                  decoration: const InputDecoration(labelText: 'رشته'),
                  items: learningTracks.entries
                      .where((entry) => entry.key != 'common')
                      .map((entry) => DropdownMenuItem(
                          value: entry.key, child: Text(entry.value)))
                      .toList(),
                  onChanged:
                      busy ? null : (value) => setState(() => track = value)),
            TextField(
                key: const ValueKey('education-year'),
                controller: year,
                enabled: !busy,
                decoration: const InputDecoration(
                    labelText: 'سال تحصیلی، نمونه 1405-1406')),
            if (error != null) Text(error!),
          ])),
          actions: [
            TextButton(
                onPressed: busy ? null : () => Navigator.pop(context),
                child: const Text('انصراف')),
            FilledButton(
                onPressed: busy ? null : save, child: const Text('ذخیره'))
          ]);
}

class LearningCoursePage extends StatefulWidget {
  const LearningCoursePage(
      {super.key, required this.api, required this.courseId});
  final HttpIdentityApi api;
  final String courseId;
  @override
  State<LearningCoursePage> createState() => _LearningCoursePageState();
}

class _LearningCoursePageState extends State<LearningCoursePage> {
  late final LearningSync sync;
  Map<String, dynamic>? course;
  String? error;
  String search = '';
  bool busy = false;
  Timer? poll;
  @override
  void initState() {
    super.initState();
    sync = LearningSync(widget.api);
    load();
    poll = Timer.periodic(
        const Duration(seconds: 30), (_) => load(syncPending: true));
  }

  @override
  void dispose() {
    poll?.cancel();
    super.dispose();
  }

  Future<void> load({bool syncPending = false}) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      Object? syncError;
      if (syncPending) {
        try {
          await sync.flush();
        } catch (e) {
          syncError = e;
        }
      }
      final value = await sync.readCourse(widget.courseId);
      if (mounted) {
        setState(() {
          course = value;
          error = syncError == null ? null : learningError(syncError);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          if (isLearningAuthFailure(e)) {
            course = null;
          }
          error = learningError(e);
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> openLesson(Map<String, dynamic> unit) async {
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => LearningLessonPage(
            api: widget.api,
            courseId: widget.courseId,
            unitId: unit['id'].toString())));
    if (mounted) await load();
  }

  @override
  Widget build(BuildContext context) {
    final units = (course?['units'] as List? ?? []).whereType<Map>().toList();
    return Scaffold(
        appBar: AppBar(
            title: Text(course?['titleFa']?.toString() ?? 'درس‌ها'),
            actions: [
              IconButton(onPressed: load, icon: const Icon(Icons.refresh))
            ]),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          if (busy) const LinearProgressIndicator(),
          if (error != null) Text(error!),
          if (course?['offline'] == true)
            const Text(
                'آفلاین؛ فهرست ذخیره‌شده و پیشرفت معلق ممکن است قدیمی باشد.'),
          Text('نسخه کتاب: ${course?['schoolYear'] ?? 'نامشخص'}'),
          if (course != null && course!['editionVerification'] != 'verified')
            const Text(
                'نسخه و سال این کتاب هنوز از صفحه معتبر ناشر تأیید نشده است.'),
          if ((course?['reviewCandidateCount'] as num? ?? 0) > 0)
            Text(
                '${course!['reviewCandidateCount']} منبع در انتظار بازبینی کامل؛ این منابع هنوز برای آموزش منتشر نشده‌اند.'),
          if (course?['alignmentNotesFa'] != null)
            Text(course!['alignmentNotesFa'].toString()),
          const Text(
              'می‌توانی از هر بخش شروع کنی. پیشرفت، گزارش خودت است و اثبات یادگیری نیست.'),
          TextField(
              decoration:
                  const InputDecoration(labelText: 'جستجوی درس یا صفحه'),
              onChanged: (value) => setState(() => search = value.trim())),
          if (!busy && units.isEmpty)
            const Text('ویدیوی منطبق برای این کتاب هنوز ثبت نشده است.'),
          ...units
              .where(
                  (u) => search.isEmpty || '${u['titleFa']}'.contains(search))
              .map((u) {
            final progress = u['progress'];
            final pending = progress is Map && progress['pending_sync'] == true;
            return Card(
                child: ListTile(
                    leading: Icon(
                        progress is Map && progress['status'] == 'completed'
                            ? Icons.check_circle_outline
                            : Icons.play_lesson_outlined),
                    title: Text(u['titleFa']?.toString() ?? 'درس'),
                    subtitle: Text(
                        '${(u['videos'] as List? ?? []).length} منبع منتشرشده · ${u['reviewCandidateCount'] ?? 0} نامزد بازبینی${pending ? ' · تغییر ارسال‌نشده' : ''}'),
                    trailing: const Icon(Icons.chevron_left),
                    onTap: () => openLesson(Map<String, dynamic>.from(u))));
          }),
        ]));
  }
}

class LearningLessonPage extends StatefulWidget {
  const LearningLessonPage(
      {super.key,
      required this.api,
      required this.courseId,
      required this.unitId});
  final HttpIdentityApi api;
  final String courseId, unitId;
  @override
  State<LearningLessonPage> createState() => _LearningLessonPageState();
}

class _LearningLessonPageState extends State<LearningLessonPage> {
  late final LearningSync sync;
  Map<String, dynamic>? course, unit;
  String? error;
  bool busy = false;
  int videoIndex = 0;
  @override
  void initState() {
    super.initState();
    sync = LearningSync(widget.api);
    load();
  }

  Future<void> load({bool syncPending = false}) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      Object? syncError;
      if (syncPending) {
        try {
          await sync.flush();
        } catch (e) {
          syncError = e;
        }
      }
      final value = await sync.readCourse(widget.courseId);
      final units = (value['units'] as List).whereType<Map>();
      final found = units.where((u) => u['id'] == widget.unitId).firstOrNull;
      if (found == null) {
        throw const ApiException(404, 'learning_unit_not_found');
      }
      if (mounted) {
        setState(() {
          course = value;
          unit = Map<String, dynamic>.from(found);
          error = syncError == null ? null : learningError(syncError);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          if (isLearningAuthFailure(e)) {
            course = null;
            unit = null;
          }
          error = learningError(e);
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> progress(String status) async {
    if (busy || unit == null) return;
    setState(() => busy = true);
    Object? mutationError;
    try {
      final old = unit!['progress'];
      await sync.setProgress(widget.unitId, status,
          old is Map ? int.tryParse('${old['version']}') ?? 0 : 0);
      if (mounted) setState(() => error = null);
    } catch (e) {
      mutationError = e;
    } finally {
      if (mounted) setState(() => busy = false);
    }
    if (mounted &&
        (mutationError == null || !isLearningAuthFailure(mutationError))) {
      await load();
    }
    if (mounted && mutationError != null) {
      setState(() {
        if (isLearningAuthFailure(mutationError!)) {
          course = null;
          unit = null;
        }
        error = learningError(mutationError);
      });
    }
  }

  Future<void> resolve() async {
    final accept = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
                title: const Text('استفاده از پیشرفت سرور؟'),
                content: const Text(
                    'تغییر معلق در سابقه بازیابی نگه داشته می‌شود و پیشرفت فعلی سرور نمایش داده خواهد شد.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('انصراف')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('استفاده از سرور'))
                ]));
    if (accept != true || !mounted) return;
    try {
      await sync.resolveUsingServer(widget.unitId);
      if (mounted) await load();
    } catch (e) {
      if (mounted) setState(() => error = learningError(e));
    }
  }

  Future<void> plan() async {
    if (busy || unit == null) return;
    final date = await showDatePicker(
        context: context,
        initialDate: DateTime.now(),
        firstDate: DateTime.now().subtract(const Duration(days: 1)),
        lastDate: DateTime.now().add(const Duration(days: 730)));
    if (date == null || !mounted) return;
    final minutes = await showDialog<int>(
        context: context,
        builder: (_) => SimpleDialog(
            title: const Text('زمان برنامه‌ریزی‌شده'),
            children: [15, 30, 45, 60]
                .map((m) => SimpleDialogOption(
                    onPressed: () => Navigator.pop(context, m),
                    child: Text('$m دقیقه')))
                .toList()));
    if (minutes == null || !mounted) return;
    setState(() => busy = true);
    try {
      final outcome = await PlanSync(widget.api).create({
        'kind': 'study_session',
        'title': '${course?['titleFa']} · ${unit!['titleFa']}',
        'learningUnitId': widget.unitId,
        'visibility': 'private',
        'startsAt': DateTime(date.year, date.month, date.day,
                DateTime.now().hour, DateTime.now().minute)
            .toUtc()
            .toIso8601String(),
        'plannedDurationSeconds': minutes * 60,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(outcome.queued
              ? 'برنامه روی دستگاه ثبت شد؛ تأیید سرور هنوز دریافت نشده است.'
              : 'برنامه در سرور ثبت و تأیید شد.')));
      if (!outcome.queued && outcome.item != null) {
        await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) =>
                StudyTimerPage(api: widget.api, item: outcome.item!)));
      }
    } catch (e) {
      if (mounted) setState(() => error = learningError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final videos = (unit?['videos'] as List? ?? []).whereType<Map>().toList();
    final video =
        videos.isEmpty ? null : videos[videoIndex.clamp(0, videos.length - 1)];
    final current = unit?['progress'];
    final pending = current is Map && current['pending_sync'] == true;
    final conflict = current is Map && current['queueStatus'] == 'conflict';
    final progressLines = [
      'پیشرفت شخصی: ${current is Map ? {
            'not_started': 'شروع نشده',
            'in_progress': 'در حال یادگیری',
            'completed': 'تکمیل طبق گزارش من'
          }[current['status']] ?? 'نامشخص' : 'شروع نشده'}',
      if (pending) 'تغییر روی دستگاه ذخیره شده؛ تأیید سرور دریافت نشده است.',
      if (current is Map && current['updatedAt'] != null)
        'آخرین ثبت سرور: ${current['updatedAt']}',
    ];
    final units = (course?['units'] as List? ?? []).whereType<Map>().toList();
    final index = units.indexWhere((u) => u['id'] == widget.unitId);
    void move(int to) =>
        Navigator.of(context).pushReplacement(MaterialPageRoute(
            builder: (_) => LearningLessonPage(
                api: widget.api,
                courseId: widget.courseId,
                unitId: units[to]['id'].toString())));
    return Scaffold(
        appBar:
            AppBar(title: Text(unit?['titleFa']?.toString() ?? 'آموزش درس')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          if (busy) const LinearProgressIndicator(),
          if (error != null) Text(error!),
          Text(course?['titleFa']?.toString() ?? ''),
          if (course?['offline'] == true)
            const Text('آفلاین؛ پخش ویدیو نیاز به اینترنت دارد.'),
          if (video != null && video['freeAccess'] != false) ...[
            AparatPlayer(
                key: ValueKey(video['aparatId']),
                videoHash: video['aparatId'].toString(),
                title: video['titleFa']?.toString() ?? 'آموزش'),
            Text('مدرس: ${video['creatorName'] ?? 'نام تأیید نشده'}'),
            SelectableText(video['creatorUrl']?.toString() ?? ''),
            Text(video['qualityNotesFa']?.toString() ??
                'بازبینی کامل کیفیت تدریس انجام نشده است.'),
            if (video['freeAccess'] == null)
              const Text('رایگان‌بودن و دسترسی فعلی این منبع تأیید نشده است.'),
            const Text(
                'نمایش ویدیو، یادگیری یا تکمیل درس را خودکار ثبت نمی‌کند.'),
          ] else
            const Text(
                'برای این بخش، ویدیوی بازبینی‌شده و منتشرشده هنوز ثبت نشده است.'),
          if (videos.length > 1)
            Wrap(
                spacing: 8,
                children: List.generate(
                    videos.length,
                    (i) => ChoiceChip(
                        label: Text('منبع ${i + 1}'),
                        selected: videoIndex == i,
                        onSelected: (_) => setState(() => videoIndex = i)))),
          const Divider(),
          OutlinedButton.icon(
              onPressed: unit == null
                  ? null
                  : () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => LearningQuizPage(
                          api: widget.api, unitId: widget.unitId))),
              icon: const Icon(Icons.quiz_outlined),
              label: const Text('تمرین فهم درس و مرور')),
          TextButton.icon(
              onPressed: unit == null
                  ? null
                  : () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => LearningFeedbackPage(
                          api: widget.api, unitId: widget.unitId))),
              icon: const Icon(Icons.feedback_outlined),
              label: const Text('گزارش ایراد این درس')),
          Semantics(
              key: const ValueKey('learning-progress-announcement'),
              container: true,
              // Flutter disallows status + liveRegion on the same node.
              // Web status has implicit ARIA live semantics; native uses the flag.
              role: kIsWeb ? SemanticsRole.status : SemanticsRole.none,
              liveRegion: !kIsWeb,
              excludeSemantics: true,
              textDirection: Directionality.of(context),
              label: progressLines.join('\n'),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: progressLines.map((line) => Text(line)).toList())),
          if (conflict)
            TextButton(
                onPressed: busy ? null : resolve,
                child: const Text('حل تعارض با پیشرفت سرور')),
          Wrap(spacing: 8, children: [
            TextButton(
                onPressed: busy || pending || unit == null
                    ? null
                    : () => progress('not_started'),
                child: const Text('شروع نشده')),
            OutlinedButton(
                onPressed: busy || pending || unit == null
                    ? null
                    : () => progress('in_progress'),
                child: const Text('در حال یادگیری')),
            FilledButton(
                onPressed: busy || pending || unit == null
                    ? null
                    : () => progress('completed'),
                child: const Text('طبق گزارش من تکمیل شد')),
          ]),
          FilledButton.tonalIcon(
              onPressed: busy || unit == null ? null : plan,
              icon: const Icon(Icons.event_note_outlined),
              label: const Text('افزودن درس به برنامه و تایمر')),
          const Text(
              'برنامه به‌صورت خصوصی ایجاد می‌شود؛ اشتراک با خانواده از تنظیمات برنامه‌ریز انجام می‌شود.'),
          TextButton(
              onPressed: busy ? null : () => load(syncPending: true),
              child: const Text('همگام‌سازی و تازه‌سازی')),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            TextButton(
                onPressed: index > 0 ? () => move(index - 1) : null,
                child: const Text('بخش قبلی')),
            TextButton(
                onPressed: index >= 0 && index + 1 < units.length
                    ? () => move(index + 1)
                    : null,
                child: const Text('بخش بعدی')),
          ]),
        ]));
  }
}
