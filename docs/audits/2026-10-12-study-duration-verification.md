# LifeGuide — دقت نمایش زمان مطالعه

بسته کوچک ادامه توسعه مستقل از حضور مالک: شاخه `fix/study-duration-display`، source `d0b3446d736b67fdb4e0218282ad15f0e74fdb55`، [PR13](https://github.com/davoodmehraban89/LifeMate/pull/13) روی PR12. Backend0.7.1 ثابت؛ کلاینت0.7.1+7. نسخه قبلی واقعاً4ثانیه را0دقیقه و90ثانیه را2دقیقه نشان می‌داد. PostgreSQL عدد درست را حفظ کرده بود.

تابع نمایش اکنون ثانیه‌ها را دقیق تفکیک می‌کند:4ثانیه،1دقیقه و30ثانیه؛ صفر و دقیقه کامل مثل25دقیقه حفظ می‌شوند. مجموع برنامه/ثبت، روز، درس و تکلیف همان نمایش را دارند. تایمر، schema، اشتراک و مجوزها تغییر نکردند. label روزانه Flexible شد تا روی RTL باریک جا بگیرد؛ cache عمومی بهv0.7.1-7 تغییر کرد. زمان ثبت‌شده همچنان خوداظهاری/تایمر است و اثبات مطالعه نیست.

## خروجی واقعی

| اجرا | خروجی |
| --- | --- |
| RED widget regression | 7شکست از22؛ missing exact time برای4،29،30،59،61،90 و ردیف‌ها |
| اصلاح formatter | focused22/22 PASS |
| افزودن legacy95seconds و RTL320 | RTL ابتدا RenderFlex73pxoverflow؛ پس از Flexible،24/24 PASS |
| suite کامل Flutter |212/212،44ثانیه؛ formatter69فایل/0تغییر، analyzer `No issues found` |
| worker با نسخه تازه |4/4 PASS؛ fallback عمومی و عدم پاسخ ساختگی به API/config/auth حفظ شد |
| Python helper |syntax و10مرز مدت،3رد زمان غلط PASS؛ wholeminute انتظار، suffix ثانیه اضافه را قبول نمی‌کند |
| release web واقعی |53.6ثانیه؛ localfont/CanvasKit، bootstrap و provenance66input PASS |
| Docker gateway prebuilt | ساخته و روی Compose محلی loopback8445healthy؛ api/postgres/backup قبلی healthy و بدون تغییر |
| Chromium HTTPS واقعی،320pxRTL |23درخواست،refresh200، نشست ذخیره‌شده، گزارش completed با4ثانیه،0external/network/browser/http errors در همین run |
| PostgreSQL مستقل پس از UI |taskcompleted/v6/parent_guardian/planned1800؛ sessioncompleted/timer/recorded4seconds/2intervals |

[Receipt مرورگر/SQL و تصویر](evidence/study-duration-browser-2026-10-12.json). root تصویر واقعی را مشاهده کرد؛ مجموع، روز و درس4ثانیه و تکلیف کامل زیر آن دیده شد. helper دقیق بودن متن ثبت/برنامه را سنجید. JSON reportbody تب restore توسط browser helper خوانده نشده و UNVERIFIED است؛ SQL مستقل اجرا شد. هیچ login تازه، seed، تغییر تایمر یا task برای گرفتن نتیجه جدید لازم نشد.

اولین تلاش GREEN به‌علت مسیر Python اشتباه در cwdاپ، callsiteها را rename نکرد و compile شکست خورد؛ مسیر تصحیح و GREEN واقعی گرفته شد. یک query SQL اولیه escapeنادرست داشت و اجرا نشد؛ heredoc درست با ON_ERROR_STOP هر دو query را واقعاً اجرا کرد. این‌ها تست موفق محسوب نمی‌شوند. لاگ‌های محلی در `/workspace/scratch/study-duration-*` هستند.

بازبین مستقل formatter/callsite/Flexible/tests را خواند؛ ایراد باز پیدا نکرد. falsepositive substring در تست‌یار دقیقه کامل گزارش و اصلاح شد؛ بازبین10مدت/دوprefix و3رد زمان غلط را مستقل بررسی کرد. نسخه pubspec/cache همخوان است. او suiteFlutter را دوباره اجرا نکرد و چنین ادعایی نمی‌شود.

## حدود

[CI38223988983](https://github.com/davoodmehraban89/LifeMate/actions/runs/38223988983) روی همین source واقعاً SUCCESS شد؛ سه job موفق، Backend245/245، role9+96 و restore، Flutter212/212 و analyzer clean. وب و APK0.7.1/code7 ساخته شدند. root ZIP و APK را دانلود و integrity/digest/manifest مستقل بررسی کرد؛ runner واقعاً v2signature را تأیید کرد. [Receipt](evidence/ci-study-duration-2026-10-12.json)، [APK آزمایشی](https://github.com/davoodmehraban89/LifeMate/actions/runs/38223988983/artifacts/11735469546)، [وب](https://github.com/davoodmehraban89/LifeMate/actions/runs/38223988983/artifacts/11734794646). APK168960986bytes، SHA `3a66f37971af6776fc2b22f0f79ed74cc35c68722bbcf5ee8b6c15fd6b41cd37`؛ debugcertificate با قبلی متفاوت است. apksigner محلی موجود نبود؛ نصب و ارتقای دستگاه UNVERIFIED و حذف داده برای رفع تفاوت امضا توصیه نمی‌شود. Android واقعی/نصب/ارتقا، Safari/A2HS، Windows مالک، ایران بدون VPN و امضای release مالک UNVERIFIED. علت ERR_ABORTEDهای قبلی با این اصلاح حل‌شده اعلام نمی‌شود. receiptهای قبلی4sec→0min تاریخی‌اند و تغییر نمی‌کنند. فایل نصبی، API عمومی نمی‌سازد؛ دامنه عمومی/API سازگار و فعال تأیید نشده است. هیچ تغییر DNS/live deploy/realdata/merge/publicrelease/signup/payment انجام نشده است.

بررسی خواندنی تازه دامنه12اکتبر: `/config.json` و `/api/health` هر دوHTTP200/text-html، بدون JSON معتبر بودند. [Receipt](evidence/public-api-paths-2026-10-12.json). این بررسی فقط همان دو مسیر است؛ وضعیت تمام hostها یا دسترسی از ایران را اثبات نمی‌کند و DNS تغییر نکرد. مالک فعلاً اقدام فوری ندارد؛ اجرای رایگان LAN پس از دسترسی به PC و اعتماد CA در [راهنمای تحویل](../operations/HANDOVER_0.7.1.md) است.
