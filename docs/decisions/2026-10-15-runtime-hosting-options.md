# LifeGuide — گزینه‌های محیط اجرا و نشست PWA

- **Status: PROPOSED — منتظر انتخاب صریح مالک**
- تاریخ: ۲۰۲۶-۱۰-۱۵؛ انتخاب‌های H/S در [فهرست تصمیم‌ها](2026-10-15-phase1-decision-index.md).
- هیچ حساب، هزینه، DNS، سرویس، migration، merge یا deploy با این سند مجاز نمی‌شود.

## واقعیت مشاهده‌شده و نیاز

**VERIFIED در ممیزی فاز۰:** `app.lifeguide.ir` صفحه معرفی static است، نه API خانواده. Supabase QA ساختار خصوصی با۲۰migration و۵۹جدول دارای ENABLE/FORCE RLS دارد؛ نقش‌های معمول به آن schema مجوز ندارند و نقش owner دارای BYPASSRLS است. این metadata، اتصال Express یا least-privilege API را ثابت نمی‌کند. اسناد [ممیزی موجود Supabase](../audits/2026-10-15-supabase-current-state.md) و [مرز معرفی عمومی](../operations/PUBLIC_REVIEW_PAGE.md) مبنای زمینه‌اند؛ وضعیت تاریخی DNS در آن‌ها را وضعیت فعلی فرض نکنید.

**UNVERIFIED:** دسترسی کاربر داخل ایران بدون VPN، هزینه/شرایط روز ارائه‌دهنده، قابلیت Node/native Argon2 روی مقصد، نقش DB عملیاتی، HTTPS دستگاه و OTP واقعی. این بسته تحقیق تازه قیمت/دسترسی یا تغییر زیرساخت انجام نمی‌دهد.

مرز صریح مالک: Railway کنار گذاشته شده؛ وجود Supabase QA اعلام/ممیزی شده است؛ دوباره راه‌اندازی Railway یا انتخاب سرویس جایگزین خودکار مجاز نیست. داده واقعی کودک/خانواده/چت خصوصی روی میزبان خارجی ممنوع است. هدف، Android و PWA روی یک API/PostgreSQL با مجوز سرور و بسته قابل‌انتقال است؛ نه دو backend مستقل یا دسترسی مستقیم کلاینت به DB.

## گزینه‌های H

|گزینه|جریان پیشنهادی|فایده|ریسک و مجوز لازم|
|---|---|---|---|
|H-A|Android/PWA ← HTTPS reverse proxy ← Node/Express ← schema خصوصی Supabase QA؛ فقط داده مصنوعی|reuse ساختار۲۰migration بدون بازنویسی API|میزبان Node هنوز انتخاب نشده؛ سازگاری TLS/search_path/role و تأخیر/دسترسی ایران نامعلوم؛ foreign QA مجوز داده واقعی نمی‌دهد|
|H-B|همان API و imageها ← PostgreSQL مستقل روی LAN مالک؛ انتقال بعدی به سرور داخلیِ مورد تأیید|آزمون بدون هزینه میزبانی در LAN و قابلیت جابه‌جایی|LAN برای بیرون خانه قابل دسترسی نیست؛ سرور عمومی، پرداخت، IP و SLA هنوز انتخاب نشده‌اند|

پیشنهاد بررسی: LAN از H-B برای پذیرش اولیه مصنوعی و بدون هزینه؛ H-A فقط اگر مالک بخواهد اتصال QA موجود را جدا بسنجد. مقصد عمومی انتخاب نشده؛ هیچ خرید یا ایجاد حساب پیشنهاد اجرایی این PR نیست. مجازبودن محل واقعی داده نیازمند تصمیم صریح مالک و بررسی حقوقی مربوط است.

در هر گزینه، client ← API تنها مسیر داده باشد؛ credential مالک/DB/service key در client نباشد. همان origin برای app/API و دانلود APK ترجیح پیشنهادی است؛ public Pages فعلی بدون تأیید جدا بازنویسی نشود. API URL از config زمان اجرا بیاید؛ موفقیت health پاسخ‌دهنده با آمادگی DB/مجوزها اشتباه نشود.

## نقش پایگاه داده و جابه‌جایی پیشنهادی

- نقش runtime غیرمالک و بدون BYPASSRLS، نقش migration جدا، deny-all روی schemaهای قابل REST و مجوز function/table صریح پیشنهاد می‌شود. RLS اجباری بدون policy به معنی قابل استفاده‌بودن API نیست؛ برای سبزکردن advisor policy عمومی ایجاد نشود.
- انتخاب H-A پیش از هر استفاده به آزمون synthetic روی همان نسخه PG، search_path ثابت، TLS با اعتبارسنجی CA، hash ledger و ماتریس مجوز نیاز دارد؛ تغییر SQL/RLS زنده مجوز جدا می‌خواهد.
- انتقال پیشنهادی با pg_dump/restore فقط مصنوعی در محیط جدا تمرین شود؛ count/hash، migration ledger، API و بازیابی backup مقایسه شوند. سپس runbook واقعی با پنجره توقف نوشتن، snapshot، DNS cutover و rollback برای تأیید جدا ارائه شود؛ داده واقعی اکنون منتقل نمی‌شود.
- log، backup و crash report نیز داده‌اند؛ محل و مدت نگهداری آن‌ها باید همان مرز مصوب را رعایت کند؛ هیچ payload خصوصی در telemetry یا CI نباشد.

## گزینه‌های S برای نشست مرورگر

**VERIFIED-source در گزارش فاز۰:** main توکن حافظه‌ای دارد؛ PR16 refresh token وب را در localStorage نگه می‌دارد. secure storage بومی، دفاع XSS مرورگر نیست؛ این سند قرارداد موجود را تغییر نمی‌دهد.

|گزینه|رفتار پیشنهادی|محدودیت|
|---|---|---|
|S-A|refresh در cookie با HttpOnly/Secure/SameSite؛ access کوتاه‌عمر در حافظه؛ همان origin|کاهش سرقت refresh با JS؛ CSRF/Origin و single-flight/rotation همچنان لازم‌اند؛ تغییر API نیازمند PR است|
|S-B|bearer و refresh فقط حافظه؛ login مجدد پس از بسته‌شدن کامل|عدم ذخیره refresh در JS پایدار؛ تجربه ورود ضعیف‌تر و فرایند OTP مکرر|

پیشنهاد بررسی S-A است؛ انتخاب نشده. cache شخصی endpoint+user scoped، خروج با پاک‌سازی و اخطار صف ارسال‌نشده، تازگی داده و single-flight در هر انتخاب لازم‌اند؛ token/response خصوصی داخل Service Worker cache قرار نگیرد. مدت نشست و timeout بی‌کاری را مالک باید مستقل مشخص کند.

## معیار پذیرش؛ همه UNVERIFIED در این بسته

- API واقعی/DB و نه صرفاً health روی داده مصنوعی آزموده شود؛ parent مجاز می‌بیند، خانواده دیگر رد می‌شود؛ دسترسی مستقیم کلاینت DB ناممکن باشد.
- Android و Safari واقعی در LAN با HTTPS مورد اعتماد: install/login/restart/refresh/logout و offline queue بدون duplicate؛ سپس آزمون مستقل داخل ایران برای مقصد عمومی.
- نقش runtime/RLS و export/restore مصنوعی آزموده شوند؛ قطع DB، انقضای TLS، quota و rollback پیام خطای روشن بدهند؛ old cache داده را live نشان ندهد.
- روی S-A تست CSRF/Origin/cookie و روی S-B پاک‌شدن حافظه/relogin اجرا شود؛ در هر دو XSS، rotation موازی و خروج/ابطال دستگاه بررسی شوند.
- پیشنهاد infra، runbook، هزینه احتمالی و مرز داده با مالک مرور شوند؛ تصویب ADR هنوز مجوز اجرای زنده، تغییر DNS یا migration واقعی نیست.
