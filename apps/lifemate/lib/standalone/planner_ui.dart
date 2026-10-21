import 'package:flutter/material.dart';

import 'app.dart';
import 'model.dart';
import 'personal_dates.dart';
import 'personal_date_picker.dart';
import 'settings_ui.dart';
import 'store.dart';

DateTime _day(DateTime value) => DateTime(value.year, value.month, value.day);
DateTime _addDays(DateTime value, int count) =>
    DateTime(value.year, value.month, value.day + count);
DateTime _saturday(DateTime value) =>
    _addDays(_day(value), -((value.weekday + 1) % 7));

String _digits(Object value) => value.toString().replaceAllMapped(
    RegExp('[0-9]'), (match) => '۰۱۲۳۴۵۶۷۸۹'[int.parse(match[0]!)]);
String _time(int minute) =>
    '${_digits((minute ~/ 60).toString().padLeft(2, '0'))}:${_digits((minute % 60).toString().padLeft(2, '0'))}';
const _weekdays = <int, String>{
  6: 'شنبه',
  7: 'یکشنبه',
  1: 'دوشنبه',
  2: 'سه‌شنبه',
  3: 'چهارشنبه',
  4: 'پنجشنبه',
  5: 'جمعه',
};
String _date(DateTime value) => personalDateLabel(value);
String _kind(StandalonePlanKind value) => switch (value) {
      StandalonePlanKind.task => 'کار',
      StandalonePlanKind.event => 'رویداد',
      StandalonePlanKind.routine => 'عادت',
    };
String _recurrence(StandaloneRecurrence value) => switch (value) {
      StandaloneRecurrence.once => 'فقط یک بار',
      StandaloneRecurrence.daily => 'هر روز',
      StandaloneRecurrence.everyTwoDays => 'یک روز در میان',
      StandaloneRecurrence.weekly => 'روزهای انتخابی هفته',
    };

class StandalonePlannerShell extends StatefulWidget {
  const StandalonePlannerShell({
    super.key,
    required this.store,
    required this.profile,
    required this.onProfileSaved,
    this.reminderSettingsBuilder,
    this.onPlansChanged,
    this.onBeforePlansChange,
    this.onResumed,
  });
  final StandaloneStore store;
  final StandaloneProfile profile;
  final Future<void> Function() onProfileSaved;
  final StandaloneReminderSettingsBuilder? reminderSettingsBuilder;
  final Future<void> Function(StandaloneStore)? onPlansChanged;
  final Future<void> Function(StandaloneStore)? onBeforePlansChange;
  final Future<void> Function(StandaloneStore)? onResumed;

  @override
  State<StandalonePlannerShell> createState() => _StandalonePlannerShellState();
}

class _StandalonePlannerShellState extends State<StandalonePlannerShell>
    with WidgetsBindingObserver {
  int _tab = 0;
  DateTime _selectedDate = _day(DateTime.now());
  List<StandaloneOccurrence> _today = [];
  List<StandaloneOccurrence> _week = [];
  bool _loading = true;
  bool _failed = false;
  bool _saving = false;
  int _loadNumber = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_saving) _resume();
  }

  Future<void> _resume() async {
    await _load();
    if (!mounted || _saving || _failed) return;
    try {
      await widget.onResumed?.call(widget.store);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'برنامه‌ها باز شدند؛ وضعیت یادآوری را در تنظیمات بررسی کن.')));
      }
    }
  }

  Future<void> _load() async {
    final request = ++_loadNumber;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final today = _day(DateTime.now());
      final weekStart = _saturday(_selectedDate);
      final values = await Future.wait([
        widget.store.occurrences(from: today, through: today),
        widget.store
            .occurrences(from: weekStart, through: _addDays(weekStart, 6)),
      ]);
      if (!mounted || request != _loadNumber) return;
      setState(() {
        _today = values[0].where((item) => !item.archived).toList();
        _week = values[1].where((item) => !item.archived).toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted || request != _loadNumber) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  Future<bool> _write(Future<void> Function() action) async {
    if (_saving) return false;
    setState(() => _saving = true);
    try {
      await widget.onBeforePlansChange?.call(widget.store);
      await action();
    } catch (_) {
      try {
        await widget.onPlansChanged?.call(widget.store);
      } catch (_) {
        // Restoring old reminders is best effort; the durable error stays visible.
      }
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'تغییر ذخیره نشد. فضای خالی گوشی را بررسی کن و دوباره تلاش کن.')));
      }
      return false;
    }
    bool reminderFailed = false;
    try {
      await widget.onPlansChanged?.call(widget.store);
    } catch (_) {
      reminderFailed = true;
    }
    if (!mounted) return true;
    setState(() => _saving = false);
    await _load();
    if (!mounted) return true;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(reminderFailed
            ? 'برنامه ذخیره شد؛ آماده‌سازی یادآوری را در تنظیمات بررسی کن.'
            : 'روی این گوشی ذخیره شد.')));
    return true;
  }

  Future<void> _openEditor() async {
    await Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) => Directionality(
              textDirection: TextDirection.rtl,
              child: _PlanEditor(
                date: _tab == 0 ? _day(DateTime.now()) : _selectedDate,
                onSave: (draft) => _write(() async {
                  await widget.store.createPlan(draft);
                }),
              ),
            )));
  }

  Future<void> _details(StandaloneOccurrence item) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: _OccurrenceDetails(
          initial: item,
          store: widget.store,
          write: _write,
        ),
      ),
    );
  }

  Widget _list(List<StandaloneOccurrence> items) => Column(
        children: items
            .map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _OccurrenceCard(
                    item: item,
                    enabled: !_saving,
                    onOpen: () => _details(item),
                    onTick: () => _write(() async {
                      await widget.store.updateOccurrence(item.id,
                          completed: !item.completed);
                    }),
                  ),
                ))
            .toList(),
      );

  Widget _empty() => Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            Icon(Icons.edit_calendar_outlined,
                size: 44, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            const Text('برای این روز هنوز برنامه‌ای ننوشته‌ای.'),
            const SizedBox(height: 12),
            OutlinedButton.icon(
                onPressed: _saving ? null : _openEditor,
                icon: const Icon(Icons.add),
                label: const Text('یک برنامه اضافه کن')),
          ]),
        ),
      );

  Widget _todayPage() {
    final completed = _today.where((item) => item.completed).length;
    final pending = _today.where((item) => !item.completed).take(4).toList();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('سلام ${widget.profile.displayName}',
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text('${_weekdays[DateTime.now().weekday]}، ${_date(DateTime.now())}'),
        const SizedBox(height: 20),
        Card(
          color: Theme.of(context).colorScheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    _today.isEmpty
                        ? 'امروز را خودت بساز'
                        : 'هر قدم حساب می‌شود',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                Text(_today.isEmpty
                    ? 'با یک کار کوچک شروع کن.'
                    : '${_digits(completed)} از ${_digits(_today.length)} برنامه انجام شده'),
                if (_today.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Semantics(
                    label:
                        '${_digits(completed)} از ${_digits(_today.length)} برنامه انجام شده',
                    child: LinearProgressIndicator(
                      value: completed / _today.length,
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text('قدم‌های امروز', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        if (_today.isEmpty)
          _empty()
        else if (pending.isEmpty)
          const Card(
              child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text(
                      'برنامه‌های امروز انجام شده‌اند. وقت یک نفس تازه است.')))
        else
          _list(pending),
        if (_today.length > pending.length) ...[
          const SizedBox(height: 12),
          TextButton(
              onPressed: () => setState(() {
                    _selectedDate = _day(DateTime.now());
                    _tab = 1;
                    _load();
                  }),
              child: const Text('دیدن همهٔ برنامه‌های امروز در هفته')),
        ],
        const SizedBox(height: 72),
      ],
    );
  }

  Widget _weekPage() {
    final start = _saturday(_selectedDate);
    final items =
        _week.where((item) => _day(item.date) == _selectedDate).toList();
    return ListView(padding: const EdgeInsets.all(20), children: [
      Row(children: [
        Expanded(
            child: Text('هفتهٔ من',
                style: Theme.of(context).textTheme.headlineSmall)),
        TextButton(
            onPressed: () {
              _selectedDate = _day(DateTime.now());
              _load();
            },
            child: const Text('امروز')),
      ]),
      Row(children: [
        IconButton(
            tooltip: 'هفتهٔ قبل',
            onPressed: () {
              _selectedDate = _addDays(_selectedDate, -7);
              _load();
            },
            icon: const Icon(Icons.chevron_right)),
        Expanded(
            child: Text('${_date(start)} تا ${_date(_addDays(start, 6))}',
                textAlign: TextAlign.center)),
        IconButton(
            tooltip: 'هفتهٔ بعد',
            onPressed: () {
              _selectedDate = _addDays(_selectedDate, 7);
              _load();
            },
            icon: const Icon(Icons.chevron_left)),
      ]),
      const Text('تاریخ‌ها شمسی‌اند.', textAlign: TextAlign.center),
      const SizedBox(height: 16),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (int index = 0; index < 7; index++)
          ChoiceChip(
            label: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                  '${_weekdays[_addDays(start, index).weekday]}\n${personalDayLabel(_addDays(start, index))}',
                  textAlign: TextAlign.center),
            ),
            selected: _addDays(start, index) == _selectedDate,
            onSelected: (_) =>
                setState(() => _selectedDate = _addDays(start, index)),
          ),
      ]),
      const SizedBox(height: 24),
      Text('${_weekdays[_selectedDate.weekday]}، ${_date(_selectedDate)}',
          style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 12),
      if (items.isEmpty) _empty() else _list(items),
      const SizedBox(height: 72),
    ]);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          toolbarHeight: 56 * MediaQuery.textScalerOf(context).scale(1),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('برنامهٔ من', style: Theme.of(context).textTheme.titleLarge),
              Text('فقط این گوشی',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: _tab == 2
                ? StandaloneSettings(
                    key: ValueKey(widget.profile.id),
                    store: widget.store,
                    profile: widget.profile,
                    onSaved: widget.onProfileSaved,
                    onBeforeChange: () async =>
                        widget.onBeforePlansChange?.call(widget.store),
                    onAfterChange: () async =>
                        widget.onPlansChanged?.call(widget.store),
                    reminderSettings: widget.reminderSettingsBuilder
                        ?.call(context, widget.store),
                  )
                : _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _failed
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text(
                                        'خواندن برنامه‌ها انجام نشد. داده‌ای پاک نشده است.',
                                        textAlign: TextAlign.center),
                                    const SizedBox(height: 16),
                                    FilledButton(
                                        onPressed: _load,
                                        child: const Text('تلاش دوباره')),
                                  ]),
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: _tab == 0 ? _todayPage() : _weekPage()),
          ),
        ),
        floatingActionButton: _tab == 2 || _loading || _failed
            ? null
            : FloatingActionButton.extended(
                heroTag: null,
                onPressed: _saving ? null : _openEditor,
                icon: const Icon(Icons.add),
                label: const Text('برنامهٔ تازه')),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (value) => setState(() => _tab = value),
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.wb_sunny_outlined), label: 'امروز'),
            NavigationDestination(
                icon: Icon(Icons.calendar_month_outlined), label: 'هفته'),
            NavigationDestination(icon: Icon(Icons.tune), label: 'تنظیمات'),
          ],
        ),
      );
}

class _OccurrenceCard extends StatelessWidget {
  const _OccurrenceCard(
      {required this.item,
      required this.enabled,
      required this.onOpen,
      required this.onTick});
  final StandaloneOccurrence item;
  final bool enabled;
  final VoidCallback onOpen;
  final VoidCallback onTick;

  @override
  Widget build(BuildContext context) => Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 48,
              height: 48,
              child: Checkbox(
                value: item.completed,
                semanticLabel: 'انجام ${item.title}',
                onChanged: enabled ? (_) => onTick() : null,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          decoration: item.completed
                              ? TextDecoration.lineThrough
                              : null)),
                  const SizedBox(height: 4),
                  Text(
                      '${_time(item.startMinute)} تا ${_time(item.endMinute)} · ${_kind(item.kind)}'),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: enabled ? onOpen : null,
                    child: Text(item.completed ? 'جزئیات' : 'شروع'),
                  ),
                ],
              ),
            ),
          ]),
        ),
      );
}

class _OccurrenceDetails extends StatefulWidget {
  const _OccurrenceDetails(
      {required this.initial, required this.store, required this.write});
  final StandaloneOccurrence initial;
  final StandaloneStore store;
  final Future<bool> Function(Future<void> Function()) write;

  @override
  State<_OccurrenceDetails> createState() => _OccurrenceDetailsState();
}

class _OccurrenceDetailsState extends State<_OccurrenceDetails> {
  late StandaloneOccurrence _item = widget.initial;
  bool _busy = false;
  String? _error;

  Future<bool> _change(Future<void> Function() action) async {
    if (_busy) return false;
    setState(() {
      _busy = true;
      _error = null;
    });
    final saved = await widget.write(action);
    if (!mounted) return saved;
    if (saved) {
      try {
        final item = await widget.store.occurrence(_item.id);
        if (!mounted) return true;
        if (item == null || item.archived) {
          Navigator.pop(context);
          return true;
        }
        setState(() => _item = item);
      } catch (_) {
        setState(() => _error =
            'تغییر ذخیره شد؛ بازخوانی جزئیات انجام نشد. این صفحه را ببند و دوباره باز کن.');
      }
    } else {
      setState(() => _error = 'ذخیره انجام نشد. دوباره تلاش کن.');
    }
    if (mounted) setState(() => _busy = false);
    return saved;
  }

  Future<void> _archive() async {
    final scope = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('کدام برنامه بایگانی شود؟'),
              content: const Text(
                  'بایگانی این نوبت، فقط همین روز را از فهرست کنار می‌گذارد. بایگانی کل برنامه، نوبت‌های آینده و یادآوری‌های آن را متوقف می‌کند؛ سابقهٔ انجام‌شده حفظ می‌شود.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('انصراف')),
                TextButton(
                    onPressed: () => Navigator.pop(context, 'one'),
                    child: const Text('فقط این نوبت')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, 'all'),
                    child: const Text('کل برنامه و همهٔ نوبت‌های آینده')),
              ],
            ));
    if (scope == null || !mounted) return;
    final saved = await _change(() async {
      if (scope == 'all') {
        await widget.store.archivePlan(_item.planId);
      } else {
        await widget.store.archiveOccurrence(_item.id);
      }
    });
    if (saved && scope == 'all' && mounted) Navigator.pop(context);
  }

  Future<void> _edit() async {
    await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        isDismissible: false,
        enableDrag: false,
        builder: (_) => _OccurrenceEditor(
            item: _item,
            onSave: (edit) => _change(() async {
                  await widget.store.updateOccurrence(_item.id,
                      title: edit.title,
                      startMinute: edit.start,
                      endMinute: edit.end,
                      reminderMinutes: edit.reminder,
                      removeReminder: edit.reminder == null);
                })));
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
            24, 24, 24, 24 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(_item.title,
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 12),
              Text('${_weekdays[_item.date.weekday]}، ${_date(_item.date)}'),
              Text(
                  '${_time(_item.startMinute)} تا ${_time(_item.endMinute)} · ${_kind(_item.kind)}'),
              const SizedBox(height: 8),
              Text(_item.reminderMinutes == null
                  ? 'برای این نوبت یادآوری انتخاب نشده.'
                  : '${_digits(_item.reminderMinutes!)} دقیقه پیش از شروع؛ وضعیت فعال بودن را در تنظیمات یادآوری بررسی کن.'),
              const SizedBox(height: 20),
              const Text('وقتی کارت تمام شد، انجام آن را ثبت کن.'),
              const SizedBox(height: 16),
              FilledButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _change(() async {
                            await widget.store.updateOccurrence(_item.id,
                                completed: !_item.completed);
                          }),
                  icon: Icon(_item.completed ? Icons.undo : Icons.check),
                  label: Text(_item.completed
                      ? 'برگرداندن به انجام‌نشده'
                      : 'انجام شد')),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                  onPressed: _busy ? null : _edit,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('ویرایش همین نوبت')),
              TextButton.icon(
                  onPressed: _busy ? null : _archive,
                  icon: const Icon(Icons.archive_outlined),
                  label: const Text('بایگانی…')),
              if (_error != null)
                Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              TextButton(
                  onPressed: _busy ? null : () => Navigator.pop(context),
                  child: const Text('بستن')),
            ]),
      );
}

class _OccurrenceEdit {
  const _OccurrenceEdit(this.title, this.start, this.end, this.reminder);
  final String title;
  final int start;
  final int end;
  final int? reminder;
}

class _OccurrenceEditor extends StatefulWidget {
  const _OccurrenceEditor({required this.item, required this.onSave});
  final StandaloneOccurrence item;
  final Future<bool> Function(_OccurrenceEdit) onSave;
  @override
  State<_OccurrenceEditor> createState() => _OccurrenceEditorState();
}

class _OccurrenceEditorState extends State<_OccurrenceEditor> {
  late final TextEditingController _title =
      TextEditingController(text: widget.item.title);
  late int _start = widget.item.startMinute;
  late int _end = widget.item.endMinute;
  late int? _reminder = widget.item.reminderMinutes;
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_busy,
        child: Directionality(
            textDirection: TextDirection.rtl,
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                  24, 24, 24, 24 + MediaQuery.viewInsetsOf(context).bottom),
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('ویرایش همین نوبت',
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 16),
                    TextField(
                        key: const Key('occurrence-title'),
                        controller: _title,
                        enabled: !_busy,
                        maxLength: 120,
                        decoration: const InputDecoration(labelText: 'عنوان')),
                    const SizedBox(height: 12),
                    _TimeFields(
                        start: _start,
                        end: _end,
                        enabled: !_busy,
                        onChanged: (start, end) => setState(() {
                              _start = start;
                              _end = end;
                            })),
                    const SizedBox(height: 16),
                    _ReminderField(
                        value: _reminder,
                        enabled: !_busy,
                        onChanged: (value) =>
                            setState(() => _reminder = value)),
                    if (_error != null)
                      Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(_error!,
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.error))),
                    const SizedBox(height: 20),
                    FilledButton(
                        onPressed: _busy
                            ? null
                            : () async {
                                if (_title.text.trim().isEmpty ||
                                    _end <= _start) {
                                  setState(() => _error =
                                      'عنوان را بنویس و پایان را بعد از شروع انتخاب کن.');
                                  return;
                                }
                                setState(() {
                                  _busy = true;
                                  _error = null;
                                });
                                final saved = await widget.onSave(
                                    _OccurrenceEdit(_title.text.trim(), _start,
                                        _end, _reminder));
                                if (!context.mounted) return;
                                if (saved) {
                                  Navigator.pop(context);
                                } else {
                                  setState(() {
                                    _busy = false;
                                    _error =
                                        'تغییر ذخیره نشد. می‌توانی دوباره تلاش کنی.';
                                  });
                                }
                              },
                        child: Text(
                            _busy ? 'در حال ذخیره…' : 'ثبت تغییر همین نوبت')),
                    TextButton(
                        onPressed: _busy ? null : () => Navigator.pop(context),
                        child: const Text('انصراف')),
                  ]),
            )),
      );
}

class _PlanEditor extends StatefulWidget {
  const _PlanEditor({required this.date, required this.onSave});
  final DateTime date;
  final Future<bool> Function(StandalonePlanDraft) onSave;
  @override
  State<_PlanEditor> createState() => _PlanEditorState();
}

class _PlanEditorState extends State<_PlanEditor> {
  final _title = TextEditingController();
  StandalonePlanKind _kindValue = StandalonePlanKind.task;
  StandaloneRecurrence _repeat = StandaloneRecurrence.once;
  late DateTime _startDate = _day(widget.date);
  DateTime? _until;
  int _start = 9 * 60;
  int _end = 10 * 60;
  int? _reminder;
  final Map<int, (int, int)> _slots = {};
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<DateTime?> _pickDate(DateTime initial) => showPersonalDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100));

  Future<void> _save() async {
    if (_busy) return;
    if (_title.text.trim().isEmpty) {
      setState(() => _error = 'یک عنوان برای برنامه بنویس.');
      return;
    }
    if (_repeat == StandaloneRecurrence.weekly && _slots.isEmpty) {
      setState(() => _error = 'دست‌کم یک روز هفته را انتخاب کن.');
      return;
    }
    if (_end <= _start || _slots.values.any((slot) => slot.$2 <= slot.$1)) {
      setState(
          () => _error = 'ساعت پایان هر روز باید بعد از شروع همان روز باشد.');
      return;
    }
    if (_until != null && _until!.isBefore(_startDate)) {
      setState(() => _error = 'تاریخ پایان تکرار نباید پیش از شروع باشد.');
      return;
    }
    final draft = StandalonePlanDraft(
      title: _title.text.trim(),
      kind: _kindValue,
      recurrence: _repeat,
      startDate: _startDate,
      untilDate: _repeat == StandaloneRecurrence.once ? null : _until,
      startMinute: _start,
      endMinute: _end,
      reminderMinutes: _reminder,
      weeklySlots: _repeat != StandaloneRecurrence.weekly
          ? const []
          : _slots.entries
              .map((entry) => StandaloneWeeklySlot(
                  weekday: entry.key,
                  startMinute: entry.value.$1,
                  endMinute: entry.value.$2))
              .toList(),
    );
    setState(() {
      _busy = true;
      _error = null;
    });
    final saved = await widget.onSave(draft);
    if (!mounted) return;
    if (saved) {
      Navigator.pop(context);
    } else {
      setState(() {
        _busy = false;
        _error = 'برنامه ذخیره نشد. می‌توانی دوباره تلاش کنی.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_busy,
        child: Scaffold(
          appBar: AppBar(title: const Text('برنامهٔ تازه')),
          body: Center(
              child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      TextField(
                          key: const Key('plan-title'),
                          controller: _title,
                          enabled: !_busy,
                          maxLength: 120,
                          decoration: const InputDecoration(
                              labelText: 'عنوان برنامه',
                              hintText: 'یک قدم مشخص و شدنی')),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<StandalonePlanKind>(
                          initialValue: _kindValue,
                          itemHeight: null,
                          isExpanded: true,
                          decoration:
                              const InputDecoration(labelText: 'نوع برنامه'),
                          items: StandalonePlanKind.values
                              .map((value) => DropdownMenuItem(
                                  value: value, child: Text(_kind(value))))
                              .toList(),
                          onChanged: _busy
                              ? null
                              : (value) => setState(() => _kindValue = value!)),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<StandaloneRecurrence>(
                          key: const Key('plan-recurrence'),
                          initialValue: _repeat,
                          itemHeight: null,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'تکرار'),
                          items: StandaloneRecurrence.values
                              .map((value) => DropdownMenuItem(
                                  value: value,
                                  child: Text(_recurrence(value))))
                              .toList(),
                          onChanged: _busy
                              ? null
                              : (value) => setState(() => _repeat = value!)),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                          onPressed: _busy
                              ? null
                              : () async {
                                  final picked = await _pickDate(_startDate);
                                  if (picked != null && mounted) {
                                    setState(() => _startDate = _day(picked));
                                  }
                                },
                          icon: const Icon(Icons.calendar_today_outlined),
                          label: Text(
                              '${_repeat == StandaloneRecurrence.once ? 'تاریخ' : 'شروع تکرار'}: ${_date(_startDate)}')),
                      if (_repeat == StandaloneRecurrence.weekly) ...[
                        const SizedBox(height: 20),
                        const Text('روزهای هفته و ساعت مستقل هر روز'),
                        const SizedBox(height: 12),
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          for (final entry in _weekdays.entries)
                            FilterChip(
                                key: ValueKey('plan-weekday-${entry.key}'),
                                label: Padding(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 8),
                                    child: Text(entry.value)),
                                selected: _slots.containsKey(entry.key),
                                onSelected: _busy
                                    ? null
                                    : (selected) => setState(() {
                                          if (selected) {
                                            _slots[entry.key] = (_start, _end);
                                          } else {
                                            _slots.remove(entry.key);
                                          }
                                        })),
                        ]),
                        for (final weekday
                            in _weekdays.keys.where(_slots.containsKey)) ...[
                          const SizedBox(height: 16),
                          Text(_weekdays[weekday]!),
                          _TimeFields(
                              key: ValueKey('weekly-hours-$weekday'),
                              start: _slots[weekday]!.$1,
                              end: _slots[weekday]!.$2,
                              enabled: !_busy,
                              onChanged: (start, end) => setState(
                                  () => _slots[weekday] = (start, end))),
                        ],
                      ] else ...[
                        const SizedBox(height: 16),
                        _TimeFields(
                            start: _start,
                            end: _end,
                            enabled: !_busy,
                            onChanged: (start, end) => setState(() {
                                  _start = start;
                                  _end = end;
                                })),
                      ],
                      if (_repeat != StandaloneRecurrence.once) ...[
                        const SizedBox(height: 20),
                        SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('تکرار تاریخ پایان داشته باشد'),
                            value: _until != null,
                            onChanged: _busy
                                ? null
                                : (value) => setState(() => _until =
                                    value ? _addDays(_startDate, 30) : null)),
                        if (_until != null)
                          OutlinedButton(
                              onPressed: _busy
                                  ? null
                                  : () async {
                                      final picked = await _pickDate(_until!);
                                      if (picked != null && mounted) {
                                        setState(() => _until = _day(picked));
                                      }
                                    },
                              child: Text('آخرین روز: ${_date(_until!)}')),
                      ],
                      const SizedBox(height: 20),
                      _ReminderField(
                          value: _reminder,
                          enabled: !_busy,
                          onChanged: (value) =>
                              setState(() => _reminder = value)),
                      const SizedBox(height: 8),
                      const Text(
                          'انتخاب زمان یادآوری به‌تنهایی اعلان را فعال نمی‌کند. مجوز و وضعیت آن در تنظیمات یادآوری دیده می‌شود.'),
                      if (_error != null)
                        Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: Text(_error!,
                                style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.error))),
                      const SizedBox(height: 24),
                      FilledButton(
                          onPressed: _busy ? null : _save,
                          child:
                              Text(_busy ? 'در حال ذخیره…' : 'ذخیرهٔ برنامه')),
                      const SizedBox(height: 24),
                    ],
                  ))),
        ),
      );
}

class _TimeFields extends StatelessWidget {
  const _TimeFields(
      {super.key,
      required this.start,
      required this.end,
      required this.onChanged,
      this.enabled = true});
  final int start;
  final int end;
  final bool enabled;
  final void Function(int start, int end) onChanged;

  Future<int?> _pick(BuildContext context, int minute) async {
    final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay(hour: (minute ~/ 60) % 24, minute: minute % 60),
        initialEntryMode: TimePickerEntryMode.input,
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
            child: child!));
    return time == null ? null : time.hour * 60 + time.minute;
  }

  @override
  Widget build(BuildContext context) =>
      Wrap(spacing: 12, runSpacing: 8, children: [
        OutlinedButton(
            onPressed: !enabled
                ? null
                : () async {
                    final value = await _pick(context, start);
                    if (value != null) onChanged(value, end);
                  },
            child: Text('شروع: ${_time(start)}')),
        OutlinedButton(
            onPressed: !enabled
                ? null
                : () async {
                    final value = await _pick(context, end);
                    if (value != null) onChanged(start, value);
                  },
            child: Text('پایان: ${_time(end)}')),
      ]);
}

class _ReminderField extends StatelessWidget {
  const _ReminderField(
      {required this.value, required this.onChanged, this.enabled = true});
  final int? value;
  final ValueChanged<int?> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<int>(
        initialValue: value ?? -1,
        itemHeight: null,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'زمان یادآوری'),
        items: [
          const DropdownMenuItem(value: -1, child: Text('بدون یادآوری')),
          const DropdownMenuItem(value: 0, child: Text('هنگام شروع')),
          for (final minutes in [5, 10, 15, 30])
            DropdownMenuItem(
                value: minutes,
                child: Text('${_digits(minutes)} دقیقه پیش از شروع')),
        ],
        onChanged: !enabled
            ? null
            : (selected) => onChanged(selected == -1 ? null : selected),
      );
}
