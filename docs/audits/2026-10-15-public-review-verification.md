# شواهد صفحه عمومی LifeGuide —۱۵اکتبر۲۰۲۶

دامنه این بسته، صفحه معرفی عمومی مورد درخواست مالک برای بررسی کاوه‌نگار است. صفحه در `site/review` و Workflow در `.github/workflows/publish-static.yml` قرار دارند. کد Flutter، Backend، دیتابیس یا تنظیمات سرویس پیامک در این شاخه تغییر نکرده‌اند.

## اجراهای واقعی محلی

- `python3 scripts/check-review-site.py`: PASS؛ چهار HTML فارسی RTL، نام LifeGuide، لینک‌ها/دارایی‌های محلی، CNAME صحیح، عدم فرم/اسکریپت/API و مرز artifact عمومی بررسی شدند. checker لینک واقعی مخزن LifeMate و مسیر `./` به index را از خطای کاذب مستثنی می‌کند؛ نام محصول روی صفحه LifeGuide است.
- مرورگر واقعی Chromium با Playwright روی HTTP محلی: **۱۲/۱۲**، چهار صفحه در عرض‌های۳۲۰/۳۹۰/۱۲۸۰. فونت محلی واقعاً بارگیری شد، overflow افقی نداشت، دکمه OTP غیرفعال بود، لینک حریم خصوصی باز شد، ورودی/فرم/اسکریپت/iframe/کوکی/localStorage/sessionStorage وجود نداشت. **۷۵ درخواست محلی، صفر درخواست خارجی، صفر خطای کنسول/شبکه**. [receipt](evidence/pages-browser-2026-10-15.json). این اجرا HTTPS عمومی، Safari واقعی یا اتصال Backend را آزموده معرفی نمی‌کند.
- YAML با PyYAML parse شد و شرط main-only، permissions جداگانه و مرز `site/review` بررسی شد. `git diff --check` موفق بود. بازبینی مستقل، مانع اجرایی در محتوا/Workflow پیدا نکرد؛ بازبینی به معنی اجرای deploy نیست.

[تصویر موبایل۳۹۰](evidence/pages-browser-2026-10-15-390.png)، [موبایل۳۲۰](evidence/pages-browser-2026-10-15-320.png)، [دسکتاپ۱۲۸۰](evidence/pages-browser-2026-10-15-1280.png). مسئول هماهنگی تصویر موبایل را مشاهده کرد.

## واقعیت GitHub/DNS پیش از انتشار

CLI رسمی GitHub با حساب مجاز موجود، Pages را `build_type:workflow`، `cname:app.lifeguide.ir`، `https_enforced:false` و `https_certificate:null` گزارش کرد. محیط github-pages فقط شاخه main را در policy دارد؛ این policy تغییر نکرده است. [ممیزی DNS/HTTP تازه](2026-10-15-pages-dns.md) و [JSON](evidence/pages-dns-before-2026-10-15.json) نشان می‌دهند صفحه HTTP200 فعلی loader قدیمی LifeMate است و DNS عمومی به proxy آروان پاسخ می‌دهد. این‌ها، نصب یا درست‌بودن API جدید را ثابت نمی‌کنند.

## در انتظار / UNVERIFIED

CI همین commit و deploy عمومی تا ثبت run واقعی، **UNVERIFIED** هستند. push feature فقط build/upload می‌کند؛ deploy فقط پس از تأیید مالک برای ادغام PR این صفحه در main انجام می‌شود. این توقف از دستور مستقیم قبلی مالک «final merge ... forbidden without my explicit approval» و policy واقعی محیط می‌آید؛ مجوز انتشار صفحه دریافت شده، ولی محدودیت merge دور زده نشده است.

تغییر DNS نیازمند پنل آروان مالک است. [راهنمای دقیق CNAME و ترتیب HTTPS](../operations/PUBLIC_REVIEW_PAGE.md). دسترسی از ایران، گواهی عمومی پس از DNS، Safari/Android واقعی، ورود/ارسال SMS و تأیید نهایی کاوه‌نگار **UNVERIFIED** هستند. هیچ تیکت، پیامک یا پیام خارجی ارسال نشده و هیچ کلید/API یا داده خصوصی در سایت قرار نگرفته است.
