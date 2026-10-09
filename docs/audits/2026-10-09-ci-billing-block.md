# LifeGuide — توقف CI پیش از شروع job

بررسی واقعی در ۲۰۲۶-۱۰-۰۹ UTC، با اتصال رسمی GitHub و CLI تنظیم‌شده محیط؛ مقدار credential خوانده یا چاپ نشد.

- شاخه: `feat/online-family-stage0`، PR باز و Draft شماره۱۰؛ main تغییر نکرده است.
- commit مستندات/helper: `1c162a50e1d9b7c0129205c46653f80d56d425ea`.
- [attempt 1، run 37813595994](https://github.com/davoodmehraban89/LifeMate/actions/runs/37813595994/attempts/1): آغاز ۲۰۲۶-۱۰-۰۸ ساعت۱۷:۰۳:۲۶، پایان۱۷:۰۳:۳۱ UTC، conclusion=`failure`.
- jobs Backend/security/Flutter: runner name خالی، `steps=[]`؛ هیچ تست یا build شروع نشده است. درخواست log نیز `404 BlobNotFound` داد.

پیام واقعی annotation job Backend:

```text
The job was not started because recent account payments have failed or your spending limit needs to be increased. Please check the 'Billing & plans' section in your settings
```

این متن علت گزارش‌شده GitHub است؛ مشخص نمی‌کند کدام‌یک از دو وضعیت حساب رخ داده. هزینه/سقف/وضعیت پرداخت حساب مستقلاً بررسی نشده و **UNVERIFIED** است. هیچ پرداخت، افزایش سقف، تغییر تنظیم حساب، signup یا rerun هزینه‌زا انجام نشد؛ خرید یا پرداخت راهکار پیشنهادی این بسته نیست.

## شواهد معتبر و مسیر بدون هزینه میزبانی

[run موفق 37810558847](https://github.com/davoodmehraban89/LifeMate/actions/runs/37810558847) روی منبع `7d9366832adaaab4cc3f24ef4d928fddd307fdc9` هر سه job را اجرا کرد:۱۳۰ Backend،۶۴ Flutter، web و APK debug build/upload. [گزارش A–H و artifactها](2026-10-08-online-acceptance.md) شامل نتایج محلی HTTPS، مرورگر والد و restore نیز هست. این شواهد، موفقیت CI آخرین head یا پذیرش Safari/Android واقعی را اثبات نمی‌کنند.

فرمان زیر روی checkout تحویل واقعاً اجرا و diff خالی مشاهده شد:

```bash
git diff --exit-code 7d93668 HEAD -- backend apps/lifemate deployment docker-compose.yml docker-compose.prebuilt-web.yml Dockerfile
```

کد برنامه/Backend/بسته استقرار نسبت به منبع موفق تغییر ندارد؛ helper مرورگر مستقل روی HTTPS محلی آزموده و نحو آن بررسی شد. تغییر نهایی فقط مستندات است و با `[skip ci]` فرستاده می‌شود؛ این skip، نتیجه PASS برای CI نیست. PR تا پذیرش و رفع گیت‌ها Draft می‌ماند.

برای آزمون بدون هزینه میزبانی، [Stage 0](../operations/STAGE0.md) و artifact وب prebuilt یا build واقعی Flutter3.47.6 محلی را استفاده کنید. دستورهای آزمون محلی در README و همان راهنما هستند. گوشی‌ها روی LAN به یک origin/API/PostgreSQL وصل می‌شوند؛ هیچ حساب میزبان خارجی لازم نیست. فقط داده ساختگی و یک تب/PWA فعال در هر browser profile استفاده شود. راه‌اندازی Windows و پذیرش دستگاه مالک همچنان **UNVERIFIED** است. سرویس زنده، DNS و داده واقعی تغییر نکردند.

پاک‌سازی محیط توسعه در۲۰۲۶-۱۰-۰۹: فقط گواهی عمومی آزمون `LifeGuide-Stage0-testCA-20261008` از NSS مرورگر محیط حذف و باقی‌ماندن گواهی‌های موجود تأیید شد؛ گواهی/تنظیم گوشی یا رایانه مالک تغییر نکرد. برای تکرار browser smoke، اعتماد عادی CA آزمون باید دوباره مطابق runbook آماده شود؛ TLS bypass وجود ندارد.

## رفع مانع و اجرای واقعی دوباره

پس از اعلام مالک مبنی بر رفع محدودیت، درخواست rerun در GitHub واقعاً اجرا شد. [attempt 2](https://github.com/davoodmehraban89/LifeMate/actions/runs/37813595994/attempts/2) روی همان commit `1c162a50e1d9b7c0129205c46653f80d56d425ea` هر سه job را با conclusion=`success` تمام کرد: backend `113688484014`، Flutter `113688483744` و security `113688483996`. log واقعی۱۳۰ تست Backend،۶۴ تست Flutter و build/upload وب و debug APK در۲۰۲۶-۱۰-۰۹ را نشان داد.

artifact تازهٔ [LifeGuide-web](https://github.com/davoodmehraban89/LifeMate/actions/runs/37813595994/artifacts/11597771814) با digest ZIP `5ad69d44ccfb30fb959fc826680ce50d800e39aed9a3cbf4791aa7346549996e` و [LifeGuide-debug-apk](https://github.com/davoodmehraban89/LifeMate/actions/runs/37813595994/artifacts/11598037633) با digest ZIP `80a41df8a35c694fa1e1c7aa21dbc2365d1e58d6763fc624c664d8b7f46dde06` ثبت شدند. این digestها متعلق به archive GitHub هستند؛ digest خود APK یا نصب گوشی نیستند. دریافت مستقل APK در این محیط با `Forbidden` متوقف شد و **UNVERIFIED** باقی ماند.

محدودیت CI اکنون مانع فعال نیست. این نتیجه فقط منبع همان attempt را پوشش می‌دهد؛ اصلاحات جدید نقش DB/نشست وب آزمون و run جدا دارند. هیچ تنظیم حساب، پرداخت، سرور زنده، DNS یا merge انجام نشد. توضیحات توقف بالا، سابقهٔ attempt 1 هستند.
