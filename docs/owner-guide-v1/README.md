# دفترچهٔ مالک لایف‌گاید — نسخهٔ ۱

راهنمای فارسی ۱۲صفحه‌ای برای دیدن مقصد محصول، توان واقعی امروز، علت فاصله تا تحویل و شش بستهٔ پیشنهادی اجرا. این بسته فقط مستندات است؛ برنامه، Backend، سایت، DNS، داده و مجوزها را تغییر نمی‌دهد.

- [HTML تعاملی و خودکفا](index.html): فهرست، قبلی/بعدی، متن بزرگ و چاپ؛ بدون درخواست بیرونی، سرور لازم برای استفاده یا فرم جمع‌آوری داده. فایل را با مرورگر باز کنید؛ همهٔ فونت‌ها و تصویرها داخل همان فایل هستند.
- [PDF دوازده‌صفحه‌ای](LifeGuide-Owner-Guide-v1.pdf): A4 مناسب چاپ/بزرگ‌نمایی.
- [نمای کلی](overview.png) و [تصویر صفحه‌ها](pages/).
- [برنامهٔ تحویل با مالک و معیار خروج](DELIVERY_PLAN.md).
- [خروجی واقعی بررسی همین دفترچه](verification.json).

همهٔ شخصیت‌ها، نام‌های عمومی، برنامه‌ها و درس نمونه ساختگی یا تألیفی‌اند. فقط تصویر خالی نخستین اجرای صفحهٔ ۲ از شبیه‌ساز واقعی آمده است. چهره، نام، شماره تماس، دادهٔ واقعی کودک یا secret استفاده نشده است. تصویرهای SVG/HTML تألیفی‌اند؛ فایل خارجی یا پخش زنده وجود ندارد. دو فونت مخزن، LifeGuidePersian و LifeGuideLatin، به‌صورت data URL جاسازی شده‌اند؛ مجوزهای همراه در [licenses](licenses/) و منبع در [پوشهٔ فونت‌های مخزن](../../apps/lifemate/assets/fonts/) هستند.

## مبنای واقعی و حدود اعتبار

1. [PROJECT_STATE.md](../../PROJECT_STATE.md)، **فقط بخش نخست ۲۰ اکتبر ۲۰۲۶**، source کد آزموده‌شده `3e36dfd4f01d51e11816c0f97d1abda4266f1945` و baseline مستندات `3429196`. بخش‌های قدیمی‌تر تاریخی‌اند و روی وضعیت نخست تقدم ندارند.
2. [راهنمای Android شخصی](../operations/PERSONAL_ANDROID.md)، [گواه شبیه‌ساز و SQLite واقعی](../audits/evidence/personal-android-2026-10-20.json) و [تصویر خالی اجرای واقعی](../audits/evidence/personal-user-first-launch-2026-10-20.png). APK شخصی `0.7.2-personal.1/code9`، شناسهٔ `ir.lifeguide.app.device` و debug است؛ بدون URL/API/ورود و بدون همگام‌سازی/خروجی/backup/بازیابی.
3. [CI اختصاصی 39480587450](https://github.com/davoodmehraban89/LifeMate/actions/runs/39480587450): Flutter314، Python23، analyze، دو APK و آزمون native emulator/SQLite. [CI عمومی 39480587202](https://github.com/davoodmehraban89/LifeMate/actions/runs/39480587202): Backend308، identity41، regression96، Flutter314. این‌ها **نتایج تاریخی همان source** هستند؛ در head این دفترچه دوباره اجرا نشده‌اند. هیچ app test یا build برای تغییر docs انجام نشد.
4. [ADR0016](../decisions/0016-initial-child-planner-delivery.md): انتخاب D-A برای APK اولیه ACCEPTED. [ADR0015](../decisions/0015-managed-child-education-scope-options.md): همچنان PROPOSED؛ نه ظاهر دفترچه و نه برنامهٔ تحویل مجوز گسترش دسترسی کودک نیست.
5. [وضعیت پژوهش و مرور محدود](../research/2026-10-11-math-pilot-review.md) و بخش «آموزش واقعی و دامنه‌ها» در PROJECT_STATE: ویدئوی واقعی با بازبینی کامل و منتشرشده **۰**؛ پخش/تمام‌صفحه/بازگشت UNVERIFIED. درس هفتم و امکانات آموزشی این دفترچه نمونهٔ آینده‌اند، نه موجودی نصب‌شده.
6. [ممیزی فاصله تا تکمیل](../audits/2026-10-11-completion-gap-analysis.md)، [اتصال APK](../audits/2026-10-11-apk-connection.md) و [گواه مسیرهای عمومی ۱۹ اکتبر](../audits/evidence/public-api-paths-2026-10-19.json) برای توضیح مشکل ترتیب تحویل. هیچ probe تازهٔ سرویس زنده در این بسته اجرا نشده است.

گوشی فیزیکی، Safari/PWA، شبکهٔ ایران، API و SMS واقعی، استقرار، ارتقای هم‌امضا، بازیابی، بازبینی کامل ویدئو و انتشار پایدار با این سند تأیید نمی‌شوند. علت‌های تأخیر صفحهٔ ۱۱ جمع‌بندی مسئولیت مهندسی از شواهد موجود است. خواندن متمرکز منابع، صفحهٔ ۶، README و جدول برنامه انجام شد؛ ممیزی مستقل کامل آموزشی یا حقوقی این نسخه انجام نشده است.

## بازتولید و بررسی

ابزار لازم: Python3، Node.js، Playwright و Chromium، Poppler (`pdfinfo`, `pdftoppm`). روی محیط این اجرا:

```bash
cd /tmp/lifeguide-delivery
python3 docs/owner-guide-v1/build_owner_guide.py
NODE_PATH=/opt/codex/runtimes/codex-primary-runtime/dependencies/node/node_modules \
  node docs/owner-guide-v1/build_and_check.cjs
python3 docs/owner-guide-v1/rasterize.py
```

اسکریپت بررسی فقط یک HTTP server موقت روی `127.0.0.1` برای HTML دفترچه باز می‌کند، در پایان آن را می‌بندد و مرورگر آفلاین جداگانه نیز می‌سنجد؛ هیچ policy مرورگر خاموش نمی‌شود. استفاده از فایل تحویلی نیازمند سرور نیست. مسیر Chromium در اسکریپت `/usr/bin/chromium` است. فونت و screenshot از مخزن خوانده می‌شوند؛ build شبکه نمی‌خواهد.

بررسی‌های لازم: ۱۲ صفحهٔ HTML/PDF، فونت جاسازی‌شده، حداقل متن ۱۲px و کنترل‌های ۴۸px، نبود overflow در ۳۲۰/۳۶۰/۳۹۰ و متن بزرگ، مرز محتوای چاپ/پاورقی و فرزندان تصویرها، کارکرد فهرست/جابجایی، دارایی و ناوبری آفلاین، صفر درخواست خارجی/فرم/خطای مرورگر. PNGها **از PDF با pdftoppm** گرفته می‌شوند؛ تصویر بلند مرورگر مبنای آن‌ها نیست.

فایل ZIP همراه این پوشه را در بر دارد و خودش را داخل خود قرار نمی‌دهد. صدور نسخهٔ جدید با اسکریپت‌ها انجام شود تا HTML/PDF/تصویرها هم‌نسخه بمانند.
