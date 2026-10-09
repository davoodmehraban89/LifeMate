# LifeGuide — سخت‌سازی جداسازی Stage 0

تاریخ:۲۰۲۶-۱۰-۰۹. مبنا: `feat/online-family-stage0`، PR10، منبع آزموده‌شده `7d93668` و گزارش واقعی PROJECT_STATE. اجرای محلی/آزمون/PR از قبل مجاز است؛ این طراحی مجوز استقرار زنده، انتقال داده واقعی، DNS یا merge نیست.

## هدف و دامنه

دو نقص مشخص مانع استفاده امن‌تر بسته مشترک‌اند: API در Compose از کاربر bootstrap دارای superuser استفاده می‌کند؛ دو تب وب می‌توانند refresh token و صف/cache مشترک را هم‌زمان تغییر دهند. هسته سالم planner، auth، خانواده و PostgreSQL بازسازی نمی‌شود. نام LifeGuide، `ir.lifeguide.app`، نام مخزن/SQL/JWT و استقرار یک‌مبدأ حفظ می‌شوند.

راهکار کم‌پیچیدگی انتخاب‌شده، نقش‌های مستقل PostgreSQL و فقط یک instance فعال وب در هر browser profile/origin است. تقسیم و merge صف بین تب‌ها یا اشتراک token، خارج این بسته است. هیچ وابستگی مدیریتی خارجی اضافه نمی‌شود.

## دیتابیس: مسئول اصلی deployment_stage0

- `POSTGRES_USER/PASSWORD` فقط برای bootstrap و عملیات صریح operator می‌ماند؛ API آن را دریافت نمی‌کند.
- `API_DB_USER/PASSWORD`: LOGIN مستقل، بدون SUPERUSER/CREATEDB/CREATEROLE/BYPASSRLS، عضویت یا مالکیت app/schema؛ فقط DML و توابع لازم API. schema/table DDL، role modification و نوشتن migration ledger ممنوع‌اند.
- `MIGRATOR_DB_USER/PASSWORD`: غیرsuperuser، مالک schema/اشیای app؛ مجوز لازم برای migrationهای موجود، بدون مدیریت کاربران/دیتابیس‌های دیگر.
- `BACKUP_DB_USER/PASSWORD`: خواندن app/ledger/sequences برای pg_dump؛ بدون DML و توابع تغییر‌دهنده. restore با migrator انجام می‌شود.
- provisioning و grants تکرارپذیر، ابتدا با بررسی مالکیت اشیای موجود. تبدیل DB موجود فقط با مسیر operator صریح، expected owner و backup؛ بدون REASSIGN OWNED سراسری، حذف volume یا تغییر داده.
- grantهای اشیای migration جدید نیز اعمال می‌شوند؛ ساختار و migrations سالم فعلی حفظ می‌شوند. secretها فقط env خصوصی، بدون چاپ در config/log یا Git.

پذیرش: DB تازه ساختگی، هر۱۲ migration و اجرای تکراری، CRUD/auth/مجوز از API واقعی با runtime، رد DDL/role/ledger writes، backup خواندنی و restore با migrator. هیچ نتیجه‌ای از روی بررسی متن config به‌عنوان اجرای PostgreSQL گزارش نمی‌شود.

## مرورگر: مسئول اصلی review_persistence

- Web Locks انحصاری `lifeguide.active-instance.v1` پیش از `_flutter.loader.load`، runtime config، session restore، cache/queue یا auth گرفته می‌شود.
- lock در تمام عمر document نگه داشته می‌شود؛ background/blur آن را آزاد نمی‌کند. localStorage lease یا fail-open استفاده نمی‌شود.
- تب دوم یا مرورگر فاقد Locks، صفحه ثابت فارسی با توضیح و retry می‌بیند؛ Flutter/service worker/auth/sync/cache وارد نمی‌شوند و هیچ داده‌ای پاک نمی‌شود.
- getter مالکیت bootstrap و guard وب از ادامه session/cache/HTTP در document فاقد مالکیت جلوگیری می‌کنند. native Android رفتار موجود را حفظ می‌کند.
- پس از close/crash صاحب، retry تب دیگر می‌تواند lock بگیرد. pagehide مالکیت داخلی را باطل و بازیابی pageshow مسیر startup جدید را طی می‌کند؛ document قدیمی نباید با مالکیت منقضی ادامه دهد.
- این پروتکل به browser profile/origin محدود است؛ دستگاه‌های مستقل همچنان با سرور sync می‌شوند. کد قدیمیِ بازمانده lock ندارد؛ هنگام ارتقای این نامزد، همه تب/PWAهای نسخه قبل یک‌بار بسته شوند.
- بررسی مستقل روی artifact کامپایل‌شده، پاک‌شدن pending پس از pagehide در میانه refresh و سپس401 را بازتولید کرد. انقضای ناخواسته/restore mismatch باید credential و دسترسی فعال را ببندد ولی namespace ارسال‌نشده را بدون تغییر دیسک قرنطینه کند؛ store قدیمی با generation نامعتبر دسترسی نداشته باشد. ورود تأییدشده همان account+endpoint، store تازه می‌سازد و صف را بازیابی می‌کند؛ حساب دیگر نمی‌تواند آن را بخواند/ارسال کند. حذف صریح خروج/تغییر سرور پس از تأیید کاربر حفظ می‌شود.

پذیرش: دو تب واقعی Chromium، startup هم‌زمان فقط یک owner، تب دوم بدون loader/auth/storage، retry پس از close/crash، origin/profile مستقل و مرورگر فاقد Locks. آزمون client401/pagehide، حفظ صف و منع store قدیمی/حساب دیگر، بازیابی و replay یک UUID همان حساب نیز لازم است. fixture با engine ساختگی یا پاسخ HTTPS مصنوعی فقط رفتار client را ثابت می‌کند؛ API/DB و خروجی کامل کامپایل‌شده جدا آزموده شوند. Safari/Android فیزیکی بدون اجرای واقعی UNVERIFIED می‌مانند.

## ادغام، شواهد و محدودیت‌ها

هماهنگی، CI و مستندات بر عهده root است. آزمون‌ها RED→GREEN با خروجی واقعی‌اند؛ source پس از freeze ساخته و provenance جدید ثبت می‌شود. CI محدودشده فقط پس از اعلام رفع محدودیت مالک rerun شد؛ هیچ تنظیم پرداخت/سقف تغییر نکرده است.

داده فقط ساختگی است. backup رمزگذاری‌شده خارج PC، UX/CRUD آموزشی باقی‌مانده، SMTP/SMS واقعی، کلید release، VPN-free Iran و Safari نصب‌شده همچنان گیت‌های جدا هستند. این بسته عنوان نسخه کامل عملیاتی ندارد.
