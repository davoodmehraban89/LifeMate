# LifeGuide0.5.1 — اقدام‌های دستی مالک

کد آزموده‌شده `7c4ca78` و خروجی‌های [run37893432018](https://github.com/davoodmehraban89/LifeMate/actions/runs/37893432018) هستند. commit تحویل بعدی فقط مستندات است. نصب Windows/Android/Safari و دسترسی بدون VPN ایران **UNVERIFIED**؛ فقط حساب‌های ساختگی برای پذیرش استفاده شوند. هیچ گام این صفحه توسط تیم روی سرور زنده انجام نشده است.

## 1. Stage0 رایگان؛ نیازی به انتخاب VPS فعلی نیست

checkout شاخه `feat/online-family-stage0` را در پوشهٔ آزمون مستقل آماده کنید. [LifeGuide-web](https://github.com/davoodmehraban89/LifeMate/actions/runs/37893432018/artifacts/11600220473) را همراه `build-provenance.json` در `apps/lifemate/build/web` استخراج کنید. Docker Desktop/WSL2، Node22 و mkcert لازم‌اند. IP نمونه را با IP واقعی PC عوض کنید؛ port-forward/tunnel/DNS عمومی نسازید.

description فعلی GitHub هنوز نام قدیمی دارد؛ اگر مالک metadata را اصلاح کرد، فقط description به LifeGuide تغییر کند، نه نام/URL مخزن. این تنظیم خارجی توسط تیم تغییر نکرده است.

```powershell
New-Item -ItemType Directory -Force deployment/tls | Out-Null
mkcert -install
mkcert -cert-file deployment/tls/server.pem -key-file deployment/tls/server-key.pem 192.168.1.10 localhost 127.0.0.1
mkcert -CAROOT
node scripts/prebuilt-web-check.mjs apps/lifemate
./scripts/local-deploy.ps1 -Origin https://192.168.1.10 -PrebuiltWeb
```

نصب تازه نقش‌ها را آماده می‌کند. روی دیتابیس موجود، script عادی مالکیت را تغییر نمی‌دهد؛ writers را متوقف، backup تازه و restore drill را تأیید و [DATABASE_ROLES](DATABASE_ROLES.md) را با expected owner واقعی انجام دهید. CA فقط به‌صورت **گواهی عمومی** به دستگاه آزمون منتقل شود؛ private key هرگز منتقل نشود. اعتماد iOS/Android و ساخت debug با public CA در [STAGE0](STAGE0.md) آمده؛ APK عمومی CI، اعتماد خودکار به mkcert گوشی را اثبات نمی‌کند.

fixture سه حساب مستقل و smoke را دقیقاً از همان راهنما اجرا کنید؛ داده واقعی وارد نکنید. Android کودک و PWA هر والد به یک origin/API/DB وصل شوند. سناریوی هشت‌مرحله‌ای را با بستن/بازکردن هر سه دستگاه، تغییر آفلاین و reconnect اجرا و تاریخ/دستگاه/نتیجه A–H را بدون password/token ثبت کنید. پیش از ارتقا تمام تب‌های نسخه قبل را ببندید؛ تب دوم نسخه جدید صفحه retry دارد. ورود دوباره همان حساب/API، صف قرنطینه‌شده را بازیابی می‌کند؛ خروج عمدی یا تغییر سرور را قبل از بررسی pending انجام ندهید.

## 2. خروجی APK و کلید رسمی

[LifeGuide-debug.apk](https://github.com/davoodmehraban89/LifeMate/actions/runs/37893432018/artifacts/11600076483) فقط آزمایشی و با گواهی debug است. پس از استخراج، hash فایل را با [receipt](../audits/evidence/ci-0.5.1.json) مقایسه کنید:

```powershell
Get-FileHash ./LifeGuide-debug.apk -Algorithm SHA256
```

SHA256 APK با ZIP متفاوت است. نصب/upgrade هنوز **UNVERIFIED**؛ گواهی debug دو run می‌تواند متفاوت باشد. برای کلید رسمی، در terminal خودتان و خارج repo، با JDK یک keystore پایدار بسازید؛ password فقط prompt محلی:

```text
keytool -genkeypair -keystore LifeGuide-release.jks -alias lifeguide -keyalg RSA -keysize 4096 -validity 10000
```

این فرمان در این بسته اجرا نشده است؛ کلید را با backup امن جدا نگه دارید. شناسهٔ نهایی `ir.lifeguide.app` پس از انتشار تغییر نکند. secretهای `LIFEGUIDE_KEYSTORE_BASE64`, `LIFEGUIDE_KEYSTORE_PASSWORD`, `LIFEGUIDE_KEY_ALIAS`, `LIFEGUIDE_KEY_PASSWORD` فقط در GitHub environment حفاظت‌شده `release-signing`/secret manager تنظیم شوند؛ keystore/password/base64 در repo، issue یا chat نیایند. workflow امضا پیش‌فرض خاموش است؛ فقط پس از تصمیم مالک، `LIFEGUIDE_RELEASE_SIGNING_CONFIGURED=true` و dispatch با `BUILD_SIGNED_TEST_ARTIFACT`. این ساخت test artifact مجوز انتشار عمومی نیست. `LifeGuide.apk` رسمی در این بسته ساخته نشده است.

## 3. پیامک/ایمیل

مالک provider قابل استفاده با شرایط/پرداخت واقعی خود را انتخاب کند؛ هیچ ثبت حساب/خرید انجام نشده و delivery واقعی **UNVERIFIED** است. قرارداد SMS adapter و متغیرهای `SMS_*` در `.env.example`/Backend هستند؛ default خاموش بماند تا endpoint HTTPS، token در secret manager، callback/idempotency و delivery با داده ساختگی آزموده شوند. email اختیاری است؛ بدون provider فعال، ثبت‌نام pending است و fixture verified شاهد تحویل نیست. کلید provider در chat ارسال نشود.

## 4. میزبانی، DNS و انتقال داخلی

پیشنهاد فعلی [ADR0009](../decisions/0009-provider-neutral-hosting.md): Stage0 روی LAN بدون هزینه میزبانی؛ fallback فقط سرورِ تحت کنترل مالک، اگر در اختیار باشد. VPS خارجی، KYC/پرداخت و VPN-free Iran تأیید نشده‌اند؛ خرید سرویس ایرانی توصیه نشده و managed-hostهای ممنوع کنار گذاشته شده‌اند. قبل از انتخاب عمومی، testerهای داخل ایران از حداقل دو اپراتور، VPN خاموش، `scripts/reachability-smoke.mjs` را روی origin انتخاب‌شده اجرا کنند. TLS/PWA/health PASS به‌تنهایی پذیرش چندکاربره نیست؛ API round-trip به credential ساختگی و opt-in نوشتن نیاز دارد.

DNS، deploy یا تغییر زنده فقط پس از تصمیم و مجوز صریح مالک است. همان Compose با PostgreSQL16 داخلی، imageهای ثبت‌شده و credentialهای مستقل منتقل می‌شود. [DOMESTIC_MIGRATION](DOMESTIC_MIGRATION.md) شامل dump با backup فقط‌خواندنی، restore توسط migrator روی مقصد خالی، grants، کنترل شمار/مجوز/نشست، توقف writers، cutover یک مبدأ و rollback بدون دو DB هم‌زمان writable است. drill ساختگی واقعاً PASS شد؛ cutover/rollback زنده **UNVERIFIED**. ابتدا backup رمزگذاری‌شده خارج PC و restore دوره‌ای آماده کنید. داده واقعی حساس کودک/چرخه/یادداشت/AI روی میزبان خارجی قرار نگیرد؛ gate حقوقی/رضایت و نگهداری داخلی هنوز فقط flag است.
