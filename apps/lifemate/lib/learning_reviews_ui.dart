import 'dart:async';

import 'package:flutter/material.dart';

import 'api.dart';
import 'offline_store.dart';

/// Owner-private server receipts, separate from unanswered/unsent work.
/// This page never grades answers or changes a learner's progress.
class LearningReviewsPage extends StatefulWidget {
  const LearningReviewsPage(
      {super.key, required this.api, required this.onOpenLesson});
  final HttpIdentityApi api;
  final Future<void> Function(BuildContext, String unitId) onOpenLesson;
  @override
  State<LearningReviewsPage> createState() => _LearningReviewsPageState();
}

class _LearningReviewsPageState extends State<LearningReviewsPage>
    with WidgetsBindingObserver {
  static final _uuid =
      RegExp(r'^[a-fA-F0-9]{8}(-[a-fA-F0-9]{4}){3}-[a-fA-F0-9]{12}$');
  List<Map<String, dynamic>> _reviews = [], _attempts = [];
  Map<String, Map<String, dynamic>> _titles = {};
  String? _scope, _error, _reviewsFetchedAt, _attemptsFetchedAt, _opening;
  OfflineStore? _store;
  int? _pending;
  int _epoch = 0;
  bool _busy = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bindScope();
    _startPoll();
    _load();
  }

  void _bindScope() {
    _scope = widget.api.cacheNamespace;
    _store = _scope == null ? null : OfflineStore.forApi(widget.api);
  }

  void _startPoll() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 30), (_) => _load());
  }

  void _clearServerData() {
    _reviews = [];
    _attempts = [];
    _titles = {};
    _reviewsFetchedAt = _attemptsFetchedAt = null;
  }

  @override
  void didUpdateWidget(covariant LearningReviewsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.api != widget.api || _scope != widget.api.cacheNamespace) {
      _epoch++;
      _busy = false;
      _pending = null;
      _opening = null;
      _clearServerData();
      _bindScope();
      _load();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startPoll();
      _load();
    } else {
      _poll?.cancel();
      _epoch++;
      if (mounted) {
        setState(() {
          _busy = false;
          _opening = null;
          _pending = null;
          _clearServerData();
        });
      }
    }
  }

  @override
  void dispose() {
    _epoch++;
    _poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  bool _current(int epoch) => mounted && epoch == _epoch;

  void _checkScope() {
    if (_scope == null || widget.api.cacheNamespace != _scope) {
      throw const ApiException(401, 'learning_history_scope_changed');
    }
  }

  Future<List<Map<String, dynamic>>> _guard() async {
    _checkScope();
    final queue = await _store!.readQueue();
    _checkScope();
    return queue;
  }

  static bool _instant(dynamic value) =>
      value is String &&
      RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(value) &&
      DateTime.tryParse(value) != null;
  static bool _id(dynamic value) => value is String && _uuid.hasMatch(value);
  static bool _text(dynamic value) =>
      value is String && value.trim().isNotEmpty && value.length <= 2000;
  static Never _invalid() =>
      throw const ApiException(502, 'invalid_learning_history_response');

  static List<Map<String, dynamic>> _parseReviews(
      Map<String, dynamic> response) {
    if (!_instant(response['fetchedAt']) || response['reviews'] is! List) {
      _invalid();
    }
    final rows = response['reviews'] as List;
    final units = <String>{};
    if (rows.length > 100) _invalid();
    return rows.map((row) {
      if (row is! Map ||
          !_id(row['unitId']) ||
          !units.add(row['unitId'] as String) ||
          !_instant(row['nextReviewAt']) ||
          row['schedulePolicy'] != 'pilot-1-or-3-days') {
        _invalid();
      }
      return Map<String, dynamic>.from(row);
    }).toList();
  }

  static List<Map<String, dynamic>> _parseAttempts(
      Map<String, dynamic> response) {
    if (!_instant(response['fetchedAt']) || response['attempts'] is! List) {
      _invalid();
    }
    final rows = response['attempts'] as List;
    final ids = <String>{};
    if (rows.length > 100) _invalid();
    return rows.map((row) {
      if (row is! Map ||
          !_id(row['attemptId']) ||
          !ids.add(row['attemptId'] as String) ||
          !_id(row['unitId']) ||
          !_id(row['assessmentId']) ||
          !_id(row['mutationId']) ||
          row['assessmentVersion'] is! int ||
          row['assessmentVersion'] < 1 ||
          row['source'] != 'quiz_answers' ||
          !['unsure', 'somewhat', 'confident'].contains(row['confidence']) ||
          row['total'] is! int ||
          row['total'] < 1 ||
          row['total'] > 20 ||
          row['correctCount'] is! int ||
          row['correctCount'] < 0 ||
          row['correctCount'] > row['total'] ||
          row['resultLabel'] !=
              (row['correctCount'] == row['total']
                  ? 'answered_correctly'
                  : 'needs_practice') ||
          !_instant(row['acceptedAt']) ||
          !_instant(row['nextReviewAt']) ||
          row['schedulePolicy'] != 'pilot-1-or-3-days' ||
          row['feedback'] is! List ||
          (row['feedback'] as List).length != row['total']) {
        _invalid();
      }
      final questions = <String>{};
      var correct = 0;
      for (final feedback in row['feedback'] as List) {
        if (feedback is! Map ||
            !_text(feedback['questionId']) ||
            !questions.add(feedback['questionId'] as String) ||
            !_text(feedback['objectiveId']) ||
            feedback['correct'] is! bool ||
            !_text(feedback['explanationFa']) ||
            !_text(feedback['remediationFa'])) {
          _invalid();
        }
        if (feedback['correct'] == true) correct++;
      }
      if (correct != row['correctCount']) _invalid();
      return Map<String, dynamic>.from(row);
    }).toList();
  }

  Future<Map<String, dynamic>> _locate(String id) async {
    try {
      final response = await widget.api
          .requestJson('GET', '/v1/education/units/${Uri.encodeComponent(id)}');
      _checkScope();
      final unit = response['unit'];
      if (!_instant(response['fetchedAt']) ||
          unit is! Map ||
          unit['id'] != id ||
          !_id(unit['courseId']) ||
          !_text(unit['titleFa'])) {
        _invalid();
      }
      return {...Map<String, dynamic>.from(unit), 'available': true};
    } catch (failure) {
      _checkScope();
      if (failure is ApiException && [401, 403].contains(failure.statusCode)) {
        rethrow;
      }
      return {
        'id': id,
        'titleFa': failure is ApiException && failure.statusCode == 404
            ? 'درس از دسترس خارج شده'
            : 'نام درس دریافت نشد',
        'available': false,
      };
    }
  }

  Future<Map<String, Map<String, dynamic>>> _locateTitles(
      Iterable<String> units, int epoch) async {
    final ids = units.toSet().take(100).toList();
    final titles = <String, Map<String, dynamic>>{};
    // Bounded requests; do not issue one unbounded Future per receipt.
    for (var at = 0; at < ids.length; at += 4) {
      if (!_current(epoch)) return {};
      final batch = ids.skip(at).take(4).toList();
      final result = await Future.wait(batch.map(_locate));
      _checkScope();
      for (var index = 0; index < batch.length; index++) {
        titles[batch[index]] = result[index];
      }
    }
    return titles;
  }

  String _failure(Object failure) {
    if (failure is ApiException && [401, 403].contains(failure.statusCode)) {
      return 'نشست یا دسترسی معتبر نیست؛ دوباره وارد حساب خود شوید.';
    }
    if (isOfflineFailure(failure)) {
      return 'اتصال برقرار نیست؛ تاریخچه تازه از سرور دریافت نشد.';
    }
    if (failure is ApiException && failure.code.startsWith('local_')) {
      return 'وضعیت ارسال‌های دستگاه خوانده نشد؛ داده‌ای حذف نشده است.';
    }
    return 'پاسخ معتبر دریافت نشد؛ دوباره تلاش کنید.';
  }

  Future<void> _load() async {
    if (_busy || !mounted || _opening != null) return;
    final epoch = ++_epoch;
    setState(() {
      _busy = true;
      _error = null;
      _clearServerData();
    });
    try {
      final queue = await _guard();
      if (!_current(epoch)) return;
      setState(() => _pending =
          queue.where((row) => row['entityType'] == 'learning_attempt').length);
      final responses = await Future.wait([
        widget.api.requestJson('GET', '/v1/me/learning-reviews'),
        widget.api.requestJson('GET', '/v1/me/learning-attempts'),
      ], eagerError: true);
      _checkScope();
      if (!_current(epoch)) return;
      final reviews = _parseReviews(responses[0]);
      final attempts = _parseAttempts(responses[1]);
      final titles = await _locateTitles([
        ...reviews.map((row) => row['unitId'] as String),
        ...attempts.map((row) => row['unitId'] as String),
      ], epoch);
      await _guard(); // Reject a handle invalidated while network was pending.
      if (!_current(epoch)) return;
      setState(() {
        _reviews = reviews;
        _attempts = attempts;
        _titles = titles;
        _reviewsFetchedAt = responses[0]['fetchedAt'] as String;
        _attemptsFetchedAt = responses[1]['fetchedAt'] as String;
      });
    } catch (failure) {
      if (!_current(epoch)) return;
      setState(() {
        _clearServerData();
        _error = _failure(failure);
        if (failure is ApiException &&
            [401, 403].contains(failure.statusCode)) {
          _pending = null;
        }
      });
    } finally {
      if (_current(epoch)) setState(() => _busy = false);
    }
  }

  Future<void> _open(String id) async {
    if (_opening != null || _busy) return;
    final epoch = _epoch;
    _poll?.cancel();
    setState(() => _opening = id);
    try {
      await _guard();
      if (!_current(epoch)) return;
      var title = _titles[id];
      if (title?['available'] != true) {
        title = await _locate(id);
        await _guard();
        if (!_current(epoch)) return;
        setState(() => _titles[id] = title!);
      }
      if (title?['available'] != true) {
        throw const ApiException(404, 'unit_not_available');
      }
      if (!mounted) return;
      await widget.onOpenLesson(context, id);
      await _guard();
    } catch (failure) {
      if (!_current(epoch)) return;
      setState(() {
        _error = failure is ApiException && failure.statusCode == 404
            ? 'این درس فعلاً در کتابخانه فعال در دسترس نیست.'
            : _failure(failure);
        if (failure is ApiException &&
            [401, 403].contains(failure.statusCode)) {
          _clearServerData();
          _pending = null;
        }
      });
    } finally {
      if (_current(epoch)) {
        setState(() => _opening = null);
        _startPoll();
      }
    }
  }

  String _title(String id) =>
      _titles[id]?['titleFa'] as String? ?? 'نام درس هنوز دریافت نشده';
  String _number(int value) {
    const digits = '۰۱۲۳۴۵۶۷۸۹';
    return value.toString().split('').map((v) => digits[int.parse(v)]).join();
  }

  Widget _review(Map<String, dynamic> row) {
    final id = row['unitId'] as String;
    final due = !DateTime.parse(row['nextReviewAt'] as String)
        .isAfter(DateTime.now().toUtc());
    return Card(
        key: Key('review-$id'),
        child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(_title(id),
                      style: Theme.of(context).textTheme.titleMedium),
                  Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Chip(
                          avatar: Icon(due ? Icons.history : Icons.schedule),
                          label: Text(due ? 'موعد رسیده' : 'مرور آینده'))),
                  Text('زمان پیشنهادی مرور: ${row['nextReviewAt']}'),
                  TextButton.icon(
                      key: Key('open-review-$id'),
                      onPressed:
                          _opening == null && !_busy ? () => _open(id) : null,
                      icon: const Icon(Icons.menu_book_outlined),
                      label: Text(_opening == id
                          ? 'در حال بازکردن…'
                          : 'بازکردن درس برای مرور')),
                ])));
  }

  Widget _attempt(Map<String, dynamic> row) {
    final id = row['unitId'] as String;
    final feedback = row['feedback'] as List;
    final confidence = switch (row['confidence']) {
      'confident' => 'مطمئن بودم',
      'somewhat' => 'تا حدی مطمئن بودم',
      _ => 'مطمئن نبودم',
    };
    return Card(
        key: Key('attempt-${row['attemptId']}'),
        child: ExpansionTile(
            title: Text(_title(id)),
            subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                      '${_number(row['correctCount'] as int)} پاسخ درست از ${_number(row['total'] as int)}'),
                  Text(row['resultLabel'] == 'needs_practice'
                      ? 'نیاز به تمرین'
                      : 'پاسخ‌های این تلاش درست بودند'),
                  Text('ثبت و تأیید سرور: ${row['acceptedAt']}'),
                  Text('اعتماد گزارش‌شده: $confidence'),
                  Text(
                      'نسخه آزمون: ${_number(row['assessmentVersion'] as int)}'),
                  const Text('برای دیدن توضیح پاسخ‌ها باز کنید.'),
                ]),
            children: [
              for (var index = 0; index < feedback.length; index++)
                Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                              'پرسش ${_number(index + 1)} · ${feedback[index]['correct'] == true ? 'پاسخ درست ثبت شد' : 'تمرین بیشتر پیشنهاد می‌شود'}'),
                          Text(feedback[index]['explanationFa'] as String),
                          Text(feedback[index]['remediationFa'] as String),
                        ])),
              TextButton.icon(
                  key: Key('open-attempt-${row['attemptId']}'),
                  onPressed:
                      _opening == null && !_busy ? () => _open(id) : null,
                  icon: const Icon(Icons.menu_book_outlined),
                  label: const Text('بازکردن درس')),
            ]));
  }

  @override
  Widget build(BuildContext context) => Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
          appBar: AppBar(title: const Text('مرور و تاریخچه یادگیری')),
          body: RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                  padding: const EdgeInsets.all(16),
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    const Text(
                        'نتیجه آزمون به‌تنهایی اثبات تسلط نیست. این صفحه فقط پاسخ‌های تصحیح‌شده و تأییدشده سرور را نشان می‌دهد.'),
                    const SizedBox(height: 8),
                    const Text(
                        'زمان مرور پیشنهاد آزمایشی ۱ یا ۳ روزه است؛ به معنی اجبار یا تضمین یادگیری نیست.'),
                    if (_pending != null)
                      Text(
                          'ارسال آزمون در انتظار تأیید یا بررسی روی این دستگاه: ${_number(_pending!)}'),
                    if (_busy) ...[
                      const SizedBox(height: 12),
                      const LinearProgressIndicator(),
                      const Text('در حال دریافت اطلاعات از سرور…'),
                    ],
                    if (_error != null)
                      Card(
                          child: ListTile(
                              leading: const Icon(Icons.warning_amber),
                              title: Text(_error!),
                              subtitle: const Text(
                                  'تأیید تازه دریافت نشده؛ پاسخ‌های ارسال‌نشده حذف نمی‌شوند.'))),
                    if (_reviewsFetchedAt != null) ...[
                      Text('دریافت مرورها از سرور: $_reviewsFetchedAt'),
                      Text('مرورهای موعددار',
                          style: Theme.of(context).textTheme.titleLarge),
                      if (_reviews.isEmpty) const Text('مروری ثبت نشده است.'),
                      ..._reviews.map(_review),
                    ],
                    if (_attemptsFetchedAt != null) ...[
                      Text('دریافت تاریخچه از سرور: $_attemptsFetchedAt'),
                      Text('تاریخچه آزمون‌های پذیرفته‌شده',
                          style: Theme.of(context).textTheme.titleLarge),
                      const Text('تا ۱۰۰ تلاش اخیر حساب خودتان از سرور'),
                      if (_attempts.isEmpty)
                        const Text('هنوز نتیجه پذیرفته‌شده‌ای ثبت نشده است.'),
                      ..._attempts.map(_attempt),
                    ],
                    TextButton.icon(
                        key: const Key('refresh-learning-history'),
                        onPressed: _busy || _opening != null ? null : _load,
                        icon: const Icon(Icons.refresh),
                        label: const Text('تازه‌سازی از سرور')),
                  ]))));
}
