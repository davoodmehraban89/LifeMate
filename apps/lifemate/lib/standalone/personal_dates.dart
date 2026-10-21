import 'package:shamsi_date/shamsi_date.dart';

// Display calendar only. SQLite/notification dates remain local Gregorian dates.
String personalDateDigits(Object value) => value.toString().replaceAllMapped(
    RegExp('[0-9]'), (match) => '۰۱۲۳۴۵۶۷۸۹'[int.parse(match[0]!)]);

String personalDateLabel(DateTime value) {
  final date = Jalali.fromDateTime(value);
  return '${personalDateDigits(date.day)} ${date.formatter.mN} ${personalDateDigits(date.year)} شمسی';
}

String personalDayLabel(DateTime value) =>
    personalDateDigits(Jalali.fromDateTime(value).day);
