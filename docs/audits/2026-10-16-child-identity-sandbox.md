# فاز۱ — زیربنای آزمایشی هویت کودک

**VERIFIED محلی:** `npm test -- --test-concurrency=1` → **297pass،0fail،0skip**. نقش محدود DB:30 و96 تست موفق؛ backup/restore با نقش‌های جدا موفق. این نتیجه برای Backend ساختگی محلی است؛ فاز۱ کامل و محصول آماده استفاده نیست.

## تغییر قابل بررسی

زنجیرهٔ جدید بر PR24 در `ef1205417b6523e199ace4ac3d3667a8aaf9cab5` متکی است، نه main قدیمی:

1. [PR27 — schema](https://github.com/davoodmehraban89/LifeMate/pull/27)، شاخه `feat/child-identity-schema`، commit `6050a422598c3a575bf5a1f8a49fbfe262de843d`: migration0024/0025، رضایت صرفاً ساختگی، دعوت و scope؛ تابع مشترک سرپرستی برای مدل جدید، نیازمند رضایت و شاهد پذیرش است.
2. [PR28 — مرز نشست](https://github.com/davoodmehraban89/LifeMate/pull/28)، شاخه `fix/managed-child-session-boundary`، commit `c72621fade774576ab9038f27e61670f5ba73335`: scope و صادرکننده از DB، حفظ محدودیت در refresh، no-store و منع مسیرهای خصوصی/ارتقای سن و نقش.
3. شاخه `feat/child-device-safety` روی PR28: API آزمایشی ساخت کودک، دعوت دستگاه، سرپرست دوم، لغو و نمایش محدود دیدپذیری؛ آزمون روی app واقعی و اضافه‌شدن همین سناریو به آزمون نقش محدود در CI. PR و head نهایی در گزارش تحویل ثبت می‌شوند.

همه تغییرات برای بررسی‌اند؛ هیچ merge،deploy،DNS،schema زنده یا SMS انجام نشده است. main هنگام بررسی همچنان `64b938dc9b0c3bb3620a7a12c22c690313d75bd7` بود. تغییرات ذخیره‌نشدهٔ worktreeهای قدیمی دست‌نخورده ماندند.

## دامنه و مرز داده

طبق [طرح sandbox](../decisions/2026-10-16-child-identity-sandbox.md)، تأیید ادامه فقط برای نمونه C-A/E-A/R-A تفسیر شد. `ENABLE_CHILD_IDENTITY_SANDBOX=true` همراه `NODE_ENV=test/development` لازم است؛ production همیشه503. این شرط مجوز واردکردن اطلاعات واقعی نیست.

- والد ایجادکننده باید عضو فعال با نقش parent_guardian، مدیر و دارای DOB بالغ باشد. کودک جدید DOB معتبرِ زیر۱۸ و category مستقل از نقش خانواده دارد؛ بدون تماس یا رمز ساخته می‌شود. سن با تاریخ DB محاسبه می‌شود؛ احراز حقوقی سن نیست.
- ثبت پروفایل، عضویت، سرپرست اولیه، نسخه/هش رضایت ساختگی و audit اتمیک است. متن `sandbox-child-consent-v1-not-legal` رضایت حقوقی نیست.
- سرپرست دوم فقط با دعوت سازنده و پذیرش همان عضو بالغ اضافه می‌شود. endpoint قدیمی `/guardians` برای این کودکان رد می‌شود؛ سیاست legacy برای حساب‌های قدیمی هنوز اصلاح کامل نشده است.
- دعوت دستگاه توکن تصادفی256بیتی/10دقیقه‌ای sandbox، digest و مصرف اتمیک دارد. صدور جایگزین ابتدا تمام نشست‌ها و دعوت‌های قبلی کودک را باطل می‌کند. حذف سرپرست دوم و لغو رضایت، اختیار/نشست‌های وابسته را قطع می‌کنند.
- هر نشست صادرشده توسط والد، حتی اولین ورود، فقط `child_education` دارد؛ refresh به standard تبدیل نمی‌شود. وابستگی به سرپرست صادرکننده، رضایت، خانواده و عضویت در درخواست بعد دوباره بررسی می‌شود.
- نام scope مجوز دسترسی به تمام داده آموزشی نیست: planner، جلسات خصوصی، هدف، سابقه آزمون، چت، سلامت و قاعدگی رد می‌شوند. فقط catalogue/locator/assessment منتشرشده، تقویم عمومی، پروفایل حداقلی بدون DOB/تماس، فهرست خانواده و API دیدپذیری مجازند. نمایش دیدپذیری فعلاً API است؛ صفحه Flutter نیست.

از آنجا که والد می‌تواند دستگاه را صادر کند، دادن نشست کامل کودک مسیر ورود به فضای خصوصی او می‌شد. تا طراحی مسیرهای آموزشی با مجوز سطح رکورد، مسیرهای خصوصی قدیمی برای این نشست‌ها باز نمی‌شوند. این بسته سناریوی کامل تکلیف/تایمر/آزمون والد را پیاده نمی‌کند.

## اجرای واقعی

Node24.19.0، npm11.9.0 و PostgreSQL16.15. ظرف **جدید** `lifeguide-child-tests-20261016` با tmpfs و اتصال فقط loopback ساخته شد؛ سرویس‌های قبلی و Supabase استفاده/تغییر نشدند. داده‌ها و تماس‌ها همه ساختگی‌اند. احراز اتصال fixture از نوع trust محلی بود؛ آزمون نقش‌ها، مجوز SQL را می‌سنجد و گواه تنظیم احراز شبکه تولید نیست.

|دستور|خروجی واقعی|
|---|---|
|`npm ci --no-fund`|111package نصب؛ exit0|
|`npm run migrate` روی DB تازه و تکرار|23migration؛ تکرار بدون اعمال مجدد، exit0|
|`node scripts/import-learning-catalog.js` و تکرار|217book/1373unit/1348video؛ تمام ویدیوها draft|
|`node --test tests/managed_child_scope.test.js` پیش از اصلاح|3fail/2pass؛ نشست محدود به مسیرهای خصوصی می‌رسید|
|`node --test tests/child_identity.test.js` پیش از وجود مسیر|9fail؛ مسیرهای جدید404|
|`npm test -- --test-concurrency=1` اجرای نهایی بدون فیلتر|297test/297pass/0fail/0skip؛87.75s|
|`node scripts/test-db-roles.js --synthetic-only`|30test/30pass با runtime مستقیم؛96test/96pass رگرسیون با fixture جدا|
|چهار `*schema_test.sql` با `psql -v ON_ERROR_STOP=1`|چهار exit0؛ سه fixture rollback، فایل phase6 فقط assertion خواندنی|
|`scripts/backup.sh` با نقش backup و `scripts/restore.sh` با migrator؛ `--verify-restored`|ledger23، مجوزها، داده ساختگی و study600seconds حفظ؛ exit0|
|`npm run check`؛ `npm audit --audit-level=high`؛ `git diff --check`|82فایل syntax؛0vulnerability؛ diff پاک|
|Gitleaks8.30.1 روی21فایل تغییرکردهٔ کد/schema/تست|0finding؛ archiveSHA با مرجع قبلی یکسان|
|بازبین مستقل؛ چهار فایل scope/identity/server/bundle|29pass/0fail/0skip؛ یافته مهم حل‌نشده در همین دامنه محدود گزارش نشد|

اجرای کامل نخست296pass/1fail بود: observer تست رقابت login/reset متن SQL قدیمی را عیناً می‌خواست؛ شرط جدید منع managed-child باعث شد قفل واقعی recovery را نشناسد. observer همچنان قفل واقعی account در `pg_stat_activity` را می‌بیند و اکنون فیلتر اضافی را مجاز می‌داند؛ اجرای نهایی297pass است. بازبین همچنین نام دارای NUL را با500 بازتولید کرد؛ validator و regression400 اضافه شد. wrapper گزارش SQL ابتدا به‌اشتباه برای assertion خواندنی phase6 انتظار ROLLBACK داشت؛ چهار اجرای psql از ابتدا exit0 بودند، طبقه‌بندی گزارش تصحیح شد.

۲۱ migration قبلی، شامل0001–0020 و0023، و bundleهای تاریخی Supabase بایت‌به‌بایت حفظ شدند. generator جدید23فایل را برای **schema تازه** می‌سازد؛ migration افزایشی مناسب QA موجود یا گواه اعمال زنده نیست. از اجرای آن یا migrator عمومی روی Supabase موجود خودداری شود تا بسته انتقال جدا بررسی و تأیید شود.

[رسید ماشین‌خوان و SHA لاگ‌ها](evidence/child-identity-sandbox-2026-10-16.json). لاگ‌های کامل ساختگی در بسته تحویل مستقل نگهداری می‌شوند؛ شماره/ایمیل واقعی، رمز، توکن یا داده واقعی کودک در این گزارش و receipt نیست.

## اجرای مجدد

روی شاخه نهایی، فقط PostgreSQL **تازه و محلیِ ساختگی** با نام `lifemate_ci` بسازید و `DATABASE_URL`/`JWT_SECRET` آزمایشی را در محیط قرار دهید؛ سپس در backend:

```sh
npm ci
npm run migrate
npm run migrate
node scripts/import-learning-catalog.js
npm test -- --test-concurrency=1
npm run check
```

نصب UI جدید یا ارسال SMS لازم نیست. CI موجود نیز پس از PR همین migration/test و آزمون نقش/restore را اجرا می‌کند؛ وضعیت تازه هر PR باید از خروجی خودش خوانده شود. اجرای Flutter212 و ساخت APKdebug در CI قبلی PR24 تأیید شد، ولی ساخت این بسته یا نصب واقعی محسوب نمی‌شود.

## UNVERIFIED و ادامه

UI/QR، Android/iPhone/Safari و نصب/ارتقا؛ مسیر جدید مجازِ تکلیف/تایمر/آزمون، SMS واقعی و تأیید کاوه‌نگار؛ دسترسی ایران؛ سیستم آنلاین عمومی؛ رضایت حقوقی، نگهداری و زیرساخت تولید؛ اعمال0024/0025 روی Supabase و امضای release تأیید نشده‌اند. داده کودک واقعی یا تغییر میزبانی مجاز نشده است.

P0های قبلیِ داده حساس در صورت بازکردن flag، سرپرستی حساب‌های legacy و سایر موارد ممیزی همچنان در برنامه‌اند. UI توضیح مجوزها، متن رضایت/اعتراض و مسیر بلوغ باید جدا تکمیل و بازبینی شوند. **فاز۲ شروع نشده است؛ فاز۱ کامل اعلام نمی‌شود.**
