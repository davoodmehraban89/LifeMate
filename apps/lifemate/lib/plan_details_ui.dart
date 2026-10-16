import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'mobile_home.dart';
import 'plan_sync.dart';

/// Displays one selected record. Mutations stay with the caller's PlanSync path.
class PlanDetailsPage extends StatefulWidget {
  const PlanDetailsPage(
      {super.key,
      required this.item,
      this.sharedUpdates,
      required this.canEdit,
      required this.canStudy,
      required this.offline,
      required this.onAction,
      required this.kindLabel,
      required this.dateLabel,
      required this.errorLabel});
  final Map<String, dynamic> item;
  final ValueListenable<Map<String, dynamic>?>? sharedUpdates;
  final bool canEdit, canStudy, offline;
  final Future<MutationOutcome?> Function(Map<String, dynamic>, String)
      onAction;
  final String Function(String) kindLabel;
  final String Function(dynamic) dateLabel;
  final String Function(Object) errorLabel;
  @override
  State<PlanDetailsPage> createState() => _PlanDetailsPageState();
}

class _PlanDetailsPageState extends State<PlanDetailsPage>
    with WidgetsBindingObserver {
  late Map<String, dynamic> item = Map.of(widget.item);
  bool busy = false, acknowledged = false;
  String? error, pendingAction;
  bool snapshotInvalid = false, active = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.sharedUpdates?.addListener(sharedChanged);
  }

  void sharedChanged() {
    if (!mounted || !active) return;
    final latest = widget.sharedUpdates?.value;
    setState(() {
      snapshotInvalid = latest == null;
      item = latest == null ? {} : Map.of(latest);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    active = state == AppLifecycleState.resumed;
    if (!widget.canEdit && !active && mounted) {
      setState(() {
        snapshotInvalid = true;
        item = {};
      });
    }
  }

  @override
  void dispose() {
    widget.sharedUpdates?.removeListener(sharedChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> act(String action) async {
    if (busy) return;
    setState(() {
      busy = true;
      pendingAction = action;
      error = null;
    });
    try {
      final outcome = await widget.onAction(item, action);
      if (!mounted || outcome == null) return;
      if (action == 'archive') {
        Navigator.pop(context);
        return;
      }
      setState(() {
        item = Map.of(outcome.item ?? item);
        item['pending_sync'] = outcome.queued;
        acknowledged = !outcome.queued;
      });
    } catch (failure) {
      if (mounted) {
        setState(() {
          error = widget.errorLabel(failure);
          if (action == 'study') {
            snapshotInvalid = true;
            item = {};
          }
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (snapshotInvalid) {
      return Scaffold(
          appBar: AppBar(title: const Text('وضعیت کار')),
          body: Center(
              child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Text(
                        'اطلاعات تازه در دسترس نیست. برای بررسی وضعیت و دسترسی، به فهرست برنامه برگرد.'),
                    if (error != null) Text(error!),
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('بازگشت به برنامه')),
                  ]))));
    }
    final pending = item['pending_sync'] == true;
    final status = item['status']?.toString() ?? 'planned';
    final stateLabel = switch (status) {
      'completed' => 'انجام‌شده',
      'in_progress' => 'در حال انجام',
      'cancelled' => 'بایگانی‌شده',
      _ => 'برنامه‌ریزی‌شده',
    };
    final visibility = switch (item['visibility']) {
      'parent_guardian' => 'سرپرستان مجاز',
      'selected_members' => 'اعضای انتخاب‌شده',
      'family' => 'اعضای مجاز خانواده',
      _ => 'فقط من',
    };
    final seconds = num.tryParse((item['planned_duration_seconds'] ??
                item['plannedDurationSeconds'] ??
                0)
            .toString()) ??
        0;
    final minutes = seconds > 0
        ? (seconds / 60).round()
        : (num.tryParse(item['duration_minutes'].toString()) ?? 0);
    return PopScope(
        canPop: !busy,
        child: Scaffold(
            key: const ValueKey('plan-details'),
            backgroundColor: MobileHomeMenu.paper,
            appBar: AppBar(title: const Text('جزئیات تکلیف')),
            body: SafeArea(
                child: ListView(padding: const EdgeInsets.all(20), children: [
              Text(
                  '${widget.kindLabel(item['kind']?.toString() ?? 'task')} · $stateLabel',
                  style: const TextStyle(color: MobileHomeMenu.accent)),
              const SizedBox(height: 12),
              Text(item['title']?.toString() ?? '',
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(color: MobileHomeMenu.ink)),
              const SizedBox(height: 20),
              Card(
                  child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('زمان و برنامه'),
                            const SizedBox(height: 8),
                            Text(widget.dateLabel(item['starts_at'] ??
                                item['startsAt'] ??
                                item['due_at'] ??
                                item['dueAt'])),
                            Text(minutes > 0
                                ? '$minutes دقیقه زمان برنامه‌ریزی‌شده'
                                : 'زمان مطالعه تعیین نشده است'),
                          ]))),
              Card(
                  child: ListTile(
                      leading: const Icon(Icons.shield_outlined),
                      title: const Text('با چه کسی به اشتراک گذاشته شده؟'),
                      subtitle: Text(visibility))),
              if (item['notes'] is String &&
                  (item['notes'] as String).isNotEmpty)
                Card(
                    child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(item['notes'] as String))),
              Card(
                  color: pending ? const Color(0xFFFFF1D9) : null,
                  child: ListTile(
                      leading: Icon(
                          pending ? Icons.sync : Icons.cloud_done_outlined),
                      title: Text(pending
                          ? 'در انتظار تأیید سرور'
                          : acknowledged
                              ? 'توسط سرور تأیید شد'
                              : widget.offline
                                  ? 'نسخه ذخیره‌شده؛ داده زنده نیست'
                                  : 'آخرین دریافت از برنامه'),
                      subtitle: const Text(
                          'این صفحه وضعیت رکورد انتخاب‌شده است؛ برای دریافت تغییرات دستگاه دیگر به فهرست برگرد و تازه‌سازی کن.'))),
              if (error != null)
                Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error))),
              if (!widget.canEdit)
                const Text(
                    'فقط مشاهده؛ ویرایش و ثبت زمان برای مالک این کار است.'),
              if (widget.canEdit) ...[
                if (widget.canStudy && !pending && status != 'completed')
                  FilledButton.icon(
                      key: const ValueKey('detail-study'),
                      onPressed: busy ? null : () => act('study'),
                      icon: const Icon(Icons.play_arrow_outlined),
                      label: const Text('شروع مطالعه این تکلیف')),
                if (status != 'completed')
                  FilledButton.icon(
                      key: const ValueKey('detail-complete'),
                      onPressed: busy ? null : () => act('complete'),
                      icon: const Icon(Icons.check),
                      label: const Text('انجام شد')),
                OutlinedButton.icon(
                    key: const ValueKey('detail-edit'),
                    onPressed: busy ? null : () => act('edit'),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('ویرایش تکلیف')),
                TextButton.icon(
                    key: const ValueKey('detail-archive'),
                    onPressed: busy ? null : () => act('archive'),
                    icon: const Icon(Icons.archive_outlined),
                    label: const Text('بایگانی')),
              ],
              if (busy && pendingAction == 'complete')
                const Center(child: CircularProgressIndicator()),
            ]))));
  }
}
