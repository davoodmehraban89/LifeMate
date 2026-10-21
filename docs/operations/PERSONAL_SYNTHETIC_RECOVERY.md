# LifeGuide — تمرین بازیابی رمزدار، فقط دادهٔ ساختگی

این بسته ابزار QA است؛ پشتیبان‌گیری از گوشی یا اطلاعات مالک نیست. [ADR0018](../decisions/0018-offline-installed-data-rescue-options.md) فقط آماده‌سازی و آزمون ساختگی را مجاز می‌کند. **نسخهٔ نصب‌شده را حذف، clear-data یا با APK ناسازگار جایگزین نکنید.** کلید خصوصی امضای اولیه هنوز UNVERIFIED است؛ APK آن کلید را بازیابی نمی‌کند.

## چه چیزی واقعاً آزمایش می‌شود

Python3.11+، SQLite واقعی schema1، یک پروفایل خیالی، چهار نوع تکرار، سه ساعت هفتگی و چهار نوبت مستقل با تیک/ویرایش/بایگانی. خروجی JSON قابل‌حمل با تمام فیلدها در حافظه ساخته، با AES-256-GCM و Scrypt ثابت رمز می‌شود؛ salt و nonce هر بار تصادفی‌اند. سپس فایل رمزدار دوباره باز، اعتبارسنجی و به SQLite تازه بازسازی می‌شود. SQL مستقل و تطبیق همهٔ مقادیر پس از بسته‌شدن اتصال بررسی می‌شوند.

فایل فقط اگر marker آزمایشی در هدر SQLite داشته باشد پذیرفته می‌شود. marker جلوی اشتباه معمول را می‌گیرد؛ **احراز اصالت یا اثبات ساختگی‌بودن نیست** و نباید برای عبور دادهٔ واقعی تنظیم شود. فایل بدون marker پیش از خواندن بدنهٔ رکوردها رد می‌شود. schema آینده، جدول/trigger/view ناشناخته، UUID/تاریخ/رابطهٔ نامعتبر، فایل حجیم، رمز اشتباه و تغییر ciphertext رد می‌شوند.

این مرحله فقط SQLite **بسته‌شده، بدون WAL/SHM/journal و با هدر rollback** را می‌پذیرد. جمع‌آوری سازگار WAL از Android، نصب کناری و آپدیت بعدی app تازه آزمون جدا دارند. رد فایل به معنی پاک‌کردن sidecar یا reset دیتابیس نیست. برنامهٔ موجود و داده‌هایش دست‌نخورده بمانند.

## اجرای محلی با اطلاعات خیالی

از ریشهٔ شاخهٔ `feat/personal-encrypted-recovery`؛ نصب وابستگی اینترنت می‌خواهد، خود ابزار شبکه ندارد. پس از نصب وابستگی می‌توان شبکه را قطع کرد. روی Windows به‌جای `python3` از Python3.11+ نصب‌شده استفاده شود؛ Windows/USB/ACL واقعی مالک هنوز **UNVERIFIED** است.

```bash
python3 -m venv .venv-recovery
.venv-recovery/bin/python -m pip install -r requirements-personal-recovery.txt
.venv-recovery/bin/python -m unittest discover -s scripts/tests -p 'test_recovery*.py' -v
.venv-recovery/bin/python scripts/personal_recovery_cli.py demo --directory /tmp/lifeguide-fictional-rehearsal --acknowledge-synthetic-only
```

مسیر demo باید تازه یا خالی باشد. گزارش فقط شمار رکوردها، hash و PASS/UNVERIFIED دارد؛ گذرواژهٔ تصادفی همین demo چاپ یا ذخیره نمی‌شود و فایل demo برای پشتیبان قابل اتکای مالک نیست. پوشه فقط نمونهٔ خیالی را نگه می‌دارد. خروجی موفق `result=PASS` است، خطا exit2 و لغو exit130. برای تکرار، پوشهٔ تازه انتخاب کنید؛ فایل موجود بازنویسی نمی‌شود.

دستورهای جزئی فقط برای همین fixture ساختگی هستند. هر خروجی باید مسیر تازه باشد:

```bash
python3 scripts/personal_recovery_cli.py create-fixture --output /tmp/fictional-source.sqlite --acknowledge-synthetic-only
python3 scripts/personal_recovery_cli.py pack --source /tmp/fictional-source.sqlite --output /tmp/fictional-transfer.lgrf --acknowledge-synthetic-only
python3 scripts/personal_recovery_cli.py restore-fixture --source /tmp/fictional-transfer.lgrf --output /tmp/fictional-restored.sqlite --acknowledge-synthetic-only
```

pack/restore ترمینال تعاملی می‌خواهند؛ گذرواژه مخفی پرسیده می‌شود. آن را در خط فرمان، env، Git، پیام یا لاگ ننویسید. حداقل۱۲ نویسه فقط حداقل فنی است؛ برای دادهٔ واقعی در آینده عبارت طولانی و تصادفی با نگهداری امن لازم است. رمزگذاری، گذرواژهٔ ضعیف را امن نمی‌کند؛ طول ciphertext دیده می‌شود و پاک‌سازی تضمین‌شدهٔ حافظه در Python نداریم. ابزار فعلی مجوز استفاده از دادهٔ واقعی ندارد.

فایل خروجی روی POSIX با mode0600، پس از تکمیل و fsync فایل، با hard-link اتمیک و بدون overwrite منتشر می‌شود. فایل‌سیستم فاقد hard-link با خطا متوقف می‌شود؛ fallback ناامن ندارد. قطع عملیات یا خطای شبیه‌سازی‌شدهٔ کمبود فضا پیش از انتشار، فایل نیمه‌کاره باقی نمی‌گذارد. دوام در قطع برق، ACL و رفتار Windows، دیسک پر واقعی و محیط گوشی **UNVERIFIED** هستند.

## مرز تحویل بعدی

این PR کلاینت، Backend، شناسهٔ نصب، baseline امضای قدیمی یا مجوز اعلان را تغییر نمی‌دهد و APK تازه نمی‌دهد. آزمون بعدی باید exact APK قدیمی را فقط روی شبیه‌ساز تازه با دادهٔ خیالی اجرا کند، نصب آزمایشی کناری و بازگشایی هر دو DB پیش‌فرض و سپس ارتقای همان نصب تازه را بررسی کند. APK fixture هرگز توزیع نمی‌شود. اعلان app تازه پیش‌فرض خاموش می‌ماند؛ رضایت/مجوز قدیمی منتقل نمی‌شود.

انتقال واقعی بعد از پذیرش، فقط روی رایانه و گوشی مالک و با انتخاب قابل‌فهم خود کاربر فرزند دربارهٔ دامنه، مقصد و دارندهٔ رمز انجام‌پذیر خواهد بود. تیم DB، رمز، کلید یا اطلاعات خصوصی نمی‌گیرد. هیچ نمای والد، دسترسی خانوادگی، ارسال AI یا cloud backup اضافه نشده است.
