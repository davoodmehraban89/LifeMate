import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lifemate/local_data_store.dart';
import 'package:lifemate/local_only_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _phase = String.fromEnvironment('PERSISTENCE_PHASE');
const _originalTitle = 'آزمون پایداری تکلیف روی دستگاه';
const _editedTitle = 'آزمون پایداری تکلیف روی دستگاه - ویرایش';
const _dueAt = '2030-10-15T12:00:00.000Z';
const _editedNotes = 'این تغییر باید پس از توقف اجباری باقی بماند.';

Map<String, dynamic> _record(
  Iterable<Map<String, dynamic>> items,
  String title,
) {
  final matches = items.where((item) => item['title'] == title).toList();
  expect(matches, hasLength(1),
      reason: 'Expected one durable test assignment.');
  expect(matches.single['id'], isA<String>());
  expect(matches.single['id'], isNotEmpty);
  return matches.single;
}

Future<Map<String, dynamic>> _readDisk() async {
  final preferences = SharedPreferencesAsync();
  final raw = await preferences.getString(LocalDataStore.key);
  expect(raw, isNotNull,
      reason: 'The Android preference must survive restart.');
  final data = jsonDecode(raw!) as Map<String, dynamic>;
  expect(data['version'], 1);
  expect(data['items'], hasLength(1));
  return data;
}

Iterable<Map<String, dynamic>> _savedItems(Map<String, dynamic> data) =>
    (data['items'] as List).map(
      (item) => Map<String, dynamic>.from(item as Map),
    );

Future<void> _expectEditedProfile(LocalOnlyApi api) async {
  final profile = await api.getProfile();
  expect(profile['display_name'], 'سارا');
  expect(profile['theme_preference'], 'boy_blue');
  expect(profile['profile_category'], 'girl_minor');
  expect(api.accessToken, isNull);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Android persistence phase: $_phase', (tester) async {
    expect(defaultTargetPlatform, TargetPlatform.android);
    expect(_phase, isIn(['create', 'update', 'archive', 'verify']));
    final api = LocalOnlyApi(category: 'girl_minor', displayName: 'آرام');
    expect(api.accessToken, isNull,
        reason: 'Local entry has no server session.');

    switch (_phase) {
      case 'create':
        final preferences = SharedPreferencesAsync();
        expect(
          await preferences.containsKey(LocalDataStore.key),
          isFalse,
          reason:
              'Create must start on a fresh emulator, without clearing data.',
        );
        expect(await api.listPlanItems(), isEmpty);
        final created = await api.createPlanItem({
          'kind': 'assignment',
          'title': _originalTitle,
          'dueAt': _dueAt,
          'visibility': 'private',
        });
        final visible = _record(await api.listPlanItems(), _originalTitle);
        final saved = _record(_savedItems(await _readDisk()), _originalTitle);
        expect(visible['id'], created['id']);
        expect(saved['id'], created['id']);
        expect(saved['kind'], 'assignment');
        expect(saved['due_at'], _dueAt);
        expect(saved['visibility'], 'private');
        expect(saved['status'], 'planned');
        expect((await api.getProfile())['display_name'], 'آرام');

      case 'update':
        final restored = _record(await api.listPlanItems(), _originalTitle);
        final id = restored['id'] as String;
        expect(restored['due_at'], _dueAt);
        expect(restored['status'], 'planned');
        await api.updatePlanItem(id, {
          'title': _editedTitle,
          'notes': _editedNotes,
          'status': 'in_progress',
        });
        await api.updateProfile(
            displayName: 'سارا', themePreference: 'boy_blue');
        final updated = _record(await api.listPlanItems(), _editedTitle);
        expect(updated['id'], id);
        expect(updated['notes'], _editedNotes);
        expect(updated['status'], 'in_progress');
        expect(updated['due_at'], _dueAt);
        await _expectEditedProfile(api);

      case 'archive':
        await _expectEditedProfile(api);
        final restored = _record(await api.listPlanItems(), _editedTitle);
        final id = restored['id'] as String;
        expect(restored['notes'], _editedNotes);
        expect(restored['status'], 'in_progress');
        await api.updatePlanItem(id, {'status': 'cancelled'});
        expect(await api.listPlanItems(), isEmpty);
        final archived = _record(_savedItems(await _readDisk()), _editedTitle);
        expect(archived['id'], id);
        expect(archived['status'], 'cancelled');

      case 'verify':
        await _expectEditedProfile(api);
        expect(await api.listPlanItems(), isEmpty);
        final data = await _readDisk();
        final archived = _record(_savedItems(data), _editedTitle);
        expect(archived['status'], 'cancelled');
        expect(archived['kind'], 'assignment');
        expect(archived['notes'], _editedNotes);
        expect(archived['due_at'], _dueAt);
        expect(archived['visibility'], 'private');
        final profile = data['profile'] as Map;
        expect(profile['display_name'], 'سارا');
        expect(profile['theme_preference'], 'boy_blue');
        expect(archived['owner_user_id'], profile['user_id']);
    }

    expect(api.accessToken, isNull);
  });
}
