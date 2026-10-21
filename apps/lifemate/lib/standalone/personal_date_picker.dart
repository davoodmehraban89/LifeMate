import 'package:flutter/material.dart';
import 'package:shamsi_date/shamsi_date.dart';

import 'personal_dates.dart';

/// Presentation-only calendar: the result is still a local Gregorian DateTime.
/// No stored date, weekday or notification timestamp is converted in place.
Future<DateTime?> showPersonalDatePicker({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
}) {
  final first = DateUtils.dateOnly(firstDate);
  final last = DateUtils.dateOnly(lastDate);
  if (last.isBefore(first)) throw ArgumentError('Invalid calendar date range.');
  final initial = DateUtils.dateOnly(initialDate);
  return showDialog<DateTime>(
    context: context,
    builder: (_) => _PersianDateDialog(
      initial: initial.isBefore(first)
          ? first
          : initial.isAfter(last)
              ? last
              : initial,
      first: first,
      last: last,
    ),
  );
}

class _PersianDateDialog extends StatefulWidget {
  const _PersianDateDialog({
    required this.initial,
    required this.first,
    required this.last,
  });
  final DateTime initial;
  final DateTime first;
  final DateTime last;

  @override
  State<_PersianDateDialog> createState() => _PersianDateDialogState();
}

class _PersianDateDialogState extends State<_PersianDateDialog> {
  late final _first = Jalali.fromDateTime(widget.first);
  late final _last = Jalali.fromDateTime(widget.last);
  late Jalali _selected = Jalali.fromDateTime(widget.initial);

  int _firstMonth(int year) => year == _first.year ? _first.month : 1;
  int _lastMonth(int year) => year == _last.year ? _last.month : 12;
  int _firstDay(int year, int month) =>
      year == _first.year && month == _first.month ? _first.day : 1;
  int _lastDay(int year, int month) =>
      year == _last.year && month == _last.month
          ? _last.day
          : Jalali(year, month).monthLength;

  void _change({int? year, int? month, int? day}) {
    final y = (year ?? _selected.year).clamp(_first.year, _last.year);
    final m = (month ?? _selected.month).clamp(_firstMonth(y), _lastMonth(y));
    final d = (day ?? _selected.day).clamp(_firstDay(y, m), _lastDay(y, m));
    setState(() => _selected = Jalali(y, m, d));
  }

  Widget _field({
    required String id,
    required String label,
    required int value,
    required int first,
    required int last,
    required String Function(int) text,
    required ValueChanged<int> changed,
  }) =>
      InputDecorator(
        key: ValueKey('personal-date-$id'),
        decoration: InputDecoration(labelText: label),
        child: DropdownButtonHideUnderline(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: DropdownButton<int>(
              value: value,
              isExpanded: true,
              itemHeight: null,
              menuMaxHeight: MediaQuery.sizeOf(context).height * .6,
              items: [
                for (var item = first; item <= last; item++)
                  DropdownMenuItem(
                    value: item,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 48),
                      child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Text(text(item))),
                    ),
                  ),
              ],
              onChanged: (selected) {
                if (selected != null) changed(selected);
              },
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => AlertDialog(
        key: const Key('personal-date-dialog'),
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        title: const Text('انتخاب تاریخ شمسی'),
        content: SizedBox(
          width: 320,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                _field(
                    id: 'year',
                    label: 'سال',
                    value: _selected.year,
                    first: _first.year,
                    last: _last.year,
                    text: personalDateDigits,
                    changed: (value) => _change(year: value)),
                const SizedBox(height: 20),
                _field(
                    id: 'month',
                    label: 'ماه',
                    value: _selected.month,
                    first: _firstMonth(_selected.year),
                    last: _lastMonth(_selected.year),
                    text: (month) => Jalali(_selected.year, month).formatter.mN,
                    changed: (value) => _change(month: value)),
                const SizedBox(height: 20),
                _field(
                    id: 'day',
                    label: 'روز',
                    value: _selected.day,
                    first: _firstDay(_selected.year, _selected.month),
                    last: _lastDay(_selected.year, _selected.month),
                    text: personalDateDigits,
                    changed: (value) => _change(day: value)),
                const SizedBox(height: 20),
                Text(personalDateLabel(_selected.toDateTime()),
                    key: const Key('personal-date-preview'),
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                const Text(
                    'اگر روز انتخابی در ماه یا سال جدید نباشد، آخرین روز مجاز انتخاب می‌شود.'),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('انصراف')),
          FilledButton(
              onPressed: () => Navigator.pop(context, _selected.toDateTime()),
              child: const Text('انتخاب تاریخ')),
        ],
      );
}
