# LifeGuide — بررسی CI و APK آزمایشیِ PR31

این گزارش ادامهٔ بستهٔFlutterاست، نه انتشار محصول. هیچmerge/deploy/DNSیاپایگاه زنده تغییر نکرد.

## VERIFIED با GitHub API

- Draft[PR31](https://github.com/davoodmehraban89/LifeMate/pull/31)، شاخه`feat/flutter-mobile-navigation`،head`c067163033ebcb6862292e6943dedbb543b9056b`،باز وادغام‌نشده.
- اجرای[LifeGuide CI 38906353812](https://github.com/davoodmehraban89/LifeMate/actions/runs/38906353812) باهمینhead،completed/success.
- jobهایsecurity،backend،flutterهمگیsuccess. دوstep«Build test APK (debug certificate; not a release)» و«Inspect the actual APK manifest and debug signature» موفق ثبت شدند.
- artifactشناسه12048063680 با نام`LifeGuide-debug-apk` وsize87902767bytes،expired=false؛webartifactهم موجود است. این اندازهٔZIPartifactاست، نه اندازهAPKاستخراج‌شده.

خواندن این metadata تأیید اجرای CI است؛ buildمحلیAndroid یا نصب روی گوشی از آن نتیجه نمی‌شود. فایلZIPاز اتصال رسمیGitHubدریافت شد؛ SHA256دقیقاًباdigestاعلامیGitHubبرابر بود: `3699fa0efc8e6ca875e980118248db1d7c02b41399bc7eb20a3360677fec3bd3`. سلامتZIPوخواندنmanifestواقعی محلی موفق بود. APKاستخراج‌شده168988950bytesاست؛ package=`ir.lifeguide.app`،label=`لایف‌گاید`،version0.7.1+7،minSDK24/target36،debuggable=true،allowBackup=false،cleartext=false. SHA256APK:`671f29ab5a33f4c170ccbb1af65e3da163eee8125e06a7a531c6de322604042d`. [رسیدprovenance](evidence/android-pr31-2026-10-16/provenance.json) و[manifest](evidence/android-pr31-2026-10-16/manifest.json).

دستور اجراشده: `python apps/lifemate/tool/check_apk_manifest.py <downloaded-apk> --mode debug` →PASS. `hashlib.sha256`رویZIPو`testzip()`آرشیو نیز موفق بودند. apksignerمحلی نصب نیست؛ **امضا مستقلاً محلی UNVERIFIED** است و فقطsuccessمرحلهٔCIبرای آن مشاهده شد. دانلودCLIازمسیرموقت فایل نتیجه نداد؛ اتصال رسمیGitHubفایل را بازیابی کرد. هیچ لینک امضاشده،tokenیاfixtureخصوصی درگزارش/مخزن قرار نگرفت. هیچartifactموقت یا لینک امضاشده درمخزن ذخیره نمی‌شود.

## مانع تصمیمی بعدی

نشست جدیدکودک هنوز به planner/studyقدیمی دسترسی ندارد. پیشنهاد محدود و گزینهٔ حفظ وضعیت در[ADR0015](../decisions/0015-managed-child-education-scope-options.md) برای تصمیم مالک آماده است؛ کدallowlistیاpolicyتغییر نکرده است.

## UNVERIFIED

نصب وارتقایAndroid،آیفون/Safari،امضایreleaseمالک،سرورعمومی،ورودSMSواقعی وپذیرش نشستmanaged-childجدید. خروجیdebugنسخهٔآزمایشی است و بدونBackendHTTPSمجاز، سیستم آنلاین خانواده نمی‌شود. APKنبایدسرویس‌عمومی‌تولید فرض شود؛۲۵/۵نیز هنوز دربستهٔقبلی پیاده نشده است.
