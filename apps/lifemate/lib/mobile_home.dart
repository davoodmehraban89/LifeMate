import 'package:flutter/material.dart';

/// Presentation only. Categories choose menus; API permissions remain server-side.
class MobileHomeMenu extends StatelessWidget {
  const MobileHomeMenu(
      {super.key,
      required this.displayName,
      required this.adult,
      required this.onOpen});
  final String displayName;
  final bool adult;
  final ValueChanged<String> onOpen;

  static const ink = Color(0xFF245B4E);
  static const paper = Color(0xFFF4F5EE);
  static const accent = Color(0xFF226F5C);

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final compact = box.maxHeight < 590;
        final menus = adult
            ? const [
                (
                  'plan',
                  'برنامه من',
                  'کارها و زمان‌های شخصی',
                  Icons.event_note_outlined,
                  Color(0xFFE7EEDC)
                ),
                (
                  'family',
                  'خانواده',
                  'اعضا و تنظیمات اشتراک',
                  Icons.people_outline,
                  Color(0xFFF4E4E8)
                ),
                (
                  'report',
                  'گزارش‌های مجاز',
                  'انتخاب خانواده و فرزند',
                  Icons.bar_chart_outlined,
                  Color(0xFFE5EFF3)
                ),
                (
                  'reminders',
                  'یادآوری‌ها',
                  'پیام‌های داخل برنامه',
                  Icons.notifications_none,
                  Color(0xFFF5EED8)
                ),
              ]
            : const [
                (
                  'plan',
                  'برنامه من',
                  'کارها و تکلیف‌ها',
                  Icons.event_note_outlined,
                  Color(0xFFE7EEDC)
                ),
                (
                  'courses',
                  'درس‌های من',
                  'پایه، کتاب و یادگیری',
                  Icons.menu_book_outlined,
                  Color(0xFFF6E7DC)
                ),
                (
                  'focus',
                  'وقت تمرکز',
                  'مطالعه با تایمر',
                  Icons.timelapse_outlined,
                  Color(0xFFECE6F7)
                ),
                (
                  'family',
                  'خانواده',
                  'حساب و اشتراک‌گذاری',
                  Icons.people_outline,
                  Color(0xFFF4E4E8)
                ),
                (
                  'report',
                  'گزارش من',
                  'مرور و تاریخچه یادگیری',
                  Icons.bar_chart_outlined,
                  Color(0xFFF5EED8)
                ),
                (
                  'reminders',
                  'یادآوری‌ها',
                  'پیام‌های داخل برنامه',
                  Icons.notifications_none,
                  Color(0xFFE5EFF3)
                ),
              ];
        return SingleChildScrollView(
            key: const ValueKey('home-scroll'),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            child: Center(
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('سلام $displayName',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(
                                      color: ink, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 5),
                          Text(
                              adult
                                  ? 'فضای شخصی و خانوادگی تو'
                                  : 'امروز از کدام قدم شروع کنیم؟',
                              style: const TextStyle(
                                  color: Color(0xFF6E7C6D), fontSize: 13)),
                          SizedBox(height: compact ? 12 : 20),
                          Container(
                              width: double.infinity,
                              padding: EdgeInsets.all(compact ? 14 : 20),
                              decoration: BoxDecoration(
                                  color: adult
                                      ? const Color(0xFFE2EDF0)
                                      : const Color(0xFFE4EED7),
                                  borderRadius: BorderRadius.circular(24)),
                              child: Row(children: [
                                Expanded(
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                      Text(
                                          adult
                                              ? 'کنار هم، با برنامه‌ای روشن'
                                              : 'یک شروع کوچک، یک قدم جلوتر',
                                          style: TextStyle(
                                              color: ink,
                                              fontSize: compact ? 17 : 21,
                                              fontWeight: FontWeight.w600)),
                                      const SizedBox(height: 8),
                                      Text(
                                          adult
                                              ? 'برنامه شخصی و اطلاعاتی که با تو به اشتراک گذاشته شده‌اند.'
                                              : 'برنامه‌ات را ببین، یک کار انتخاب کن و شروع کن.',
                                          style: const TextStyle(
                                              color: ink, fontSize: 12)),
                                    ])),
                                if (box.maxWidth > 340) ...[
                                  const SizedBox(width: 14),
                                  ExcludeSemantics(
                                      child: Icon(
                                          adult
                                              ? Icons.diversity_1_outlined
                                              : Icons.route_outlined,
                                          size: compact ? 45 : 68,
                                          color:
                                              accent.withValues(alpha: .55))),
                                ],
                              ])),
                          SizedBox(height: compact ? 12 : 20),
                          const Text('همه چیز، سر جای خودش',
                              style: TextStyle(color: ink, fontSize: 13)),
                          const SizedBox(height: 10),
                          GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount:
                                          MediaQuery.textScalerOf(context)
                                                      .scale(1) >
                                                  1.3
                                              ? 1
                                              : 2,
                                      crossAxisSpacing: 10,
                                      mainAxisSpacing: 10,
                                      mainAxisExtent: (compact ? 88.0 : 100.0) *
                                          MediaQuery.textScalerOf(context)
                                              .scale(1)
                                              .clamp(1, 1.8)),
                              itemCount: menus.length,
                              itemBuilder: (context, index) {
                                final (id, title, subtitle, icon, tint) =
                                    menus[index];
                                return _HomeTile(
                                    id: id,
                                    title: title,
                                    subtitle: subtitle,
                                    icon: icon,
                                    tint: tint,
                                    onTap: () => onOpen(id));
                              }),
                        ]))));
      });
}

class _HomeTile extends StatelessWidget {
  const _HomeTile(
      {required this.id,
      required this.title,
      required this.subtitle,
      required this.icon,
      required this.tint,
      required this.onTap});
  final String id, title, subtitle;
  final IconData icon;
  final Color tint;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
          key: ValueKey('home-$id'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Semantics(
              button: true,
              child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                  color: tint,
                                  borderRadius: BorderRadius.circular(10)),
                              child: Icon(icon,
                                  size: 18, color: MobileHomeMenu.ink)),
                          const SizedBox(width: 6),
                          Expanded(
                              child: Text(title,
                                  style: const TextStyle(
                                      color: MobileHomeMenu.ink,
                                      fontSize: 13,
                                      height: 1.25,
                                      fontWeight: FontWeight.w600))),
                        ]),
                        const SizedBox(height: 5),
                        Text(subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Color(0xFF788475),
                                fontSize: 11,
                                height: 1.25)),
                      ])))));
}
