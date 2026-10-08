# تحویل اصلاح درخواست و نشست Backend

تاریخ: ۲۰۲۶-۱۰-۰۸. شاخه: `fix/backend-request-safety`؛ بسته جدا از APK محلی، بر پایه شاخه `fix/local-task-persistence`.

## تغییر واقعی

- نوشتن Phase 6 از parser و CORS مشترک عبور می‌کند؛ PATCH پروفایل، PUT آموزش و POST رکورد مالک در PostgreSQL ذخیره و با GET خوانده می‌شوند. روش‌های PUT/DELETE برای originهای مجاز قبلی پشتیبانی می‌شوند.
- JSON ناقص و body بیش‌ازحد، پاسخ مشخص ۴۰۰ و ۴۱۳ می‌گیرند. لاگ خطا فقط metadata مجاز دارد؛ error/body/password و جزئیات ردیف خصوصی چاپ نمی‌شوند. پس از شروع پاسخ، جریان بسته می‌شود و خطای خام به handler پیش‌فرض منتقل نمی‌شود.
- JWT معتبر به‌تنهایی برای حساب غیرفعال کافی نیست؛ نشست و refresh با وضعیت فعلی حساب کنترل می‌شوند. بررسی مشترک auth در routerهای اصلی و Phase 6 اجرا می‌شود.
- import تولیدی `server.js` listener پنهان ایجاد نمی‌کند. entrypoint تنها listener عملیاتی را آغاز می‌کند؛ PORT برای import دستکاری نمی‌شود.

## شواهد و حدود

در PostgreSQL مستقل `lifemate_backend_safety` فقط fixture مصنوعی استفاده شد. آزمون‌های جدید child واقعی با `NODE_ENV=production` و HTTP واقعی راه می‌اندازند؛ احراز هویت و ذخیره‌سازی Mock نیستند. دیتابیس و JWT آزمون الزامی‌اند و این آزمون‌ها بدون آن‌ها silently skip نمی‌شوند.

RED اولیه: ۱۵ آزمون، ۱۴ شکست و یک پاس؛ نوشتن ۵۰۰، CORS ناقص، JSON ۵۰۰، لاگ حساس و پذیرش حساب disabled بازتولید شدند. listener import و خطای پاسخ ناقص نیز جداگانه RED شدند. برای پاسخ ناقص، sentinel روی همان stderr پس از فرصت logging معوق Express قرار می‌گیرد و پیش از assertion منتظر تخلیه خروجی می‌ماند؛ fixture نهایی روی handler قدیمی RED و روی اصلاح فعلی GREEN شد.

| بررسی نهایی اجراشده | نتیجه |
|---|---|
| `npm test` روی Node 24.19.0 | ۳۱ پاس، صفر شکست، صفر skip |
| `npm exec --yes --package=node@22 -- npm test` روی Node 22.23.3 | ۳۱ پاس، صفر شکست، صفر skip؛ عامل اصلی نیز مستقلاً تکرار کرد |
| HTTP جدید | ۱۸ regression واقعی؛ ۱۷ مسیر production entrypoint و یک fixture پاسخ ناقص با handler واقعی |
| شش migration روی DB مستقل و چهار SQL suite | پاس |
| `npm run check` و `git diff --check` | پاس |
| بازبینی مستقل source نهایی | یافته مهم یا بحرانی باز در دامنه این اصلاح گزارش نشد |

Commit کد: `148c260e912dc220f862af27fbe4d34be226dfda`. گزارش نتیجه CI و لینک PR پس از ثبت اجرای GitHub اضافه می‌شود. این commit روی سرویس زنده مستقر نشده است.

برای تکرار از `backend/`، `DATABASE_URL` به PostgreSQL آزمایشی دارای migrationها و `JWT_SECRET` مصنوعی با حداقل ۳۲ نویسه تنظیم شود؛ `NODE_ENV=test` برای parent و child آزمون با `production` اجرا می‌شود. اطلاعات محرمانه یا token واقعی در سند قرار نمی‌گیرد.

هیچ migration، استقرار Railway، تغییر DNS/مجوز سرویس یا داده واقعی تغییر نکرد. کدهای family role، رابطه سرپرست و اشتراک منتخب در این بسته دست‌نخورده‌اند. نقص‌های این سیاست‌ها در [ممیزی اولیه](2026-10-08-backend-audit.md) همچنان باقی‌اند؛ سلامت opt-in و آمادگی انتشار عمومی تأیید نمی‌شوند.

گام بعد: قرارداد `profile_category` با حفظ roleهای موجود، یکسان‌کردن مجوز عضویت/سرپرست/اشتراک و جداسازی کش کاربر؛ سپس پذیرش دستگاه و Sync.
