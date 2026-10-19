# LifeGuide / لایف‌گاید — وضعیت واقعی پروژه

## آزمون مستقل اعلان Android — ۲۰۲۶-۱۰-۱۹؛ پذیرش گوشی هنوز باز است

[PR36](https://github.com/davoodmehraban89/LifeMate/pull/36) فقط fixture و ابزار آزمون شبیه‌ساز است؛ Flutter/Android عملیاتی، Backend و APK تحویلی0.7.2+8 تغییر نکرده‌اند. پورت اصلی با رکورد ساختگی و برچسب صریحِ تأیید سرور شبیه‌سازی‌شده استفاده می‌شود. دستگاه فیزیکی/بستهٔ از قبل نصب‌شده رد می‌شود؛ fixture APK توزیع نمی‌شود.

**VERIFIED در7fb737d:** Flutter282pass، host21pass و analyze بدون ایراد؛ CI عمومی39192545903 موفق با Backend308pass، role41 و regression96، buildوب و APKdebug. **اجرای شبیه‌ساز39192545919 شکست خورد**: `fixture_process_did_not_exit`؛ نصب تازه و inspect موفق بودند، پذیرش رسیدن اعلان انجام نشد. [شکست حفظ‌شده](docs/audits/evidence/android-reminder-ci-first-2026-10-19.json) و [دستورهای محلی](docs/audits/evidence/android-reminder-tooling-2026-10-19.json). اجرای دوم39193398410، بسته‌شدن پردازش را پس از۴تلاش تأیید کرد، ولی دریافت markerصفحهٔ scheduleشکست خورد؛ [شکست دوم](docs/audits/evidence/android-reminder-ci-second-2026-10-19.json). ابزار اکنون taskساختگی خودش را با NEW_TASK/CLEAR_TASKباز می‌کند؛ وضعیت بومی و اعلان‌ها پاک نمی‌شوند. host25تست موفق؛ اجرای سوم39194206345نیز باخطای فرمان ابزار شکست خورد؛ [گواه](docs/audits/evidence/android-reminder-ci-third-2026-10-19.json). NEW_TASKنام خط‌فرمان مستقلی ندارد؛ مقدار مستند `-f 0x10008000`جایگزین شد. اجرای بعدی Androidهنوز UNVERIFIED است. CIعمومی دوم39193398238 بر837f323نیز موفق شد.

**VERIFIED خواندنی:** GETباTLSمعتبر در19اکتبر روی سه مسیر عمومی `app.lifeguide.ir/config.json`،`/api/health` و`/health` هر سه404 داد؛ APIسازگار از این مسیرها تأیید نشد. [رسید](docs/audits/evidence/public-api-paths-2026-10-19.json). این آزمون دسترسی از ایران یا تمام مسیرهای دامنه نیست. هیچ deploy،merge،DNS،حساب/داده واقعی یا تغییر سیاستی انجام نشده است. نصب/اعلان/صدا/باتری روی گوشی، Safari، ورود خصوصی کودک و APIعمومی همچنان **UNVERIFIED/باز** هستند. [راهنمای آزمون](docs/operations/ANDROID_REMINDER_ACCEPTANCE.md).

## برنامهٔ هفته و اعلان Android — ۲۰۲۶-۱۰-۱۸؛ هنوز آمادهٔ بهره‌برداری کودک نیست

مالک اجرای بستهٔ برنامهٔ شخصی را تأیید کرد. API مستقل در [PR34](https://github.com/davoodmehraban89/LifeMate/pull/34) و Flutter/Android وابسته در [PR35](https://github.com/davoodmehraban89/LifeMate/pull/35) آماده شد؛ هیچ merge/deploy انجام نشد. نوبت‌های واقعی PostgreSQL، تکرار و ساعت‌های مستقل، صف پایدار، تیک/ویرایش هر روز و اعلان opt-in با دریافت تازهٔ مالک پیاده شد. Feature1، نام LifeGuide و مرز خصوصی نشست کودک حفظ شدند.

**VERIFIED محلی در0878623:** Backend308pass/0fail/0skip؛ Flutter277pass/0fail؛ analyze بدون مشکل، build releaseوب67.0ثانیه و منابع محلی؛ بررسی credential فایل‌های tracked و naming459مورد موفق. بازبینی سه خطای خاموش‌کردن اعلان، برگشت تیک/یادآوری و پیشرفت خانه را پیدا کرد؛ رگرسیون و اصلاح ثبت شد. [دستورها، خروجی و شکست‌های اولیه](docs/audits/evidence/weekly-planner-local-2026-10-18.json).

**UNVERIFIED/باز:** CI39170095124 روی0878623 هر سه job موفق؛ APK0.7.2+8/debug ساخته و از اتصال رسمی دریافت شد، ZIP با digest گیت‌هاب و manifest/hash محلی برابر است. [گواه فایل/امضا](docs/audits/evidence/weekly-planner-ci-apk-2026-10-18.json). مرورگر HTTPS واقعی با API/PostgreSQL محلی6/6موفق، بدون interception یا مبدأ خارجی؛ [گواه](docs/audits/evidence/weekly-planner-browser-2026-10-18.json). نصب و اعلان واقعی Android، Safari/ایران و امضای release اجرا نشده‌اند. سرور آنلاین و ورود خصوصی مستقل کودک آماده نیست. [ADR0016](docs/decisions/0016-initial-child-planner-delivery.md) دو مسیر مستقلِ روی گوشی یا انتظار برای آنلاین را آماده کرده و منتظر پاسخ مالک است؛ درخواست «ادامه» انتخاب سیاستی محسوب نشده است. URL یا حساب ساختگی جای اتصال گذاشته نشد. [پذیرش گوشی و محدودیت‌ها](docs/operations/WEEKLY_PLANNER_ANDROID.md). فاز استفادهٔ کودک تکمیل‌شده گزارش نمی‌شود.

## ادامهٔ بررسی PR31 و تصمیم دسترسی آموزشی — ۲۰۲۶-۱۰-۱۶

GitHubAPI،CIاجرای38906353812برایheadc067163راsuccessوartifactآزمایشیAndroidرا موجود نشان داد. ZIPاز اتصال رسمی دریافت شد؛ digestآن باGitHubبرابر وmanifestواقعی محلیPASSاست. این شواهدِbuild/integrityاست، نه نصب‌روی‌گوشی یا انتشار. [جزئیات تحویل](docs/ux/2026-10-16-pr31-ci-android-handoff.md).

برای مانع دسترسی نشست جدیدکودک، [ADR0015](docs/decisions/0015-managed-child-education-scope-options.md) با دو گزینه و قرارداد/معیارپذیرش آماده شد؛ **PROPOSED،منتظرتصمیم مالک**. اجازهٔ برنامه/مطالعه خصوصی،AI،زیرساخت،تولید،mergeیاdeployداده نشد. کدAPIوFlutterدراینPRاسناد تغییر نمی‌کند.

## Flutter — نخستین پیاده‌سازی طرح تأییدشده — ۲۰۲۶-۱۰-۱۶

مالک، طرح۱۲صفحه‌ای را تأیید کرد. در شاخهٔ مستقل `feat/flutter-mobile-navigation` بر PR30، خانهٔ جمع‌وجور RTL با شش منوی کودک/چهار منوی بزرگسال، صفحه‌های جدا و برگشت، استفاده از صفحه‌های API موجود و جزئیات همان تکلیف با ویرایش/تکمیل/بایگانی از PlanSync پیاده شد. نام از پروفایل؛ بدون آمار یا رکورد نمایشی. مجوزها و API تغییر نکردند.

**VERIFIED:** baseline212→226تستFlutterموفق؛14بررسی متمرکز شامل اصلاح سه یافتهٔ مستقل؛ analyzeبدون مشکل،format73فایل/0تغییر، ساخت releaseوب و منابع محلی؛4تستworker و بررسیCanvasKit/فونت بدوندامنهٔخارجی. مرورگرChromiumباTLSمعتبر و Node/PostgreSQL16کاملاًمحلی:6PASS؛ ایجاد تکلیف ازUI باSQL/APIمستقل، بازکردن مجدد، ویرایش، تایمر واقعی، تکمیل و بایگانی. [شواهد و محدودیت‌ها](docs/ux/2026-10-16-flutter-navigation-implementation.md).

**UNVERIFIED/ناقص:** گوشیAndroid/Safari،APKامضاشده، استقرار عمومی،SMS/ویدئوی واقعی،۲۵/۵ و پذیرش چندوالد. نشست managed-child جدید همچنان روی APIقدیمی403است؛ آزمون محلی باحساب legacyساختگی انجام شد. ظاهر تمام زیرصفحه‌ها هنوز هم‌سطح طرح نهایی نیست. این بسته تکمیل فاز۱ یا محصول آنلاین نیست؛ هیچ merge/deploy/DNS/schemaزنده انجام نشد. گام بعد بررسیPR و بستهٔ بعدیِ متناسب با مانع واقعی است.

## طرح موبایل — منتظر بررسی مالک — ۲۰۲۶-۱۰-۱۶

در پاسخ به بازخورد مالک، این بسته فقط تجربهٔ دیدنی/قابل کلیک را طراحی می‌کند؛ توسعهٔ هسته و تغییر محصول زنده انجام نشد. [بستهٔ۱۲صفحه‌ای](design-review/mobile-v1/README.md) شامل منوی اصلی، زیرصفحه‌ها، نمای والد و کودک،PNG/PDFقابل زوم وHTMLمستقل است. همه داده‌ها ساختگی‌اند؛ منتظر تأیید طراحی قبل از پیاده‌سازی درFlutter.

منبع، شناسهٔبوم/نسخه و خروجی‌ها درمخزن ذخیره شدند تا ادامهٔکار به چت وابسته نباشد. تأیید UI برابر با تأیید auth/permission، محتوای آموزشی،SMS یا انتشار نیست. app.lifeguide.ir،Backend،DB وDNS تغییرنکرده‌اند. شرح وreceiptدر بستهٔطرح موجود است.

## فاز۱ — هویت کودکِ صرفاً ساختگی، بدون انتشار — ۲۰۲۶-۱۰-۱۶

سه بخش وابسته بر PR24 آماده شد: [schema در PR27](https://github.com/davoodmehraban89/LifeMate/pull/27)، [مرز نشست در PR28](https://github.com/davoodmehraban89/LifeMate/pull/28) و جریان `feat/child-device-safety` روی آن‌ها. ساخت کودک با DOB اجباری و رضایتِ صریحاً غیرحقوقیِ sandbox، سرپرست دوم با دعوت سازنده/پذیرش گیرنده، بازیابی با ابطال نشست‌های قبلی، scope محدود در DB و refresh و API دیدپذیری پیاده شد. Production حتی با flag فعال503؛ داده واقعی مجاز نیست.

**VERIFIED محلی:** npm ci؛23migration و تکرار/import تکراری؛ چهار SQL assertion موفق؛ Backend **297pass/0fail/0skip**، runtime30 و regression96 موفق؛ backup/restore مستقل و کنترل مجوز پس از restore؛ syntax82، audit0 و بررسی diff. [گزارش، شکست اولیه و حدود شواهد](docs/audits/2026-10-16-child-identity-sandbox.md).

۲۱ migration قبلی و bundleهای تاریخی Supabase حفظ شدند؛ live QA تغییر نکرد. هیچ merge/deploy/DNS/SMS یا داده زنده‌ای تغییر نکرد. UI/QR، Android/Safari، آنلاین عمومی، رضایت حقوقی و مسیر آموزشی مجاز جدید هنوز **UNVERIFIED/تکمیل‌نشده** هستند. مسیرهای خصوصی قدیمی برای نشست جدید بسته‌اند؛ کامل‌شدن Backend این بسته، آماده‌بودن نرم‌افزار خانواده نیست. **فاز۱ کامل نیست و فاز۲ شروع نشده است.** Feature1، نام LifeGuide و شناسه‌های فنی موجود حفظ شدند.

## فاز۱ — اصلاح هویت در PR وابسته؛ بدون انتشار

مالک پس از گزارش فاز۰ شروع فاز۱ را تأیید کرد. شاخه `fix/auth-abuse-expiry-safety` از PR14 در `5da6c4290e422162c13c3fe5260345770dde7ffa` منشعب است؛ به main یا سرویس زنده منتقل نشده است. محدودیت IP مشترک PostgreSQL، بررسی تازه انقضا پس از قفل و gate تأیید ارسال SMS پیاده شد. **VERIFIED محلی:** `npm test -- --test-concurrency=1` →271pass/0fail/0skip؛ migration و import تکراری، چهار SQL matrix و syntax موفق. [گزارش و محدودیت‌ها](docs/audits/2026-10-15-phase1-auth-hardening.md).

Migration0023 فقط محلی آزموده شد؛۲۰ فایل اصلی و۳bundle تاریخی تغییر نکرده‌اند و Supabase زنده همان baseline20 است. manifest جدید generator شامل21فایل، گواه اعمال روی QA نیست. AI/guardian/cycle policy، سرور آنلاین، دستگاه/Safari، SMS واقعی و امضای release هنوز تأیید/تکمیل نشده‌اند؛ **فاز۱ کامل نیست**. پاکسازی مخزن و اسناد گزینه‌های سیاستی در PRهای مستقل آماده می‌شوند. هیچ merge،deploy،DNS،داده یا schema زنده تغییر نکرده و این PR اجازه آن‌ها نیست.

## Supabase LifeGuide-QA full private schema — 2026-10-15 (HISTORICAL CHECKPOINT)

**20/20 original PostgreSQL migrations copied to the isolated QA database, SQL family/privacy assertions PASS, client-access remains DENY ALL.** This is a **database integration milestone**, not a publicly operational LifeGuide Android/PWA.

- Supabase Free `DM Studio` → `LifeGuide-QA` project `iqkrwxeprxvdiubdfcrb` Frankfurt PostgreSQL17.11; $0/month project creation quote. Existing `Finora ERP – Production` not touched and remains `ACTIVE_HEALTHY`.
- Two checked, atomic, provider-applied migrations: `20261014215436_lifeguide_qa_app_schema_0001_0010`, `20261014215539_lifeguide_qa_app_schema_0011_0020`. Exact SQL committed in `supabase/migrations/202610150001_...` and `202610150002_...`; 20 filename/SHA256 source hashes persist in `lifeguide_qa.schema_migration`. No original migration SQL rewritten in the source tree.
- Real database read-after-write verification: **59 private tables**, **19 functions**, **20 migration entries**, **0 public app tables**, **0 user/family/task/session rows after rollback**. All tables RLS ENABLED+FORCED, and `anon`, `authenticated`, `service_role` lack QA schema USAGE. Exactly five fixed school function search paths were redirected from `public` to QA. Supabase security advisor emits only INFO `rls_enabled_no_policy` for intentional deny-all; this does **not** mean clients can access the tables.
- Real SQL family fixture, transaction ROLLBACK: two authorized parents see child academic/shared-task state, unrelated outsider denied, private child task denied to parent, father access revoked while mother retained, study session **4s preserved**. Verified no fixture persisted. This is DB function evaluation, not an HTTP JWT test.
- Owner's Kavenegar `lifeguideotp` OTP template still **under review**; adapter source/mock tests available on PR14, no key configured, no paid SMS ever sent.
- Backend Node/Express/native Argon2/custom sessions **not yet hosted** on the QA project; Supabase is managed PG not the long-running existing app server. No real PWA or Android app pointed at Supabase, no production domain/DNS/Railway/Finora changes. No-VPN Iran, device tests and live SMS UNVERIFIED.
- **Authoritative evidence:** [Full schema / rollback family test](docs/audits/2026-10-15-supabase-full-schema-family-acceptance.md); [initial provider bootstrap](docs/audits/2026-10-15-supabase-qa-provisioning.md); [Kavenegar setup](docs/operations/KAVENEGAR_SMS_SETUP.md); [Draft PR14](https://github.com/davoodmehraban89/LifeMate/pull/14).
- **NEXT:** determine no-card free compatible host for existing Express/Argon2, implement server-side least-privileged access with real HTTPS negative-role API tests, then connect QA Android/PWA. Keep production rollout gated. PostgreSQL private QA schema has no client policies by design.

Older checkpoints below are retained as historical evidence; this latest verified entry supersedes outdated statements about no application migrations, no table structures or unsolved Supabase organization access.

## Kavenegar template owner verification — 2026-10-15

- Owner screenshot from Kavenegar console shows SMS VerifyLookup template **`lifeguideotp` created** with status **در حال بررسی / under review**, NOT approved and NOT sent.
- Visible message preview contains literal `%token`, LifeGuide brand, 5-minute validity and "do not share" warning.
- Console lists **نام اپلیکیشن = `lifeguideotp`**, which duplicates the template name instead of product name LifeGuide. Prefer correcting the display name to `LifeGuide` if provider supports editing; do not delete/recreate the pending template without need.
- No actual Kavenegar API key, OTP, phone number, or SMS delivery proof is available. No paid SMS sent. Keep live provider configuration disabled until approval, secure secret placement, and explicit owner consent for a paid test.
- Latest GitHub CI for QA branch `c79939351b88` run [38640974777](https://github.com/davoodmehraban89/LifeMate/actions/runs/38640974777) was still **in progress** at check; do not mark adapter CI passed.

## Kavenegar API adapter — 2026-10-15 (QA CODE, NOT LIVE)

- Provider **Kavenegar**, verified by owner screenshots of `console.kavenegar.com`; screenshot shows masked API key and a draft new validation template. The key was **not** obtained or stored.
- Suggested `lifeguideotp` validation pattern with literal `%token`, product name LifeGuide, SMS mobile-app use, fallback resend disabled. Provider approval **UNVERIFIED**.
- Backend opt-in `SMS_PROVIDER=kavenegar` implemented on isolated QA branch using `backend/src/kavenegar_sms.js`, minimal factory change in `backend/src/auth_delivery.js`, blank secret variable `KAVENEGAR_API_KEY` in `.env.example`, and mock-only tests in `backend/tests/kavenegar_sms.test.js`. Existing disabled/webhook provider paths kept.
- Implementation confines API key to server env, uses fixed HTTPS Kavenegar VerifyLookup host, no logged provider response/secret/OTP, and no automatic retry of non-idempotent SMS sends. It does **not** use account credentials in Supabase, and the real Node/Express backend still has no approved online hosting.
- New draft [PR14](https://github.com/davoodmehraban89/LifeMate/pull/14) opened to run CI; test results **PENDING**, no merge or live deployment.
- Owner's prepaid Kavenegar balance is finite. **No paid real SMS** sent/approved yet; requesting template name/approval status, never API key. The public `app.lifeguide.ir` is not connected to LifeGuide-QA.
- Guide: [KAVENEGAR_SMS_SETUP.md](docs/operations/KAVENEGAR_SMS_SETUP.md). Provider official `VerifyLookup` documented in the official Kavenegar Node SDK.

## Public domain and owner SMS panel — 2026-10-15 (READ-ONLY CHECK)

- **Official product name: LifeGuide** (not آرام). Repository path `davoodmehraban89/LifeMate` and package/protocol identifiers remain unchanged unless separately approved.
- User reports an external **SMS provider panel is set up** for registration/login. **Provider name, API documentation, SMS template/pattern ID, permitted sender, delivery capability and available provider credentials are not yet verified or integrated.** Never request any API secrets in a chat/Git repository or issue a real OTP without explicit operational consent.
- Existing v0.7.1 Node/Express backend includes `SmsProvider` and a generic HTTPS `webhook` adapter in `backend/src/auth_delivery.js`, `/v1/auth/phone/request-otp` and `/v1/auth/phone/verify-otp` in `backend/src/auth_router.js`, plus phone registration and OTP recovery. `.env.example` defaults to `SMS_PROVIDER=disabled`. No deployed provider integration confirmed.
- The existing LifeGuide-QA Supabase project currently contains only a private synthetic `lifeguide_qa.setup_probe` table and JWT-protected health Edge Function; **it is not the complete LifeGuide API/DB**. No public `app.lifeguide.ir` origin/runtime-config/DNS change was performed by this workstream.
- Attempts on this date to fetch `https://app.lifeguide.ir/`, `/config.json`, `/api/health`, `/ready` through public fetch tools produced inaccessible or empty content, so **live domain/API behavior is UNVERIFIED**, not established as either healthy or down. Historical probe of 2026-10-12 saw HTML fallback for API/config paths; this is not a current observation.
- Next: obtain provider **name and public API documentation** from owner (never secret token); design and test a safe adapter in an isolated branch, preserve account-level OTP rate limits, 5-minute expiry, guardian privacy, and secrets confined to server configuration. Separately deploy/verify an authenticated QA API against Supabase PostgreSQL before switching domain/Android/PWA. Any public/domain change and real SMS sending need independent approval.

## Supabase QA verified checkpoint — 2026-10-15 (CURRENT)

**LifeGuide-QA is provisioned on Supabase Free but the LifeGuide mobile/PWA app is NOT deployed or connected.**

- Supabase organization: **DM Studio**, id `unrlckipyubhegrpqgei`, Free. User approved it as the shared administration umbrella for multiple *isolated* projects. Exact `get_cost(project)`: **$0/month**; confirmation performed. Provider accepted the new project.
- Separate project: **LifeGuide-QA**, id `iqkrwxeprxvdiubdfcrb`, Frankfurt (`eu-central-1`), PostgreSQL17.11, `ACTIVE_HEALTHY`. Other observed project `Finora ERP – Production` (id `hcsixhqbyuhpshfwqpjx`) remained `ACTIVE_HEALTHY` and was **not changed**.
- Only a PRIVATE QA schema `lifeguide_qa` and `setup_probe` table were created in the new project via additive migration `20261014210221_lifeguide_qa_isolated_connectivity_baseline`. One `synthetic_backend_handshake` write/read passed. Zero application tables under `public`. Privileges for `anon` and `authenticated` explicitly absent; RLS enabled and forced. Security advisor issued INFO `rls_enabled_no_policy`, expected for a deliberately closed table.
- Synthetic-only JWT-gated Supabase Edge Function `lifeguide-qa-health` v1 deployed `ACTIVE` with `verify_jwt=true`; an external unauthenticated GET received **HTTP 401**. Authenticated success NOT VERIFIED. This endpoint is NOT the current Node/Express backend.
- PostgreSQL current setup proof is **not** the application's 20 migrations or guardian permissions. No child/parent accounts created, no existing application data, production domain, Railway/Neon/other Supabase project, `main` or stacked PRs changed. Real Android and iOS Safari, Iran no-VPN connectivity and PWA are UNVERIFIED.
- Evidence: [Provisioning audit](docs/audits/2026-10-15-supabase-qa-provisioning.md), [Supabase migration](supabase/migrations/20261014210221_lifeguide_qa_isolated_connectivity_baseline.sql), [Edge source](supabase/functions/lifeguide-qa-health/index.ts), [QA runbook](docs/operations/SUPABASE_QA_BOOTSTRAP.md).
- **Next:** compatibility assessment of Express/Argon2/JWT session model/managed Supabase PG grants before any real application SQL or Auth adaptation. Resolve API hosting and privacy parity, then synthetic child→authorized mother/father task/study sync and physical devices. Production hosting ADR0009 remains the baseline.

The Supabase preparation/identity notes retained below are **historical snapshots** from earlier connector states. When they contradict this checkpoint, **this checkpoint is authoritative**. The unchanged 0.7.1 engineering checkpoint below is still valid for that earlier source/CI.

## Supabase historical preparation — 2026-10-15 (SUPERSEDED)

Owner approved evaluating a **separate Free Supabase organization `LifeGuide`** and synthetic-data QA project. This is **not** a new public deployment, a database migration, or a replacement for production hosting ADR 0009.

- Working branch: `infra/lifeguide-supabase-qa`, forked from the 0.7.1 test head `fix/study-duration-display`. No Flutter/Backend runtime code changed for this trial.
- Current connected Supabase account: existing unrelated Free organization `Finora` and two unrelated projects `Finora` (INACTIVE) / `EasyFactor` (ACTIVE_HEALTHY). Do **not** modify/reuse them.
- The connected Supabase tool cannot create organizations; owner must first create **LifeGuide / Free** manually in their dashboard. No new LifeGuide organization or project has been verified.
- After the independent organization appears, verify **$0** exact project cost through `get_cost` and available account-wide free-project quota before creating `LifeGuide-QA`. The two free active projects limit spans organizations; an INACTIVE label alone is not quota evidence.
- Node/Express/Argon2 and Supabase Edge Functions are not drop-in interchangeable; review DB roles/security and design minimal auth-safe prototype before deploying. No secrets or real child records in tests.
- Gate status: organization **BLOCKED on owner action**; cost check, new DB, deployment, Android/Safari/without-VPN Iran acceptance **NOT RUN**.
- Technical runbook: [Supabase QA bootstrap](docs/operations/SUPABASE_QA_BOOTSTRAP.md); [QA decision](docs/decisions/0011-supabase-free-qa-trial.md). Original 0.7.1 evidence below is unchanged.

## Supabase historical naming decision — 2026-10-15 (SUPERSEDED)

- Owner **approved the general-purpose organization display name `DM Studio`** for managing several software projects; `LifeGuide` remains the product name.
- **Organization rename PENDING manual dashboard action**: connected Supabase tools have no organization-update operation. Last verified actual name is `LifeGuide`; ID `kpbskbvjspggwzmgqyze` was formerly named `Finora`. Do not claim a second independent organization exists.
- Proposed project is still `LifeGuide-QA`, in the existing organization after its display name is updated. Independent **projects** rather than independent organizations are the isolation boundary.
- Supabase reported project cost `$0/month` for current Free org; do not create any project before verifying current Free active-project quota, original Finora/EasyFactor resources and explicit owner confirmation of exact charge. No new Supabase project or DB has been provisioned.

## Supabase historical organization visibility issue — 2026-10-15 (RESOLVED)

- Read-only Supabase connector reports `LifeGuide` Free and `get_cost(project)` **$0/month**.
- **Identity mismatch blocks provisioning:** currently listed LifeGuide ID `kpbskbvjspggwzmgqyze` is precisely the ID previously seen as `Finora`. Both separate organizations are not visible to this connection. `list_projects` returns empty and direct access to previously listed unrelated projects returns permission denied; no assertion of deletion, reassignment or independent organization creation is supported.
- Await owner's confirmation that **LifeGuide and Finora are two separate dashboard organizations**, and the new LifeGuide non-secret ID. Until then do **not** call project cost confirmation or create `LifeGuide-QA`.
- No Supabase project, DB, schema, migration, credentials, app deploy, DNS change or real-data import executed. Earlier 0.7.1 branch and CI evidence stay unchanged.

Updated: 2026-10-12. Backend **0.7.1**; Flutter **0.7.1+7**. Branch **fix/study-duration-display**, stacked on **feat/learning-content-operations** at `e4cbc8bd37ee8d1c580a3b8ac33c3abfe6e269a3`. Main remains `abdc9d9d032bc6746c8390b902a2e52d82991530`. Repository remains `davoodmehraban89/LifeMate`; Android identity remains `ir.lifeguide.app`.

**نامزد آزمون با داده ساختگی؛ نسخه کامل عملیاتی یا انتشار عمومی نیست.** [ممیزی فاصله تا تکمیل](docs/audits/2026-10-11-completion-gap-analysis.md) مبنای این بسته است. جزئیات و خروجی‌های تاریخی0.6.0 در [checkpoint قبلی](docs/history/2026-10-11-project-state-0.6.0.md) حفظ شده‌اند؛ آن CI موفق، اجرای تازه این منبع نیست. [PR پیش‌نویس۱۲](https://github.com/davoodmehraban89/LifeMate/pull/12) روی۱۱ باز است؛و [PR13](https://github.com/davoodmehraban89/LifeMate/pull/13) اصلاح زمان روی۱۲ است؛۱۰،۱۱،۱۲ و۱۳ ادغام نشده‌اند.

## ادامه توسعه: دقت زمان، کلاینت0.7.1+7

source `d0b3446d736b67fdb4e0218282ad15f0e74fdb55`:4ثانیه اکنون4ثانیه و90ثانیه1دقیقه و30ثانیه در تمام ردیف‌های گزارش مجاز والد نشان داده می‌شود. UI باریکRTL320 پس از رفع overflow آزموده شد. Flutter212/212 و analyzerclean؛ worker4، وبrelease53.6ثانیه و gatewayprebuilt ساخته شد. PWA واقعی HTTPS از همان profile قبلی با23درخواست بدون خطای آن run،4ثانیه را نمایش داد و root SQL مستقل4ثانیه/دوinterval وtaskv6/completed را تأیید کرد. [شواهد اصلاح](docs/audits/2026-10-12-study-duration-verification.md). [CI38223988983](https://github.com/davoodmehraban89/LifeMate/actions/runs/38223988983) هر سه job SUCCESS؛ Backend245، role9+96/restore و Flutter212، وب و APK0.7.1/code7 ساخته و root دانلود/digest/manifest را بررسی کرد. [Receipt](docs/audits/evidence/ci-study-duration-2026-10-12.json)، [APK تازه](https://github.com/davoodmehraban89/LifeMate/actions/runs/38223988983/artifacts/11735469546). امضای debug تازه با قبلی متفاوت است؛ نصب/ارتقا/owner-release همچنان UNVERIFIED. مجوز و داده/API تغییر نکردند.

## بسته قبلی0.7.1 / کلاینت0.7.0+6

- عملیات بازخورد آموزشی: دسترسی صریح و قابل لغو مستقل از مدیر خانواده؛ فقط خلاصه‌ای که مالک با رضایت انتخاب کرده، triage نسخه‌دار و تهیه برنامه توسعه بدون متن خصوصی یا مشخصات مالک. پس‌گرفتن رضایت، خواندن/brief بعدی را متوقف می‌کند. ارسال خودکار به AI، پیام‌رسان یا agent و انتشار خودکار وجود ندارد.
- اهداف خصوصی: CRUD/بایگانی روی API/PostgreSQL، UUID پایدار، کنترل نسخه، صف بادوام و رسید معتبر؛ بازتاب یادگیری و تاریخچه از API خصوصی موجود. درخواست‌های legacy بدون idempotency پس از پاسخ نامعلوم فقط دوباره خوانده می‌شوند، نه خودکار نوشته.
- خانواده: مدیریت UI روی API واقعی، انتقال اتمی مدیریت، تغییر نقش و لغو دعوت با مجوز فعلی؛ لغو نقش/عضویت، اشتراک و سرپرستی ناسازگار را قطع می‌کند. نوع پروفایل مجوز نیست. سن ثبت‌شده، احراز هویت رسمی سن محسوب نمی‌شود.
- مدرسه: مدیریت زمینه/سال/نیم‌سال نسخه‌دار و بایگانی بدون حذف تکلیف/تاریخ؛ درس و کلاس از API موجود. تاریخ‌ها صریح انتخاب می‌شوند؛ راه‌اندازی ثابت و ساخت خودکار سال نمونه حذف شده است.
- مرور و گزارش: تاریخچه آزمون و مرور فقط برای مالک؛ گزارش مجاز والد با شمارنده‌های بازه مستقل از کل سابقه، زمان تهران، نمره مدرسه جدا از کوییز خصوصی و رفع fingerprint ناپایدار. خطای دریافت، داده قبلی را تازه معرفی نمی‌کند. زمان تایمر یا خوداظهاری اثبات مطالعه نیست.
- شروع آفلاین PWA: service worker فقط صفحه عمومی قطع اتصال ارائه می‌کند؛ API/config/auth یا داده خصوصی را به‌جای پاسخ شبکه برنمی‌گرداند. دسترسی آفلاین به برنامه احراز هویت‌شده پس از cold-start، quota/eviction و Safari هنوز UNVERIFIED هستند.
- ابزار محلی عملیات انتشار برای fixture ساختگی با credential جدا، dry-run، هش/نسخه/review gate و journal شناسه/هش؛ API حق انتشار ندارد. این ابزار مجوز انتشار درس واقعی یا تأیید بازبینی ویدیو نیست.

## آموزش واقعی و دامنه‌ها

Feature 1 ایران و Backend/خانواده/planner/offline queue/آزمون‌های مجوز main حفظ شده‌اند؛ LocalOnlyApi وارد نسخه آنلاین نشده است. موجودی تحقیق:217 کتاب،1373 بخش،1348 نامزد ویدیو؛ **ویدیوی واقعی با بازبینی کامل و منتشرشده:0؛ بانک سؤال واقعی منتشرشده:0**. نمونه اصیل ریاضی اول ابتدایی برای چاپ1405–1406 و چند کتاب متوسطه بررسی محدود مستند دارند؛ [گزارش و حدود بررسی](docs/research/2026-10-11-math-pilot-review.md). فایل draft ریاضی reviewRecord:null دارد. مشاهده کامل فیلم، حقوق نمایش، تطبیق همه صفحات، بازبینی متخصص و ارزیابی اثر یادگیری هنوز تکمیل نشده‌اند. metadata و امتیاز یک کوییز تضمین فهم یا یک سال مدرسه نیستند.

APK نصب تازه آدرس HTTPS **API فعال مشترک** می‌خواهد؛ default عمومی تأییدشده وجود ندارد. طبق [بررسی اتصال11اکتبر](docs/audits/2026-10-11-apk-connection.md)، app.lifeguide.ir هنوز HTML قدیمی ارائه می‌کرد و مسیرهای config/health/ready بررسی‌شده API JSON سازگار نبودند. بررسی خواندنی تازه12اکتبر فقط `/config.json` و `/api/health` راHTTP200/HTMLغیرJSON نشان داد؛ [receipt](docs/audits/evidence/public-api-paths-2026-10-12.json). این بررسی DNS یا تمام مسیرها نیست. هیچ DNS یا سرویس زنده تغییر نکرده است.

## اجرای بسته جاری

نسخه پایه0.7.0 واقعاً آزموده و ساخته شد: Node22/PG16 **244/244**؛ Flutter **200/200**، formatter69فایل/بدون تغییر و analyzer clean؛ syntax67فایل و npm audit صفر vulnerability؛20 migration checksumدار و repeat/import repeat؛ چهار ماتریسSQL؛ runtime family9/9 و learning/family/school/report96/96؛58 منعSQL هم در source و هم restore. backup با credential read-only و restore با migrator مستقل، تاریخچه و session600ثانیه را حفظ کردند.

release web محلی56.8ثانیه ساخته شد؛ fonts/CanvasKit محلی، تست compiled14request/zeroexternal، guards8+8، Chrome3/3، حفظ صف پس از expiry، checker/provenance و Windows-style checkout/tamper rejection موفق شدند. API استاندارد Dockerfile و gateway prebuilt واقعاً ساخته شدند؛ Compose با role محدود سالم است،20/20checksum و صفر محتوای واقعی published مستقلSQL تأیید شد. HTTPS round-trip7مرحله موفق شد. مرورگر واقعی HTTPS بدون interception/TLS-bypass **14/14**،90درخواست محلی و صفرخطا گذراند: ثبت/بازگشایی، AXstatus، feedback/withdrawal، آفلاین با حفظ exact bytes و reconnect یک mutation بدون duplicate. [Receipt](docs/audits/evidence/content-operations-browser-2026-10-12.json). تصویر اول و بازگشایی SHA یکسان دارند؛ root تصویر درس را بررسی کرد. در تست‌یار، نام AX محاسبه‌شده Chromium فاصله‌ها را normalize می‌کند؛ مقایسه صرف newline نادرست اصلاح شد، وضعیت و timestamp همچنان دقیق بررسی می‌شوند.

[CI بسته قبلی38201011644](https://github.com/davoodmehraban89/LifeMate/actions/runs/38201011644) روی source `0831ee6ba81a4811f819e8d8dbfe3f7b24a566ef`: هر سه job SUCCESS؛ Node245/245، Flutter200/200، syntax68 و audit0، role9+96 و restore موفق. [Receipt و خطوط خروجی](docs/audits/evidence/ci-content-operations-final-2026-10-12.json). root اجرای محلی0.7.1 را نیز با245/245 و regression7/7 مشاهده کرد. [گزارش کامل پذیرش A–H و شکست‌ها](docs/audits/2026-10-12-content-operations-verification.md).

APK واقعی **0.7.0/code6/ir.lifeguide.app** ساخته، manifest و debug-v2signature روی runner بررسی شد؛ root ZIP و APK را دانلود و digest/manifest مستقل تأیید کرد. [APK نهایی](https://github.com/davoodmehraban89/LifeMate/actions/runs/38201011644/artifacts/11725931941)، [وب](https://github.com/davoodmehraban89/LifeMate/actions/runs/38201011644/artifacts/11725840928). APK168960414bytes، SHA `b9b8599de796986cf2800ce24782ee85bc87a7d97889d2d194465f0ad4f07915`. debugcertificate با قبلی فرق دارد؛ نصب/ارتقا UNVERIFIED و حذف داده برای حل تفاوت امضا مجاز نیست. خروجی release امضاشده مالک هنوز ساخته نشده است.

آزمون خانواده سه‌حسابی HTTPS واقعی: تکلیف ریاضی → مادر در PWA → تایمر با pause/resume → گزارش → تکمیل → پدر جدا → بازگشایی نشست‌ها، پنج اجرای مرورگر117درخواست بدون خطای آن runهای موفق. اقدام فرزند از API بود، نه Android. SQL مستقل taskv6/completed/1800seconds برنامه و session4seconds/دوinterval را تأیید کرد؛ UI کلاینت قبلی زیر یک دقیقه را0 دقیقه نشان داد؛ در بسته جدید اصلاح شد و receipt قبلی تاریخی حفظ است. [Receipt](docs/audits/evidence/contentops-family-real-https-2026-10-12.json).

تست والد نقص429 هنگام reopen را آشکار کرد. اصلاح0.7.1 فقط GET دقیق capabilities و POST دقیق refresh/logout را در budgetهای محدود جدا نگه می‌دارد؛ ورود/بازیابی/ارسال همچنان سقف حساس10/600 دارند. 30درخواست HTTPS واقعی روی API role محدود و سه حساب موفق؛ task و report هر دو والد پس از تعویض image محفوظ بود. [Receipt](docs/audits/evidence/contentops-nat-https-2026-10-12.json). دو probe اضافی والد ERR_ABORTED داشتند؛ دو retry بدون تغییر/ورود تازه و probe ابزارشده بعدی موفق بودند. علت لغوهای قبلی UNVERIFIED و در گزارش حفظ است؛ ادعای بی‌خطایی همه probeها وجود ندارد.

## محدودیت‌ها و گیت‌های باز

- Android واقعی سه‌دستگاه، نصب/ارتقا با داده معلق؛ iPhone/iPad Safari و Add to Home Screen، لمس و screen reader: UNVERIFIED.
- Windows/LAN/mkcert مالک، شبکه ایران بدون VPN، انتخاب میزبان/پرداخت/KYC، ایمیل/پیامک واقعی و push پس‌زمینه: UNVERIFIED.
- امضای release با keystore مالک و انتشار LifeGuide.apk: UNVERIFIED. خروجی debug انتشار رسمی نیست؛ برای تفاوت امضا، داده ارسال‌نشده را حذف نکنید.
- حساب/contact/closure و سیاست نگهداری، آزمون تشریحی/rubric، سنجش تشخیصی و برنامه یادگیری تطبیقی، پوشش کامل کتاب‌های نظری/فنی‌وحرفه‌ای و آموزش خانواده هنوز کامل نیستند.
- AI/voice خارجی، سلامت/چرخه و مشاوره حساس کودک غیرفعال‌اند. رضایت/حقوق/نگهداری داخلی و safeguarding باید جداگانه طراحی و بررسی تخصصی شوند؛ هیچ استخراج گفت‌وگوی خصوصی یا ارسال خودکار برای والد/مدیر انجام نمی‌شود.
- Production/live deploy، DNS، انتقال داده واقعی، merge نهایی، انتشار عمومی، ثبت‌نام یا خرید مجاز نیستند و اجرا نشده‌اند. درخواست ادامه توسعه جای مجوز صریح آن اقدامات را نمی‌گیرد.

## راه تحویل و اقدام مالک

[تحویل0.7.1 و مراحل دقیق](docs/operations/HANDOVER_0.7.1.md)، [Stage0 رایگان](docs/operations/STAGE0.md)، [نقش‌های مستقل دیتابیس](docs/operations/DATABASE_ROLES.md)، [میزبانی](docs/decisions/0009-provider-neutral-hosting.md)، [نام‌گذاری](docs/decisions/0010-lifeguide-naming.md)، [مهاجرت داخلی و rollback](docs/operations/DOMESTIC_MIGRATION.md). مالک پس از دسترسی به PC/LAN آزمون‌های واقعی را اجرا می‌کند؛ تا آن زمان اقدام فوری لازم نیست. انتخاب سرور، DNS، SMS/email provider و key امضا خارج چت و پیش از هر تغییر زنده انجام می‌شود.
