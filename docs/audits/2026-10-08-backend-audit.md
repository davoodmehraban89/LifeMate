# ممیزی بک‌اند، دامنه و حریم خصوصی LifeMate

تاریخ: ۲۰۲۶-۱۰-۰۸. مبنای کد: commit `796d6be` روی شاخهٔ `fix/local-task-persistence`. این گزارش نتیجهٔ خواندن کد و اجرای تازهٔ آزمون‌ها در محیط محلی است؛ تأیید وضعیت فعلی Railway، Neon، محیط واقعی یا انتشار محصول محسوب نمی‌شود. هیچ کد اجرایی بک‌اند، migration در محیط واقعی، حساب واقعی یا استقرار در این ممیزی تغییر نکرد.

## نتیجهٔ اصلی

بک‌اند یک پیاده‌سازی واقعی Node/PostgreSQL با ذخیره‌سازی پایدار است. هر شش migration روی PostgreSQL مستقل اجرا شدند، ۳۳ جدول عمومی ساخته شد، چهار فایل آزمون SQL و ۱۳ آزمون Node پاس شدند. با این حال اجرای مستقیم entrypoint عملیاتی چند خرابی مهم را نشان داد که آزمون‌های فعلی پوشش نمی‌دهند: ثبت بدنهٔ حساس در لاگ خطا، باقی‌ماندن دسترسی حساب غیرفعال و سرپرست حذف‌شده، ناهماهنگی لغو اشتراک منتخب، و خطای ۵۰۰ در نوشتن داده‌های Phase 6. این ایرادها اصلاح نشده‌اند و مانع اتکا به عبارت «آمادهٔ انتشار» هستند.

پکیج فعلی بازیابی/ماندگاری محلی باید از این اصلاحات جدا گزارش شود. پاس‌شدن آزمون‌های موجود به معنی رفع این مسدودکننده‌ها نیست.

## محیط و شواهد آزمون

- Node `v24.19.0` و npm `11.9.0`؛ حداقل اعلام‌شدهٔ پروژه Node 22 است. اجرای فعلی روی Node 22 تکرار نشده است.
- PostgreSQL `16.15` در کانتینر مستقل `lifemate-audit-postgres-20261008`؛ پورت تنها روی `127.0.0.1:55432` باز شد. هیچ دادهٔ واقعی استفاده نشد.
- دیتابیس‌های `lifemate_audit`، `lifemate_audit_migrator` و `lifemate_audit_restore` فقط دادهٔ مصنوعی داشتند. کانتینر برای تکرار آزمون توسط هماهنگ‌کننده روشن نگه داشته شد.
- وابستگی‌ها با `npm install --package-lock=false` نصب شدند؛ فایل اجرایی tracked تغییر نکرد. برای audit یک package lock موقت بیرون مخزن ساخته شد. مخزن در مبنای ممیزی lockfile بک‌اند ندارد؛ نتیجهٔ audit مربوط به نسخه‌های resolveشده در همین اجراست.
- هیچ مقدار secret، token، رمز واقعی یا بدنهٔ خصوصی واقعی در این گزارش درج نشده است.

| بررسی اجراشده | نتیجهٔ مشاهده‌شده | محدودیت ادعا |
|---|---|---|
| نصب وابستگی‌های بک‌اند | ۱۱۱ بسته نصب شد؛ exit 0 | نسخه‌ها بدون lockfile ثابت نیستند |
| migrationهای `0001` تا `0006` با `psql -v ON_ERROR_STOP=1` | هر شش فایل پاس؛ ۳۳ جدول عمومی | دیتابیس خالی محلی، نه schema زنده |
| `schema_test.sql`، `phase3_schema_test.sql`، `phase4_schema_test.sql`، `phase6_schema_test.sql` | هر چهار فایل پاس؛ exit 0 | شامل بررسی helper/constraint/schema؛ پوشش کامل HTTP یا RLS نیست |
| `npm test` با دیتابیس واقعی محلی و `NODE_ENV=test` | ۱۳ پاس، ۰ شکست، ۰ skip؛ exit 0 | ۴ آزمون HTTP به دیتابیس واقعی وصل‌اند؛ ۹ آزمون متن کد/سند را با regex بررسی می‌کنند |
| `npm run check` | بررسی syntax شش فایل JS پاس؛ exit 0 | بررسی syntax، نه رفتار runtime |
| `npm audit --audit-level=high` در دایرکتوری موقت | ۰ vulnerability؛ exit 0 | scan وابستگی است، نه ممیزی منطق مجوز |
| `npm run migrate` روی دیتابیس خالی دوم، سپس تکرار فوری | بار اول شش migration؛ بار دوم هیچ اجرای مجدد؛ ledger دارای ۶ ردیف | upgrade دادهٔ قدیمی، drift و اجرای هم‌زمان بررسی نشد |
| `backup.sh` و `restore.sh` با دیتابیس مقصد خالی محلی | marker با نام `Restore Smoke` برابر ۱؛ تعداد جدول‌ها ۳۳؛ exit 0 | بازیابی محلی ساختار/داده؛ بازیابی سرویس واقعی و زمان RTO/RPO بررسی نشد |
| smoke HTTP با `NODE_ENV=production` و entrypoint واقعی | خرابی‌های جدول بعدی بازتولید شدند | fixture مصنوعی و curl/fetch محلی؛ مرورگر/گوشی واقعی بررسی نشد |

چهار آزمون HTTP فعلی عبارت‌اند از identity/family، عدم افشای وجود حساب در پاسخ forgot-password، Phase 3 planner/school/family و Phase 4 learning/wellbeing/safety. این آزمون‌ها `app` را از `server.js` import می‌کنند؛ `entrypoint.js` عملیاتی، middleware بیرونی و HTTP نوشتن Phase 6 را اجرا نمی‌کنند. آزمون‌های Phase 6 فعلی فقط وجود متن قابلیت‌ها/جدول‌ها را بررسی می‌کنند. CI در [ci.yml](../../.github/workflows/ci.yml) همان تفاوت را دارد.

دستورهای اصلی اجراشده، از ریشهٔ مخزن مگر آنکه محل دیگری ذکر شود:

```bash
docker run --detach --name lifemate-audit-postgres-20261008 \
  --publish 127.0.0.1:55432:5432 \
  --env POSTGRES_HOST_AUTH_METHOD=trust --env POSTGRES_DB=lifemate_audit postgres:16

# از backend/
npm install --package-lock=false
# JWT_SECRET محلی با حداقل ۳۲ نویسه در محیط آزمون تنظیم شد؛ مقدار آن درج نمی‌شود.
DATABASE_URL=postgresql://postgres@127.0.0.1:55432/lifemate_audit NODE_ENV=test npm test
npm run check

# از ریشهٔ مخزن
for migration in backend/migrations/*.sql; do
  docker exec -i lifemate-audit-postgres-20261008 \
    psql -U postgres -d lifemate_audit -v ON_ERROR_STOP=1 < "$migration" || exit 1
done
for sql_test in backend/tests/schema_test.sql backend/tests/phase3_schema_test.sql \
  backend/tests/phase4_schema_test.sql backend/tests/phase6_schema_test.sql; do
  docker exec -i lifemate-audit-postgres-20261008 \
    psql -U postgres -d lifemate_audit -v ON_ERROR_STOP=1 < "$sql_test" || exit 1
done

# از backend/؛ ledger مستقل
DATABASE_URL=postgresql://postgres@127.0.0.1:55432/lifemate_audit_migrator npm run migrate
DATABASE_URL=postgresql://postgres@127.0.0.1:55432/lifemate_audit_migrator npm run migrate

# package.json به دایرکتوری موقت /tmp کپی شد؛ سپس از همان دایرکتوری
npm install --package-lock-only --ignore-scripts
npm audit --audit-level=high

# backup/restore با نسخهٔ کپی‌شدهٔ اسکریپت‌های مخزن داخل کانتینر اجرا شد
docker exec -e DATABASE_URL=postgresql://postgres@localhost/lifemate_audit \
  lifemate-audit-postgres-20261008 bash /tmp/lifemate-backend-audit/backup.sh \
  /tmp/lifemate-backend-audit/restore-drill.dump
docker exec -e DATABASE_URL=postgresql://postgres@localhost/lifemate_audit_restore \
  lifemate-audit-postgres-20261008 bash /tmp/lifemate-backend-audit/restore.sh \
  /tmp/lifemate-backend-audit/restore-drill.dump
```

## خرابی‌های بازتولیدشده

اولویت «بالا» در این جدول به معنی نیاز به اصلاح پیش از انتشار عمومی/اتکا به مجوزهای حساس است. این ممیزی هیچ‌یک را رفع نکرده است.

| مورد | شاهد فعلی و نتیجهٔ واقعی | اقدام لازم |
|---|---|---|
| بالا: لاگ‌کردن رمز/دادهٔ خصوصی در خطا | [server.js:610](../../backend/src/server.js#L610) تمام `err` را با `console.error` می‌نویسد. POST JSON ناقص به `/v1/auth/login` با یک password کاملاً مصنوعی، HTTP 500 داد؛ capture لاگ نشان داد هم `err.body` و هم نشانگر رمز مصنوعی ثبت شده‌اند. handler بیرونی امن این خطا را دریافت نمی‌کند. | یک مسیر مشترک خطای sanitizeشده؛ body، token و جزئیات ردیف DB وارد لاگ نشوند؛ malformed JSON پاسخ مناسب 400 بگیرد. ادعای نشت جزئیات ردیف DB فعلاً مبتنی بر ساختار خطا/خواندن کد است، نه بازتولید جداگانه. |
| بالا: غیرفعال‌شدن حساب نشست موجود را قطع نمی‌کند | [server.js:98](../../backend/src/server.js#L98)، [server.js:254](../../backend/src/server.js#L254) و [phase6.js:13](../../backend/src/phase6.js#L13) فقط `auth_session` را می‌خوانند. پس از تنظیم `app_user.disabled_at` در fixture، GET `/v1/profile` همچنان 200 داد؛ POST `/v1/auth/refresh` نیز 200 و access token جدید داد. login برعکس، disabled را بررسی می‌کند. | بررسی کاربر فعال در auth/refresh و یک adapter مشترک؛ آزمون revocation حساب در تمام routerها. |
| بالا: سرپرست حذف‌شده هنوز خلاصهٔ تحصیلی می‌بیند | [phase3.js:522](../../backend/src/phase3.js#L522) تنها `guardian_relationship.active` را کنترل می‌کند. بعد از تنظیم `family_membership.ended_at` سرپرست، `/support-summary` باز هم 200 و عنوان تکلیف مصنوعی خصوصی را داد؛ همان fixture در `/wellbeing-summary` پاسخ 403 گرفت. | استفادهٔ یکسان از سیاست عضویت/رابطهٔ فعال؛ آزمون حذف سرپرست و حذف فرزند. |
| بالا: معیار نقش سرپرست ناهماهنگ است | `is_active_guardian` در [0001:108](../../backend/migrations/0001_identity_family.sql#L108) نقش‌ها را بررسی می‌کند؛ `can_view_student_academic` و helper Phase 4 فقط رابطه و عضویت فعال را می‌سنجند. با تغییر نقش fixture به `adult_member`، helper سخت‌گیر false، helper تحصیلی true و HTTP wellbeing-summary برابر 200 شد. | یک سیاست معتبر مرکزی برای نقش جاری/رابطه؛ regression برای تغییر نقش. قبول دو دعوت pending با نقش متفاوت یک مسیر بالقوهٔ تغییر نقش در API موجود است؛ آن توالی در این ممیزی اجرا نشد. |
| بالا: گیرندهٔ منتخب پس از خروج خانواده دسترسی دارد | [0003:176](../../backend/migrations/0003_planner_school_family.sql#L176) وجود `sharing_grant` را بدون بررسی عضویت جاری یا `visibility` معتبر می‌پذیرد. پس از پایان عضویت گیرنده در fixture، `can_view_plan_item` همچنان true شد. | تعریف/اجرای لغو اشتراک عضو منتخب با خروج از خانواده و آزمون آن؛ بررسی migration جدید روی دادهٔ قدیمی پیش از اجرا. |
| بالا: نوشتن Phase 6 در entrypoint خراب است | [entrypoint.js:36](../../backend/src/entrypoint.js#L36) Phase 6 را پیش از app دارای JSON/CORS در [server.js:17](../../backend/src/server.js#L17) mount می‌کند. PATCH Iran profile، PUT education و POST menstrual cycles با JSON معتبر هر سه 500 با `TypeError` دادند؛ `req.body` parse نشده است. | middleware مشترک پیش از تمام routerها؛ آزمون HTTP entrypoint واقعی شامل نوشتن/خواندن دوباره. |
| بالا: CORS Phase 6 از pipeline عبور نمی‌کند | با Origin مجاز تنظیم‌شده، GET profile اصلی 200 با ACAO صحیح بود؛ GET Iran profile/cycles پاسخ 200 بدون ACAO داد. OPTIONS education پاسخ 200 با متن خام `PUT` و بدون CORS داد. فهرست CORS فعلی PUT/DELETE را نیز ندارد. | بررسی GET/PATCH/PUT/POST/DELETE و OPTIONS از Origin مجاز/غیرمجاز در entrypoint واقعی. |
| نیازمند تصمیم سیاست و اصلاح: یادداشت تکلیف private از مسیر مدرسه می‌رسد | GET عمومی plan-items همان تکلیف private را از سرپرست پنهان کرد؛ GET school overview یادداشت مصنوعی خصوصی آن را برگرداند. [phase3.js:443](../../backend/src/phase3.js#L443) تمام ردیف‌ها را با `select *` بدون `can_view_plan_item` می‌خواند. | دقیقاً مشخص شود استثنای دسترسی تحصیلی چه فیلدهایی را شامل می‌شود؛ تا آن زمان نمی‌توان private بودن notes در همهٔ مسیرها را تضمین کرد. |

برای smoke عملیاتی، fixtureها با UUID تصادفی و نشست محلی ساخته شدند؛ `src/entrypoint.js` با `NODE_ENV=production` و پورت‌های loopback `55808`/`55809` در subprocess اجرا و سپس متوقف شد. فقط وضعیت‌ها، headerها و boolean حضور نشانگر مصنوعی ثبت شدند؛ هیچ token یا بدنهٔ حساس واقعی چاپ نشد. اولین اجرای smoke به علت تلاش harness برای JSON-parse متن OPTIONS متوقف شد؛ harness به پاسخ متنی نیز سازگار شد و اجرای بعدی کامل با exit 0 انجام شد. این خطای harness با خرابی‌های برنامه اشتباه گرفته نشده است.

## وضعیت ذخیره‌سازی و مدل دامنه

منبع پایدار بک‌اند، PostgreSQL پشت API اختصاصی LifeMate است، طبق [ADR-0006](../decisions/0006-provider-neutral-postgresql-backend.md). Pool از `DATABASE_URL` استفاده می‌کند. DB مالک اصلی داده‌هاست؛ فایل محلی یا mock جای این DB را نمی‌گیرد. اتصال به Supabase شرط پیاده‌سازی نیست و هیچ SDK/معماری Supabase در بک‌اند فعلی لازم نشده است.

| دامنه | پیاده‌سازی موجود | فاصله یا محدودیت |
|---|---|---|
| هویت و پروفایل | `app_user`، `profile`، Argon2id، tokenهای digestشده/زمان‌دار، session refresh/revoke | نبود lockfile، نقص disabled-account و log امن؛ موفقیت email واقعی بررسی نشد |
| خانواده | workspaceهای پویا، membership مستقل با role/admin، invitation و guardian relationship، audit | عدد ثابت اعضا/والدین ندارد؛ سیاست لغو/تغییر نقش در همهٔ مسیرها یکسان نیست |
| برنامه‌ریز | `plan_item` واقعی، CRUD ساخت/ویرایش و visibility، reminder، outbox، mutation ledger | API sync فقط update/complete/reschedule را می‌پذیرد؛ ساخت آفلاین از این مسیر پشتیبانی نمی‌شود، هرچند enum/schema واژهٔ create دارد |
| مدرسه | life context جدا از ریشهٔ Profile، سال/ترم/درس/کلاس و grade | student هویت دائمی شخص نیست؛ دسترسی notes خصوصی و لغو guardianship نیاز به اصلاح دارد |
| learning/wellbeing/AI | goal/check-in، owner-oriented wellbeing، session/message/proposal، ledger ایمنی جدا | پذیرش proposal فقط وضعیت proposal را عوض می‌کند؛ planner بی‌اجازه تغییر نمی‌کند. gateهای ایمنی/حقوقی هنوز بازند |
| بومی‌سازی ایران | `education_profile`، `curriculum_subject`، `textbook_catalog`، `iran_calendar_event` | catalog فعلی برای پایهٔ ۷ seed شده؛ grade mapping به تنهایی پوشش کامل کتاب تمام پایه‌ها را اثبات نمی‌کند؛ مسیرهای نوشتن عملیاتی Phase 6 خرابند |
| سلامت خصوصی | `menstrual_cycle_entry` جدا، GET/DELETE با owner predicate و بدون مسیر family | schema فعلی فیلد اختصاصی رضایت/opt-in ندارد؛ نوشتن عملیاتی خراب است؛ retention/export/deletion و رضایت تولید نیازمند کار جداست |
| اطلاع‌رسانی | جدول preferences، reminder و outbox واقعی | push provider و ارسال دستگاه واقعی تأیید نشده؛ preferences جدید Phase 6 به معنی اثبات اجرای تمام تنظیمات در worker نیست |

تست‌های HTTP اتصال واقعی به DB دارند و مسیرهای ابتدایی محصول mock نیستند. مسیر APK آزمایشی/کلاینت محلی موضوع بستهٔ موازی persistence است؛ این گزارش ماندگاری یا امنیت آن را تأیید نمی‌کند.

## وضعیت `profile_category`

در schema و API بک‌اند مبنای این ممیزی، `profile_category` وجود ندارد. این نام فقط در [طرح پروفایل شخصی](../superpowers/specs/2026-10-07-personalized-profile-guidance-design.md) و [برنامهٔ پیاده‌سازی](../superpowers/plans/2026-10-07-personalized-profile-foundation.md) دیده شد. query واقعی ستون‌های `profile` این موارد را داد: `user_id`، `display_name`، `birth_date`، `theme_preference`، `updated_at`، `household_persona`، `sex`.

پس دسته‌های `girl_minor | boy_minor | adult` فعلاً قرارداد طراحی هستند؛ ذخیره/GET/PATCH واقعی آن‌ها در بک‌اند اجرا نشده است. `household_persona` با مقادیر mother/father/child/adult، sex، theme و `member_role` چهار مفهوم جدا هستند و جای این دستهٔ صریح را نمی‌گیرند. راهنمای AI عمومی نیز در مسیر فعلی profile category/سن را از پروفایل نمی‌خواند؛ prompt عمدتاً guide kind و متن درخواست را می‌گیرد. نباید انتخاب دستهٔ محلی APK را به‌عنوان completion مهاجرت دامنه یا اجرای مجوز backend معرفی کرد.

## مرز حریم خصوصی و ادعای آمادگی

نقاط مثبت فعلی قابل مشاهده‌اند: API نوشتن برنامه owner را کنترل می‌کند؛ raw wellbeing note در فهرست wellbeing برنمی‌گردد؛ خلاصهٔ والد فقط check-inهای `guardian_summary` را aggregate می‌کند؛ AI session/message مالک را کنترل می‌کند؛ چرخهٔ سلامت مسیر family ندارد؛ high-risk متن به پاسخ ثابت و ledger جدا می‌رود؛ proposal بدون تصمیم صریح planner را تغییر نمی‌دهد. این موارد با وجود نقص مسیرهای دیگر، اثبات امنیت کامل نیستند.

RLS در هیچ‌یک از ۳۳ جدول عمومی این دیتابیس محلی فعال نبود. در معماری پذیرفته‌شده، API مرز اصلی مجوز و constraint/helper دفاع تکمیلی است؛ نبود RLS به تنهایی نقض ADR محسوب نمی‌شود، اما اتصال client با role مالک و دورزدن API باید ممنوع بماند. role و credential واقعی staging در این ممیزی بررسی نشده‌اند.

gateهای رضایت والد/قانونی، retention/export/deletion، taxonomy ایمنی، منابع اضطراری محلی، provider AI/voice، push و پذیرش دستگاه واقعی در `PROJECT_STATE.md` صریحاً deferred هستند. این gateها با نقص‌های اجرایی بازتولیدشده فرق دارند: نقص‌های بالا هم‌اکنون در کد موجودند و با پاس‌شدن آزمون‌های قبلی رفع نمی‌شوند. هیچ ادعای تازه‌ای دربارهٔ استقرار یا رفع آن‌ها در این ممیزی صورت نمی‌گیرد.

## بستهٔ بعدی پیشنهادی

۱. یکسان‌کردن parser/CORS/auth/error handler در entrypoint و routerها؛ red/green HTTP برای نوشتن Phase 6، JSON ناقص، disabled account و refresh.

۲. یکسان‌کردن سیاست membership/guardian/selected sharing، تعیین دقیق استثنای academic private notes و regression خروج/تغییر نقش/دعوت قدیمی. برای تغییر حساس سیاست یا migration محیط واقعی، مجوز مرتبط با همان اقدام لازم است.

۳. پیاده‌سازی مستقل قرارداد `profile_category` با جدایی theme/role و مسیر opt-in حساس؛ سپس اجرای کلاینت API-backed و migration روی محیط آزمایشی. بستهٔ محلی persistence پیش‌نیاز این کار نیست و جای آن را نمی‌گیرد.

۴. تثبیت وابستگی‌ها با lockfile و افزودن آزمون entrypoint عملیاتی به CI. نگه‌داشتن نتایج فعلی به‌عنوان baseline، همراه با بیان این مسدودکننده‌ها؛ release عمومی هنوز مجاز یا انجام‌شده نیست.
