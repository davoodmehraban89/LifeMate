# LifeGuide / لایف‌گاید — تحلیل اولیه شکاف نسخه آنلاین

تاریخ: ۲۰۲۶-۱۰-۰۸. این گزارش **پیش از پیاده‌سازی آنلاین جدید**، با خواندن source در `main` تهیه شده است. هدف جدید، Android و PWA والدین متصل به یک Node/PostgreSQL مشترک است. بسته محلی بدون Login، شاهد اشتراک یا Sync آنلاین نیست. نام‌های تاریخی `LifeMate`، مسیر `apps/lifemate` و قراردادهای موجود، فقط برای ارجاع دقیق حفظ شده‌اند.

## خط مبنا و شاخه‌های قابل استفاده

هماهنگ‌کننده headهای زیر را با GitHub تأیید کرده است؛ SHA کامل از refs محلی خوانده شد. این تأیید مخزن است، نه تأیید استقرار یا دسترسی از ایران.

| ref | head دقیق | وضعیت source و کاربرد |
| --- | --- | --- |
| `main` | `abdc9d9d032bc6746c8390b902a2e52d82991530` | مبنای این گزارش؛ Node/Postgres و Flutter دارای Login، شش migration و Feature 1 ایران در source وجود دارند. `PROJECT_STATE.md` ادعاهای تاریخی COMPLETE/READY مورخ ۲۰۲۶-۱۰-۰۵ دارد؛ پذیرش آنلاین جدید را ثابت نمی‌کند. |
| `feat/online-family-stage0`، هنگام ایجاد | `abdc9d9d032bc6746c8390b902a2e52d82991530` | worktree جدید `/workspace/LifeMate-online` از `main`؛ این سند، عکس خط مبنای آغاز کار است. |
| `fix/local-task-persistence` | `62e82baab96f742b86d4ef7bb886168039ddede5` | `LocalOnlyApi`، سند محلی، فرم‌های ویرایش/بایگانی و تست‌های ماندگاری/guard دارد. طراحی آن صریحاً device-only است؛ API، جدول و انتقال داده مشترک ایجاد نمی‌کند. اجزای فرم/اعتبارسنجی فقط با تطبیق قرارداد آنلاین قابل استفاده‌اند. |
| `fix/backend-request-safety` | `e5e3e4120af702c8b8430f35fd3f56d9e924e1c6` | اصلاح parser/CORS مشترک، خطای sanitized، auth حساب فعال و import بدون listener در commit مستقل `148c260e912dc220f862af27fbe4d34be226dfda` قابل استفاده است. head همچنین تغییر endpoint استیجینگ Railway دارد؛ برای Stage 0 جدید نباید تنظیم Railway یا کل شاخه محلی را همراه اصلاح Backend وارد کرد. |
| `infra/cloudflare-neon-migration` | `7a83ca86e72ef8f2c022188c860f9add4dc595c9` | افزوده‌های نسبت به main: `backend/src/worker.js`، `backend/wrangler.jsonc`، contract test و runbook. adapter از `cloudflare:node` و Neon URL استفاده می‌کند؛ Compose/Windows/LAN HTTPS ندارد و شاهد سرویس زنده نیست. |
| `final-feature-1/iran-family-school` | `71ee193e4b5a6ef39a5a4b5e5a2abbed8756023d` | diff فایل‌های `backend` و `apps/lifemate/lib` نسبت به main خالی است؛ پیاده‌سازی runtime Feature 1 از قبل در main موجود است. تست‌های Flutter این شاخه با main فرق دارند؛ شاخه runtime تازه‌ای برای ادغام نیست. |

## شکاف‌های عملیاتی و داده

| نیاز | آنچه در main واقعاً وجود دارد | شکاف برای پذیرش جدید |
| --- | --- | --- |
| Stage 0 مشترک روی Windows/LAN | `backend/package.json` با Node >=22 و `npm start → src/entrypoint.js`؛ migration runner و `backend/scripts/backup.sh`/`restore.sh`. `apps/lifemate/Dockerfile` فقط web/APK را می‌سازد و nginx روی HTTP:80 ارائه می‌کند. | Compose مشترک API/Postgres/web، volume داده، health/startup migration، HTTPS قابل اعتماد برای گوشی و Safari، تنظیم LAN/Firewall و راهنمای Windows وجود ندارند. Dockerfile و `publish-static.yml` به Railway وابسته‌اند. اجرای Compose روی Windows/LAN در این ممیزی **UNVERIFIED** است. |
| endpoint قابل تغییر در runtime | `HttpIdentityApi(baseUrl:)` قابلیت تزریق URL دارد؛ مقدار پیش‌فرض از `LIFEMATE_API_URL` در زمان build و سپس `http://localhost:8080` است (`apps/lifemate/lib/api.dart`). | رابط انتخاب/ذخیره/اعتبارسنجی HTTPS endpoint و پیکربندی runtime PWA وجود ندارند. localhost گوشی به سرور LAN اشاره نمی‌کند. تغییر server نباید token/cache حساب سرور قبلی را نگه دارد. |
| Android رسمی | `applicationId = com.example.lifemate`، label قدیمی و `release` با debug signing در `android/app/build.gradle.kts`. manifest اصلی main اجازه INTERNET ندارد؛ فقط debug/profile آن را دارند. | شناسه `ir.lifeguide.app`، label لایف‌گاید، INTERNET در release، keystore رسمی بیرون Git، secret CI، بررسی certificate و دستور ارتقای پایدار لازم‌اند. APK محلی `com.example.lifemate.localtest` یا گواهی debug شاهد release رسمی/ارتقای نصب قبلی نیست. |
| Auth واقعی و ماندگار | جدول‌های `app_user`، `auth_credential`، `auth_token` و `auth_session` در migrationهای 0001/0002؛ register/verify/login/refresh/reset/change/logout در `backend/src/server.js`. | tokenهای Flutter فقط field حافظه‌اند؛ شروع برنامه همیشه SignIn است. restore امن session، logout/پاک‌سازی cache، refresh هم‌زمان و شکست refresh نیاز به قرارداد و تست دارند. |
| تحویل ایمیل، شکست و ارسال مجدد | Resend/SMTP در `sendTransactionalEmail`. register ابتدا DB را commit می‌کند؛ در نبود provider، پاسخ `emailDelivery=pending_configuration` می‌دهد؛ خطای provider بعد از commit می‌تواند 500 بدهد. Flutter نتیجه تحویل را دور می‌اندازد و همیشه «ایمیل تأیید را بررسی کن» نشان می‌دهد. | endpoint و UI ارسال مجدد تأیید وجود ندارند؛ کاربر پس از شکست تحویل ممکن است حساب ساخته‌شده و ورود غیرممکن داشته باشد. وضعیت truthful، retry محدود، لینک روی PUBLIC_APP_URL صحیح و جلوگیری از افشای وجود حساب لازم است. تحویل ایمیل واقعی **UNVERIFIED** است. |
| درگاه شماره تلفن | auth/schema موجود بر email/password بنا شده‌اند. | phone normalization، OTP/provider port، وضعیت تحویل، انقضا، محدودسازی و تست provider موجود نیستند؛ SMS واقعی **UNVERIFIED** است. |
| تکلیف مشترک | `plan_item` در 0003؛ `POST/GET/PATCH /v1/plan-items` و family calendar در `backend/src/phase3.js`، HttpIdentityApi و فرم Planner/School. owner از session گرفته می‌شود و PATCH مستقیم owner-only است. | برای دید مادر/پدر، family و visibility مجاز باید در فرم و Backend یکسان باشند. اثبات مستقل HTTP → DB → client دیگر و ID پایدار در پذیرش جدید هنوز اجرا نشده است. |
| جلسه مطالعه واقعی | `kind=study_session` و `duration_minutes` در `plan_item`؛ گزارش هفته، مجموع duration موارد completed را می‌گیرد. | جدول/endpoint start/pause/resume/end و زمان ثبت‌شده مستقل از زمان برنامه‌ریزی‌شده وجود ندارند. UI «تمرکز» و انتخاب نوع مطالعه، timer ماندگار یا اندازه‌گیری زمان نیستند. app exit/resume، retry/idempotency و resync زمان باید تعریف و تست شوند. |
| تازه‌سازی سه دستگاه | GETهای today/planner/family/support-summary و بارگذاری اولیه/RefreshIndicator وجود دارند. | polling با lifecycle، لغو هنگام خروج، reconnect، freshness و نمایش وضعیت خطا/آخرین Sync وجود ندارند؛ جست‌وجوی source، Timer.periodic یا listener lifecycle برای این مسیرها نشان نداد. |
| Sync آفلاین دقیقاً یک بار | `OfflineStore` در SharedPreferences و `POST /v1/sync/mutations` با mutation ID، owner check، row lock و ثبت duplicate در `sync_mutation`. عملیات موجود update/complete/reschedule هستند. | mismatch واقعی source: `phase3_ui.dart:128,340` شناسه `microseconds-randomNumber` می‌سازد، ولی `sync_mutation.id` در 0003 از نوع UUID است و query duplicate در `phase3.js:613` آن را می‌خواند؛ این قالب UUID معتبر نیست. `flushQueue` شکست را می‌پوشاند. offline create و study session پشتیبانی نمی‌شوند. queue/cache بین حساب‌ها مشترک‌اند؛ append/remove، retry هم‌زمان، ID پایدار UUID، idempotency تراکنشی و conflict نیاز به اصلاح و آزمون دارند. |
| گزارش والد | `GET /v1/families/:familyId/children/:studentUserId/support-summary` و `ParentFamilyDashboard`/dialog؛ upcoming، completed7days، overdue، studyMinutes7days و gradePercent دارد. | planned/recorded جدا، امروز، درصد completion، trend هفته/ماه، subject/exam و freshness کامل نیستند؛ گزارش فعلی مطالعه اندازه‌گیری‌شده را نشان نمی‌دهد. |

## مسدودکننده‌های حریم خصوصی در source خط مبنا

- `backend/src/phase3.js`، مسیر support-summary: فقط `guardian_relationship.active` را می‌سنجد؛ membership جاری والد/کودک را join نمی‌کند و queryهای upcoming/metrics را با `can_view_plan_item` محدود نمی‌کند. بنابراین private items نیز می‌توانند در عنوان/آمار والد ظاهر شوند. مسیر school overview نیز پس از مجوز academic، workload را بدون visibility موردبه‌مورد می‌خواند. این رفتار باید در همه گزارش‌ها، نه فقط صفحه والد، بررسی شود.
- `backend/migrations/0003_planner_school_family.sql`، `can_view_plan_item`: sharing_grant را بدون شرط visibility فعلی و عضویت جاری می‌پذیرد؛ خصوصی‌کردن رکورد یا خروج عضو، به‌تنهایی grant قدیمی را بی‌اثر نمی‌کند. آزمون revocation و other-family لازم است.
- auth main وضعیت `app_user.disabled_at` را برای session جاری/refresh بررسی نمی‌کند؛ اصلاح محدود `148c260` این مورد، ترتیب Phase6 قبل از parser/CORS و raw error log را پوشش می‌دهد. این commit مجوز گزارش، guardian consent یا sharing revocation را اصلاح نمی‌کند.
- wellbeing/cycle در migrationهای 0004/0005 و routeهای phase4/phase6 وجود دارند، اما consent/feature gate مربوط به minor دیده نشد. owner-private cycle CRUD به معنی رضایت قانونی یا آمادگی محصول نیست. `providerGuide` با وجود AI_API_KEY/AI_BASE_URL/AI_MODEL می‌تواند به provider خارجی وصل شود؛ صرفاً نبود credential، feature gate صریح نیست. برای scope فعلی، wellbeing/cycle minor باید پشت gate باقی بمانند و AI/voice خارجی فعال نشوند.
- `apps/lifemate/lib/offline_store.dart` cache/queue را با user/server namespace تفکیک نمی‌کند؛ fallback UI همه exceptionها، از جمله خطای auth، را آفلاین تلقی می‌کند. این مرز باید پیش از استفاده چندحسابی/اشتراک دستگاه اصلاح و با عدم نمایش داده حساب قبلی تست شود.

## مسیر هشت‌مرحله‌ای خواسته‌شده

| مرحله | وضعیت در خط مبنا و شاهد لازم |
| --- | --- |
| ۱. کودک تکلیف ریاضی می‌افزاید | CRUD موجود؛ باید ID پاسخ با query مستقل DB و بازخوانی API تطبیق داده شود. **UNVERIFIED** برای Stage 0. |
| ۲. مادر تکلیف را می‌بیند | guardian/family source موجود؛ visibility و عضویت جاری باید در API برقرار باشند. مسیر parent report فعلی مسدودکننده حریم خصوصی دارد. |
| ۳. کودک جلسه را شروع می‌کند | start-session/timer واقعی موجود نیست. |
| ۴. کودک جلسه را تمام می‌کند | end/pause/resume و ثبت زمان واقعی موجود نیست. |
| ۵. زمان ثبت‌شده در گزارش مجاز والد ظاهر می‌شود | گزارش موجود زمان برنامه‌ریزی‌شده study_session completed را جمع می‌کند؛ شاهد مدت ثبت‌شده نیست. |
| ۶. کودک تکلیف را کامل می‌کند | PATCH status و sync complete موجود؛ idempotent retry و گزارش مجاز باید تست شوند. |
| ۷. پدر در دستگاه دیگر تغییر را می‌بیند | GET مشترک وجود دارد؛ polling/freshness و مشاهده دو دستگاه واقعی **UNVERIFIED** است. |
| ۸. هر سه دستگاه پس از restart داده را دارند | DB قابلیت ذخیره داده دارد، ولی token client حافظه‌ای است؛ restore/login/refetch و سه دستگاه واقعی **UNVERIFIED** هستند. |

معیارهای تکمیلی کاربر: A بررسی مستقل API/DB، B PWA والد مجاز، C polling چنددستگاهی، D restart، E offline Sync فقط یک‌بار با ID ثابت، F رد والد نامجاز/خانواده دیگر/private، G timer pause/resume/app-exit/resync، H Safari HTTPS/install/login/refresh. هیچ‌یک در این ممیزی read-only، به عنوان پذیرش runtime جدید پاس اعلام نمی‌شود.

## مرز شواهد و مرحله بعد

در این ممیزی تست، migration، Compose، deploy، ارسال ایمیل/SMS یا ساخت APK اجرا نشد. هماهنگ‌کننده گزارش کرده Docker Compose 2.40.3 در محیط فعلی کار می‌کند و فقط Postgres مصنوعی موجود است؛ این وضعیت، Windows میزبان کاربر یا شبکه ایران را تأیید نمی‌کند. فایل‌های تست موجود و گزارش‌های قبلی شاخه‌ها، جایگزین اجرای acceptance جدید نیستند.

PWA main، manifest standalone/RTL/icons و metaهای iOS دارد (`web/index.html`، `web/manifest.json`)؛ `docs/architecture/PWA_PLATFORM_CONSTRAINTS_V1.md` نیز محدودیت‌های browser storage/background و ضرورت آزمون Safari را ثبت می‌کند. Safari واقعی/Home Screen، اعتماد certificate روی iPhone، رفتار session پس از restart، دسترسی ایران و تحویل provider اکنون **UNVERIFIED** هستند. تست‌های HTTP/DB و مرورگرهای جایگزین باید نام جایگزین و این محدودیت را روشن ثبت کنند.

اولویت آغاز: استفاده انتخابی از commit اصلاح request safety، ساخت Stage 0 Node/Postgres/HTTPS و تنظیم runtime endpoint، سپس Auth ماندگار/تحویل، authorization همه read/write/reportها، مطالعه واقعی و polling/Sync و در پایان بررسی هشت مرحله و release رسمی. شاخه migration ابری یا APK device-only نباید به عنوان سامانه آنلاین تأییدشده معرفی شود. merge/deploy/public release در این ممیزی انجام نشده است.
