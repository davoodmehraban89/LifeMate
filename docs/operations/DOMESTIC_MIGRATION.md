# LifeGuide — انتقال به سرور داخلی و بازگشت

این runbook همان Compose و PostgreSQL مستقل را منتقل می‌کند. **انتقال واقعی خانواده، DNS cutover، deploy سرور داخلی و rollback زنده در این کار اجرا نشده‌اند و UNVERIFIED هستند.** تنها drill با داده ساختگی محلی، پس از ثبت خروجی، می‌تواند VERIFIED شود. private notes، AI chat، wellbeing/چرخه و داده روانی کودکان نباید روی میزبان خارجی قرار بگیرند؛ درگاه حقوقی/رضایت و محل نگهداری داخلی جدا لازم‌اند.

## drill قابل اجرا بدون داده واقعی

بعد از بالا آمدن Stage 0:

```bash
bash scripts/restore-drill.sh --synthetic-only
```

script از Docker محلی استفاده می‌کند و سناریوی [نقش‌های محدود](DATABASE_ROLES.md) را اجرا می‌کند: دو نام DB تازه با prefix `lifeguide_roles_` می‌سازد، migrations موجود با migrator اجرا، fixture موجود `backend/scripts/restore-smoke.sql` و fixture خانواده ساختگی `deployment/restore-fixture.sql` را درج و scripts موجود `backup.sh`/`restore.sh` را با backup فقط‌خواندنی و restore migrator اجرا می‌کند. در مقصد، حساب/profile،12checksum ledger، مالکیت، SQL forbidden، guardian مجاز، تکلیف خصوصی/والد نامرتبط و مجموع۶۰۰ثانیه interval مطالعه با وقفه را بررسی و فقط همین دو DB تازه را با marker دقیق همان run پاک می‌کند. دیتابیس برنامه و volume آن restore/drop نمی‌شوند. خروجی `PASS local least-privilege ...` شاهد drill است؛ موفقیت syntax/build به‌تنهایی شاهد restore نیست.

اجرای قبلی محلی ۲۰۲۶-۱۰-۰۸،۱۶:۴۶UTC با PostgreSQL16، حفظ12migration را نشان داد. اجرای نهایی جدید ۲۰۲۶-۱۰-۰۹ با نقش‌های جدا، **PASS** بود: runtime HTTP9/9،17منع SQL در source و restore،12checksum ledger و policy/intervalهای مقصد. query مستقل بعد از cleanup، تعداد DBهای role-test باقی‌مانده را صفر نشان داد. این شاهد، انتقال واقعی، DNS و سرور داخلی مالک را تأیید نمی‌کند.

## مراحل دستی انتقال واقعی، فقط پس از مجوز

1. origin/DNS و سرور داخلی را مالک تعیین کند. imageهای دقیق و versioned، PostgreSQL16 و ظرفیت دیسک مقصد را بررسی کنید. مقصد باید database تازه و خالی داشته باشد. پیش از اتصال کاربران، همان Compose روی مقصد با داده **ساختگی** آزمون شود.
2. schema/version، migration ledger، roleهای DB و envهای لازم را فهرست کنید. secretها فقط کانال امن/secret management؛ در issue/chat/docs قرار نگیرند. نام جدول/SQL function و قراردادهای JWT تغییر نمی‌کنند. زمان UTC، CORS و PUBLIC_APP_URL مطابق origin مقصد شوند. API/PWA/APK همه همان origin هستند.
3. بازه توقف نوشتن را تعیین و مشتری‌ها را از maintenance آگاه کنید. API/gateway قدیمی را متوقف یا route نوشتن را در لایه مالک مسدود کنید؛ فقط نمایش stale/offline معتبر مجاز است. queueهای دستگاه تا پایان انتقال server acknowledgement جدید نمی‌گیرند.
4. از دیتابیس منبع `pg_dump --format=custom --no-owner --no-privileges` با `backend/scripts/backup.sh` بگیرید. checksum SHA256 و snapshot/backup قبل از انتقال را ثبت کنید. dump را رمزگذاری و از مسیر امن به **داخل کشور** انتقال دهید؛ به مقصد خارجی یا CDN منتقل نشود.
5. روی DB تازه مقصد، ابتدا نقش‌ها/public را با `db-provision` آماده و فقط با مجوز restore، service دستی `restore` را با credential migrator اجرا کنید. script از `--clean --if-exists` استفاده می‌کند؛ **نباید به DB دارای داده جدید اشاره کند**. backup credential فقط‌خواندنی است و برای restore مناسب نیست. مقصد خالی، مالک درست extension pgcrypto را نیز حفظ می‌کند؛ هیچ catalog update برای مالک آن نکنید. نسخه source/backups را حفظ کنید. سپس migration ledger، `migrate` و `db-grants` را با نسخه تاییدشده بررسی کنید.
6. تعداد رکوردهای کلیدی، مالکیت، خانواده/guardian، تاریخ‌ها، revoked sessions و policyهای خصوصی را با query و API مستقل بررسی کنید؛ private data در log نیاید. سناریوی ۸ مرحله‌ای با fixture جدید و تست restore نشست/Sync را اجرا کنید. مقصد هنوز public نیست.
7. مالک پس از پذیرش، DNS/endpoint را cutover کند. TTL قبلی و مدت caching را در نظر بگیرید؛ endpoint runtime با `config.json` no-store و تنظیم Android قابل تغییر است. همه originهای fallback باید متعلق به همان سامانه تأییدشده باشند؛ fallback به DB مستقل جدید، Sync امن نیست. TLS hostname و Safari نصب‌شده را دوباره آزمون کنید.
8. منبع قدیمی را تا پایان بازه rollback حفظ و در حالت **بدون نوشتن** نگه دارید. دو DB هم‌زمان قابل نوشتن باعث divergence می‌شوند. پس از پایان بازه و مجوز مالک، خاموشی/حذف منبع انجام شود.

دستورهای زیر فقط الگوی اجرای دستی اپراتور **بعد از مجوز** هستند؛ به سرور source/target وصل نمی‌شوند و باید در terminal همان میزبان، با `.env` درست اجرا شوند. source و target باید تشخیص داده شوند؛ قبل از restore، مقصد تازه و خالی را بررسی کنید.

```bash
# SOURCE، پس از توقف نوشتن مجازشده
docker compose stop api gateway
docker compose exec -T backup /opt/lifeguide/backup.sh /backups/LifeGuide-transfer.dump
docker compose cp backup:/backups/LifeGuide-transfer.dump ./LifeGuide-transfer.dump
sha256sum LifeGuide-transfer.dump
# انتقال امن/رمزگذاری‌شده dump، imageها و env توسط اپراتور؛ هیچ upload خودکار ندارد.

# TARGET تازه، با TLS/env آماده، پیش از public کردن
docker compose up -d --wait postgres
docker compose run --rm --no-deps db-provision
docker compose --profile ops create --no-deps restore
docker compose cp ./LifeGuide-transfer.dump restore:/backups/LifeGuide-transfer.dump
docker compose run --rm --no-deps restore /backups/LifeGuide-transfer.dump
docker compose run --rm --no-deps migrate
docker compose run --rm --no-deps db-grants
docker compose up -d --wait api gateway
node scripts/reachability-smoke.mjs https://OWNER_APPROVED_ORIGIN
```

در صورت snapshot فایل قدیمی با همان نام، قبل از backup نام یکتا انتخاب کنید؛ نسخه بازیابی معتبر قبلی را overwrite نکنید. این الگوی **restore واقعی UNVERIFIED** است. اجرای drill محلی، حفظ ledger و representative rows را می‌سنجد؛ جای مقایسه کامل policy/data و پذیرش cutover واقعی نیست.

## بازگشت

اگر مقصد هنوز نوشتن جدید ندارد، مالک می‌تواند DNS/endpoint را به منبع read-only حفظ‌شده برگرداند و بعد از بررسی مجوزها نوشتن را فعال کند. اگر مقصد داده جدید دارد، ابتدا backup کامل آن بگیرید؛ برگشت مستقیم به dump قدیمی آن نوشته‌ها را از بین می‌برد. reconciliation/restore معکوس باید با plan، حفظ هر دو نسخه و مجوز جدا انجام شود. rollback بدون بررسی Login/CRUD/Sync و داده تازه کامل نیست.
