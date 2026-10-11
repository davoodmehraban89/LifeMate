import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'api.dart';
import 'offline_store.dart';
import 'plan_sync.dart' show newMutationId;

final _quizUuid =
    RegExp(r'^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$');
final _quizKey = RegExp(r'^[a-zA-Z0-9_-]{1,80}$');
const _confidences = {
  'unsure': 'مطمئن نیستم',
  'somewhat': 'تا حدی مطمئنم',
  'confident': 'مطمئنم',
};

bool _uuid(dynamic value) => value is String && _quizUuid.hasMatch(value);
bool _key(dynamic value) => value is String && _quizKey.hasMatch(value);
bool _text(dynamic value) =>
    value is String &&
    value.trim().isNotEmpty &&
    value.length <= 2000 &&
    !value.contains('\u0000');
bool _fields(Map value, Set<String> fields) =>
    value.length == fields.length && value.keys.every(fields.contains);

Map<String, dynamic> _attemptBody(Map<String, dynamic> value) {
  if (!_fields(value, {
        'mutationId',
        'assessmentId',
        'assessmentVersion',
        'answers',
        'confidence'
      }) ||
      !_uuid(value['mutationId']) ||
      !_uuid(value['assessmentId']) ||
      value['assessmentVersion'] is! int ||
      value['assessmentVersion'] < 1 ||
      !_confidences.containsKey(value['confidence']) ||
      value['answers'] is! List) {
    throw const ApiException(422, 'invalid_quiz_attempt');
  }
  final answers = value['answers'] as List;
  final questions = <String>{};
  if (answers.isEmpty || answers.length > 20) {
    throw const ApiException(422, 'invalid_quiz_attempt');
  }
  for (final answer in answers) {
    if (answer is! Map ||
        !_fields(answer, {'questionId', 'choiceId'}) ||
        !_key(answer['questionId']) ||
        !_key(answer['choiceId']) ||
        !questions.add(answer['questionId'] as String)) {
      throw const ApiException(422, 'invalid_quiz_attempt');
    }
  }
  // Own an immutable-by-caller snapshot before any asynchronous storage work.
  return Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);
}

/// Durable, account-scoped quiz answers. A quiz result never changes the
/// learner's separate, explicitly reported lesson-progress state.
class LearningQuizSync {
  LearningQuizSync(this.api, {OfflineStore? store})
      : store = store ?? OfflineStore.forApi(api);
  final HttpIdentityApi api;
  final OfflineStore store;
  static final _tails = <String, Future<void>>{};
  static const _cache = 'learning_attempts';

  void _scope() {
    if (api.cacheNamespace != store.scope) {
      throw const ApiException(401, 'cache_scope_closed');
    }
  }

  Future<T> _serial<T>(Future<T> Function() operation) {
    final previous = _tails[store.scope];
    final release = Completer<void>();
    _tails[store.scope] = release.future;
    return (() async {
      if (previous != null) await previous;
      try {
        _scope();
        await store.readQueue(); // Also checks the captured store generation.
        _scope();
        final result = await operation();
        _scope();
        return result;
      } finally {
        if (identical(_tails[store.scope], release.future)) {
          _tails.remove(store.scope);
        }
        release.complete();
      }
    })();
  }

  Future<List<Map<String, dynamic>>> pendingForUnit(String unitId) async {
    _scope();
    final pending = (await store.readQueue())
        .where((m) =>
            m['entityType'] == 'learning_attempt' && m['unitId'] == unitId)
        .toList();
    _scope();
    return pending;
  }

  Future<Map<String, dynamic>?> readAssessment(String unitId) =>
      _serial(() async {
        if (!_uuid(unitId)) {
          throw const ApiException(400, 'invalid_unit_id');
        }
        final response = await api.requestJson('GET',
            '/v1/education/units/${Uri.encodeComponent(unitId)}/assessment');
        _scope();
        // Check generation again before exposing a response to the old page.
        await store.readQueue();
        if (response['assessment'] == null &&
            response['reason'] == 'review_pending') {
          return null;
        }
        final raw = response['assessment'];
        if (raw is! Map ||
            !_fields(raw, {'id', 'unitId', 'version', 'questions'}) ||
            !_uuid(raw['id']) ||
            raw['unitId'] != unitId ||
            raw['version'] is! int ||
            raw['version'] < 1 ||
            raw['questions'] is! List) {
          throw const ApiException(502, 'invalid_quiz_assessment');
        }
        final questions = raw['questions'] as List;
        final ids = <String>{};
        if (questions.isEmpty || questions.length > 20) {
          throw const ApiException(502, 'invalid_quiz_assessment');
        }
        for (final question in questions) {
          if (question is! Map ||
              !_fields(
                  question, {'id', 'objectiveId', 'promptFa', 'choices'}) ||
              !_key(question['id']) ||
              !ids.add(question['id'] as String) ||
              !_key(question['objectiveId']) ||
              !_text(question['promptFa']) ||
              question['choices'] is! List) {
            throw const ApiException(502, 'invalid_quiz_assessment');
          }
          final choices = question['choices'] as List;
          final choiceIds = <String>{};
          if (choices.length < 2 || choices.length > 6) {
            throw const ApiException(502, 'invalid_quiz_assessment');
          }
          for (final choice in choices) {
            if (choice is! Map ||
                !_fields(choice, {'id', 'textFa'}) ||
                !_key(choice['id']) ||
                !choiceIds.add(choice['id'] as String) ||
                !_text(choice['textFa'])) {
              throw const ApiException(502, 'invalid_quiz_assessment');
            }
          }
        }
        return Map<String, dynamic>.from(raw);
      });

  Future<Map<String, dynamic>> submit(
      Map<String, dynamic> body, String unitId) {
    final frozen = _attemptBody(body);
    if (!_uuid(unitId)) throw const ApiException(422, 'invalid_unit_id');
    return _serial(() async {
      final pending = await pendingForUnit(unitId);
      if (pending.any((m) => m['id'] != frozen['mutationId'])) {
        throw const ApiException(409, 'sync_pending');
      }
      if (pending.any((m) => m['queueStatus'] != 'queued')) {
        throw const ApiException(409, 'quiz_pending_rejected');
      }
      final mutation = <String, dynamic>{
        'id': frozen['mutationId'],
        'entityId': frozen['mutationId'],
        'entityType': 'learning_attempt',
        'operation': 'submit',
        'unitId': unitId, // Local metadata; never put this in the POST body.
        'payload': frozen,
      };
      await store.enqueue(mutation);
      try {
        return {'queued': false, 'attempt': await _send(mutation)};
      } catch (error) {
        _scope();
        if (!isOfflineFailure(error)) rethrow;
        return {'queued': true, 'attempt': null};
      }
    });
  }

  Map<String, dynamic> _ack(
      Map<String, dynamic> raw, Map<String, dynamic> body, String unitId) {
    const fields = {
      'mutationId',
      'attemptId',
      'unitId',
      'assessmentId',
      'assessmentVersion',
      'correctCount',
      'total',
      'feedback',
      'resultLabel',
      'nextReviewAt',
      'schedulePolicy',
      'source',
      'acceptedAt'
    };
    Never invalid() =>
        throw const ApiException(502, 'invalid_sync_acknowledgement');
    DateTime? date(dynamic value) => value is String && value.endsWith('Z')
        ? DateTime.tryParse(value)
        : null;
    final accepted = date(raw['acceptedAt']);
    final next = date(raw['nextReviewAt']);
    final answers = body['answers'] as List;
    if (!_fields(raw, fields) ||
        raw['mutationId'] != body['mutationId'] ||
        !_uuid(raw['attemptId']) ||
        raw['unitId'] != unitId ||
        raw['assessmentId'] != body['assessmentId'] ||
        raw['assessmentVersion'] != body['assessmentVersion'] ||
        raw['total'] != answers.length ||
        raw['correctCount'] is! int ||
        raw['correctCount'] < 0 ||
        raw['correctCount'] > answers.length ||
        raw['feedback'] is! List ||
        raw['source'] != 'quiz_answers' ||
        raw['schedulePolicy'] != 'pilot-1-or-3-days' ||
        accepted == null ||
        next == null) {
      invalid();
    }
    final allCorrect = raw['correctCount'] == answers.length;
    if (raw['resultLabel'] !=
            (allCorrect ? 'answered_correctly' : 'needs_practice') ||
        next.difference(accepted) != Duration(days: allCorrect ? 3 : 1)) {
      invalid();
    }
    final questionIds = answers.map((a) => a['questionId']).toSet();
    final seen = <String>{};
    var count = 0;
    for (final feedback in raw['feedback'] as List) {
      if (feedback is! Map ||
          !_fields(feedback, {
            'questionId',
            'objectiveId',
            'correct',
            'explanationFa',
            'remediationFa'
          }) ||
          !_key(feedback['questionId']) ||
          !questionIds.contains(feedback['questionId']) ||
          !seen.add(feedback['questionId'] as String) ||
          !_key(feedback['objectiveId']) ||
          feedback['correct'] is! bool ||
          !_text(feedback['explanationFa']) ||
          !_text(feedback['remediationFa'])) {
        invalid();
      }
      if (feedback['correct'] == true) count++;
    }
    if (seen.length != answers.length || count != raw['correctCount']) {
      invalid();
    }
    return {...raw, 'id': raw['attemptId']};
  }

  Future<Map<String, dynamic>> _send(Map<String, dynamic> mutation) async {
    _scope();
    if (mutation['entityType'] != 'learning_attempt' ||
        mutation['operation'] != 'submit' ||
        !_uuid(mutation['unitId']) ||
        mutation['entityId'] != mutation['id'] ||
        mutation['payload'] is! Map) {
      throw const ApiException(422, 'invalid_quiz_attempt');
    }
    final body =
        _attemptBody(Map<String, dynamic>.from(mutation['payload'] as Map));
    if (body['mutationId'] != mutation['id']) {
      throw const ApiException(422, 'invalid_quiz_attempt');
    }
    await store.readQueue();
    _scope();
    final Map<String, dynamic> response;
    try {
      response =
          await api.requestJson('POST', '/v1/me/learning-attempts', body: body);
      _scope();
    } catch (error) {
      _scope();
      if (error is ApiException &&
          [400, 404, 409, 422].contains(error.statusCode)) {
        await store.markQueued(mutation['id'] as String,
            error.statusCode == 409 ? 'conflict' : 'rejected',
            error: error.code);
      }
      rethrow;
    }
    final attempt = _ack(response, body, mutation['unitId'] as String);
    await store.acknowledge(mutation['id'] as String,
        item: attempt,
        acceptedAt: attempt['acceptedAt'] as String,
        cacheKey: _cache);
    _scope();
    return attempt;
  }

  Future<void> flush() => _serial(() async {
        for (final mutation in await store.readQueue()) {
          if (mutation['entityType'] != 'learning_attempt') continue;
          if (mutation['queueStatus'] == 'conflict') {
            throw const ApiException(409, 'sync_conflict');
          }
          if (mutation['queueStatus'] != 'queued') continue;
          try {
            await _send(mutation);
          } catch (error) {
            if (isOfflineFailure(error)) return;
            rethrow;
          }
        }
      });

  /// Explicit cancellation stops retries and journals the original answers.
  /// It cannot undo an attempt that the server already accepted.
  Future<void> cancelPending(String mutationId) => _serial(() async {
        final queue = await store.readQueue();
        if (!queue.any((m) =>
            m['id'] == mutationId && m['entityType'] == 'learning_attempt')) {
          return;
        }
        await store.discardEntityChanges(mutationId,
            entityType: 'learning_attempt', cacheKey: _cache);
      });
}

class LearningQuizPage extends StatefulWidget {
  const LearningQuizPage({super.key, required this.api, required this.unitId});
  final HttpIdentityApi api;
  final String unitId;
  @override
  State<LearningQuizPage> createState() => _LearningQuizPageState();
}

class _LearningQuizPageState extends State<LearningQuizPage> {
  late final sync = LearningQuizSync(widget.api);
  Map<String, dynamic>? assessment, pending, attempt;
  final answers = <String, String>{};
  String? confidence, message;
  bool loading = true, busy = false;

  @override
  void initState() {
    super.initState();
    load();
  }

  bool get matchesPending =>
      pending == null ||
      (assessment?['id'] == pending!['assessmentId'] &&
          assessment?['version'] == pending!['assessmentVersion']);

  bool get complete =>
      assessment != null &&
      answers.length == (assessment!['questions'] as List).length &&
      confidence != null;

  void failure(Object error) {
    if (error is ApiException && [401, 403].contains(error.statusCode)) {
      assessment = pending = attempt = null;
      answers.clear();
      confidence = null;
      message = 'برای دیدن آزمون، دوباره وارد حساب خود شوید.';
    } else if (isOfflineFailure(error)) {
      message = pending == null
          ? 'برای دریافت آزمون بازبینی‌شده، اتصال به سرور لازم است.'
          : 'پاسخ‌ها روی این دستگاه نگه داشته شده‌اند؛ هنوز نتیجهٔ سرور دریافت نشده است.';
    } else if (error is ApiException && error.statusCode == 409) {
      message =
          'این ارسال به بررسی نیاز دارد. پاسخ‌ها حفظ شده‌اند؛ برای شروع دوباره، ارسال را لغو کنید.';
    } else {
      message =
          'آزمون یا تأیید نتیجه دریافت نشد. پاسخ‌های ثبت‌شده حذف نشده‌اند.';
    }
  }

  Future<void> load() async {
    try {
      final rows = await sync.pendingForUnit(widget.unitId);
      if (!mounted) return;
      if (rows.isNotEmpty) {
        pending = _attemptBody(
            Map<String, dynamic>.from(rows.first['payload'] as Map));
        for (final answer in pending!['answers'] as List) {
          answers[answer['questionId'] as String] =
              answer['choiceId'] as String;
        }
        confidence = pending!['confidence'] as String;
        message =
            'پاسخ‌ها روی این دستگاه نگه داشته شده‌اند؛ تا تأیید یا لغو، قابل تغییر نیستند.';
      }
      final bank = await sync.readAssessment(widget.unitId);
      if (mounted) setState(() => assessment = bank);
    } catch (error) {
      if (mounted) setState(() => failure(error));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> send() async {
    if (busy || (pending == null && !complete)) return;
    final body = pending ??
        {
          'mutationId': newMutationId(),
          'assessmentId': assessment!['id'],
          'assessmentVersion': assessment!['version'],
          'answers': [
            for (final question in assessment!['questions'] as List)
              {
                'questionId': question['id'],
                'choiceId': answers[question['id']]
              },
          ],
          'confidence': confidence,
        };
    setState(() {
      busy = true;
      message = null;
    });
    try {
      final result = await sync.submit(body, widget.unitId);
      if (!mounted) return;
      setState(() {
        if (result['queued'] == true) {
          pending = _attemptBody(body);
          message =
              'پاسخ‌ها روی این دستگاه نگه داشته شده‌اند؛ هنوز نتیجهٔ سرور دریافت نشده است.';
        } else {
          pending = null;
          attempt = Map<String, dynamic>.from(result['attempt'] as Map);
        }
      });
    } catch (error) {
      // A permanent rejection or malformed acknowledgement also leaves a
      // durable pending record, and must never unlock answers for a new ID.
      try {
        final rows = await sync.pendingForUnit(widget.unitId);
        if (rows.isNotEmpty) pending = _attemptBody(body);
      } catch (_) {/* Keep the original scope/storage error below. */}
      if (mounted) setState(() => failure(error));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> cancel() async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('لغو تلاش برای ارسال؟'),
              content: const Text(
                  'ممکن است سرور قبلاً این پاسخ‌ها را دریافت کرده باشد. لغو فقط تلاش بعدی این دستگاه را متوقف می‌کند و نتیجهٔ سرور را حذف نمی‌کند. پاسخ‌ها در سابقهٔ بازیابی محلی نگه داشته می‌شوند.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('بازگشت')),
                TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('لغو ارسال')),
              ],
            ));
    if (confirmed != true || !mounted || pending == null) return;
    setState(() => busy = true);
    try {
      await sync.cancelPending(pending!['mutationId'] as String);
      if (mounted) {
        setState(() {
          pending = null;
          answers.clear();
          confidence = null;
          message = 'تلاش برای ارسال لغو شد.';
        });
      }
    } catch (error) {
      if (mounted) setState(() => failure(error));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          appBar: AppBar(title: const Text('تمرین پس از درس')),
          body: loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(padding: const EdgeInsets.all(20), children: [
                  const Text(
                      'این تمرین بر اساس پاسخ‌های شماست؛ نتیجه، نشانهٔ قطعی تسلط یا مطالعهٔ واقعی نیست و وضعیت درس را خودکار تغییر نمی‌دهد.'),
                  if (message != null)
                    Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(message!)),
                  if (attempt != null) ...[
                    Text(
                        '${attempt!['correctCount']} از ${attempt!['total']} پاسخ درست',
                        style: Theme.of(context).textTheme.titleLarge),
                    for (final feedback in attempt!['feedback'] as List)
                      Card(
                          child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(feedback['correct'] == true
                                        ? 'پاسخ درست بود'
                                        : 'این بخش به تمرین نیاز دارد'),
                                    Text(feedback['explanationFa'] as String),
                                    Text(feedback['remediationFa'] as String),
                                  ]))),
                    Text(
                        'مرور بعدی: ${DateTime.parse(attempt!['nextReviewAt'] as String).toLocal().toString().split(" ").first}. این زمان‌بندی پیشنهاد آزمایشی ۱ یا ۳ روزه است، نه تضمین بهترین زمان یادگیری.'),
                  ] else ...[
                    if (assessment == null && message == null)
                      const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Text(
                              'آزمون این درس در انتظار بازبینی است. تا تأیید محتوای آن، پرسشی نمایش داده نمی‌شود.')),
                    if (assessment != null && matchesPending) ...[
                      for (final question in assessment!['questions'] as List)
                        Card(
                            child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Text(question['promptFa'] as String,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium),
                                      const SizedBox(height: 8),
                                      for (final choice
                                          in question['choices'] as List)
                                        Align(
                                            alignment: AlignmentDirectional
                                                .centerStart,
                                            child: ChoiceChip(
                                              key: Key(
                                                  'quiz-choice-${question['id']}-${choice['id']}'),
                                              label: Text(
                                                  choice['textFa'] as String),
                                              selected:
                                                  answers[question['id']] ==
                                                      choice['id'],
                                              onSelected:
                                                  pending != null || busy
                                                      ? null
                                                      : (_) => setState(() =>
                                                          answers[question['id']
                                                                  as String] =
                                                              choice['id']
                                                                  as String),
                                            )),
                                    ]))),
                      const Text('چقدر به پاسخ‌هایتان مطمئن هستید؟'),
                      Wrap(spacing: 8, children: [
                        for (final entry in _confidences.entries)
                          ChoiceChip(
                              key: Key('quiz-confidence-${entry.key}'),
                              label: Text(entry.value),
                              selected: confidence == entry.key,
                              onSelected: pending != null || busy
                                  ? null
                                  : (_) =>
                                      setState(() => confidence = entry.key)),
                      ]),
                    ],
                    if (pending != null) ...[
                      if (!matchesPending)
                        const Text(
                            'نسخهٔ پاسخ‌های ذخیره‌شده با آزمون فعلی متفاوت است. ارسال دوباره، همان پاسخ‌ها و نسخهٔ اصلی را می‌فرستد.'),
                      FilledButton(
                          key: const Key('quiz-retry'),
                          onPressed: busy ? null : send,
                          child: const Text('تلاش دوباره برای همان ارسال')),
                      TextButton(
                          key: const Key('quiz-cancel'),
                          onPressed: busy ? null : cancel,
                          child: const Text('لغو تلاش برای ارسال')),
                    ] else if (assessment != null)
                      FilledButton(
                          key: const Key('quiz-submit'),
                          onPressed: complete && !busy ? send : null,
                          child: const Text('ثبت پاسخ‌ها و دریافت بازخورد')),
                  ],
                  if (busy) const Center(child: CircularProgressIndicator()),
                ]),
        ),
      );
}
