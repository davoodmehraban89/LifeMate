import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class OfflineStore {
  OfflineStore._();
  static final OfflineStore instance = OfflineStore._();

  static const _todayKey = 'phase3.today.cache';
  static const _plannerKey = 'phase3.planner.cache';
  static const _schoolKey = 'phase3.school.cache';
  static const _queueKey = 'phase3.sync.queue';

  Future<void> writeList(String key, List<Map<String, dynamic>> value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(value));
  }

  Future<List<Map<String, dynamic>>> readList(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> cacheToday(List<Map<String, dynamic>> items) =>
      writeList(_todayKey, items);
  Future<List<Map<String, dynamic>>> readToday() => readList(_todayKey);

  Future<void> cachePlanner(List<Map<String, dynamic>> items) =>
      writeList(_plannerKey, items);
  Future<List<Map<String, dynamic>>> readPlanner() => readList(_plannerKey);

  Future<void> cacheSchool(List<Map<String, dynamic>> items) =>
      writeList(_schoolKey, items);
  Future<List<Map<String, dynamic>>> readSchool() => readList(_schoolKey);

  Future<List<Map<String, dynamic>>> readQueue() => readList(_queueKey);

  Future<void> enqueue(Map<String, dynamic> mutation) async {
    final queue = await readQueue();
    queue.add(mutation);
    await writeList(_queueKey, queue);
  }

  Future<void> removeQueued(Set<String> ids) async {
    final queue = await readQueue();
    await writeList(
      _queueKey,
      queue.where((item) => !ids.contains(item['id']?.toString())).toList(),
    );
  }
}
