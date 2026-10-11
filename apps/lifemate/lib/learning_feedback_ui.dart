import 'dart:convert';

import 'package:flutter/material.dart';

import 'api.dart';
import 'offline_store.dart';
import 'plan_sync.dart' show newMutationId;
import 'education_ui.dart' show learningError;

const feedbackCategories = {
  'inaccurate': 'اشتباه آموزشی',
  'edition_mismatch': 'تفاوت با کتاب درسی',
  'broken_video': 'اشکال پخش ویدیو',
  'unclear': 'توضیح نامفهوم',
  'topic_request': 'پیشنهاد موضوع آموزشی',
};

/// Explicitly chosen feedback only; never extracts private conversations.
class LearningFeedbackSync {
  LearningFeedbackSync(this.api, {OfflineStore? store})
      : store = store ?? OfflineStore.forApi(api);
  final HttpIdentityApi api;
  final OfflineStore store;

  Future<Map<String, dynamic>> submit(Map<String, dynamic> body) async {
    final frozen =
        Map<String, dynamic>.from(jsonDecode(jsonEncode(body)) as Map);
    final mutationId = frozen['mutationId'] as String;
    await store.enqueue({
      'id': mutationId,
      'entityId': mutationId,
      'entityType': 'learning_feedback',
      'operation': 'create',
      'payload': frozen,
    });
    try {
      return await _send(mutationId, frozen);
    } catch (e) {
      if (isOfflineFailure(e)) return {'queued': true};
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _send(
      String mutationId, Map<String, dynamic> body) async {
    if (api.cacheNamespace != store.scope) {
      throw const ApiException(401, 'cache_scope_closed');
    }
    await store.readQueue();
    final result =
        await api.requestJson('POST', '/v1/education/feedback', body: body);
    if (api.cacheNamespace != store.scope) {
      throw const ApiException(401, 'cache_scope_closed');
    }
    final acknowledgement = result['acknowledgement'];
    final feedback = result['feedback'];
    final uuid =
        RegExp(r'^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$');
    bool date(dynamic value) =>
        value is String && DateTime.tryParse(value) != null;
    if (acknowledgement is! Map ||
        feedback is! Map ||
        acknowledgement['mutationId'] != mutationId ||
        !['accepted', 'already_applied'].contains(acknowledgement['status']) ||
        feedback['mutationId'] != mutationId ||
        feedback['id'] is! String ||
        !uuid.hasMatch(feedback['id'] as String) ||
        feedback['unitId'] != body['unitId'] ||
        feedback['category'] != body['category'] ||
        feedback['version'] is! int ||
        feedback['version'] < 1 ||
        !['received', 'triaged', 'planned', 'released', 'declined']
            .contains(feedback['status']) ||
        (feedback['withdrawnAt'] == null
            ? (feedback['summary'] != body['summary'] ||
                feedback['shareWithContentTeam'] != true)
            : (!date(feedback['withdrawnAt']) ||
                feedback['summary'] != null ||
                feedback['shareWithContentTeam'] != false)) ||
        acknowledgement['feedbackId'] != feedback['id'] ||
        !date(feedback['createdAt']) ||
        !date(feedback['updatedAt'])) {
      throw const ApiException(502, 'invalid_sync_acknowledgement');
    }
    // The chosen summary remains in the durable queue until acknowledged;
    // do not retain an extra offline copy after server acceptance/withdrawal.
    await store.acknowledge(mutationId,
        acceptedAt: feedback['createdAt'] as String);
    return {'queued': false, 'feedback': feedback};
  }

  Future<void> flush() async {
    for (final pending in await store.readQueue()) {
      if (pending['entityType'] != 'learning_feedback' ||
          pending['queueStatus'] != 'queued') {
        continue;
      }
      try {
        await _send(pending['id'] as String,
            Map<String, dynamic>.from(pending['payload'] as Map));
      } catch (e) {
        if (isOfflineFailure(e)) return;
        rethrow;
      }
    }
  }
}

class LearningFeedbackPage extends StatefulWidget {
  const LearningFeedbackPage({super.key, required this.api, this.unitId});
  final HttpIdentityApi api;
  final String? unitId;
  @override
  State<LearningFeedbackPage> createState() => _LearningFeedbackPageState();
}

class _LearningFeedbackPageState extends State<LearningFeedbackPage> {
  final summary = TextEditingController();
  String category = 'topic_request';
  bool consent = false, busy = false;
  String? message;
  Map<String, dynamic>? pendingBody;
  List<Map<String, dynamic>> history = [];
  int historyEpoch = 0;
  late final LearningFeedbackSync sync;
  @override
  void initState() {
    super.initState();
    sync = LearningFeedbackSync(widget.api);
    restoreDraft();
    loadHistory();
  }

  Future<void> loadHistory() async {
    final epoch = ++historyEpoch;
    try {
      final result =
          await widget.api.requestJson('GET', '/v1/me/education-feedback');
      if (result['feedback'] is! List) {
        throw const ApiException(502, 'invalid_api_response');
      }
      if (mounted &&
          epoch == historyEpoch &&
          widget.api.cacheNamespace == sync.store.scope) {
        setState(() => history = (result['feedback'] as List)
            .map((row) => Map<String, dynamic>.from(row as Map))
            .toList());
      }
    } catch (e) {
      if (mounted && epoch == historyEpoch) {
        setState(() {
          if (e is ApiException &&
              (e.statusCode == 401 || e.statusCode == 403)) {
            history = [];
          }
          message = learningError(e);
        });
      }
    }
  }

  Future<void> withdraw(String id) async {
    if (busy) return;
    ++historyEpoch; // Earlier reads must not resurrect a withdrawn summary.
    setState(() => busy = true);
    try {
      await widget.api.requestJson(
          'DELETE', '/v1/me/education-feedback/${Uri.encodeComponent(id)}');
      if (mounted) {
        setState(() => history.removeWhere((row) => row['id'] == id));
      }
      // Clear any acknowledged feedback cache from an earlier test build.
      await sync.store.writeList('education_feedback', []);
      if (mounted) await loadHistory();
    } catch (e) {
      if (mounted) setState(() => message = learningError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> restoreDraft() async {
    try {
      final pending = (await sync.store.readQueue())
          .where((m) =>
              m['entityType'] == 'learning_feedback' &&
              (m['payload'] as Map)['unitId'] == widget.unitId)
          .firstOrNull;
      if (pending != null && mounted) {
        setState(() {
          pendingBody = Map<String, dynamic>.from(pending['payload'] as Map);
          summary.text = pendingBody!['summary'].toString();
          category = pendingBody!['category'].toString();
          consent = true;
          message = 'بازخورد ارسال‌نشده روی این دستگاه نگه داشته شده است.';
        });
      }
    } catch (e) {
      if (mounted) setState(() => message = learningError(e));
    }
  }

  @override
  void dispose() {
    summary.dispose();
    super.dispose();
  }

  Future<void> send() async {
    if (!consent || summary.text.trim().isEmpty) {
      setState(() => message = 'خلاصه و رضایت ارسال را تکمیل کن.');
      return;
    }
    setState(() => busy = true);
    pendingBody ??= {
      'mutationId': newMutationId(),
      'unitId': widget.unitId,
      'category': category,
      'summary': summary.text.trim(),
      'shareWithContentTeam': true
    };
    try {
      final result = await sync.submit(pendingBody!);
      if (mounted) {
        setState(() {
          message = result['queued'] == true
              ? 'روی دستگاه ذخیره شد؛ هنوز تأیید سرور دریافت نشده است.'
              : 'بازخورد در سرور ثبت شد؛ بررسی و انتشار نتیجه هنوز انجام نشده است.';
          if (result['queued'] != true) {
            pendingBody = null;
            summary.clear();
            consent = false;
          }
        });
        if (result['queued'] != true && mounted) await loadHistory();
      }
    } catch (e) {
      if (mounted) setState(() => message = learningError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('بازخورد و پیشنهاد آموزش')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text(
            'فقط ایراد محتوا یا نیاز آموزشی را بنویس. نام افراد، گفت‌وگوی خصوصی، اطلاعات سلامت یا شرح آزار را در بازخورد توسعه ننویس. این بخش مشاوره یا رسیدگی اضطراری نیست.'),
        DropdownButtonFormField<String>(
            initialValue: category,
            items: feedbackCategories.entries
                .map((entry) => DropdownMenuItem(
                    value: entry.key, child: Text(entry.value)))
                .toList(),
            onChanged: busy || pendingBody != null
                ? null
                : (value) => setState(() => category = value!)),
        TextField(
            controller: summary,
            enabled: !busy && pendingBody == null,
            maxLength: 1000,
            maxLines: 5,
            decoration:
                const InputDecoration(labelText: 'خلاصه ایراد یا پیشنهاد')),
        CheckboxListTile(
            value: consent,
            onChanged: busy || pendingBody != null
                ? null
                : (value) => setState(() => consent = value == true),
            title: const Text(
                'می‌خواهم فقط همین خلاصه برای بررسی محتوا در اختیار تیم توسعه قرار گیرد.')),
        if (message != null) Text(message!),
        FilledButton(
            onPressed: busy ? null : send,
            child: Text(pendingBody == null
                ? 'ارسال بازخورد'
                : 'تلاش دوباره با همان بازخورد')),
        if (pendingBody != null)
          TextButton(
              onPressed: busy
                  ? null
                  : () async {
                      await sync.store.discardEntityChanges(
                          pendingBody!['mutationId'] as String,
                          cacheKey: 'education_feedback',
                          entityType: 'learning_feedback');
                      if (mounted) {
                        setState(() {
                          pendingBody = null;
                          consent = false;
                          message =
                              'تلاش بعدی ارسال متوقف شد و پیش‌نویس در سابقه بازیابی ماند. اگر پاسخ شبکه گم شده باشد، رکورد ممکن است در سرور ثبت شده باشد؛ فهرست ثبت‌شده را بررسی و رضایت را جدا پس بگیر.';
                        });
                      }
                    },
              child: const Text('خارج‌کردن پیش‌نویس از صف ارسال')),
        const Text(
            'این فرم فقط داده انتخاب‌شده تو را ارسال می‌کند؛ گفت‌وگو، یادداشت و اطلاعات خصوصی حساب استخراج نمی‌شود.'),
        const Divider(),
        const Text('بازخوردهای ثبت‌شده من'),
        ...history.map((row) => Card(
            child: ListTile(
                title: Text(row['withdrawnAt'] == null
                    ? row['summary']?.toString() ?? 'بازخورد'
                    : 'رضایت ارسال پس گرفته شد'),
                subtitle: Text(row['withdrawnAt'] == null
                    ? 'وضعیت بررسی: ${row['status'] ?? 'دریافت‌شده'}'
                    : 'متن بازخورد حذف شده است.'),
                trailing: row['withdrawnAt'] != null
                    ? null
                    : TextButton(
                        onPressed:
                            busy ? null : () => withdraw(row['id'].toString()),
                        child: const Text('پس‌گرفتن رضایت'))))),
      ]));
}
