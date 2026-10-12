# LifeGuide / لایف‌گاید — تحویل بسته 0.7.1

واقعاً اجرا شد: Backend **245/245**، Flutter **200/200**، build وب و APK debug و هر سه job در [CI38201011644](https://github.com/davoodmehraban89/LifeMate/actions/runs/38201011644). منبع آن `0831ee6ba81a4811f819e8d8dbfe3f7b24a566ef`، نسخه Backend **0.7.1** و برنامه **0.7.0+6** است. [رسید CI و فایل‌ها](../audits/evidence/ci-content-operations-final-2026-10-12.json) و [گزارش آزمون و حدود پذیرش](../audits/2026-10-12-content-operations-verification.md) مرجع‌اند. [PR پیش‌نویس۱۲](https://github.com/davoodmehraban89/LifeMate/pull/12) ادغام نشده است؛ این خروجی نامزد آزمون با داده ساختگی است.

## اکنون و کادر URL در APK

تا وقتی به رایانه دسترسی ندارید، **اقدام فوری لازم نیست**. کادر اتصال، نشانی HTTPS **API مشترک خانواده** را می‌خواهد؛ نصب APK یا وارد کردن نشانی، سرور ایجاد نمی‌کند. API عمومی سازگار و فعال تأیید نشده است. [بررسی11اکتبر دامنه](../audits/2026-10-11-apk-connection.md) پاسخ قدیمی HTML را ثبت کرد؛ این بررسی تازه DNS نیست. `app.lifeguide.ir` یا مسیر آن را حدس نزنید و DNS را فعلاً تغییر ندهید.

بعد از اجرای سالم Stage0 و اعتماد گواهی، PWA روی `https://OWNER-LAN-IP/` و نشانی مورد نیاز APK روی `https://OWNER-LAN-IP/api` است؛ `OWNER-LAN-IP` را با IP واقعی رایانه عوض کنید. `localhost` روی گوشی به خود گوشی اشاره می‌کند. این نشانی فقط در LAN و هنگام روشن بودن PC/Docker قابل استفاده است؛ لینک اینترنتی عمومی نیست.

## فایل Android و امضا

[دانلود APK همین run](https://github.com/davoodmehraban89/LifeMate/actions/runs/38201011644/artifacts/11725931941) یک ZIP با فایل **LifeGuide-debug.apk** است. لینک artifact مخزن خصوصی به ورود حساب GitHub دارای دسترسی نیاز دارد؛ از صفحه run هم قابل دریافت است. لینک موقت فایل چت ممکن است منقضی شود. فایل APK روی iPhone نصب نمی‌شود؛ مسیر iPhone، PWA در Safari است.

پس از استخراج، در PowerShell بررسی کنید:

```powershell
Get-FileHash ./LifeGuide-debug.apk -Algorithm SHA256
```

اندازه APK **168960414 بایت** و SHA256 آن **b9b8599de796986cf2800ce24782ee85bc87a7d97889d2d194465f0ad4f07915** است؛ هش ZIP متفاوت است. manifest واقعی `ir.lifeguide.app`، نسخه0.7.0/code6، label فارسی و منع cleartext را نشان داد. روی runner، امضای debug با v2 واقعاً تأیید شد؛ گواهی SHA256 آن `c1bf6ec0237985d9fadf7d12d614b2461e78dda64903dcff1009867b43a972e1` است و با گواهی debug اجرای قبلی تفاوت دارد. **نصب/ارتقای Android واقعی UNVERIFIED** است و تفاوت امضا می‌تواند ارتقای درجا را رد کند. برای رفع آن، برنامه یا داده دارای تغییر ارسال‌نشده را حذف نکنید. APK رسمی با کلید انتشار مالک هنوز ساخته نشده است.

## Windows/LAN: دستورهای محلی پس از دسترسی به PC

Docker Desktop با WSL2، Git، Node22 و mkcert لازم‌اند. این فرمان‌ها روی Windows مالک **UNVERIFIED** هستند؛ اجرای Linux/Compose تیم جای پذیرش Windows و گوشی را نمی‌گیرد. فقط داده ساختگی استفاده کنید. یک پوشه تازه آماده کنید؛ checkout یا داده قبلی را reset/force نکنید:

```powershell
git clone --branch feat/learning-content-operations --single-branch https://github.com/davoodmehraban89/LifeMate.git LifeGuide-test-0.7.1
Set-Location LifeGuide-test-0.7.1
git switch --detach 0831ee6ba81a4811f819e8d8dbfe3f7b24a566ef
ipconfig
```

[LifeGuide-web همین run](https://github.com/davoodmehraban89/LifeMate/actions/runs/38201011644/artifacts/11725840928) را همراه تمام فایل‌ها و `build-provenance.json` در `apps/lifemate/build/web` استخراج کنید؛ `index.html` باید مستقیم در همین پوشه باشد. artifact0.6 قدیمی با این منبع سازگار نیست. اگر checker رد کرد، provenance را برای معتبر جلوه دادن خروجی قدیمی stamp نکنید؛ build موفق همان منبع لازم است. روش build محلی در [STAGE0](STAGE0.md#بسته‌بندی-pwa-از-خروجی-build-بررسی‌شده) آمده است.

PC و گوشی‌ها روی LAN مورد اعتماد باشند؛ guest Wi-Fi/client isolation می‌تواند اتصال را قطع کند. IP مثال زیر را با IP واقعی PC عوض کنید و برایش DHCP reservation بگذارید:

```powershell
New-Item -ItemType Directory -Force deployment/tls | Out-Null
mkcert -install
mkcert -cert-file deployment/tls/server.pem -key-file deployment/tls/server-key.pem 192.168.1.10 localhost 127.0.0.1
mkcert -CAROOT
node scripts/prebuilt-web-check.mjs apps/lifemate
./scripts/local-deploy.ps1 -Origin https://192.168.1.10 -PrebuiltWeb
docker compose ps
```

اگر هر مرحله fail شد، قبل از ورود به برنامه آن را برطرف کنید. اسکریپت `.env` تازه را با secretهای تصادفی می‌سازد و env موجود را حفظ می‌کند؛ API، migrator و backup credential مستقل دارند. روی volume قدیمی، انتقال مالکیت خودکار انجام نمی‌شود؛ ابتدا [DATABASE_ROLES](DATABASE_ROLES.md) و backup/adoption صریح را بررسی کنید. `.env` و کلیدها خارج Git بمانند؛ خروجی کامل `docker compose config` را در چت نفرستید.

فقط **rootCA.pem عمومی** را از مسیر `mkcert -CAROOT` به دستگاه‌های شخصی آزمون منتقل کنید. `rootCA-key.pem` و `server-key.pem` خصوصی‌اند. iPhone: profile گواهی را نصب، سپس Settings → General → About → Certificate Trust Settings، full trust همان CA را فعال کنید؛ Safari باید URL LAN را بدون هشدار گواهی باز کند. سپس Share → Add to Home Screen. این پذیرش واقعی **UNVERIFIED** است.

APK عمومی CI، CA رایانه شما را ندارد. برای LAN، توسعه‌دهنده باید با Flutter3.47.6 و public CA همان رایانه، debug جدا بسازد؛ نصب CA روی گوشی به‌تنهایی اعتماد transport برنامه را اثبات نمی‌کند:

```powershell
$caRoot = mkcert -CAROOT
$publicCa = [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $caRoot 'rootCA.pem')))
Set-Location apps/lifemate
flutter build apk --debug --dart-define="LIFEGUIDE_DEBUG_CA_BASE64=$publicCa"
Set-Location ../..
Remove-Variable publicCa
```

این build سفارشی/نصب دستگاه در این بسته **UNVERIFIED** است؛ define توسعه در release رد می‌شود و TLS نباید دور زده شود. تفاوت امضای این build با APK نصب‌شده نیز باید بررسی شود. در صورت نیاز به فایروال، فقط TCP443 در Private profile و `LocalSubnet` طبق [STAGE0](STAGE0.md#آماده‌سازی-windows) باز شود؛ port-forward، tunnel یا DNS عمومی برای LAN لازم نیست.

## حساب‌های ساختگی، smoke و سناریوی خانواده

فقط روی DB تازه Stage0، رمز تصادفی آزمایشی حداقل۱۰کاراکتر را **در محیط خصوصی رایانه خودتان** تنظیم کنید. آن را در چت یا Git قرار ندهید. seed با نقش migrator کوتاه‌مدت انجام می‌شود؛ runtime API همچنان نقش محدود دارد:

```powershell
$env:SYNTHETIC_PASSWORD = '<رمز تصادفی فقط آزمایشی روی رایانه خودتان>'
docker compose run --rm --no-deps -e ALLOW_SYNTHETIC_SEED=yes -e SYNTHETIC_PASSWORD migrate node scripts/seed-compose-smoke.js
docker compose run --rm --no-deps -e ALLOW_SYNTHETIC_SEED=yes -e SYNTHETIC_PASSWORD migrate node scripts/seed-stage0-family.js
$env:SMOKE_EMAIL = 'compose-smoke@lifeguide.test'
$env:SMOKE_PASSWORD = $env:SYNTHETIC_PASSWORD
$env:SMOKE_ALLOW_SYNTHETIC_WRITE = 'yes'
$env:ROOT_CA_FILE = Join-Path (mkcert -CAROOT) 'rootCA.pem'
node scripts/reachability-smoke.mjs https://192.168.1.10
Remove-Item Env:SYNTHETIC_PASSWORD, Env:SMOKE_PASSWORD
```

هر دستور seed باید موفق شود؛ ادامه پس از fail معتبر نیست. حساب‌های `stage0-child@lifeguide.test`، `stage0-mother@lifeguide.test` و `stage0-father@lifeguide.test` با همان رمز محلی و دو guardian مجاز ساخته می‌شوند. verification مستقیم این fixture **آزمایشی** است؛ تحویل ایمیل/پیامک را اثبات نمی‌کند. برای هر عضو از دستگاه یا browser profile مستقل استفاده کنید؛ Web Lock عمداً یک تب/PWA فعال را در هر origin/profile می‌پذیرد.

در JSON ابزار، TLS/health/PWA/config/auth boundary باید جدا **PASS** شوند. `API round-trip=PASS` یعنی ایجاد تکلیف خصوصی ساختگی، خواندن مستقل، بایگانی و logout روی API واقعی؛ بدون opt-in نوشتن، این بخش **UNVERIFIED** است. `PWA=PASS` نصب Safari را اثبات نمی‌کند. برای tester داخل ایران، تاریخ، شبکه/اپراتور، VPN خاموش و نتیجه هر check را ثبت کنید؛ password/token در گزارش نباشد.

سناریوی دستگاهی: کودک تکلیف ریاضی اضافه کند؛ مادر در PWA همان تکلیف را ببیند؛ کودک تایمر را شروع، مکث، ادامه و تمام کند؛ زمان ثبت‌شده در گزارش مجاز مادر دیده شود؛ کودک تکلیف را تمام کند؛ پدر با حساب مستقل تازه‌سازی کند؛ هر سه برنامه بسته و باز شوند؛ تغییر آفلاین با اتصال دوباره فقط یک رسید سرور بگیرد. زمان تایمر/خوداظهاری اثبات مطالعه نیست. آزمایش محلی فعلی چهارثانیه ثبت کرد؛ UI دقیقه‌ای آن را صفر دقیقه نشان می‌دهد، نه چهارثانیه دقیق. نصب/بستن Android، Safari و سه دستگاه واقعی همچنان **UNVERIFIED** هستند.

در «مدرسه من»، سال/نیم‌سال با تاریخ واقعی و پایه را انتخاب کنید؛ هدف آموزشی، پیشرفت، تاریخچه مرور و بازخورد فقط با متن ساختگی آزموده شوند. پیش از logout عمدی، تغییر سرور یا ارتقا، pending و ACK آخرین sync را بررسی کنید؛ این اعمال و پاک‌کردن storage می‌توانند صف را حذف کنند. انقضای نشست به‌تنهایی صف را برای ورود دوباره همان حساب/API حفظ می‌کند. cold-start آفلاین PWA فعلاً صفحه عمومی قطع اتصال است؛ برنامه احراز هویت‌شده آفلاینِ کامل نیست.

## گیت‌های انتشار، provider و سرور

1. **کلید امضا:** اگر کلید انتشار پایدار دارید، همان را خارج مخزن حفظ کنید. در صورت نداشتن، با JDK در پوشه خصوصی خارج repo، `keytool -genkeypair -keystore LifeGuide-release.jks -alias lifeguide -keyalg RSA -keysize 4096 -validity 10000` را با password prompt محلی اجرا و backup امن جدا نگه دارید. این فرمان توسط تیم اجرا نشده است. secretهای `LIFEGUIDE_KEYSTORE_BASE64`، `LIFEGUIDE_KEYSTORE_PASSWORD`، `LIFEGUIDE_KEY_ALIAS`، `LIFEGUIDE_KEY_PASSWORD` فقط در محیط حفاظت‌شده GitHub `release-signing`/secret manager قرار بگیرند. [workflow](../../.github/workflows/release-build.yml) پیش‌فرض خاموش است؛ فعال‌سازی `LIFEGUIDE_RELEASE_SIGNING_CONFIGURED=true` و dispatch با `BUILD_SIGNED_TEST_ARTIFACT` فقط پس از تصمیم مالک، ساخت آزمایشی امضاشده را اجازه می‌دهد. انتشار عمومی مجوز جدا می‌خواهد. شناسه `ir.lifeguide.app` بعد از انتشار تغییر نمی‌کند؛ فایل رسمی **LifeGuide.apk** هنوز ساخته نشده است.
2. **ایمیل/پیامک:** مالک provider قابل استفاده خود را انتخاب کند؛ خرید یا ساخت حساب توسط تیم انجام نشده است. email اختیاری و SMS پیش‌فرض disabled است. [نمونه env](../../.env.example) شامل SMTP و `SMS_PROVIDER=webhook`/`SMS_PROVIDER_URL`/`SMS_PROVIDER_TOKEN` است؛ token فقط محیط خصوصی، endpoint HTTPS و delivery با حساب/شماره ساختگی آزموده شود. پاسخ2xx adapter پذیرش webhook است، نه اثبات رسیدن SMS به گوشی. delivery واقعی **UNVERIFIED** است.
3. **میزبانی و DNS:** پیشنهاد [ADR0009](../decisions/0009-provider-neutral-hosting.md)، Stage0 رایگان روی PC/LAN است؛ fallback فقط سرور تحت کنترل مالک، اگر در اختیار باشد. گزینه VPS رایگان بلندمدت بدون کارت تأیید نشده؛ پذیرش ایران/پرداخت/KYC/IP/reachability نامزد خارجی **UNVERIFIED** است. خرید سرویس پیشنهاد نشده است. انتخاب origin/IP، deploy زنده، تغییر DNS `app.lifeguide.ir` و انتشار فقط پس از مجوز صریح مالک و آزمون testerهای ایران بدون VPN انجام شوند. همه fallbackها باید به همان backend/DB مجاز برسند. هیچ‌کدام اکنون اجرا نشده‌اند.
4. **backup/مهاجرت داخلی:** [DOMESTIC_MIGRATION](DOMESTIC_MIGRATION.md) دستورهای dump با backup فقط‌خواندنی، restore با migrator روی DB تازه و خالی،20checksum، grants، توقف نوشتن، cutover و rollback را دارد. drill ساختگی با **20checksum،58 منع SQL در source/restore و نشست۶۰۰ثانیه با وقفه** واقعاً گذشت؛ انتقال واقعی/DNS/rollback زنده **UNVERIFIED** است. فرمان محلی `bash scripts/restore-drill.sh --synthetic-only` از Git Bash/WSL با Docker محلی، دو DB موقت مختص drill می‌سازد؛ اجرای آن روی Windows مالک هنوز **UNVERIFIED** است. backup رمزگذاری‌شده خارج PC و پذیرش restore پیش از انتقال واقعی لازم‌اند.

برای توقف معمول، `docker compose stop` و `docker compose start` volume را حفظ می‌کنند؛ **`down -v` اجرا نکنید**. خواب/خاموشی PC سرویس LAN را قطع می‌کند. backup فعلی خودکار رمزگذاری یا خارج PC منتقل نمی‌شود.

## حدود این تحویل

اهداف، خانواده، مدرسه، گزارش مجاز والد، تاریخچه و عملیات رضایت بازخورد روی API/PostgreSQL پیاده‌سازی شده‌اند. فهرست217کتاب/1373بخش/1348نامزد ویدیو، پوشش آماده یک سال مدرسه نیست: **ویدیوی واقعی با بازبینی کامل و منتشرشده صفر؛ بانک سؤال واقعی منتشرشده صفر**. [CONTENT_REVIEW](CONTENT_REVIEW.md) و [LEARNING_CONTENT](LEARNING_CONTENT.md) گیت چاپ رسمی، مشاهده کامل، تطبیق اهداف، صحت/تناسب، حقوق نمایش و بازبینی سؤال را مشخص می‌کنند؛ draft بررسی‌نشده به کودک عرضه نمی‌شود.

A–G فقط در دامنه دقیق آزمون API/SQL/Chromium محلی شواهد دارند؛ Android واقعی، Safari/A2HS/iPad، Windows مالک، شبکه ایران بدون VPN و H دستگاهی **UNVERIFIED** هستند. ریز محدودیت‌ها و probeهای مرورگر در گزارش آزمون ثبت می‌شوند. AI/voice خارجی و سلامت/چرخه غیرفعال‌اند؛ رضایت/حقوق کودکان، نگهداری داخلی و safeguarding نیازمند کار و بررسی تخصصی جدا هستند. بازخورد رضایت‌داده‌شده خودکار به AI/agent یا والد ارسال نمی‌شود. هیچ deploy زنده، DNS، انتقال داده واقعی، merge نهایی، انتشار عمومی، ثبت‌نام یا پرداخت انجام نشده است.
