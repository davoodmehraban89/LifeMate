# ممیزی بازیابی، CI و زیرساخت LifeMate / LifeGuide

تاریخ بررسی: ۲۰۲۶-۱۰-۰۸. مخزن مرجع: [`davoodmehraban89/LifeMate`](https://github.com/davoodmehraban89/LifeMate)، خصوصی. این گزارش یک مشاهدهٔ خواندنی از وضعیت موجود است. هیچ سرویس، DNS، متغیر، کلید، استقرار یا منبع ابری تغییر نکرد؛ هیچ مهاجرت یا restore واقعی و هیچ اقدام هزینه‌دار اجرا نشد. مقادیر secret دریافت یا در گزارش درج نشدند.

## مبنای بازیابی و اعتبار اسناد

- worktree بررسی‌شده: `/workspace/LifeMate-persistence`، شاخهٔ محلی `fix/local-task-persistence`، مبنا `796d6bec16841020323bf67275f60c38048a0374` از `test/role-entry-apk`.
- طبق `AGENTS.md`، مخزن منبع حقیقت فنی است و تکمیل کار یا استقرار فقط با شاهد واقعی اعلام می‌شود.
- `PROJECT_STATE.md` موجود است ولی آخرین تاریخ درج‌شدهٔ آن ۲۰۲۶-۱۰-۰۵ است. CI شمارهٔ ۱۶۵ و استقرار قدیمی Phase 5 در این فایل شاهد تاریخی‌اند؛ وضعیت امروز باید با شواهد پایین خوانده شود.
- `PROJECT_STATUS.md` در worktree و در سه مرجع `main`، `test/role-entry-apk` و `infra/cloudflare-neon-migration` وجود ندارد. این گزارش آن فایل را ایجاد نمی‌کند.
- هر دو سند درخواستی در شاخهٔ APK و worktree بازیابی موجودند؛ در `main` و شاخهٔ زیرساخت موجود نیستند:
  - [طراحی پروفایل و راهنمایی شخصی](https://github.com/davoodmehraban89/LifeMate/blob/796d6bec16841020323bf67275f60c38048a0374/docs/superpowers/specs/2026-10-07-personalized-profile-guidance-design.md).
  - [برنامهٔ پیاده‌سازی پایهٔ پروفایل](https://github.com/davoodmehraban89/LifeMate/blob/796d6bec16841020323bf67275f60c38048a0374/docs/superpowers/plans/2026-10-07-personalized-profile-foundation.md).
- برای این اسناد نیازی به بازیابی از Aram نبود؛ مخزن Aram در این ممیزی بررسی نشد و با LifeMate یکی فرض نشده است.

## موجودی شاخه‌های GitHub

موجودی از API رسمی GitHub و refs محلی خوانده شد؛ SHAهای راه دور با refs موجود همخوان‌اند. ۱۱ شاخهٔ راه دور دیده شد. فیلد `protected` در پاسخ فهرست شاخه‌ها برای همه `false` بود؛ rulesetها یا همهٔ تنظیمات حفاظتی بررسی نشده‌اند.

| شاخه | SHA کوتاه | نقش مشاهده‌شده |
| --- | --- | --- |
| `main` | `abdc9d9` | آخرین مبنای انتشار عادی و اسناد rebrand |
| `test/role-entry-apk` | `796d6be` | ورودی آزمایشی نقش/پروفایل و ذخیرهٔ محلی پروفایل |
| `infra/cloudflare-neon-migration` | `7a83ca8` | adapter و تنظیمات Worker و runbook مهاجرت |
| `deployment-static` | `d415f07` | خروجی static workflow از `main@abdc9d9` |
| `deploy/stable-web-apk` | `97af303` | تنظیم PWA/nginx |
| `final-feature-1/iran-family-school` | `71ee193` | checkpoint ویژگی خانواده/مدرسهٔ ایران |
| `phase-1/foundation-completion` | `36a4d76` | checkpoint Phase 1 |
| `phase-2/product-foundation-identity` | `801e8c0` | checkpoint Phase 2 |
| `phase-3/planner-school-family-core` | `fe1f2ad` | checkpoint Phase 3 |
| `phase-4/ai-learning-wellbeing` | `c447270` | checkpoint Phase 4 |
| `phase-5/hardening-observability-release` | `1db6951` | checkpoint Phase 5 |

`test/role-entry-apk` شامل ۸ commit پس از `main` است. شاخهٔ زیرساخت شامل ۴ commit پس از `main` است و هیچ‌کدام از آن ۸ commit پروفایل/ورودی آزمایشی را ندارد. بنابراین دو شاخه، دو مسیر موازی توسعه‌اند؛ هیچ‌یک جمع نهایی دیگری نیست. [مقایسهٔ main و زیرساخت](https://github.com/davoodmehraban89/LifeMate/compare/abdc9d9d032bc6746c8390b902a2e52d82991530...7a83ca86e72ef8f2c022188c860f9add4dc595c9).

## شواهد CI و APK موجود

| شاهد | commit | نتیجه و محدودیت |
| --- | --- | --- |
| [Role-entry APK، run 37671241887](https://github.com/davoodmehraban89/LifeMate/actions/runs/37671241887) | `796d6be` | موفق؛ تست ورودی، ساخت APK، upload artifact و انتشار release موفق بودند |
| [LifeMate CI، run 37440198741](https://github.com/davoodmehraban89/LifeMate/actions/runs/37440198741) | `main@abdc9d9` | ناموفق؛ Flutter analyze متوقف شد؛ backend و security موفق بودند |
| [Publish static PWA and APK، run 37440198808](https://github.com/davoodmehraban89/LifeMate/actions/runs/37440198808) | `main@abdc9d9` | موفق؛ موفقیت ساخت/انتشار مستقل از موفقیت CI کامل است |

در زمان مشاهده، run `37671241887` آخرین اجرای مخزن بود. خطای main از log همان job استخراج شد: import استفاده‌نشدهٔ `package:flutter/material.dart` در `test/app_test.dart:1:8`، با کد `unused_import`. [Job مربوط](https://github.com/davoodmehraban89/LifeMate/actions/runs/37440198741/job/112191790908). تست‌های Flutter و ساخت‌های job اصلی بعد از شکست analyze skipped شدند. در همان run، backend شامل migration، تست authorization، تست‌های Node، syntax، schema و backup/restore drill موفق بود.

Workflow شاخهٔ APK فقط `flutter test test/role_entry_test.dart` و `flutter build apk --release --target=lib/role_entry_main.dart` را اجرا می‌کند. analyze کامل، کل suite Flutter، backend یا restore drill در آن workflow وجود ندارد. APK از entrypoint آزمایشی با bypass ورود ساخته می‌شود؛ نتیجهٔ موفق آن برای آزمون APK معتبر است و به‌تنهایی تأیید readiness انتشار عمومی نیست.

Artifact ثبت‌شده:

- نام: `LifeGuide-role-entry-test-apk`؛ ID: `11505078172`.
- متعلق به run `37671241887` و SHA کامل `796d6bec16841020323bf67275f60c38048a0374`.
- ایجاد: `2026-10-07T19:07:21Z`؛ انقضا: `2026-11-06T19:07:18Z`؛ `expired=false` هنگام بررسی.
- اندازهٔ ZIP: `24,893,371` بایت؛ digest آرشیو: `sha256:83435b95549161e66c45110633984ed794389f1d72ec310577ab259b149c4dcc`.
- [صفحهٔ artifact](https://github.com/davoodmehraban89/LifeMate/actions/runs/37671241887/artifacts/11505078172).

در [release آزمایشی](https://github.com/davoodmehraban89/LifeMate/releases/tag/lifeguide-role-entry-test)، tag فعلی `lifeguide-role-entry-test` مستقیماً به `796d6be` اشاره می‌کند. مقدار قدیمی `target_commitish` در metadata release برابر `3022f90` است؛ برای تعیین commit جاری، ref واقعی tag خوانده شد. Workflow tag را force می‌کند و asset را clobber می‌کند، پس این URL به مرور می‌تواند محتوای جدید بگیرد.

- نام فایل واقعی asset: `app-release.apk`؛ ID: `619548802`؛ اندازه: `53,860,559` بایت.
- آخرین update: `2026-10-07T19:07:26Z`.
- digest فایل APK: `sha256:4b37273ab1ab84e3886a26a3fc292919737c6cf0b69064ca3cac27f7958d86b1`.
- [دانلود APK ثبت‌شده](https://github.com/davoodmehraban89/LifeMate/releases/download/lifeguide-role-entry-test/app-release.apk)؛ دسترسی به مخزن خصوصی ممکن است ورود GitHub بخواهد.

Artifact و asset در این ممیزی دانلود/نصب نشدند؛ metadata، test/build job و ref tag بررسی شدند. این شواهد به commit مبنا مربوط‌اند و تأیید تغییرات جدید شاخهٔ `fix/local-task-persistence` محسوب نمی‌شوند.

## وضعیت مشاهده‌شدهٔ Railway

Connector متصل Railway، پروژهٔ `LifeMate-Staging` با ID `5b6a666b-3e8c-4ec4-9500-9b998e96b6fb` و تنها محیط `staging` با ID `a5ec96e7-5cc6-4c76-8aeb-143e0826b43e` را نشان داد. [داشبورد پروژه](https://railway.com/project/5b6a666b-3e8c-4ec4-9500-9b998e96b6fb?environmentId=a5ec96e7-5cc6-4c76-8aeb-143e0826b43e).

| سرویس | وضعیت platform | استقرار فعال | replica در حال اجرا |
| --- | --- | --- | --- |
| `lifemate-api` | `online` / `SUCCESS` | `93ad695c-f5d5-4a14-a65b-6af532577b5f` | ۱ از ۱ |
| `lifemate-api-fn` | `online` / `SUCCESS` | `5139297f-9bae-4c9a-8646-f1b74fc306cb` | ۱ از ۱ |
| `lifemate-migrate` | `online` / `SUCCESS` | `6c6c3539-b392-4309-bf50-7478a042c38a` | ۰ از ۱ |
| `mailpit` | `online` / `SUCCESS` | `02999604-81fc-44fe-857d-5f53bea7ec56` | ۱ از ۱ |
| `Postgres` | `online` / `SUCCESS` | `5dec5df6-8cbe-425a-b299-4a6d2603820a` | ۱ از ۱ |

خلاصهٔ environment status: ۵ سرویس، صفر service دارای issue، صفر failure در ۲۴ ساعت قبل، صفر warning/critical و `pendingWork=[]`. خروجی مربوط به `lifemate-migrate` هم‌زمان وضعیت online و صفر replica در حال اجرا را گزارش می‌کند؛ از این خروجی، صحت اجرای migration جاری نتیجه‌گیری نمی‌شود.

`lifemate-api` از `main@abdc9d9` در ۲۰۲۶-۱۰-۰۶ deploy شده است. استقرار فعال API function نیز در ۲۰۲۶-۱۰-۰۶ ایجاد شده و metadata آن image تابع Railway را نشان می‌دهد؛ SHA کد تابع از آن metadata معلوم نیست. [سرویس API function](https://railway.com/project/5b6a666b-3e8c-4ec4-9500-9b998e96b6fb/service/4909ac28-f1b2-47a9-9630-51a6dde30aca?environmentId=a5ec96e7-5cc6-4c76-8aeb-143e0826b43e).

برای API function دامنهٔ `lifemate-api-fn-staging.up.railway.app` روی port `8080` موجود است، custom domain دیده نشد، staged patch وجود ندارد و tracing / auto-instrumentation فعال‌اند. Endpoint موجود: `https://lifemate-api-fn-staging.up.railway.app`.

این بخش وضعیت platform را ثبت می‌کند. درخواست HTTP به `/live`، `/ready` یا `/health`، login، smoke flow یا SQL در این ممیزی اجرا نشد؛ سلامت کاربردی و آماده‌بودن DB از online بودن platform استنتاج نمی‌شود. آخرین backup واقعی staging و restore از آن backup نیز دیده نشده است. drill موفق CI روی PostgreSQL موقت، جای تأیید backup staging را نمی‌گیرد.

## شاخهٔ Cloudflare / Neon و وضعیت مشاهده‌شده

شاخهٔ [`infra/cloudflare-neon-migration@7a83ca8`](https://github.com/davoodmehraban89/LifeMate/tree/7a83ca86e72ef8f2c022188c860f9add4dc595c9) فقط ۴ فایل و ۱۰۸ خط نسبت به main اضافه می‌کند:

- `backend/src/worker.js`: entrypoint با `httpServerHandler`، انتقال bindingهای server به محیط Node و reuse کردن `entrypoint.js`.
- `backend/wrangler.jsonc`: نام Worker برابر `lifeguide-api`، compatibility date برابر `2026-10-07`، flag `nodejs_compat`، observability فعال؛ متغیرهای غیرمحرمانهٔ `NODE_ENV=production` و `LOG_REQUESTS=true`.
- `backend/tests/cloudflare_neon_contract.test.js`: دو تست قرارداد پیکربندی/runbook.
- `docs/operations/CLOUDFLARE_NEON_MIGRATION.md`: backup/restore، staging acceptance، cutover و rollback.

[runbook مهاجرت](https://github.com/davoodmehraban89/LifeMate/blob/7a83ca86e72ef8f2c022188c860f9add4dc595c9/docs/operations/CLOUDFLARE_NEON_MIGRATION.md) صریحاً حفظ Railway تا پذیرش مسیر جدید و تأیید صریح production cutover را لازم می‌داند. وجود این فایل و نام‌های secret در آن، شاهد provision یا انجام مهاجرت نیست.

API رسمی GitHub برای این شاخه صفر workflow run برگرداند. CI عمومی فعلی تنها روی push به `main` و `pull_request` اجرا می‌شود؛ push عادی به شاخهٔ زیرساخت gate CI مستقل ندارد.

تست قرارداد موجود، از محتوای commit `7a83ca8` در پوشهٔ موقت جداگانه اجرا شد: `node --test --test-reporter=tap backend/tests/cloudflare_neon_contract.test.js`، نتیجه ۲ تست، ۱ موفق، ۱ ناموفق، exit code برابر ۱. تست نخست انتظار وجود `/lifeguide-api/` در `worker.js` را دارد؛ نام فقط در `wrangler.jsonc` هست. تست runbook موفق بود. این یک ناسازگاری تست/فایل است؛ شکست همین تست به‌تنهایی خرابی runtime Worker را ثابت نمی‌کند. build یا اجرای واقعی Worker و سازگاری dependencyها در این ممیزی بررسی نشد.

Cloudflare متصل، یک account قابل مشاهده نشان داد. GET فهرست Workerها موفق بود و `lifeguide-api` در آن وجود نداشت. lookup دقیق zone با نام `lifeguide.ir` نیز موفق بود و صفر نتیجه داد. این شواهد محدود به account متصل‌اند؛ فقدان Worker/zone در همهٔ accountها یا DNS نزد registrar را ثابت نمی‌کنند. درخواست inventory برای Pages با `INVALID_ARGUMENT` / کد `8000024` برگشت؛ بنابراین موجودی Pages تأیید نشد. هیچ endpoint جدید حدس زده یا deploy نشد. [صفحهٔ Workers در account متصل](https://dash.cloudflare.com/ace6f7219be1e7d9ac5bacd59c05fbe2/workers-and-pages).

ابزارهای Neon موجودند اما project ID در اسناد بررسی‌شده یا context این ممیزی ارائه نشده است. CLI Neon نصب نبود. درخواست خواندنی `describe_project({})` نیز `INVALID_ARGUMENT` برگرداند و ابزار فهرست پروژه‌ها در ابزارهای قابل فراخوانی وجود نداشت. بنابراین project/branch/compute، schema، انتقال داده، backup یا readiness Neon تأیید نشده‌اند. project ID حدس زده نشد، connection string یا credential درخواست نشد و resource جدید ساخته نشد.

## موانع باقی‌مانده و ترتیب پیشنهادی بازیابی

1. commit مبنای APK و اسناد پروفایل باید در مسیر بازیابی حفظ شود؛ شاخهٔ زیرساخت جایگزین کامل آن نیست. تغییرات تازهٔ شاخهٔ بازیابی نیاز به verification تازه دارند.
2. قبل از ادعای CI کامل سبز، warning ثبت‌شدهٔ analyze و هر یافتهٔ تازهٔ verification اصلاح و gate کامل روی commit نهایی اجرا شود. موفقیت workflow ساخت APK یا static publish این مانع را برطرف نمی‌کند.
3. ناسازگاری قرارداد Cloudflare و نبود CI ثبت‌شدهٔ آن شاخه مانع اعلام آماده‌بودن مهاجرت است. staging build و runtime Worker، health/readiness و جریان‌های auth/family/planner/privacy هنوز شاهد پذیرش ندارند.
4. برای بررسی Neon، شناسهٔ پروژهٔ موجود و اتصال خواندنی scoped لازم است؛ تا آن زمان وضعیت آن «تأییدنشده» است.
5. قبل از هر cutover، backup واقعی Railway با recovery point معلوم، restore drill جدا، مقایسهٔ داده/constraintها و rollback target باید مشخص و تأیید شوند. این ممیزی هیچ‌کدام را اجرا نکرده است.
6. `PROJECT_STATE.md` باید با تاریخ و شاهد جدید همگام شود. فقدان `PROJECT_STATUS.md` و checkboxهای برنامهٔ پروفایل نباید با انجام‌شدن یا انجام‌نشدن واقعی کار یکسان تلقی شود.
7. Railway موجود باید طبق runbook حفظ شود. production deploy/cutover، restore مخرب، انتشار عمومی، حذف سرویس و اقدام هزینه‌دار خارج از این ممیزی‌اند و مجوز مربوط به همان اقدام را لازم دارند.

Runbookهای موجود برای ادامه: [Deployment](../operations/DEPLOYMENT.md)، [Rollback](../operations/ROLLBACK.md)، [Backup/Restore](../operations/BACKUP_RESTORE.md)، [Incident Response](../operations/INCIDENT_RESPONSE.md)، [Production Checklist](../operations/PRODUCTION_CHECKLIST.md).
