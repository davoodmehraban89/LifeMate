import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'api.dart';
import 'offline_store.dart';
import 'plan_sync.dart' show newMutationId;

const familyRoleLabels = <String, String>{
  'parent_guardian': 'سرپرست',
  'teen_minor': 'فرزند',
  'adult_member': 'عضو بزرگسال',
};
final _familyUuid = RegExp(r'^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$');
bool _uuid(dynamic value) => value is String && _familyUuid.hasMatch(value);
bool _version(dynamic value) =>
    value is int && value > 0 && value <= 2147483647;
bool _date(dynamic value) =>
    value is String &&
    RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(value) &&
    DateTime.tryParse(value) != null;
bool _exact(Map value, Set<String> keys) =>
    value.length == keys.length && value.keys.every(keys.contains);
Map<String, dynamic> _freeze(Map value) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);
Never _invalid() => throw const ApiException(502, 'invalid_family_response');

String familyManagementError(Object error) {
  if (isOfflineFailure(error)) {
    return 'اتصال برقرار نیست. نتیجه عملیات ممکن است نامشخص باشد؛ وضعیت را تازه کن. تغییر خودکار یا تلاش کور انجام نمی‌شود.';
  }
  if (error is ApiException) {
    if (error.statusCode == 401 || error.statusCode == 403) {
      return 'نشست یا دسترسی این خانواده معتبر نیست؛ اطلاعات قبلی پاک شدند.';
    }
    if (error.code == 'last_admin_required') {
      return 'آخرین مدیر فعال را نمی‌توان حذف یا از مدیریت خارج کرد؛ ابتدا مدیریت را به بزرگسال فعال منتقل کن.';
    }
    if (error.code == 'age_confirmation_required' ||
        error.code == 'minor_role_restricted' ||
        error.code == 'minor_role_upgrade_forbidden' ||
        error.code == 'minor_cannot_admin') {
      return 'سن مجاز برای نقش بزرگسال باید در سرور تأیید شود؛ نوع پروفایل مجوز مدیریت نمی‌دهد.';
    }
    if (error.statusCode == 409) {
      return 'نسخه یا وضعیت عضویت تغییر کرده است. ابتدا وضعیت تازه سرور را بررسی کن؛ درخواست قدیمی در صف محفوظ است.';
    }
    if (error.statusCode == 404) {
      return 'عضویت یا دعوت دیگر در دسترس نیست؛ وضعیت تازه را دریافت کن.';
    }
  }
  return 'عملیات با پاسخ معتبر تأیید نشد؛ ابتدا وضعیت تازه سرور را بررسی کن.';
}

/// Metadata-only journal for versioned family operations. Permissions, member
/// names, invitation contacts and tokens are never cached in this journal.
class FamilyOperationSync {
  FamilyOperationSync(this.api, this.familyId, {OfflineStore? store})
      : store = store ?? OfflineStore.forApi(api) {
    if (!_uuid(familyId)) throw ArgumentError('Invalid family ID');
  }
  final HttpIdentityApi api;
  final String familyId;
  final OfflineStore store;
  static final _tails = <String, Future<void>>{};
  String get path => '/v1/families/${Uri.encodeComponent(familyId)}';

  Future<void> scope() async {
    if (api.cacheNamespace != store.scope) {
      throw const ApiException(401, 'cache_scope_closed');
    }
    await store.readQueue();
    if (api.cacheNamespace != store.scope) {
      throw const ApiException(401, 'cache_scope_closed');
    }
  }

  Future<Map<String, dynamic>> request(String method, String suffix,
      {Map<String, dynamic>? body}) async {
    await scope();
    final response = await api.requestJson(method, '$path$suffix', body: body);
    await scope();
    return response;
  }

  Future<T> _serial<T>(Future<T> Function() operation) async {
    final previous = _tails[store.scope];
    final release = Completer<void>();
    _tails[store.scope] = release.future;
    if (previous != null) await previous;
    try {
      await scope();
      return await operation();
    } finally {
      if (identical(_tails[store.scope], release.future)) {
        _tails.remove(store.scope);
      }
      release.complete();
    }
  }

  Future<void> _membership({required bool admin}) async {
    final result = await request('GET', '');
    if (result['id'] != familyId ||
        result['is_admin'] is! bool ||
        !familyRoleLabels.containsKey(result['role']) ||
        (result['is_admin'] == true && result['role'] == 'teen_minor')) {
      _invalid();
    }
    if (admin && result['is_admin'] != true) {
      throw const ApiException(403, 'family_admin_required');
    }
  }

  Map<String, dynamic> _body(String operation, String targetId, Map value) {
    final keys = operation == 'role'
        ? {'mutationId', 'expectedVersion', 'role'}
        : operation == 'invitation_revoke'
            ? {'mutationId', 'expectedVersion', 'action'}
            : operation == 'admin_transfer'
                ? {
                    'mutationId',
                    'targetUserId',
                    'expectedVersion',
                    'expectedActorVersion'
                  }
                : <String>{};
    if (!_uuid(targetId) ||
        keys.isEmpty ||
        !_exact(value, keys) ||
        !_uuid(value['mutationId']) ||
        !_version(value['expectedVersion']) ||
        (operation == 'role' && !familyRoleLabels.containsKey(value['role'])) ||
        (operation == 'invitation_revoke' && value['action'] != 'revoke') ||
        (operation == 'admin_transfer' &&
            (value['targetUserId'] != targetId ||
                !_version(value['expectedActorVersion']) ||
                targetId == api.currentUserId))) {
      throw const ApiException(400, 'invalid_family_operation');
    }
    return _freeze(value);
  }

  Future<List<Map<String, dynamic>>> pending() async {
    await scope();
    final values = (await store.readQueue())
        .where((row) =>
            row['entityType'] == 'family_operation' &&
            row['entityId'] == familyId)
        .toList();
    await scope();
    return values;
  }

  Future<Map<String, dynamic>> submit(
      String operation, String targetId, Map<String, dynamic> body) {
    final frozen = _body(operation, targetId, body);
    return _serial(() async {
      await _membership(
          admin: true); // No new operation under cached authority.
      final mutation = {
        'id': frozen['mutationId'],
        'entityId': familyId,
        'entityType': 'family_operation',
        'operation': operation,
        'targetId': targetId,
        'payload': frozen
      };
      await store.enqueue(mutation);
      return _send(mutation);
    });
  }

  Future<Map<String, dynamic>> retry(Map<String, dynamic> mutation) =>
      _serial(() async {
        final saved = (await pending())
            .where((row) => row['id'] == mutation['id'])
            .firstOrNull;
        if (saved == null || jsonEncode(saved) != jsonEncode(mutation)) {
          throw const ApiException(409, 'family_pending_changed');
        }
        // A successful transfer removes the sender's admin flag. Its exact prior
        // receipt may still be read by that active member; the server decides.
        await _membership(admin: false);
        return _send(saved);
      });
  Future<Map<String, dynamic>> _send(Map<String, dynamic> mutation) async {
    final operation = mutation['operation'] as String;
    final targetId = mutation['targetId'] as String;
    final body = _body(operation, targetId, mutation['payload'] as Map);
    final suffix = operation == 'role'
        ? '/members/$targetId/role'
        : operation == 'invitation_revoke'
            ? '/invitations/$targetId'
            : '/admin-transfer';
    final result = await request(
        operation == 'admin_transfer' ? 'POST' : 'PATCH', suffix,
        body: body);
    final ack = result['acknowledgement'];
    if (ack is! Map ||
        !_exact(ack,
            {'mutationId', 'familyId', 'targetId', 'operation', 'status'}) ||
        ack['mutationId'] != mutation['id'] ||
        ack['familyId'] != familyId ||
        ack['targetId'] != targetId ||
        ack['operation'] != operation ||
        !const {'accepted', 'already_applied'}.contains(ack['status'])) {
      _invalid();
    }
    final accepted = ack['status'] == 'accepted';
    String acceptedAt;
    if (operation == 'invitation_revoke') {
      final row = result['invitation'];
      if (!_exact(result, {'invitation', 'acknowledgement'}) ||
          row is! Map ||
          !_exact(row, {'id', 'status', 'version', 'createdAt', 'expiresAt'}) ||
          row['id'] != targetId ||
          row['status'] != 'revoked' ||
          !_version(row['version']) ||
          row['version'] < body['expectedVersion'] + 1 ||
          (accepted && row['version'] != body['expectedVersion'] + 1) ||
          !_date(row['createdAt']) ||
          !_date(row['expiresAt'])) {
        _invalid();
      }
      acceptedAt = DateTime.now().toUtc().toIso8601String();
    } else {
      if (!_exact(result, {'members', 'acknowledgement'}) ||
          result['members'] is! List) {
        _invalid();
      }
      final rows = result['members'] as List;
      if (rows.length != (operation == 'role' ? 1 : 2)) _invalid();
      final byId = <String, Map>{};
      for (final row in rows) {
        if (row is! Map ||
            !_exact(row, {
              'userId',
              'role',
              'isAdmin',
              'version',
              'updatedAt',
              'endedAt'
            }) ||
            !_uuid(row['userId']) ||
            !familyRoleLabels.containsKey(row['role']) ||
            row['isAdmin'] is! bool ||
            !_version(row['version']) ||
            !_date(row['updatedAt']) ||
            (row['endedAt'] != null && !_date(row['endedAt'])) ||
            byId.containsKey(row['userId'])) {
          _invalid();
        }
        byId[row['userId'] as String] = row;
      }
      final target = byId[targetId];
      if (target == null ||
          target['version'] < body['expectedVersion'] + 1 ||
          (accepted &&
              (target['version'] != body['expectedVersion'] + 1 ||
                  target['endedAt'] != null))) {
        _invalid();
      }
      if (operation == 'role') {
        if (accepted && target['role'] != body['role']) _invalid();
      } else {
        final actor = byId[api.currentUserId];
        if (actor == null ||
            actor['version'] < body['expectedActorVersion'] + 1 ||
            (accepted &&
                (actor['version'] != body['expectedActorVersion'] + 1 ||
                    actor['isAdmin'] != false ||
                    actor['endedAt'] != null ||
                    target['isAdmin'] != true ||
                    target['role'] == 'teen_minor'))) {
          _invalid();
        }
      }
      acceptedAt = target['updatedAt'] as String;
    }
    await scope();
    await store.acknowledge(mutation['id'] as String, acceptedAt: acceptedAt);
    return {'acknowledgement': _freeze(ack)};
  }
}

class FamilyManagementPage extends StatefulWidget {
  const FamilyManagementPage(
      {super.key, required this.api, required this.familyId});
  final HttpIdentityApi api;
  final String familyId;
  @override
  State<FamilyManagementPage> createState() => _FamilyManagementPageState();
}

class _FamilyManagementPageState extends State<FamilyManagementPage>
    with WidgetsBindingObserver {
  late final FamilyOperationSync sync;
  Timer? timer;
  Map<String, dynamic>? family;
  List<Map<String, dynamic>> members = [], invitations = [], pending = [];
  final name = TextEditingController(), contact = TextEditingController();
  String contactKind = 'email', inviteRole = 'adult_member';
  String? guardianId, childId, invitationCursor, nextInvitationCursor, message;
  int epoch = 0;
  bool loading = false, busy = false, active = true;
  DateTime? refreshed;
  bool get admin => family?['is_admin'] == true;
  Map<String, dynamic>? get self => members
      .where((row) => row['user_id'] == widget.api.currentUserId)
      .firstOrNull;
  bool current(int request) =>
      mounted &&
      active &&
      epoch == request &&
      widget.api.cacheNamespace == sync.store.scope;

  @override
  void initState() {
    super.initState();
    sync = FamilyOperationSync(widget.api, widget.familyId);
    WidgetsBinding.instance.addObserver(this);
    refresh();
    timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (active && !busy && !loading) refresh();
    });
  }

  void clear({bool privateInputs = true}) {
    family = null;
    members = [];
    invitations = [];
    guardianId = null;
    childId = null;
    refreshed = null;
    nextInvitationCursor = null;
    name.clear();
    if (privateInputs) contact.clear();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    active = state == AppLifecycleState.resumed;
    ++epoch;
    if (mounted) {
      setState(() {
        clear();
        loading = false;
      });
    }
    if (active && !busy) refresh();
  }

  @override
  void dispose() {
    ++epoch;
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    name.dispose();
    contact.dispose();
    super.dispose();
  }

  Map<String, dynamic> validateFamily(Map raw) {
    if (raw['id'] != widget.familyId ||
        raw['name'] is! String ||
        (raw['name'] as String).trim().isEmpty ||
        (raw['name'] as String).length > 120 ||
        raw['is_admin'] is! bool ||
        !familyRoleLabels.containsKey(raw['role']) ||
        (raw['is_admin'] == true && raw['role'] == 'teen_minor')) {
      _invalid();
    }
    return {
      'id': raw['id'],
      'name': raw['name'],
      'role': raw['role'],
      'is_admin': raw['is_admin']
    };
  }

  Map<String, dynamic> validateMember(dynamic raw) {
    if (raw is! Map ||
        !_uuid(raw['user_id']) ||
        !familyRoleLabels.containsKey(raw['role']) ||
        raw['is_admin'] is! bool ||
        (raw['display_name'] != null &&
            (raw['display_name'] is! String ||
                (raw['display_name'] as String).length > 120)) ||
        (raw['version'] != null && !_version(raw['version'])) ||
        (raw['account_disabled'] != null && raw['account_disabled'] is! bool)) {
      _invalid();
    }
    return {
      'user_id': raw['user_id'],
      'display_name': raw['display_name'] ?? 'عضو خانواده',
      'role': raw['role'],
      'is_admin': raw['is_admin'],
      'version': raw['version'],
      'account_disabled': raw['account_disabled'] == true
    };
  }

  Map<String, dynamic> validateInvitation(dynamic raw) {
    if (raw is! Map ||
        !_exact(raw, {
          'id',
          'intendedRole',
          'status',
          'version',
          'createdAt',
          'expiresAt',
          'recipientHint'
        }) ||
        !_uuid(raw['id']) ||
        !familyRoleLabels.containsKey(raw['intendedRole']) ||
        !const {'pending', 'expired'}.contains(raw['status']) ||
        !_version(raw['version']) ||
        !_date(raw['createdAt']) ||
        !_date(raw['expiresAt']) ||
        raw['recipientHint'] is! String ||
        (raw['recipientHint'] as String).length > 120) {
      _invalid();
    }
    return _freeze(raw);
  }

  Future<void> refresh({bool firstInvitations = false}) async {
    if (!active || busy || !mounted) return;
    final request = ++epoch;
    if (firstInvitations) invitationCursor = null;
    setState(() {
      clear(privateInputs: false);
      loading = true;
      message = null;
    });
    try {
      final fresh = validateFamily(await sync.request('GET', ''));
      if (!current(request)) return;
      final data = await sync.request('GET', '/members');
      if (data['members'] is! List) _invalid();
      final people = (data['members'] as List).map(validateMember).toList();
      if (people.map((row) => row['user_id']).toSet().length != people.length) {
        _invalid();
      }
      final queued = await sync.pending();
      if (!current(request)) return;
      List<Map<String, dynamic>> invites = [];
      String? next;
      if (fresh['is_admin'] == true) {
        final query = Uri(queryParameters: {
          'limit': '20',
          if (invitationCursor != null) 'cursor': invitationCursor!
        }).query;
        final result = await sync.request('GET', '/invitations?$query');
        if (!_exact(result, {'invitations', 'nextCursor', 'total'}) ||
            result['invitations'] is! List ||
            (result['invitations'] as List).length > 20 ||
            result['total'] is! int ||
            result['total'] < 0 ||
            (result['nextCursor'] != null && !_uuid(result['nextCursor']))) {
          _invalid();
        }
        invites =
            (result['invitations'] as List).map(validateInvitation).toList();
        next = result['nextCursor'] as String?;
      }
      if (!current(request)) return;
      setState(() {
        family = fresh;
        members = people;
        invitations = invites;
        pending = queued;
        nextInvitationCursor = next;
        refreshed = DateTime.now();
        name.text = fresh['name'] as String;
        loading = false;
      });
    } catch (error) {
      if (!current(request)) return;
      setState(() {
        clear();
        loading = false;
        message = familyManagementError(error);
      });
    }
  }

  Future<bool> confirm(String title, String explanation) async =>
      await showDialog<bool>(
          context: context,
          builder: (context) => Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                  title: Text(title),
                  content: Text(explanation),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('انصراف')),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('تأیید تغییر'))
                  ]))) ==
      true;

  Future<void> perform(Future<void> Function() operation,
      {bool archived = false}) async {
    if (busy || !active) return;
    final request = ++epoch;
    setState(() {
      busy = true;
      clear();
      message = null;
    });
    String? outcome;
    bool success = false;
    try {
      await operation();
      if (!current(request)) return;
      success = true;
      outcome = 'عملیات در سرور تأیید شد؛ وضعیت تازه دریافت می‌شود.';
    } catch (error) {
      if (!current(request)) return;
      outcome = familyManagementError(error);
    } finally {
      if (mounted) setState(() => busy = false);
    }
    if (!mounted || !active || widget.api.cacheNamespace != sync.store.scope) {
      return;
    }
    if (archived && success) {
      setState(() => message =
          'خانواده بایگانی شد؛ دعوت‌ها و ارتباط‌های سرپرستی غیرفعال شدند. داده‌های خصوصی افراد حذف نشده‌اند.');
      return;
    }
    await refresh();
    if (!mounted || !active || widget.api.cacheNamespace != sync.store.scope) {
      return;
    }
    setState(() => message ??= outcome);
  }

  Future<void> createInvitation() async {
    final recipient = contact.text.trim();
    if (recipient.isEmpty || recipient.length > 254) {
      setState(() => message = 'ایمیل یا شماره گیرنده را تکمیل کن.');
      return;
    }
    final role = inviteRole, kind = contactKind;
    Map<String, dynamic>? created;
    await perform(() async {
      created = await widget.api.createFamilyInvitation(
          familyId: widget.familyId,
          email: kind == 'email' ? recipient : null,
          phone: kind == 'phone' ? recipient : null,
          role: role);
      await sync.scope();
      if (!_uuid(created?['id']) ||
          created?['invitationToken'] is! String ||
          (created!['invitationToken'] as String).isEmpty ||
          !_date(created?['expires_at'])) {
        _invalid();
      }
    });
    if (created == null ||
        !mounted ||
        !active ||
        !admin ||
        widget.api.cacheNamespace != sync.store.scope) {
      return;
    }
    contact.clear();
    final token = created!['invitationToken'] as String;
    await showDialog<void>(
        context: context,
        builder: (context) => Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
                title: const Text('دعوت در سرور ساخته شد'),
                content: SingleChildScrollView(
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      const Text(
                          'این کد را فقط به گیرنده موردنظر بده. ورود با تماس تأییدشده مطابق دعوت لازم است. کد در حافظه دستگاه ذخیره دائمی نمی‌شود.'),
                      SelectableText(token, textDirection: TextDirection.ltr),
                      const Text(
                          'ارسال واقعی ایمیل یا پیامک تضمین نشده است؛ فراهم‌کننده پیامک باید جداگانه پیکربندی شود.'),
                    ])),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('بستن'))
                ])));
  }

  @override
  Widget build(BuildContext context) => Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
          appBar: AppBar(title: const Text('مدیریت خانواده'), actions: [
            IconButton(
                key: const Key('family-management-refresh'),
                tooltip: 'دریافت وضعیت تازه خانواده',
                onPressed: busy ? null : () => refresh(),
                icon: const Icon(Icons.refresh))
          ]),
          body: ListView(padding: const EdgeInsets.all(16), children: [
            const Text(
                'نقش سرپرست یا بزرگسال به‌تنهایی مدیریت خانواده نیست. مجوزهای این صفحه از عضویت فعلی سرور می‌آیند؛ اطلاعات خصوصی اعضا در این صفحه نمایش داده نمی‌شود.'),
            if (loading || busy) const LinearProgressIndicator(),
            Text(refreshed == null
                ? 'وضعیت تازه خانواده در دسترس نیست.'
                : 'آخرین دریافت: ${refreshed!.hour.toString().padLeft(2, '0')}:${refreshed!.minute.toString().padLeft(2, '0')}؛ تازه‌سازی هر ۳۰ ثانیه.'),
            if (message != null) Text(message!),
            if (family != null) ...[
              Text(family!['name'] as String,
                  style: Theme.of(context).textTheme.titleLarge),
              Text(
                  'نقش عضویت شما: ${familyRoleLabels[family!['role']]}${admin ? ' · مدیر خانواده' : ''}'),
              if (admin) ...[
                TextField(
                    controller: name,
                    enabled: !busy,
                    maxLength: 120,
                    decoration:
                        const InputDecoration(labelText: 'نام خانواده')),
                TextButton(
                    onPressed: busy
                        ? null
                        : () {
                            final value = name.text.trim();
                            if (value.isEmpty || value.length > 120) {
                              setState(() => message =
                                  'نام خانواده باید بین ۱ تا ۱۲۰ نویسه باشد.');
                              return;
                            }
                            perform(() async {
                              final result = await sync
                                  .request('PATCH', '', body: {'name': value});
                              if (result['id'] != widget.familyId ||
                                  result['name'] != value) {
                                _invalid();
                              }
                            });
                          },
                    child: const Text('ذخیره نام خانواده')),
                TextButton(
                    onPressed: busy
                        ? null
                        : () async {
                            if (!await confirm('بایگانی خانواده',
                                'دسترسی خانوادگی، دعوت‌های باز و ارتباط‌های سرپرستی این خانواده غیرفعال می‌شوند. داده‌های خصوصی اعضا حذف نمی‌شوند.')) {
                              return;
                            }
                            await perform(() async {
                              await sync.request('DELETE', '');
                            }, archived: true);
                          },
                    child: const Text('بایگانی خانواده')),
              ],
              const Divider(),
              const Text('اعضای فعال خانواده'),
              ...members.map((person) => Card(
                  child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(person['display_name'] as String),
                            Text(
                                '${familyRoleLabels[person['role']]}${person['is_admin'] == true ? ' · مدیر' : ''}${person['account_disabled'] == true ? ' · حساب غیرفعال' : ''}'),
                            if (admin) ...[
                              if (person['version'] != null &&
                                  person['account_disabled'] != true)
                                DropdownButtonFormField<String>(
                                    key: Key(
                                        'family-member-role-${person['user_id']}'),
                                    decoration: const InputDecoration(
                                        labelText: 'تغییر نقش عضویت'),
                                    hint: const Text('انتخاب نقش جدید'),
                                    items: familyRoleLabels.entries
                                        .where((entry) =>
                                            entry.key != person['role'])
                                        .map((entry) => DropdownMenuItem(
                                            value: entry.key,
                                            child: Text(entry.value)))
                                        .toList(),
                                    onChanged: busy
                                        ? null
                                        : (value) async {
                                            if (value == null ||
                                                !await confirm('تغییر نقش عضو',
                                                    'نقش عضویت ${person['display_name']} به ${familyRoleLabels[value]} تغییر می‌کند. ارتباط‌های سرپرستی ناسازگار ممکن است لغو شوند؛ تغییر سن و مجوزهای خصوصی را سرور کنترل می‌کند.')) {
                                              return;
                                            }
                                            final body = {
                                              'mutationId': newMutationId(),
                                              'expectedVersion':
                                                  person['version'],
                                              'role': value
                                            };
                                            await perform(() async {
                                              await sync.submit(
                                                  'role',
                                                  person['user_id'] as String,
                                                  body);
                                            });
                                          }),
                              if (person['user_id'] !=
                                      widget.api.currentUserId &&
                                  person['role'] != 'teen_minor' &&
                                  person['account_disabled'] != true &&
                                  person['version'] != null &&
                                  self?['version'] != null)
                                TextButton(
                                    onPressed: busy
                                        ? null
                                        : () async {
                                            final actorVersion =
                                                self!['version'];
                                            if (!await confirm('انتقال مدیریت',
                                                'مدیریت به ${person['display_name']} منتقل می‌شود و دسترسی مدیریت شما برداشته خواهد شد. فقط بزرگسال فعال و مجاز می‌تواند مدیر شود.')) {
                                              return;
                                            }
                                            final body = {
                                              'mutationId': newMutationId(),
                                              'targetUserId': person['user_id'],
                                              'expectedVersion':
                                                  person['version'],
                                              'expectedActorVersion':
                                                  actorVersion
                                            };
                                            await perform(() async {
                                              await sync.submit(
                                                  'admin_transfer',
                                                  person['user_id'] as String,
                                                  body);
                                            });
                                          },
                                    child: Text(
                                        'انتقال مدیریت به ${person['display_name']}')),
                              TextButton(
                                  onPressed: busy
                                      ? null
                                      : () async {
                                          if (!await confirm('پایان عضویت',
                                              'عضویت ${person['display_name']} و ارتباط‌های سرپرستی مرتبط لغو می‌شود. اطلاعات خصوصی این فرد حذف نمی‌شود. حذف آخرین مدیر فعال مجاز نیست.')) {
                                            return;
                                          }
                                          await perform(() async {
                                            await sync.request('DELETE',
                                                '/members/${person['user_id']}');
                                          });
                                        },
                                  child: Text(
                                      'پایان عضویت ${person['display_name']}')),
                            ],
                          ])))),
              if (admin) ...[
                const Divider(),
                const Text('دعوت عضو'),
                DropdownButtonFormField<String>(
                    initialValue: contactKind,
                    decoration:
                        const InputDecoration(labelText: 'نوع تماس گیرنده'),
                    items: const [
                      DropdownMenuItem(value: 'email', child: Text('ایمیل')),
                      DropdownMenuItem(
                          value: 'phone', child: Text('شماره تلفن'))
                    ],
                    onChanged: busy
                        ? null
                        : (value) => setState(() {
                              contactKind = value!;
                              contact.clear();
                            })),
                TextField(
                    controller: contact,
                    enabled: !busy,
                    textDirection: TextDirection.ltr,
                    keyboardType: contactKind == 'email'
                        ? TextInputType.emailAddress
                        : TextInputType.phone,
                    decoration: InputDecoration(
                        labelText: contactKind == 'email'
                            ? 'ایمیل گیرنده'
                            : 'شماره تلفن با کد کشور')),
                DropdownButtonFormField<String>(
                    initialValue: inviteRole,
                    decoration: const InputDecoration(labelText: 'نقش موردنظر'),
                    items: familyRoleLabels.entries
                        .map((entry) => DropdownMenuItem(
                            value: entry.key, child: Text(entry.value)))
                        .toList(),
                    onChanged: busy
                        ? null
                        : (value) => setState(() => inviteRole = value!)),
                FilledButton(
                    onPressed: busy ? null : createInvitation,
                    child: const Text('ساخت دعوت')),
                const Text(
                    'دعوت، دسترسی خودکار به داده خصوصی یا ارتباط سرپرستی ایجاد نمی‌کند. ایمیل اجباری نیست؛ ارسال پیامک وابسته به فراهم‌کننده جداگانه است.'),
                const Text('دعوت‌های باز'),
                ...invitations.map((invite) => ListTile(
                    title: Text(invite['recipientHint'] as String),
                    subtitle: Text(
                        '${familyRoleLabels[invite['intendedRole']]} · ${invite['status'] == 'expired' ? 'منقضی‌شده' : 'منتظر پذیرش'} · تا ${invite['expiresAt']}'),
                    trailing: TextButton(
                        onPressed: busy
                            ? null
                            : () async {
                                if (!await confirm('لغو دعوت',
                                    'کد این دعوت دیگر قابل پذیرش نخواهد بود.')) {
                                  return;
                                }
                                await perform(() async {
                                  await sync.submit('invitation_revoke',
                                      invite['id'] as String, {
                                    'mutationId': newMutationId(),
                                    'expectedVersion': invite['version'],
                                    'action': 'revoke'
                                  });
                                });
                              },
                        child: const Text('لغو دعوت')))),
                if (nextInvitationCursor != null)
                  TextButton(
                      onPressed: busy
                          ? null
                          : () {
                              invitationCursor = nextInvitationCursor;
                              refresh();
                            },
                      child: const Text('دعوت‌های بعدی')),
                if (invitationCursor != null)
                  TextButton(
                      onPressed:
                          busy ? null : () => refresh(firstInvitations: true),
                      child: const Text('صفحه اول دعوت‌ها')),
                const Divider(),
                const Text('ارتباط مجاز سرپرست و فرزند'),
                const Text(
                    'این فرم فقط ارتباط را فعال یا لغو می‌کند؛ هیچ اطلاعات خصوصی یا وضعیت مطالعه پنهانی را نمایش نمی‌دهد.'),
                DropdownButtonFormField<String>(
                    initialValue: guardianId,
                    decoration: const InputDecoration(labelText: 'سرپرست'),
                    items: members
                        .where((person) =>
                            person['role'] == 'parent_guardian' &&
                            person['account_disabled'] != true)
                        .map((person) => DropdownMenuItem(
                            value: person['user_id'] as String,
                            child: Text(person['display_name'] as String)))
                        .toList(),
                    onChanged: busy
                        ? null
                        : (value) => setState(() => guardianId = value)),
                DropdownButtonFormField<String>(
                    initialValue: childId,
                    decoration: const InputDecoration(labelText: 'فرزند'),
                    items: members
                        .where((person) =>
                            person['role'] == 'teen_minor' &&
                            person['account_disabled'] != true)
                        .map((person) => DropdownMenuItem(
                            value: person['user_id'] as String,
                            child: Text(person['display_name'] as String)))
                        .toList(),
                    onChanged: busy
                        ? null
                        : (value) => setState(() => childId = value)),
                Wrap(
                    spacing: 8,
                    children: ['POST', 'DELETE']
                        .map((method) => TextButton(
                            onPressed: busy ||
                                    guardianId == null ||
                                    childId == null
                                ? null
                                : () async {
                                    final body = {
                                      'guardianUserId': guardianId,
                                      'minorUserId': childId
                                    };
                                    if (!await confirm(
                                        method == 'POST'
                                            ? 'فعال‌کردن ارتباط سرپرستی'
                                            : 'لغو ارتباط سرپرستی',
                                        'مجوزهای خانوادگی همین سرپرست و فرزند طبق سیاست سرور تغییر می‌کنند؛ داده‌های خصوصی خودکار به اشتراک گذاشته نمی‌شوند.')) {
                                      return;
                                    }
                                    await perform(() async {
                                      await sync.request(method, '/guardians',
                                          body: body);
                                    });
                                  },
                            child: Text(method == 'POST'
                                ? 'فعال‌کردن ارتباط'
                                : 'لغو ارتباط')))
                        .toList()),
              ],
            ],
            if (pending.isNotEmpty) ...[
              const Divider(),
              Text(
                  '${pending.length} عملیات نسخه‌دار بدون تأیید نهایی در صف دستگاه است. فقط شناسه و نسخه نگهداری می‌شود؛ ارسال خودکار انجام نمی‌شود.'),
              ...pending.map((queued) => ListTile(
                  title: Text(queued['operation'] == 'role'
                      ? 'تغییر نقش عضویت'
                      : queued['operation'] == 'admin_transfer'
                          ? 'انتقال مدیریت'
                          : 'لغو دعوت'),
                  subtitle: const Text(
                      'تلاش دستی با همان درخواست؛ ممکن است قبلاً در سرور اجرا شده باشد.'),
                  trailing: TextButton(
                      onPressed: busy || family == null
                          ? null
                          : () => perform(() async {
                                await sync.retry(queued);
                              }),
                      child: const Text('دریافت دوباره تأیید')))),
            ],
          ])));
}
