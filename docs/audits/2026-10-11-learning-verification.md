# LifeGuide0.6.0 — شواهد آموزش و اتصال

تاریخ اجرا۲۰۲۶-۱۰-۱۱؛ شاخه `feat/aparat-learning-library` روی base `feat/online-family-stage0`؛ main و سرور زنده تغییر نکردند. آزمایش‌ها فقط داده ساختگی در محیط محلی دارند. این بسته مدرسه کامل/نسخه عملیاتی عمومی نیست.

## اجراهای واقعی و حدود ادعا

| اجرا | خروجی مشاهده‌شده | حد نتیجه |
| --- | --- | --- |
| Node22.23.3، PostgreSQL16، `node scripts/test.js` |۱۵۱/۱۵۱، شکست/لغو/skip صفر | هویت/خانواده قبلی + کتابخانه/پیشرفت/کوییز/بازخورد واقعی HTTP/SQL؛ رسانه واقعی بررسی کامل نشده |
| syntax + npm audit |۵۱ فایل بررسی؛۰ آسیب‌پذیری گزارش‌شده | scan ابزار، نه اثبات امنیت کامل |
| نقش محدود API، نصب تازه و تکرار |۱۵ migration و۱۵ checksum؛ خانواده۹/۹ و آموزش۱۵/۱۵ | fixtureساز با migrator جدا؛ API credential فقطخواندن کاتالوگ دارد |
| dump با backup read-only و restore با migrator |policy منبع/مقصد، تکرار ledger و جلسه ساختگی۶۰۰ثانیه موفق | روی دو DB برچسب‌دار تازه؛ مهاجرت واقعی/DNS انجام نشده |
| چهار ماتریس SQL |همه با ON_ERROR_STOP=1 موفق و rollback | جانشین مجوز، نه پذیرش دستگاه |
| Flutter3.47.6، analyzer، `flutter test` |No issues found؛۱۱۲/۱۱۲ موفق | fixtureهای UI/cache synthetic؛ مرورگر/دستگاه مستقل لازم |
| release web build |ساخت واقعی۴۶٫۸ثانیه؛ self_host/provenance۵۷ ورودی موفق | وب release build؛ APK release امضای مالک نیست |
| compiled asset probe |۱۴ درخواست،۰ خارجی/ناموجود/خطا؛ فونت و CanvasKit محلی | مبدأ HTTPS مصنوعی/intercepted؛ TLS واقعی از این آزمون اثبات نمی‌شود |
| guardهای Chrome Dart |۳/۳ موفق | Chromium؛ Safari/دستگاه UNVERIFIED |
| compiled instance/expiry |۸ حالت instance و حفظ دقیق صف پس از expiry مشاهده شد |بخشی intercepted؛ BFCache واقعی همچنان UNVERIFIED |
| TLS rejection regression |۵/۵، skip صفر | ورودی insecure نمی‌تواند PASS جعلی بسازد |
| Compose تازه واقعی |Postgres/API/nginxTLS/backup healthy؛۲۱۷ کتاب/۱۳۷۳ بخش/۱۳۴۸ ویدیو draft | کاتالوگ داده پژوهش؛۰ ویدیو/۰ بانک سؤال واقعی منتشرشده |
| HTTPS واقعی محلی |گواهی قبلی و CA منقضی رد شدند؛ با CA آزمایشی تازه TLS+health+PWA+config+auth موفق | CA عمومی به آزمون داده شد؛ پذیرش اعتماد دستگاه مالک UNVERIFIED |
| مرورگر با API/DB واقعی و HTTPS معتبر |۱۰/۱۰ بررسی؛۵۵ درخواست؛۰ خارجی/خطا؛ ورود+پایه+پیشرفت+withdraw+restart موفق | Chromium با داده ساختگی و کنترل semantic؛ لمس دستگاه/Safari و دسترس‌پذیری کامل UNVERIFIED |

خروجی ماشین‌خوان: [core receipt](evidence/learning-core-2026-10-11.json). لاگ‌های واقعی در `/workspace/scratch/learning-*`؛ هیچ فایل env/key/token/password در مخزن نیست. نتیجه scan فایل‌های tracked محدودیت ابزار را دارد.

## پذیرش مرورگر واقعی محلی

`scripts/test-learning-browser.cjs` واقعاً روی Compose جدا، HTTPS مورد اعتماد عادی و PWA ساخته‌شده اجرا شد؛ هیچ پاسخ API intercept، اعتبارسنجی TLS خاموش یا state برنامه تزریق نشد. [رسید۱۰ بررسی](evidence/learning-browser-2026-10-11.json)، [تصویر پیشرفت](evidence/learning-browser-2026-10-11-progress.png) و [تصویر پس از بازکردن دوباره](evidence/learning-browser-2026-10-11.png). هماهنگ‌کننده هر دو تصویر را دید: وضعیت «در حال یادگیری» و همان زمان ثبت سرور پس از restart باقی مانده‌اند. API مستقل و SQL نیز یک رکورد با version1/source=self_reported را تأیید کردند؛ refresh نشست HTTP200 بود.

پایه۱/چاپ۱۴۰۵–۱۴۰۶ از UI ذخیره و API مستقل خوانده شد. بازکردن درس پیشرفت خودکار نساخت؛ ویدیو draft نمایش داده نشد و بانک سؤال `{assessment:null,reason:review_pending}` ماند. بازخورد بدون رضایت هیچ POST نداشت؛ با رضایت HTTP201 گرفت. پس‌گرفتن HTTP204 و خواندن مستقل API/SQL، summary=NULL و consent=false را تأیید کردند. runtime واقعی۵۵ درخواست داشت، همه همان مبدأ؛ CanvasKit و فونت‌ها محلی و خطا صفر بود.

حدود این جانشین: به علت transformهای Flutter/RTL، کنترل‌های semantic با DOM click فعال شدند و متن با صفحه‌کلید وارد شد؛ آزمون لمس/اشاره‌گر واقعی نیست. متن پویا پیشرفت/زمان در تصویر دیده می‌شود ولی پس از تغییر در ARIA snapshot نبود؛ **محدودیت شناخته‌شده دسترس‌پذیری** است و این آزمون آن را اصلاح یا certify نمی‌کند. اجراهای قبلی harness روی انتظار ARIA یا fill بدون commit متن متوقف شدند؛ به‌عنوان PASS حساب نشده‌اند. اجرای نهایی با fixture تازه، متن keyboard/Tab و شواهد مستقل موفق شد. بستن/بازکردن Chromium پذیرش Android/Safari یا cold-start کاملاً آفلاین نیست.

## اصلاح‌های بازتولیدشده

- دروازه انتشار با `free_access=NULL` پیش‌تر دور می‌خورد؛ به true صریح و بازبینی کامل نسخه‌دار نیاز دارد. اصلاح چاپ/منبع کتاب یا بخش، خواندن/شمارش ویدیوی دارای بازبینی قدیمی را متوقف می‌کند.
- runtime ابتدا می‌توانست جدول کاتالوگ را بنویسد؛ RED مجوز42501 را انتظار داشت ولی constraint23502 دیده شد. اکنون کاتالوگ و بانک سؤال SELECT-only و جدول‌های آینده خواندنی پیش‌فرض‌اند؛ importer فقط migrator. قفل FOR SHARE کاتالوگ که به UPDATE نیاز داشت حذف شد؛ attempt snapshot مطابق خواندن سازگار لحظه پذیرش می‌ماند.
- GET دیررس بازخورد پس از DELETE می‌توانست خلاصه پس‌گرفته‌شده را دوباره نمایش دهد؛ widget RED بازتولید کرد، request epoch و snapshot بدنه ارسال اصلاح شدند، GREEN موفق.
- اضافه‌شدن بخش درس/متن اتصال، چهار تست UI را در viewport۶۰۰پیکسل یا label قبلی شکست داد. تست‌ها اکنون منوی واقعاً scrollشده را لمس می‌کنند و بعد از حرکت settle می‌شوند؛ assertionهای حفظ صف/ورود/عدم تکمیل خودکار تضعیف نشده‌اند.
- fixtureهای تست از داده واقعی جدا هستند؛ خطای serviceEnv در مرحله ادغام رفع شد. اجرای نهایی کامل۱۵۱ backend و۱۱۲ Flutter صفر لغو/شکست دارد؛ اجراهای شکست‌خورده موفق معرفی نشده‌اند.
- [CI اولیه38113435509](https://github.com/davoodmehraban89/LifeMate/actions/runs/38113435509) در backend ناموفق بود:۱۴۳ موفق،۸ لغوشده؛ محافظ fixture نام موجود دیتابیس ساختگی CI را نمی‌شناخت. [رسید اولیه](evidence/ci-learning-initial-2026-10-11.json) ساخت موفق وب/APK را جدا از شکست کل اجرا ثبت می‌کند. هماهنگ‌کننده همین خطا را روی دیتابیس محلی با نام دقیق CI بازتولید کرد؛ بعد از مجازکردن همان نام مشخص و حفظ شرط میزبان محلی، آزمون هدفمند۱۰/۱۰ و مجموعه کامل۱۵۱/۱۵۱ با صفر لغو/شکست موفق شد. این تغییر فقط آزمون است و احراز هویت محصول را تغییر نمی‌دهد. لاگ‌های RED/GREEN: `/workspace/scratch/learning-ci-guard-red.log`، `learning-ci-guard-green.log` و `learning-ci-guard-full-green.log`.

## آموزش هنوز نیازمند بررسی محتواست

۶۲ کتاب ابتدایی چاپ۱۴۰۵–۱۴۰۶ از صفحات رسمی بررسی شده‌اند؛ سال چاپ۱۵۵ کتاب متوسطه هنوز نامشخص است. فهرست۱۳۷۳ بخش می‌تواند page/video index باشد و برابر پوشش کامل اهداف/فصل‌ها نیست. ۶۹۹ منبع metadata_verified نیز **بازبینی تدریس ندارند**؛۵۸۷+۶۲ منبع دسترسی رایگان نامشخص دارند. هیچ منبع صرفاً با metadata منتشر نمی‌شود. تطبیق خط‌به‌خط و دیدن کامل هر ویدیو، حقوق/تناسب و بانک سؤال واقعی **UNVERIFIED**. منبع فعلی قاب فقط آپارات است؛ رشد/تلوبیون/فیلیمومدرسه پژوهش شده‌اند، adapter و حق embed آنها تأیید نشده است.

سناریوی۸گام خانواده در نقش API واقعی بازاجرا شده ولی پذیرش سه دستگاه، Android/Safari نصب/ارتقا و پخش کامل ویدیو هنوز UNVERIFIED. کوریکولوم فنی‌وحرفه‌ای/کاردانش، آزمون جامع، گزارش تشخیصی معتبر، اثربخشی آموزشی، ادمین محتوا/اعلان مالک/agentbrief و AI/مشاوره اجرا نشده‌اند. مرور۱/۳روز سیاست پایلوت است، نه تسلط یا زمان بهینه علمی.

## تحویل و اقدام مالک

علت درخواست URL و بررسی دامنه در [connection audit](2026-10-11-apk-connection.md). APK نصب‌شده بدون API مشترک فعال امکان ورود آنلاین ندارد؛ دامنه عمومی مسیرهای بررسی‌شده را به HTML قدیمی هدایت می‌کند. URL حدسی وارد نکنید. اکنون با نبود PC اقدامی لازم نیست؛ پس از دسترسی، [Stage0](../operations/STAGE0.md) و [بررسی محتوا](../operations/LEARNING_CONTENT.md) را با داده ساختگی دنبال کنید. ورود نشانی کامل HTTPS/API از مدیر و اعتماد گواهی LAN لازم است.

CI اصلاح‌شده روی source **`b3a62b76bf93697d050b896bc5f99ad6e8fb2f2f`** و PR merge `df2bb6e685e1868d3fe05d28cdcec24c38990e7b`: [run38148788571](https://github.com/davoodmehraban89/LifeMate/actions/runs/38148788571)، **هر سه job SUCCESS**. [رسید نهایی](evidence/ci-learning-final-2026-10-11.json):۱۵۱ backend، خانواده۹ و آموزش۱۵ با credential محدود،۱۵ ledger/checksum و restore؛۱۱۲ Flutter، تحلیل بدون خطا، web build۳۹٫۷ثانیه،۳ Chrome guard و۸ حالت compiled، حفظ صف expiry و checkout موفق. manifest واقعی APK برابر0.6.0/code5/ir.lifeguide.app و امضای Android Debug/v2 معتبر بود. این نتیجه نصب/ارتقای دستگاه، امضای release مالک یا سرویس عمومی را ثابت نمی‌کند.

- [APK آزمایشی داخل ZIP](https://github.com/davoodmehraban89/LifeMate/actions/runs/38148788571/artifacts/11706166986)؛ نام فایل `LifeGuide-debug.apk`. SHA256 فایل APK: `b96a8e168c1fe804dad12899df8a882a6a23de72e209aa585c3e6f2f1071c5d5`؛ hash ZIP متفاوت و در رسید است.
- [وب همین منبع با provenance](https://github.com/davoodmehraban89/LifeMate/actions/runs/38148788571/artifacts/11706251327). Artifactها در زمان بررسی منقضی نبودند؛ دانلود GitHub نیاز به دسترسی حساب مخزن دارد. لینک دانلود موقت گفتگو جای این مرجع پایدار نیست و تضمین عمر ندارد.

گواهی debug این build با run تاریخی37900944165 و build اولیه38113435509 متفاوت است؛ نصب‌شده مالک مستقلاً بررسی نشده و سازگاری upgrade آن UNVERIFIED است. حذف برنامه/داده برای حل خطای امضا توصیه نمی‌شود. `LifeGuide.apk` با کلید انتشار مالک ساخته نشده است. پیگیری مستندات و اسکریپت آزمون مرورگر پس از source فوق، ادعای CI جدید برای آخرین HEAD نیست؛ منبع برنامه/build همان source بررسی‌شده باقی می‌ماند.

استقرار/DNS/انتقال داده واقعی/merge/انتشار عمومی انجام نشده‌اند. artifact0.5.1 تاریخی با کد جدید سازگار نیست. [تحویل0.6.0 و فرمان‌های دقیق مالک](../operations/HANDOVER_0.6.0.md). کلید release، میزبان، SMS و پذیرش ایران به تصمیم/اقدام مالک و مجوز تغییر زنده نیاز دارند؛ رمز یا کلید در چت درخواست نمی‌شود.
