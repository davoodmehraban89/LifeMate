# LifeGuide — گزارش پذیرش بسته آنلاین Stage 0

تاریخ: ۲۰۲۶-۱۰-۰۸ UTC. شاخه `feat/online-family-stage0`، Backend **0.5.0**، Flutter **0.5.0+3**. PR: [#10](https://github.com/davoodmehraban89/LifeMate/pull/10). main مبنا `abdc9d9d032bc6746c8390b902a2e52d82991530` است. فقط داده ساختگی روی محیط توسعه و Docker محلی استفاده شد؛ deploy زنده، DNS، انتقال داده واقعی، merge و انتشار عمومی انجام نشدند.

## اجراهای واقعی

| اجرا | خروجی مشاهده‌شده | دامنه اعتبار |
| --- | --- | --- |
| migration روی PostgreSQL16 تازه | `applied 0001` تا `0012` | هر ۱۲ migration واقعاً اجرا شدند؛ runner، DDL و ledger را اتمی ثبت می‌کند |
| Backend نهایی با Node22.23.3 | `tests 130; pass 130; fail 0; skipped 0`; ۳۸٫۴۶ ثانیه | API/DB واقعی، auth/privacy/version/overlap، سناریوی مستقل، SMS adapter و جداسازی env؛ env والد عمداً production/webhook مصنوعی بود و runner آن را حذف کرد |
| چهار فایل `*schema_test.sql` | exit0، transaction/DO/ROLLBACK موفق | identity/family/planner/learning/Feature 1 ساختار و مجوزها |
| `npm run check` و `npm audit --audit-level=high` | بررسی نحو موفق؛ `found 0 vulnerabilities` | زمان اجرای audit؛ گواه نبود همه آسیب‌پذیری‌ها نیست |
| Flutter نهایی، analyze + full test | `No issues found!`; ۶۴/۶۴؛ در CI نیز full test موفق | HTTP/native-channel/preferences آزمون‌ها synthetic هستند؛ سخت‌افزار واقعی نیستند |
| `dart format --output=none --set-exit-if-changed lib test` | `33 files (0 changed)` | licenseهای upstream عیناً حفظ و از whitespace انتهای خط مستثنا هستند |
| Flutter3.47.6 / Dart3.13.5 build web | `57.5s`; `✓ Built build/web` | خروجی release وب؛ APK یا Safari نیست |
| browser request check روی artifact کامپایل‌شده | ۱۴ درخواست؛ صفر external/missing/error | HTTPS origin ساختگی با response interception، service worker مسدود؛ **TLS واقعی را اثبات نمی‌کند** |
| تست یادآوری با HTTP و query مستقل PG | ۱/۱ موفق | create/update/retry/reschedule/complete/archive؛ IDs و schedule بدون تکرار |
| Compose، TLS، backup و restore | [شواهد مجزا](2026-10-08-stage0-verification.md) | نتایج واقعی gateway و مرورگر با اعتماد عادی از تست artifact جدا هستند |

خروجی‌های خام در محیط اجرا: `lifeguide-root-final-migrate.log`، `lifeguide-root-final-backend-130.log`، `online-web-tehran-final-build.log`، `online-web-tehran-final-browser.log` و `planner-reminder-regression.log` در `/workspace/scratch/`. `lifeguide-root-final-flutter.log` بازاجرای ۶۳ آزمون قبل از افزوده گزارش روز تهران است؛ نتیجه نهایی ۶۴ آزمون از اجرا/CI جدید گرفته شد. این مسیرها secret، داده واقعی یا artifact رسمی انتشار نیستند.

**CI واقعی موفق:** [run 37810558847](https://github.com/davoodmehraban89/LifeMate/actions/runs/37810558847)، commit **`7d9366832adaaab4cc3f24ef4d928fddd307fdc9`**. هر سه job Backend/security/Flutter موفق شدند: migration تکرارپذیر، چهار SQL matrix، ۱۳۰ تست، backup/restore با client16، format/analyze/۶۴ تست Flutter، web build و بررسی درخواست مرورگر. مرورگر CI، **۱۳** درخواست واقعی روی origin ساختگی و صفر external/missing/error ثبت کرد؛ اجرای host،۱۴ درخواست داشت. provenance و هر دو artifact واقعاً upload شدند.

- [LifeGuide-debug-apk](https://github.com/davoodmehraban89/LifeMate/actions/runs/37810558847/artifacts/11565283053): ZIP حدود۸۷MB، فایل `LifeGuide-debug.apk`، **کلید debug و فقط آزمایشی**؛ ساخت واقعی در log `✓ Built .../app-debug.apk` ثبت شد. metadata/signature باینری مستقل و نصب دستگاه **UNVERIFIED** هستند.
- [LifeGuide-web](https://github.com/davoodmehraban89/LifeMate/actions/runs/37810558847/artifacts/11563914781): ZIP حدود۱۹MB، web کامل و provenance برای مسیر prebuilt.

تلاش دانلود این artifactها از اتصال رسمی، file reference تولید کرد؛ دریافت URL فایل در محیط shell با HTTP error مسدود شد. صحت digest دانلود محلی، استخراج APK و دریافت APK از gateway محلی **UNVERIFIED** است. artifactها از run بالا برای مالک در GitHub در دسترس‌اند؛ این انتشار عمومی نیست. فایل release رسمی `LifeGuide.apk` ساخته نشده است.

یک اجرای ابتدایی عامل هنگام افزودن جداسازی env با cwd نادرست، پیش از اصلاح runner انجام شد و شکست خورد؛ ممکن است یک درخواست احرازنشده با credential کاملاً مصنوعی به Resend فرستاده باشد. نبود ترافیک خارجی آن اجرا **UNVERIFIED** است؛ پیام/کلید واقعی استفاده نشده و ادعای تحویل ایمیل ندارد. runner نهایی EMAIL/SMS/AI ارث‌رسیده را حذف می‌کند؛ خروجی تمیز و بازاجرای مستقل ۱۳۰/۱۳۰ مرجع این تحویل‌اند.

**به‌روزرسانی ۲۰۲۶-۱۰-۰۹:** commit مستندات/helper `1c162a5` در [run 37813595994](https://github.com/davoodmehraban89/LifeMate/actions/runs/37813595994) پیش از تخصیص runner/اجرای هر step با محدودیت پرداخت یا سقف هزینه حساب GitHub متوقف شد. تست/build روی این head **UNVERIFIED** است؛ این شکست، نتیجه آزمون کد نیست. [پیام دقیق و مسیر بدون پرداخت](2026-10-09-ci-billing-block.md). diff کد برنامه/Backend/deployment نسبت به `7d93668` خالی بررسی شد؛ CI موفق بالا شاهد همان منبع است. تنظیم حساب، پرداخت و افزایش سقف هزینه انجام نشده‌اند. اصلاح نهایی فقط مستندات است و `[skip ci]` دارد، پس موفقیت CI روی آخرین head ادعا نمی‌شود.

## ماتریس A–H و سناریوی هشت‌مرحله‌ای

| معیار | شاهد اجراشده | آنچه هنوز UNVERIFIED است |
| --- | --- | --- |
| A: ثبت تکلیف فرزند | `online_acceptance.test.js`: entrypoint واقعی، POST authenticated، بازخوانی مستقل HTTP و query مستقیم PostgreSQL | ثبت از Android واقعی |
| B: مشاهده والد مجاز در PWA | مادر و پدر با ورود مستقل Chromium، API/report200 و UI واقعی تکلیف completed، ثبت۲۵دقیقه/برنامه۳۰دقیقه؛ private note در JSON/UI نیست | Safari و PWA نصب‌شده |
| C: تغییر در یک دستگاه و مشاهده دیگری | سه client مستقل API؛ تکمیل کودک در گزارش مادر/پدر با polling واقعی دیده شد | سه دستگاه فیزیکی و شبکه ایران |
| D: بستن و بازکردن | دو restart کامل Node؛ داده PG/refresh هر سه حساب؛ بستن/بازکردن هر دو profile مرورگر با refresh200، report200 تازه و همان داده UI | Android lifecycle/upgrade و نصب Safari؛ body JSON tab بازیابی‌شده در CDP خوانده نشد |
| E: آفلاین و sync بدون تکرار | قطع واقعی HTTP، journal حفظ‌شده و replay یک UUID فقط یک رکورد DB؛ Flutter FIFO، durable enqueue، ACK خراب، conflict و cache scope آزموده شدند | airplane mode و storage واقعی روی دستگاه |
| F: مجوز و داده خصوصی | خانواده دیگر، guardian لغوشده، عضویت پایان‌یافته، private task/note/session و grant انتخابی در تست‌های read/write رد شدند | penetration test مستقل و ارزیابی حقوقی |
| G: تایمر | pause/resume و restart API؛ دو interval با مجموع ۱۵۰۰ ثانیه، retry بدون double-count؛ Flutter StudySync/recovery آزموده شد | exit/re-sync واقعی Android؛ زمان تایمر مدرک مطالعه نیست |
| H: HTTPS/Safari/install/login/refresh | HTTPS واقعی Compose، trust عادی گواهی و آزمون منفی CA، ورود/refresh واقعی Chromium، همه درخواست‌ها همان origin | Safari/iPhone/iPad و Add to Home Screen **UNVERIFIED** |

سناریوی مستقل `backend/tests/online_acceptance.test.js` واقعاً تکلیف ریاضی کودک، مشاهده مادر، شروع/وقفه/ادامه/پایان مطالعه، گزارش مجاز مدت ثبت‌شده، تکمیل تکلیف، مشاهده پدر و بازیابی سه حساب پس از restart را اجرا کرد: **۹/۹** با nested assertions. test-only proof token برای ایمیل است؛ تحویل پیام واقعی را اثبات نمی‌کند. نرخ‌های IP در این harness افزایش یافته‌اند تا assertions مجوز به‌علت بودجه آزمون متوقف نشوند؛ rate-limitهای تولید در آزمون‌های مجزا سنجیده می‌شوند. کل سناریو هنوز پذیرش سه دستگاه واقعی نیست.

## تغییرات قابل تحویل

- استفاده از هسته سالم main و Feature 1؛ مقایسه و reuse شاخه‌ها پیش از توسعه در [ممیزی](2026-10-08-online-gap-analysis.md).
- PostgreSQL مرجع رکوردهاست: planner CRUD/archive، UUID/version/idempotency، profile category مستقل از نقش خانواده، خانواده/دعوت/guardian، اهداف و check-in آموزشی خصوصی، درس/کلاس و بایگانی امن.
- study session/interval/event واقعی، جلوگیری از تداخل و تکرار، activity timestamps/source، تأیید فقط با guardian مجاز؛ گزارش‌ها فقط داده‌های مجاز را جمع می‌زنند و خوداظهاری را مدرک تلقی نمی‌کنند.
- ثبت‌نام عمومی با status/body یکسان برای حساب موجود/جدید، شکست ایمیل پس از commit بدون 500، resend محدود، proof/reset رمز، token hash و refresh rotation؛ مقاومت در برابر enumeration زمانی **UNVERIFIED**، port SMS صریحاً اختیاری.
- Android API settings و endpointهای جایگزین انتخابی، وب `config.json` no-store، secure refresh session، cache/queue جدا برای endpoint+user؛ conflict نیازمند انتخاب روشن است و payload محلی در journal بازیابی می‌ماند.
- RTL والد، freshness/error، polling، اطلاع‌رسانی داخل برنامه با port؛ فونت‌ها/CanvasKit/iconهای LifeGuide محلی، شناسه Android `ir.lifeguide.app`، guard کلید release واقعی.
- Compose یک مبدأ، PostgreSQL خصوصی، TLS، migration، cron backup، deploy محلی idempotent، smoke شبکه و restore drill؛ workflow استقرار/امضای release پیش‌فرض خاموش، بدون انتشار خودکار.

## محدودیت‌ها و گیت‌های انتشار

1. **این بسته نسخه کامل عملیاتی یا release رسمی نیست.** Safari/Android/Windows مالک، نصب و ارتقا، دسترسی بدون VPN ایران، TLS دستگاه و پذیرش سه‌دستگاهی اجرا نشده‌اند.
2. SMTP/SMS واقعی انتخاب یا ارسال نشده‌اند؛ adapter عمومی SMS قرارداد webhook دارد و جای adapter اختصاصی carrier منتخب نیست. بدون delivery تنظیم‌شده، کاربران جدید pending هستند؛ fixtureهای verified فقط آزمون محلی‌اند.
3. کلید انتشار مالک موجود نیست؛ `LifeGuide.apk` رسمی ساخته/امضاشده نیست. APK debug واقعاً در CI ساخته شد، اما جای کلید رسمی یا پذیرش دستگاه نیست.
4. Dockerfile کامل SDK در این محیط با snapshot/دیسک fail شد؛ build کامل آن **UNVERIFIED** است. مسیر prebuilt همان source واقعاً buildشده را با provenance بررسی می‌کند؛ نتیجه Compose جدا ثبت است.
5. API در Compose فعلاً از PostgreSQL bootstrap role استفاده می‌کند؛ تفکیک role migration/runtime با حداقل privileges، پیش از داده واقعی گیت سخت‌سازی است. backup volume محلی، خودکار رمزگذاری/off-PC نمی‌شود؛ export امن و restore دوره‌ای لازم‌اند.
6. تغییر contact/بستن حساب، انتقال مدیریت خانواده و تغییر نقش عضو فعال API کامل ندارند. life-context/year/term قدیمی عمدتاً create/read هستند؛ UI کامل CRUD درس/کلاس/check-in و گزارش تفصیلی امتحان/نمره هنوز نیاز به تکمیل دارد.
7. service worker فقط assetهای عمومی را cache می‌کند؛ API/config/auth cache نمی‌شوند. نصب/تازه‌سازی Safari، cold-start کاملاً آفلاین و eviction/quota دستگاه **UNVERIFIED** هستند. محافظ write در Android و mutex درون runtime وجود دارد؛ هماهنگی cache/token بین tabهای هم‌زمان وب پیاده/آزموده نشده است، پس این candidate فقط با یک tab/PWA فعال در هر browser profile آزمون شود. event مطالعه ارسال‌نشده قبل از ادامه تایمر باید ACK بگیرد.
8. AI/voice خارجی خاموش‌اند؛ health/cycle/اطلاعات روانی کودک پشت feature gate خاموش‌اند. رضایت/سن/قانون/retention و نگهداری حساس داخل کشور صرفاً flag شده‌اند، پیاده یا تأیید حقوقی نشده‌اند.
9. تست امنیت/نحو/dependency audit شاهد محدودی از این نسخه است؛ مقاومت کامل در برابر همه حملات، timing indistinguishability و availability عمومی ادعا نشده است.

## اقدامات دقیق مالک

1. ابتدا با داده ساختگی [Stage 0 روی Windows/LAN](../operations/STAGE0.md) را اجرا کنید: IP ثابت PC، Docker/Node/Flutter مشخص، mkcert، اعتماد **گواهی عمومی** روی دستگاه، فایروال محدود Private/LocalSubnet؛ سپس build/postprocess/provenance و `-PrebuiltWeb`. هیچ حساب میزبانی یا خرید لازم نیست.
2. سه حساب fixture را فقط روی DB تازه آزمون بسازید و A–H/هشت مرحله را با Android فرزند و Safari هر والد اجرا کنید؛ نتیجه با زمان و وضعیت VPN ثبت شود. credential/token/کلید را در chat/log عمومی نگذارید.
3. [smoke شبکه](../../scripts/reachability-smoke.mjs) را از شبکه داخل ایران با TLS معتبر اجرا کنید؛ هر `PASS` فقط همان check را ثابت می‌کند. round-trip بدون مجوز نوشتن fixture و credential برابر **UNVERIFIED** است.
4. hosting عمومی را خودتان انتخاب کنید؛ پیشنهاد اصلی LAN رایگان و fallback سرور داخلی **از قبل در اختیار شما** است. VPS خارجی فقط تحقیق است؛ payment/KYC/دسترسی ایران تأیید نشده. هیچ signup/پرداخت انجام ندهید صرفاً به اتکای جدول قیمت. DNS و deploy زنده مجوز جدا می‌خواهند: [ADR](../decisions/0009-provider-neutral-hosting.md).
5. کلید Android را محلی و پایدار تولید/backup کنید و تنها در secret manager/workflow environment امضا تنظیم کنید؛ فایل کلید و رمز در Git یا chat نباشد. applicationId تغییر نمی‌کند؛ debug به‌عنوان release استفاده نشود.
6. SMTP یا carrier SMS را خودتان تعیین کنید؛ webhook تنها با `SMS_PROVIDER=webhook` و URL HTTPS/token در `.env` خصوصی فعال می‌شود. API carrier، هزینه، اقامت/قرارداد و ارسال به handset تا آزمون explicit **UNVERIFIED** می‌مانند.
7. انتقال داخلی و DNS cutover فقط بعد از تصمیم/مجوز: [runbook](../operations/DOMESTIC_MIGRATION.md) شامل write freeze، pg_dump/restore، env/image version، صحت permissions، cutover و rollback با حفظ هر دو backup است. drill داده ساختگی جای انتقال داده واقعی نیست.
