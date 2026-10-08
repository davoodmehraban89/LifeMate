# تصمیم ۰۰۰۸ — مسیر مشترک درخواست و نشست API

تاریخ: ۲۰۲۶-۱۰-۰۸. دامنه: اصلاح خرابی‌های بازتولیدشده در entrypoint موجود، بدون استقرار یا migration.

Phase 6 مانند Phase 3 و Phase 4 داخل app مشترک و پس از CORS و JSON parser محدود نصب می‌شود. entrypoint لایه request context، telemetry و rate limit را روی همین app قرار می‌دهد. import کردن `server.js` listener ایجاد نمی‌کند؛ شروع مستقیم `node src/server.js` برای سازگاری حفظ می‌شود. در اجرا با `npm start` تنها listener اصلی entrypoint فعال است.

تمام routerها از بررسی مشترک امضای JWT، issuer/audience، نشست معتبر/منقضی‌نشده/لغونشده و حساب دارای `disabled_at is null` استفاده می‌کنند. refresh نیز حساب فعال را در همان تراکنش کنترل می‌کند. نقش‌های خانواده، سیاست سرپرست و schema پروفایل تغییر نمی‌کنند.

handler خطا فقط metadata مجاز ثبت می‌کند. JSON ناقص ۴۰۰، body بیش‌ازحد ۴۱۳، origin نامجاز ۴۰۳ و خطای غیرمنتظره ۵۰۰ می‌گیرد. خطا پس از شروع پاسخ با بستن پاسخ خاتمه می‌یابد؛ شیء خام خطا به Express finalhandler یا socket منتقل نمی‌شود تا message/stack حساس چاپ نشود.

معیار پذیرش: HTTP واقعی production entrypoint با PostgreSQL مستقل؛ نوشتن و خواندن دوباره Phase 6، CORS/preflight، بدنه نامعتبر، لاگ حساس، لغو حساب و refresh، و نبود listener پنهان. آزمون HTTP پاسخ ناقص نیز بسته‌شدن جریان و نبود marker خصوصی در stderr را بررسی می‌کند. نتایج در [گزارش بسته](../audits/2026-10-08-backend-request-safety.md) ثبت می‌شوند.

این تصمیم، نقص‌های باقی‌مانده اشتراک منتخب/سرپرست، حریم خصوصی یادداشت مدرسه، رضایت سلامت، `profile_category` یا Sync را رفع نمی‌کند. انتشار عمومی همچنان نیازمند تکمیل آن‌ها و مجوز مربوط به انتشار است.
