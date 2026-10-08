# LifeGuide — شواهد تحقیق میزبانی، 2026-10-08

مسئول این زیرکار: Product & Research. دامنه: تحقیق فقط خواندنی و ADR؛ کد استقرار و نتیجه اجرای Compose در بسته جدا ثبت می‌شود. [ADR 0009](../decisions/0009-provider-neutral-hosting.md) تصمیم عملی را توضیح می‌دهد.

## چه چیزی واقعاً انجام شد

- `AGENTS.md` و `PROJECT_STATE.md` روی شاخه `feat/online-family-stage0` پیش از کار خوانده شدند. سند وضعیت موجود همچنان نام و ادعاهای تاریخی میزبانی را دارد؛ دستور جدید مالک درباره نام LifeGuide، کنارگذاشتن Railway و ممنوعیت تغییر زنده مقدم است.
- با ابزار وب واقعی جست‌وجو و سپس صفحات رسمی زیر باز شد؛ اطلاعات از حافظه یا پیشنهاد قدیمی پلن‌ها برداشت نشده است. تاریخ مشاهده 2026-10-08 است.
- اسکریپت‌های موجود `backend/scripts/backup.sh` و `restore.sh` خوانده شدند: `pg_dump` custom، حذف owner/privilege و `pg_restore --clean --if-exists --exit-on-error`. این مطالعه، اجرای backup/restore نیست.
- هیچ account، VM، خرید، ticket، ارسال پیام به فروشنده، تغییر DNS، تغییر سرور یا انتقال داده واقعی انجام نشد.

## دفتر شواهد رسمی

| منبع بازشده | مشاهده قابل استناد | چه چیزی را اثبات نمی‌کند |
|---|---|---|
| [Docker Windows installation](https://docs.docker.com/desktop/setup/install/windows-install/) | راه نصب Windows/WSL و رایگان بودن Docker Desktop برای personal use در مستند رسمی | دانلود بدون VPN در ایران، نصب روی PC مالک یا اجرای پروژه |
| [mkcert repository](https://github.com/FiloSottile/mkcert) | تولید CA/certificate محلی؛ موبایل نیازمند نصب CA؛ کلید CA نباید توزیع شود؛ ابزار برای development است | TLS Flutter Android یا Safari روی دستگاه واقعی این پروژه |
| [Apple certificate trust](https://support.apple.com/en-us/102390) | نصب دستی profile به‌تنهایی SSL trust نمی‌دهد؛ full trust باید در Certificate Trust Settings فعال شود | نصب PWA، نشست، refresh یا صحت داده روی Safari مالک |
| [Android network security configuration](https://developer.android.com/privacy-and-security/security-config) | debug-overrides می‌تواند CAهای توسعه را به app debuggable اضافه کند | اینکه `dart:io HttpClient` همین تنظیم native را به‌کار می‌برد؛ transport باید جدا آزموده شود |
| [TurkVPS.cloud plans](https://turkvps.cloud/) | صفحه رسمی Istanbul KVM/root/IPv4 همراه پلن و قیمت 1 GB=$3.44، 2 GB=$4.50، 4 GB=$7.50 ماهانه را نشان می‌دهد | عملکرد/ظرفیت واقعی، اعتبار حقوقی/عملیاتی شرکت، قیمت نهایی پس از ثبت، مناسب بودن پلن برای بار پروژه |
| [TurkVPS crypto page](https://turkvps.cloud/buy-turkey-vps-crypto) | فروشنده می‌گوید مسیر USDT/TRX بدون کارت و با ایمیل است | پذیرش اقامت ایران، توان یا مجوز پرداخت مالک، پذیرش واقعی سفارش، ثبات این سیاست |
| [TurkVPS terms](https://turkvps.cloud/terms) — last updated 2026-10-02 | موجودی ناکافی در تمدید می‌تواند حذف فوری و برگشت‌ناپذیر داده بدهد؛ ضمانت بازگشت 24 ساعته برای کارت است و رمزارز بازپرداخت به مبدأ ندارد؛ backup مسئولیت مشتری است | امنیت backup، کیفیت پشتیبانی یا جبران خسارت واقعی |
| [TurkVPS looking glass](https://turkvps.cloud/looking-glass) | فروشنده test IPv4 `37.221.79.1` و فایل تست ارائه می‌کند؛ ~20 ms تهران ادعای خودش است | probe از ایران اجرا نشده؛ دسترسی IP تحویلی، دامنه نهایی/API/TLS/APK/PWA، پایداری هنگام اختلال یا اعتبار IP |
| [Oracle Free Tier FAQ](https://www.oracle.com/cloud/free/faq/) | Always Free واقعی وجود دارد اما مسیر عمومی ثبت کارت credit/debit می‌خواهد؛ اطلاعات تماس/صورتحساب باید معتبر باشد | مسیر رایگان **بدون کارت** برای این مالک، پذیرش ایران یا ظرفیت VM |
| [THE.Hosting test VPS](https://the.hosting/en/test-vps) | فقط trial سه‌روزه با signup، ticket و KYC؛ فروشنده اختیار رد دارد | VPS رایگان بلندمدت، بی‌نیاز از KYC یا قابل استفاده برای مالک. پیوند signup باز/اجرا نشد |
| [Melbicom USDT guidance](https://www.melbicom.net/solutions/buy-server-with-usdt/) | اولین پرداخت برای mandatory KYC باید با روش دیگری باشد؛ سپس crypto از invoice BitPay ممکن است | مسیر پرداخت عملی مالک ایران؛ صرف لوگوی رمزارز کافی نیست |
| [BitPay jurisdictions](https://support.bitpay.com/hc/en-us/articles/360000123366-What-countries-or-jurisdictions-does-BitPay-support) — updated 2026-10-03 | ایران صریحاً در blocked jurisdictions است | دسترسی مستقیم API خودمیزبان در ایران؛ این محدودیت متعلق به پرداخت BitPay است |
| [Hetzner payment overview](https://docs.hetzner.com/general/billing-and-account-management/billing-at-hetzner/payment-overview/) — last changed 2026-07-28 | کارت، SEPA، transfer یا PayPal؛ روش‌ها در همه کشورها یکسان نیستند؛ crypto پذیرفته نمی‌شود | روش عملی پرداخت مالک یا پذیرش ثبت‌نام ایران |
| [PQ.Hosting About](https://www.pq.hosting/en/about) — last updated 2026-02-01 | سایت خودش را comparison platform معرفی می‌کند و سفارش/پرداخت را به provider منتخب واگذار می‌کند | اطلاعات قدیمی که PQ.Hosting را یک provider واحد با شرایط ثابت فرض کند |

این جدول مطالب منابع را خلاصه می‌کند؛ گواهی مستقل برای کیفیت فروشنده نیست. TurkVPS «نامزد تحقیق» است، نه توصیه خرید. نبود گزینه رایگان تأییدشده نتیجه همین بررسی است؛ ادعای نبود تمام گزینه‌های ممکن جهان نیست.

## محدودیت‌ها و پذیرش موردنیاز

**UNVERIFIED:** دسترسی endpoint نهایی از داخل ایران بدون VPN، مسیر پرداخت مالک، ثبت‌نام/KYC ایران، IP reputation، uptime، داده‌گردانی/backup فروشندگان، اجرای Docker روی Windows مالک، Android واقعی، iPhone/iPad Safari، Add to Home Screen و API round-trip از شبکه مالک.

برای مقایسه دسترسی، tester داخل ایران باید تاریخ/ساعت، اپراتور، Wi-Fi یا mobile، خاموش بودن VPN و نتیجه TLS/health/PWA/APK/API را ثبت کند. شناسه دستگاه شخصی، IP عمومی tester و token ورود لازم نیست در گزارش عمومی یا چت قرار گیرد. بررسی ICMP/looking glass فقط سرنخ شبکه است؛ جای HTTPS و سناریوی کاربردی را نمی‌گیرد.

در LAN، PC و گوشی باید origin یکسان داشته باشند. روی iPhone، `localhost` به خود گوشی اشاره می‌کند. HTTPS با CA توسعه باید بدون suppress/skip verification آزموده شود. توسعه‌دهنده می‌تواند registry/tooling را با VPN یا انتقال آفلاین آماده کند؛ این امر معیار «کاربر نهایی بدون VPN» را برآورده نمی‌کند.

اطلاعات خصوصی خانواده، notes، chat، health/cycle و wellbeing واقعی در این تحقیق یا میزبان خارجی به‌کار نرفته است. موضوع رضایت کودکان و محل نگهداری سلامت داخل کشور نیازمند تصمیم جداست؛ سرویس خارجی AI/voice انتخاب یا فعال نشده است.

## بازبینی لازم پیش از تصمیم هزینه‌دار

مالک باید قیمت همان روز، IPv4 واقعی، هزینه تمدید، شرایط حذف داده، روش پرداخت اولیه/تمدید و صلاحیت اقامت ایران را شخصاً تأیید کند. بدون این تأیید، Stage 0 مسیر قابل بررسی است. تغییر به سرور داخلی با همان Compose و backup PostgreSQL طراحی می‌شود؛ جابه‌جایی داده واقعی و DNS به تأیید جدا نیاز دارد و در این کار انجام نشده است.
