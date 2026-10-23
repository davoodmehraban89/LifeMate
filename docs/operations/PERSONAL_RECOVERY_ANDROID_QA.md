# راهنمای آزمون بازیابی Android — PR45 / B2

این بسته فقط **SYNTHETIC EMULATOR ONLY** است: آماده‌سازی گزینهٔ B در [ADR0018](../decisions/0018-offline-installed-data-rescue-options.md) و آزمون خیالی مجاز است؛ [طرح پذیرش](../superpowers/plans/2026-10-22-personal-recovery-android-acceptance.md) مرجع دامنه است.
داده یا کلید واقعی مالک، گوشی مالک، انتقال واقعی، merge، deploy، DNS و توزیع APK خارج این مجوزند. نصب موجود حذف یا clear-data نشود؛ هیچ تصمیم سیاستی یا انتخاب میزبان در این راهنما انجام نمی‌شود.

منبع عملکردی: `bdc97c8d95992385e91b40853d1c7a6c40c4c494`؛ پذیرش واقعی با دادهٔ خیالی در Android API35 در [اجرای 39914081997](https://github.com/davoodmehraban89/LifeMate/actions/runs/39914081997) **VERIFIED / PASS، complete** است.
گواه اجرای واقعی و شکست‌ها: [personal-recovery-android-2026-10-23.json](../audits/evidence/personal-recovery-android-2026-10-23.json). هماهنگ‌کننده ZIP رسمی را با digest تطبیق داد، تمام PASSها و hash هر دو PNG را بررسی کرد و هر دو تصویر واقعی را دید. این نتیجه مخصوص همین شبیه‌ساز/fixture است.
VERIFIED: محلی و CI، ۸۲ آزمون host، ۵۵ آزمون B1 و ۳۳۲ تست Flutter؛ analyze پاک، هشت حالت رد Gradle و تمام تطبیق‌های SQL/فیلد/بازگشایی/ارتقای QA موفق‌اند. بازبین و هماهنگ‌کننده نیز ۳۴۳ ترکیب واقعی shell را با صفر نتیجهٔ غیرمنتظره اجرا کردند. تاریخ fixture در ۲۰۲۴ است؛ خالی‌بودن «امروز» در تصاویر عمدی است.

## پیش‌شرط و ورودی ثابت

- فقط توسعه‌دهنده و AVD تازهٔ API35؛ هرگز گوشی مالک. پیش از هر تغییر adb: تأیید صریح دادهٔ خیالی، serial از نوع `emulator-N`، qemu، سخت‌افزار ranchu/goldfish، محصول SDK و نبود همهٔ packageهای LifeGuide لازم است.
- فایل اولیهٔ تحویلی از artifact `12292340083` اجرای `39480587450` گرفته می‌شود؛ **هرگز از نو ساخته یا با build مشابه جایگزین نمی‌شود**.
- [baseline ثابت](personal-delivered-baseline.json): package=`ir.lifeguide.app.device`، code=`9`، نام نسخه=`0.7.2-personal.1`؛ hash و certificate باید دقیقاً مطابق باشند. baseline و قفل تحویل APK تغییر نکنند.
- SHA256 APK: `c24ff6e75a987945399b0d96129f5d1a72525fa0270f31b0c481f9780f84db8e`.
- SHA256 certificate: `4ef990d647fc98ac41113d5dbe7ee476ba80bf95b71b5f219b7863fa95263391`.
- دو APK خصوصی QA با package=`ir.lifeguide.app.personal` و codeهای ۱۰ و ۱۱، با **همان کلید موقت آزمون** ساخته می‌شوند؛ این کلید، کلید مالک یا وعدهٔ ارتقای محصول نیست.
- Gradle opt-in، دو Dart define، target مخصوص QA و debug باید منطبق باشند؛ release/profile، هویت یا نسخهٔ نامنطبق رد می‌شود. پیش‌فرض `.app` و `.device` حفظ می‌شود.

## ترتیب پذیرش

۱. APK اصلی دقیق بدون overwrite نصب شود. تنها DB پیش‌فرضِ غایبِ نصب تازه، متعلق به همین harness و هنوز بازنشده با fixture بستهٔ B1 پر شود؛ DB جانبی مخصوص نمایش پذیرفته نیست.
۲. UI معمول برنامه باز شود و پروفایل خیالی دیده شود؛ خروج عادی انجام و نبود PID تأیید شود. `uninstall`، `clear-data`، `force-stop`، root و checkpoint مبدأ ممنوع‌اند.
۳. برداشت مبدأ فقط خواندنی است. نبود PID و **همان شکل cache بی‌اثر پیش و پس از خواندن** لازم است: بدون sidecar؛ یا WAL معمولی صفر بایت با SHM غایب/فایل معمولی (دو حالت) و بدون journal؛ یا journal معمولی صفر بایت بدون WAL/SHM.
۴. WAL/journal غیرخالی، symlink حتی شکسته، نوع فایل غیرعادی، SHM تنها، هم‌زمانی journal با WAL/SHM یا تغییر شکل cache رد می‌شود. برای سبزشدن آزمون هیچ فایل مبدأ حذف یا checkpoint نشود.
۵. فقط **کپی خصوصی فایل اصلی در میزبان** normalize شود؛ بایت‌های مبدأ ثابت بمانند. fixture سراسر مربوط به گذشتهٔ ۲۰۲۴ است: ۱ پروفایل، ۴ برنامه، ۳ ساعت هفتگی و ۴ نوبت؛ تمام فیلدها/شناسه‌ها و SQL مستقل، quick_check و foreign_key_check تطبیق داده شوند.
۶. roundtrip رمزدار احرازاصالت‌شدهٔ B1 در حافظه انجام شود؛ QA code10 کنار نصب اصلی نصب و تنها DB پیش‌فرض غایبش seed شود. هر دو برنامه عادی باز، بسته و دوباره باز شوند؛ دادهٔ کامل برابر و hash مبدأ قدیمی ثابت بماند.
۷. فقط QA با همان certificate موقت از ۱۰ به ۱۱ ارتقا یابد؛ این «آپدیت نصب قدیمی» نیست. هر دو برنامه دوباره باز/بسته شوند و تطبیق کامل DB و hash قدیمی تکرار شود.
۸. اعلان QA و مجوز OS خاموش بماند؛ رضایت یا shared preferences اعلان منتقل نشود. فایل UIAutomator با نام موقت متعلق به harness ساخته و پاک شود؛ dump به `/dev/tty` جایگزین نشود.

## دستورهای بازتولید

این دستورها را فقط در checkout منبع بالا و محیط توسعه اجرا کنید؛ dependencies فایل `requirements-personal-recovery.txt` و Flutter طبق [workflow](../../.github/workflows/personal-recovery-android.yml) آماده باشند. دستورهای بررسی محلی دقیق workflow:

```bash
cd apps/lifemate
dart format --output=none --set-exit-if-changed tool/personal_recovery_fixture.dart
flutter analyze
flutter test
python -m unittest discover -s tool -p '*_test.py' -v
cd ../..
python -m unittest discover -s scripts/tests -p 'test_recovery*.py' -v
```

ساخت خصوصی دو نسخه، کنترل manifest و رد واقعی ترکیب‌های ناامن دقیقاً طبق workflow انجام شود؛ هیچ APK خروجی برای کاربر ارسال نشود. پس از آماده‌شدن سه فایل و AVD تازه، فرمان harness خود workflow از `apps/lifemate` چنین است:

```bash
python tool/test_personal_recovery_android.py --serial emulator-5554 --original-apk build/original-delivered/LifeGuide.apk --qa-apk build/recovery-qa-10.apk --upgrade-apk build/recovery-qa-11.apk --acknowledge-synthetic-emulator-only --output exports/personal-recovery-android.json
```

فقط JSON پالایش‌شده و PNG حاوی رکورد خیالی upload شود؛ APK، SQLite/DB، آرشیو رمزدار، کلید و دادهٔ مالک upload نشوند. JSON، فاز شکست و تصاویر واقعی باید پیش از ادعای PASS بررسی شوند؛ شکست با حذف gate پنهان نشود.

## حدود اعتبار

گوشی فیزیکی، Windows، USB، ACL، قطع برق/دیسک پر، snapshot دارای WAL غیرخالی، دادهٔ واقعی، کلید مالک، اعلان روشن نصب قبلی و حذف اعلان تکراری، برنامه‌های فعال آینده و اجرای انتقال واقعی همگی **UNVERIFIED** هستند.
Doze، reboot، صدا/لرزش و UI رضایت واقعی مجوز نیز اثبات نشده‌اند. fixture گذشته، زمان‌بندی آینده را نمی‌آزماید؛ host mock، Android واقعی نیست.
این بسته **آمادهٔ production یا انتقال مالک نیست**؛ پایان موفق شبیه‌ساز هم مجوز عملیات واقعی یا توزیع ایجاد نمی‌کند.

## مرز تحویل

[CI عمومی39914082002](https://github.com/davoodmehraban89/LifeMate/actions/runs/39914082002) موفق است؛ مسیر تحویل APK شخصی39914082024 همچنان **BLOCKED** است: certificate متفاوت، code قدیمی افزایش‌نیافته و پذیرش آپدیت همان نصب موجود ناقص است. B2 نصب کناری/کلید موقت را می‌آزماید و این قفل را باز نمی‌کند. فایل APK جدید برای گوشی مالک تحویل نشده است.

Commit پایانی فقط راهنما/JSON/تصاویر خیالی است؛ تست کامل برای آن دوباره اجرا نشده و **UNVERIFIED** است. گواه کد، SHA عملکردی بالا را پوشش می‌دهد. تصاویر [نصب اولیه](../audits/evidence/personal-recovery-original-2026-10-23.png) و [QA پس از بازیابی](../audits/evidence/personal-recovery-qa-restored-2026-10-23.png) اسکرین‌شات واقعی شبیه‌سازند؛ نمایش همهٔ ردیف‌ها از مسیر منوی UI در این آزمون انجام نشده و داده با SQL مستقل بررسی شده است.
