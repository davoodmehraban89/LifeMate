# وضعیت تأییدشده Supabase — ۱۵ اکتبر ۲۰۲۶

بررسی خواندنی در 07:20 UTC از اتصال رسمی Supabase و GitHub انجام شد. اعلام تازه مالک درباره انتقال از Railway به Supabase مبنای ادامه توسعه است؛ محدودیت قدیمی استفاده‌نکردن از Supabase برای این پروژه موجود، با این اعلام جدید جایگزین می‌شود. این تأیید، مجوز ساخت حساب/سرویس، تغییر سرویس زنده، انتقال داده واقعی یا ارسال پیامک نیست.

## شواهد سرویس موجود

- پروژه `LifeGuide-QA` در Supabase وضعیت `ACTIVE_HEALTHY` و PostgreSQL17.11 دارد.
- پرس‌وجوی فقط‌خواندنی روی pg_catalog، وجود schema خصوصی `lifeguide_qa` با۵۹ جدول و public بدون جدول را تأیید کرد. هیچ رکورد کاربر/خانواده/گفت‌وگو خوانده نشد.
- تاریخچه Migration سه ثبت دارد: baseline، `lifeguide_qa_app_schema_0001_0010` و `lifeguide_qa_app_schema_0011_0020`. این خواندن تاریخچه است؛ تیم در این بسته Migration اجرا نکرد.
- فهرست Edge Functions فقط `lifeguide-qa-health` فعال نسخه۱ با verify_jwt=true را نشان داد. فهرست‌کردن این تابع، آزمون API ورود یا خانواده نیست. هیچ کلید API دریافت نشد.

## تطبیق با مخزن

ممیزی مستقل GitHub: main همچنان abdc9d9 است. شاخه `infra/lifeguide-supabase-qa` در5da6c42 و PR۱۴ باز/Draft، انتقال۲۰ Migration به همین schema و۵۹ جدول را مستند می‌کنند. نسخه تازه‌تر Pages در2c3ea97 صریحاً static-only است: scripts/build-github-pages-qa.sh و workflow lifeguide-github-pages-qa.yml، API را عمداً غیرفعال می‌کنند؛ web/config.json مسیر /api با fallback خالی دارد. PR۱۹ تغییر محیط Pages است و API خانواده/ورود اضافه نمی‌کند.

main هنوز referenceهای تاریخی‌مانده Railway را در publish-static.yml و Dockerfile کلاینت دارد؛ این‌ها نباید به‌عنوان مقصد جدید اجرا یا بازفعال شوند. PR۲۰ فقط صفحه معرفی مستقل از API را منتشر خواهد کرد و مسیر قدیمی publisher آن را جایگزین می‌کند.

## حدود تأیید

وجود و سلامت دیتابیس QA تأیید شد. اتصال عملیاتی Node API، ورود OTP، Android/PWA، ذخیره و همگام‌سازی دو دستگاه به این دیتابیس هنوز UNVERIFIED است. داده واقعی یا حساس نباید برای آزمون به میزبان خارجی منتقل شود. خواندن HTTPS با TLS عادی برای / و /config.json و /health در app.lifeguide.ir در همین بررسی HTTP404 داد؛ این فقط مشاهده این محیط است و آزمون شبکه ایران/Safari نیست. DNS، سرویس زنده، مخزن، دسترسی‌ها یا داده‌ای تغییر نکردند.
