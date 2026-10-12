# LifeGuide — شواهد بسته 0.7.1 / کلاینت 0.7.0+6

تاریخ: 2026-10-12. شاخه `feat/learning-content-operations`؛ source آزموده و ساخته‌شده `0831ee6ba81a4811f819e8d8dbfe3f7b24a566ef`. [PR12](https://github.com/davoodmehraban89/LifeMate/pull/12) پیش‌نویس و روی PR11 است؛ هیچ merge یا تغییر زنده انجام نشد. commitهای بعدی مستندات و تست‌یار خواندنی، build تازه برنامه محسوب نمی‌شوند. داده تمام سناریوها ساختگی بود.

## اجرای واقعی

| اجرا | خروجی مشاهده‌شده | حدود اثبات |
| --- | --- | --- |
| Node22.23.3 / PostgreSQL16، `npm test` | `tests245, pass245, fail0`؛ 66.85ثانیه | API واقعی، نه گوشی |
| regression محدودیت NAT پس از محدودکردن guard محیط | `tests7, pass7, fail0`؛ سه guard منفی قبل از اتصال DB رد شدند | entrypoint واقعی، ساعت طبیعی، بدون reset پنجره |
| `npm run check` / `npm audit --audit-level=high` | 68فایل syntax، صفر vulnerability | کیفیت/امنیت کامل محصول را تضمین نمی‌کند |
| Flutter3.47.6 / Dart3.13.5، `flutter test` | 200/200، 56ثانیه | widget/unit، نه دستگاه واقعی |
| formatter/analyzer | 69فایل، صفر تغییر؛ `No issues found` | کد کلاینت ثابت مانده است |
| migration/import/repeat | 20/20checksum؛ repeat بدون تغییر؛ 217کتاب/1373بخش/1348نامزد DRAFT | صفر ویدیوی واقعی و صفر بانک سؤال واقعی منتشرشده |
| چهار ماتریس SQL | اجرا با psql واقعی کانتینر؛ PASS | شامل guardian/privacy/Phase3/Phase4 |
| نقش محدود runtime | family9/9 و learning/content/goals/family/school/report/locator96/96؛ 58منعSQL در source و restore | API فاقد DDL، capability/catalogue/publication audit فقط خواندنی |
| backup و restore | `PASS restored checksum ledger entries, migrator ownership/repeat, runtime denial matrix, guardian/private policy and paused-study600seconds` | dump فقط‌خواندنی، restore نقش migrator در DB تازه ساختگی؛ انتقال واقعی اجرا نشد |
| `flutter build web --release --no-web-resources-cdn --pwa-strategy=none` | build محلی56.8ثانیه موفق؛ fonts/CanvasKit محلی | build کامل SDK در Docker این محیط UNVERIFIED؛ مسیر prebuilt واقعاً ساخته شد |
| compiled runtime/resource/guards | 14request/0external؛ Web Locks8+8؛ Chrome3؛ expiry/queue preservation؛ worker4؛ provenance/Windows-checkout/tamper rejection PASS | برخی تست‌ها interception دارند و مدرک TLS نیستند |
| Compose محلی | API استاندارد Dockerfile و gateway prebuilt ساخته؛ api/postgres/gateway/backup healthy؛ 20checksum و صفر real-published مستقلSQL | پروژه جدا `lifeguide-learning-audit`، HTTPS loopback8445، نه میزبان مالک |
| smoke HTTPS | 7/7، گواهی و hostname واقعاً بررسی شد؛ homework create/read/archive، logout و رد token قبلی | [receipt](evidence/contentops-https-roundtrip-2026-10-12.json)؛ نصب Safari را اثبات نمی‌کند |
| کتابخانه با PWA کامپایل‌شده روی HTTPS | 14/14،90درخواست محلی، صفر browser/online error،4قطع عمدی آفلاین | [receipt](evidence/content-operations-browser-2026-10-12.json)؛ بدون interception یا TLS bypass |
| سه‌حساب خانواده روی HTTPS | پنج اجرای PWA،117درخواست محلی؛ homework/timer/completion و بازگشایی محفوظ | [receipt](evidence/contentops-family-real-https-2026-10-12.json)؛ فرزند از API، والدها Chromium profile مستقل |
| بعد از تعویض API به0.7.1 | 30درخواست HTTPS واقعی، سه حساب، caps/login/refresh و گزارش هر دو والد PASS؛ رکورد قبلی taskv6/session4sec محفوظ | [receipt](evidence/contentops-nat-https-2026-10-12.json)؛ این 30درخواست رسیدن به سقف429 را نمی‌سنجد؛ regression جدا آن را سنجید |
| CI نهایی | سه job SUCCESS؛ backend245، Flutter200، محدودیت نقش/restore و وب/APK واقعی | [run38201011644](https://github.com/davoodmehraban89/LifeMate/actions/runs/38201011644)، [metadata و خطوط خروجی](evidence/ci-content-operations-final-2026-10-12.json) |

لاگ‌های کامل محلی در `/workspace/scratch/contentops-*` و لاگ‌های CI در run پیوندشده‌اند. credential/token و متن fixture خصوصی به سند/مخزن کپی نشده‌اند. خلاصه بالا از خروجی واقعی است؛ صرف success یکی از jobها شاهد پذیرش چند دستگاه نیست.

## شکست‌های مشاهده‌شده و اصلاح

- اجرای نخست suite، قرارداد invite فعال را403 به‌جای409 داد؛ ترتیب اعتبارسنجی اصلاح و suite244/244 و سپس245/245 گذشت. دو widget test به‌علت Drawer طولانی پیش از scroll، کنترل تنظیمات را نمی‌دیدند؛ interaction تست اصلاح شد و assertions حفظ شدند. یک lint واقعی main اصلاح شد.
- ماتریسSQL ابتدا با psql میزبانِ موجودنبودن127 متوقف شد؛ با psql واقعی PG کانتینر اجرا شد. restore نخست به‌علت متغیر exportنشده شکست خورد؛ env خصوصی درست صادر و drill کامل دوباره گذشت، checksum migration دستکاری نشد.
- نخستین full run0.7.1 هنگام build هم‌زمان Docker vfs به `No space left on device / SQL53100` رسید. فقط کپی‌های image/build/archive متعلق به همین اجرا و بدون reference پاک شد؛ هیچ volume/داده/صف حذف نشد. پس از آزادسازی، full suite245/245 گذشت؛ این شکست پنهان نمی‌شود.
- نخستین browser learning run، label محاسبه‌شده AX را با newline literal مقایسه کرد. Chromium whitespace را normalize می‌کند؛ تست‌یار اکنون DOM exact و AX normalized را با وضعیت و timestamp کامل می‌سنجد، یک status و نبود duplicate را حفظ می‌کند. fresh synthetic run14/14 گذشت. دو تصویر درس/بازگشایی SHA یکسان دارند؛ تغییر بصری ساختگی ادعا نمی‌شود.
- تست خانواده هنگام بازگشایی429 واقعی نشان داد: `/v1/auth/capabilities` و refresh سقف مشترک حساس10/600 را مصرف می‌کردند.0.7.1 فقط GET دقیق capabilities را در120/60 و POST دقیق refresh/logout را در60/600 محدود می‌کند؛ register/login/recovery/resend/OTP همچنان10/600 هستند. مسیرهای نزدیک، case، روش اشتباه و XFF جعل‌شده strict باقی می‌مانند. JWT/Argon2id/tokenhash/rotation تغییر نکرده‌اند.
- پس از0.7.1 دو probe والد `net::ERR_ABORTED` داشتند؛ دو اجرای بعدی همان profile با refresh200 و گزارش completed موفق شدند، بدون ورود/توکن جدید یا reset. trace بعدی بعضی abortها را **پیش از teardown** ثبت کرد؛ نسبت‌دادن به بستن تست‌یار صحیح نیست. stream-probe موفق، `reader.cancel()` بعد از EOF را دید ولی علت شکست قبلی را ثابت نکرد. [receipt با شکست‌ها و حدود](evidence/contentops-parents-after-nat-2026-10-12.json). [بررسی مستقل و probe نهایی23درخواست](evidence/contentops-browser-abort-review-2026-10-12.json) نیز موفق بود، ولی رفتار reader.cancel بعد از EOF علت شکست قبلی را ثابت نکرد. علت نهایی UNVERIFIED؛ هیچ شکست شبکه‌ای globally ignore نشده و ادعای zero-error برای تمام probeهای بعد از hotfix وجود ندارد.

## پذیرش A–H و سناریوی هشت‌مرحله‌ای

| معیار | آنچه واقعاً اجرا شد | پذیرش واقعی باقی‌مانده |
| --- | --- | --- |
| A تکلیف فرزند و خواندن مستقل | HTTPS create ACK، GET مستقل و SQL: completed/v6، planned1800seconds | ثبت همین تکلیف در Android واقعی UNVERIFIED |
| B والد مجاز در PWA | مادر در compiled Chromium از حساب مستقل task planned را دید | Safari/A2HS UNVERIFIED |
| C تغییر بین حساب‌ها | completion فرزند، refresh پدر جدا و reportcompleted؛ SQL مستقل | دستگاه‌های فیزیکی UNVERIFIED |
| D بستن/بازگشایی و ماندگاری | هر دو parent browser profile بسته/باز و refresh؛ child refresh؛ رکورد پس از API image recreation باقی ماند | Android exit/upgrade و Safari process kill UNVERIFIED |
| E آفلاین و بدون duplicate | UI واقعی progress UUID پایدار را journal کرد؛ exactbytes پس از reopen عمومی آفلاین محفوظ؛ reconnect همان intent یک‌بار ACK، second sync duplicate نداشت | این run برای پیشرفت درس است؛ offline homework دستگاه واقعی UNVERIFIED |
| F والد نامجاز/خانواده دیگر | HTTP+SQL authorization matrix؛ owner-only goals/checkins/attempts و گزارش مجاز بدون private note | بررسی حقوقی و داده‌های wellbeing واقعی در دامنه این تست نیست |
| G pause/resume/exit/re-sync | تایمر actual-time: دو interval، pause، login مستقل جدید، resume/stop و replay بدون doublecount؛ 4ثانیه؛ drill fixture جدا600ثانیه | خروج برنامه Android و ادامه تایمر UI UNVERIFIED |
| H HTTPS Safari install/login/refresh | trusted HTTPS، compiled Chromium login/refresh، manifest/worker | Safari/iPhone/iPad/Add to Home Screen اجرا نشده: UNVERIFIED |

هشت مرحله به‌صورت **جایگزین نرم‌افزاری محدود** اجرا شد: تکلیف ریاضی توسط فرزند → مشاهده مادر → شروع/وقفه/ادامه/پایان session → گزارش مجاز → تکمیل → مشاهده پدر → بازگشایی profileهای مستقل و خواندن محفوظ. زمان API چهار ثانیه است؛ UI فعلی دقیقه صحیح نشان می‌دهد و زیر یک دقیقه را0 نشان داد. نمایش دقیق ثانیه و مطالعه واقعی اثبات نشده‌اند. child actions از HTTP API بودند؛ این شاهد اجرای هشت مرحله با سه گوشی نیست.

## بازبینی و کنترل تحویل

بازبین مستقل، diff محدود hotfix از `fcbaa12` تا `0831ee6` و تغییر تست‌یار AX را خواند؛ Critical/Important/Minor مشخصی گزارش نکرد. این بازبینی اجرای تست جدید یا بررسی تمام محصول نیست. کنترل نهایی tracked-secret/artifact scan، naming379case/0display item، `git diff --check`، parse7JSON، لینک23سند محلی و prebuilt66input/matching digest واقعاً گذشتند. checker لینک نخست source-excerptهای بریده inventory را به‌اشتباه لینک سند شمرد؛ با جداکردن فقط inventory تولیدشده از اسناد، targetهای واقعی بدون خطا تأیید شدند.

## فایل نصبی و گیت تحویل

[APK آزمایشی نهایی](https://github.com/davoodmehraban89/LifeMate/actions/runs/38201011644/artifacts/11725931941) و [PWA](https://github.com/davoodmehraban89/LifeMate/actions/runs/38201011644/artifacts/11725840928) تا2027-01-10 artifact گیت‌هاب‌اند؛ ممکن است ورود گیت‌هاب لازم باشد. ZIP APK واقعاً دانلود، integrity و تک‌ورودی `LifeGuide-debug.apk` بررسی شد. binary manifest مستقل PASS: `ir.lifeguide.app`،0.7.0/code6، labelفارسی، backupfalse، cleartextfalse. SHA APK: `b9b8599de796986cf2800ce24782ee85bc87a7d97889d2d194465f0ad4f07915`؛168960414bytes. CI واقعاً apksigner را اجرا و v2true اعلام کرد؛ apksigner محلی موجود نبود و اجرای محلی امضا UNVERIFIED است.

debugcertificate این run با runقبلی فرق دارد؛ upgrade روی نسخه قبلی ممکن است رد شود. حذف برنامه یا داده ارسال‌نشده راه حل تحویل نیست. کلید پایدار release مالک در secretmanager، امضای رسمی LifeGuide.apk و آزمون نصب/ارتقا هنوز UNVERIFIED هستند. APK جدید، API عمومی ایجاد نمی‌کند و CA LAN اختصاصی مالک در artifactCI وجود ندارد؛ [تحویل و مراحل مالک](../operations/HANDOVER_0.7.1.md) مسیر صحیح را توضیح می‌دهد.

ویدیوهای کامل بررسی‌شده/منتشرشده و بانک سؤال واقعی هنوز0 هستند. نمونه ریاضی `reviewRecord:null` و DRAFT است؛ ترجمه metadata به «آموزش کامل» مجاز نیست. مدرسه تطبیقی، امتحان تشریحی، آموزش خانواده، safeguarding و حقوق/رضایت تخصصی کودکان کامل نشده‌اند. AI/voice خارجی و سلامت/چرخه غیرفعال‌اند. Windows مالک، ایران بدون VPN، میزبان عمومی، ایمیل/SMS واقعی، releasekey و دستگاه‌ها UNVERIFIED. هیچ DNS، live deploy، real migration، merge نهایی، publicrelease، signup یا payment انجام نشد.
