# ADR-0010 — نام LifeGuide و هویت پایدار انتشار

- Status: Accepted — دستور صریح مالک، 2026-10-08
- Product: **LifeGuide / لایف‌گاید**
- Android application ID: **ir.lifeguide.app**؛ پس از انتشار تغییر نمی‌کند.
- Signed release filename: **LifeGuide.apk**؛ debug: **LifeGuide-debug.apk**.

برند در label، PWA، صفحات، ایمیل‌ها و مستندات جاری LifeGuide است. نام مخزن `davoodmehraban89/LifeMate`، مسیر `apps/lifemate`، package داخلی Dart/Node، منابع داخلی drawable و قرارداد JWT issuer=`lifemate`/audience=`lifemate-api` حفظ می‌شوند. تغییر این قراردادها به‌عنوان تغییر نام ظاهری مجاز نیست. کلاس داخلی `LifeMateApp` برای سازگاری آزمون‌های موجود باقی می‌ماند و نام نمایشی نیست.

نام‌های تاریخی در اسناد تصمیم/آزمون قدیمی با وضعیت تاریخی حفظ می‌شوند. [ممیزی نام‌ها](../audits/2026-10-08-naming.md) هر occurrence باقی‌مانده در فایل‌های متنی Git را طبقه‌بندی می‌کند؛ `python3 scripts/audit-naming.py --check` باقی‌ماندن نام نمایشی قبلی در کلاینت و workflow جاری را رد می‌کند.

شناسه جدید جایگزین `com.example.lifemate` است؛ نصب قبلی با شناسه قدیمی به‌صورت خودکار upgrade نمی‌شود. پاک‌کردن نصب قدیمی یا انتقال داده آن بدون تصمیم مستقل مجاز نیست. کلید امضای واقعی مالک بیرون Git و chat می‌ماند. ساخت release بدون secretها یا با گواهی Android Debug رد می‌شود؛ این کنترل source جای اثبات نصب/ارتقای واقعی را نمی‌گیرد. release امضاشده، ارتقا و کلید مالک **UNVERIFIED** تا اجرای مربوط‌اند.

شماره تکراری ADR-0004 رفع شد: Flutter به ADR-0007 منتقل شد؛ ADR-0004 مخصوص AI/privacy باقی ماند. ADR-0005 Supabase Superseded است؛ ترجیح میزبانی قدیمی ADR-0006 با ADR-0009 جایگزین شد.

ممیزی metadata رسمی GitHub در۲۰۲۶-۱۰-۰۹ نشان داد description مخزن هنوز نام قدیمی دارد: **user-facing — change**؛ مقدار مشاهده‌شده در [شواهد ممیزی](../audits/2026-10-09-isolation-verification.md) ثبت است. این تنظیم خارج فایل‌های Git/PR است؛ تیم آن را تغییر نداده است. مالک می‌تواند description را به LifeGuide تغییر دهد؛ نام/URL مخزن و قراردادها ثابت می‌مانند. جدول تولیدشده naming فقط متن‌های tracked را پوشش می‌دهد؛ این مورد بیرونی جدا ثبت شده است.
