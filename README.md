# LifeMate

**Personal, Family & Learning Companion**

LifeMate is a cross-platform personal and family companion designed to grow with its users across life stages. The first product focus is a teen-and-family experience combining planning, school organization, learning support, family coordination, and safe AI-assisted wellbeing guidance.

## Product principles

- One identity, multiple life contexts: student, personal, family, and later work/university.
- One Family Workspace with independent member accounts and role-based access.
- Parents can access authorized planning, academic reports, and meaningful support signals without turning the product into continuous surveillance.
- AI assists with planning, learning, reflection, and parent guidance; it does not impersonate a clinician or replace human professional care.
- Android installable app + high-quality iPhone/iPad PWA + responsive web, sharing one backend and data model.
- Persian/RTL quality and an attractive, age-appropriate visual experience are first-class requirements.
- Security, privacy, safety, and auditability are architectural requirements, not post-release additions.

## Current phase

محصول در مرحله پیاده‌سازی و ممیزی است و آماده انتشار کامل نیست. وضعیت معتبر، محدودیت‌ها و شواهد آزمون در [PROJECT_STATE.md](PROJECT_STATE.md) و [گزارش‌های ممیزی](docs/audits/) آمده‌اند؛ ادعاهای تاریخی COMPLETE/READY تأیید فعلی محسوب نمی‌شوند.

## ساخت و مرز نسخه‌ها

از `apps/lifemate/` با Flutter 3.47.6:

```bash
flutter pub get
flutter analyze --no-pub
flutter test --no-pub

# نسخه مستقل محلی بدون Login؛ شناسه com.example.lifemate.localtest
ORG_GRADLE_PROJECT_lifemateLocalTest=true flutter build apk --release --target=lib/role_entry_main.dart

# نسخه دارای Login متصل به staging؛ نشانی HTTPS باید صریح باشد
flutter build apk --release --dart-define=LIFEMATE_API_URL=https://lifemate-api-fn-staging.up.railway.app
flutter build web --release --dart-define=LIFEMATE_API_URL=https://lifemate-api-fn-staging.up.railway.app
```

نسخه «آرام (محلی)» پروفایل و تکلیف را فقط روی دستگاه نگه می‌دارد؛ Sync/backup سرور، خانواده، سلامت و AI ندارد. داده نصب قبلی را منتقل نمی‌کند و uninstall می‌تواند داده را حذف کند. بایگانی رکورد را حفظ می‌کند. APK محلی را از workflow `Verify local device persistence` و Artifact `LifeGuide-local-persistence-test-apk` دریافت کنید؛ Artifact استاندارد CI entrypoint دارای Login دارد.

پیش‌فرض `LIFEMATE_API_URL` در کد `http://localhost:8080` و فقط برای توسعه است؛ در Android واقعی، localhost همان دستگاه است. CI و workflow انتشار موجود نشانی HTTPS staging را صریح تزریق می‌کنند. داشتن مجوز INTERNET و endpoint صحیح، اثبات login/CRUD روی دستگاه یا استقرار اصلاحات Backend نیست. تغییرات این بسته روی Railway مستقر نشده‌اند و نقص‌های خانواده/اشتراک هنوز باقی‌اند.

امضای فعلی APKها debug است؛ امضاهای CI قبلی و جدید واقعاً متفاوت بودند. نسخه محلی با شناسه مستقل برای حفظ نصب قبلی ساخته می‌شود؛ نگهداری امن کلید پایدار برای ارتقای نسخه‌های بعد و پذیرش نصب روی گوشی مالک هنوز لازم است. هیچ کلید یا token واقعی نباید در مخزن یا متن چت قرار گیرد.

## Repository operating documents

- [`AGENTS.md`](AGENTS.md) — operating rules and ownership model.
- [`PROJECT_STATE.md`](PROJECT_STATE.md) — current checkpoint and change ledger.
- [`docs/decisions/`](docs/decisions/) — architecture and product decision records.

## Working name

نام محصول در دستور انتقال مالک «آرام / Life Guide» است؛ نام مخزن و package پروژه همچنان LifeMate است.
