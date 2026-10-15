# LifeGuide — پاکسازی مخزن و نام‌های باقی‌مانده

دامنه این بسته: مستندات فعلی، رفع شناسه تکراری ADR و حذف workflow تعمیر یک‌باره. runtime، migration، schema، JWT، سایت عمومی و زیرساخت تغییر نمی‌کنند. نام محصول، طبق دستور مالک، **LifeGuide / لایف‌گاید** است؛ نام مخزن تغییر نمی‌کند.

## طبقه‌بندی نام قبلی

طبقه‌بندی زیر جایگزین blind replace است. این بسته rebrand کامل نسخه اجرایی را ادعا نمی‌کند؛ متن‌های نمایشی باقی‌مانده در `main` کار جدا هستند.

|دسته|موارد|اقدام|
|user-facing / مستندات فعلی|README، AGENTS، PROJECT_STATE، backend/README، سندهای فعلی product/architecture/quality/safety/UX و runbook عمومی deploy|متن برند در این بسته LifeGuide شد؛ مفاد سیاست تغییر نکرد|
|user-facing / runtime باقی‌مانده|`apps/lifemate/lib/main.dart` متن صفحه ورود و AppBar؛ web index/manifest؛ Android label؛ pubspec description؛ email subject/body و AI identity prompt در Backend|اصلاح در PR فنی جدا؛ این بسته فقط ثبت می‌کند، نتیجه هنوز UNVERIFIED|
|user-facing / بسته‌بندی باقی‌مانده|نام workflow/Artifact در CI و `LifeMate.apk` در Dockerfile؛ شناسه آزمایشی Android `com.example.lifemate`|release blocker؛ به‌صورت جدا با سازگاری نصب/امضا بررسی شود؛ نام نهایی APK هدف `LifeGuide.apk` است|
|protocol-sensitive / حفظ|JWT issuer=`lifemate` و audience=`lifemate-api`؛ پاسخ service/telemetry؛ package/class و importهای فعلی؛ env key موجود و مسیر `apps/lifemate`؛ schema/SQL؛ نام مخزن و URLهای رسمی آن|حفظ سازگاری؛ تغییر خودکار مجاز نیست|
|historical / حفظ|اسناد history، plans و superpowers؛ تصمیم‌های اولیه؛ audit/evidence پیش از انتشار؛ نام واقعی artifact قدیمی Figma؛ نام artifact در checklist تاریخی Feature1|به‌عنوان سابقه باقی می‌ماند؛ راهنمای نام محصول یا آمادگی امروز نیست|
|technical / حفظ|نام فایل dump/test DB، دامنه‌های رزروشده `.invalid`/`.test` و fixture مصنوعی، عبارت‌های شناسایی برند ممنوع در checker سایت|شناسه فنی یا تست منفی؛ نمایش محصول نیست؛ مقدار واقعی یا secret اضافه نمی‌شود|

اسناد نسخه‌دار اولیه ممکن است هنوز سیاست‌های پیشنهادی قبلی را بیان کنند. آن‌ها مجوز اجرای تازه AI، cycle، مشاهده خصوصی کودک یا انتخاب میزبان نیستند؛ سیاست‌های بعدی به سند گزینه‌ها و تأیید مالک نیاز دارند. [وضعیت جاری](../../PROJECT_STATE.md) نسبت به پلن تاریخی اولویت دارد. referenceهای تاریخی Railway نگه داشته می‌شوند؛ مقصد فعال و مجوز راه‌اندازی آن نیستند. آدرس قدیمی Railway در Dockerfile کلاینت، نقص فنی ثبت‌شده برای PR جدا است؛ این پاکسازی آن را اجرا یا معتبر معرفی نمی‌کند.

## ADRها

frontend ADR از شناسه تکراری۰۰۰۴ به [ADR-2026-10-05-frontend](../decisions/2026-10-05-frontend-flutter.md) منتقل شد؛ انتخاب Flutter و مرزهای آن تغییر نکرد. هیچ ارجاع فعال به مسیر قدیمی در منبع `main` وجود نداشت. ADR0004 مربوط به AI و تاریخچه آن حفظ شدند؛ سیاست بعدی باید با تأیید مالک تعیین شود.

[ADR0005](../decisions/0005-backend-supabase.md) از قبل Superseded بود؛ لینک مستقیم به [ADR0006](../decisions/0006-provider-neutral-postgresql-backend.md) و توضیح QA افزوده شد. مشاهده Supabase QA، احیای تصمیم قدیمی استفاده از combined Auth/BaaS نیست. ترجیح Neon در متن۰۰۰۶ به‌عنوان زمینه تاریخی مشخص شد؛ میزبان جدیدی انتخاب نشد.

## حذف workflow تعمیر یک‌باره

**VERIFIED:** `fix-unused.yml` فقط push شاخه قدیمی `final-feature-1/iran-family-school` را می‌گرفت، `contents:write` داشت و یک متغیر استفاده‌نشده را با commit/push خودکار حذف می‌کرد. عبارت هدف اکنون هم در `main` و هم در همان شاخه قدیمی وجود ندارد؛ فایل فعلی از قبل `final prefs=s.data![3];` دارد. workflowهای دیگر آن را فراخوانی نمی‌کنند و `workflow_call` ندارد.

مشاهده خواندنی `gh run list --workflow fix-unused.yml --limit 5 --json databaseId,headSha,status,conclusion,createdAt` فقط دو run تکمیل‌شده قدیمی `37352116388` و `37341988363` در۵اکتبر با success داد. حذف آن، مسیر بی‌نیاز دارای مجوز نوشتن را از source حذف می‌کند؛ GitHub یا سرور زنده در این بسته تغییر داده نمی‌شود.

## شواهد و محدودیت‌ها

[خلاصه فاز۰](2026-10-15-phase0-summary.md) شمارها، مبنا و محدودیت اسکن را ثبت می‌کند. فهرست کلید مشخص برای rotation بر مبنای آن اسکن خالی است؛ نه مقدار کلید یا اطلاعات تماس منتشر می‌شود و نه ادعای نبود تمام secretها.

PR21 برای شواهد انتشار عمومی هنوز مستقل و باز است؛ متن‌های README/PROJECT_STATE همپوشان باید پیش از ادغام reconcile شوند. سایت عمومی به مخزن/سورس لینک نمی‌دهد و این بسته آن فایل‌ها را تغییر نمی‌دهد. تست runtime/ساخت تازه در این PR مستنداتی **UNVERIFIED** است؛ نتایج فاز۰ با تاریخ و SHA جدا نقل شده‌اند.
