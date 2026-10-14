# LifeGuide / لایف‌گاید — وضعیت واقعی پروژه

## Supabase isolated QA workstream — 2026-10-15 (PREPARATION ONLY)

Owner approved evaluating a **separate Free Supabase organization `LifeGuide`** and synthetic-data QA project. This is **not** a new public deployment, a database migration, or a replacement for production hosting ADR 0009.

- Working branch: `infra/lifeguide-supabase-qa`, forked from the 0.7.1 test head `fix/study-duration-display`. No Flutter/Backend runtime code changed for this trial.
- Current connected Supabase account: existing unrelated Free organization `Finora` and two unrelated projects `Finora` (INACTIVE) / `EasyFactor` (ACTIVE_HEALTHY). Do **not** modify/reuse them.
- The connected Supabase tool cannot create organizations; owner must first create **LifeGuide / Free** manually in their dashboard. No new LifeGuide organization or project has been verified.
- After the independent organization appears, verify **$0** exact project cost through `get_cost` and available account-wide free-project quota before creating `LifeGuide-QA`. The two free active projects limit spans organizations; an INACTIVE label alone is not quota evidence.
- Node/Express/Argon2 and Supabase Edge Functions are not drop-in interchangeable; review DB roles/security and design minimal auth-safe prototype before deploying. No secrets or real child records in tests.
- Gate status: organization **BLOCKED on owner action**; cost check, new DB, deployment, Android/Safari/without-VPN Iran acceptance **NOT RUN**.
- Technical runbook: [Supabase QA bootstrap](docs/operations/SUPABASE_QA_BOOTSTRAP.md); [QA decision](docs/decisions/0011-supabase-free-qa-trial.md). Original 0.7.1 evidence below is unchanged.

Updated: 2026-10-12. Backend **0.7.1**; Flutter **0.7.1+7**. Branch **fix/study-duration-display**, stacked on **feat/learning-content-operations** at `e4cbc8bd37ee8d1c580a3b8ac33c3abfe6e269a3`. Main remains `abdc9d9d032bc6746c8390b902a2e52d82991530`. Repository remains `davoodmehraban89/LifeMate`; Android identity remains `ir.lifeguide.app`.

**نامزد آزمون با داده ساختگی؛ نسخه کامل عملیاتی یا انتشار عمومی نیست.** [ممیزی فاصله تا تکمیل](docs/audits/2026-10-11-completion-gap-analysis.md) مبنای این بسته است. جزئیات و خروجی‌های تاریخی0.6.0 در [checkpoint قبلی](docs/history/2026-10-11-project-state-0.6.0.md) حفظ شده‌اند؛ آن CI موفق، اجرای تازه این منبع نیست. [PR پیش‌نویس۱۲](https://github.com/davoodmehraban89/LifeMate/pull/12) روی۱۱ باز است؛و [PR13](https://github.com/davoodmehraban89/LifeMate/pull/13) اصلاح زمان روی۱۲ است؛۱۰،۱۱،۱۲ و۱۳ ادغام نشده‌اند.

## ادامه توسعه: دقت زمان، کلاینت0.7.1+7

source `d0b3446d736b67fdb4e0218282ad15f0e74fdb55`:4ثانیه اکنون4ثانیه و90ثانیه1دقیقه و30ثانیه در تمام ردیف‌های گزارش مجاز والد نشان داده می‌شود. UI باریکRTL320 پس از رفع overflow آزموده شد. Flutter212/212 و analyzerclean؛ worker4، وبrelease53.6ثانیه و gatewayprebuilt ساخته شد. PWA واقعی HTTPS از همان profile قبلی با23درخواست بدون خطای آن run،4ثانیه را نمایش داد و root SQL مستقل4ثانیه/دوinterval وtaskv6/completed را تأیید کرد. [شواهد اصلاح](docs/audits/2026-10-12-study-duration-verification.md). [CI38223988983](https://github.com/davoodmehraban89/LifeMate/actions/runs/38223988983) هر سه job SUCCESS؛ Backend245، role9+96/restore و Flutter212، وب و APK0.7.1/code7 ساخته و root دانلود/digest/manifest را بررسی کرد. [Receipt](docs/audits/evidence/ci-study-duration-2026-10-12.json)، [APK تازه](https://github.com/davoodmehraban89/LifeMate/actions/runs/38223988983/artifacts/11735469546). امضای debug تازه با قبلی متفاوت است؛ نصب/ارتقا/owner-release همچنان UNVERIFIED. مجوز و داده/API تغییر نکردند.

## بسته قبلی0.7.1 / کلاینت0.7.0+6

- عملیات بازخورد آموزشی: دسترسی صریح و قابل لغو مستقل از مدیر خانواده؛ فقط خلاصه‌ای که مالک با رضایت انتخاب کرده، triage نسخه‌دار و تهیه برنامه توسعه بدون متن خصوصی یا مشخصات مالک. پس‌گرفتن رضایت، خواندن/brief بعدی را متوقف می‌کند. ارسال خودکار به AI، پیام‌رسان یا agent و انتشار خودکار وجود ندارد.
- اهداف خصوصی: CRUD/بایگانی روی API/PostgreSQL، UUID پایدار، کنترل نسخه، صف بادوام و رسید معتبر؛ بازتاب یادگیری و تاریخچه از API خصوصی موجود. درخواست‌های legacy بدون idempotency پس از پاسخ نامعلوم فقط دوباره خوانده می‌شوند، نه خودکار نوشته.
- خانواده: مدیریت UI روی API واقعی، انتقال اتمی مدیریت، تغییر نقش و لغو دعوت با مجوز فعلی؛ لغو نقش/عضویت، اشتراک و سرپرستی ناسازگار را قطع می‌کند. نوع پروفایل مجوز نیست. سن ثبت‌شده، احراز هویت رسمی سن محسوب نمی‌شود.
- مدرسه: مدیریت زمینه/سال/نیم‌سال نسخه‌دار و بایگانی بدون حذف تکلیف/تاریخ؛ درس و کلاس از API موجود. تاریخ‌ها صریح انتخاب می‌شوند؛ راه‌اندازی ثابت و ساخت خودکار سال نمونه حذف شده است.
- مرور و گزارش: تاریخچه آزمون و مرور فقط برای مالک؛ گزارش مجاز والد با شمارنده‌های بازه مستقل از کل سابقه، زمان تهران، نمره مدرسه جدا از کوییز خصوصی و رفع fingerprint ناپایدار. خطای دریافت، داده قبلی را تازه معرفی نمی‌کند. زمان تایمر یا خوداظهاری اثبات مطالعه نیست.
- شروع آفلاین PWA: service worker فقط صفحه عمومی قطع اتصال ارائه می‌کند؛ API/config/auth یا داده خصوصی را به‌جای پاسخ شبکه برنمی‌گرداند. دسترسی آفلاین به برنامه احراز هویت‌شده پس از cold-start، quota/eviction و Safari هنوز UNVERIFIED هستند.
- ابزار محلی عملیات انتشار برای fixture ساختگی با credential جدا، dry-run، هش/نسخه/review gate و journal شناسه/هش؛ API حق انتشار ندارد. این ابزار مجوز انتشار درس واقعی یا تأیید بازبینی ویدیو نیست.

## آموزش واقعی و دامنه‌ها

Feature 1 ایران و Backend/خانواده/planner/offline queue/آزمون‌های مجوز main حفظ شده‌اند؛ LocalOnlyApi وارد نسخه آنلاین نشده است. موجودی تحقیق:217 کتاب،1373 بخش،1348 نامزد ویدیو؛ **ویدیوی واقعی با بازبینی کامل و منتشرشده:0؛ بانک سؤال واقعی منتشرشده:0**. نمونه اصیل ریاضی اول ابتدایی برای چاپ1405–1406 و چند کتاب متوسطه بررسی محدود مستند دارند؛ [گزارش و حدود بررسی](docs/research/2026-10-11-math-pilot-review.md). فایل draft ریاضی reviewRecord:null دارد. مشاهده کامل فیلم، حقوق نمایش، تطبیق همه صفحات، بازبینی متخصص و ارزیابی اثر یادگیری هنوز تکمیل نشده‌اند. metadata و امتیاز یک کوییز تضمین فهم یا یک سال مدرسه نیستند.

APK نصب تازه آدرس HTTPS **API فعال مشترک** می‌خواهد؛ default عمومی تأییدشده وجود ندارد. طبق [بررسی اتصال11اکتبر](docs/audits/2026-10-11-apk-connection.md)، app.lifeguide.ir هنوز HTML قدیمی ارائه می‌کرد و مسیرهای config/health/ready بررسی‌شده API JSON سازگار نبودند. بررسی خواندنی تازه12اکتبر فقط `/config.json` و `/api/health` راHTTP200/HTMLغیرJSON نشان داد؛ [receipt](docs/audits/evidence/public-api-paths-2026-10-12.json). این بررسی DNS یا تمام مسیرها نیست. هیچ DNS یا سرویس زنده تغییر نکرده است.

## اجرای بسته جاری

نسخه پایه0.7.0 واقعاً آزموده و ساخته شد: Node22/PG16 **244/244**؛ Flutter **200/200**، formatter69فایل/بدون تغییر و analyzer clean؛ syntax67فایل و npm audit صفر vulnerability؛20 migration checksumدار و repeat/import repeat؛ چهار ماتریسSQL؛ runtime family9/9 و learning/family/school/report96/96؛58 منعSQL هم در source و هم restore. backup با credential read-only و restore با migrator مستقل، تاریخچه و session600ثانیه را حفظ کردند.

release web محلی56.8ثانیه ساخته شد؛ fonts/CanvasKit محلی، تست compiled14request/zeroexternal، guards8+8، Chrome3/3، حفظ صف پس از expiry، checker/provenance و Windows-style checkout/tamper rejection موفق شدند. API استاندارد Dockerfile و gateway prebuilt واقعاً ساخته شدند؛ Compose با role محدود سالم است،20/20checksum و صفر محتوای واقعی published مستقلSQL تأیید شد. HTTPS round-trip7مرحله موفق شد. مرورگر واقعی HTTPS بدون interception/TLS-bypass **14/14**،90درخواست محلی و صفرخطا گذراند: ثبت/بازگشایی، AXstatus، feedback/withdrawal، آفلاین با حفظ exact bytes و reconnect یک mutation بدون duplicate. [Receipt](docs/audits/evidence/content-operations-browser-2026-10-12.json). تصویر اول و بازگشایی SHA یکسان دارند؛ root تصویر درس را بررسی کرد. در تست‌یار، نام AX محاسبه‌شده Chromium فاصله‌ها را normalize می‌کند؛ مقایسه صرف newline نادرست اصلاح شد، وضعیت و timestamp همچنان دقیق بررسی می‌شوند.

[CI بسته قبلی38201011644](https://github.com/davoodmehraban89/LifeMate/actions/runs/38201011644) روی source `0831ee6ba81a4811f819e8d8dbfe3f7b24a566ef`: هر سه job SUCCESS؛ Node245/245، Flutter200/200، syntax68 و audit0، role9+96 و restore موفق. [Receipt و خطوط خروجی](docs/audits/evidence/ci-content-operations-final-2026-10-12.json). root اجرای محلی0.7.1 را نیز با245/245 و regression7/7 مشاهده کرد. [گزارش کامل پذیرش A–H و شکست‌ها](docs/audits/2026-10-12-content-operations-verification.md).

APK واقعی **0.7.0/code6/ir.lifeguide.app** ساخته، manifest و debug-v2signature روی runner بررسی شد؛ root ZIP و APK را دانلود و digest/manifest مستقل تأیید کرد. [APK نهایی](https://github.com/davoodmehraban89/LifeMate/actions/runs/38201011644/artifacts/11725931941)، [وب](https://github.com/davoodmehraban89/LifeMate/actions/runs/38201011644/artifacts/11725840928). APK168960414bytes، SHA `b9b8599de796986cf2800ce24782ee85bc87a7d97889d2d194465f0ad4f07915`. debugcertificate با قبلی فرق دارد؛ نصب/ارتقا UNVERIFIED و حذف داده برای حل تفاوت امضا مجاز نیست. خروجی release امضاشده مالک هنوز ساخته نشده است.

آزمون خانواده سه‌حسابی HTTPS واقعی: تکلیف ریاضی → مادر در PWA → تایمر با pause/resume → گزارش → تکمیل → پدر جدا → بازگشایی نشست‌ها، پنج اجرای مرورگر117درخواست بدون خطای آن runهای موفق. اقدام فرزند از API بود، نه Android. SQL مستقل taskv6/completed/1800seconds برنامه و session4seconds/دوinterval را تأیید کرد؛ UI کلاینت قبلی زیر یک دقیقه را0 دقیقه نشان داد؛ در بسته جدید اصلاح شد و receipt قبلی تاریخی حفظ است. [Receipt](docs/audits/evidence/contentops-family-real-https-2026-10-12.json).

تست والد نقص429 هنگام reopen را آشکار کرد. اصلاح0.7.1 فقط GET دقیق capabilities و POST دقیق refresh/logout را در budgetهای محدود جدا نگه می‌دارد؛ ورود/بازیابی/ارسال همچنان سقف حساس10/600 دارند. 30درخواست HTTPS واقعی روی API role محدود و سه حساب موفق؛ task و report هر دو والد پس از تعویض image محفوظ بود. [Receipt](docs/audits/evidence/contentops-nat-https-2026-10-12.json). دو probe اضافی والد ERR_ABORTED داشتند؛ دو retry بدون تغییر/ورود تازه و probe ابزارشده بعدی موفق بودند. علت لغوهای قبلی UNVERIFIED و در گزارش حفظ است؛ ادعای بی‌خطایی همه probeها وجود ندارد.

## محدودیت‌ها و گیت‌های باز

- Android واقعی سه‌دستگاه، نصب/ارتقا با داده معلق؛ iPhone/iPad Safari و Add to Home Screen، لمس و screen reader: UNVERIFIED.
- Windows/LAN/mkcert مالک، شبکه ایران بدون VPN، انتخاب میزبان/پرداخت/KYC، ایمیل/پیامک واقعی و push پس‌زمینه: UNVERIFIED.
- امضای release با keystore مالک و انتشار LifeGuide.apk: UNVERIFIED. خروجی debug انتشار رسمی نیست؛ برای تفاوت امضا، داده ارسال‌نشده را حذف نکنید.
- حساب/contact/closure و سیاست نگهداری، آزمون تشریحی/rubric، سنجش تشخیصی و برنامه یادگیری تطبیقی، پوشش کامل کتاب‌های نظری/فنی‌وحرفه‌ای و آموزش خانواده هنوز کامل نیستند.
- AI/voice خارجی، سلامت/چرخه و مشاوره حساس کودک غیرفعال‌اند. رضایت/حقوق/نگهداری داخلی و safeguarding باید جداگانه طراحی و بررسی تخصصی شوند؛ هیچ استخراج گفت‌وگوی خصوصی یا ارسال خودکار برای والد/مدیر انجام نمی‌شود.
- Production/live deploy، DNS، انتقال داده واقعی، merge نهایی، انتشار عمومی، ثبت‌نام یا خرید مجاز نیستند و اجرا نشده‌اند. درخواست ادامه توسعه جای مجوز صریح آن اقدامات را نمی‌گیرد.

## راه تحویل و اقدام مالک

[تحویل0.7.1 و مراحل دقیق](docs/operations/HANDOVER_0.7.1.md)، [Stage0 رایگان](docs/operations/STAGE0.md)، [نقش‌های مستقل دیتابیس](docs/operations/DATABASE_ROLES.md)، [میزبانی](docs/decisions/0009-provider-neutral-hosting.md)، [نام‌گذاری](docs/decisions/0010-lifeguide-naming.md)، [مهاجرت داخلی و rollback](docs/operations/DOMESTIC_MIGRATION.md). مالک پس از دسترسی به PC/LAN آزمون‌های واقعی را اجرا می‌کند؛ تا آن زمان اقدام فوری لازم نیست. انتخاب سرور، DNS، SMS/email provider و key امضا خارج چت و پیش از هر تغییر زنده انجام می‌شود.
