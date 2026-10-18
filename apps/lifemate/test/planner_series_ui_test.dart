import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate/api.dart';
import 'package:lifemate/planner_series.dart';
import 'package:lifemate/planner_series_ui.dart';

void main() {
  setUpAll(() async {
    await (FontLoader('LifeGuidePersian')
          ..addFont(rootBundle.load('assets/fonts/LifeGuidePersian.ttf')))
        .load();
  });

  Future<void> open(
    WidgetTester tester,
    Future<PlannerSeriesOutcome> Function(Map<String, dynamic>, {String? id})
        create, {
    ValueChanged<PlannerSeriesOutcome?>? onClosed,
    Size size = const Size(390, 844),
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(fontFamily: 'LifeGuidePersian'),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Builder(builder: (context) {
        return Scaffold(
          body: TextButton(
            child: const Text('افزودن'),
            onPressed: () async {
              final result = await showDialog<PlannerSeriesOutcome>(
                context: context,
                builder: (_) => Directionality(
                  textDirection: TextDirection.rtl,
                  child: PlannerSeriesDialog(
                    api: HttpIdentityApi(baseUrl: 'https://example.invalid'),
                    initialDate: DateTime(2026, 10, 19),
                    onCreate: create,
                  ),
                ),
              );
              onClosed?.call(result);
            },
          ),
        );
      }),
    ));
    await tester.tap(find.text('افزودن'));
    await tester.pumpAndSettle();
  }

  Future<void> tapVisible(WidgetTester tester, Finder target) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  testWidgets('empty title never submits a recurring plan', (tester) async {
    var submitted = 0;
    await open(tester, (payload, {id}) async {
      submitted++;
      return PlannerSeriesOutcome(queued: false, id: id!);
    });
    await tester.tap(find.byKey(const ValueKey('series-save')));
    await tester.pumpAndSettle();
    expect(find.text('عنوان را وارد کن.'), findsOneWidget);
    expect(submitted, 0);
  });

  testWidgets('weekly selected days retain independent time slots and privacy',
      (tester) async {
    Map<String, dynamic>? submitted;
    PlannerSeriesOutcome? result;
    await open(tester, (payload, {id}) async {
      submitted = jsonDecode(jsonEncode(payload)) as Map<String, dynamic>;
      return PlannerSeriesOutcome(queued: false, id: id!);
    }, onClosed: (value) => result = value);
    await tester.enterText(
        find.byKey(const ValueKey('series-title')), 'برنامهٔ تمرینی ساختگی');
    await tapVisible(tester, find.byKey(const ValueKey('series-weekday-6')));
    await tapVisible(tester, find.byKey(const ValueKey('series-day-6-end')));
    final timeFields = find.descendant(
        of: find.byType(TimePickerDialog), matching: find.byType(TextField));
    await tester.enterText(timeFields.at(0), '10');
    await tester.enterText(timeFields.at(1), '30');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('series-save')));
    await tester.pumpAndSettle();
    expect(submitted!['timezone'], 'Asia/Tehran');
    expect(submitted!['startsOn'], '2026-10-19');
    expect(submitted!['frequency'], 'weekly');
    expect(submitted!['intervalDays'], 1);
    expect(submitted!['slots'], [
      {'weekday': 1, 'start': '08:00', 'end': '09:00'},
      {'weekday': 6, 'start': '08:00', 'end': '10:30'},
    ]);
    expect(submitted!.containsKey('visibility'), isFalse);
    expect(submitted!.containsKey('familyId'), isFalse);
    expect(result?.queued, isFalse);
    expect(result?.id, matches(RegExp(r'^[a-f0-9-]{36}$')));
    expect(tester.takeException(), isNull);
  });

  testWidgets('daily alternate schedule omits weekdays and accepts reminders',
      (tester) async {
    Map<String, dynamic>? submitted;
    await open(tester, (payload, {id}) async {
      submitted = payload;
      return PlannerSeriesOutcome(queued: true, id: id!);
    });
    await tester.enterText(
        find.byKey(const ValueKey('series-title')), 'کار روزدرمیان ساختگی');
    await tapVisible(tester, find.byKey(const ValueKey('series-frequency')));
    await tester.tap(find.text('روزانه').last);
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byKey(const ValueKey('series-interval')));
    await tester.tap(find.text('یک روز در میان').last);
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byKey(const ValueKey('series-reminder')));
    await tester.tap(find.text('۱۰ دقیقه پیش از شروع').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('series-save')));
    await tester.pumpAndSettle();
    expect(submitted!['frequency'], 'daily');
    expect(submitted!['intervalDays'], 2);
    expect(submitted!['slots'], [
      {'start': '08:00', 'end': '09:00'}
    ]);
    expect(submitted!['reminderMinutes'], [10]);
    expect(find.byType(PlannerSeriesDialog), findsNothing);
  });

  testWidgets(
      'unknown response freezes every control and retries exact request',
      (tester) async {
    final payloads = <String>[];
    final ids = <String?>[];
    await open(tester, (payload, {id}) async {
      payloads.add(jsonEncode(payload));
      ids.add(id);
      if (ids.length == 1) throw const ApiException(500, 'unknown_response');
      return PlannerSeriesOutcome(queued: false, id: id!);
    });
    await tester.enterText(
        find.byKey(const ValueKey('series-title')), 'درخواست با پاسخ نامعلوم');
    await tester.tap(find.byKey(const ValueKey('series-save')));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('series-title')))
            .enabled,
        isFalse);
    expect(
        tester
            .widget<DropdownButtonFormField<String>>(
                find.byKey(const ValueKey('series-frequency')))
            .onChanged,
        isNull);
    expect(
        tester
            .widget<OutlinedButton>(
                find.byKey(const ValueKey('series-start-date')))
            .onPressed,
        isNull);
    expect(
        tester
            .widget<CheckboxListTile>(
                find.byKey(const ValueKey('series-has-end')))
            .onChanged,
        isNull);
    await tester.tap(find.byKey(const ValueKey('series-save')));
    await tester.pumpAndSettle();
    expect(ids, hasLength(2));
    expect(ids[0], ids[1]);
    expect(payloads[0], payloads[1]);
  });

  testWidgets('same-day end must follow start and no day means no submission',
      (tester) async {
    var submitted = 0;
    await open(tester, (payload, {id}) async {
      submitted++;
      return PlannerSeriesOutcome(queued: false, id: id!);
    });
    await tester.enterText(find.byKey(const ValueKey('series-title')), 'نمونه');
    await tapVisible(tester, find.byKey(const ValueKey('series-day-1-end')));
    final timeFields = find.descendant(
        of: find.byType(TimePickerDialog), matching: find.byType(TextField));
    await tester.enterText(timeFields.at(0), '08');
    await tester.enterText(timeFields.at(1), '00');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('series-save')));
    await tester.pumpAndSettle();
    expect(find.text('پایان هر نوبت باید پس از شروع و در همان روز باشد.'),
        findsOneWidget);
    await tapVisible(tester, find.byKey(const ValueKey('series-weekday-1')));
    await tester.tap(find.byKey(const ValueKey('series-save')));
    await tester.pumpAndSettle();
    expect(find.text('دست‌کم یک روز هفته را انتخاب کن.'), findsOneWidget);
    expect(submitted, 0);
  });

  testWidgets('terminal rejection keeps identity and offers queue recovery',
      (tester) async {
    await open(tester, (payload, {id}) async {
      throw const ApiException(409, 'version_conflict');
    });
    await tester.enterText(find.byKey(const ValueKey('series-title')), 'نمونه');
    await tester.tap(find.byKey(const ValueKey('series-save')));
    await tester.pumpAndSettle();
    expect(find.text('بررسی تغییرات در انتظار'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('series-save')))
            .onPressed,
        isNull);
    expect(find.textContaining('شناسهٔ تازه نساز'), findsOneWidget);
  });

  testWidgets(
      'form scrolls at 320 pixels and 200 percent text without overflow',
      (tester) async {
    await open(tester, (payload, {id}) async {
      return PlannerSeriesOutcome(queued: true, id: id!);
    }, size: const Size(320, 740), textScale: 2);
    await tapVisible(tester, find.byKey(const ValueKey('series-has-end')));
    expect(find.byKey(const ValueKey('series-end-date')), findsOneWidget);
    await tapVisible(tester, find.byKey(const ValueKey('series-weekday-6')));
    await tester.ensureVisible(find.byKey(const ValueKey('series-reminder')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('series-save')).hitTestable(),
        findsOneWidget);
    expect(tester.getSize(find.byKey(const ValueKey('series-save'))).height,
        greaterThanOrEqualTo(48));
  });
}
