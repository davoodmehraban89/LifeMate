/// Domain for the explicitly device-only edition. These records are not API
/// identities, cached server records, or acknowledgements of online writes.
enum StandaloneProfileCategory { girlMinor, boyMinor, adult }

enum StandalonePlanKind { task, event, routine }

enum StandaloneRecurrence { once, daily, everyTwoDays, weekly }

class StandaloneProfile {
  const StandaloneProfile(
      {required this.id,
      required this.displayName,
      required this.category,
      required this.companionName,
      required this.themeKey});
  final String id;
  final String displayName;
  final StandaloneProfileCategory category;
  final String companionName;
  final String themeKey;
  static const themeKeys = ['violet', 'blue', 'mint', 'coral'];
}

/// Calendar operations use UTC only for day arithmetic. Occurrence clock times
/// remain local wall-clock times, including when the local UTC offset changes.
abstract final class StandaloneDate {
  static DateTime only(DateTime value) =>
      DateTime(value.year, value.month, value.day);
  static String key(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
  static DateTime parse(String value) {
    final parsed = DateTime.parse(value);
    return only(parsed);
  }

  static int daysBetween(DateTime from, DateTime to) =>
      DateTime.utc(to.year, to.month, to.day)
          .difference(DateTime.utc(from.year, from.month, from.day))
          .inDays;
  static DateTime addDays(DateTime value, int count) =>
      DateTime(value.year, value.month, value.day + count);
}

class StandaloneWeeklySlot {
  const StandaloneWeeklySlot(
      {required this.weekday,
      required this.startMinute,
      required this.endMinute});
  final int weekday;
  final int startMinute;
  final int endMinute;
}

class StandalonePlanDraft {
  const StandalonePlanDraft(
      {required this.title,
      required this.kind,
      required this.recurrence,
      required this.startDate,
      required this.startMinute,
      required this.endMinute,
      this.untilDate,
      this.weeklySlots = const [],
      this.reminderMinutes});
  final String title;
  final StandalonePlanKind kind;
  final StandaloneRecurrence recurrence;
  final DateTime startDate;
  final DateTime? untilDate;
  final int startMinute;
  final int endMinute;
  final List<StandaloneWeeklySlot> weeklySlots;
  final int? reminderMinutes;
}

class StandalonePlan {
  StandalonePlan(
      {required this.id,
      required this.profileId,
      required this.title,
      required this.kind,
      required this.recurrence,
      required this.startDate,
      required this.startMinute,
      required this.endMinute,
      required this.archived,
      this.untilDate,
      List<StandaloneWeeklySlot> weeklySlots = const [],
      this.reminderMinutes})
      : weeklySlots = List.unmodifiable(weeklySlots);
  final String id;
  final String profileId;
  final String title;
  final StandalonePlanKind kind;
  final StandaloneRecurrence recurrence;
  final DateTime startDate;
  final DateTime? untilDate;
  final int startMinute;
  final int endMinute;
  final List<StandaloneWeeklySlot> weeklySlots;
  final int? reminderMinutes;
  final bool archived;
}

class StandaloneOccurrence {
  const StandaloneOccurrence(
      {required this.id,
      required this.planId,
      required this.date,
      required this.title,
      required this.kind,
      required this.startMinute,
      required this.endMinute,
      required this.completed,
      required this.archived,
      this.reminderMinutes});
  final String id;
  final String planId;
  final DateTime date;
  final String title;
  final StandalonePlanKind kind;
  final int startMinute;
  final int endMinute;
  final bool completed;
  final bool archived;
  final int? reminderMinutes;
  DateTime get startsAt => DateTime(
      date.year, date.month, date.day, startMinute ~/ 60, startMinute % 60);
  DateTime get endsAt => DateTime(
      date.year, date.month, date.day, endMinute ~/ 60, endMinute % 60);
  DateTime? get remindAt => reminderMinutes == null
      ? null
      : startsAt.subtract(Duration(minutes: reminderMinutes!));
}
