import 'package:flutter/material.dart';

import 'api.dart';

class Phase4Hub extends StatefulWidget {
  const Phase4Hub({super.key, required this.api, this.adultShell = false});
  final IdentityApi api;
  final bool adultShell;

  @override
  State<Phase4Hub> createState() => _Phase4HubState();
}

class _Phase4HubState extends State<Phase4Hub> {
  late Future<List<Map<String, dynamic>>> goals;

  @override
  void initState() {
    super.initState();
    goals = widget.api.listLearningGoals();
  }

  Future<void> addGoal() async {
    final title = TextEditingController();
    final target = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('هدف یادگیری جدید'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: title,
              decoration: const InputDecoration(labelText: 'عنوان'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: target,
              decoration: const InputDecoration(labelText: 'هدف یا نتیجه مطلوب'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () async {
              if (title.text.trim().isEmpty) return;
              await widget.api.createLearningGoal(
                title: title.text.trim(),
                target: target.text.trim().isEmpty ? null : target.text.trim(),
              );
              if (dialogContext.mounted) Navigator.pop(dialogContext, true);
            },
            child: const Text('ذخیره'),
          ),
        ],
      ),
    );
    title.dispose();
    target.dispose();
    if (saved == true && mounted) {
      setState(() => goals = widget.api.listLearningGoals());
    }
  }

  Future<void> wellbeingCheckin() async {
    var mood = 3;
    var energy = 3;
    var stress = 3;
    var visibility = 'private';
    final note = TextEditingController();

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: const Text('ثبت حال امروز'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ScaleRow(
                  label: 'حال کلی',
                  value: mood,
                  onChanged: (v) => setLocalState(() => mood = v),
                ),
                _ScaleRow(
                  label: 'انرژی',
                  value: energy,
                  onChanged: (v) => setLocalState(() => energy = v),
                ),
                _ScaleRow(
                  label: 'استرس',
                  value: stress,
                  onChanged: (v) => setLocalState(() => stress = v),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: note,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'یادداشت خصوصی (اختیاری)',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: visibility,
                  decoration: const InputDecoration(labelText: 'اشتراک وضعیت'),
                  items: const [
                    DropdownMenuItem(
                      value: 'private',
                      child: Text('کاملاً خصوصی'),
                    ),
                    DropdownMenuItem(
                      value: 'guardian_summary',
                      child: Text('فقط در خلاصه آماری والد'),
                    ),
                  ],
                  onChanged: (v) {
                    if (v != null) setLocalState(() => visibility = v);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('انصراف'),
            ),
            FilledButton(
              onPressed: () async {
                await widget.api.createWellbeingCheckin(
                  mood: mood,
                  energy: energy,
                  stress: stress,
                  note: note.text.trim().isEmpty ? null : note.text.trim(),
                  visibility: visibility,
                );
                if (dialogContext.mounted) Navigator.pop(dialogContext, true);
              },
              child: const Text('ثبت'),
            ),
          ],
        ),
      ),
    );
    note.dispose();
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ثبت شد. متن یادداشت خصوصی باقی می‌ماند.')),
      );
    }
  }

  void openGuide(String kind, String title) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GuideChatPage(
          api: widget.api,
          kind: kind,
          title: title,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            widget.adultShell ? 'راهنمای هوشمند' : 'یادگیری و حال خوب',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 6),
          const Text(
            'راهنماها پیشنهاد می‌دهند؛ تصمیم و اجرای تغییرها با خودت است.',
          ),
          const SizedBox(height: 16),
          _GuideCard(
            icon: Icons.school_rounded,
            title: 'راهنمای مطالعه',
            subtitle: 'فهم بهتر، مرور فعال و برنامه مطالعه مرحله‌به‌مرحله.',
            onTap: () => openGuide('study', 'راهنمای مطالعه'),
          ),
          _GuideCard(
            icon: Icons.auto_awesome_rounded,
            title: 'راهنمای برنامه‌ریزی',
            subtitle: 'اولویت‌بندی و شکستن کارها بدون تغییر خودکار برنامه.',
            onTap: () => openGuide('planner', 'راهنمای برنامه‌ریزی'),
          ),
          _GuideCard(
            icon: Icons.self_improvement_rounded,
            title: 'همراه حال خوب',
            subtitle: 'گفت‌وگوی حمایتی و غیرتشخیصی برای حال، ارتباط و فشار روزمره.',
            onTap: () => openGuide('wellbeing', 'همراه حال خوب'),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: wellbeingCheckin,
                  icon: const Icon(Icons.favorite_outline),
                  label: const Text('ثبت حال امروز'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: addGoal,
                  icon: const Icon(Icons.flag_outlined),
                  label: const Text('هدف یادگیری'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'حریم خصوصی: متن گفت‌وگو و یادداشت حال خوب برای خود کاربر است. '
                'والد فقط خلاصه‌ای را می‌بیند که مجاز شده باشد؛ در وضعیت ایمنی جدی، '
                'سیگنال ایمنی جدا از متن خصوصی مدیریت می‌شود.',
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text('هدف‌های یادگیری', style: Theme.of(context).textTheme.titleMedium),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: goals,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snapshot.data!.isEmpty) {
                return const Card(
                  child: ListTile(
                    leading: Icon(Icons.flag_outlined),
                    title: Text('هنوز هدفی ثبت نشده'),
                  ),
                );
              }
              return Column(
                children: snapshot.data!
                    .map(
                      (goal) => Card(
                        child: ListTile(
                          leading: const Icon(Icons.flag_circle_outlined),
                          title: Text(goal['title']?.toString() ?? ''),
                          subtitle: Text(goal['target']?.toString() ?? ''),
                        ),
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ],
      );
}

class GuideChatPage extends StatefulWidget {
  const GuideChatPage({
    super.key,
    required this.api,
    required this.kind,
    required this.title,
  });

  final IdentityApi api;
  final String kind;
  final String title;

  @override
  State<GuideChatPage> createState() => _GuideChatPageState();
}

class _GuideChatPageState extends State<GuideChatPage> {
  final input = TextEditingController();
  final messages = <Map<String, String>>[];
  String? sessionId;
  bool busy = false;

  Future<void> send() async {
    final text = input.text.trim();
    if (text.isEmpty || busy) return;
    setState(() {
      busy = true;
      messages.add({'role': 'user', 'body': text});
      input.clear();
    });
    try {
      final session = sessionId == null
          ? await widget.api.createAiSession(widget.kind)
          : null;
      sessionId ??= session?['id']?.toString();
      if (sessionId == null) throw StateError('session_not_created');
      final reply = await widget.api.sendAiMessage(sessionId!, text);
      if (mounted) {
        setState(() {
          messages.add({
            'role': 'assistant',
            'body': reply['body']?.toString() ?? '',
          });
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          messages.add({
            'role': 'assistant',
            'body': 'ارسال انجام نشد. دوباره تلاش کن.',
          });
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                'این راهنما جای پزشک، روان‌شناس یا خدمات اضطراری نیست و تشخیص پزشکی نمی‌دهد.',
                textAlign: TextAlign.center,
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: messages.length,
                itemBuilder: (context, index) {
                  final item = messages[index];
                  final mine = item['role'] == 'user';
                  return Align(
                    alignment:
                        mine ? Alignment.centerRight : Alignment.centerLeft,
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 560),
                          child: Text(item['body'] ?? ''),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: input,
                        minLines: 1,
                        maxLines: 4,
                        onSubmitted: (_) => send(),
                        decoration: const InputDecoration(
                          hintText: 'اینجا بنویس...',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: busy ? null : send,
                      icon: busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send_rounded),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
}

class _GuideCard extends StatelessWidget {
  const _GuideCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          leading: Icon(icon),
          title: Text(title),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_left_rounded),
          onTap: onTap,
        ),
      );
}

class _ScaleRow extends StatelessWidget {
  const _ScaleRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          SizedBox(width: 70, child: Text(label)),
          Expanded(
            child: Slider(
              value: value.toDouble(),
              min: 1,
              max: 5,
              divisions: 4,
              label: value.toString(),
              onChanged: (v) => onChanged(v.round()),
            ),
          ),
          Text(value.toString()),
        ],
      );
}
