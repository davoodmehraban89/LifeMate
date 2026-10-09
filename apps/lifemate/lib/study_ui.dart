import 'dart:async';
import 'package:flutter/material.dart';
import 'api.dart';
import 'offline_store.dart';
import 'phase3_ui.dart';
import 'study_coordinator.dart';

class StudyHub extends StatelessWidget {
  const StudyHub({super.key, required this.api});
  final IdentityApi api;
  @override
  Widget build(BuildContext context) => Column(children: [
        const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
                'تایمر را از منوی هر تکلیف در برنامه‌ریز باز کن. زمان ثبت‌شده، گزارش شخصی است و اثبات مطالعه نیست.')),
        Expanded(child: PlannerPage(api: api))
      ]);
}

class StudyTimerPage extends StatefulWidget {
  const StudyTimerPage({super.key, required this.api, required this.item});
  final HttpIdentityApi api;
  final Map<String, dynamic> item;
  @override
  State<StudyTimerPage> createState() => _StudyTimerPageState();
}

class _StudyTimerPageState extends State<StudyTimerPage>
    with WidgetsBindingObserver {
  late final StudySync sync;
  List<Map<String, dynamic>> sessions = [];
  bool busy = false, loaded = false, offline = false, pending = false;
  String? error;
  Timer? ticker, poll;
  DateTime? fetchedAt;
  @override
  void initState() {
    super.initState();
    sync = StudySync(widget.api);
    WidgetsBinding.instance.addObserver(this);
    timers();
    load();
  }

  void timers() {
    ticker?.cancel();
    poll?.cancel();
    ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    poll = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!busy) load();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) {
      timers();
      load();
    } else {
      ticker?.cancel();
      poll?.cancel();
    }
  }

  @override
  void dispose() {
    ticker?.cancel();
    poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Map<String, dynamic>? get current {
    final active = sessions
        .where((s) => s['status'] == 'running' || s['status'] == 'paused');
    return active.isEmpty ? null : active.first;
  }

  Future<void> load() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await sync.flush();
      final rows = await widget.api
          .listStudySessions(planItemId: widget.item['id'].toString());
      final store = sync.store;
      final all = await store.readList('study.sessions');
      all.removeWhere((s) => s['planItemId'] == widget.item['id']);
      all.addAll(rows);
      await store.writeList('study.sessions', all);
      final hasPending = (await store.readQueue())
          .any((m) => m['entityType'] == 'study_session');
      if (mounted) {
        setState(() {
          sessions = rows;
          loaded = true;
          offline = false;
          pending = hasPending;
          fetchedAt = DateTime.now();
        });
      }
    } catch (e) {
      if (isOfflineFailure(e)) {
        try {
          final cache = await sync.store.readList('study.sessions');
          final queue = await sync.store.readQueue();
          if (mounted) {
            setState(() {
              sessions = cache
                  .where((s) => s['planItemId'] == widget.item['id'])
                  .toList();
              loaded = true;
              offline = true;
              pending = queue.any((m) => m['entityType'] == 'study_session');
              error = uiErrorText(e);
            });
          }
        } catch (storage) {
          if (mounted) setState(() => error = uiErrorText(storage));
        }
      } else {
        if (mounted) {
          setState(() {
            error = uiErrorText(e);
            offline = true;
          });
        }
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> act(String action) async {
    if (busy || pending) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final outcome = action == 'start'
          ? await sync.start(widget.item['id'].toString())
          : await sync.event(current!, action);
      if (mounted) {
        setState(() {
          pending = outcome.queued;
          if (outcome.item != null) {
            sessions.removeWhere((s) => s['id'] == outcome.item!['id']);
            sessions.add(outcome.item!);
          }
          if (outcome.queued) {
            offline = true;
            error =
                'رویداد روی دستگاه ثبت شد؛ شروع یا پایان در سرور هنوز تأیید نشده است.';
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = uiErrorText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  int elapsed(Map<String, dynamic> session) {
    var seconds = (session['recordedDurationSeconds'] as num? ?? 0).toInt();
    if (session['status'] == 'running' && !offline && !pending) {
      final intervals = session['intervals'] as List? ?? [];
      if (intervals.isNotEmpty) {
        final last = intervals.last as Map;
        if (last['end'] == null) {
          final start = DateTime.tryParse(last['start'].toString());
          if (start != null) {
            final difference =
                DateTime.now().toUtc().difference(start).inSeconds;
            if (difference > 0) seconds += difference;
          }
        }
      }
    }
    return seconds;
  }

  String duration(int seconds) =>
      '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('تایمر مطالعه')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Text(widget.item['title']?.toString() ?? '',
            style: Theme.of(context).textTheme.headlineSmall),
        const Text(
            'زمان ثبت‌شده، گزارش شخصی است و اثبات مطالعه نیست. توقف تایمر تکلیف را انجام‌شده نمی‌کند.'),
        SyncNotice(
            offline: offline, pending: pending ? 1 : 0, syncedAt: fetchedAt),
        if (error != null)
          Card(
              child: Padding(
                  padding: const EdgeInsets.all(12), child: Text(error!))),
        if (!loaded && busy) const LinearProgressIndicator(),
        if (current != null) ...[
          Text(duration(elapsed(current!)),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.displayMedium),
          Text(
              offline
                  ? 'زمان دریافت‌شده قبلی؛ وضعیت فعلی تأیید نشده'
                  : 'نمایش زمان دستگاه؛ مقدار نهایی پس از تأیید سرور ثبت می‌شود.',
              textAlign: TextAlign.center),
          Row(children: [
            Expanded(
                child: FilledButton(
                    onPressed: busy || pending
                        ? null
                        : () => act(current!['status'] == 'running'
                            ? 'pause'
                            : 'resume'),
                    child: Text(
                        current!['status'] == 'running' ? 'مکث' : 'ادامه'))),
            const SizedBox(width: 12),
            Expanded(
                child: OutlinedButton(
                    onPressed: busy || pending ? null : () => act('stop'),
                    child: const Text('پایان')))
          ]),
        ] else
          FilledButton.icon(
              onPressed: !loaded || busy || pending ? null : () => act('start'),
              icon: const Icon(Icons.play_arrow),
              label: const Text('شروع مطالعه')),
        TextButton(
            onPressed: busy ? null : load,
            child: const Text('همگام‌سازی و تلاش دوباره')),
        ...sessions.where((s) => s['status'] == 'completed').map((s) => ListTile(
            title: const Text('جلسه پایان‌یافته'),
            subtitle: Text(
                '${duration(elapsed(s))} ثبت‌شده · ${shortDate(s['endedAt'])}'))),
      ]));
}
