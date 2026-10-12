import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'api.dart';
import 'offline_store.dart';
import 'plan_sync.dart' show newMutationId;

const _schoolTypes = ['contexts', 'years', 'terms'];
final _schoolUuid = RegExp(r'^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$',
    caseSensitive: false);
String _latinDigits(String value) {
  const all = '۰۱۲۳۴۵۶۷۸۹٠١٢٣٤٥٦٧٨٩';
  return value.trim().split('').map((c) {
    final n = all.indexOf(c);
    return n < 0 ? c : '${n % 10}';
  }).join();
}

String _faDigits(String value) => value
    .split('')
    .map((c) => int.tryParse(c) == null ? c : '۰۱۲۳۴۵۶۷۸۹'[int.parse(c)])
    .join();
String _dateText(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
bool _schoolDate(dynamic value) =>
    value is String &&
    RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) &&
    !value.startsWith('0000-') &&
    DateTime.tryParse(value) != null &&
    _dateText(DateTime.parse(value)) == value;
bool _schoolTime(dynamic value) =>
    value is String &&
    RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(value) &&
    DateTime.tryParse(value) != null;

/// The existing account/endpoint queue stores intent before delivery. Setup
/// progresses only after the preceding parent has a canonical server ACK.
class SchoolLifecycleSync {
  SchoolLifecycleSync(this.api, {OfflineStore? store})
      : store = store ?? OfflineStore.forApi(api);
  final HttpIdentityApi api;
  final OfflineStore store;
  static final _tails = <String, Future<void>>{};
  void _scope() {
    if (api.cacheNamespace != store.scope) {
      throw const ApiException(401, 'cache_scope_closed');
    }
  }

  Future<T> _serial<T>(Future<T> Function() run) async {
    final before = _tails[store.scope], release = Completer<void>();
    _tails[store.scope] = release.future;
    if (before != null) await before;
    try {
      _scope();
      await store.readQueue();
      final value = await run();
      _scope();
      return value;
    } finally {
      if (identical(_tails[store.scope], release.future)) {
        _tails.remove(store.scope);
      }
      release.complete();
    }
  }

  Map<String, dynamic> _entity(String type, dynamic raw) {
    if (raw is! Map ||
        raw['id'] is! String ||
        !_schoolUuid.hasMatch(raw['id']) ||
        raw['title'] is! String ||
        (raw['title'] as String).trim().isEmpty ||
        raw['version'] is! int ||
        raw['version'] < 1 ||
        raw['active'] is! bool ||
        !_schoolTime(raw['created_at']) ||
        !_schoolTime(raw['updated_at'])) {
      throw const ApiException(502, 'invalid_school_entity');
    }
    if (type == 'contexts' &&
        (raw['user_id'] != api.currentUserId ||
            !['student', 'work', 'personal'].contains(raw['kind']))) {
      throw const ApiException(502, 'invalid_school_entity');
    }
    if (type != 'contexts' &&
        (!_schoolDate(raw['starts_on']) ||
            !_schoolDate(raw['ends_on']) ||
            (raw['ends_on'] as String).compareTo(raw['starts_on'] as String) <
                0)) {
      throw const ApiException(502, 'invalid_school_entity');
    }
    final parent = type == 'years'
        ? raw['life_context_id']
        : type == 'terms'
            ? raw['academic_year_id']
            : null;
    if (type != 'contexts' &&
        (parent is! String ||
            !_schoolUuid.hasMatch(parent) ||
            (type == 'years' && raw['student_user_id'] != api.currentUserId))) {
      throw const ApiException(502, 'invalid_school_entity');
    }
    return Map<String, dynamic>.from(raw);
  }

  Future<List<Map<String, dynamic>>> pending() async {
    _scope();
    final rows = await store.readQueue();
    _scope();
    return rows
        .where((row) => _schoolTypes
            .any((type) => row['entityType'] == 'school_lifecycle_$type'))
        .toList();
  }

  Future<Map<String, dynamic>> read() => _serial(() async {
        var offline = false;
        final result = <String, dynamic>{};
        try {
          final raw = await api.requestJson('GET', '/v1/school/lifecycle');
          _scope();
          if (!_schoolTime(raw['fetchedAt'])) {
            throw const ApiException(502, 'invalid_school_snapshot');
          }
          for (final type in _schoolTypes) {
            if (raw[type] is! List || (raw[type] as List).length > 500) {
              throw const ApiException(502, 'invalid_school_snapshot');
            }
            final rows =
                (raw[type] as List).map((row) => _entity(type, row)).toList();
            if (rows.map((row) => row['id']).toSet().length != rows.length) {
              throw const ApiException(502, 'invalid_school_snapshot');
            }
            result[type] = rows;
          }
          final contexts = {
            for (final row in result['contexts'] as List) row['id']
          };
          final years = {for (final row in result['years'] as List) row['id']};
          if ((result['years'] as List)
                  .any((row) => !contexts.contains(row['life_context_id'])) ||
              (result['terms'] as List)
                  .any((row) => !years.contains(row['academic_year_id']))) {
            throw const ApiException(502, 'invalid_school_snapshot');
          }
          for (final type in _schoolTypes) {
            await store.writeList('school_lifecycle_$type',
                result[type] as List<Map<String, dynamic>>);
          }
          await store.writeList('school_lifecycle_received', [
            {'fetchedAt': raw['fetchedAt']}
          ]);
        } catch (error) {
          _scope();
          if (!isOfflineFailure(error)) rethrow;
          offline = true;
          for (final type in _schoolTypes) {
            result[type] = (await store.readList('school_lifecycle_$type'))
                .map((row) => _entity(type, row))
                .toList();
          }
        }
        final received = await store.readList('school_lifecycle_received');
        return {
          ...result,
          'offline': offline,
          'fetchedAt': received.firstOrNull?['fetchedAt'],
          'pending': await pending()
        };
      });
  void _validate(String type, Map<String, dynamic> body) {
    if (!_schoolTypes.contains(type) ||
        body['mutationId'] is! String ||
        !_schoolUuid.hasMatch(body['mutationId']) ||
        body['entityId'] is! String ||
        !_schoolUuid.hasMatch(body['entityId']) ||
        !['create', 'update', 'archive'].contains(body['operation']) ||
        body['expectedVersion'] is! int ||
        body['expectedVersion'] < 0 ||
        body['expectedVersion'] > 2147483646 ||
        (body['operation'] == 'create'
            ? body['expectedVersion'] != 0
            : body['expectedVersion'] < 1) ||
        body['data'] is! Map) {
      throw const ApiException(400, 'invalid_school_mutation');
    }
    final data = body['data'] as Map, operation = body['operation'];
    final keys = operation == 'archive'
        ? <String>[]
        : type == 'contexts'
            ? ['title', 'kind']
            : [
                'title',
                'startsOn',
                'endsOn',
                if (operation == 'create')
                  type == 'years' ? 'lifeContextId' : 'academicYearId'
              ];
    if (data.keys.any((key) => !keys.contains(key)) ||
        (operation == 'create' && keys.any((key) => !data.containsKey(key))) ||
        (operation == 'update' && data.isEmpty)) {
      throw const ApiException(400, 'invalid_school_input');
    }
    if ((data.containsKey('title') &&
            (data['title'] is! String ||
                (data['title'] as String).trim().isEmpty ||
                (data['title'] as String).length > 120)) ||
        (data.containsKey('kind') &&
            !['student', 'work', 'personal'].contains(data['kind']))) {
      throw const ApiException(400, 'invalid_school_input');
    }
    for (final key in ['startsOn', 'endsOn']) {
      if (data.containsKey(key) && !_schoolDate(data[key])) {
        throw const ApiException(400, 'invalid_school_date');
      }
    }
    if (data['startsOn'] is String &&
        data['endsOn'] is String &&
        (data['endsOn'] as String).compareTo(data['startsOn'] as String) < 0) {
      throw const ApiException(400, 'invalid_school_date');
    }
    for (final key in ['lifeContextId', 'academicYearId']) {
      if (data.containsKey(key) &&
          (data[key] is! String || !_schoolUuid.hasMatch(data[key]))) {
        throw const ApiException(400, 'invalid_school_input');
      }
    }
  }

  Future<Map<String, dynamic>> mutate(
      String type, String operation, Map<String, dynamic> data,
      {String? entityId, int expectedVersion = 0}) {
    final normalized = {...data};
    if (normalized['title'] is String) {
      normalized['title'] = (normalized['title'] as String).trim();
    }
    for (final key in ['startsOn', 'endsOn']) {
      if (normalized[key] is String) {
        normalized[key] = _latinDigits(normalized[key]);
      }
    }
    final body = Map<String, dynamic>.from(jsonDecode(jsonEncode({
      'mutationId': newMutationId(),
      'entityId': entityId ?? newMutationId(),
      'operation': operation,
      'expectedVersion': expectedVersion,
      'data': normalized
    })) as Map);
    _validate(type, body);
    return _serial(() async {
      if ((await pending()).any((row) => row['entityId'] == body['entityId'])) {
        throw const ApiException(409, 'school_sync_pending');
      }
      final record = {
        'id': body['mutationId'],
        'entityId': body['entityId'],
        'entityType': 'school_lifecycle_$type',
        'operation': operation,
        'expectedVersion': expectedVersion,
        'payload': body
      };
      await store.enqueue(record);
      try {
        return {'queued': false, 'entity': await _send(type, record)};
      } catch (error) {
        _scope();
        if (!isOfflineFailure(error)) rethrow;
        return {'queued': true, 'entityId': body['entityId']};
      }
    });
  }

  Future<Map<String, dynamic>> _send(
      String type, Map<String, dynamic> record) async {
    final body = Map<String, dynamic>.from(record['payload'] as Map);
    _validate(type, body);
    if (record['id'] != body['mutationId'] ||
        record['entityId'] != body['entityId'] ||
        record['entityType'] != 'school_lifecycle_$type' ||
        record['operation'] != body['operation'] ||
        record['expectedVersion'] != body['expectedVersion']) {
      throw const ApiException(422, 'invalid_school_mutation');
    }
    late Map<String, dynamic> raw;
    try {
      raw = await api.requestJson(
          'POST', '/v1/school/lifecycle/$type/mutations',
          body: body);
      _scope();
    } catch (error) {
      _scope();
      if (error is ApiException &&
          [400, 404, 409, 422].contains(error.statusCode)) {
        await store.markQueued(record['id'] as String,
            error.statusCode == 409 ? 'conflict' : 'rejected',
            error: error.code);
      }
      rethrow;
    }
    final row = _entity(type, raw['entity']), ack = raw['acknowledgement'];
    if (row['id'] != body['entityId'] ||
        ack is! Map ||
        ack['mutationId'] != body['mutationId'] ||
        ack['entityId'] != body['entityId'] ||
        ack['entityType'] != type ||
        ack['operation'] != body['operation'] ||
        !['accepted', 'already_applied'].contains(ack['status']) ||
        ack['appliedVersion'] != body['expectedVersion'] + 1 ||
        row['version'] < ack['appliedVersion'] ||
        !_schoolTime(ack['acceptedAt'])) {
      throw const ApiException(502, 'invalid_school_acknowledgement');
    }
    if (row['version'] == ack['appliedVersion']) {
      const columns = {
        'title': 'title',
        'kind': 'kind',
        'startsOn': 'starts_on',
        'endsOn': 'ends_on',
        'lifeContextId': 'life_context_id',
        'academicYearId': 'academic_year_id'
      };
      if ((body['operation'] == 'archive'
              ? row['active'] != false
              : row['active'] != true) ||
          (body['data'] as Map)
              .entries
              .any((entry) => row[columns[entry.key]] != entry.value)) {
        throw const ApiException(502, 'invalid_school_acknowledgement');
      }
    }
    await store.acknowledge(record['id'] as String,
        item: row,
        acceptedAt: ack['acceptedAt'] as String,
        cacheKey: 'school_lifecycle_$type');
    _scope();
    return row;
  }

  Future<void> flush() => _serial(() async {
        for (final record in await pending()) {
          if (['conflict', 'rejected'].contains(record['queueStatus'])) {
            throw const ApiException(409, 'school_sync_conflict');
          }
          final type = (record['entityType'] as String)
              .replaceFirst('school_lifecycle_', '');
          await _send(type, record);
        }
      });
  Future<void> useServer(String type, String entityId) async {
    final snapshot = await read();
    if (snapshot['offline'] == true) {
      throw const ApiException(409, 'server_snapshot_required');
    }
    await _serial(() async {
      final row = (snapshot[type] as List<Map<String, dynamic>>)
          .where((row) => row['id'] == entityId)
          .firstOrNull;
      await store.discardEntityChanges(entityId,
          serverItem: row,
          entityType: 'school_lifecycle_$type',
          cacheKey: 'school_lifecycle_$type');
    });
  }
}

String _schoolError(Object error) {
  if (isOfflineFailure(error)) {
    return 'اتصال برقرار نیست؛ تغییرهای ذخیره‌شده هنوز تأیید سرور ندارند.';
  }
  if (error is ApiException) {
    if ([401, 403].contains(error.statusCode)) {
      return 'نشست یا دسترسی معتبر نیست؛ اطلاعات قبلی از صفحه پاک شد.';
    }
    if (error.statusCode == 409) {
      return 'تغییر معلق، تعارض نسخه یا محدودیت اطلاعات وابسته وجود دارد. وضعیت سرور را بررسی کن.';
    }
    if (error.statusCode == 400) {
      return 'عنوان، تاریخ و محدوده سال یا نیمسال را بررسی کن.';
    }
  }
  return 'عملیات با پاسخ معتبر سرور تأیید نشد. وضعیت را تازه کن.';
}

class SchoolManagementPage extends StatefulWidget {
  const SchoolManagementPage({super.key, required this.api});
  final HttpIdentityApi api;
  @override
  State<SchoolManagementPage> createState() => _SchoolManagementPageState();
}

class _SchoolManagementPageState extends State<SchoolManagementPage> {
  late final SchoolLifecycleSync sync;
  Map<String, dynamic>? snapshot;
  List<Map<String, dynamic>> subjects = [], classes = [];
  bool busy = false, childrenFresh = false;
  String? error, notice;
  int epoch = 0;
  @override
  void initState() {
    super.initState();
    sync = SchoolLifecycleSync(widget.api);
    load();
  }

  @override
  void dispose() {
    epoch++;
    super.dispose();
  }

  bool get writable => !busy && snapshot != null;
  Future<void> load({bool retry = false}) async {
    if (busy) return;
    final mine = ++epoch;
    setState(() {
      busy = true;
      childrenFresh = false;
    });
    try {
      if (retry) await sync.flush();
      final value = await sync.read();
      if (!mounted || mine != epoch) return;
      setState(() {
        snapshot = value;
        error = null;
        subjects = [];
        classes = [];
      });
      if (value['offline'] != true) {
        final overview =
            await widget.api.getSchoolOverview(widget.api.currentUserId!);
        final timetable =
            await widget.api.getTimetable(widget.api.currentUserId!);
        if (!mounted ||
            mine != epoch ||
            widget.api.cacheNamespace != sync.store.scope) {
          return;
        }
        setState(() {
          subjects = (overview['subjects'] as List? ?? [])
              .map((raw) => Map<String, dynamic>.from(raw as Map))
              .toList();
          classes = timetable;
          childrenFresh = true;
        });
      }
    } catch (failure) {
      if (mounted && mine == epoch) {
        setState(() {
          if (failure is ApiException &&
              [401, 403].contains(failure.statusCode)) {
            snapshot = null;
            subjects = [];
            classes = [];
          }
          notice = _schoolError(failure);
        });
      }
    } finally {
      if (mounted && mine == epoch) setState(() => busy = false);
    }
  }

  List<Map<String, dynamic>> rows(String type) =>
      (snapshot?[type] as List? ?? [])
          .map((raw) => Map<String, dynamic>.from(raw as Map))
          .toList();
  bool contextActive(String id) => rows('contexts').any((row) =>
      row['id'] == id && row['active'] == true && row['kind'] == 'student');
  bool yearActive(String id) => rows('years').any((row) =>
      row['id'] == id &&
      row['active'] == true &&
      contextActive(row['life_context_id'].toString()));
  bool termActive(String id) => rows('terms').any((row) =>
      row['id'] == id &&
      row['active'] == true &&
      yearActive(row['academic_year_id'].toString()));

  Future<void> editLifecycle(String type, [Map<String, dynamic>? row]) async {
    if (!writable) return;
    final title = TextEditingController(text: row?['title']?.toString() ?? '');
    final starts =
        TextEditingController(text: row?['starts_on']?.toString() ?? '');
    final ends = TextEditingController(text: row?['ends_on']?.toString() ?? '');
    final draftId = row?['id']?.toString() ?? newMutationId();
    var attempted = false;
    var kind = row?['kind']?.toString() ?? 'student';
    String? parentId;
    final parents = type == 'years'
        ? rows('contexts')
            .where((row) => row['active'] == true && row['kind'] == 'student')
            .toList()
        : rows('years')
            .where((row) => yearActive(row['id'].toString()))
            .toList();
    if (row != null) {
      parentId = row[type == 'years' ? 'life_context_id' : 'academic_year_id']
          ?.toString();
    }
    var saving = false;
    String? failure;
    final saved = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialog) => StatefulBuilder(builder: (context, local) {
              Future<void> pick(TextEditingController target) async {
                final initial = DateTime.tryParse(_latinDigits(target.text));
                final selected = await showDatePicker(
                    context: context,
                    initialDate: initial != null &&
                            initial.year >= 1900 &&
                            initial.year <= 2200
                        ? initial
                        : DateTime.now(),
                    firstDate: DateTime(1900),
                    lastDate: DateTime(2200, 12, 31));
                if (selected != null) {
                  local(() => target.text = _dateText(selected));
                }
              }

              return AlertDialog(
                  title: Text(row == null
                      ? 'ایجاد ${_typeLabel(type)}'
                      : 'ویرایش ${_typeLabel(type)}'),
                  content: SingleChildScrollView(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                    TextField(
                        controller: title,
                        enabled: !saving,
                        maxLength: 120,
                        decoration: const InputDecoration(labelText: 'عنوان')),
                    if (type == 'contexts')
                      DropdownButtonFormField<String>(
                          initialValue: kind,
                          decoration:
                              const InputDecoration(labelText: 'نوع زمینه'),
                          items: const [
                            DropdownMenuItem(
                                value: 'student', child: Text('مدرسه')),
                            DropdownMenuItem(value: 'work', child: Text('کار')),
                            DropdownMenuItem(
                                value: 'personal', child: Text('شخصی'))
                          ],
                          onChanged: saving
                              ? null
                              : (value) => local(() => kind = value!)),
                    if (type != 'contexts' && row == null)
                      DropdownButtonFormField<String>(
                          initialValue: parentId,
                          decoration: InputDecoration(
                              labelText:
                                  type == 'years' ? 'مدرسه فعال' : 'سال فعال'),
                          items: parents
                              .map((parent) => DropdownMenuItem(
                                  value: parent['id'].toString(),
                                  child: Text(parent['title'].toString())))
                              .toList(),
                          onChanged: saving
                              ? null
                              : (value) => local(() => parentId = value)),
                    if (type != 'contexts') ...[
                      const Text(
                          'تاریخ میلادی: YYYY-MM-DD؛ تاریخ شروع و پایان را خودت انتخاب کن.'),
                      TextField(
                          controller: starts,
                          enabled: !saving,
                          textDirection: TextDirection.ltr,
                          decoration: InputDecoration(
                              labelText: 'تاریخ شروع میلادی',
                              suffixIcon: IconButton(
                                  onPressed: saving ? null : () => pick(starts),
                                  icon: const Icon(Icons.calendar_month)))),
                      TextField(
                          controller: ends,
                          enabled: !saving,
                          textDirection: TextDirection.ltr,
                          decoration: InputDecoration(
                              labelText: 'تاریخ پایان میلادی',
                              suffixIcon: IconButton(
                                  onPressed: saving ? null : () => pick(ends),
                                  icon: const Icon(Icons.calendar_month)))),
                    ],
                    if (failure != null)
                      Text(failure!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                  ])),
                  actions: [
                    TextButton(
                        onPressed:
                            saving ? null : () => Navigator.pop(dialog, false),
                        child: const Text('انصراف')),
                    FilledButton(
                        onPressed: saving
                            ? null
                            : () async {
                                if (type != 'contexts' &&
                                    row == null &&
                                    parentId == null) {
                                  local(() => failure =
                                      'ابتدا یک زمینه یا سال فعال انتخاب کن.');
                                  return;
                                }
                                local(() {
                                  saving = true;
                                  failure = null;
                                });
                                try {
                                  final data = {
                                    'title': title.text,
                                    if (type == 'contexts') 'kind': kind,
                                    if (type != 'contexts') ...{
                                      'startsOn': starts.text,
                                      'endsOn': ends.text
                                    },
                                    if (type != 'contexts' && row == null)
                                      type == 'years'
                                          ? 'lifeContextId'
                                          : 'academicYearId': parentId
                                  };
                                  attempted = true;
                                  final result = await sync.mutate(type,
                                      row == null ? 'create' : 'update', data,
                                      entityId: draftId,
                                      expectedVersion:
                                          row?['version'] as int? ?? 0);
                                  if (mounted) {
                                    notice = result['queued'] == true
                                        ? 'در دستگاه ذخیره شد؛ تا تأیید سرور، مرحله وابسته را نساز.'
                                        : 'تغییر با تأیید سرور ثبت شد.';
                                  }
                                  if (dialog.mounted) {
                                    Navigator.pop(dialog, true);
                                  }
                                } catch (e) {
                                  if (dialog.mounted) {
                                    local(() {
                                      failure = _schoolError(e);
                                      saving = false;
                                    });
                                  }
                                }
                              },
                        child: Text(saving ? 'در حال ثبت…' : 'ثبت')),
                  ]);
            }));
    title.dispose();
    starts.dispose();
    ends.dispose();
    if ((saved == true || attempted) && mounted) await load();
  }

  Future<void> archive(String type, Map<String, dynamic> row) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
                title: const Text('بایگانی'),
                content: const Text(
                    'اطلاعات، تکالیف و سابقه حذف نمی‌شوند. ویرایش اطلاعات وابسته متوقف می‌شود.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialog, false),
                      child: const Text('انصراف')),
                  FilledButton(
                      onPressed: () => Navigator.pop(dialog, true),
                      child: const Text('بایگانی'))
                ]));
    if (confirmed != true || !mounted || busy) return;
    setState(() => busy = true);
    try {
      final result = await sync.mutate(type, 'archive', {},
          entityId: row['id'].toString(),
          expectedVersion: row['version'] as int);
      notice = result['queued'] == true
          ? 'بایگانی در انتظار تأیید سرور است.'
          : 'بایگانی با تأیید سرور ثبت شد.';
    } catch (e) {
      if (mounted) setState(() => notice = _schoolError(e));
    } finally {
      if (mounted) {
        setState(() => busy = false);
        await load();
      }
    }
  }

  Future<void> childWrite(Future<void> Function() action) async {
    if (!writable || !childrenFresh) return;
    setState(() {
      busy = true;
      notice = null;
    });
    try {
      await action();
      if (mounted) notice = 'تغییر اطلاعات درسی با پاسخ سرور ثبت شد.';
    } catch (failure) {
      if (mounted) {
        if (isOfflineFailure(failure) ||
            failure is ApiException && failure.statusCode >= 500) {
          notice =
              'نتیجه ارسال نامشخص است. این عملیات خودکار تکرار نمی‌شود؛ پیش از ثبت دوباره، فهرست سرور را تازه و بررسی کن.';
        } else {
          error = _schoolError(failure);
        }
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
        await load();
      }
    }
  }

  Future<void> editSubject([Map<String, dynamic>? row]) async {
    final name = TextEditingController(text: row?['name']?.toString() ?? '');
    final teacher =
        TextEditingController(text: row?['teacher_name']?.toString() ?? '');
    var termId = row?['academic_term_id']?.toString();
    final active =
        rows('terms').where((row) => termActive(row['id'].toString())).toList();
    final data = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (dialog) => StatefulBuilder(
            builder: (context, local) => AlertDialog(
                    title: Text(row == null ? 'درس جدید' : 'ویرایش درس'),
                    content: SingleChildScrollView(
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                      TextField(
                          controller: name,
                          maxLength: 120,
                          decoration:
                              const InputDecoration(labelText: 'نام درس')),
                      TextField(
                          controller: teacher,
                          maxLength: 120,
                          decoration: const InputDecoration(
                              labelText: 'نام دبیر؛ اختیاری')),
                      DropdownButtonFormField<String>(
                          initialValue: termId,
                          decoration:
                              const InputDecoration(labelText: 'نیمسال فعال'),
                          items: active
                              .map((term) => DropdownMenuItem(
                                  value: term['id'].toString(),
                                  child: Text(term['title'].toString())))
                              .toList(),
                          onChanged: (value) => local(() => termId = value))
                    ])),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(dialog),
                          child: const Text('انصراف')),
                      FilledButton(
                          onPressed: () =>
                              name.text.trim().isEmpty || termId == null
                                  ? null
                                  : Navigator.pop(dialog, {
                                      'name': name.text.trim(),
                                      'teacherName': teacher.text.trim().isEmpty
                                          ? null
                                          : teacher.text.trim(),
                                      'academicTermId': termId
                                    }),
                          child: const Text('ثبت'))
                    ])));
    name.dispose();
    teacher.dispose();
    if (data == null || !mounted) return;
    await childWrite(() async {
      if (row == null) {
        final payload = {...data}..remove('academicTermId');
        await widget.api
            .createSubject(data['academicTermId'].toString(), payload);
      } else {
        await widget.api.requestJson(
            'PATCH', '/v1/school/subjects/${row['id']}',
            body: data);
      }
    });
  }

  Future<void> editClass([Map<String, dynamic>? row]) async {
    final starts = TextEditingController(
        text: row?['starts_at']?.toString().substring(0, 5) ?? '');
    final ends = TextEditingController(
        text: row?['ends_at']?.toString().substring(0, 5) ?? '');
    final location =
        TextEditingController(text: row?['location']?.toString() ?? '');
    final until = TextEditingController(
        text: row?['recurrence_until']?.toString().substring(0, 10) ?? '');
    var subjectId = row?['subject_id']?.toString(),
        weekday = row?['weekday'] as int? ?? 1;
    const weekdays = [
      'شنبه',
      'یکشنبه',
      'دوشنبه',
      'سه‌شنبه',
      'چهارشنبه',
      'پنجشنبه',
      'جمعه'
    ];
    final data = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (dialog) => StatefulBuilder(
            builder: (context, local) => AlertDialog(
                    title: Text(row == null ? 'کلاس جدید' : 'ویرایش کلاس'),
                    content: SingleChildScrollView(
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                      DropdownButtonFormField<String>(
                          initialValue: subjectId,
                          decoration:
                              const InputDecoration(labelText: 'درس فعال'),
                          items: subjects
                              .map((subject) => DropdownMenuItem(
                                  value: subject['id'].toString(),
                                  child: Text(subject['name'].toString())))
                              .toList(),
                          onChanged: (value) => local(() => subjectId = value)),
                      DropdownButtonFormField<int>(
                          initialValue: weekday,
                          decoration:
                              const InputDecoration(labelText: 'روز هفته'),
                          items: List.generate(
                              7,
                              (i) => DropdownMenuItem(
                                  value: i + 1, child: Text(weekdays[i]))),
                          onChanged: (value) => local(() => weekday = value!)),
                      TextField(
                          controller: starts,
                          textDirection: TextDirection.ltr,
                          decoration: const InputDecoration(
                              labelText: 'شروع کلاس HH:mm')),
                      TextField(
                          controller: ends,
                          textDirection: TextDirection.ltr,
                          decoration: const InputDecoration(
                              labelText: 'پایان کلاس HH:mm')),
                      TextField(
                          controller: location,
                          maxLength: 240,
                          decoration:
                              const InputDecoration(labelText: 'محل؛ اختیاری')),
                      TextField(
                          controller: until,
                          textDirection: TextDirection.ltr,
                          decoration: const InputDecoration(
                              labelText:
                                  'آخرین تکرار میلادی YYYY-MM-DD؛ اختیاری'))
                    ])),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(dialog),
                          child: const Text('انصراف')),
                      FilledButton(
                          onPressed: () => subjectId == null
                              ? null
                              : Navigator.pop(dialog, {
                                  'subjectId': subjectId,
                                  'weekday': weekday,
                                  'startsAt': _latinDigits(starts.text),
                                  'endsAt': _latinDigits(ends.text),
                                  'location': location.text.trim().isEmpty
                                      ? null
                                      : location.text.trim(),
                                  'recurrenceUntil': until.text.trim().isEmpty
                                      ? null
                                      : _latinDigits(until.text)
                                }),
                          child: const Text('ثبت'))
                    ])));
    starts.dispose();
    ends.dispose();
    location.dispose();
    until.dispose();
    if (data == null || !mounted) return;
    await childWrite(() async {
      if (row == null) {
        final payload = {...data}..remove('subjectId');
        await widget.api
            .createClassSession(data['subjectId'].toString(), payload);
      } else {
        await widget.api.requestJson('PATCH', '/v1/school/classes/${row['id']}',
            body: data);
      }
    });
  }

  Future<void> archiveChild(String path) async {
    final yes = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
                title: const Text('بایگانی اطلاعات درسی'),
                content: const Text('سابقه و تکالیف وابسته حفظ می‌شود.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialog, false),
                      child: const Text('انصراف')),
                  FilledButton(
                      onPressed: () => Navigator.pop(dialog, true),
                      child: const Text('بایگانی'))
                ]));
    if (yes == true && mounted) {
      await childWrite(() async {
        await widget.api.requestJson('DELETE', path);
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('مدیریت مدرسه'), actions: [
        IconButton(
            onPressed: busy ? null : () => load(),
            icon: const Icon(Icons.refresh),
            tooltip: 'تازه‌کردن')
      ]),
      body: Directionality(
          textDirection: TextDirection.rtl,
          child: ListView(padding: const EdgeInsets.all(16), children: [
            const Text(
                'این اطلاعات خصوصی است. ابتدا مدرسه، سپس سال با تاریخ دلخواه، نیمسال، درس و کلاس را بساز. هیچ درس یا تاریخی خودکار ساخته نمی‌شود.'),
            if (busy) const LinearProgressIndicator(),
            if (error != null)
              Text(error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            if (notice != null)
              Semantics(liveRegion: true, child: Text(notice!)),
            if (snapshot != null)
              Text(snapshot!['offline'] == true
                  ? 'نسخه ذخیره‌شده؛ داده زنده نیست'
                  : 'آخرین دریافت سرور: ${snapshot!['fetchedAt'] ?? 'نامشخص'}'),
            if (snapshot != null &&
                (snapshot!['pending'] as List).isNotEmpty) ...[
              FilledButton(
                  onPressed: busy ? null : () => load(retry: true),
                  child: const Text('ارسال دوباره تغییرهای ذخیره‌شده')),
              ...(snapshot!['pending'] as List).map((raw) {
                final record = Map<String, dynamic>.from(raw as Map);
                final type = (record['entityType'] as String)
                    .replaceFirst('school_lifecycle_', '');
                return Card(
                    child: ListTile(
                        title:
                            Text('${_typeLabel(type)}: در انتظار تأیید سرور'),
                        subtitle: Text(record['queueStatus'] == 'conflict'
                            ? 'تعارض نسخه؛ تغییر محلی نگه داشته شده است'
                            : '${record['operation']} · ${(record['payload'] as Map)['data']['title'] ?? ''}'),
                        trailing: TextButton(
                            onPressed: busy
                                ? null
                                : () async {
                                    final yes = await showDialog<bool>(
                                        context: context,
                                        builder: (dialog) => AlertDialog(
                                                title: const Text(
                                                    'انتخاب نسخه سرور'),
                                                content: const Text(
                                                    'تغییر محلی از صف کنار می‌رود و در سابقه بازیابی دستگاه نگه داشته می‌شود.'),
                                                actions: [
                                                  TextButton(
                                                      onPressed: () =>
                                                          Navigator.pop(
                                                              dialog, false),
                                                      child:
                                                          const Text('انصراف')),
                                                  FilledButton(
                                                      onPressed: () =>
                                                          Navigator.pop(
                                                              dialog, true),
                                                      child: const Text(
                                                          'نسخه سرور'))
                                                ]));
                                    if (yes == true && mounted) {
                                      try {
                                        await sync.useServer(type,
                                            record['entityId'].toString());
                                        await load();
                                      } catch (e) {
                                        if (mounted) {
                                          setState(
                                              () => error = _schoolError(e));
                                        }
                                      }
                                    }
                                  },
                            child: const Text('بررسی نسخه سرور'))));
              }),
            ],
            for (final type in _schoolTypes) ...[
              Row(children: [
                Expanded(
                    child: Text(_typeLabel(type),
                        style: Theme.of(context).textTheme.titleMedium)),
                TextButton.icon(
                    onPressed: writable ? () => editLifecycle(type) : null,
                    icon: const Icon(Icons.add),
                    label: const Text('ایجاد'))
              ]),
              ...rows(type).map((row) {
                final ancestorActive = type == 'contexts' ||
                    (type == 'years'
                        ? contextActive(row['life_context_id'].toString())
                        : yearActive(row['academic_year_id'].toString()));
                final pending = (snapshot!['pending'] as List)
                    .any((m) => m['entityId'] == row['id']);
                return Card(
                    child: ListTile(
                        title: Text(row['title'].toString()),
                        subtitle: Text(
                            '${row['active'] == true ? (ancestorActive ? 'فعال' : 'زمینه بالادست بایگانی شده') : 'بایگانی‌شده'} · نسخه ${_faDigits(row['version'].toString())}${type == 'contexts' ? '' : '\n${_faDigits(row['starts_on'].toString())} تا ${_faDigits(row['ends_on'].toString())} (میلادی)'}'),
                        trailing: Wrap(children: [
                          IconButton(
                              onPressed: writable &&
                                      !pending &&
                                      row['active'] == true &&
                                      ancestorActive
                                  ? () => editLifecycle(type, row)
                                  : null,
                              icon: const Icon(Icons.edit_outlined),
                              tooltip: 'ویرایش ${_typeLabel(type)}'),
                          IconButton(
                              onPressed:
                                  writable && !pending && row['active'] == true
                                      ? () => archive(type, row)
                                      : null,
                              icon: const Icon(Icons.archive_outlined),
                              tooltip: 'بایگانی ${_typeLabel(type)}')
                        ])));
              }),
            ],
            Row(children: [
              Expanded(
                  child: Text('درس‌ها',
                      style: Theme.of(context).textTheme.titleMedium)),
              TextButton.icon(
                  onPressed:
                      writable && childrenFresh ? () => editSubject() : null,
                  icon: const Icon(Icons.add),
                  label: const Text('درس جدید'))
            ]),
            ...subjects.map((row) => Card(
                child: ListTile(
                    title: Text(row['name'].toString()),
                    subtitle: Text(row['teacher_name']?.toString() ??
                        row['term_title']?.toString() ??
                        ''),
                    trailing: Wrap(children: [
                      IconButton(
                          onPressed: writable && childrenFresh
                              ? () => editSubject(row)
                              : null,
                          icon: const Icon(Icons.edit_outlined),
                          tooltip: 'ویرایش درس'),
                      IconButton(
                          onPressed: writable && childrenFresh
                              ? () => archiveChild(
                                  '/v1/school/subjects/${row['id']}')
                              : null,
                          icon: const Icon(Icons.archive_outlined),
                          tooltip: 'بایگانی درس')
                    ])))),
            Row(children: [
              Expanded(
                  child: Text('کلاس‌ها',
                      style: Theme.of(context).textTheme.titleMedium)),
              TextButton.icon(
                  onPressed:
                      writable && childrenFresh ? () => editClass() : null,
                  icon: const Icon(Icons.add),
                  label: const Text('کلاس جدید'))
            ]),
            ...classes.map((row) => Card(
                child: ListTile(
                    title: Text(row['subject_name']?.toString() ?? 'کلاس'),
                    subtitle: Text(
                        'روز ${_faDigits(row['weekday'].toString())} · ${_faDigits(row['starts_at'].toString())} تا ${_faDigits(row['ends_at'].toString())}'),
                    trailing: Wrap(children: [
                      IconButton(
                          onPressed: writable && childrenFresh
                              ? () => editClass(row)
                              : null,
                          icon: const Icon(Icons.edit_outlined),
                          tooltip: 'ویرایش کلاس'),
                      IconButton(
                          onPressed: writable && childrenFresh
                              ? () => archiveChild(
                                  '/v1/school/classes/${row['id']}')
                              : null,
                          icon: const Icon(Icons.archive_outlined),
                          tooltip: 'بایگانی کلاس')
                    ])))),
          ])));
}

String _typeLabel(String type) => switch (type) {
      'contexts' => 'زمینه مدرسه و زندگی',
      'years' => 'سال تحصیلی',
      'terms' => 'نیمسال',
      _ => 'اطلاعات مدرسه'
    };
