# LifeGuide / لایف‌گاید — Stage 0 روی LAN

این بسته Node/Express، PostgreSQL و PWA را روی **یک PC محلی** با یک مبدأ HTTPS اجرا می‌کند. حساب، پرداخت، DNS عمومی، تونل و port-forward ندارد. این راهنما دستور اجرای مالک است؛ اجرای Windows، Android واقعی و Safari واقعی تا ثبت شواهد **UNVERIFIED** هستند. توصیه میزبانی در [ADR 0009](../decisions/0009-provider-neutral-hosting.md) است.

## آماده‌سازی Windows

1. Docker Desktop با WSL2، Git، Node >=22 و mkcert را نصب کنید. گوشی‌ها و PC به LAN مورد اعتماد متصل باشند. IP محلی PC را با `ipconfig` پیدا و DHCP آن را ثابت کنید. دریافت اولیه وابستگی‌ها ممکن است به VPN توسعه‌دهنده نیاز داشته باشد؛ اجرای کلاینت CDN خارجی ندارد.
2. ابتدا خروجی بررسی‌شده وب را طبق بخش «بسته‌بندی PWA» آماده کنید: artifact کامل [LifeGuide-web](https://github.com/davoodmehraban89/LifeMate/actions/runs/37810558847/artifacts/11563914781) را همراه provenance در `apps/lifemate/build/web` استخراج کنید، یا build واقعی محلی را انجام دهید. سپس از ریشه مخزن، در PowerShell، IP نمونه را عوض کنید:

   ```powershell
   New-Item -ItemType Directory -Force deployment/tls | Out-Null
   mkcert -install
   mkcert -cert-file deployment/tls/server.pem -key-file deployment/tls/server-key.pem 192.168.1.10 localhost 127.0.0.1
   mkcert -CAROOT
   node scripts/prebuilt-web-check.mjs apps/lifemate
   ./scripts/local-deploy.ps1 -Origin https://192.168.1.10 -PrebuiltWeb
   ```

   اولین اجرا `.env` را با secretهای تصادفی می‌سازد؛ اجراهای بعدی آن را حفظ می‌کنند. فایل `.env`، کلید سرور و rootCA-key خصوصی هستند و باید خارج Git بمانند. فقط **گواهی عمومی** rootCA.pem را به گوشی آزمون منتقل کنید. CA خصوصی را هرگز منتقل نکنید.
3. فقط در صورت نیاز، PowerShell مدیر، rule فایروال محدود به LAN بسازید:

   ```powershell
   New-NetFirewallRule -DisplayName 'LifeGuide Stage 0 HTTPS' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 443 -Profile Private -RemoteAddress LocalSubnet
   ```

4. iOS: profile گواهی عمومی را نصب و Settings → General → About → Certificate Trust Settings، full trust همان CA را فعال کنید. Safari باید `https://192.168.1.10/` را بدون هشدار TLS باز کند؛ سپس Share → Add to Home Screen. روی Android، اعتماد اپ Dart به CA نصب‌شده باید مستقلاً آزموده شود؛ نصب CA به‌تنهایی شاهد نیست. نسخه release نباید TLS را دور بزند. برای APK debug توسعه، گواهی عمومی mkcert را صریحاً به build بدهید:

   ```powershell
   $caRoot = mkcert -CAROOT
   $publicCa = [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $caRoot 'rootCA.pem')))
   Set-Location apps/lifemate
   flutter build apk --debug --dart-define="LIFEGUIDE_DEBUG_CA_BASE64=$publicCa"
   Set-Location ../..
   ```

   این فرمان **UNVERIFIED روی Android واقعی** است. فقط public CA وارد context اعتماد debug می‌شود؛ هیچ callback برای قبول گواهی نامعتبر وجود ندارد. این define در profile/release رد می‌شود. APK debug جای APK رسمی امضاشده نیست و اگر نسخه با گواهی متفاوت نصب باشد ارتقای درجا ممکن نیست؛ داده واقعی را در نسخه توسعه وارد نکنید.

## بسته‌بندی PWA از خروجی build بررسی‌شده

برای جلوگیری از download و snapshotهای بزرگ SDK داخل Docker، می‌توانید PWA را با Flutter3.47.6 روی محیط توسعه/CI بسازید و فقط خروجی بررسی‌شده را با همان nginx/TLS بسته‌بندی کنید. فرمان‌ها از ریشه مخزن، **پس از checkout همان commit** هستند:

```powershell
Set-Location apps/lifemate
flutter build web --release --no-web-resources-cdn --pwa-strategy=none
node tool/self_host_web.mjs build/web
Set-Location ../..
node scripts/prebuilt-web-check.mjs apps/lifemate --stamp-after-build
./scripts/local-deploy.ps1 -Origin https://192.168.1.10 -PrebuiltWeb
```

Linux محلی، پس از همین build و بررسی: `bash scripts/local-deploy.sh --prebuilt-web --init https://192.168.1.10`. گزینه `--prebuilt-web` باید پیش از `--init` باشد. artifact CI بررسی‌شده را نیز می‌توان در `apps/lifemate/build/web` استخراج کرد؛ فایل provenance باید همراهش باشد. checker source و artifact را با SHA256 تطبیق می‌دهد، برند، CanvasKit/سه فونت محلی و نبود CDN ممنوع را بررسی می‌کند و artifact قدیمی را رد می‌کند. **stamp به‌تنهایی build نیست**؛ فقط پس از اجرای واقعی و موفق build/postprocess آن را بسازید. release APK در این مسیر ساخته نمی‌شود.

مسیر پیش‌فرض Dockerfile از source با SDK دقیق pinشده است. در محیط فعلی توسعه، web compile در Docker موفق شد ولی ساخت image به‌دلیل ظرفیت/snapshot دیسک fail شد؛ build کامل این مسیر **UNVERIFIED** است. مسیر prebuilt از همان source buildشده، compose API/PostgreSQL/backup و gateway واقعی استفاده می‌کند؛ نتیجه اجرای آن در [شواهد Stage 0](../audits/2026-10-08-stage0-verification.md) ثبت می‌شود. اجرای Windows و پذیرش گوشی جدا هستند.

## حساب و round-trip ساختگی

اگر شبکه توسعه از proxy با CA سازمانی استفاده می‌کند، فقط گواهی **عمومی** آن را در `BUILD_CA_FILE` تنظیم کنید. script از override اختیاری `docker-compose.build-proxy.yml` و BuildKit secret استفاده می‌کند؛ گواهی یا proxy URL داخل کلاینت نهایی قرار نمی‌گیرد. TLS verification خاموش نمی‌شود. این گزینه مخصوص build است؛ CA اعتماد Stage 0 روی گوشی، گواهی جداگانه mkcert است.

این fixture، فقط برای دیتابیس تازه Stage 0 است؛ تحویل واقعی ایمیل/SMS را اثبات نمی‌کند. رمز را خودتان تولید و فقط در محیط محلی نگه دارید. ثبت/ورود کاربران محصول باید از API عادی بگذرد.

```powershell
$env:SYNTHETIC_PASSWORD = '<یک رمز آزمایشی تصادفی حداقل ۱۰ کاراکتر>'
docker compose exec -e ALLOW_SYNTHETIC_SEED=yes -e SYNTHETIC_PASSWORD api node scripts/seed-compose-smoke.js
$env:SMOKE_EMAIL = 'compose-smoke@lifeguide.test'
$env:SMOKE_PASSWORD = $env:SYNTHETIC_PASSWORD
$env:SMOKE_ALLOW_SYNTHETIC_WRITE = 'yes'
$env:ROOT_CA_FILE = '<مسیر rootCA.pem عمومی>'
node scripts/reachability-smoke.mjs https://192.168.1.10
```

برای پذیرش چندکاربره، روی **همین DB ساختگی Stage 0** می‌توانید قبل از پاک کردن متغیر رمز، fixture خانواده را بسازید:

```powershell
docker compose exec -e ALLOW_SYNTHETIC_SEED=yes -e SYNTHETIC_PASSWORD api node scripts/seed-stage0-family.js
```

حساب‌های `stage0-child@lifeguide.test`، `stage0-mother@lifeguide.test` و `stage0-father@lifeguide.test` با همان رمز آزمایشی ساخته می‌شوند؛ عضویت و دو رابطه guardian در DB مشترک‌اند. script حساب/family غیرfixture را تغییر نمی‌دهد. تأیید ایمیل این fixture مستقیم و صریحاً آزمایشی است؛ تحویل ایمیل/SMS محصول را اثبات نمی‌کند. Android فرزند و PWA هر والد باید با حساب مستقل وارد همان origin شوند. سناریوی واقعی تکلیف/مطالعه/تازه‌سازی را از API عادی انجام دهید؛ موفقیت seed جای پذیرش سه دستگاه نیست.

هر والد روی دستگاه یا browser profile مستقل، فقط **یک تب/PWA فعال LifeGuide** داشته باشد. هماهنگی token/cache بین تب‌های هم‌زمان هنوز پیاده‌سازی و آزموده نشده است؛ private-mode/پاک‌کردن storage نیز صف ارسال‌نشده را حذف می‌کند. قبل از خروج یا تغییر سرور، وضعیت صف و تأیید آخرین sync را بررسی کنید.

پس از پایان آزمون، متغیرهای رمز را پاک کنید:

```powershell
Remove-Item Env:SYNTHETIC_PASSWORD, Env:SMOKE_PASSWORD
```

خروجی JSON هر check را جدا نشان می‌دهد. `TLS=PASS` یعنی زنجیره و hostname معتبرند؛ health فقط آماده بودن DB را نشان می‌دهد. `PWA=PASS` بارگیری HTML/manifest است، **نصب Safari را اثبات نمی‌کند**. `API round-trip=PASS` ایجاد تکلیف خصوصی ساختگی، خواندن مستقل و بایگانی روی API مشترک است. بدون اجازه explicit نوشتن و credential ساختگی، round-trip برابر **UNVERIFIED** است. نتیجه داخل ایران باید با تاریخ، اپراتور شبکه و وضعیت VPN خاموش ثبت شود؛ credential و token به گزارش اضافه نشوند.

## Linux محلی و نگهداری

```bash
mkcert -cert-file deployment/tls/server.pem -key-file deployment/tls/server-key.pem 192.168.1.10 localhost 127.0.0.1
bash scripts/local-deploy.sh --prebuilt-web --init https://192.168.1.10
bash scripts/restore-drill.sh --synthetic-only
docker compose ps
docker compose logs --tail=50 migrate api backup
docker compose stop
docker compose start
```

`stop/start` و `down` بدون `-v` volume داده را حفظ می‌کنند. **`down -v` داده و backupها را حذف می‌کند؛ برای استفاده معمول اجرا نکنید.** script اجرای محلی endpoint Docker از نوع SSH/TCP را رد می‌کند. PostgreSQL هیچ host port ندارد. `.env` را `source` نکنید؛ `docker compose config` بدون `--quiet` می‌تواند secretها را چاپ کند.

backup در volume جدا، هنگام startup و طبق cron UTC ساخته می‌شود؛ `/backups/last-success` وضعیت آخرین موفقیت است. این نسخه، backup را خودکار رمزگذاری یا از PC خارج نمی‌کند. مالک باید نسخه رمزگذاری‌شده روی فضای محلی جدا نگه دارد و بازیابی را آزمون کند. خاموشی/خواب PC و توقف Docker باعث قطع سرویس LAN می‌شود. برای خروج، CA آزمون و rule فایروال را از دستگاه‌های آزمون حذف کنید.

## APK

Dockerfile فقط PWA می‌سازد؛ APK را با کلید debug به‌عنوان release تولید نمی‌کند. فقط APK **امضاشده رسمی با کلید انتشار مالک** را پس از بررسی در `deployment/downloads/LifeGuide.apk` بگذارید؛ از همان مبدأ `/downloads/LifeGuide.apk` دریافت می‌شود. APK توسعه، اگر نیاز بود، باید جدا با نام صریح `LifeGuide-debug.apk` و برچسب آزمایشی نگه داشته شود؛ جای فایل رسمی نیست. فایل‌ها در Git نیستند. تا آماده شدن کلید و آزمون امضا، artifact رسمی **UNVERIFIED/ساخته‌نشده** است. نام و وجود فایل، معتبر بودن امضا یا پذیرش دستگاه را اثبات نمی‌کنند.
