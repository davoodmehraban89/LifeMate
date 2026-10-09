# Stage 0 Isolation Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement task-by-task. Steps use checkbox (`- [x]`) syntax.

**Goal:** بستن دو نقص نقش DB بیش‌ازحدمجاز و اجرای هم‌زمان نشست/صف وب، با آزمون واقعی و حفظ هسته آنلاین.

**Architecture:** Compose کاربر bootstrap، migrator، runtime و backup مستقل دارد. Bootstrap وب قبل از Flutter فقط یک Web Lock می‌گیرد؛ instance دیگر بدون دسترسی به نشست/cache متوقف می‌شود.

**Tech Stack:** Node22، PostgreSQL16، Flutter3.47.6، Dart3.13.5، Chromium/Playwright1.62.1، Compose.

**Spec:** [طراحی](../specs/2026-10-09-stage0-isolation-hardening-design.md).

## Global Constraints

- فقط محیط محلی و داده ساختگی؛ بدون live/DNS/real migration/merge/signup/payment.
- LifeGuide و `ir.lifeguide.app`؛ repo/schema/JWT بدون تغییر.
- secretها در env خصوصی؛ TLS/proxy/CA معمول حفظ شوند، credential چاپ نشود.
- از main و migrations/auth/planner سالم استفاده شود؛ SDK image سنگین Docker تکرار نشود.
- یک مسئول اصلی برای هر زیرکار؛ root مالک CI/اسناد/ادغام است. اجرای موازی موجود مجاز و شروع شده است.

## Review Focus

1. DB موجود با owner غیرمنتظره: provisioning باید پیش از تغییر fail کند؛ تبدیل فقط مسیر explicit با backup/expected owner.
2. جدول/تابع جدید پس از migration: runtime فقط مجوز لازم، ledger بدون write، backup بدون mutation.
3. دو startup هم‌زمان: فقط یک tab وارد engine/auth/storage شود؛ دیگری هیچ داده‌ای پاک نکند.
4. close/crash/background/BFcache: آزادسازی فقط teardown، مالکیت منقضی در pageshow قابل استفاده نباشد.
5. unsupported Locks و نسخه قدیمی باز: fail-closed/retry واضح؛ operator همه instanceهای قدیمی را یک‌بار ببندد.

## Task 1 — نقش‌های PostgreSQL، owner deployment_stage0

**Files:** docker-compose*.yml، .env.example، backend/scripts/provision-db-roles.js، db-role-policy.js، test-db-roles.js، scripts/test-db-roles.sh و deploy/backup/restore؛ ops runbook.

**Interfaces:** runtime env از `API_DB_USER/PASSWORD`؛ migration از `MIGRATOR_DB_USER/PASSWORD`؛ backup از `BACKUP_DB_USER/PASSWORD`. bootstrap credential فقط provision/operator. `node scripts/test-db-roles.js --synthetic-only` تست fresh/runtime را با PGHOST/PGUSER/... صریح اجرا و source_db/target_db در ROLE_TEST_STATE_FILE ثبت می‌کند؛ `--verify-restored` و `--cleanup` فقط همین DBهای tagشده را مصرف می‌کنند. CI pg_dump backup/pg_restore migrator با client16 بین این مراحل اجرا می‌کند.

- [x] RED: ثبت privilege/ownership واقعی unsafe موجود و آزمون انتظار منع runtime DDL/role/ledger write.
- [x] GREEN: provisioning/grants تکرارپذیر، نقش‌های مستقل، ترتیب compose/deploy؛ عدم adoption خاموش.
- [x] PG واقعی: fresh/repeat۱۲ migrations، runtime API CRUD/auth/permission، forbidden operations، migration بعدی/grants، readonly backup و migrator restore.
- [x] بازبینی تبدیل DB موجود/owner mismatch، secretهای env و runbook؛ گزارش دقیق و freeze فایل‌ها.
- [x] root تغییر محدود را commit می‌کند؛ source اصلی بدون مجوز زنده تغییر نمی‌کند.

## Task 2 — یک instance وب، owner review_persistence

**Files:** apps/lifemate/web/flutter_bootstrap.js، guard/session/HTTP وب در lib، آزمون focused مرورگر و guard؛ native فقط از رابط موجود استفاده می‌کند.

**Interfaces:** Web Lock ثابت `lifeguide.active-instance.v1`، getter مالکیت bootstrap خواندنی، guard رد دسترسی پیش از startup/پس از pagehide؛ retry در تب blocked پس از آزادشدن lock.

- [x] RED: actual two-tab startup وارد هر دو engine/auth/storage می‌شود؛ race و unsupported Locks سنجیده شوند.
- [x] GREEN: lock قبل loader، held document callback، Persian static failure/retry، guard session/cache/HTTP، teardown/pageshow handling.
- [x] browser واقعی: هم‌زمانی، close/crash/retry، background، profile/origin مستقل، unsupported؛ log بدون credential.
- [x] RED→GREEN حفظ صف پس از انقضای ناخواسته: `_expireSession` جدا از logout صریح؛ `onScopeQuarantined` به `OfflineStore.invalidateNamespace` بدون حذف دیسک وصل شود؛ store قدیمی/حساب دیگر ممنوع، ورود همان حساب/endpoint بازیابی و replay بدون تکرار.
- [x] freeze source و اطلاع به flutter_toolchain؛ شواهد fixture با compiled app اشتباه نشوند.
- [x] root commit محدود می‌سازد و دستور node browser acceptance را به CI می‌افزاید.

## Task 3 — ادغام/تحویل، owner root؛ ابزار Flutter با flutter_toolchain

- [x] تأیید rerun واقعی CI قبلی و ثبت attempt/job/artifact، بدون ادعای source جدید.
- [x] SDK دقیق پایدار؛ analyze/test/build جدید فقط پس از freeze، self-host و compiled browser gate و provenance.
- [x] backend/role tests و backup/restore مرتبط؛ CI کامل روی source جدید و debug artifact، release رسمی همچنان UNVERIFIED.
- [x] بررسی مستقل changed scope و رفع یافته‌های مهم؛ README/CHANGELOG/STATE/گزارش‌ها/PR هماهنگ شوند.
- [x] تحویل SHA/branch/PR، output واقعی، manual steps و گیت‌های فیزیکی/زنده/حقوقی باز؛ هیچ merge/deploy خودکار.
