# LifeGuide0.5.1 — شواهد جداسازی محلی

تاریخ:۲۰۲۶-۱۰-۰۹ UTC. شاخه `feat/online-family-stage0`، [PR10](https://github.com/davoodmehraban89/LifeMate/pull/10)، Backend0.5.1 و Flutter0.5.1+4. این گزارش فقط اجرای واقعی محلی/CI با داده ساختگی را ثبت می‌کند؛ نسخه کامل عملیاتی نیست.

## CI رفع‌شدهٔ منبع قبلی

درخواست rerun واقعاً انجام شد. [run37813595994 attempt2](https://github.com/davoodmehraban89/LifeMate/actions/runs/37813595994/attempts/2) روی `1c162a5` هر سه job را گذراند:۱۳۰ Backend،۶۴ Flutter، build/upload وب و debug APK. [receipt دقیق](2026-10-09-ci-billing-block.md). این اجرا، اصلاحات جدید0.5.1 را تأیید نمی‌کند.

## نشست، صف و مرورگر

- RED واقعی: پاسخ refresh نگه‌داشته‌شده، pagehide صریح، سپس reopen/401 روی client کامپایل‌شده باعث pending1→0 شد. API مصنوعی intercepted است؛ server refresh commit یا TLS/Safari واقعی ادعا نمی‌شود.
- GREEN واحد:۴ آزمون انقضای نشست، شامل401/403، حفظ payload/UUID، بسته‌شدن handle قدیمی، عدم replay حساب دیگر، یک replay همان حساب، و حذف عمدی logout/server switch.
- aggregate Flutter تازه: **۶۸/۶۸ PASS، صفر failure/skip**. analyzer clean؛ formatting unchanged.
- Dart guard در Chromium واقعی: **۳/۳ PASS، صفر skip**.
- bootstrap/Chromium gate:۸ حالت شامل رقابت startup، تب دوم بدون engine/auth/cache، background، close→retry، renderer crash پس از ثبت نشست، origin/profile مستقل و unsupported fail-closed. آزمون pagehide/pageshow مصنوعی با بازیابی واقعی BFCache یکسان نیست؛ BFCache حقیقی **UNVERIFIED**.
- خروجی تازهٔ frozen source در۰۶:۲۰:۵۳ واقعاً build شد: **۴۳.۰s PASS**؛ postprocess و traffic **۱۴ درخواست محلی، صفر external/missing/error**؛ compiled gate **۸ حالت PASS**؛ compiled expiry **pending1→1 و bytes بدون تغییر PASS**. probe مستقل نیز exit0 داد و SHA فایل‌ها قبل/بعد یکسان بود. همه پاسخ‌های API این browser regressionها مصنوعی intercepted هستند و شاهد TLS/backend واقعی نیستند.
- provenance در۰۶:۲۲:۱۶Z:۴۷ input، sourceDigest `1eeb1d833d63331e1a24a322836f8d9bf1f24205267e33286ff3a2349a6eff53`، artifactDigest `c6937cc01490dd289d09adc1e84a32824c720cb22d97a470e99e78fabd1cf1b0`؛ checker مستقل PASS. خروجی candidate قبلی شاهد اصلاح انقضا نیست.
- رسید local Flutter، tool session93519: `00:15 +68: All tests passed!`؛ session2265: `+3: All tests passed!` و `No issues found! (ran in2.1s)`. آزمون‌ها واقعاً اجرا شدند ولی output این دو run در فایل scratch ذخیره نشد. CI تازه receipt قابل مرور جدا خواهد داشت.

## PostgreSQL و عملیات

RED محلی نشان داد API قدیمی flags مدیریتی و مالکیت اشیا داشت. آزمون سبز fresh/runtime/restore با۱۲ migration تکرارپذیر و۹ آزمون HTTP/DB خانواده تحت credential runtime اجرا شده است. ماتریس ممنوعیت SQL، آیندهٔ grantها و dump فقط‌خواندنی/restore غیرsuperuser جدا هستند. اجرای نهایی guardهای ownership/auxiliary-schema،۱۷ منع SQL در هر DB با احتساب future-table،۱۲ checksum مقصد،۹/۹ سناریوی خانواده با runtime،۶۰۰ ثانیهٔ paused session و cleanup دو DB tagشده **PASS**. preflight، API/migrator مالک DB، مالکیت غیرpublic، PUBLIC/direct CREATE و auxiliary SECURITY DEFINER را پیش از تغییر رد کرد. helper adoption واقعی روی DB محلی ساختگی **PASS**؛ تلاش نخست روی identity-linked sequence با0A000 rollback شد و مالک/داده حفظ شدند؛ سپس انتقال از مالکیت جدول و بررسی sequence اصلاح شد. Archive خراب/بدون manifest/owner نامنطبق نیز رد شدند. هیچ volume برنامه drop/restore نشد. API موجود واقعاً `current_user=lifeguide_api` و همه super/createdb/createrole/bypassRLS/DB CREATE/TEMP/schema CREATE=false گزارش کرد؛ snapshot task1/version6/completed و session1/1500/completed پیش/پس دقیقاً یکسان ماند. ledger تاریخی۱۰ ورودی NULL checksum دارد؛ گواهی گذشته‌نگر ایجاد نشد. چهار service فعلی PG/API/nginx/backup healthy شدند.

root واقعاً `npm run check` اجرا کرد: **۴۱ source/script/test file بررسی نحوی شد**. `docker compose config --quiet`، bash syntax چهار script، Python compile checker APK، YAML سه job و `git diff --check` exit0 دادند. این موارد جای آزمون PostgreSQL یا اجرای workflow نیستند.

دیسک محیط پر شد؛ فقط BuildKit cache بلااستفاده و imageهای dangling غیرمتصل پاک شدند. imageهای rollback برچسب‌دار، containerهای متصل، تمام volumeهای PG/backup، SDK، source و شواهد حفظ شدند. فضای آزاد واقعی ازصفر به۹.۱GB رسید. image دقیق قبلی `958bf30` به‌صورت dangling حذف شد؛ image قدیمی0.5.0 نگه‌داشته‌شده `eb3ac05` در container مستقل با **۲۶ hash فایل API/migration برابر source جاری** تأیید شد. بازگشت اجرایی به این image در این بسته **UNVERIFIED** است؛ حفظ دقیق image اولیه ادعا نمی‌شود. هیچ cleanup دادهٔ برنامه اجرا نشد.

## PWA فعلی روی API واقعی

روی gateway تازهٔ0.5.1+4، با Chromium151 و trust عادی NSS، ورود مادر و گزارش مجاز واقعاً۲۰۰ دادند.۲۳ درخواست هم‌مبدأ، صفر external/failed/browser/HTTP error؛ JSON server و رابط واقعی تکلیف completed و۱۵۰۰ ثانیه ثبت‌شده/۱۸۰۰ ثانیه برنامه را تأیید کردند و یادداشت خصوصی در گزارش نبود. [receipt غیرمحرمانه](evidence/stage0-parent-report-0.5.1.json) و [تصویر بررسی‌شدهٔ RTL](evidence/stage0-parent-report-0.5.1.png).

اجرای نخست به‌علت حذف قبلی CA در navigation شکست خورد؛ فقط CA عمومی آزمون LifeGuide موقتاً به NSS اضافه شد و اجرای معتبر بعدی PASS شد. همان CA پس از پایان حذف و چهار CA عمومی قبلی محیط حفظ شدند؛ هیچ ignore-TLS، interception یا تغییر گواهی دستگاه مالک در این پذیرش به کار نرفت. این run login تازه است؛ restart مادر/پدر با refresh واقعی در receipt0.5.0 ثبت شده و برای0.5.1 مستقلاً تکرار نشد، بنابراین پذیرش restart دستگاه فعلی **UNVERIFIED** است.

## CI source تازه

منبع `7c4ca78ffe55ce37d0b94984c205b6ba592cf722` واقعاً push و [run37893432018](https://github.com/davoodmehraban89/LifeMate/actions/runs/37893432018) آغاز شد. Backend job113699263054 و security113699262752 با conclusion=success پایان یافتند؛ log Backend۱۳۰/۱۳۰ اصلی،۹/۹ runtime family،۴۱ syntax file، audit0، failclosed preflight و restore۱۲checksum را نشان می‌دهد. Flutter job113699262974 نیز success پایان یافت. output واقعی `🎉 68 tests passed.`، `+3: All tests passed!`،۸ حالت compiled instance، pending1→1 با bytes برابر و۱۳ درخواست محلی/صفر خارجی CI را نشان داد؛ host۱۴ درخواست داشت. مرحلهٔ دریافت/بررسی مرورگر۱۲m۵۴s طول کشید، سپس موفق شد؛ run متوقف یا تغییر داده نشد.

APK واقعاً در۰۶:۴۵:۱۴Z build و در۰۶:۴۵:۲۱Z upload شد. checker روی خود فایل باینری **PASS**: `ir.lifeguide.app`، label«لایف‌گاید»، versionName0.5.1/code4، minSDK24/target36، debuggable=true، allowBackup=false، usesCleartextTraffic=false و INTERNET=true. `apksigner verify --verbose --print-certs` خروجی `Verifies`، v2=true و certificate DN=`C=US, O=Android, CN=Android Debug` داد. این امضای معتبر debug است؛ release رسمی نیست.

- [LifeGuide-web](https://github.com/davoodmehraban89/LifeMate/actions/runs/37893432018/artifacts/11600220473): ZIP18,932,576bytes؛ digest archive `d7acfe7d619a47c077167a982f582337e821b26db4507bf88fe7920b5e236c42`.
- [LifeGuide-debug-apk](https://github.com/davoodmehraban89/LifeMate/actions/runs/37893432018/artifacts/11600076483): ZIP86,928,494bytes؛ digest archive `71954bddac25cacf29b9f2115b62de8eb576c763d4e5e26495b0e98c0d8add1f`.
- SHA256 خود APK: `0b23e4fa242b0ee5e35186e49537bcf67c2753211e33aa3d69789576aba0f044`. certificate SHA256: `3179f7325a42b6f5de9a85699e54097075886e48e974fdcd511f6eb6447cdd41`. digest ZIP با digest APK/certificate یکی نیست. [receipt خوانا](evidence/ci-0.5.1.json).

commit تحویل پس از این منبع فقط مستندات/تصویر/receipt و `[skip ci]` دارد؛ CI روی آخرین head ادعا نمی‌شود. diff backend/app/deployment/scripts نسبت به منبع آزموده‌شده باید خالی بماند.

## فرمان‌ها و رسیدهای محلی

```bash
flutter test
flutter test --platform chrome test/web/instance_guard_browser.dart --reporter expanded
flutter analyze
node tool/test_web_instance.cjs --compiled build/web
node tool/test_web_session_expiry.cjs --artifact=build/web
bash scripts/test-db-roles.sh --synthetic-only
```

Flutter commandها از `apps/lifemate` و shell role command از root repo اجرا شدند. Logs این محیط: `/workspace/scratch/lifeguide-dbrole-green-final.log`، `review-web-refresh-preserve-red.log`، `review-web-refresh-preserve-green.log`، `online-quarantine-final-browser-expiry.log` و `online-quarantine-final-web-provenance.json`. این مسیرهای scratch، artifact منتشرشده یا فایل در Git نیستند. تست‌های خصوصی با credential مصنوعی در env اجرا شدند؛ secret در گزارش ثبت نمی‌شود.

## ممیزی metadata بیرون از Git

در fetch رسمی GitHub، description مخزن در۲۰۲۶-۱۰-۰۹ هنوز `LifeMate — Personal, Family & Learning Companion` بود. **target setting: user-facing — change**؛ نقل‌قول این گزارش فقط شاهد تاریخی مشاهده‌شده است. این تنظیم بیرون PR است و توسط تیم تغییر نکرد؛ اقدام دستی مالک فقط اصلاح description به LifeGuide، بدون rename مخزن/URL/DB/JWT است. naming inventory تولیدشده شامل تمام خطوط legacy در متن‌های tracked است؛ metadata خارجی اینجا جدا طبقه‌بندی شد.

## گیت‌های باز

CI source تازه و manifest/signature debug روی runner تأیید شدند؛ دریافت مستقل APK در این محیط باForbidden متوقف شد و download/extract/install روی دستگاه همچنان **UNVERIFIED** است. بسته وب تازه با receipt بالا build و در gateway نهایی بسته‌بندی شد. HTTPS smoke واقعی در۰۶:۲۴:۲۶Z **۷/۷ PASS**: chain/hostname معتبر، health متصل به DB، PWA HTML/manifest، config same-origin/no-store،401 ناشناس، ایجاد/خواندن مستقل/آرشیو و رد token پس از logout. این شاهد Node TLS/API واقعی است؛ نصب Safari نیست. Android/Safari/Windows واقعی، Add to Home Screen، BFCache حقیقی، VPN-free Iran، ایمیل/SMS واقعی، release مالک، backup رمزگذاری‌شده خارج PC و تغییر نقش روی میزبان زنده همچنان **UNVERIFIED**. هیچ live deploy، DNS، مهاجرت داده واقعی، merge، خرید، signup یا public release انجام نشده است.

برای آزمون مالک: [Stage0](../operations/STAGE0.md)، [نقش‌ها و adoption صریح](../operations/DATABASE_ROLES.md)، [مهاجرت/rollback](../operations/DOMESTIC_MIGRATION.md). صف حفظ‌شده فقط پس از ورود تأییدشده همان حساب/API در دسترس قرار می‌گیرد. بستهٔ آنلاین قبلی و پذیرش A–H با حدود واقعی در [گزارش پذیرش](2026-10-08-online-acceptance.md) باقی است.
