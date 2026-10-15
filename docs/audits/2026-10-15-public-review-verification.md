# شواهد صفحه عمومی LifeGuide —۱۵اکتبر۲۰۲۶

دامنه این بسته، صفحه معرفی عمومی مورد درخواست مالک برای بررسی کاوه‌نگار است. صفحه در `site/review` و Workflow در `.github/workflows/publish-static.yml` قرار دارند. Backend، دیتابیس و تنظیمات سرویس پیامک تغییر نکرده‌اند. دو نقص پایه Flutter که اجرای CI آشکار کرد اصلاح شدند: import استفاده‌نشده test/app_test.dart حذف شد و راهنمای حداقل۱۰کاراکتر، مطابق تست موجود، در ورودی رمز ثبت‌نام نشان داده شد.

## اجراهای واقعی محلی

- `python3 scripts/check-review-site.py`: PASS؛ چهار HTML فارسی RTL، نام LifeGuide، لینک‌ها/دارایی‌های محلی، CNAME صحیح، عدم فرم/اسکریپت/API و مرز artifact عمومی بررسی شدند. checker لینک واقعی مخزن LifeMate و مسیر `./` به index را از خطای کاذب مستثنی می‌کند؛ نام محصول روی صفحه LifeGuide است.
- مرورگر واقعی Chromium با Playwright روی HTTP محلی: **۱۲/۱۲**، چهار صفحه در عرض‌های۳۲۰/۳۹۰/۱۲۸۰. فونت محلی واقعاً بارگیری شد، overflow افقی نداشت، دکمه OTP غیرفعال بود، لینک حریم خصوصی باز شد، ورودی/فرم/اسکریپت/iframe/کوکی/localStorage/sessionStorage وجود نداشت. **۷۵ درخواست محلی، صفر درخواست خارجی، صفر خطای کنسول/شبکه**. [receipt](evidence/pages-browser-2026-10-15.json). این اجرا HTTPS عمومی، Safari واقعی یا اتصال Backend را آزموده معرفی نمی‌کند.
- YAML با PyYAML parse شد و شرط main-only، permissions جداگانه و مرز `site/review` بررسی شد. `git diff --check` روی فایل‌های tracked اولیه موفق بود؛ بررسی staged سپس یک فاصله انتهایی در کپی مجوز فونت یافت. فقط همان whitespace اصلاح و بررسی staged دوباره اجرا شد. بازبینی مستقل، مانع اجرایی در محتوا/Workflow پیدا نکرد؛ بازبینی به معنی اجرای deploy نیست.

[تصویر موبایل۳۹۰](evidence/pages-browser-2026-10-15-390.png)، [موبایل۳۲۰](evidence/pages-browser-2026-10-15-320.png)، [دسکتاپ۱۲۸۰](evidence/pages-browser-2026-10-15-1280.png). مسئول هماهنگی تصویر موبایل را مشاهده کرد.

## واقعیت GitHub/DNS پیش از انتشار

CLI رسمی GitHub با حساب مجاز موجود، Pages را `build_type:workflow`، `cname:app.lifeguide.ir`، `https_enforced:false` و `https_certificate:null` گزارش کرد. محیط github-pages فقط شاخه main را در policy دارد؛ این policy تغییر نکرده است. [ممیزی DNS/HTTP تازه](2026-10-15-pages-dns.md) و [JSON](evidence/pages-dns-before-2026-10-15.json) نشان می‌دهند صفحه HTTP200 فعلی loader قدیمی LifeMate است و DNS عمومی به proxy آروان پاسخ می‌دهد. این‌ها، نصب یا درست‌بودن API جدید را ثابت نمی‌کنند.

## در انتظار / UNVERIFIED

CI همین commit و deploy عمومی تا ثبت run واقعی، **UNVERIFIED** هستند. PR فقط build/upload می‌کند؛ deploy فقط پس از تأیید مالک برای ادغام PR این صفحه در main انجام می‌شود. این توقف از دستور مستقیم قبلی مالک «final merge ... forbidden without my explicit approval» و policy واقعی محیط می‌آید؛ مجوز انتشار صفحه دریافت شده، ولی محدودیت merge دور زده نشده است.

تغییر DNS نیازمند پنل آروان مالک است. [راهنمای دقیق CNAME و ترتیب HTTPS](../operations/PUBLIC_REVIEW_PAGE.md). دسترسی از ایران، گواهی عمومی پس از DNS، Safari/Android واقعی، ورود/ارسال SMS و تأیید نهایی کاوه‌نگار **UNVERIFIED** هستند. هیچ تیکت، پیامک یا پیام خارجی ارسال نشده و هیچ کلید/API یا داده خصوصی در سایت قرار نگرفته است.

## رفع خطاهای واقعی CI پایه

run38695022648 برای source92fffe2، security و backend را موفق و Flutter analyzer را به دلیل یک unused_import ناموفق گزارش کرد. پس از حذف همان import، analyzer محلی clean شد؛ اجرای واقعی تست‌های پایه سپس۴موفق/۱ناموفق داد، چون راهنمای حداقل۱۰کاراکتر در فرم ثبت‌نام نشان داده نمی‌شد. helperText همان فیلد اضافه شد؛ این اصلاح هیچ ارسال SMS یا اتصال Backend اضافه نمی‌کند. نسخه Flutter محلی3.47.6 و runner شکست‌خورده3.47.7 بود. نتیجه اجرای نهایی محلی و CI تازه باید جدا ثبت شود.

run38694970653 ساخت صفحه را واقعاً موفق و deploy را SKIPPED گزارش کرد. لاگ validator چهار صفحه PASS و upload artifact11954051844 با142081bytes را ثبت کرد؛ این موفقیت deploy نیست. دانلود مستقل artifact از CLI با403 مقصد موقت شکست خورد و محتوی آن مستقل تأیید نشده است؛ هیچ ادعای موفقیت دانلود وجود ندارد.

پس از دو اصلاح پایه، `flutter analyze --no-pub` محلی No issues و `flutter test --no-pub` **۵/۵ موفق** شد. این پنج تست مربوط به app پایه main است، نه شاخه توسعه آنلاین خانواده. ابزار Flutter هنگام pub get فایل تنظیم analysis و lock تولید کرد؛ تغییرهای تولیدی وارد PR نشدند. validator چهار صفحه بعد از اصلاح‌ها دوباره PASS شد.
