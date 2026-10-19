# آزمون اعلان در شبیه‌ساز Android

این بسته فقط آزمون است؛ APK تحویلی0.7.2+8، Backend، حریم خصوصی، ورود و سرویس زنده را تغییر نمی‌دهد. هیچ تماس، حساب یا دادهٔ واقعی استفاده نمی‌شود. دریافت اعلان در شبیه‌ساز، پذیرش گوشی واقعی یا اتصال آنلاین کودک محسوب نمی‌شود.

## مرز fixture

entry point مستقل `apps/lifemate/tool/native_reminder_fixture.dart` فقط در debug و با `LG_NATIVE_REMINDER_FIXTURE=true` کار می‌کند. برنامهٔ اصلی آن را import نمی‌کند. این APK را نصب دستی یا توزیع نکنید؛ workflow آن را upload نمی‌کند. شناسهٔ بسته همان برنامه است، به همین دلیل harness **هر بستهٔ از قبل نصب‌شده و هر دستگاه فیزیکی را رد می‌کند**. فقط AVD تازه، پاک و یک‌بارمصرف قابل استفاده است.

تأیید رکورد در این fixture **شبیه‌سازی‌شده** است و در JSON با `simulatedServerAcknowledgement:true` مشخص می‌شود؛ هیچ API، نشست یا تأیید واقعی سروری در آزمون نیست. پورت Dart و AlarmManager/NotificationManager اصلی بدون تغییر استفاده می‌شوند. UI یک متن canary ساختگی دارد؛ اعلان باید فقط نام همراه ساختگی و متن عمومی مجاز داشته باشد.

## اجرای قابل تکرار

پیش‌نیاز: Flutter3.47.6، Python3، Android SDK/adb و یک AVD تازه Android35 با سخت‌افزار `ranchu/goldfish`؛ گوشی مالک را به این آزمون وصل نکنید. خود workflow با `-wipe-data -no-snapshot` شبیه‌ساز تازه می‌سازد.

```sh
cd apps/lifemate
flutter pub get
flutter test
python3 -m unittest discover -s tool -p 'test_native_reminders_android_test.py' -v
flutter build apk --debug --target=tool/native_reminder_fixture.dart --dart-define=LG_NATIVE_REMINDER_FIXTURE=true
python3 tool/test_native_reminders_android.py --serial emulator-5554 --apk build/app/outputs/flutter-apk/app-debug.apk --allow-synthetic-emulator-reset --output exports/native-reminders-android.json
```

harness به serial صریح، تأیید محیط ساختگی، manifest debug با شناسهٔ درست، وضعیت device، مشخصات emulator، API35 و نبود بسته پیش از نصب نیاز دارد. مجوز notification و exact alarm از adb فقط روی همین AVD داده می‌شود؛ **این کار آزمون جریان رضایت UI نیست**.

سناریوها: زمان‌بندی ← Home و `am kill` با اثبات نبود PID ← مشاهدهٔ اعلان واقعی سیستم ← بازکردن inspect بدون activate و بررسی بقای اعلان/وضعیت delivered در preference بومی ← لغو اعلان نمایش‌داده‌شده ← لغو مورد آینده و عبور از موعد بدون اعلان ← مجوز exact خاموش و ثبت وضعیت approximate ← خاموش‌کردن و پاک‌شدن وضعیت.

هیچ `force-stop`، broadcast دستی به receiver خصوصی، پاک‌کردن logcat، uninstall یا kill-server استفاده نمی‌شود. برای تشخیص اعلان فعال از `cmd notification list` استفاده می‌شود؛ dump خام سیستم یا preference در خروجی ذخیره نمی‌شود. فقط receipt محدود با نتیجه و شمارنده‌های ساختگی upload می‌شود.

## خواندن نتیجه و حدود اعتبار

فقط `PASS` در receipt و exit0 اجرای واقعی، نتیجهٔ همان شبیه‌ساز را تأیید می‌کند. unit testها فقط منطق ابزار و دروازه‌های ایمنی را تأیید می‌کنند. شکست پیش‌نیاز یا timeout را موفقیت حساب نکنید. exact و approximate جدا گزارش می‌شوند؛ ثبت approximate، تضمین تحویل آن در چند ثانیه نیست.

**UNVERIFIED:** نصب/ارتقای گوشی واقعی، صدا و لرزش، صفحهٔ قفل سازنده، reboot، Doze/محدودیت باتری، اجازهٔ واقعی کاربر، iPhone/Safari/PWA، شبکهٔ ایران، تأیید سرور و ورود خصوصی مستقل کودک. نتیجهٔ اجرا و دستور/خروجی در گزارش همین PR ثبت می‌شود؛ قبل از اجرای CI، خود سناریوی Android نیز UNVERIFIED است.
