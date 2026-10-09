# LifeGuide — نقش‌های محدود PostgreSQL

این بسته، فقط PostgreSQL مستقل Compose را پیکربندی می‌کند. اجرای زنده، داده واقعی، انتقال واقعی یا تغییر حساس دسترسی نیازمند مجوز مالک است؛ این runbook چنین مجوزی ایجاد نمی‌کند. آزمون این بسته باید با fixture ساختگی باشد. نام schema/JWT/repo تغییر نمی‌کند.

| نقش | مجوز | محل credential |
| --- | --- | --- |
| bootstrap: `POSTGRES_USER` | مدیر اولیه PostgreSQL؛ DB را ایجاد می‌کند و provisioning/grants کوتاه‌مدت انجام می‌دهد | فقط postgres و jobs عملیاتی؛ هرگز API یا cron backup |
| `lifeguide_migrator` | LOGIN مستقل، بدون superuser/createdb/createrole/bypassRLS/عضویت؛ مالک public و اشیای برنامه، CREATE فقط در DB برنامه برای trusted pgcrypto | migrate و restore دستی |
| `lifeguide_api` | LOGIN مستقل، DML برنامه، sequence USAGE/SELECT، توابع INVOKER مشخص برنامه و UUID generator؛ بدون مالکیت/CREATE/TEMP/TRUNCATE/ledger | فقط API |
| `lifeguide_backup` | LOGIN مستقل، SELECT جدول‌ها و ledger/sequenceها؛ بدون نوشتن یا اجرای توابع برنامه | فقط backup |

سه نقش برنامه نباید مالک هیچ DB در cluster باشند. Runtime/backup نباید مالک schema، relation، function، type یا extension در DB هدف باشند؛ preflight این وضعیت و عضویت/flags غیرمنتظره را پیش از تغییر credential/grant رد می‌کند. DB اختصاصی برنامه فقط public و schemaهای سیستمی PostgreSQL را می‌پذیرد؛ namespace ناشناخته، از جمله CREATE موروثی یا SECURITY DEFINER در schema دیگر، fail می‌شود و ACL آن خودکار تغییر نمی‌کند. این بررسی مالکیت سایر DBها را می‌سنجد؛ policy جدول/ACL داخل DBهای نامرتبط را تغییر نمی‌دهد. cluster اختصاصی LifeGuide توصیه می‌شود؛ ایجاد DB جدید و تغییر PUBLIC ACL در سایر DBها نیازمند ممیزی اپراتور است.

نقش‌ها در env مستقل‌اند. `node scripts/prepare-db-role-env.mjs --write` فقط متغیرهای مفقود/placeholder سه نقش را با secret تصادفی در `.env` محلی می‌سازد؛ credential قبلی bootstrap/JWT را حفظ می‌کند. `.env` چاپ یا `source` نشود. PowerShell/Windows اجرای واقعی این بسته **UNVERIFIED** است.

## پایگاه تازه

`local-deploy.sh` و نسخه PowerShell ترتیب را رعایت می‌کنند:

1. PostgreSQL bootstrap سالم شود.
2. `db-provision` نقش‌ها، public و default privileges را آماده کند.
3. `migrate` با credential غیرsuperuser مهاجرت‌های موجود را اجرا کند.
4. `db-grants` با مدیر کوتاه‌مدت، grantهای فعلی را تطبیق دهد؛ PUBLIC EXECUTE و مجوز ledger API را لغو کند.
5. API/backup فقط پس از موفقیت این مراحل شروع شوند.

برای بررسی دستی **محلی**، بدون build کردن Flutter SDK داخل Docker:

```bash
node scripts/prepare-db-role-env.mjs --write
docker compose config --quiet
docker compose up -d --wait postgres
docker compose run --rm --no-deps db-provision
docker compose run --rm --no-deps migrate
docker compose run --rm --no-deps db-grants
docker compose up -d --wait api gateway backup
```

migrationهای تکراری checksum ledger را بررسی می‌کنند. default privileges فقط برای سازنده migrator اعمال می‌شوند؛ آینده باید migration/restore را با همین نقش اجرا کند. جدول جدید مالک migrator می‌ماند و runtime DML/backup SELECT می‌گیرد. تابع جدید خودکار به API/backup داده نمی‌شود؛ allowlist توابع باید همراه بررسی امنیتی توسعه یابد. پس از هر migration، `db-grants` الزامی است؛ اجرای migrate منفرد جای این ترتیب را نمی‌گیرد.

مقادیر پیش‌فرض قدیمی UUID به تابع `public.gen_random_uuid()` متعلق به pgcrypto bind شده‌اند. صرف تغییر search_path کافی نیست؛ EXECUTE فقط همین تابع تولید مقدار برای API/migrator حفظ می‌شود. مالک extension یا C functions آن دست‌کاری نمی‌شود. توابع مجوز برنامه همچنان SECURITY INVOKER هستند؛ این بسته RLS یا جداسازی tenant در SQL ایجاد نمی‌کند. policyهای server-side کاربران/خانواده همچنان ضروری‌اند.

## پایگاه موجود: انتقال مالکیت فقط با تصمیم اپراتور

اجرای عادی provisioning روی اشیای دارای مالک قبلی fail می‌شود؛ هیچ `REASSIGN OWNED` یا انتقال wildcard ندارد. عملیات پایین متعلق به اپراتور همان میزبان است و روی میزبان زنده در این کار اجرا نشده است.

1. داده واقعی را وارد نکنید تا پذیرش این بسته کامل شود. snapshot مالکیت و grantهای قبلی، نسخه imageها و کپی امن env را نگه دارید. PUBLIC grants پیشین را برای rollback فهرست کنید؛ secretها در گزارش نیایند.
2. نوشتن محلی را متوقف کنید: `docker compose stop api gateway`. backup قبلی معتبر را حفظ کنید. **پیش از تغییر نسخه/credential container قدیمی backup** از همان credential فعلی مجاز dump تازه بگیرید: `docker compose exec -T backup /opt/lifeguide/run-backup.sh`؛ برنامه نام یکتا تولید می‌کند. اگر container قبلی در دسترس نیست، اپراتور با administrator امن و script موجود backup بسازد؛ credential در command line یا chat نرود.
3. `pg_restore --list` و یک restore drill از backup را بررسی کنید. فایل هدف adoption باید در volume `/backups`، custom-format و متعلق به همین DB باشد. فقط خوانایی archive جای اثبات کامل restore نیست.
4. image API جدید را build/load و env مستقل نقش‌ها را آماده کنید؛ هنوز API متوقف بماند. نام مالک قبلی را از snapshot واقعی تعیین کنید؛ پیش‌فرض به معنی اثبات مالک نیست.

   ```bash
   bash scripts/adopt-db-roles.sh --local-existing --expected-owner lifeguide \
     --backup-file /backups/LifeGuide-OWNER-CHOSEN-UNIQUE.dump
   docker compose run --rm --no-deps migrate
   docker compose run --rm --no-deps db-grants
   docker compose up -d --wait api gateway backup
   bash scripts/test-db-roles.sh --synthetic-only
   ```

helper Docker remote و API فعال را رد می‌کند، `pg_restore --list` واقعی و header نام DB را می‌سنجد، SHA256/manifest اعتبارسنجی تازه می‌سازد و تنها سپس Node provisioning را فراخوانی می‌کند. Node همان hash، DB و validation را بررسی می‌کند. این شاهد خوانایی/هویت archive است؛ تازگی کامل داده و restore آن backup را اپراتور جدا تأیید می‌کند. انتقال مالکیت فقط جدول/sequence/type/functionهای allowlist برنامه با مالک قبلیِ دقیق، در DB/public فعلی است؛ extension memberها، مالک DB و اشیای نامرتبط تغییر نمی‌کنند. مالکیت غیرمنتظره runtime/backup/migrator روی DB نیازمند حل دستی و مجوز جداست.

5. health، ورود، CRUD/shared report، دسترسی غیرمجاز و رکوردهای قبل/بعد را با API/SQL مستقل بررسی کنید. ledger تاریخی بدون checksum را صادقانه **UNVERIFIED** نگه دارید؛ آن را گذشته‌نگر backfill نکنید. در صورت خطا، writers را روشن نکنید؛ backup و هر دو snapshot را حفظ کنید.

PostgreSQL به LOGIN اجازه تغییر password/تنظیمات خودش را می‌دهد؛ NOCREATEROLE جلوی مدیریت نقش دیگر یا ارتقای superuser را می‌گیرد، نه همه شکل‌های `ALTER ROLE` خودش. آزمون، تغییر نقش دیگر و ارتقای دسترسی خود را واقعاً رد می‌کند. این credential فقط در server/secret management است؛ کاربران محصول آن را دریافت نمی‌کنند.

## backup، restore و انتقال داخلی

cron اکنون با نقش read-only dump می‌گیرد. restore با backup credential انجام نمی‌شود؛ `restore` یک service دستی با migrator و profile `ops` است. فقط مقصد **تازه و خالی** را برای restore تعیین کنید؛ script موجود `--clean --if-exists` دارد و روی مقصد دارای داده جدید مناسب نیست. dump از `--no-owner --no-privileges` استفاده می‌کند، بنابراین مالک/grants باید در مقصد از ترتیب provisioning → restore/migrate → grants بازسازی شوند.

```bash
# TARGET تازه، فقط پس از مجوز اپراتور، TLS/env/image آماده
docker compose up -d --wait postgres
docker compose run --rm --no-deps db-provision
docker compose --profile ops create --no-deps restore
docker compose cp ./LifeGuide-transfer.dump restore:/backups/LifeGuide-transfer.dump
docker compose run --rm --no-deps restore /backups/LifeGuide-transfer.dump
docker compose run --rm --no-deps migrate
docker compose run --rm --no-deps db-grants
docker compose up -d --wait api gateway backup
```

pgcrypto مقصد باید توسط migrator ایجاد شود؛ restore روی extension قدیمی متعلق به administrator می‌تواند در `COMMENT ON EXTENSION` شکست بخورد. به همین دلیل مقصد خالی و drill لازم‌اند؛ مالک extension را با تغییر catalog اصلاح نکنید. DNS/cutover/rollback زنده همچنان **UNVERIFIED** هستند. backup رمزگذاری‌شده خارج PC هنوز gate جداست.

## آزمون قابل اجرای محلی و CI

```bash
bash scripts/test-db-roles.sh --synthetic-only
# restore-drill همین سناریو را با read-only dump و migrator restore اجرا می‌کند:
bash scripts/restore-drill.sh --synthetic-only
```

آزمون دو DB تازه با نام تصادفی `lifeguide_roles_*` و comment مخصوص run می‌سازد. خطاهای مالکیت عمدی، CREATE مستقیم/موروثی در schema ناشناخته و SECURITY DEFINER فقط در همین DBها بررسی و برگشت داده می‌شوند. نقش‌ها/default grants، تمام12migration و تکرار، SQL forbidden، CRUD جدول جدید، سناریوی واقعی خانواده با API runtime، read-only dump، migrator restore و policy خصوصی مقصد آزموده می‌شوند. cleanup فقط DBهایی با نام/comment/owner دقیق همان run را حذف می‌کند؛ اگر cleanup fail شود state محلی حفظ و نتیجه **UNVERIFIED** گزارش می‌شود. application DB و volumeها restore/drop نمی‌شوند.

در اجرای واقعی محلی ۲۰۲۶-۱۰-۰۹، این سناریو **PASS** بود:9/9 آزمون خانواده با runtime،17 منع SQL در هر یک از source/restore،12checksum ledger و cleanup صفر DB باقی‌مانده. adoption صریح DB ساختگی موجود نیز پس از backup/list/hash موفق شد؛ یک تلاش اولیه به علت linked identity sequence fail شد و transaction کامل rollback کرد. اصلاح فقط انتقال مالکیت table و بررسی follow-up sequence است. API واقعی سپس `lifeguide_api` با flags/CREATE/TEMP=false گزارش کرد؛ task قبلی version6 و session1500ثانیه هر دو دقیقاً یک رکورد باقی ماندند. ledger تاریخی0001–0010 همچنان بدون checksum و **UNVERIFIED** است. شواهد root در گزارش پذیرش ثبت می‌شوند؛ Windows/سرور زنده/rollback زنده با این اجرای محلی تأیید نمی‌شوند.

CI بدون تغییر Compose نیز می‌تواند `backend/scripts/test-db-roles.js` را با PG fields مدیر **fixture** و سه password مستقل اجرا کند: `--synthetic-only`، سپس dump با backup و restore با migrator با client16، `--verify-restored` و `--cleanup`. `ROLE_TEST_STATE_FILE` فقط شناسه DBهای ساختگی را دارد؛ credential در آن نیست. suite نگهدارنده با administrator، جای این آزمون API/runtime را نمی‌گیرد. دستگاه Android/Safari، Windows، شبکه ایران و سرور زنده با این سناریو تأیید نمی‌شوند.
