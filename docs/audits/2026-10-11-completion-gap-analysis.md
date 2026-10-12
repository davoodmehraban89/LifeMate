# ممیزی فاصله تا تکمیل LifeGuide — ۱۱ اکتبر ۲۰۲۶

این ممیزی فقط از خواندن فایل‌های مخزن تهیه شد. شاخه در زمان خواندن `feat/learning-content-operations` و HEAD برابر `fccc10e9604ae0c6b6b4aa8949b443fb90ca4b1c` بود. `AGENTS.md` و `PROJECT_STATE.md` ابتدا خوانده شدند. **هیچ تست، build، استقرار، بررسی دستگاه یا تغییر زنده در این ممیزی اجرا نشد؛ پذیرش تازه این فهرست UNVERIFIED است.** نتایج قبلی فقط از طریق اسناد شاهد معرفی می‌شوند، نه به‌عنوان اجرای این ممیزی.

## آنچه باید حفظ شود

پروژه دیگر APK با API نمایشی نیست. مسیرهای واقعی خانواده/سرپرستی، planner، session مطالعه، صف پایدار، مجوزهای فعلی، ثبت‌نام قابل بازیابی، پروفایل، دروس، کتابخانه، پیشرفت خصوصی، ارزیابی نسخه‌دار و بازخورد رضایت‌محور وجود دارند. PostgreSQL و Compose مشترک، نقش‌های مستقل دیتابیس، assets محلی، آدرس runtime و بسته تحویل هم موجودند. بازسازی این بخش‌ها اتلاف کار و خطر برگشت رگرسیون است.

شواهد قبلی در [وضعیت پروژه](../../PROJECT_STATE.md)، [ممیزی آموزش](2026-10-11-learning-verification.md) و [تحویل ۰٫۶٫۰](../operations/HANDOVER_0.6.0.md) قرار دارند. سبز بودن آن شواهد به‌تنهایی انتشار عمومی، پوشش یک سال آموزشی یا پذیرش واقعی موبایل نیست.

## فاصله‌های مشخص در کد

| بخش | موجود در کد خوانده‌شده | فاصله واقعی | بسته محلی قابل اجرا |
|---|---|---|---|
| اتصال اولین APK | Android با API قابل تنظیم، توضیح صریح صفحه، بدون default تأییدنشده | آدرس عمومی سازگار هنوز طبق آخرین سند تأیید نشده؛ ورود آنلاین به سرور نیاز دارد | حفظ setup، آزمون خطای HTML به‌جای JSON و گزارش قابلیت‌های سرور؛ اتصال عمومی فقط بعد از انتخاب/مجوز مالک |
| محتوای آموزش | `learning_catalog.js`، importer، gates SQL، کتاب/واحد/منبع و پخش درون صفحه | ۱۳۴۸ سرنخ ویدیو، **صفر ویدیوی واقعی با بازبینی کامل و صفر بانک سؤال واقعی منتشرشده**؛ سال چاپ دبیرستان تأییدنشده؛ پوشش واحدها کامل نیست | ابزار تهیه/اعتبارسنجی بسته بازبینی و انتشار/کنارگذاری کنترل‌شده؛ ابتدا یک درس کامل با شاهد واقعی، سپس گسترش |
| مدیریت محتوا | runtime API فقط SELECT روی تعریف کاتالوگ/سؤال؛ انتشار توسط gate دیتابیس محدود است | importer فقط draft وارد می‌کند؛ workflow قابل استفاده برای reviewer، revision، withdrawal و گزارش پوشش وجود ندارد | CLI محلی با نقش migrator موجود، dry-run، نسخه/هش و audit؛ از family admin برای platform curator استفاده نشود |
| بازخورد به توسعه | POST/GET/withdraw مالک با consent، rate limit و tombstone؛ جدول status دارد | هیچ route/CLI triage، brief تحقیق، خروجی قابل بازبینی مدیر یا انتقال انتخابی به agent وجود ندارد | گردش محلی صریحِ consented summary → triage → brief؛ بدون خصوصی‌خوانی، پیام خودکار یا deployment |
| مرور یادگیری | `/me/learning-attempts` و `/me/learning-reviews`؛ سرور پاسخ را تصحیح می‌کند | client فقط آزمون همان درس/نتیجه جاری را نشان می‌دهد؛ فهرست مرور موعددار و تاریخچه پذیرفته‌شده در UI دیده نشد | صفحه مالک برای مرور/تلاش‌ها، timestamps، انتخاب درس و pending acknowledgement؛ عدم ادعای mastery از یک نمره |
| هدف‌های یادگیری | `phase4.js` واقعاً create/read/update/archive مالک دارد | `Phase4Hub` فقط create/list/افزودن check-in را عرضه می‌کند؛ FutureBuilder خطای goals را نمایش نمی‌دهد، dialog نوشتن busy/error ندارد؛ edit/archive/history UI غایب است؛ POST mutation-id و PATCH expectedVersion ندارند | تکمیل client روی API موجود، محافظت دوبارکلیک و تاریخچه خصوصی؛ retry نامطمئن/صف آفلاین قبل از قرارداد idempotency/version تبلیغ نشود؛ CRUD سرور را دوباره نسازید |
| خانواده و سرپرستی | API rename/archive/remove member/activate/deactivate guardian با transaction و audit دارد | UI فقط ساخت/دعوت/list/set guardian؛ role/admin transfer فعال و list/revoke invitation API غایب‌اند | UI مدیریت قابلیت‌های موجود؛ بسته جدا برای lifecycle نقش/admin با invariant آخرین مدیر و لغو دسترسی فوری |
| حساب | ثبت‌نام ایمیل اختیاری/phone، verification/OTP/recovery/password/session موجود | route برای افزودن/تعویض تماس تأییدشده یا بستن حساب وجود ندارد؛ profile PATCH تماس‌ها را تغییر نمی‌دهد | طراحی/تست مستقل contact proof و closure غیرمخرب با لغو session، تعیین تکلیف آخرین مدیر و سیاست retention؛ حذف واقعی داده/اجرای زنده جداگانه |
| سال/نیمسال/زمینه زندگی | `life-contexts` list/create؛ سال و term create؛ `academic_year.active` و `life_context.active` | read یک مورد، edit و archive lifecycle سال/term/context وجود ندارند؛ term archived flag ندارد | owner-only lifecycle، نگهداری linked task/history، date containment و جلوگیری از نوشتن روی ancestor آرشیوی |
| صفحه مدرسه | overview، create assignment/exam؛ subject/class owner CRUD سرور موجود | UI subjectها فقط read-only، کلاس/تاریخ/teacher edit/archive ندارد؛ quickSetup فقط ریاضی و تاریخ Gregorian سپتامبر–ژوئن می‌سازد | school editor به‌جای setup ثابت؛ dates صریح، نمایش فارسی، استفاده از پروفایل/سال انتخابی؛ retry نباید سال/term تکراری بسازد |
| امتحان/نمره | assignment/exam با gradePoints/gradeOutOf و validation/version؛ report item نمره را نشان می‌دهد | SchoolPage فقط تعداد grades را نشان می‌دهد؛ grade history، subject/exam breakdown و rubric وجود ندارد | گزارش دقیق مبتنی بر داده ثبت‌شده و مالکیت؛ نمره مدرسه از quiz تمرینی و تأیید سرپرست جدا بماند |
| گزارش والد | گزارش مجوزدار واقعی، trend، task/status/time و grade در item؛ ۷/۳۰ روز در UI | query taskهای همه زمان‌ها را می‌خواند؛ `totalTasks/completedTasks/subjects` همه‌زمانه‌اند، درحالی‌که زمان ثبت‌شده محدود به بازه است؛ UI معنای دو بازه را توضیح نمی‌دهد | تصمیم روشن «کل کارها» در برابر «این بازه»، metricهای مجزای بازه/همه‌زمانه و تست boundary تهران؛ aggregation بر شناسه subject بهتر از نام مشترک |
| PWA آفلاین سرد | worker فقط public `assets/canvaskit/icons` را network-first cache می‌کند؛ API/config/auth/nav cache نمی‌شود | `index.html`، `main.dart.js` و bootstrap تضمین offline startup ندارند؛ `restoreSession` refresh آنلاین می‌خواهد | طراحی offline shell عمومی نسخه‌دار + صفحه قفل/وضعیت قابل اعتماد؛ token/مجوز از cache جعلی ساخته نشود، config شبکه معتبر حفظ شود |
| timer و sync | pause/resume/stop، interval و ACK، conflict، restart و durable queue موجود | event بعدی تا تأیید event قبلی محدود است؛ تجربه چند event آفلاین و cold restart با دستگاه واقعی باز است؛ UI correction/archive جلسه در `study_ui.dart` عرضه نمی‌کند | UX محدودیت صریح و صفحه تاریخچه/correction روی API موجود؛ گسترش چند event فقط با مدل causal/version و تست مستقل |
| accessibility | RTL و semantics اولیه وجود دارد؛ سند مرورگر dynamic progress semantics را حل‌نشده می‌داند | screen reader/physical touch/keyboard و همه breakpointها تأیید نشده‌اند | focused semantics regression، keyboard/touch target checks و سپس Android/Safari واقعی؛ screenshot تأیید screen reader نیست |
| انتشار | `ir.lifeguide.app`، Gradle جلوی debug release key را می‌گیرد؛ workflow دستی disabled | key مالک و actual release signing، APK upgrade روی دستگاه، public reachability و rollout تأیید نشده | نگه‌داشتن artifact تست؛ owner key در secrets و پذیرش واقعی بعد از آماده‌شدن، بدون انتشار خودکار |

فایل‌های مبنا: [server.js](../../backend/src/server.js)، [profile_router.js](../../backend/src/profile_router.js)، [auth_router.js](../../backend/src/auth_router.js)، [phase3.js](../../backend/src/phase3.js)، [phase4.js](../../backend/src/phase4.js)، [school_crud_router.js](../../backend/src/school_crud_router.js)، [study_sessions.js](../../backend/src/study_sessions.js)، [learning_assessment.js](../../backend/src/learning_assessment.js)، [main.dart](../../apps/lifemate/lib/main.dart)، [phase3_ui.dart](../../apps/lifemate/lib/phase3_ui.dart)، [phase4_ui.dart](../../apps/lifemate/lib/phase4_ui.dart)، [learning_quiz_ui.dart](../../apps/lifemate/lib/learning_quiz_ui.dart)، [dashboard_ui.dart](../../apps/lifemate/lib/dashboard_ui.dart)، [worker](../../apps/lifemate/web/lifeguide-sw.js)، [runtime_controller.dart](../../apps/lifemate/lib/runtime_controller.dart).

## اولویت و مالکیت بسته‌های اجرایی

این جدول تقسیم کار پیشنهادی است؛ تخصیص نهایی و integration با lead engineer است. هر بسته یک مالک اصلی دارد. `api.dart`، `main.dart`، `server.js` و شماره migration نقاط مشترک‌اند و فقط با هماهنگی lead تغییر کنند.

| اولویت/بسته | مالک اصلی/فایل‌های پیشنهادی | معیار پذیرش مستقل |
|---|---|---|
| P0: عملیات بازبینی و انتشار | Backend/content operations؛ فایل‌های جدید `backend/scripts/*learning*review*.js` و runbook محتوا | dry-run بدون mutation؛ draft پیش‌فرض؛ record ناقص/قدیمی/بدون rights رد شود؛ complete review با role جدا و synthetic fixture پذیرفته؛ runtime/parent نتواند منتشر کند؛ withdrawn منبع دیگر به learner عرضه نشود؛ history محفوظ |
| P0: یک مسیر آموزشی کامل | Product/research + reviewer مشخص؛ بسته evidence/سؤال محلی جدید، code ندارد مگر gate لازم | چاپ رسمی و صفحات/هدف روشن؛ رسانه کامل واقعاً مشاهده و timestamp-reviewed؛ تطبیق هدف، صحت، سن، حقوق نمایش؛ سؤال اصیل با توضیح و remediation بازبینی؛ lesson → quiz → spaced review → reopen، مستقل API/DB؛ هر بخش unrun، UNVERIFIED |
| P1: صفحه مرور و تلاش‌ها | Client education؛ فایل جدید `learning_reviews_ui.dart` و تست مربوط؛ wiring با root | only-own، empty/error/offline واضح؛ بازه زمانی و server timestamp؛ history پس از reopen از API؛ pending پاسخ duplicate نسازد؛ expiry مجوز را حذف کند و work unsent را نگه دارد؛ بدون نسبت‌دادن اثبات فهم |
| P1: triage توسعه رضایت‌محور | Backend operations؛ CLI/validator/brief template جدید؛ shared learning_feedback route فقط root | بدون رضایت/پس از withdrawal هیچ متن export نشود؛ خلاصه انتخابی و بدون contact/chat/health؛ export بعدی withdrawal را منعکس کند؛ وضعیت/نسخه و auditor ثبت؛ no send/no autonomous deploy؛ نسخه قبلاً صادرشده قابلیت magic revoke ندارد و runbook آن را بگوید |
| P1: تجربه goals/check-in | Client learning؛ ترجیحاً `learning_goals_ui.dart` جدید، adapter مشترک با root | create → reopen → read → edit → archive؛ API مستقل همان record؛ owner فقط؛ error دیده شود؛ double tap یک intent؛ notes check-in خصوصی؛ archive با تاریخچه linked check-in باقی بماند |
| P1: UI مدیریت خانواده | Client family؛ فایل جدید `family_management_ui.dart`، wiring با root | rename/archive/removal/revoke guardian روی API موجود؛ warning و server acknowledgement؛ revoked والد فوراً 403 و UI داده قبلی را پاک کند؛ آخرین مدیر 409، نه orphan family؛ lost response به موفقیت ساختگی تبدیل نشود |
| P2: lifecycle نقش/دعوت | Backend identity؛ router مستقل جدید + تست migration تنها بعد از تصمیم شماره توسط root | admin transfer atomic؛ آخرین active admin محفوظ؛ cross-family/teen/nonadmin رد؛ تغییر role رابطه guardian ناسازگار و outstanding invite را معتبر نگه ندارد؛ invitation revoke + expiry + accept race امن؛ اسناد audit |
| P2: lifecycle مدرسه | Backend school؛ router جدا یا `school_crud_router.js` و tests، شماره migration با root | owner read/update/archive context/year/term؛ nested dates معتبر؛ ancestor archive جلو create/edit جدید را بگیرد؛ homework/history/grade حفظ؛ outsider/guardian هیچ mutation؛ two-device stale write conflict |
| P2: editor مدرسه و گزارش دقیق | Client school و backend reporting با مالک واحد/کار sequential | انتخاب سال/term، ساخت/edit/archive درس/کلاس؛ setup retry duplicate نسازد؛ صفر/مفقود grade با شکست فرق داشته باشد؛ weekly/monthly metric با taskهای بیرون بازه و timezone boundary آزمایش؛ داده خصوصی وارد aggregate نشود |
| P2: offline cold shell | Cross-platform/security؛ worker/bootstrap/runtime config تحت یک مالک | actual compiled browser: warm install → close → offline reopen؛ فقط shell عمومی و وضعیت محفوظ، نه ورود جعلی؛ cache نسل قدیم به‌روزرسانی امن؛ config/HTTP auth از cache worker سرو نشوند؛ unsent bytes محفوظ؛ Safari همچنان پذیرش سخت‌افزاری جدا |
| P3: contact/closure | Backend identity/safety؛ طراحی/ADR سپس router + tests | verified proof جدید لازم؛ old channel تا تأیید جدید سالم؛ concurrent swap/OTP expiry/replay امن؛ closure لغو فوری session/guardian/grant؛ no orphan admin؛ retention/export/restore semantics پیش از حذف واقعی مشخص |

## محدودیت‌هایی که با کدنویسی محلی حل کامل نمی‌شوند

| نوع مانع | شرط لازم | کار مجاز در این محیط |
|---|---|---|
| مالک/سرور زنده | انتخاب میزبان قابل دسترس ایران، مجوز مشخص deploy/DNS/migration/merge/release | package، smoke، تست fixture، runbook، PR و شواهد؛ هیچ اقدام زنده |
| دستگاه/شبکه ایران | Android واقعی، iPhone/iPad Safari و A2HS، owner LAN/Windows، VPN-free کاربران ایران | Chromium/HTTP/SQL substitutes با محدودیت نام‌برده؛ هرگز معادل Safari/ایران اعلام نشود |
| امضا/تحویل واقعی | key/certificate مالک در secret manager، upgrade و داده‌های pending روی دستگاه | workflow gated و debug artifact؛ بدون key انتشار ادعا نشود و برای signer mismatch حذف data توصیه نشود |
| محتوای تدریس | دسترسی به آخرین چاپ رسمی، مشاهده کامل واقعی، حقوق embed و reviewer صلاحیت‌دار | ابزار، evidence checklist، shortlist و نمونه محدود واقعاً قابل بررسی؛ metadata را full review نام‌گذاری نکنید |
| AI/سلامت/حمایت کودک | رضایت سن‌متناسب، privacy/retention، محل نگهداری داخل کشور، safeguarding و بررسی متخصص | آموزش عمومی غیرتشخیصی، ADR/ports غیرفعال؛ no psychologist impersonation، no private-chat mining، no auto-parent-forwarding |
| پیامک/ایمیل/push | انتخاب provider و هزینه/eligibility/تحویل واقعی | adapter pluggable، unit/integration synthetic و error behavior؛ no signup/pay/message به فرد دیگر |

«تا انتها ادامه بده» مجوز توسعه لازم و برگشت‌پذیر است؛ جای مجوز صریح اقدامات زنده، خرید، انتشار، داده واقعی یا تغییر حساس دسترسی را نمی‌گیرد. هر بسته محلی باید کد/ابزار، آزمون مناسب و شاهد، مستندات و PR داشته باشد. تکمیل همه مقاطع، مشاوره خانواده یا نسخه operational تنها وقتی قابل گزارش است که شرایط واقعی همان قابلیت برقرار و آزمایش شده باشد.

## نکات تصمیم محصول

- School quiz در کد فعلی فقط multiple-choice با تصحیح server و توضیح است. chapter exam، پاسخ تشریحی با rubric، baseline تشخیصی، misconception/objective coverage و effectiveness pilot هنوز پیاده‌سازی کامل نیستند. در انتخاب روش از retrieval/spacing/feedback استفاده شود؛ برنامه ثابت ۱/۳ روز فعلی policy آزمایشی است، نه استاندارد واحد همه سن‌ها.
- خانواده یک workspace مجوزدار است؛ نقش والد/مدیر خانواده هرگز مجوز curator سراسری، private quiz history، گفتگو، سلامت یا data export نیست. اشتراک آموزشی جدید، مجوز و مدل داده صریح می‌خواهد.
- گزارش فعلی recorded duration را خوداظهاری می‌نامد؛ این مرز باید در reportهای جدید هم بماند. نمره مدرسه، پاسخ آزمون، confidence و تأیید شاهد نباید در یک «اثبات مطالعه» ادغام شوند.
- حلقه بازخورد محصول با support/safeguarding متفاوت است. disclosure کودک به‌صورت خودکار به brief مدیر، AI خارجی یا والد منتقل نشود؛ آن نیاز workflow بررسی‌شده جدا است.
- اول ابزار عملیات و یک بسته محتوای واقعاً تأییدشده؛ سپس گسترش. انتشار ۱۳۴۸ draft یا پرکردن بانک سؤال بدون بررسی، completion محسوب نمی‌شود.
