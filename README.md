# LifeGuide / لایف‌گاید

همراه فارسی و راست‌به‌چپ خانواده و آموزش؛ Android و PWA والدین از یک API مبتنی بر Node/Express و PostgreSQL مشترک استفاده می‌کنند. نام مخزن `davoodmehraban89/LifeMate` و قراردادهای قدیمی پایگاه داده و JWT تغییر نمی‌کنند.

این شاخه یک **نامزد آزمون آنلاین با داده ساختگی** است. نسخه کامل عملیاتی یا منتشرشده نیست. پذیرش Android/iPhone/Safari واقعی و دسترسی بدون VPN داخل ایران **UNVERIFIED** است. Backend موجود و Feature 1 ایران حفظ شده‌اند؛ حالت بدون ورودِ محلی جای سیستم چندکاربره نیست.

## شروع محلی

Windows/LAN: [راهنمای Stage 0](docs/operations/STAGE0.md). Docker Desktop/Compose و گواهی HTTPS مورد اعتماد دستگاه‌های آزمون لازم‌اند؛ حساب یا پرداخت میزبان لازم نیست. مسیر بررسی‌شده، بسته‌بندی وب از خروجی واقعی build است: [LifeGuide-web از CI موفق](https://github.com/davoodmehraban89/LifeMate/actions/runs/37810558847/artifacts/11563914781) را همراه فایل provenance در `apps/lifemate/build/web` استخراج کنید، یا مطابق راهنما با Flutter3.47.6 بسازید. checkout باید شامل همان کد برنامه باشد؛ checker خروجی قدیمی یا نامنطبق را رد می‌کند.

```powershell
node scripts/prebuilt-web-check.mjs apps/lifemate
./scripts/local-deploy.ps1 -Origin https://192.168.1.10 -Certificate deployment/tls/server.pem -PrivateKey deployment/tls/server-key.pem -PrebuiltWeb
```

IP نمونه را با IP رایانه عوض کنید. روی Linux، پس از تولید گواهی و انتخاب مبدأ:

```bash
bash scripts/local-deploy.sh --prebuilt-web --init https://192.168.1.10
```

`.env`، گواهی خصوصی، backup و keystore خارج Git بمانند. API و PostgreSQL پورت عمومی ندارند؛ nginx، PWA و `/api` را از همان HTTPS ارائه می‌کند. `deployment/runtime-config.json` تنظیم عمومی وب است؛ Android از تنظیم داخل برنامه استفاده می‌کند. تغییر سرور، نشست و کش قبلی را پاک می‌کند؛ صف خصوصی به سرور دیگری ارسال نمی‌شود. build کامل SDK داخل Docker در این محیط به علت کمبود دیسک موفق نشد و **UNVERIFIED** است؛ مسیر prebuilt، Compose و HTTPS واقعی آزموده شده‌اند. اجرای Windows و گوشی مالک همچنان جداگانه لازم است.

## توسعه و آزمون

```bash
cd backend
npm ci
npm run migrate
npm test
npm run check
```

دیتابیس آزمون باید PostgreSQL16 محلی با **داده ساختگی** باشد؛ `DATABASE_URL` و `JWT_SECRET` را از محیط خصوصی تنظیم کنید. پیش از آزمون، migrationها را اجرا کنید. Flutter3.47.6:

```bash
cd apps/lifemate
flutter pub get
flutter analyze
flutter test
flutter build web --release --no-web-resources-cdn --pwa-strategy=none
node tool/self_host_web.mjs build/web
cd ../..
node scripts/prebuilt-web-check.mjs apps/lifemate --stamp-after-build
```

خروجی وب CanvasKit و فونت‌ها را محلی ارائه می‌کند. انتشار خودکار قبلی حذف شده؛ استقرار و APK امضاشده فقط workflow دستیِ پیش‌فرض خاموش دارند. APK آزمایشی debug را با release رسمی اشتباه نگیرید. شناسه نهایی Android `ir.lifeguide.app` و نام فایل release رسمی `LifeGuide.apk` است؛ ساخت آن به کلید واقعی مالک نیاز دارد.

## داده و حریم خصوصی

PostgreSQL مرجع رکوردها و مجوزهاست؛ کش/صف آفلاین بر اساس کاربر و API جدا می‌شود. شناسه UUID، نسخه و تأیید سرور از تکرار و بازنویسی خاموش جلوگیری می‌کنند. والد فقط تکلیف و گزارش مجاز را می‌بیند. زمان ثبت‌شده تایمر یا گزارش شخصی، مدرک مطالعه واقعی نیست. AI/voice خارجی و قابلیت‌های حساس سلامت/چرخه در این بسته غیرفعال‌اند؛ بررسی حقوقی/رضایت و نگهداری داخلی داده حساس، گیت‌های باز انتشار هستند.

در این نامزد آزمون، هر حساب از دستگاه یا browser profile مستقل و فقط یک تب/PWA فعال استفاده کند؛ هماهنگی token و cache بین تب‌های هم‌زمان هنوز پیاده‌سازی و آزموده نشده است.

- [وضعیت و شواهد](PROJECT_STATE.md)، [تغییرات](CHANGELOG.md)، [تحلیل شکاف main](docs/audits/2026-10-08-online-gap-analysis.md)
- [ماتریس پذیرش A–H، خروجی‌ها و artifactها](docs/audits/2026-10-08-online-acceptance.md)، [HTTPS و مرورگر واقعی محلی](docs/audits/2026-10-08-stage0-verification.md)
- [تصمیم میزبانی و تحقیق](docs/decisions/0009-provider-neutral-hosting.md)، [نام و هویت انتشار](docs/decisions/0010-lifeguide-naming.md)
- [استقرار/بازگشت](docs/operations/SELF_HOSTED_DEPLOYMENT.md)، [تمرین مهاجرت داخلی](docs/operations/DOMESTIC_MIGRATION.md)

میزبانی عمومی، DNS، انتقال داده واقعی، merge و انتشار هنوز انجام نشده‌اند و به مجوز مالک نیاز دارند. گزینه پیشنهادی فعلی Stage 0 رایگان روی LAN است؛ VPS رایگانِ مناسب بدون کارت در تحقیق تأیید نشد.
