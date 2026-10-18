import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate/phase3_ui.dart';
import 'package:lifemate/plan_sync.dart';
import 'package:lifemate/planner_series.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'app_test.dart' show FakeApi;

class PlannerFixture extends FakeApi {
  final writes = <Map<String, dynamic>>[];
  final rows = <Map<String, dynamic>>[];
  @override
  Future<List<Map<String, dynamic>>> listFamilies() async => [];
  @override
  Future<List<Map<String, dynamic>>> listPlanItems(
          {DateTime? from, DateTime? to, String? kind}) async =>
      rows;
  @override
  Future<List<Map<String, dynamic>>> getToday(
          {DateTime? from, DateTime? to}) async =>
      rows
          .where((row) =>
              row['status'] != 'completed' && row['status'] != 'cancelled')
          .toList();
  @override
  Future<Map<String, dynamic>> submitSyncMutations(
      List<Map<String, dynamic>> changes) async {
    writes.addAll(changes);
    final m = changes.single;
    final payload = m['payload'] as Map<String, dynamic>;
    final old = rows.where((row) => row['id'] == m['entityId']).firstOrNull;
    final row = <String, dynamic>{
      ...?(old),
      'id': m['entityId'],
      'version': (m['expectedVersion'] as int) + 1,
      'title': payload['title'] ?? old?['title'],
      'status': payload['status'] ?? 'planned',
      'starts_at': payload['startsAt'] ?? old?['starts_at'],
      'ends_at': payload['endsAt'] ?? old?['ends_at']
    };
    rows.removeWhere((item) => item['id'] == row['id']);
    rows.add(row);
    return {
      'results': [
        {
          'id': m['id'],
          'status': 'accepted',
          'item': row,
          'acceptedAt': DateTime.now().toUtc().toIso8601String()
        }
      ]
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData({});
    String? token;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('lifeguide/local_write_guard'), (call) async {
      if (call.method == 'getBlocked') return token != null;
      if (call.method == 'beginWrite') return token = 'weekly-widget-write';
      if (call.method == 'completeWrite' && call.arguments == token) {
        token = null;
        return true;
      }
      throw PlatformException(code: 'local_storage_restart_required');
    });
  });
  Future<void> dialog(WidgetTester tester, PlannerFixture api,
      {Map<String, dynamic>? item, DateTime? date}) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () => showDialog<MutationOutcome>(
                        context: context,
                        builder: (_) => PlanItemDialog(
                            api: api, item: item, initialDate: date)),
                    child: const Text('open'))))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('selected calendar day creates explicit start and end',
      (tester) async {
    final api = PlannerFixture();
    final date = DateTime.now().add(const Duration(days: 3));
    await dialog(tester, api, date: date);
    await tester.enterText(
        find.widgetWithText(TextField, 'عنوان'), 'برنامه ساختگی');
    await tester.tap(find.text('ذخیره'));
    await tester.pumpAndSettle();
    final body = api.writes.single['payload'] as Map;
    expect(plannerDate(DateTime.parse(body['startsAt']).toLocal()),
        plannerDate(date));
    expect(
        DateTime.parse(body['endsAt'])
            .difference(DateTime.parse(body['startsAt']))
            .inMinutes,
        30);
    expect(body['visibility'], 'private');
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('home retains completed count after a fresh read',
      (tester) async {
    final api = PlannerFixture();
    api.rows.add({
      'id': '40000000-0000-4000-8000-000000000001',
      'title': 'کار ساختگی',
      'kind': 'task',
      'status': 'planned',
      'version': 1,
      'starts_at': DateTime.now().toUtc().toIso8601String()
    });
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body:
                TodayPage(api: api, home: true, displayName: 'کاربر ساختگی'))));
    await tester.pumpAndSettle();
    expect(find.text('0 از 1 کار امروز انجام شده'), findsOneWidget);
    final tick =
        find.byKey(const ValueKey('tick-40000000-0000-4000-8000-000000000001'));
    await tester.ensureVisible(tick);
    await tester.tap(tick);
    await tester.pumpAndSettle();
    expect(find.text('1 از 1 کار امروز انجام شده'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('removing time range clears both endpoints, not just end',
      (tester) async {
    final api = PlannerFixture();
    final start = DateTime.now().add(const Duration(hours: 1));
    await dialog(tester, api, item: {
      'id': 'synthetic-plan',
      'title': 'برنامه ساختگی',
      'kind': 'task',
      'status': 'planned',
      'visibility': 'private',
      'version': 1,
      'starts_at': start.toUtc().toIso8601String(),
      'ends_at': start.add(const Duration(hours: 1)).toUtc().toIso8601String()
    });
    final range = find.byKey(const ValueKey('plan-time-range'));
    await tester.ensureVisible(range);
    await tester.tap(range);
    await tester.pumpAndSettle();
    await tester.tap(find.text('ذخیره'));
    await tester.pumpAndSettle();
    final body = api.writes.single['payload'] as Map;
    expect(body.containsKey('startsAt'), true);
    expect(body['startsAt'], isNull);
    expect(body.containsKey('endsAt'), true);
    expect(body['endsAt'], isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('tick changes one occurrence only and week day switches',
      (tester) async {
    final api = PlannerFixture();
    final now = DateTime.now();
    final tomorrow = now.add(const Duration(days: 1));
    api.rows.addAll([
      {
        'id': 'occurrence-a',
        'series_id': 'synthetic-series',
        'title': 'امروز ساختگی',
        'status': 'planned',
        'version': 1,
        'starts_at': now.toUtc().toIso8601String()
      },
      {
        'id': 'occurrence-b',
        'series_id': 'synthetic-series',
        'title': 'فردا ساختگی',
        'status': 'planned',
        'version': 1,
        'starts_at': tomorrow.toUtc().toIso8601String()
      },
    ]);
    await tester
        .pumpWidget(MaterialApp(home: Scaffold(body: PlannerPage(api: api))));
    await tester.pumpAndSettle();
    expect(find.text('امروز ساختگی'), findsOneWidget);
    expect(find.text('فردا ساختگی'), findsNothing);
    await tester.ensureVisible(find.byKey(const ValueKey('tick-occurrence-a')));
    await tester.tap(find.byKey(const ValueKey('tick-occurrence-a')));
    await tester.pumpAndSettle();
    expect(api.rows.firstWhere((row) => row['id'] == 'occurrence-a')['status'],
        'completed');
    expect(api.rows.firstWhere((row) => row['id'] == 'occurrence-b')['status'],
        'planned');
    if (tomorrow.weekday == DateTime.saturday) {
      await tester.tap(find.byTooltip('هفتهٔ بعد'));
      await tester.pumpAndSettle();
    }
    final day = find.byKey(ValueKey('planner-day-${tomorrow.weekday}'));
    await tester.ensureVisible(day);
    await tester.tap(day);
    await tester.pumpAndSettle();
    expect(find.text('فردا ساختگی'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
