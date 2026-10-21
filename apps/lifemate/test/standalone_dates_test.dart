import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate/standalone/personal_dates.dart';

void main() {
  final references = <DateTime, String>{
    DateTime(2024, 3, 20): '۱ فروردین ۱۴۰۳ شمسی',
    DateTime(2025, 3, 20): '۳۰ اسفند ۱۴۰۳ شمسی',
    DateTime(2025, 3, 21): '۱ فروردین ۱۴۰۴ شمسی',
    DateTime(2026, 10, 20): '۲۸ مهر ۱۴۰۵ شمسی',
    DateTime(2027, 3, 21): '۱ فروردین ۱۴۰۶ شمسی',
  };
  for (final entry in references.entries) {
    test('Persian date for ${entry.key.toIso8601String()}', () {
      expect(personalDateLabel(entry.key), entry.value);
    });
  }
  test('week chip day follows Persian month and does not use Gregorian day',
      () {
    expect(personalDayLabel(DateTime(2025, 3, 20)), '۳۰');
    expect(personalDayLabel(DateTime(2025, 3, 21)), '۱');
  });
  test('display uses the supplied calendar fields without moving UTC midnight',
      () {
    expect(personalDateLabel(DateTime.utc(2027, 3, 21)), '۱ فروردین ۱۴۰۶ شمسی');
  });
}
