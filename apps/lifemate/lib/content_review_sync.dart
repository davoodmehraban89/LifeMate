import 'dart:async';
import 'dart:convert';

import 'api.dart';
import 'offline_store.dart';
import 'learning_feedback_ui.dart' show feedbackCategories;

const contentReviewStatuses = <String, String>{
  'received': 'دریافت‌شده',
  'triaged': 'بررسی اولیه',
  'planned': 'در برنامه بررسی و توسعه',
  'declined': 'پذیرفته‌نشده',
  'released': 'انتشار ثبت‌شده',
};
const contentReviewTransitions = <String, List<String>>{
  'received': ['triaged', 'declined'],
  'triaged': ['planned', 'declined'],
  'planned': ['triaged', 'declined'],
  'declined': ['triaged'],
};
const _permissions = {'feedback.read', 'feedback.review', 'brief.prepare'};
final _uuidPattern = RegExp(r'^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$');
bool _uuid(dynamic value) => value is String && _uuidPattern.hasMatch(value);
bool _version(dynamic value) =>
    value is int && value > 0 && value <= 2147483647;
bool _date(dynamic value) =>
    value is String && DateTime.tryParse(value) != null;
bool _text(dynamic value, [int limit = 2000]) =>
    value is String &&
    value.trim().isNotEmpty &&
    value.length <= limit &&
    !value.contains('\u0000');
bool _exact(Map value, Set<String> keys) =>
    value.length == keys.length && value.keys.every(keys.contains);
Never _invalid() => throw const ApiException(502, 'invalid_content_response');
Map<String, dynamic> _freeze(Map value) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);

/// Reviewer mutations retain only IDs, versions and requested statuses. There
/// is no local inbox, permission cache, chosen summary or automatic offline send.
class ContentReviewSync {
  ContentReviewSync(this.api, {OfflineStore? store})
      : store = store ?? OfflineStore.forApi(api);
  final HttpIdentityApi api;
  final OfflineStore store;
  static final _tails = <String, Future<void>>{};

  Future<void> _scope() async {
    if (api.cacheNamespace != store.scope) {
      throw const ApiException(401, 'cache_scope_closed');
    }
    await store.readQueue(); // Rejects handles from an invalidated generation.
    if (api.cacheNamespace != store.scope) {
      throw const ApiException(401, 'cache_scope_closed');
    }
  }

  Future<T> _serial<T>(Future<T> Function() operation) async {
    final previous = _tails[store.scope];
    final release = Completer<void>();
    _tails[store.scope] = release.future;
    if (previous != null) await previous;
    try {
      await _scope();
      final result = await operation();
      await _scope();
      return result;
    } finally {
      if (identical(_tails[store.scope], release.future)) {
        _tails.remove(store.scope);
      }
      release.complete();
    }
  }

  Future<Set<String>> capabilities() async {
    await _scope();
    final response =
        await api.requestJson('GET', '/v1/me/content-capabilities');
    await _scope();
    if (!_exact(response, {'permissions'}) ||
        response['permissions'] is! List) {
      _invalid();
    }
    final values = response['permissions'] as List;
    if (values.any((value) => !_permissions.contains(value)) ||
        values.toSet().length != values.length) {
      _invalid();
    }
    return Set<String>.from(values);
  }

  Future<void> _require(String permission) async {
    final allowed = await capabilities();
    if (!allowed.contains('feedback.read') || !allowed.contains(permission)) {
      throw const ApiException(403, 'content_permission_required');
    }
  }

  Map<String, dynamic> _feedback(dynamic raw) {
    if (raw is! Map ||
        !_exact(raw, {
          'id',
          'unitId',
          'category',
          'summary',
          'status',
          'version',
          'createdAt',
          'updatedAt'
        }) ||
        !_uuid(raw['id']) ||
        (raw['unitId'] != null && !_uuid(raw['unitId'])) ||
        !feedbackCategories.containsKey(raw['category']) ||
        !_text(raw['summary'], 1000) ||
        !contentReviewStatuses.containsKey(raw['status']) ||
        !_version(raw['version']) ||
        !_date(raw['createdAt']) ||
        !_date(raw['updatedAt'])) {
      _invalid();
    }
    return _freeze(raw);
  }

  Future<Map<String, dynamic>> inbox({String? status, String? cursor}) async {
    await _scope();
    if ((status != null && !contentReviewStatuses.containsKey(status)) ||
        (cursor != null && !_uuid(cursor))) {
      throw const ApiException(400, 'invalid_content_query');
    }
    final query = Uri(queryParameters: {
      'limit': '20',
      if (status != null) 'status': status,
      if (cursor != null) 'cursor': cursor
    }).query;
    final response =
        await api.requestJson('GET', '/v1/content-review/feedback?$query');
    await _scope();
    if (!_exact(response, {'feedback', 'nextCursor', 'total'}) ||
        response['feedback'] is! List ||
        (response['feedback'] as List).length > 20 ||
        response['total'] is! int ||
        response['total'] < 0 ||
        (response['nextCursor'] != null && !_uuid(response['nextCursor']))) {
      _invalid();
    }
    final rows = (response['feedback'] as List).map(_feedback).toList();
    if (rows.map((row) => row['id']).toSet().length != rows.length ||
        rows.any((row) => status != null && row['status'] != status) ||
        response['total'] < rows.length) {
      _invalid();
    }
    return {...response, 'feedback': rows};
  }

  Map<String, dynamic> _reviewBody(Map value) {
    if (!_exact(value, {'mutationId', 'expectedVersion', 'status'}) ||
        !_uuid(value['mutationId']) ||
        !_version(value['expectedVersion']) ||
        !const {'triaged', 'planned', 'declined'}.contains(value['status'])) {
      throw const ApiException(400, 'invalid_review_mutation');
    }
    return _freeze(value);
  }

  Map<String, dynamic> _briefBody(Map value) {
    if (!_exact(value, {'mutationId', 'feedback'}) ||
        !_uuid(value['mutationId']) ||
        value['feedback'] is! List ||
        (value['feedback'] as List).isEmpty ||
        (value['feedback'] as List).length > 20) {
      throw const ApiException(400, 'invalid_brief_mutation');
    }
    final ids = <String>{};
    for (final row in value['feedback'] as List) {
      if (row is! Map ||
          !_exact(row, {'id', 'expectedVersion'}) ||
          !_uuid(row['id']) ||
          !_version(row['expectedVersion']) ||
          !ids.add(row['id'] as String)) {
        throw const ApiException(400, 'invalid_brief_mutation');
      }
    }
    return _freeze(value);
  }

  Future<List<Map<String, dynamic>>> pending() async {
    await _scope();
    final rows = (await store.readQueue())
        .where((row) =>
            row['entityType'] == 'content_review' ||
            row['entityType'] == 'content_brief')
        .toList();
    await _scope();
    return rows;
  }

  Future<Map<String, dynamic>> review(String id, Map<String, dynamic> body) {
    final frozen = _reviewBody(body);
    if (!_uuid(id)) throw const ApiException(400, 'invalid_review_mutation');
    return _serial(() async {
      await _require('feedback.review'); // No new offline reviewer change.
      final mutation = {
        'id': frozen['mutationId'],
        'entityId': id,
        'entityType': 'content_review',
        'operation': 'review',
        'payload': frozen
      };
      await store.enqueue(mutation);
      return _send(mutation);
    });
  }

  Future<Map<String, dynamic>> prepareBrief(Map<String, dynamic> body) {
    final frozen = _briefBody(body);
    return _serial(() async {
      await _require('brief.prepare');
      final mutation = {
        'id': frozen['mutationId'],
        'entityId': frozen['mutationId'],
        'entityType': 'content_brief',
        'operation': 'prepare',
        'payload': frozen
      };
      await store.enqueue(mutation);
      return _send(mutation);
    });
  }

  Future<Map<String, dynamic>> retry(Map<String, dynamic> pending) =>
      _serial(() async {
        final stored = (await this.pending())
            .where((row) => row['id'] == pending['id'])
            .firstOrNull;
        if (stored == null || jsonEncode(stored) != jsonEncode(pending)) {
          throw const ApiException(409, 'content_pending_changed');
        }
        await _require(stored['entityType'] == 'content_review'
            ? 'feedback.review'
            : 'brief.prepare');
        return _send(stored);
      });

  Future<Map<String, dynamic>> _send(Map<String, dynamic> mutation) async {
    final review = mutation['entityType'] == 'content_review';
    final body = review
        ? _reviewBody(mutation['payload'] as Map)
        : _briefBody(mutation['payload'] as Map);
    await _scope();
    final response = await api.requestJson(
        review ? 'PATCH' : 'POST',
        review
            ? '/v1/content-review/feedback/${Uri.encodeComponent(mutation['entityId'] as String)}'
            : '/v1/content-review/briefs',
        body: body);
    await _scope();
    final ack = response['acknowledgement'];
    if (ack is! Map ||
        !_exact(
            ack, {'mutationId', review ? 'feedbackId' : 'briefId', 'status'}) ||
        ack['mutationId'] != mutation['id'] ||
        !const {'accepted', 'already_applied'}.contains(ack['status'])) {
      _invalid();
    }
    String acceptedAt;
    Map<String, dynamic>? brief;
    if (review) {
      if (!_exact(response, {'feedback', 'acknowledgement'})) _invalid();
      final row = _feedback(response['feedback']);
      if (row['id'] != mutation['entityId'] ||
          ack['feedbackId'] != row['id'] ||
          row['version'] < (body['expectedVersion'] as int) + 1 ||
          (ack['status'] == 'accepted' &&
              (row['version'] != (body['expectedVersion'] as int) + 1 ||
                  row['status'] != body['status']))) {
        _invalid();
      }
      acceptedAt = row['updatedAt'] as String;
      // Do not return/store the summary in the durable mutation result.
    } else {
      if (!_exact(response, {'brief', 'acknowledgement'})) _invalid();
      brief = _brief(response['brief']);
      if (ack['briefId'] != brief['id'] ||
          brief['sourceCount'] != (body['feedback'] as List).length) {
        _invalid();
      }
      acceptedAt = brief['createdAt'] as String;
    }
    await store.acknowledge(mutation['id'] as String, acceptedAt: acceptedAt);
    return {'acknowledgement': _freeze(ack), if (brief != null) 'brief': brief};
  }

  Map<String, dynamic> _brief(dynamic raw) {
    if (raw is! Map ||
        !_exact(raw, {
          'id',
          'title',
          'createdAt',
          'sourceCount',
          'categories',
          'units',
          'tasks',
          'notice'
        }) ||
        !_uuid(raw['id']) ||
        raw['title'] != 'پیشنهاد بررسی و توسعه محتوای آموزشی' ||
        !_date(raw['createdAt']) ||
        raw['sourceCount'] is! int ||
        raw['sourceCount'] < 1 ||
        raw['sourceCount'] > 20 ||
        raw['categories'] is! List ||
        raw['units'] is! List ||
        (raw['units'] as List).length > raw['sourceCount'] ||
        raw['tasks'] is! List ||
        jsonEncode(raw['tasks']) !=
            jsonEncode(const [
              'نسخه رسمی کتاب و هدف یادگیری این درس را بررسی کنید.',
              'محتوای پیشنهادی و سؤال‌های تمرینی را به‌طور کامل بازبینی کنید.',
              'برای تغییر پیشنهادی معیار پذیرش، آزمون و PR مستقل تهیه کنید.',
              'انتشار محتوا و استقرار فقط پس از بازبینی و مجوز جداگانه انجام شود.'
            ]) ||
        raw['notice'] !=
            'این پیشنهاد ساختاری فاقد متن بازخورد و اطلاعات خصوصی است؛ تأیید محتوا یا دستور انتشار نیست.') {
      _invalid();
    }
    var count = 0;
    final categories = <String>{};
    for (final row in raw['categories'] as List) {
      if (row is! Map ||
          !_exact(row, {'category', 'count'}) ||
          !feedbackCategories.containsKey(row['category']) ||
          row['count'] is! int ||
          row['count'] < 1 ||
          !categories.add(row['category'] as String)) {
        _invalid();
      }
      count += row['count'] as int;
    }
    if (count != raw['sourceCount']) _invalid();
    final units = <String>{};
    for (final row in raw['units'] as List) {
      if (row is! Map ||
          !_exact(row, {
            'id',
            'title',
            'bookCode',
            'bookTitle',
            'gradeLevel',
            'trackCode',
            'editionYear',
            'editionStatus'
          }) ||
          !_uuid(row['id']) ||
          !units.add(row['id'] as String) ||
          !_text(row['title']) ||
          !_text(row['bookTitle']) ||
          !_text(row['bookCode'], 80) ||
          row['gradeLevel'] is! int ||
          row['gradeLevel'] < 1 ||
          row['gradeLevel'] > 12 ||
          row['trackCode'] is! List ||
          (row['trackCode'] as List).any((value) => !const {
                'common',
                'math',
                'experimental',
                'humanities'
              }.contains(value)) ||
          (row['editionYear'] != null && !_text(row['editionYear'], 40)) ||
          !const {'verified', 'unverified'}.contains(row['editionStatus'])) {
        _invalid();
      }
    }
    return _freeze(raw);
  }

  Future<Map<String, dynamic>> readBrief(String id) async {
    if (!_uuid(id)) throw const ApiException(400, 'invalid_brief_id');
    await _require('brief.prepare');
    final response = await api.requestJson(
        'GET', '/v1/content-review/briefs/${Uri.encodeComponent(id)}');
    await _scope();
    if (!_exact(response, {'brief'})) _invalid();
    final brief = _brief(response['brief']);
    if (brief['id'] != id) _invalid();
    return brief;
  }
}
