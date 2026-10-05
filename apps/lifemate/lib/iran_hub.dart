import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'api.dart';

String iranStageLabel(int grade) {
  if (grade <= 3) return 'دوره اول ابتدایی';
  if (grade <= 6) return 'دوره دوم ابتدایی';
  if (grade <= 9) return 'دوره اول متوسطه';
  return 'دوره دوم متوسطه';
}

int iranLocalYear(int grade) {
  if (grade <= 3) return grade;
  if (grade <= 6) return grade - 3;
  if (grade <= 9) return grade - 6;
  return grade - 9;
}

class IranianFamilyLearningHub extends StatefulWidget {
  const IranianFamilyLearningHub({super.key, required this.identity});
  final IdentityApi identity;

  @override
  State<IranianFamilyLearningHub> createState() => _IranianFamilyLearningHubState();
}

class _IranianFamilyLearningHubState extends State<IranianFamilyLearningHub> {
  int grade = 7;
  String persona = 'child';
  late Future<List<Map<String, dynamic>>> data;

  String get baseUrl => const String.fromEnvironment(
        'LIFEMATE_API_URL',
        defaultValue: 'http://localhost:8080',
      );

  Future<Map<String, dynamic>> request(String method, String path,
      {Map<String, dynamic>? body}) async {
    final req = http.Request(method, Uri.parse('$baseUrl$path'))
      ..headers.addAll({
        'content-type': 'application/json',
        'authorization': 'Bearer ${widget.identity.accessToken ?? ''}',
      });
    if (body != null) req.body = jsonEncode(body);
    final res = await http.Response.fromStream(await req.send());
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('request_failed_${res.statusCode}');
    }
    return res.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(res.body) as Map<String, dynamic>;
  }

  @override
  void initState() {
    super.initState();
    data = load();
  }

  Future<List<Map<String, dynamic>>> load() async => [
        await request('GET', '/v1/me/iran-profile'),
        await request('GET', '/v1/education/catalog?grade=$grade&schoolYear=1405-1406'),
        await request('GET', '/v1/calendar/iran?year=1405'),
        await request('GET', '/v1/me/notification-preferences'),
        await request('GET', '/v1/me/menstrual-cycles'),
      ];

  Future<void> saveProfile() async {
    await request('PATCH', '/v1/me/iran-profile', body: {
      'householdPersona': persona,
    });
    if (persona == 'child') {
      await request('PUT', '/v1/me/education', body: {
        'nationalGrade': grade,
        'schoolYear': '1405-1406',
      });
    }
    setState(() => data = load());
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('خانواده و یادگیری ایران')),
        body: FutureBuilder<List<Map<String, dynamic>>>(
          future: data,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final profile = snapshot.data![0];
            final catalog = snapshot.data![1]['subjects'] as List<dynamic>? ?? const [];
            final events = snapshot.data![2]['events'] as List<dynamic>? ?? const [];
            final cycles = snapshot.data![4]['entries'] as List<dynamic>? ?? const [];
            persona = profile['household_persona']?.toString() ?? persona;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('پروفایل ایرانی', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: persona,
                  decoration: const InputDecoration(labelText: 'نقش'),
                  items: const [
                    DropdownMenuItem(value: 'mother', child: Text('مادر')),
                    DropdownMenuItem(value: 'father', child: Text('پدر')),
                    DropdownMenuItem(value: 'child', child: Text('فرزند')),
                    DropdownMenuItem(value: 'adult', child: Text('بزرگسال')),
                  ],
                  onChanged: (value) => setState(() => persona = value ?? persona),
                ),
                if (persona == 'child') ...[
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    value: grade,
                    decoration: const InputDecoration(labelText: 'پایه تحصیلی'),
                    items: [
                      for (var g = 1; g <= 12; g++)
                        DropdownMenuItem(
                          value: g,
                          child: Text('پایه $g — ${iranStageLabel(g)}، سال ${iranLocalYear(g)}'),
                        ),
                    ],
                    onChanged: (value) => setState(() => grade = value ?? grade),
                  ),
                ],
                const SizedBox(height: 8),
                FilledButton(onPressed: saveProfile, child: const Text('ذخیره پروفایل')),
                const Divider(height: 32),
                Text('کتاب‌ها و درس‌ها', style: Theme.of(context).textTheme.titleLarge),
                const Text('منبع رسمی کتاب‌ها لینک می‌شود؛ PDF بدون مجوز بازتوزیع داخل برنامه بسته‌بندی نمی‌شود.'),
                ...catalog.map((raw) {
                  final row = Map<String, dynamic>.from(raw as Map);
                  return ListTile(
                    leading: const Icon(Icons.menu_book_outlined),
                    title: Text(row['name_fa']?.toString() ?? ''),
                    subtitle: Text(row['source_url']?.toString() ?? ''),
                  );
                }),
                const Divider(height: 32),
                Text('تقویم جلالی ۱۴۰۵', style: Theme.of(context).textTheme.titleLarge),
                const Text('هفته از شنبه آغاز می‌شود؛ پنج‌شنبه و جمعه آخرهفته پیش‌فرض‌اند.'),
                ...events.take(12).map((raw) {
                  final row = Map<String, dynamic>.from(raw as Map);
                  return ListTile(
                    leading: Icon(row['is_official_holiday'] == true
                        ? Icons.event_busy_outlined
                        : Icons.event_outlined),
                    title: Text(row['title_fa']?.toString() ?? ''),
                    subtitle: Text('${row['jalali_month']}/${row['jalali_day']}'),
                  );
                }),
                const Divider(height: 32),
                Text('چرخه شخصی', style: Theme.of(context).textTheme.titleLarge),
                const Text('این بخش فقط برای صاحب حساب است و کاربرد تشخیصی ندارد.'),
                Text('${cycles.length} ثبت خصوصی'),
              ],
            );
          },
        ),
      );
}
