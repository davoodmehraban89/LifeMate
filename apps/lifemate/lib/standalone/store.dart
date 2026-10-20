import 'dart:math';

import 'package:path/path.dart' as paths;
import 'package:sqflite/sqflite.dart';

import 'model.dart';

/// Authoritative private storage for the device-only edition. Opening or writing
/// a database failure is surfaced to the caller; no empty fallback replaces it.
class StandaloneStore {
  StandaloneStore._(this._database);
  final Database _database;
  static const schemaVersion = 1;
  static const databaseName = 'lifeguide_standalone_v1.sqlite';

  static Future<StandaloneStore> open(
      {String? path, DatabaseFactory? factory}) async {
    final driver = factory ?? databaseFactory;
    final resolved =
        path ?? paths.join(await driver.getDatabasesPath(), databaseName);
    final database = await driver.openDatabase(resolved,
        options: OpenDatabaseOptions(
          version: schemaVersion,
          onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
          onCreate: (db, version) => _migrate(db, 0, version),
          onUpgrade: _migrate,
          onDowngrade: (db, oldVersion, newVersion) async {
            throw StateError(
                'The local database requires a newer app version.');
          },
          onOpen: (db) async {
            final check = await db.rawQuery('PRAGMA quick_check');
            if (check.length != 1 || check.single.values.single != 'ok') {
              throw StateError('The local database integrity check failed.');
            }
          },
        ));
    return StandaloneStore._(database);
  }

  static Future<void> _migrate(
      Database db, int oldVersion, int newVersion) async {
    // Sqflite wraps create/upgrade callbacks in one transaction. Future versions
    // must add ordered migrations here and never clear user tables on failure.
    if (oldVersion < 1) {
      await db.execute('''CREATE TABLE local_profiles (
        singleton INTEGER PRIMARY KEY CHECK(singleton = 1),
        id TEXT NOT NULL UNIQUE CHECK(length(id) = 36),
        display_name TEXT NOT NULL CHECK(length(trim(display_name)) BETWEEN 1 AND 80),
        category TEXT NOT NULL CHECK(category IN ('girl_minor','boy_minor','adult')),
        companion_name TEXT NOT NULL CHECK(length(trim(companion_name)) BETWEEN 1 AND 40),
        theme_key TEXT NOT NULL CHECK(theme_key IN ('violet','blue','mint','coral'))
      )''');
      await db.execute('''CREATE TABLE local_plans (
        id TEXT PRIMARY KEY NOT NULL CHECK(length(id) = 36),
        profile_id TEXT NOT NULL REFERENCES local_profiles(id),
        title TEXT NOT NULL CHECK(length(trim(title)) BETWEEN 1 AND 200),
        kind TEXT NOT NULL CHECK(kind IN ('task','event','routine')),
        recurrence TEXT NOT NULL CHECK(recurrence IN ('once','daily','everyTwoDays','weekly')),
        start_date TEXT NOT NULL CHECK(length(start_date) = 10),
        until_date TEXT CHECK(until_date IS NULL OR (length(until_date) = 10 AND until_date >= start_date)),
        start_minute INTEGER NOT NULL CHECK(start_minute BETWEEN 0 AND 1439),
        end_minute INTEGER NOT NULL CHECK(end_minute BETWEEN 1 AND 1440 AND end_minute > start_minute),
        reminder_minutes INTEGER CHECK(reminder_minutes IS NULL OR reminder_minutes IN (0,5,10,15,30)),
        archived INTEGER NOT NULL DEFAULT 0 CHECK(archived IN (0,1))
      )''');
      await db.execute('''CREATE TABLE local_weekly_slots (
        plan_id TEXT NOT NULL REFERENCES local_plans(id),
        weekday INTEGER NOT NULL CHECK(weekday BETWEEN 1 AND 7),
        start_minute INTEGER NOT NULL CHECK(start_minute BETWEEN 0 AND 1439),
        end_minute INTEGER NOT NULL CHECK(end_minute BETWEEN 1 AND 1440 AND end_minute > start_minute),
        PRIMARY KEY(plan_id, weekday)
      )''');
      await db.execute('''CREATE TABLE local_occurrences (
        id TEXT PRIMARY KEY NOT NULL CHECK(length(id) = 36),
        plan_id TEXT NOT NULL REFERENCES local_plans(id),
        occurrence_date TEXT NOT NULL CHECK(length(occurrence_date) = 10),
        title TEXT NOT NULL CHECK(length(trim(title)) BETWEEN 1 AND 200),
        kind TEXT NOT NULL CHECK(kind IN ('task','event','routine')),
        start_minute INTEGER NOT NULL CHECK(start_minute BETWEEN 0 AND 1439),
        end_minute INTEGER NOT NULL CHECK(end_minute BETWEEN 1 AND 1440 AND end_minute > start_minute),
        completed INTEGER NOT NULL DEFAULT 0 CHECK(completed IN (0,1)),
        archived INTEGER NOT NULL DEFAULT 0 CHECK(archived IN (0,1)),
        reminder_minutes INTEGER CHECK(reminder_minutes IS NULL OR reminder_minutes IN (0,5,10,15,30)),
        UNIQUE(plan_id, occurrence_date)
      )''');
      await db.execute(
          'CREATE INDEX local_occurrences_date ON local_occurrences(occurrence_date)');
    }
  }

  Future<StandaloneProfile?> profile() async {
    final rows = await _database.query('local_profiles');
    return rows.isEmpty ? null : _profile(rows.single);
  }

  Future<StandaloneProfile> createProfile({
    required String displayName,
    required StandaloneProfileCategory category,
    String companionName = 'همراه',
    String themeKey = 'violet',
  }) async {
    final name = _text(displayName, 'displayName', 80);
    final companion = _text(companionName, 'companionName', 40);
    _theme(themeKey);
    return _database.transaction((tx) async {
      if ((await tx.query('local_profiles')).isNotEmpty) {
        throw StateError('This installation already has its local profile.');
      }
      final row = <String, Object?>{
        'singleton': 1,
        'id': _uuid(),
        'display_name': name,
        'category': _categoryKey(category),
        'companion_name': companion,
        'theme_key': themeKey,
      };
      await tx.insert('local_profiles', row);
      return _profile(row);
    });
  }

  Future<StandaloneProfile> updateProfile(
      {String? displayName,
      StandaloneProfileCategory? category,
      String? companionName,
      String? themeKey}) async {
    return _database.transaction((tx) async {
      final rows = await tx.query('local_profiles');
      if (rows.isEmpty) throw StateError('Create the local profile first.');
      final row = Map<String, Object?>.of(rows.single);
      if (displayName != null) {
        row['display_name'] = _text(displayName, 'displayName', 80);
      }
      if (category != null) row['category'] = _categoryKey(category);
      if (companionName != null) {
        row['companion_name'] = _text(companionName, 'companionName', 40);
      }
      if (themeKey != null) {
        _theme(themeKey);
        row['theme_key'] = themeKey;
      }
      await tx.update('local_profiles', row, where: 'singleton = 1');
      return _profile(row);
    });
  }

  Future<StandalonePlan> createPlan(StandalonePlanDraft draft) async {
    final title = _text(draft.title, 'title', 200);
    _time(draft.startMinute, draft.endMinute);
    _date(draft.startDate);
    _reminder(draft.reminderMinutes);
    if (draft.untilDate != null) {
      _date(draft.untilDate!);
      if (StandaloneDate.daysBetween(draft.startDate, draft.untilDate!) < 0) {
        throw ArgumentError('untilDate must not precede startDate.');
      }
    }
    if (draft.recurrence == StandaloneRecurrence.weekly) {
      if (draft.weeklySlots.isEmpty || draft.weeklySlots.length > 7) {
        throw ArgumentError('Select one to seven weekdays.');
      }
      final days = <int>{};
      for (final slot in draft.weeklySlots) {
        _time(slot.startMinute, slot.endMinute);
        if (slot.weekday < 1 || slot.weekday > 7 || !days.add(slot.weekday)) {
          throw ArgumentError('Each weekday must be valid and unique.');
        }
      }
    } else if (draft.weeklySlots.isNotEmpty) {
      throw ArgumentError('Weekday slots require weekly recurrence.');
    }
    return _database.transaction((tx) async {
      final profiles = await tx.query('local_profiles');
      if (profiles.isEmpty) throw StateError('Create the local profile first.');
      final row = <String, Object?>{
        'id': _uuid(),
        'profile_id': profiles.single['id'],
        'title': title,
        'kind': draft.kind.name,
        'recurrence': draft.recurrence.name,
        'start_date': StandaloneDate.key(draft.startDate),
        'until_date': draft.untilDate == null
            ? null
            : StandaloneDate.key(draft.untilDate!),
        'start_minute': draft.startMinute,
        'end_minute': draft.endMinute,
        'reminder_minutes': draft.reminderMinutes,
        'archived': 0,
      };
      await tx.insert('local_plans', row);
      for (final slot in draft.weeklySlots) {
        await tx.insert('local_weekly_slots', {
          'plan_id': row['id'],
          'weekday': slot.weekday,
          'start_minute': slot.startMinute,
          'end_minute': slot.endMinute
        });
      }
      return _plan(row, draft.weeklySlots);
    });
  }

  Future<List<StandalonePlan>> listPlans({bool includeArchived = false}) =>
      _plans(_database, includeArchived: includeArchived);

  Future<List<StandalonePlan>> _plans(DatabaseExecutor executor,
      {bool includeArchived = false}) async {
    final rows = await executor.query('local_plans',
        where: includeArchived ? null : 'archived = 0', orderBy: 'rowid');
    final slots =
        await executor.query('local_weekly_slots', orderBy: 'weekday');
    return rows
        .map((row) => _plan(
            row,
            slots
                .where((slot) => slot['plan_id'] == row['id'])
                .map(_slot)
                .toList()))
        .toList();
  }

  /// Date bounds are inclusive. Materialized occurrences and their exceptions
  /// survive every later read; UNIQUE(plan_id, occurrence_date) prevents races.
  Future<List<StandaloneOccurrence>> occurrences(
      {required DateTime from,
      required DateTime through,
      bool includeArchived = false}) async {
    _date(from);
    _date(through);
    final count = StandaloneDate.daysBetween(from, through);
    if (count < 0 || count > 366) {
      throw ArgumentError('Read a range of at most 367 calendar dates.');
    }
    return _database.transaction((tx) async {
      final plans = await _plans(tx);
      for (final plan in plans) {
        for (var day = 0; day <= count; day++) {
          final date = StandaloneDate.addDays(from, day);
          final slot = _slotFor(plan, date);
          if (slot == null) continue;
          // Ignore only a duplicate occurrence. All other validation/storage
          // failures remain errors and roll back this entire transaction.
          await tx.rawInsert(
              '''INSERT INTO local_occurrences
            (id,plan_id,occurrence_date,title,kind,start_minute,end_minute,completed,archived,reminder_minutes)
            SELECT ?,?,?,?,?,?,?,0,0,?
            WHERE NOT EXISTS (SELECT 1 FROM local_occurrences WHERE plan_id = ? AND occurrence_date = ?)''',
              [
                _uuid(),
                plan.id,
                StandaloneDate.key(date),
                plan.title,
                plan.kind.name,
                slot.startMinute,
                slot.endMinute,
                plan.reminderMinutes,
                plan.id,
                StandaloneDate.key(date),
              ]);
        }
      }
      final rows = await tx.rawQuery('''SELECT o.* FROM local_occurrences o
        JOIN local_plans p ON p.id = o.plan_id
        WHERE o.occurrence_date BETWEEN ? AND ?
        ${includeArchived ? '' : 'AND o.archived = 0 AND p.archived = 0'}
        ORDER BY o.occurrence_date, o.start_minute, o.id''',
          [StandaloneDate.key(from), StandaloneDate.key(through)]);
      return rows.map(_occurrence).toList();
    });
  }

  Future<StandaloneOccurrence?> occurrence(String id) async {
    final rows = await _database
        .query('local_occurrences', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : _occurrence(rows.single);
  }

  Future<StandaloneOccurrence> updateOccurrence(String id,
      {String? title,
      int? startMinute,
      int? endMinute,
      bool? completed,
      int? reminderMinutes,
      bool removeReminder = false}) async {
    if (removeReminder && reminderMinutes != null) {
      throw ArgumentError('Choose a reminder or remove it.');
    }
    _reminder(reminderMinutes);
    return _database.transaction((tx) async {
      final rows = await tx.rawQuery('''SELECT o.*, p.archived AS plan_archived
        FROM local_occurrences o JOIN local_plans p ON p.id = o.plan_id WHERE o.id = ?''',
          [id]);
      if (rows.isEmpty) throw StateError('Occurrence does not exist.');
      if (rows.single['archived'] == 1 || rows.single['plan_archived'] == 1) {
        throw StateError('Occurrence is archived.');
      }
      final row = Map<String, Object?>.of(rows.single)..remove('plan_archived');
      if (title != null) row['title'] = _text(title, 'title', 200);
      if (startMinute != null) row['start_minute'] = startMinute;
      if (endMinute != null) row['end_minute'] = endMinute;
      _time(row['start_minute'] as int, row['end_minute'] as int);
      if (completed != null) row['completed'] = completed ? 1 : 0;
      if (removeReminder || reminderMinutes != null) {
        row['reminder_minutes'] = removeReminder ? null : reminderMinutes;
      }
      await tx
          .update('local_occurrences', row, where: 'id = ?', whereArgs: [id]);
      return _occurrence(row);
    });
  }

  Future<void> archiveOccurrence(String id) async {
    final count = await _database.update('local_occurrences', {'archived': 1},
        where: 'id = ?', whereArgs: [id]);
    if (count != 1) throw StateError('Occurrence does not exist.');
  }

  Future<void> archivePlan(String id) async {
    final count = await _database.update('local_plans', {'archived': 1},
        where: 'id = ?', whereArgs: [id]);
    if (count != 1) throw StateError('Plan does not exist.');
  }

  /// Bounds are instants, unlike [occurrences]. Include the next date because a
  /// reminder shortly before midnight can belong to tomorrow's occurrence.
  Future<List<StandaloneOccurrence>> pendingReminders(
      {required DateTime from, required DateTime through}) async {
    if (through.isBefore(from)) throw ArgumentError('Invalid reminder range.');
    final items = await occurrences(
        from: StandaloneDate.only(from),
        through: StandaloneDate.addDays(through, 1));
    final pending = items
        .where((item) =>
            !item.completed &&
            item.remindAt != null &&
            !item.remindAt!.isBefore(from) &&
            !item.remindAt!.isAfter(through))
        .toList();
    pending.sort((a, b) => a.remindAt!.compareTo(b.remindAt!));
    return pending;
  }

  Future<void> close() => _database.close();

  static StandaloneWeeklySlot? _slotFor(StandalonePlan plan, DateTime date) {
    final delta = StandaloneDate.daysBetween(plan.startDate, date);
    if (delta < 0 ||
        (plan.untilDate != null &&
            StandaloneDate.daysBetween(date, plan.untilDate!) < 0)) {
      return null;
    }
    if (plan.recurrence == StandaloneRecurrence.once && delta != 0) return null;
    if (plan.recurrence == StandaloneRecurrence.everyTwoDays && delta.isOdd) {
      return null;
    }
    if (plan.recurrence == StandaloneRecurrence.weekly) {
      for (final slot in plan.weeklySlots) {
        if (slot.weekday == date.weekday) return slot;
      }
      return null;
    }
    return StandaloneWeeklySlot(
        weekday: date.weekday,
        startMinute: plan.startMinute,
        endMinute: plan.endMinute);
  }

  static StandaloneProfile _profile(Map<String, Object?> row) =>
      StandaloneProfile(
          id: row['id'] as String,
          displayName: row['display_name'] as String,
          category: switch (row['category']) {
            'girl_minor' => StandaloneProfileCategory.girlMinor,
            'boy_minor' => StandaloneProfileCategory.boyMinor,
            'adult' => StandaloneProfileCategory.adult,
            _ => throw StateError('Invalid local profile category.')
          },
          companionName: row['companion_name'] as String,
          themeKey: row['theme_key'] as String);
  static String _categoryKey(StandaloneProfileCategory category) =>
      switch (category) {
        StandaloneProfileCategory.girlMinor => 'girl_minor',
        StandaloneProfileCategory.boyMinor => 'boy_minor',
        StandaloneProfileCategory.adult => 'adult'
      };
  static StandaloneWeeklySlot _slot(Map<String, Object?> row) =>
      StandaloneWeeklySlot(
          weekday: row['weekday'] as int,
          startMinute: row['start_minute'] as int,
          endMinute: row['end_minute'] as int);
  static StandalonePlan _plan(
          Map<String, Object?> row, List<StandaloneWeeklySlot> slots) =>
      StandalonePlan(
          id: row['id'] as String,
          profileId: row['profile_id'] as String,
          title: row['title'] as String,
          kind: StandalonePlanKind.values.byName(row['kind'] as String),
          recurrence:
              StandaloneRecurrence.values.byName(row['recurrence'] as String),
          startDate: StandaloneDate.parse(row['start_date'] as String),
          untilDate: row['until_date'] == null
              ? null
              : StandaloneDate.parse(row['until_date'] as String),
          startMinute: row['start_minute'] as int,
          endMinute: row['end_minute'] as int,
          reminderMinutes: row['reminder_minutes'] as int?,
          archived: row['archived'] == 1,
          weeklySlots: slots);
  static StandaloneOccurrence _occurrence(Map<String, Object?> row) =>
      StandaloneOccurrence(
          id: row['id'] as String,
          planId: row['plan_id'] as String,
          date: StandaloneDate.parse(row['occurrence_date'] as String),
          title: row['title'] as String,
          kind: StandalonePlanKind.values.byName(row['kind'] as String),
          startMinute: row['start_minute'] as int,
          endMinute: row['end_minute'] as int,
          completed: row['completed'] == 1,
          archived: row['archived'] == 1,
          reminderMinutes: row['reminder_minutes'] as int?);
  static void _time(int start, int end) {
    if (start < 0 || start >= 1440 || end <= start || end > 1440) {
      throw ArgumentError('Choose valid start and end times on the same day.');
    }
  }

  static String _text(String value, String name, int max) {
    final text = value.trim();
    if (text.isEmpty || text.length > max) {
      throw ArgumentError.value(
          value, name, 'Length must be between 1 and $max.');
    }
    return text;
  }

  static void _date(DateTime value) {
    if (value.year < 1 || value.year > 9999) {
      throw ArgumentError('Unsupported calendar date.');
    }
  }

  static void _reminder(int? value) {
    if (value != null && !const [0, 5, 10, 15, 30].contains(value)) {
      throw ArgumentError('Invalid reminder lead time.');
    }
  }

  static void _theme(String value) {
    if (!StandaloneProfile.themeKeys.contains(value)) {
      throw ArgumentError('Unknown local theme.');
    }
  }

  static String _uuid() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final text =
        bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    return '${text.substring(0, 8)}-${text.substring(8, 12)}-${text.substring(12, 16)}-${text.substring(16, 20)}-${text.substring(20)}';
  }
}
