import 'package:flutter/material.dart';
import 'api.dart';
import 'phase3_ui.dart';

String iranStageLabel(int grade) => grade <= 3
    ? 'دوره اول ابتدایی'
    : grade <= 6
        ? 'دوره دوم ابتدایی'
        : grade <= 9
            ? 'دوره اول متوسطه'
            : 'دوره دوم متوسطه';
int iranLocalYear(int grade) => grade <= 3
    ? grade
    : grade <= 6
        ? grade - 3
        : grade <= 9
            ? grade - 6
            : grade - 9;

class IranianFamilyLearningHub extends StatefulWidget {
  const IranianFamilyLearningHub({super.key, required this.identity});
  final IdentityApi identity;
  @override
  State<IranianFamilyLearningHub> createState() => _IranHubState();
}

class _IranHubState extends State<IranianFamilyLearningHub> {
  int grade = 7;
  String persona = 'child', sex = 'unspecified';
  final birth = TextEditingController();
  late Future<List<Map<String, dynamic>>> data;
  bool busy = false, profileLoaded = false;
  String? error;
  Future<Map<String, dynamic>> request(String method, String path,
      {Map<String, dynamic>? body}) {
    final api = widget.identity;
    if (api is! HttpIdentityApi) {
      throw const ApiException(503, 'configured_api_required');
    }
    return api.requestJson(method, path, body: body);
  }

  @override
  void initState() {
    super.initState();
    data = load();
  }

  @override
  void dispose() {
    birth.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> load() async {
    final profile = await request('GET', '/v1/me/iran-profile');
    if (!profileLoaded) {
      final row = profile['profile'] as Map? ?? profile;
      persona = row['household_persona']?.toString() ??
          row['householdPersona']?.toString() ??
          persona;
      sex = row['sex']?.toString() ?? sex;
      birth.text =
          row['birth_date']?.toString() ?? row['birthDate']?.toString() ?? '';
      profileLoaded = true;
    }
    return [
      profile,
      await request(
          'GET', '/v1/education/catalog?grade=$grade&schoolYear=1405-1406'),
      await request('GET', '/v1/calendar/iran?year=1405'),
      await request('GET', '/v1/me/notification-preferences')
    ];
  }

  void reload() {
    setState(() {
      data = load();
    });
  }

  Future<void> mutate(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
      if (mounted) {
        reload();
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('سرور تغییر را تأیید کرد.')));
      }
    } catch (e) {
      if (mounted) setState(() => error = uiErrorText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save() => mutate(() async {
        await request('PATCH', '/v1/me/iran-profile', body: {
          'householdPersona': persona,
          'sex': sex,
          'birthDate': birth.text.trim().isEmpty ? null : birth.text.trim()
        });
        if (persona == 'child') {
          await request('PUT', '/v1/me/education',
              body: {'nationalGrade': grade, 'schoolYear': '1405-1406'});
        }
      });
  Future<void> preference(String key, bool value) => mutate(() async {
        await request('PATCH', '/v1/me/notification-preferences',
            body: {key: value});
      });
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('خانواده و یادگیری ایران')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
          future: data,
          builder: (context, s) {
            if (s.hasError) return LoadError(error: s.error!, retry: reload);
            if (!s.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final prefs = s.data![3]['preferences'] as Map? ?? s.data![3];
            final catalog = s.data![1]['subjects'] as List? ?? [];
            final events = s.data![2]['events'] as List? ?? [];
            return ListView(padding: const EdgeInsets.all(16), children: [
              if (busy) const LinearProgressIndicator(),
              if (error != null)
                Text(error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              Text('پروفایل ایرانی',
                  style: Theme.of(context).textTheme.titleLarge),
              const Text(
                  'این انتخاب، نقش خانواده یا دسترسی سرپرستی ایجاد نمی‌کند.'),
              DropdownButtonFormField<String>(
                  initialValue: persona,
                  decoration: const InputDecoration(labelText: 'نقش نمایشی'),
                  items: const [
                    DropdownMenuItem(value: 'mother', child: Text('مادر')),
                    DropdownMenuItem(value: 'father', child: Text('پدر')),
                    DropdownMenuItem(value: 'child', child: Text('فرزند')),
                    DropdownMenuItem(value: 'adult', child: Text('بزرگسال'))
                  ],
                  onChanged: busy
                      ? null
                      : (v) => setState(() => persona = v ?? persona)),
              DropdownButtonFormField<String>(
                  initialValue: sex,
                  decoration: const InputDecoration(labelText: 'جنسیت'),
                  items: const [
                    DropdownMenuItem(value: 'female', child: Text('دختر / زن')),
                    DropdownMenuItem(value: 'male', child: Text('پسر / مرد')),
                    DropdownMenuItem(
                        value: 'unspecified', child: Text('ذکر نشود'))
                  ],
                  onChanged:
                      busy ? null : (v) => setState(() => sex = v ?? sex)),
              TextField(
                  controller: birth,
                  enabled: !busy,
                  decoration: const InputDecoration(
                      labelText: 'تاریخ تولد (YYYY-MM-DD)')),
              if (persona == 'child')
                DropdownButtonFormField<int>(
                    initialValue: grade,
                    decoration: const InputDecoration(labelText: 'پایه تحصیلی'),
                    items: [
                      for (var g = 1; g <= 12; g++)
                        DropdownMenuItem(
                            value: g,
                            child: Text(
                                'پایه $g — ${iranStageLabel(g)}، سال ${iranLocalYear(g)}'))
                    ],
                    onChanged: busy
                        ? null
                        : (v) {
                            setState(() => grade = v ?? grade);
                            reload();
                          }),
              FilledButton(
                  onPressed: busy ? null : save,
                  child: const Text('ذخیره پروفایل')),
              const Divider(),
              Text('کتاب‌ها و درس‌ها',
                  style: Theme.of(context).textTheme.titleLarge),
              const Text(
                  'منبع رسمی کتاب‌ها لینک می‌شود؛ PDF بدون مجوز بازتوزیع بسته‌بندی نمی‌شود. اعتبار هر منبع نیازمند بررسی ناشر است.'),
              ...catalog.map((raw) {
                final r = raw as Map;
                return ListTile(
                    leading: const Icon(Icons.menu_book_outlined),
                    title: Text(r['name_fa']?.toString() ?? ''),
                    subtitle:
                        SelectableText(r['source_url']?.toString() ?? ''));
              }),
              const Divider(),
              Text('تقویم جلالی ۱۴۰۵',
                  style: Theme.of(context).textTheme.titleLarge),
              const Text(
                  'هفته از شنبه آغاز می‌شود؛ پنج‌شنبه و جمعه آخرهفته پیش‌فرض‌اند.'),
              ...events.take(40).map((raw) {
                final r = raw as Map;
                return ListTile(
                    leading: Icon(r['is_official_holiday'] == true
                        ? Icons.event_busy_outlined
                        : Icons.event_outlined),
                    title: Text(r['title_fa']?.toString() ?? ''),
                    subtitle: Text('${r['jalali_month']}/${r['jalali_day']}'));
              }),
              const Divider(),
              Text('یادآوری و اعلان',
                  style: Theme.of(context).textTheme.titleLarge),
              for (final entry in {
                'inAppBanner': 'بنر داخل برنامه',
                'schoolReminders': 'یادآوری مدرسه',
                'calendarReminders': 'یادآوری تقویم'
              }.entries)
                SwitchListTile(
                    title: Text(entry.value),
                    value: prefs[switch (entry.key) {
                          'inAppBanner' => 'in_app_banner',
                          'schoolReminders' => 'school_reminders',
                          _ => 'calendar_reminders'
                        }] ==
                        true,
                    onChanged: busy ? null : (v) => preference(entry.key, v)),
              const Divider(),
              const Text(
                  'قابلیت‌های سلامت، چرخه شخصی و راهنمای هوشمند در این مرحله فعال نیستند.'),
            ]);
          }));
}
