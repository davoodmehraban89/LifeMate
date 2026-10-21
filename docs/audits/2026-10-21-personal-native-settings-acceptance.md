# پذیرش تنظیمات صدای Android — ابزار آزمون، نه APK جدید

این PR بر `fix/personal-notification-controls` /76efe36 فقط ابزار آزمون و مستندات را توسعه می‌دهد. Flutter محصول، Kotlin، SQLite محصول، امضا، نسخه، مجوزها و قفل upload تغییر نکردند. هیچ سیاست اشتراک/backup یا زیرساخت انتخاب نشد.

## کاری که آزمون بررسی می‌کند

پس از سناریوی موجودِ SQLite واقعی، اعلان پس از نبود پردازش، لغو و OFF، fixture هرگز توزیع‌نشده متد واقعی `openNotificationSettings` را صدا می‌زند. میزبان با UIAutomator بررسی می‌کند عنوان کانال ثابت روی node متعلق به `com.android.settings` باشد؛ عنوان مشابه از app دیگر، XML نامعتبر/بزرگ یا صفحهٔ دیگر پذیرفته نمی‌شود. سپس Android Back، بستن/بازگشایی، SQL مستقل و وضعیت native بررسی می‌شوند: انتخاب OFF حفظ، اعلان جدید صفر و دادهٔ ساختگی موجود برقرار باشد.

هیچ reset/uninstall، انتخاب ضمنی دستگاه، ورودی دادهٔ واقعی یا نوشتن DB محصول اضافه نشده است. گیت‌های fresh API35 emulator، serial صریح، دو APK هم‌امضا و نبود بستهٔ قبلی حفظ شدند. XML/DB خام فقط در حافظه می‌ماند؛ خروجی assertionهای محدود است. توضیح طراحی در [برنامهٔ آزمون](../superpowers/plans/2026-10-21-personal-native-settings-acceptance.md).

## VERIFIED محلی

[گواه دستور/خروجی](evidence/personal-native-settings-2026-10-21.json): baseline35، RED4 شکستِ نبود بررسی، GREEN39 تست مرتبط و64 تست کل ابزار، Flutter332، analyze بدون مشکل و format1/0تغییر. تست‌های host از مدل Android برای بررسی orchestration استفاده می‌کنند؛ این مدل اجرای OS نیست. بازبین مستقل ایراد مسدودکننده‌ای در حفظ گیت‌ها/DB/رضایت پیدا نکرد؛ خودش تست native اجرا نکرد.

## UNVERIFIED و مانع تحویل

اجرای سناریوی جدید در Android تا نتیجهٔ CI **UNVERIFIED** است. این بررسی حتی با PASS، صدای شنیدنی، انتخاب صدای واقعی، OEM fallback، گوشی/Doze/reboot یا حفظ دادهٔ **APK دقیق تحویلی قبلی → نامزد جدید در DB محصول** را اثبات نمی‌کند. متن این سند وضعیت زمان ثبت است؛ CI، receipt خودش را در artifact diagnostics نگه می‌دارد.

PR40 عمومی موفق شد؛ شخصیِ آن پس از build و پذیرش OS فقط به‌علت `certificate_mismatch` و `version_code_not_incremented` در guard شکست خورد و APK upload نشد. PR41 عمومی و پذیرش اعلان کانال آنلاین نیز موفق شدند؛ این‌ها جای سناریوی جدید نیستند. [قفل تحویل](../operations/PERSONAL_UPDATE_GUARD.md) همچنان بسته است. هیچ APK تازه‌ای به‌عنوان آپدیت امن تحویل نشده است.

بررسی نام‌های secrets در GitHub با403integration رد شد؛ فقط فهرست cacheها قابل خواندن بود. جست‌وجوی محلی فقط دو کپی fixture عمومی SDK با نام debug.keystore یافت؛ محتوای کلید خوانده نشد. این مشاهدات، نبود کلید اصلی نزد مالک را اثبات نمی‌کنند. وضعیت آن هنوز **UNVERIFIED** است. برای حل اختلاف امضا، برنامهٔ نصب‌شده حذف یا clear-data نشود.
