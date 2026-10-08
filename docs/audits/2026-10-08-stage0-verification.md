# LifeGuide — شواهد Stage 0

تاریخ: ۲۰۲۶-۱۰-۰۸ UTC. scope اجرا، Docker محلی Linux در محیط توسعه با **داده ساختگی** است. `.env` خصوصی، پروژه `lifeguide-stage0-audit`، HTTPS loopback `127.0.0.1:8443` و گواهی آزمون OpenSSL خارج Git استفاده شدند؛ mkcert/Windows مالک یا شبکه داخل ایران اجرا نشده‌اند. شاخه `feat/online-family-stage0`؛ SHA نهایی در گزارش تحویل ثبت می‌شود.

| اجرا | نتیجه مشاهده‌شده | حد اعتبار |
| --- | --- | --- |
| `docker version` / `docker compose version` | Engine 28.4.0، Compose 2.40.3 | فقط محیط Linux فعلی |
| `docker compose config --quiet` | exit0 | secrets چاپ نشد؛ startup نیست |
| `bash -n scripts/local-deploy.sh scripts/restore-drill.sh deployment/backup/*.sh` و Node `--check` smoke/seed | exit0 | syntax؛ اجرای Windows PS **UNVERIFIED** |
| build API/backup با npm lock و Node22 | موفق | اجرای اول npm شبکه fail شد؛ trusted build proxy/CA اضافه و TLS verification حفظ شد |
| migration نخست DB تازه، سپس تکرار و upgrade 0010 | 0001–0009 applied؛ تکرار بدون applied؛ 0010 بعداً applied | فقط DB ساختگی محلی؛ ledger idempotency مشاهده شد |
| `docker compose up -d --wait ... api backup` | PostgreSQL/API/backup healthy | این نتیجه UI/CRUD/Safari را تأیید نمی‌کند |
| startup backup + cron آزمایشی یک‌دقیقه‌ای | dump ساعت10:37:20 و dump scheduled10:38:00؛ archive list قابل خواندن | schedule خصوصی آزمون به default روزانه برگشت؛ restore جدا اجرا شد |
| `bash scripts/restore-drill.sh --synthetic-only` | **PASS** نهایی16:46 با image نهایی API: حساب، policy خانواده/خصوصی، interval مطالعه و12migration؛ query مستقل count DB باقی‌مانده0 | دو DB تازه، داده ساختگی؛ انتقال واقعی **UNVERIFIED** |
| `DOCKER_HOST=ssh://invalid.example bash scripts/local-deploy.sh` و restore-drill | هر دو با exit1 رد شدند، پیش از تماس remote | guard واقعی محلی؛ سرور زنده تغییر نکرد |
| `bash scripts/local-deploy.sh --prebuilt-web` با CA عمومی build proxy | build imageهای API/gateway/backup و تکرار deploy محلی موفق؛ هر چهار سرویس healthy، migration one-shot exit0 | PWA از build واقعی Flutter؛ مسیر کامل SDK داخل Docker **UNVERIFIED** |
| checker مستقل artifact | **PASS**:44 ورودی، SHA source/artifact مطابق، CanvasKit/فونت محلی، branding و config همان origin | stamp به‌تنهایی build نیست؛ host build جدا اجرا شده |
| HTTPS smoke با `ROOT_CA_FILE` عمومی و حساب ساختگی | **7/7 PASS**: TLS، health DB، PWA/manifest، config no-store، anonymous401، create/read/archive، logout/revocation | TLS verification فعال؛ نصب Safari تأیید نشده |
| HTTPS بدون CA آزمون | exit1، `UNABLE_TO_VERIFY_LEAF_SIGNATURE` | آزمون منفی؛ قبول گواهی نامعتبر فعال نشد |
| دو backup هم‌زمان،16:28:45 | دو archive یکتا، هر دو `pg_restore --list` معتبر، mode600، فایل ناقص0 | نسخه رمزگذاری‌شده و خارج PC **UNVERIFIED** |
| فرزند: API HTTPS واقعی → sync create → independent read → pause/resume/stop → complete | task UUID پایدار، session1500ثانیه، completed؛ independent SQL پس از restart API: یک task version6 و یک session1500 | timestamps مطالعه ساختگی‌اند؛ مدرک مطالعه واقعی/تایمر روی گوشی نیست |
| مادر و پدر: Chromium151 با اعتماد عادی NSS به CA آزمون | ورود200، report200، JSON مجاز و UI فارسی RTL: تکلیف completed، ثبت25دقیقه، برنامه30دقیقه؛ یادداشت خصوصی در JSON نیست | دو profile مستقل روی یک ماشین؛ سه دستگاه فیزیکی **UNVERIFIED** |
| بستن و بازکردن هر دو profile والد | refresh200، report200 جدید، همان عنوان/status/25دقیقه/30دقیقه در UI؛ هر run22 درخواست همان origin، خطای شبکه/HTTP/browser و درخواست خارجی0 | body پاسخ tab بازیابی‌شده در CDP **UNVERIFIED**؛ JSON در اجرای fresh هر والد مستقل بررسی شد |

خروجی واقعی drill:

```text
DO
PASS synthetic PostgreSQL dump/restore: identity, family permissions, private task, paused study intervals and 12 migrations preserved.
```

خطاهای build اولیه پنهان نشده‌اند: image Flutter3.47.6 در registry Cirrus وجود نداشت؛ Dockerfile به commit رسمی Flutter pin شد. SHA-only checkout، SDK را `0.0.0-unknown` گزارش کرد؛ tag رسمی3.47.6 با همان SHA از GitHub fetch/verify شد. COPY فایل‌های checkout با permission600 به runtime غیرroot، خطای EACCES داد؛ COPY --chown=node:node اصلاح شد. web compile هنگام توسعه هم‌زمان خطا داشت؛ در retry بعدی واقعاً `✓ Built build/web` ثبت شد ولی مرحله بعد با `no space left on device` شکست خورد. داده/volumeها حفظ شدند. SDK host به دیسک جدا منتقل و cacheهای unused با مدیریت lead پاک شدند. این خروجی، build کامل Dockerfile اصلی یا gateway معتبر نیست؛ مسیر اصلی تا build موفق کامل **UNVERIFIED** است. مسیر prebuilt دقیقاً artifact واقعی Flutter را با همان gateway و Compose بسته‌بندی می‌کند و checker، SHA source/artifact و نبود CDN را می‌سنجد؛ stamp، build نیست.

## هویت خروجی نهایی و شواهد مرورگر

PWA نهایی با Flutter3.47.6، revision `5fc346839b5d0eef006ed8404392afb4dfae428d`، Dart3.13.5 از source ثابت ساخته شد؛ خروجی build واقعی، postprocess و Chromium artifact به‌طور جدا ثبت شده‌اند. provenance نهایی16:34:24UTC:

```text
source SHA256   a5fa7dec9e5f3069a3a1670425ec7f608c691a4b2a60142d19c8d57c7132054e
artifact SHA256 2d0f59639da289044db78b70d95a75fced7675b38d09d80c1e30c5cb60a90330
API image       958bf30e68a42201ac611104dbdc0c74f0cddd8cbeb39cf0af0a4edc501d52fc
gateway image   db6007599859f4c373aea88597b435f5fe0ec500fcf4148504b033ba4ae9303f
```

PostgreSQL16، Node22.23.3، nginx1.28.3 و Chromium151.0.7922.173 در اجرا استفاده شدند. migrationهای0011–0012 checksum دارند؛ در DB طول‌عمر آزمون، checksum تاریخی0001–0010 پیش از اضافه‌شدن ledger ثبت نشده و صریحاً **UNVERIFIED** گزارش می‌شود. drill تازه هر12migration را از source اجرا کرد. schema، JWT issuer/audience و نام repo تغییر نکردند.

مرورگر، gateway HTTPS واقعی را بدون intercept، mock یا ignoreTLS باز کرد. CA عمومی آزمون فقط به NSS محیط توسعه افزوده شد؛ این اجرای mkcert روی Windows یا نصب CA روی گوشی نیست. CanvasKit JS/WASM و فونت‌های فارسی/Latin/Emoji/Material/Cupertino همان origin بارگیری شدند؛ service worker واقعی فعال بود. fresh مادر22 و پدر23 درخواست داشت؛ هیچ درخواست خارجی، HTTP error، failed request یا page error مشاهده نشد.

تصویرهای [مادر](2026-10-08-stage0-mother.png) و [پدر](2026-10-08-stage0-father.png) فقط خانواده ساختگی را نشان می‌دهند. گزارش آشکارا زمان را «ثبت‌شده، گزارش شخصی و نه اثبات مطالعه» معرفی می‌کند. هر دو profile در process جدا بسته و باز شدند و refresh200 و report تازه دریافت کردند؛ JSON body اجراهای reopen به‌دلیل محدودیت CDP خوانده نشد و بررسی آن **UNVERIFIED** است. assertions واقعی UI عنوان تکلیف، completed،25دقیقه ثبت و30دقیقه برنامه را بررسی کردند؛ fresh JSON همان داده را مستقل تأیید کرده بود.

logs خصوصی ابزار در محیط توسعه حفظ شدند و secrets ندارند: `lifeguide-stage0-idempotent-final.log`، `lifeguide-compose-https-smoke-final.log`، `lifeguide-concurrent-backup-final.log`، `lifeguide-compose-restore-final-sms.log`، `lifeguide-real-https-{mother,father}-window-final.log` و `lifeguide-real-https-{mother,father}-window-resume-final.log`. وجود log جای اجرای دستگاه مالک نیست.

## مرز پذیرش

این بسته آنلاین محلی با یک API/DB مشترک است؛ این نتیجه پذیرش نهایی محصول نیست. اجرای حقیقی Safari/iPhone/Android و نصب/ارتقا، دسترسی بدون VPN از ایران، Windows/PowerShell/mkcert مالک، ایمیل/SMS واقعی، APK release امضاشده، hosting/DNS/live deploy، rollback زنده و migration داده واقعی **UNVERIFIED** هستند. provider پیامک در Compose نهایی غیرفعال بود؛ capabilities واقعی `smsAvailable:false` و `smsStatus:UNVERIFIED` داد. CA آزمون جای TLS عمومی محصول نیست.

پیش از داده واقعی، نقش runtime DB باید از superuser bootstrap جدا شود و backup رمزگذاری‌شده خارج PC با drill بازیابی آماده باشد؛ این دو gate در بسته فعلی حل نشده‌اند. داده سلامت/چرخه/روانی کودکان و AI خصوصی روی میزبان خارجی آزموده یا ارسال نشدند؛ consent/legal و محل داخلی نیازمند تصمیم جدا هستند. هیچ deploy زنده، DNS، حساب جدید، پرداخت یا انتقال واقعی در این مأموریت اجرا نشد.
