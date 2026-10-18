import 'dart:convert';

import 'package:flutter/material.dart';

import 'api.dart';
import 'phase3_ui.dart' show faKind, uiErrorText;
import 'plan_sync.dart' show newMutationId;
import 'planner_series.dart';
import 'sync_changes_ui.dart';

typedef CreatePlannerSeries = Future<PlannerSeriesOutcome>
    Function(Map<String, dynamic> payload, {String? id});

/// Creates private occurrences. Editing one occurrence is handled separately by
/// PlanItemDialog; this form never changes family visibility or permissions.
class PlannerSeriesDialog extends StatefulWidget {
  const PlannerSeriesDialog({
    super.key,
    required this.api,
    this.initialDate,
    this.onCreate,
    this.clock = DateTime.now,
  });

  final HttpIdentityApi api;
  final DateTime? initialDate;
  final CreatePlannerSeries? onCreate;
  final DateTime Function() clock;

  @override
  State<PlannerSeriesDialog> createState() => _PlannerSeriesDialogState();
}

class _TimeSlot {
  const _TimeSlot({
    this.start = const TimeOfDay(hour: 8, minute: 0),
    this.end = const TimeOfDay(hour: 9, minute: 0),
  });
  final TimeOfDay start, end;

  bool get valid => end.hour * 60 + end.minute > start.hour * 60 + start.minute;
  Map<String, dynamic> get payload =>
      {'start': _clock(start), 'end': _clock(end)};
}

String _clock(TimeOfDay time) =>
    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
String _calendarDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

class _PlannerSeriesDialogState extends State<PlannerSeriesDialog> {
  static const weekdays = <int, String>{
    6: 'شنبه',
    7: 'یکشنبه',
    1: 'دوشنبه',
    2: 'سه‌شنبه',
    3: 'چهارشنبه',
    4: 'پنجشنبه',
    5: 'جمعه',
  };
  final title = TextEditingController();
  final id = newMutationId();
  final selected = <int>{};
  final slots = <int, _TimeSlot>{};
  _TimeSlot dailySlot = const _TimeSlot();
  late DateTime startsOn, untilOn;
  String kind = 'routine', frequency = 'weekly';
  int intervalDays = 1, reminderMinutes = -1;
  bool hasEnd = false, busy = false, terminal = false;
  String? error;
  Map<String, dynamic>? frozenPayload;

  bool get editable => !busy && frozenPayload == null;

  // The server accepts ±730 Tehran calendar days. A UTC reference and a one-day
  // margin avoid offering an unsupported boundary near midnight or a time-zone
  // change. This is a UI guard; the API remains authoritative.
  DateTime get referenceDay {
    final now = widget.clock().toUtc();
    return DateTime(now.year, now.month, now.day);
  }

  DateTime get firstDate => referenceDay.subtract(const Duration(days: 729));
  DateTime get lastDate => referenceDay.add(const Duration(days: 729));
  bool supportedDate(DateTime value) =>
      !value.isBefore(firstDate) && !value.isAfter(lastDate);

  @override
  void initState() {
    super.initState();
    final date = widget.initialDate ?? widget.clock();
    startsOn = DateTime(date.year, date.month, date.day);
    untilOn = startsOn.add(const Duration(days: 90));
    selected.add(startsOn.weekday);
    slots[startsOn.weekday] = const _TimeSlot();
  }

  @override
  void dispose() {
    title.dispose();
    super.dispose();
  }

  Future<void> pickDate({required bool end}) async {
    if (!editable) return;
    final selectedDate = end ? untilOn : startsOn;
    final first = firstDate, last = lastDate;
    final initial = selectedDate.isBefore(first)
        ? first
        : selectedDate.isAfter(last)
            ? last
            : selectedDate;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
    );
    if (date != null && mounted && editable) {
      setState(() => end ? untilOn = date : startsOn = date);
    }
  }

  Future<void> pickTime(int? weekday, {required bool end}) async {
    if (!editable) return;
    final slot = weekday == null ? dailySlot : slots[weekday]!;
    final time = await showTimePicker(
      context: context,
      initialTime: end ? slot.end : slot.start,
      initialEntryMode: TimePickerEntryMode.input,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (time == null || !mounted || !editable) return;
    final changed = _TimeSlot(
      start: end ? slot.start : time,
      end: end ? time : slot.end,
    );
    setState(
        () => weekday == null ? dailySlot = changed : slots[weekday] = changed);
  }

  Map<String, dynamic>? payload() {
    if (title.text.trim().isEmpty) {
      error = 'عنوان را وارد کن.';
      return null;
    }
    if (!supportedDate(startsOn)) {
      error = 'تاریخ شروع باید در بازهٔ مجاز دو ساله باشد.';
      return null;
    }
    if (hasEnd && !supportedDate(untilOn)) {
      error = 'تاریخ پایان باید در بازهٔ مجاز دو ساله باشد.';
      return null;
    }
    if (hasEnd && untilOn.isBefore(startsOn)) {
      error = 'تاریخ پایان نباید پیش از تاریخ شروع باشد.';
      return null;
    }
    if (frequency == 'weekly' && selected.isEmpty) {
      error = 'دست‌کم یک روز هفته را انتخاب کن.';
      return null;
    }
    final activeSlots =
        frequency == 'daily' ? [dailySlot] : selected.map((day) => slots[day]!);
    if (activeSlots.any((slot) => !slot.valid)) {
      error = 'پایان هر نوبت باید پس از شروع و در همان روز باشد.';
      return null;
    }
    final sortedDays = selected.toList()..sort();
    return <String, dynamic>{
      'title': title.text.trim(),
      'kind': kind,
      'timezone': 'Asia/Tehran',
      'startsOn': _calendarDate(startsOn),
      if (hasEnd) 'untilOn': _calendarDate(untilOn),
      'frequency': frequency,
      'intervalDays': frequency == 'daily' ? intervalDays : 1,
      'slots': frequency == 'daily'
          ? [dailySlot.payload]
          : [
              for (final day in sortedDays)
                {'weekday': day, ...slots[day]!.payload}
            ],
      'reminderMinutes': reminderMinutes < 0 ? <int>[] : [reminderMinutes],
    };
  }

  Future<void> save() async {
    if (busy || terminal) return;
    final draft = frozenPayload ?? payload();
    if (draft == null) {
      setState(() {});
      return;
    }
    // Freeze both identity and exact body before awaiting durable enqueue/HTTP.
    // An unknown response can mean that the original request already committed.
    frozenPayload ??= jsonDecode(jsonEncode(draft)) as Map<String, dynamic>;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final create = widget.onCreate ?? PlannerSeriesSync(widget.api).create;
      final result = await create(
          jsonDecode(jsonEncode(frozenPayload)) as Map<String, dynamic>,
          id: id);
      if (mounted) Navigator.of(context).pop(result);
    } catch (failure) {
      if (mounted) {
        setState(() {
          terminal = failure is ApiException &&
              [400, 409, 422].contains(failure.statusCode);
          error = uiErrorText(failure);
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void openRecovery() {
    final navigator = Navigator.of(context);
    navigator.pop();
    navigator.push(MaterialPageRoute<void>(
      builder: (_) => SyncChangesPage(api: widget.api),
    ));
  }

  Widget timeSlot(int? weekday) {
    final slot = weekday == null ? dailySlot : slots[weekday]!;
    final prefix = weekday == null ? 'daily' : '$weekday';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(weekday == null ? 'ساعت هر نوبت' : weekdays[weekday]!,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final end in [false, true])
              OutlinedButton(
                key: ValueKey('series-day-$prefix-${end ? 'end' : 'start'}'),
                style:
                    OutlinedButton.styleFrom(minimumSize: const Size(100, 48)),
                onPressed: editable ? () => pickTime(weekday, end: end) : null,
                child: Text(
                    '${end ? 'پایان' : 'شروع'}: ${_clock(end ? slot.end : slot.start)}'),
              ),
          ]),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !busy,
        child: AlertDialog(
          title: const Text('برنامهٔ تکرارشونده',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: DefaultTextStyle.merge(
                style: const TextStyle(fontSize: 14, height: 1.6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                        'این برنامه خصوصی است. هر نوبت تیک و ساعت مستقل دارد؛ تغییر یک نوبت، روزهای دیگر را عوض نمی‌کند.'),
                    const SizedBox(height: 12),
                    TextField(
                      key: const ValueKey('series-title'),
                      controller: title,
                      enabled: editable,
                      maxLength: 200,
                      style: const TextStyle(fontSize: 16),
                      decoration: const InputDecoration(labelText: 'عنوان'),
                    ),
                    DropdownButtonFormField<String>(
                      key: const ValueKey('series-kind'),
                      initialValue: kind,
                      decoration: const InputDecoration(labelText: 'نوع'),
                      items: [
                        for (final value in ['task', 'event', 'routine'])
                          DropdownMenuItem(
                              value: value, child: Text(faKind(value))),
                      ],
                      onChanged: editable
                          ? (value) => setState(() => kind = value ?? kind)
                          : null,
                    ),
                    const SizedBox(height: 12),
                    const Text('زمان‌ها به وقت تهران (Asia/Tehran) هستند.'),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      key: const ValueKey('series-start-date'),
                      style: OutlinedButton.styleFrom(
                          minimumSize: const Size(48, 48)),
                      onPressed: editable ? () => pickDate(end: false) : null,
                      icon: const Icon(Icons.calendar_today_outlined),
                      label: Text('شروع: ${_calendarDate(startsOn)}'),
                    ),
                    CheckboxListTile(
                      key: const ValueKey('series-has-end'),
                      value: hasEnd,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('تاریخ پایان دارد'),
                      onChanged: editable
                          ? (value) => setState(() => hasEnd = value ?? false)
                          : null,
                    ),
                    if (hasEnd)
                      OutlinedButton.icon(
                        key: const ValueKey('series-end-date'),
                        style: OutlinedButton.styleFrom(
                            minimumSize: const Size(48, 48)),
                        onPressed: editable ? () => pickDate(end: true) : null,
                        icon: const Icon(Icons.event_outlined),
                        label: Text('پایان: ${_calendarDate(untilOn)}'),
                      ),
                    DropdownButtonFormField<String>(
                      key: const ValueKey('series-frequency'),
                      initialValue: frequency,
                      decoration: const InputDecoration(labelText: 'تکرار'),
                      items: const [
                        DropdownMenuItem(value: 'weekly', child: Text('هفتگی')),
                        DropdownMenuItem(value: 'daily', child: Text('روزانه')),
                      ],
                      onChanged: editable
                          ? (value) =>
                              setState(() => frequency = value ?? frequency)
                          : null,
                    ),
                    const SizedBox(height: 12),
                    if (frequency == 'daily') ...[
                      DropdownButtonFormField<int>(
                        key: const ValueKey('series-interval'),
                        initialValue: intervalDays,
                        decoration:
                            const InputDecoration(labelText: 'فاصلهٔ روزها'),
                        items: const [
                          DropdownMenuItem(value: 1, child: Text('هر روز')),
                          DropdownMenuItem(
                              value: 2, child: Text('یک روز در میان')),
                        ],
                        onChanged: editable
                            ? (value) =>
                                setState(() => intervalDays = value ?? 1)
                            : null,
                      ),
                      const SizedBox(height: 8),
                      timeSlot(null),
                    ] else ...[
                      const Text('روزهای برنامه را انتخاب کن:'),
                      const SizedBox(height: 8),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        for (final day in weekdays.keys)
                          ConstrainedBox(
                            constraints: const BoxConstraints(
                                minWidth: 48, minHeight: 48),
                            child: FilterChip(
                              key: ValueKey('series-weekday-$day'),
                              label: Text(weekdays[day]!),
                              selected: selected.contains(day),
                              materialTapTargetSize:
                                  MaterialTapTargetSize.padded,
                              onSelected: editable
                                  ? (value) => setState(() {
                                        if (value) {
                                          selected.add(day);
                                          slots.putIfAbsent(
                                              day, () => const _TimeSlot());
                                        } else {
                                          selected.remove(day);
                                        }
                                      })
                                  : null,
                            ),
                          ),
                      ]),
                      const SizedBox(height: 8),
                      for (final day in weekdays.keys)
                        if (selected.contains(day)) timeSlot(day),
                    ],
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      key: const ValueKey('series-reminder'),
                      initialValue: reminderMinutes,
                      decoration:
                          const InputDecoration(labelText: 'یادآوری هر نوبت'),
                      isExpanded: true,
                      items: const [
                        DropdownMenuItem(
                            value: -1, child: Text('بدون یادآوری')),
                        DropdownMenuItem(value: 0, child: Text('هنگام شروع')),
                        DropdownMenuItem(
                            value: 5, child: Text('۵ دقیقه پیش از شروع')),
                        DropdownMenuItem(
                            value: 10, child: Text('۱۰ دقیقه پیش از شروع')),
                        DropdownMenuItem(
                            value: 15, child: Text('۱۵ دقیقه پیش از شروع')),
                      ],
                      onChanged: editable
                          ? (value) => setState(() => reminderMinutes = value!)
                          : null,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                        'برای اعلان روی گوشی، اجازهٔ اعلان و تنظیمات یادآوری دستگاه هم باید فعال باشند. انتخاب ساعت، تضمین نمایش اعلان نیست.'),
                    if (frozenPayload != null) ...[
                      const SizedBox(height: 12),
                      const Text(
                          'درخواست با همان شناسه نگه داشته شد. تا روشن‌شدن نتیجه، جزئیات قابل تغییر نیست؛ شناسهٔ تازه نساز.'),
                    ],
                    if (error != null) ...[
                      const SizedBox(height: 12),
                      Text(error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                    ],
                    if (terminal)
                      TextButton(
                        style: TextButton.styleFrom(
                            minimumSize: const Size(48, 48)),
                        onPressed: busy ? null : openRecovery,
                        child: const Text('بررسی تغییرات در انتظار'),
                      ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: busy ? null : () => Navigator.of(context).pop(),
              child: Text(frozenPayload == null ? 'انصراف' : 'بستن'),
            ),
            FilledButton(
              key: const ValueKey('series-save'),
              style: FilledButton.styleFrom(minimumSize: const Size(96, 48)),
              onPressed: busy || terminal ? null : save,
              child: Text(busy
                  ? 'در حال بررسی…'
                  : frozenPayload == null
                      ? 'ثبت برنامه'
                      : 'تلاش دوباره'),
            ),
          ],
        ),
      );
}
