import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate/standalone/model.dart';
import 'package:lifemate/standalone/store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory directory;
  late String path;
  late StandaloneStore store;
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('lifeguide-local-store-');
    path = '${directory.path}/planner.sqlite';
    store = await StandaloneStore.open(path: path, factory: databaseFactoryFfi);
  });
  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });
  Future<StandaloneProfile> profile() => store.createProfile(
        displayName: 'نام ساختگی',
        category: StandaloneProfileCategory.girlMinor,
      );
  StandalonePlanDraft daily({
    DateTime? start,
    DateTime? until,
    int? reminder,
    StandaloneRecurrence recurrence = StandaloneRecurrence.daily,
  }) =>
      StandalonePlanDraft(
        title: 'برنامه ساختگی',
        kind: StandalonePlanKind.task,
        recurrence: recurrence,
        startDate: start ?? DateTime(2026, 10, 19),
        untilDate: until,
        startMinute: 480,
        endMinute: 540,
        reminderMinutes: reminder,
      );
  test('real SQLite file preserves profile and independent edits on reopen',
      () async {
    final owner = await profile();
    expect(
        owner.id,
        matches(RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
    final plan = await store.createPlan(daily());
    final first = await store.occurrences(
        from: DateTime(2026, 10, 19), through: DateTime(2026, 10, 20));
    await store.updateOccurrence(first.first.id,
        title: 'عنوان مستقل',
        startMinute: 600,
        endMinute: 660,
        completed: true);
    await store.close();
    expect(await File(path).length(), greaterThan(0));
    store = await StandaloneStore.open(path: path, factory: databaseFactoryFfi);
    expect((await store.profile())!.id, owner.id);
    final reread = await store.occurrences(
        from: DateTime(2026, 10, 19), through: DateTime(2026, 10, 20));
    expect(reread.map((item) => item.id), first.map((item) => item.id));
    expect(reread.first.title, 'عنوان مستقل');
    expect(reread.first.completed, isTrue);
    expect(reread.first.startMinute, 600);
    expect(reread.last.completed, isFalse);
    expect(reread.last.title, 'برنامه ساختگی');
    await store.archivePlan(plan.id);
    expect(await store.listPlans(), isEmpty);
    expect((await store.occurrence(first.first.id))!.completed, isTrue);
    await store.close();
    store = await StandaloneStore.open(path: path, factory: databaseFactoryFfi);
    expect(
        (await store.listPlans(includeArchived: true)).single.archived, isTrue);
  });
  test('profile edits retain identity and plans; a second profile is rejected',
      () async {
    final owner = await profile();
    await store.createPlan(daily());
    await expectLater(profile(), throwsStateError);
    final updated = await store.updateProfile(
        displayName: 'نام تازه', companionName: 'آوا', themeKey: 'mint');
    expect(updated.id, owner.id);
    expect(updated.displayName, 'نام تازه');
    expect(updated.companionName, 'آوا');
    expect(updated.themeKey, 'mint');
    expect(await store.listPlans(), hasLength(1));
  });
  test('every two days uses calendar dates across month and DST', () async {
    await profile();
    await store.createPlan(daily(
        start: DateTime(2026, 10, 30),
        until: DateTime(2026, 11, 5),
        recurrence: StandaloneRecurrence.everyTwoDays));
    final occurrences = await store.occurrences(
        from: DateTime(2026, 10, 31), through: DateTime(2026, 11, 7));
    expect(occurrences.map((item) => item.date.day), [1, 3, 5]);
    expect(occurrences.every((item) => item.startMinute == 480), isTrue);
    expect(occurrences.every((item) => item.startsAt.hour == 8), isTrue);
    expect(
        StandaloneDate.daysBetween(DateTime(2026, 3, 7), DateTime(2026, 3, 10)),
        3);
  });
  test('weekly schedules use selected weekdays and independent hours',
      () async {
    await profile();
    await store.createPlan(StandalonePlanDraft(
      title: 'هفتگی ساختگی',
      kind: StandalonePlanKind.routine,
      recurrence: StandaloneRecurrence.weekly,
      startDate: DateTime(2026, 10, 19),
      untilDate: DateTime(2026, 10, 25),
      startMinute: 480,
      endMinute: 540,
      weeklySlots: const [
        StandaloneWeeklySlot(
            weekday: DateTime.monday, startMinute: 480, endMinute: 540),
        StandaloneWeeklySlot(
            weekday: DateTime.friday, startMinute: 1080, endMinute: 1140),
      ],
    ));
    final occurrences = await store.occurrences(
        from: DateTime(2026, 10, 18), through: DateTime(2026, 10, 26));
    expect(occurrences.map((item) => item.date.day), [19, 23]);
    expect(occurrences.map((item) => item.startMinute), [480, 1080]);
    expect(occurrences.map((item) => item.endMinute), [540, 1140]);
  });
  test(
      'one-off plans produce only their date and overlapping reads never duplicate',
      () async {
    await profile();
    await store.createPlan(daily(recurrence: StandaloneRecurrence.once));
    final reads = await Future.wait(List.generate(
        4,
        (_) => store.occurrences(
            from: DateTime(2026, 10, 18), through: DateTime(2026, 10, 21))));
    expect(reads.every((items) => items.length == 1), isTrue);
    expect(reads.map((items) => items.single.id).toSet(), hasLength(1));
  });
  test('archived occurrence is never regenerated', () async {
    await profile();
    await store.createPlan(daily());
    final initial = await store.occurrences(
        from: DateTime(2026, 10, 19), through: DateTime(2026, 10, 20));
    await store.archiveOccurrence(initial.first.id);
    final active = await store.occurrences(
        from: DateTime(2026, 10, 19), through: DateTime(2026, 10, 20));
    expect(active.map((item) => item.id), [initial.last.id]);
    expect((await store.occurrence(initial.first.id))!.archived, isTrue);
  });
  test('reminders use edits and exclude completed and archived series',
      () async {
    await profile();
    final plan = await store.createPlan(daily(reminder: 10));
    final occurrences = await store.occurrences(
        from: DateTime(2026, 10, 19), through: DateTime(2026, 10, 21));
    await store.updateOccurrence(occurrences[0].id, completed: true);
    await store.updateOccurrence(occurrences[1].id,
        startMinute: 600, endMinute: 660, reminderMinutes: 30);
    final pending = await store.pendingReminders(
        from: DateTime(2026, 10, 19), through: DateTime(2026, 10, 22));
    expect(
        pending.map((item) => item.id), [occurrences[1].id, occurrences[2].id]);
    expect(pending.first.remindAt, DateTime(2026, 10, 20, 9, 30));
    await store.archivePlan(plan.id);
    expect(
        await store.pendingReminders(
            from: DateTime(2026, 10, 19), through: DateTime(2026, 10, 22)),
        isEmpty);
    expect((await store.occurrence(occurrences[0].id))!.completed, isTrue);
  });
  test('invalid schedule fails before a plan is saved', () async {
    await profile();
    await expectLater(
        store.createPlan(StandalonePlanDraft(
          title: '',
          kind: StandalonePlanKind.task,
          recurrence: StandaloneRecurrence.daily,
          startDate: DateTime(2026, 10, 19),
          startMinute: 600,
          endMinute: 500,
        )),
        throwsArgumentError);
    await expectLater(
        store.createPlan(daily(reminder: 7)), throwsArgumentError);
    expect(await store.listPlans(), isEmpty);
  });
  test('SQLite independently rejects duplicates and invalid times', () async {
    await profile();
    await store.createPlan(daily(recurrence: StandaloneRecurrence.once));
    final item = (await store.occurrences(
            from: DateTime(2026, 10, 19), through: DateTime(2026, 10, 19)))
        .single;
    final database = await databaseFactoryFfi.openDatabase(path);
    await expectLater(
        database.rawInsert(
          'INSERT INTO local_occurrences SELECT ? AS id, plan_id, occurrence_date, title, kind, start_minute, end_minute, completed, archived, reminder_minutes FROM local_occurrences WHERE id = ?',
          ['00000000-0000-4000-8000-000000000000', item.id],
        ),
        throwsA(isA<DatabaseException>()));
    await expectLater(
        database.rawUpdate(
            'UPDATE local_occurrences SET end_minute = start_minute WHERE id = ?',
            [item.id]),
        throwsA(isA<DatabaseException>()));
  });
  test('a storage failure rolls back the complete plan transaction', () async {
    await profile();
    final database = await databaseFactoryFfi.openDatabase(path);
    await database.execute(
        "CREATE TRIGGER reject_slot BEFORE INSERT ON local_weekly_slots BEGIN SELECT RAISE(ABORT, 'synthetic disk write rejection'); END");
    await expectLater(
        store.createPlan(StandalonePlanDraft(
          title: 'rollback fixture',
          kind: StandalonePlanKind.routine,
          recurrence: StandaloneRecurrence.weekly,
          startDate: DateTime(2026, 10, 19),
          startMinute: 480,
          endMinute: 540,
          weeklySlots: const [
            StandaloneWeeklySlot(weekday: 1, startMinute: 480, endMinute: 540)
          ],
        )),
        throwsA(isA<DatabaseException>()));
    expect(await store.listPlans(includeArchived: true), isEmpty);
    expect(await database.query('local_weekly_slots'), isEmpty);
  });
  test('schema version is durable and newer data is refused without resetting',
      () async {
    final owner = await profile();
    final database = await databaseFactoryFfi.openDatabase(path);
    expect(await database.getVersion(), StandaloneStore.schemaVersion);
    await database.setVersion(StandaloneStore.schemaVersion + 1);
    await store.close();
    await expectLater(
        StandaloneStore.open(path: path, factory: databaseFactoryFfi),
        throwsStateError);
    final preserved = await databaseFactoryFfi.openDatabase(path);
    expect(await preserved.getVersion(), StandaloneStore.schemaVersion + 1);
    expect((await preserved.query('local_profiles')).single['id'], owner.id);
    await preserved.close();
  });
  test('reminders can be disabled independently and include next-day lead time',
      () async {
    await profile();
    await store.createPlan(StandalonePlanDraft(
      title: 'midnight fixture',
      kind: StandalonePlanKind.event,
      recurrence: StandaloneRecurrence.daily,
      startDate: DateTime(2026, 10, 19),
      startMinute: 10,
      endMinute: 60,
      reminderMinutes: 30,
    ));
    final pending = await store.pendingReminders(
        from: DateTime(2026, 10, 19, 23),
        through: DateTime(2026, 10, 19, 23, 59));
    expect(pending.single.date, DateTime(2026, 10, 20));
    expect(pending.single.remindAt, DateTime(2026, 10, 19, 23, 40));
    await store.updateOccurrence(pending.single.id, removeReminder: true);
    expect(
        await store.pendingReminders(
            from: DateTime(2026, 10, 19, 23),
            through: DateTime(2026, 10, 19, 23, 59)),
        isEmpty);
  });
  test('closed writes throw and corruption never resets the database',
      () async {
    await profile();
    await store.close();
    await expectLater(
        store.updateProfile(displayName: 'not saved'), throwsA(anything));
    final badPath = '${directory.path}/corrupt.sqlite';
    final bytes = [1, 7, 9, 2, 5, 3];
    await File(badPath).writeAsBytes(bytes);
    await expectLater(
        StandaloneStore.open(path: badPath, factory: databaseFactoryFfi),
        throwsA(anything));
    expect(await File(badPath).readAsBytes(), bytes);
  });
}
