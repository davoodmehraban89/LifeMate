# LifeGuide — بسته اصلاح هویت در فاز۱

این بسته بر شاخه `fix/auth-abuse-expiry-safety` و مبنای PR14 در `5da6c4290e422162c13c3fe5260345770dde7ffa` است؛ **در main ادغام نشده و سرویس زنده اصلاح‌شده محسوب نمی‌شود**. استفاده از کد سالم موجود عمدی است؛ این PR ورود/خانواده/کتابخانه را بازسازی نمی‌کند. نسخه Backend همان0.7.1 است؛ تغییرات هنوز Unreleased هستند.

## طراحی محدود و معیار پذیرش

- شمار درخواست auth/session باید در دو فرایند و پس از restart مشترک بماند؛ شماره و IP محدودیت مستقل دارند. محدودیت شماره/OTP هش‌شده۵دقیقه‌ای/۵تلاش از مبنا حفظ می‌شود؛ IP اکنون DB-based است.
- یک‌بارمصرف، refresh و OTP منقضی‌شده هنگام انتظار قفل نباید پذیرفته شوند. ساعت پس از گرفتن قفل‌ها در statement تازه خوانده شود؛ `now()` آغاز تراکنش کافی نیست.
- داشتن credential پیامک به معنی اجازه ارسال نیست؛ تا تأیید مالک و الگو، وضعیت `APPROVAL_REQUIRED` و بدون شبکه باشد. development از adapter تزریقیِ fixture استفاده می‌کند؛ مسیر تولید OTP debug در پاسخ یا لاگ ندارد.
- اجرای production باید از `npm start`/`src/entrypoint.js` باشد؛ listener مستقیم `server.js` نباید middleware مشترک را دور بزند.
- بیست Migration اصلی و سه فایل Supabase تاریخی نباید تغییر کنند؛ هیچ داده/DDL/سرویس زنده در این بسته تغییر نکند.

## تغییرات واقعی

**VERIFIED-source/runtime محلی:** `auth_rate_limit.js` برای مسیرهای auth و session شمارنده اتمیک PostgreSQL دارد؛ کلید تنها HMAC دامنه‌دار IP canonical با JWT_SECRET موجود است. IPv4 و IPv6 معادل یک سهمیه دارند؛ هدر forwarding فقط طبق allowlist معتبر Express اثر دارد. ساعت DB پس از advisory lock خوانده می‌شود. خطای SQL/قفل پاسخ عمومی503 می‌دهد و به counter حافظه‌ای fallback نمی‌کند. share حافظه‌ای general/AI باقی است؛ auth دوباره شارژ نمی‌شود.

Migration افزایشی `0023_auth_ip_rate_limit.sql` فقط profile،digest،window و count دارد؛ IP خام، شماره، OTP، userId یا body در آن ذخیره نمی‌شود.0021/0022 برای کار ناتمام قبلی در worktree دیگر رزرو مانده‌اند و وارد این PR نمی‌شوند. runtime-role allowlist جدول جدید را شامل می‌شود. `pruneExpiredAuthRateLimits` حداکثر۵۰۰ ردیف منقضی را با `SKIP LOCKED` پاک می‌کند؛ **هیچ cron/worker یا زمان‌بندی خارجی ایجاد نشده است**. JWT secret باید میان replicaها یکسان باشد؛ چرخش آن quota را هم عوض می‌کند.

مصرف email/reset token، refresh و OTP پس از قفل account و row، انقضا را با `clock_timestamp()` در statement بعدی بررسی می‌کند. cooldown شماره نیز بعد از قفل با زمان تازه محاسبه می‌شود. Argon2id، digest tokenها، rotation نشست، schema و issuer/audience حفظ شدند.

`SMS_PROVIDER` همچنان disabled است. انتخاب Kavenegar علاوه بر credential به دو مقدار دقیق `SMS_LIVE_ENABLED=true` و `KAVENEGAR_TEMPLATE_APPROVED=true` نیاز دارد؛ webhook نیز live flag می‌خواهد. `.env.example` هر دو را false می‌گذارد. این مقادیر هرگز توسط کلاینت تنظیم نمی‌شوند؛ نوشتن true مدرک تأیید یا مجوز عملیاتی نیست. هیچ ارسال واقعی انجام نشد.

QA SQL builder اکنون **منبع۲۱تایی**۰۰۰۱–۰۰۲۰+۰۰۲۳ را صریح می‌پذیرد و lockdown را حفظ می‌کند؛ baseline زنده Supabase همچنان همان۲۰ Migration ممیزی‌شده است. SQL خروجی جدید روی QA اجرا نشده و برای اجرای دوباره روی schema موجود طراحی نشده است. گرفتن21entry از generator به معنی اعمال21migration نیست. hash همه۲۰ فایل اصلی و هر۳bundle تاریخی نسبت به مبنا یکسان تأیید شد.

## RED → GREEN و شواهد اجرا

**VERIFIED / Node24.19.0، PostgreSQL16.15، فقط fixture مصنوعی loopback:**

|فرمان|خروجی واقعی|
|---|---|
|`node --test tests/auth_post_lock_expiry.test.js tests/sms_approval_gate.test.js` پیش از اصلاح، با اجرای ترتیبی|۶شکست/۱موفق؛۴مسیر منقضی به‌اشتباه200/204 و۲حالت SMS فعال بودند|
|همان مسیرهای expiry/provider همراه تست‌های adapter پس از اصلاح|۲۳/۲۳ موفق؛ بدون provider زنده|
|`node --test tests/auth_ip_rate_limit.test.js` پیش از اصلاح|دو فرایند۶درخواست پذیرفتند، انتظار۳؛ RED|
|آزمون‌های جدید IP و رگرسیون NAT/proxy/operations|۱۴/۱۴ موفق؛۷تست جدید PG/HTTP؛ تکرار مستقل NAT نیز۱/۱ موفق|
|تست واقعی `production_entrypoint.test.js`|RED: listener قدیمی باز ماند؛ GREEN: exit1 با دستور امن و بدون listener؛ بازبین مستقل هم۱/۱ موفق|
|`npm run migrate`، تکرار، import کاتالوگ و تکرار|همه exit0؛۲۱migration محلی؛ کاتالوگ همچنان DRAFT|
|چهار فایل `*schema_test.sql` با `psql -v ON_ERROR_STOP=1`|هر۴ اجرا exit0 و rollback fixture|
|`npm test -- --test-concurrency=1`، بدون فیلتر فایل/نام|**۲۷۱تست،۲۷۱pass،۰fail/cancelled/skip**؛79.28s|
|`npm run check` و `git diff --check`|هر دو exit0|
|بازبینی مستقل|۲۳تست provider/bundle/direct-start، alias probe و مقایسه بایت Migrationها موفق؛ هیچ critical/important حل‌نشده در تغییرات محدود گزارش نشد|

برای اجرای کامل، DB محلی قدیمیِ آزمایشی با نام مجاز موقتاً با catalog rename حفظ شد؛ DB تازه با همان نام برای fixtureها ساخته، پس از تست حذف و نام قبلی بازگردانده شد. داده کاربردی DB قبلی خوانده/تغییر نکرد. env محلی خصوصی بود و در Git/گزارش قرار نگرفت. اجرای اولیه filtered baseline به‌دلیل resourceهای moduleهای skipشده متوقف شد و موفق گزارش نمی‌شود؛ اجرای کامل بالا بدون فیلتر است. اولین harness تست expiry نیز مسیر HTTP اشتباه داشت؛ پس از اصلاح harness، RED واقعی با وضعیت200/204 مشاهده شد، سپس کد اصلاح شد.

## محدودیت و ادامه

**UNVERIFIED در این بسته:** Node22 محلی، ساخت تازه Flutter/APK، امضای release، Android/Safari، SMS واقعی/تأیید الگو، اتصال عملیاتی Express به Supabase، تست شبکه ایران، backup/restore و نقش runtime واقعی در اجرای محلی جدید. CI/دستگاه تا مشاهده خروجی خودشان تأیید نمی‌شوند. import/restore/CI قدیمی به این patch نسبت داده نمی‌شود.

این اصلاح **فاز۱ کامل نیست**: سرپرستی/رضایت/QR کودک، مشتقات چت خصوصی در حالت حساس، cycle plaintext در حالت بازشده، باقی audit/validation و session-after-wait در مسیرهای دیگر هنوز به بسته و تصمیم جدا نیاز دارند. AI خارجی در مبنا خاموش و sensitive پیش‌فرض بسته بود؛ این PR سیاست آن‌ها را تغییر نداده است. private PWA session/retention و زیرساخت نیز نیازمند انتخاب ADR هستند. main/PWA عمومی همچنان نسخه معرفی‌اند.

ادغام/انتشار بدون تأیید مالک ممنوع است. پس از ادغام‌های مصوب، ابتدا21migration در DB مصنوعی محلی، سپس آزمون‌ها اجرا شوند. قبل هر اتصال remote باید schema/search_path، نقش runtime، TLS معتبر و Migration افزایشی متناسب با QA موجود جدا بررسی/تأیید شوند؛ `migrate.js` عمومی را کورکورانه روی lifeguide_qa اجرا نکنید. برای تست توسعه از fixture محلی و `SMS_PROVIDER=disabled` استفاده کنید؛ فعال‌کردن هر دو flag پیامک و ارسال واقعی هنوز مجوز جدا می‌خواهد.
