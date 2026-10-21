# LifeGuide / لایف‌گاید — وضعیت واقعی پروژه

## بازیابی رمزدار ساختگی روی رایانه — ۲۰۲۶-۱۰-۲۱؛ آمادهٔ بررسی در PR44

[PR44](https://github.com/davoodmehraban89/LifeMate/pull/44)، شاخهٔ `feat/personal-encrypted-recovery` بر PR43، منبع `29fa2c7247847c4eadb7792daaa91379dd0f2367`: ابزار QA با fixture واقعی SQLite1، آرشیو AES-256-GCM/Scrypt، اعتبارسنجی schema/هدر/رابطه و بازیابی بدون overwrite اضافه شد. source فقط خوانده می‌شود؛ DB بدون marker ساختگی پیش از بدنه رد می‌شود. این marker اثبات منشأ نیست. ابزار، ورودی backup مالک یا انتقال گوشی نیست و کلاینت/Backend/شناسه/امضای محصول را تغییر نمی‌دهد.

**VERIFIED:** محلی55 آزمون بازیابی و60 آزمون host قبلی، demo واقعی close/reopen با1پروفایل/4برنامه/3ساعت هفتگی/4نوبت؛ تطبیق تمام فیلدها و SQL مستقل، ماندن hash مبدأ، رد رمز اشتباه/فایل دستکاری‌شده/مقصد موجود. review مستقل دو ایراد FIFO/race را بازتولید کرد؛ اصلاح و تکرار هر دو موفق بود. CI اختصاصی [39673314234](https://github.com/davoodmehraban89/LifeMate/actions/runs/39673314234) و39673386588 روی همان منبع موفق؛55+60 و demo اجرا شدند. scan فقط tracked/high-confidence است، audit کامل تاریخچه نیست. [دستور/خروجی](docs/audits/evidence/personal-synthetic-recovery-2026-10-21.json)، [راهنمای فارسی](docs/operations/PERSONAL_SYNTHETIC_RECOVERY.md).

**UNVERIFIED:** نصب کناری/ارتقای app تازه روی Android، کلید ثابت واقعی مالک، گوشی/Windows/USB/ACL، snapshot دارای WAL و دوام قطع برق/دیسک پر واقعی. ورودی WAL/SHM/journal یا هدر WAL رد می‌شود؛ چیزی پاک نمی‌شود. CI عمومی39673386647 هنگام ثبت این بخش هنوز درحال اجرا بود؛ نتیجهٔ آن ادعا نمی‌شود. APK تازه تحویل نشد. گام بعد آزمون جدا روی شبیه‌ساز تازه با همان APK اولیه و دادهٔ خیالی است؛ هیچ عملیات دادهٔ واقعی، merge/deploy/DNS مجاز/اجرا نشده است.

## آماده‌سازی بازیابی رمزدار — ۲۰۲۶-۱۰-۲۱؛ فقط دادهٔ ساختگی تأیید شد

مالک گزینهٔ B در [ADR0018](docs/decisions/0018-offline-installed-data-rescue-options.md) را **فقط برای آماده‌سازی و آزمون ساختگی** تأیید کرد. [برنامهٔ اجرا](docs/superpowers/plans/2026-10-21-personal-encrypted-recovery.md) در شاخهٔ `feat/personal-encrypted-recovery` بر PR43 است. کد محصول، نصب موجود، کلید امضای واقعی، دادهٔ کودک، merge/deploy/DNS دست‌نخورده‌اند. انتقال واقعی و پذیرش گوشی هنوز **UNVERIFIED/غیرمجاز در این بسته** هستند.

## پیشنهاد حفظ نصب قبلی در صورت نبود کلید — سابقهٔ پیش از تأیید محدود

در شاخهٔ `docs/offline-data-rescue-options` بر PR41، [ADR0018](docs/decisions/0018-offline-installed-data-rescue-options.md) سه گزینه را مشخص می‌کند: کلید اصلی/آپدیت همان نصب، نصب کناری و انتقال کاملاً محلی رمزدار، یا حفظ نسخهٔ فعلی. **PROPOSED؛ هیچ گزینهٔ انتقال یا هویت تازه تأیید/اجرا نشده است.** کلید اصلی هنوز UNVERIFIED است؛ نداشتن دسترسی تیم، نبود آن نزد مالک را اثبات نمی‌کند.

**VERIFIED:** مستند رسمی Android signing باHTTP200 خوانده شد و علت نیاز به certificate یکسان/هویت جدا توضیح داده شد؛ سند و لینک‌های محلی بررسی شدند. **UNVERIFIED:** ابزار انتقال/بازیابی، نصب کناری و آزمون ارتقای تازه هنوز ساخته یا اجرا نشده‌اند. کد محصول، تنظیمات امضا، package، DB، دادهٔ واقعی، merge/deploy/DNS تغییر نکردند. نصب موجود حذف یا clear-data نشود؛ بدون تصمیم مالک به روش تازهٔ نگهداری داده وارد نمی‌شویم.

## اولویت آفلاین و حفظ دادهٔ آپدیت — ۲۰۲۶-۱۰-۲۱؛ APK جدید تحویل نشده

مالک صریحاً تکمیل همین نسخهٔ شخصی روی گوشی را پیش از ادامهٔ آنلاین خواست. [ADR0017](docs/decisions/0017-offline-first-and-update-continuity.md) این ترتیب و معیار ارتقای همان نصب را ثبت می‌کند؛ روش تازهٔ انتقال/پشتیبان داده هنوز انتخاب نشده است. دادهٔ واقعی کودک، آنلاین/AI/دسترسی والد، merge/deploy/DNS تغییر نکردند.

**VERIFIED از گواه APKهای تحویلی/CI:** فایل قبلی در CI39480587450 و فایل PR39 در CI39541418453 هر دو package شخصی/code9 اما certificate متفاوت دارند. CI39541418453 و39541418486 واقعاً موفق شدند؛ موفقیت build، ارتقای نصب قبلی را اثبات نمی‌کند. موجودبودن کلید خصوصی قبلی **UNVERIFIED** است. [PR40](https://github.com/davoodmehraban89/LifeMate/pull/40)، `a21eba1`، کنترل fail-closed امضا/version و قفل upload APK را اضافه می‌کند؛ آزمون فعلی fixture در DB جدا، پذیرش exact-old→new/default-DB نیست. [گواه و کنترل تحویل](docs/operations/PERSONAL_UPDATE_GUARD.md).

[PR41](https://github.com/davoodmehraban89/LifeMate/pull/41)، شاخهٔ `fix/personal-notification-controls`، منبع `111b793b03a0342d130a1dd3c833ceea200d4ea9` بر PR40: دکمهٔ تنظیم صدا/اعلان Android، بازگشت به تنظیمات همان app در صورت نبود Activity و خطای فارسی بدون دست‌زدن به برنامه/انتخاب/زمان‌بندی قبلی. بازگشت از settings مجوز را دوباره می‌خواند. لحن همراه و حداقل لمس۴۸؛ عنوان خصوصی روی اعلان اضافه نشد.

**VERIFIED محلی:** Flutter332 روی49702e8؛ پس از اصلاح صرفاً lint در111b793، تست متمرکز4 و analyze clean؛ Python60؛ format19/0تغییر. عرض۳۲۰ و متن۲۰۰٪، ماندنOFF و حفظ اعلان فعال هنگام خطا آزموده شدند. SQLite واقعی است؛ مرز Android در این تست‌ها mock است. [دستور/خروجی و شکست‌ها](docs/audits/evidence/personal-notification-controls-2026-10-21.json)، [شرح بسته](docs/audits/2026-10-21-personal-notification-controls.md).

**UNVERIFIED/BLOCKED:** نتیجهٔ CI منبع جدید تا آخرین خواندن pending/in-progress؛ Intent واقعی/OEM، صدا/لرزش/باتری/reboot، گوشی، ارتقای همان نصب با حفظ داده، export/restore و کلید قبلی. APK جدید به‌عنوان آپدیت ارائه نمی‌شود؛ **نسخهٔ موجود حذف یا clear-data نشود**. گام بعد: رفع مانع امضا/طرح حفظ داده، پذیرش دقیق ارتقا، سپس آزمون گوشی و تحویل محدود آفلاین؛ کار آنلاین پس از تکمیل این بسته ادامه می‌یابد.


## تاریخ شمسی برنامه‌ریز شخصی — ۲۰۲۶-۱۰-۲۱؛ اصلاح منبع، بدون ارتقای APK نصب‌شده

[PR39](https://github.com/davoodmehraban89/LifeMate/pull/39)، شاخهٔ `fix/personal-jalali-dates`، منبع `c5cb3084f665cb5b1546447e34e35963e5ea5597`. پس از تحویل [کتابچهٔ ۱۲صفحه‌ای/برنامهٔ شش‌بسته‌ای در PR38](https://github.com/davoodmehraban89/LifeMate/pull/38)، نمایش و انتخاب تاریخ خانه/هفته/نوبت/تکرار شمسی شد؛ سال ثابت نیست. SQLite/ISO، روز هفته، زمان اعلان، مجوز و نسخهٔ آنلاین تغییر نکردند؛ migration یا انتقال داده اجرا نشد.

**VERIFIED محلی روی همین منبع:** Flutter328/328، analyze بدون مشکل، format6/0تغییر، Python23؛ انتخاب۱۴۰۶/۱/۱ از UI، SQL مستقل read-only=`2027-03-21` پس از بستن، بازگشایی همان شناسه/تاریخ؛ کبیسه و کران/ماه ناقص و تأیید/لغو با عرض۳۲۰/متن۲۰۰٪. تصویر، رندر واقعی widget-test با دادهٔ ساختگی است، نه گوشی/شبیه‌ساز. [دستورها و خروجی‌ها](docs/audits/evidence/personal-jalali-2026-10-21.json)، [شرح تغییر و شکست‌ها](docs/audits/2026-10-21-personal-jalali-dates.md).

**FAILED/UNVERIFIED:** ساخت bundle محلی با نبود Android SDK شکست خورد؛ CI39541418453 و39541418486 در آخرین خواندن در حال اجرا بودند و موفقیت‌شان ادعا نشده است. APK جدید/نصب/ارتقا، گوشی/صدا/Doze/reboot، Safari/ایران و امضای پایدار تأیید نشده‌اند. APK قبلی زیر، همچنان همان تحویل آزمون اولیه است؛ اطلاعاتش پاک نشود. پشتیبان/بازیابی و همگام‌سازی هنوز اضافه نشده‌اند. گام بعد، پشتیبان و مسیر ارتقای امن است؛ قرارداد حریم خصوصی/زیرساخت و مجوز merge/deploy عوض نشده‌اند.


## لایف‌گاید شخصی — ۲۰۲۶-۱۰-۲۰؛ APK اولیه بدون URL آمادهٔ آزمون گوشی

[PR37](https://github.com/davoodmehraban89/LifeMate/pull/37)، شاخهٔ `feat/standalone-weekly-planner`، کد آزموده‌شده `3e36dfd4f01d51e11816c0f97d1abda4266f1945`. طبق انتخاب پذیرفته‌شدهٔ D-A در ADR0016، APK جدا با نام «لایف‌گاید شخصی»، شناسهٔ `ir.lifeguide.app.device` و نسخه `0.7.2-personal.1/code9` بدون URL/ورود/سرور اجرا می‌شود. شناسه و مجوزهای نسخهٔ آنلاین تغییر نکرده‌اند. SQLite خصوصی و تراکنشی مرجع همین بسته است؛ برنامهٔ یک‌باره/روزانه/روزدرمیان/هفتگی با ساعت مستقل، تیک/ویرایش/بایگانی هر نوبت، نام همراه و چهار تم واقعی دارد. هیچ ACK سرور یا حساب نمایشی ندارد.

**VERIFIED:** [CI اختصاصی39480587450](https://github.com/davoodmehraban89/LifeMate/actions/runs/39480587450) موفق: Flutter314، Python23، analyze clean، build دو APK جدا و manifest بدون INTERNET. APK واقعی کاربر ابتدا روی API35 باز و تصویرش مستقل مشاهده شد؛ سپس fixture هم‌امضا و هرگز توزیع‌نشده با DB ساختگی جدا، SQL مستقل بعد از close/reopen، ماندگاری/ساعت‌های مختلف/تکرار/تیک/بایگانی، اعلان OS پس از نبود پردازش، متن عمومی بدون canary خصوصی، لغو قبل از موعد و خاموش‌کردن را پاس کرد. [گواه کامل با دو شکست قبلی و اصلاح ابزار](docs/audits/evidence/personal-android-2026-10-20.json).

**VERIFIED:** CI عمومی39480587202 موفق؛ Backend308، identity41، regression96، Flutter314، analyze و buildوب/Android. فایل APK کاربر از اتصال رسمی دریافت شد؛ digest ZIP، hash APK، manifest باینری و امضای v2 با ApkVerifier محلی تطبیق داده شدند. [فایل آزمون نصب](https://github.com/davoodmehraban89/LifeMate/actions/runs/39480587450/artifacts/12292340083)، [راهنما](docs/operations/PERSONAL_ANDROID.md). این APK debug برای آزمون اولیه است، نه release امضاشدهٔ مالک.

**UNVERIFIED/محدود:** گوشی فیزیکی، صدا/لرزش، Doze/reboot، UI رضایت واقعی، ارتقا با حفظ کلید، Safari/PWA و شبکه ایران. داده فقط روی همین گوشی است؛ همگام‌سازی، نمای والد، خروجی/backup و بازیابی سرور ندارد. برای اختلاف امضا هرگز برنامه/داده را پاک نکنید. آزمون جداگانهٔ کانال آنلاین در تلاش اول39480587033 با `adb_command_unavailable` شکست خورد؛ تلاش دوم بدون تغییر کد واقعاً موفق شد و هر دو نتیجه در گواه حفظ شده‌اند. هیچ merge/deploy/DNS/schema زنده یا دادهٔ واقعی استفاده نشده است. گزارش‌های زیر تاریخی‌اند؛ PROPOSED قبلی ADR0016 با انتخاب فعلی جایگزین شده است.

## اعلان Android در شبیه‌ساز — ۲۰۲۶-۱۰-۱۹؛ APIآنلاین هنوز مانع تحویل است

[PR36](https://github.com/davoodmehraban89/LifeMate/pull/36)، شاخهٔ `test/android-reminder-acceptance`، فقط ابزار آزمون و مستندات است. Flutter/Android عملیاتی، Backend و APKتحویلی0.7.2+8 تغییر نکرده‌اند. fixture فقط debug، رکورد ساختگی و تأییدسرور صریحاً شبیه‌سازی‌شده دارد؛ دستگاه فیزیکی/بستهٔ نصب‌شده را رد می‌کند و APKآن توزیع نمی‌شود.

**VERIFIED درc1a22bd:** اجرای واقعی API35 در [CI39194965252](https://github.com/davoodmehraban89/LifeMate/actions/runs/39194965252) موفق: نبود پردازش پیش از موعد، اعلان OSپس ازبستن، متن عمومی/نبود canaryخصوصی، حفظ اعلان/وضعیت deliveredپس از بازکردن مجدد، حذف اعلان نمایش‌داده‌شده، لغو آینده بدون اعلان، وضعیت تقریبی پس از لغو مجوز exact و خاموش‌کردن. CIعمومی39194965236 نیز موفق با Backend308، role41، regression96، Flutter282، analyzeclean و buildوب/Androiddebug. hostمحلی25تست موفق؛ بازبینی مستقل انجام شد. [دستور، خروجی و حدوداعتبار](docs/audits/evidence/android-reminder-ci-final-2026-10-19.json).

سه اجرای ناموفق اول و اصلاحات ابزار حفظ شدند: بستن عادی/تأخیر رفتن Activityبه پس‌زمینه، taskبا Intentقبلی، و گزینهٔ خط‌فرمان نامعتبر. هیچ شکست با حذف کنترل، force-stop یا اعلان دستی سبز نشد؛ numeric `-f 0x10008000`مطابق parserرسمیAndroid15است. CIعمومی سوم به‌دلیل commitبعدی cancelledشد و موفق گزارش نمی‌شود. [راهنما](docs/operations/ANDROID_REMINDER_ACCEPTANCE.md).

**مانع عملیاتی:** APIبخش سروریِ همین محصول است و مسئولیت آماده‌کردن/تنظیم نشانی آن با تیم فنی است؛ مالک نباید APIبخرد یاURLحدسی وارد کند. داشتن دامنه/دیتابیس به‌تنهایی اجرای Backendنیست. GETباTLSمعتبر در19اکتبر روی `app.lifeguide.ir/config.json`،`/api/health` و`/health` هر سه404داد؛ [گواه خواندنی](docs/audits/evidence/public-api-paths-2026-10-19.json). سرور عمومی و ورود خصوصی مستقل کودک برای این APKتأیید نشده‌اند. [گزینه‌های تحویل اولیه ADR0016](docs/decisions/0016-initial-child-planner-delivery.md) هنوز PROPOSEDاند؛ درخواست ادامه یا سؤال APIانتخاب سیاستی محسوب نشده است.

**UNVERIFIED:** گوشی واقعی، نصب/ارتقا، صدا/لرزش، Doze/reboot، رضایت واقعیUI، تحویل زمانی حالت approximate، ACKواقعی سرور، Safariوایران. هیچ merge،deploy،DNS،تغییرسیاست یا دادهٔ واقعی استفاده نشده است. این نتیجه تکمیل آزمون اعلان در شبیه‌ساز است؛ بهره‌برداری آنلاین کودک هنوز آماده نیست.

## برنامهٔ هفته و اعلان Android — ۲۰۲۶-۱۰-۱۸؛ هنوز آمادهٔ بهره‌برداری کودک نیست

مالک اجرای بستهٔ برنامهٔ شخصی را تأیید کرد. API مستقل در [PR34](https://github.com/davoodmehraban89/LifeMate/pull/34) و Flutter/Android وابسته در [PR35](https://github.com/davoodmehraban89/LifeMate/pull/35) آماده شد؛ هیچ merge/deploy انجام نشد. نوبت‌های واقعی PostgreSQL، تکرار و ساعت‌های مستقل، صف پایدار، تیک/ویرایش هر روز و اعلان opt-in با دریافت تازهٔ مالک پیاده شد. Feature1، نام LifeGuide و مرز خصوصی نشست کودک حفظ شدند.

**VERIFIED محلی در0878623:** Backend308pass/0fail/0skip؛ Flutter277pass/0fail؛ analyze بدون مشکل، build releaseوب67.0ثانیه و منابع محلی؛ بررسی credential فایل‌های tracked و naming459مورد موفق. بازبینی سه خطای خاموش‌کردن اعلان، برگشت تیک/یادآوری و پیشرفت خانه را پیدا کرد؛ رگرسیون و اصلاح ثبت شد. [دستورها، خروجی و شکست‌های اولیه](docs/audits/evidence/weekly-planner-local-2026-10-18.json).

**UNVERIFIED/باز:** CI39170095124 روی0878623 هر سه job موفق؛ APK0.7.2+8/debug ساخته و از اتصال رسمی دریافت شد، ZIP با digest گیت‌هاب و manifest/hash محلی برابر است. [گواه فایل/امضا](docs/audits/evidence/weekly-planner-ci-apk-2026-10-18.json). مرورگر HTTPS واقعی با API/PostgreSQL محلی6/6موفق، بدون interception یا مبدأ خارجی؛ [گواه](docs/audits/evidence/weekly-planner-browser-2026-10-18.json). نصب و اعلان واقعی Android، Safari/ایران و امضای release اجرا نشده‌اند. سرور آنلاین و ورود خصوصی مستقل کودک آماده نیست. [ADR0016](docs/decisions/0016-initial-child-planner-delivery.md) دو مسیر مستقلِ روی گوشی یا انتظار برای آنلاین را آماده کرده و منتظر پاسخ مالک است؛ درخواست «ادامه» انتخاب سیاستی محسوب نشده است. URL یا حساب ساختگی جای اتصال گذاشته نشد. [پذیرش گوشی و محدودیت‌ها](docs/operations/WEEKLY_PLANNER_ANDROID.md). فاز استفادهٔ کودک تکمیل‌شده گزارش نمی‌شود.

## ادامهٔ بررسی PR31 و تصمیم دسترسی آموزشی — ۲۰۲۶-۱۰-۱۶

GitHubAPI،CIاجرای38906353812برایheadc067163راsuccessوartifactآزمایشیAndroidرا موجود نشان داد. ZIPاز اتصال رسمی دریافت شد؛ digestآن باGitHubبرابر وmanifestواقعی محلیPASSاست. این شواهدِbuild/integrityاست، نه نصب‌روی‌گوشی یا انتشار. [جزئیات تحویل](docs/ux/2026-10-16-pr31-ci-android-handoff.md).

برای مانع دسترسی نشست جدیدکودک، [ADR0015](docs/decisions/0015-managed-child-education-scope-options.md) با دو گزینه و قرارداد/معیارپذیرش آماده شد؛ **PROPOSED،منتظرتصمیم مالک**. اجازهٔ برنامه/مطالعه خصوصی،AI،زیرساخت،تولید،mergeیاdeployداده نشد. کدAPIوFlutterدراینPRاسناد تغییر نمی‌کند.

## Flutter — نخستین پیاده‌سازی طرح تأییدشده — ۲۰۲۶-۱۰-۱۶

مالک، طرح۱۲صفحه‌ای را تأیید کرد. در شاخهٔ مستقل `feat/flutter-mobile-navigation` بر PR30، خانهٔ جمع‌وجور RTL با شش منوی کودک/چهار منوی بزرگسال، صفحه‌های جدا و برگشت، استفاده از صفحه‌های API موجود و جزئیات همان تکلیف با ویرایش/تکمیل/بایگانی از PlanSync پیاده شد. نام از پروفایل؛ بدون آمار یا رکورد نمایشی. مجوزها و API تغییر نکردند.

**VERIFIED:** baseline212→226تستFlutterموفق؛14بررسی متمرکز شامل اصلاح سه یافتهٔ مستقل؛ analyzeبدون مشکل،format73فایل/0تغییر، ساخت releaseوب و منابع محلی؛4تستworker و بررسیCanvasKit/فونت بدوندامنهٔخارجی. مرورگرChromiumباTLSمعتبر و Node/PostgreSQL16کاملاًمحلی:6PASS؛ ایجاد تکلیف ازUI باSQL/APIمستقل، بازکردن مجدد، ویرایش، تایمر واقعی، تکمیل و بایگانی. [شواهد و محدودیت‌ها](docs/ux/2026-10-16-flutter-navigation-implementation.md).

**UNVERIFIED/ناقص:** گوشیAndroid/Safari،APKامضاشده، استقرار عمومی،SMS/ویدئوی واقعی،۲۵/۵ و پذیرش چندوالد. نشست managed-child جدید همچنان روی APIقدیمی403است؛ آزمون محلی باحساب legacyساختگی انجام شد. ظاهر تمام زیرصفحه‌ها هنوز هم‌سطح طرح نهایی نیست. این بسته تکمیل فاز۱ یا محصول آنلاین نیست؛ هیچ merge/deploy/DNS/schemaزنده انجام نشد. گام بعد بررسیPR و بستهٔ بعدیِ متناسب با مانع واقعی است.

## طرح موبایل — منتظر بررسی مالک — ۲۰۲۶-۱۰-۱۶

در پاسخ به بازخورد مالک، این بسته فقط تجربهٔ دیدنی/قابل کلیک را طراحی می‌کند؛ توسعهٔ هسته و تغییر محصول زنده انجام نشد. [بستهٔ۱۲صفحه‌ای](design-review/mobile-v1/README.md) شامل منوی اصلی، زیرصفحه‌ها، نمای والد و کودک،PNG/PDFقابل زوم وHTMLمستقل است. همه داده‌ها ساختگی‌اند؛ منتظر تأیید طراحی قبل از پیاده‌سازی درFlutter.

منبع، شناسهٔبوم/نسخه و خروجی‌ها درمخزن ذخیره شدند تا ادامهٔکار به چت وابسته نباشد. تأیید UI برابر با تأیید auth/permission، محتوای آموزشی،SMS یا انتشار نیست. app.lifeguide.ir،Backend،DB وDNS تغییرنکرده‌اند. شرح وreceiptدر بستهٔطرح موجود است.

## فاز۱ — هویت کودکِ صرفاً ساختگی، بدون انتشار — ۲۰۲۶-۱۰-۱۶

سه بخش وابسته بر PR24 آماده شد: [schema در PR27](https://github.com/davoodmehraban89/LifeMate/pull/27)، [مرز نشست در PR28](https://github.com/davoodmehraban89/LifeMate/pull/28) و جریان `feat/child-device-safety` روی آن‌ها. ساخت کودک با DOB اجباری و رضایتِ صریحاً غیرحقوقیِ sandbox، سرپرست دوم با دعوت سازنده/پذیرش گیرنده، بازیابی با ابطال نشست‌های قبلی، scope محدود در DB و refresh و API دیدپذیری پیاده شد. Production حتی با flag فعال503؛ داده واقعی مجاز نیست.

**VERIFIED محلی:** npm ci؛23migration و تکرار/import تکراری؛ چهار SQL assertion موفق؛ Backend **297pass/0fail/0skip**، runtime30 و regression96 موفق؛ backup/restore مستقل و کنترل مجوز پس از restore؛ syntax82، audit0 و بررسی diff. [گزارش، شکست اولیه و حدود شواهد](docs/audits/2026-10-16-child-identity-sandbox.md).

۲۱ migration قبلی و bundleهای تاریخی Supabase حفظ شدند؛ live QA تغییر نکرد. هیچ merge/deploy/DNS/SMS یا داده زنده‌ای تغییر نکرد. UI/QR، Android/Safari، آنلاین عمومی، رضایت حقوقی و مسیر آموزشی مجاز جدید هنوز **UNVERIFIED/تکمیل‌نشده** هستند. مسیرهای خصوصی قدیمی برای نشست جدید بسته‌اند؛ کامل‌شدن Backend این بسته، آماده‌بودن نرم‌افزار خانواده نیست. **فاز۱ کامل نیست و فاز۲ شروع نشده است.** Feature1، نام LifeGuide و شناسه‌های فنی موجود حفظ شدند.

## فاز۱ — اصلاح هویت در PR وابسته؛ بدون انتشار

مالک پس از گزارش فاز۰ شروع فاز۱ را تأیید کرد. شاخه `fix/auth-abuse-expiry-safety` از PR14 در `5da6c4290e422162c13c3fe5260345770dde7ffa` منشعب است؛ به main یا سرویس زنده منتقل نشده است. محدودیت IP مشترک PostgreSQL، بررسی تازه انقضا پس از قفل و gate تأیید ارسال SMS پیاده شد. **VERIFIED محلی:** `npm test -- --test-concurrency=1` →271pass/0fail/0skip؛ migration و import تکراری، چهار SQL matrix و syntax موفق. [گزارش و محدودیت‌ها](docs/audits/2026-10-15-phase1-auth-hardening.md).

Migration0023 فقط محلی آزموده شد؛۲۰ فایل اصلی و۳bundle تاریخی تغییر نکرده‌اند و Supabase زنده همان baseline20 است. manifest جدید generator شامل21فایل، گواه اعمال روی QA نیست. AI/guardian/cycle policy، سرور آنلاین، دستگاه/Safari، SMS واقعی و امضای release هنوز تأیید/تکمیل نشده‌اند؛ **فاز۱ کامل نیست**. پاکسازی مخزن و اسناد گزینه‌های سیاستی در PRهای مستقل آماده می‌شوند. هیچ merge،deploy،DNS،داده یا schema زنده تغییر نکرده و این PR اجازه آن‌ها نیست.

## Supabase LifeGuide-QA full private schema — 2026-10-15 (HISTORICAL CHECKPOINT)

**20/20 original PostgreSQL migrations copied to the isolated QA database, SQL family/privacy assertions PASS, client-access remains DENY ALL.** This is a **database integration milestone**, not a publicly operational LifeGuide Android/PWA.

- Supabase Free `DM Studio` → `LifeGuide-QA` project `iqkrwxeprxvdiubdfcrb` Frankfurt PostgreSQL17.11; $0/month project creation quote. Existing `Finora ERP – Production` not touched and remains `ACTIVE_HEALTHY`.
- Two checked, atomic, provider-applied migrations: `20261014215436_lifeguide_qa_app_schema_0001_0010`, `20261014215539_lifeguide_qa_app_schema_0011_0020`. Exact SQL committed in `supabase/migrations/202610150001_...` and `202610150002_...`; 20 filename/SHA256 source hashes persist in `lifeguide_qa.schema_migration`. No original migration SQL rewritten in the source tree.
- Real database read-after-write verification: **59 private tables**, **19 functions**, **20 migration entries**, **0 public app tables**, **0 user/family/task/session rows after rollback**. All tables RLS ENABLED+FORCED, and `anon`, `authenticated`, `service_role` lack QA schema USAGE. Exactly five fixed school function search paths were redirected from `public` to QA. Supabase security advisor emits only INFO `rls_enabled_no_policy` for intentional deny-all; this does **not** mean clients can access the tables.
- Real SQL family fixture, transaction ROLLBACK: two authorized parents see child academic/shared-task state, unrelated outsider denied, private child task denied to parent, father access revoked while mother retained, study session **4s preserved**. Verified no fixture persisted. This is DB function evaluation, not an HTTP JWT test.
- Owner's Kavenegar `lifeguideotp` OTP template still **under review**; adapter source/mock tests available on PR14, no key configured, no paid SMS ever sent.
- Backend Node/Express/native Argon2/custom sessions **not yet hosted** on the QA project; Supabase is managed PG not the long-running existing app server. No real PWA or Android app pointed at Supabase, no production domain/DNS/Railway/Finora changes. No-VPN Iran, device tests and live SMS UNVERIFIED.
- **Authoritative evidence:** [Full schema / rollback family test](docs/audits/2026-10-15-supabase-full-schema-family-acceptance.md); [initial provider bootstrap](docs/audits/2026-10-15-supabase-qa-provisioning.md); [Kavenegar setup](docs/operations/KAVENEGAR_SMS_SETUP.md); [Draft PR14](https://github.com/davoodmehraban89/LifeMate/pull/14).
- **NEXT:** determine no-card free compatible host for existing Express/Argon2, implement server-side least-privileged access with real HTTPS negative-role API tests, then connect QA Android/PWA. Keep production rollout gated. PostgreSQL private QA schema has no client policies by design.

Older checkpoints below are retained as historical evidence; this latest verified entry supersedes outdated statements about no application migrations, no table structures or unsolved Supabase organization access.

## Kavenegar template owner verification — 2026-10-15

- Owner screenshot from Kavenegar console shows SMS VerifyLookup template **`lifeguideotp` created** with status **در حال بررسی / under review**, NOT approved and NOT sent.
- Visible message preview contains literal `%token`, LifeGuide brand, 5-minute validity and "do not share" warning.
- Console lists **نام اپلیکیشن = `lifeguideotp`**, which duplicates the template name instead of product name LifeGuide. Prefer correcting the display name to `LifeGuide` if provider supports editing; do not delete/recreate the pending template without need.
- No actual Kavenegar API key, OTP, phone number, or SMS delivery proof is available. No paid SMS sent. Keep live provider configuration disabled until approval, secure secret placement, and explicit owner consent for a paid test.
- Latest GitHub CI for QA branch `c79939351b88` run [38640974777](https://github.com/davoodmehraban89/LifeMate/actions/runs/38640974777) was still **in progress** at check; do not mark adapter CI passed.

## Kavenegar API adapter — 2026-10-15 (QA CODE, NOT LIVE)

- Provider **Kavenegar**, verified by owner screenshots of `console.kavenegar.com`; screenshot shows masked API key and a draft new validation template. The key was **not** obtained or stored.
- Suggested `lifeguideotp` validation pattern with literal `%token`, product name LifeGuide, SMS mobile-app use, fallback resend disabled. Provider approval **UNVERIFIED**.
- Backend opt-in `SMS_PROVIDER=kavenegar` implemented on isolated QA branch using `backend/src/kavenegar_sms.js`, minimal factory change in `backend/src/auth_delivery.js`, blank secret variable `KAVENEGAR_API_KEY` in `.env.example`, and mock-only tests in `backend/tests/kavenegar_sms.test.js`. Existing disabled/webhook provider paths kept.
- Implementation confines API key to server env, uses fixed HTTPS Kavenegar VerifyLookup host, no logged provider response/secret/OTP, and no automatic retry of non-idempotent SMS sends. It does **not** use account credentials in Supabase, and the real Node/Express backend still has no approved online hosting.
- New draft [PR14](https://github.com/davoodmehraban89/LifeMate/pull/14) opened to run CI; test results **PENDING**, no merge or live deployment.
- Owner's prepaid Kavenegar balance is finite. **No paid real SMS** sent/approved yet; requesting template name/approval status, never API key. The public `app.lifeguide.ir` is not connected to LifeGuide-QA.
- Guide: [KAVENEGAR_SMS_SETUP.md](docs/operations/KAVENEGAR_SMS_SETUP.md). Provider official `VerifyLookup` documented in the official Kavenegar Node SDK.

## Public domain and owner SMS panel — 2026-10-15 (READ-ONLY CHECK)

- **Official product name: LifeGuide** (not آرام). Repository path `davoodmehraban89/LifeMate` and package/protocol identifiers remain unchanged unless separately approved.
- User reports an external **SMS provider panel is set up** for registration/login. **Provider name, API documentation, SMS template/pattern ID, permitted sender, delivery capability and available provider credentials are not yet verified or integrated.** Never request any API secrets in a chat/Git repository or issue a real OTP without explicit operational consent.
- Existing v0.7.1 Node/Express backend includes `SmsProvider` and a generic HTTPS `webhook` adapter in `backend/src/auth_delivery.js`, `/v1/auth/phone/request-otp` and `/v1/auth/phone/verify-otp` in `backend/src/auth_router.js`, plus phone registration and OTP recovery. `.env.example` defaults to `SMS_PROVIDER=disabled`. No deployed provider integration confirmed.
- The existing LifeGuide-QA Supabase project currently contains only a private synthetic `lifeguide_qa.setup_probe` table and JWT-protected health Edge Function; **it is not the complete LifeGuide API/DB**. No public `app.lifeguide.ir` origin/runtime-config/DNS change was performed by this workstream.
- Attempts on this date to fetch `https://app.lifeguide.ir/`, `/config.json`, `/api/health`, `/ready` through public fetch tools produced inaccessible or empty content, so **live domain/API behavior is UNVERIFIED**, not established as either healthy or down. Historical probe of 2026-10-12 saw HTML fallback for API/config paths; this is not a current observation.
- Next: obtain provider **name and public API documentation** from owner (never secret token); design and test a safe adapter in an isolated branch, preserve account-level OTP rate limits, 5-minute expiry, guardian privacy, and secrets confined to server configuration. Separately deploy/verify an authenticated QA API against Supabase PostgreSQL before switching domain/Android/PWA. Any public/domain change and real SMS sending need independent approval.

## Supabase QA verified checkpoint — 2026-10-15 (CURRENT)

**LifeGuide-QA is provisioned on Supabase Free but the LifeGuide mobile/PWA app is NOT deployed or connected.**

- Supabase organization: **DM Studio**, id `unrlckipyubhegrpqgei`, Free. User approved it as the shared administration umbrella for multiple *isolated* projects. Exact `get_cost(project)`: **$0/month**; confirmation performed. Provider accepted the new project.
- Separate project: **LifeGuide-QA**, id `iqkrwxeprxvdiubdfcrb`, Frankfurt (`eu-central-1`), PostgreSQL17.11, `ACTIVE_HEALTHY`. Other observed project `Finora ERP – Production` (id `hcsixhqbyuhpshfwqpjx`) remained `ACTIVE_HEALTHY` and was **not changed**.
- Only a PRIVATE QA schema `lifeguide_qa` and `setup_probe` table were created in the new project via additive migration `20261014210221_lifeguide_qa_isolated_connectivity_baseline`. One `synthetic_backend_handshake` write/read passed. Zero application tables under `public`. Privileges for `anon` and `authenticated` explicitly absent; RLS enabled and forced. Security advisor issued INFO `rls_enabled_no_policy`, expected for a deliberately closed table.
- Synthetic-only JWT-gated Supabase Edge Function `lifeguide-qa-health` v1 deployed `ACTIVE` with `verify_jwt=true`; an external unauthenticated GET received **HTTP 401**. Authenticated success NOT VERIFIED. This endpoint is NOT the current Node/Express backend.
- PostgreSQL current setup proof is **not** the application's 20 migrations or guardian permissions. No child/parent accounts created, no existing application data, production domain, Railway/Neon/other Supabase project, `main` or stacked PRs changed. Real Android and iOS Safari, Iran no-VPN connectivity and PWA are UNVERIFIED.
- Evidence: [Provisioning audit](docs/audits/2026-10-15-supabase-qa-provisioning.md), [Supabase migration](supabase/migrations/20261014210221_lifeguide_qa_isolated_connectivity_baseline.sql), [Edge source](supabase/functions/lifeguide-qa-health/index.ts), [QA runbook](docs/operations/SUPABASE_QA_BOOTSTRAP.md).
- **Next:** compatibility assessment of Express/Argon2/JWT session model/managed Supabase PG grants before any real application SQL or Auth adaptation. Resolve API hosting and privacy parity, then synthetic child→authorized mother/father task/study sync and physical devices. Production hosting ADR0009 remains the baseline.

The Supabase preparation/identity notes retained below are **historical snapshots** from earlier connector states. When they contradict this checkpoint, **this checkpoint is authoritative**. The unchanged 0.7.1 engineering checkpoint below is still valid for that earlier source/CI.

## Supabase historical preparation — 2026-10-15 (SUPERSEDED)

Owner approved evaluating a **separate Free Supabase organization `LifeGuide`** and synthetic-data QA project. This is **not** a new public deployment, a database migration, or a replacement for production hosting ADR 0009.

- Working branch: `infra/lifeguide-supabase-qa`, forked from the 0.7.1 test head `fix/study-duration-display`. No Flutter/Backend runtime code changed for this trial.
- Current connected Supabase account: existing unrelated Free organization `Finora` and two unrelated projects `Finora` (INACTIVE) / `EasyFactor` (ACTIVE_HEALTHY). Do **not** modify/reuse them.
- The connected Supabase tool cannot create organizations; owner must first create **LifeGuide / Free** manually in their dashboard. No new LifeGuide organization or project has been verified.
- After the independent organization appears, verify **$0** exact project cost through `get_cost` and available account-wide free-project quota before creating `LifeGuide-QA`. The two free active projects limit spans organizations; an INACTIVE label alone is not quota evidence.
- Node/Express/Argon2 and Supabase Edge Functions are not drop-in interchangeable; review DB roles/security and design minimal auth-safe prototype before deploying. No secrets or real child records in tests.
- Gate status: organization **BLOCKED on owner action**; cost check, new DB, deployment, Android/Safari/without-VPN Iran acceptance **NOT RUN**.
- Technical runbook: [Supabase QA bootstrap](docs/operations/SUPABASE_QA_BOOTSTRAP.md); [QA decision](docs/decisions/0011-supabase-free-qa-trial.md). Original 0.7.1 evidence below is unchanged.

## Supabase historical naming decision — 2026-10-15 (SUPERSEDED)

- Owner **approved the general-purpose organization display name `DM Studio`** for managing several software projects; `LifeGuide` remains the product name.
- **Organization rename PENDING manual dashboard action**: connected Supabase tools have no organization-update operation. Last verified actual name is `LifeGuide`; ID `kpbskbvjspggwzmgqyze` was formerly named `Finora`. Do not claim a second independent organization exists.
- Proposed project is still `LifeGuide-QA`, in the existing organization after its display name is updated. Independent **projects** rather than independent organizations are the isolation boundary.
- Supabase reported project cost `$0/month` for current Free org; do not create any project before verifying current Free active-project quota, original Finora/EasyFactor resources and explicit owner confirmation of exact charge. No new Supabase project or DB has been provisioned.

## Supabase historical organization visibility issue — 2026-10-15 (RESOLVED)

- Read-only Supabase connector reports `LifeGuide` Free and `get_cost(project)` **$0/month**.
- **Identity mismatch blocks provisioning:** currently listed LifeGuide ID `kpbskbvjspggwzmgqyze` is precisely the ID previously seen as `Finora`. Both separate organizations are not visible to this connection. `list_projects` returns empty and direct access to previously listed unrelated projects returns permission denied; no assertion of deletion, reassignment or independent organization creation is supported.
- Await owner's confirmation that **LifeGuide and Finora are two separate dashboard organizations**, and the new LifeGuide non-secret ID. Until then do **not** call project cost confirmation or create `LifeGuide-QA`.
- No Supabase project, DB, schema, migration, credentials, app deploy, DNS change or real-data import executed. Earlier 0.7.1 branch and CI evidence stay unchanged.

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
