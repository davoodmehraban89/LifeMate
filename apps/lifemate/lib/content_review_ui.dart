import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'content_review_sync.dart';
import 'learning_feedback_ui.dart' show feedbackCategories;
import 'offline_store.dart';
import 'plan_sync.dart' show newMutationId;

String contentReviewError(Object error) {
  if (isOfflineFailure(error)) {
    return 'اتصال برقرار نیست؛ متن‌های صندوق پاک شدند. دریافت تازه یا تلاش دستی لازم است.';
  }
  if (error is ApiException) {
    if (error.statusCode == 401 || error.statusCode == 403) {
      return 'مجوز معتبر بررسی محتوا لازم است. عضویت خانواده این دسترسی را نمی‌دهد.';
    }
    if (error.statusCode == 404) {
      return 'این بازخورد دیگر در دسترس نیست؛ ممکن است رضایت ارسال پس گرفته شده باشد.';
    }
    if (error.statusCode == 409) {
      return 'نسخه یا رضایت منبع تغییر کرده است. صندوق را تازه کن؛ تغییر یا پیشنهاد قدیمی تأیید نشد.';
    }
  }
  return 'پاسخ معتبر دریافت نشد؛ متن‌های قبلی نمایش داده نمی‌شوند.';
}

/// Online-only operations over voluntarily shared educational feedback. Parent
/// and family roles do not imply reviewer access; every server call checks it.
class ContentReviewPage extends StatefulWidget {
  const ContentReviewPage({super.key, required this.api});
  final HttpIdentityApi api;
  @override
  State<ContentReviewPage> createState() => _ContentReviewPageState();
}

class _ContentReviewPageState extends State<ContentReviewPage>
    with WidgetsBindingObserver {
  late final ContentReviewSync sync;
  Timer? poll;
  Set<String> permissions = {};
  List<Map<String, dynamic>> rows = [], pending = [];
  Set<String> selected = {};
  Map<String, dynamic>? brief;
  String? filter, cursor, nextCursor, message;
  int epoch = 0, total = 0;
  bool loading = false, mutating = false, active = true;
  DateTime? refreshedAt;

  bool get canReview => permissions.contains('feedback.review');
  bool get canPrepare => permissions.contains('brief.prepare');
  bool current(int request) =>
      mounted &&
      active &&
      request == epoch &&
      widget.api.cacheNamespace == sync.store.scope;

  @override
  void initState() {
    super.initState();
    sync = ContentReviewSync(widget.api);
    WidgetsBinding.instance.addObserver(this);
    refresh();
    poll = Timer.periodic(const Duration(seconds: 30), (_) {
      if (active && !mutating && !loading) refresh();
    });
  }

  void clearContent() {
    rows = [];
    permissions = {};
    selected = {};
    brief = null;
    refreshedAt = null;
    total = 0;
    nextCursor = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    active = state == AppLifecycleState.resumed;
    ++epoch;
    if (!mounted) return;
    setState(() {
      clearContent();
      loading = false;
    });
    if (active && !mutating) refresh();
  }

  @override
  void dispose() {
    ++epoch;
    poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> refresh({bool firstPage = false}) async {
    if (!mounted || !active || mutating) return;
    final request = ++epoch;
    if (firstPage) cursor = null;
    setState(() {
      clearContent();
      loading = true;
      message = null;
    });
    try {
      final granted = await sync.capabilities();
      if (!current(request)) return;
      final durable = await sync.pending();
      if (!current(request)) return;
      if (!granted.contains('feedback.read')) {
        setState(() {
          pending = durable;
          message = 'مجوز بررسی محتوا برای این حساب فعال نیست.';
          loading = false;
        });
        return;
      }
      final result = await sync.inbox(status: filter, cursor: cursor);
      if (!current(request)) return;
      setState(() {
        permissions = granted;
        pending = durable;
        rows = List<Map<String, dynamic>>.from(result['feedback'] as List);
        nextCursor = result['nextCursor'] as String?;
        total = result['total'] as int;
        refreshedAt = DateTime.now();
        loading = false;
      });
    } catch (error) {
      if (!current(request)) return;
      setState(() {
        clearContent();
        message = contentReviewError(error);
        loading = false;
        if (error is ApiException && error.statusCode == 404) cursor = null;
      });
    }
  }

  Future<void> action(Future<Map<String, dynamic>> Function() operation,
      {bool showBrief = false}) async {
    if (mutating || !active) return;
    final request = ++epoch;
    setState(() {
      mutating = true;
      clearContent();
      message = null;
    });
    Map<String, dynamic>? prepared;
    String? outcome;
    try {
      final result = await operation();
      if (!current(request)) return;
      prepared = result['brief'] as Map<String, dynamic>?;
      outcome =
          'تأیید سرور دریافت شد. این عملیات انتشار آموزش یا اجرای توسعه نیست.';
    } catch (error) {
      if (!current(request)) return;
      outcome = contentReviewError(error);
    } finally {
      if (mounted) setState(() => mutating = false);
    }
    if (!mounted || !active || widget.api.cacheNamespace != sync.store.scope) {
      return;
    }
    await refresh(firstPage: false);
    if (!mounted || !active || widget.api.cacheNamespace != sync.store.scope) {
      return;
    }
    // A failed refresh must not reintroduce a brief or hide revoked access.
    setState(() {
      if (showBrief && canPrepare && prepared != null) brief = prepared;
      message ??= outcome;
    });
  }

  Future<void> copyBrief() async {
    final id = brief?['id'] as String?;
    if (id == null || mutating || !active) return;
    final request = ++epoch;
    setState(() {
      mutating = true;
      brief = null;
      message = 'اعتبار رضایت و نسخه منابع در سرور دوباره بررسی می‌شود.';
    });
    try {
      final fresh = await sync.readBrief(id);
      if (!current(request)) return;
      final lines = <String>[
        fresh['title'] as String,
        'زمان تهیه: ${fresh['createdAt']}',
        'تعداد منابع رضایت‌داده: ${fresh['sourceCount']}',
        ...(fresh['categories'] as List).map(
            (row) => '${feedbackCategories[row['category']]}: ${row['count']}'),
        ...(fresh['units'] as List).map((row) =>
            'پایه ${row['gradeLevel']}، ${row['bookTitle']} (${row['bookCode']})، ${row['title']}؛ نسخه ${row['editionYear'] ?? 'نامشخص'}، ${row['editionStatus'] == 'verified' ? 'منبع بررسی‌شده' : 'نسخه تأییدنشده'}'),
        ...(fresh['tasks'] as List).cast<String>(),
        fresh['notice'] as String,
      ];
      await Clipboard.setData(ClipboardData(text: lines.join('\n')));
      if (!current(request)) return;
      setState(() {
        brief = fresh;
        message =
            'پیشنهاد ساختاری پس از بررسی تازه سرور کپی شد؛ متن بازخورد در آن نیست.';
      });
    } catch (error) {
      if (current(request)) {
        setState(() {
          clearContent();
          message = contentReviewError(error);
        });
      }
    } finally {
      if (mounted) setState(() => mutating = false);
    }
  }

  @override
  Widget build(BuildContext context) => Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
          appBar: AppBar(title: const Text('بررسی محتوای آموزشی'), actions: [
            IconButton(
                key: const Key('content-refresh'),
                tooltip: 'دریافت تازه از سرور',
                onPressed: mutating ? null : () => refresh(),
                icon: const Icon(Icons.refresh))
          ]),
          body: ListView(padding: const EdgeInsets.all(16), children: [
            const Text(
                'فقط خلاصه‌ای که کاربر با رضایت برای تیم محتوا فرستاده است نمایش داده می‌شود. این صندوق شامل گفت‌وگوها، یادداشت‌ها یا اطلاعات سلامت نیست.'),
            const SizedBox(height: 8),
            const Text(
                'متن‌های صندوق فقط هنگام اتصال در حافظه‌اند. پیشنهاد توسعه به‌صورت دستی بازبینی می‌شود؛ هوش مصنوعی، پیام‌رسانی و انتشار خودکار اجرا نمی‌شوند.'),
            if (loading || mutating) const LinearProgressIndicator(),
            Text(refreshedAt == null
                ? 'داده تازه تأییدشده در دسترس نیست.'
                : 'آخرین دریافت: ${refreshedAt!.hour.toString().padLeft(2, '0')}:${refreshedAt!.minute.toString().padLeft(2, '0')}؛ تازه‌سازی هر ۳۰ ثانیه، مجموع $total بازخورد.'),
            if (message != null)
              Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(message!)),
            DropdownButtonFormField<String>(
                key: ValueKey('content-filter-${filter ?? 'all'}'),
                initialValue: filter ?? 'all',
                decoration: const InputDecoration(labelText: 'فیلتر وضعیت'),
                items: [
                  const DropdownMenuItem(
                      value: 'all', child: Text('همه وضعیت‌ها')),
                  ...contentReviewStatuses.entries.map((entry) =>
                      DropdownMenuItem(
                          value: entry.key, child: Text(entry.value)))
                ],
                onChanged: mutating
                    ? null
                    : (value) {
                        filter = value == 'all' ? null : value;
                        refresh(firstPage: true);
                      }),
            ...rows.map((row) => Card(
                child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(row['summary'] as String),
                          const SizedBox(height: 6),
                          Text(
                              '${feedbackCategories[row['category']]} · ${contentReviewStatuses[row['status']]} · نسخه ${row['version']}'),
                          Text('زمان ثبت در سرور: ${row['createdAt']}'),
                          if (row['unitId'] == null)
                            const Text('پیشنهاد عمومی آموزش'),
                          if (canReview &&
                              contentReviewTransitions
                                  .containsKey(row['status']))
                            DropdownButtonFormField<String>(
                                key: Key('review-status-${row['id']}'),
                                decoration: const InputDecoration(
                                    labelText: 'تغییر مرحله بررسی'),
                                hint: const Text('انتخاب مرحله بعد'),
                                items: contentReviewTransitions[row['status']]!
                                    .map((status) => DropdownMenuItem(
                                        value: status,
                                        child: Text(
                                            contentReviewStatuses[status]!)))
                                    .toList(),
                                onChanged: mutating
                                    ? null
                                    : (value) {
                                        if (value == null) return;
                                        final body = {
                                          'mutationId': newMutationId(),
                                          'expectedVersion': row['version'],
                                          'status': value
                                        };
                                        action(() => sync.review(
                                            row['id'] as String, body));
                                      }),
                          if (canPrepare && row['status'] == 'planned')
                            CheckboxListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text(
                                    'انتخاب برای پیشنهاد ساختاری توسعه'),
                                value: selected.contains(row['id']),
                                onChanged: mutating
                                    ? null
                                    : (value) => setState(() {
                                          if (value == true &&
                                              selected.length < 20) {
                                            selected.add(row['id'] as String);
                                          }
                                          if (value != true) {
                                            selected.remove(row['id']);
                                          }
                                        })),
                        ])))),
            if (!loading &&
                permissions.contains('feedback.read') &&
                rows.isEmpty)
              const Text('بازخورد رضایت‌داده‌ای در این صفحه نیست.'),
            if (nextCursor != null)
              TextButton(
                  onPressed: mutating
                      ? null
                      : () {
                          cursor = nextCursor;
                          refresh();
                        },
                  child: const Text('صفحه بعد')),
            if (cursor != null)
              TextButton(
                  onPressed: mutating ? null : () => refresh(firstPage: true),
                  child: const Text('بازگشت به صفحه اول')),
            if (canPrepare)
              FilledButton(
                  onPressed: selected.isEmpty || mutating
                      ? null
                      : () {
                          final sources = rows
                              .where((row) => selected.contains(row['id']))
                              .map((row) => {
                                    'id': row['id'],
                                    'expectedVersion': row['version']
                                  })
                              .toList();
                          final body = {
                            'mutationId': newMutationId(),
                            'feedback': sources
                          };
                          action(() => sync.prepareBrief(body),
                              showBrief: true);
                        },
                  child: const Text('تهیه پیشنهاد توسعه، بدون متن بازخورد')),
            if (brief != null)
              Card(
                  child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(brief!['title'] as String),
                            Text('تعداد منابع: ${brief!['sourceCount']}'),
                            Text(brief!['notice'] as String),
                            TextButton(
                                key: const Key('copy-content-brief'),
                                onPressed: mutating ? null : copyBrief,
                                child: const Text(
                                    'بررسی دوباره منابع و کپی پیشنهاد')),
                          ]))),
            if (pending.isNotEmpty) ...[
              const Divider(),
              Text(
                  '${pending.length} عملیات بدون دریافت تأیید سرور یا با تعارض روی این دستگاه مانده است. فقط شناسه‌ها و مرحله در صف‌اند؛ ارسال خودکار انجام نمی‌شود.'),
              ...pending.map((row) => ListTile(
                  title: Text(row['entityType'] == 'content_review'
                      ? 'تغییر مرحله بررسی'
                      : 'تهیه پیشنهاد توسعه'),
                  subtitle: const Text(
                      'تلاش دستی با همان شناسه و نسخه؛ ممکن است عملیات قبلاً در سرور ثبت شده باشد.'),
                  trailing: TextButton(
                      onPressed: mutating ||
                              !permissions.contains('feedback.read') ||
                              !(row['entityType'] == 'content_review'
                                  ? canReview
                                  : canPrepare)
                          ? null
                          : () => action(() => sync.retry(row),
                              showBrief: row['entityType'] == 'content_brief'),
                      child: const Text('تلاش دوباره')))),
            ],
          ])));
}
