import 'api.dart';
import 'local_data_store.dart';

/// Real device storage, without login, networking, family sharing or server sync.
/// The authenticated application continues to use HttpIdentityApi exclusively.
class LocalOnlyApi implements IdentityApi {
  LocalOnlyApi({required String category, required String displayName})
      : store = LocalDataStore(category: category, displayName: displayName);

  final LocalDataStore store;

  @override
  String? get accessToken => null;

  @override
  Future<Map<String, dynamic>> getProfile() async =>
      Map<String, dynamic>.from((await store.read())['profile'] as Map);

  @override
  Future<Map<String, dynamic>> updateProfile({
    String? displayName,
    String? birthDate,
    String? themePreference,
  }) async {
    if (birthDate != null ||
        (displayName != null &&
            (displayName.trim().isEmpty || displayName.trim().length > 120)) ||
        (themePreference != null &&
            !LocalDataStore.themes.contains(themePreference))) {
      throw const ApiException(400, 'local_invalid_profile');
    }
    return store.mutate((data) {
      final profile = data['profile'] as Map<String, dynamic>;
      if (displayName != null) profile['display_name'] = displayName.trim();
      if (themePreference != null)
        profile['theme_preference'] = themePreference;
      return Map<String, dynamic>.from(profile);
    });
  }

  @override
  Future<List<Map<String, dynamic>>> listFamilies() async => [];

  Map<String, dynamic> _fields(Map<String, dynamic> input) {
    const allowed = {
      'kind',
      'title',
      'notes',
      'status',
      'priority',
      'startsAt',
      'dueAt',
      'visibility'
    };
    if (input.isEmpty ||
        input.keys.any((key) => !allowed.contains(key)) ||
        (input.containsKey('title') &&
            (input['title'] is! String ||
                (input['title'] as String).trim().isEmpty ||
                (input['title'] as String).trim().length > 240)) ||
        (input.containsKey('kind') &&
            !LocalDataStore.kinds.contains(input['kind'])) ||
        (input.containsKey('status') &&
            !LocalDataStore.statuses.contains(input['status'])) ||
        (input.containsKey('priority') &&
            !{'low', 'normal', 'high', 'urgent'}.contains(input['priority'])) ||
        (input.containsKey('visibility') && input['visibility'] != 'private') ||
        (input['notes'] != null &&
            (input['notes'] is! String ||
                (input['notes'] as String).length > 10000))) {
      throw const ApiException(400, 'local_invalid_item');
    }
    final fields = <String, dynamic>{};
    for (final entry in input.entries) {
      if (entry.key == 'startsAt' || entry.key == 'dueAt') {
        final value = entry.value;
        final date = value == null ? null : DateTime.tryParse(value.toString());
        if (value != null && date == null)
          throw const ApiException(400, 'local_invalid_item');
        fields[entry.key == 'startsAt' ? 'starts_at' : 'due_at'] =
            date?.toUtc().toIso8601String();
      } else {
        fields[entry.key] =
            entry.key == 'title' ? (entry.value as String).trim() : entry.value;
      }
    }
    return fields;
  }

  void _validateDates(Map<String, dynamic> item) {
    final start = DateTime.tryParse(item['starts_at']?.toString() ?? '');
    final due = DateTime.tryParse(item['due_at']?.toString() ?? '');
    if (start != null && due != null && due.isBefore(start)) {
      throw const ApiException(400, 'local_invalid_item');
    }
  }

  @override
  Future<Map<String, dynamic>> createPlanItem(
      Map<String, dynamic> input) async {
    final fields = _fields(input);
    if (!fields.containsKey('title') || !fields.containsKey('kind')) {
      throw const ApiException(400, 'local_invalid_item');
    }
    _validateDates(fields);
    return store.mutate((data) {
      final now = DateTime.now().toUtc().toIso8601String();
      final item = <String, dynamic>{
        'id': LocalDataStore.newId(),
        'owner_user_id': (data['profile'] as Map)['user_id'],
        'status': 'planned',
        'priority': 'normal',
        'visibility': 'private',
        'created_at': now,
        'updated_at': now,
        ...fields,
      };
      (data['items'] as List).add(item);
      return Map<String, dynamic>.from(item);
    });
  }

  @override
  Future<Map<String, dynamic>> updatePlanItem(
      String itemId, Map<String, dynamic> input) async {
    final fields = _fields(input);
    return store.mutate((data) {
      final items = data['items'] as List;
      final index = items.indexWhere((item) => (item as Map)['id'] == itemId);
      if (index < 0) throw const ApiException(404, 'local_item_not_found');
      final item = <String, dynamic>{
        ...Map<String, dynamic>.from(items[index] as Map),
        ...fields
      };
      _validateDates(item);
      item['updated_at'] = DateTime.now().toUtc().toIso8601String();
      items[index] = item;
      return Map<String, dynamic>.from(item);
    });
  }

  @override
  Future<List<Map<String, dynamic>>> listPlanItems(
      {DateTime? from, DateTime? to, String? kind}) async {
    final data = await store.read();
    final items = (data['items'] as List)
        .map((item) => Map<String, dynamic>.from(item as Map));
    return items.where((item) {
      if (item['status'] == 'cancelled' ||
          (kind != null && kind != item['kind'])) return false;
      final date = DateTime.tryParse(
          (item['due_at'] ?? item['starts_at'])?.toString() ?? '');
      // Undated records remain visible in the planner; dates use [from, to).
      if (date == null) return true;
      return (from == null || !date.isBefore(from)) &&
          (to == null || date.isBefore(to));
    }).toList();
  }

  @override
  Future<List<Map<String, dynamic>>> getToday(
          {required DateTime from, required DateTime to}) async =>
      (await listPlanItems(from: from, to: to))
          .where((item) =>
              item['status'] != 'completed' &&
              (item['due_at'] != null || item['starts_at'] != null))
          .toList();

  // Unsupported flows fail visibly instead of manufacturing successful records.
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw const ApiException(409, 'local_feature_unavailable');
}
