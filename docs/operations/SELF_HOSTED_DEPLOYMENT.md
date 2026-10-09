# LifeGuide — بسته مستقل از میزبان

Compose مشترک از `docker-compose.yml` استفاده می‌کند: API با Node22 و Argon2 native، PostgreSQL16 داخلی، migration با ledger موجود، nginx TLS برای PWA/API/APK و cron backup با scripts موجود. API/migrator/backup اکنون نقش محدود و credential مستقل دارند؛ [DATABASE_ROLES.md](DATABASE_ROLES.md) ترتیب provisioning/grants و adoption صریح volume قدیمی را توضیح می‌دهد. `/api` از همان origin به API می‌رود. `deployment/runtime-config.json` در runtime mount می‌شود و `Cache-Control: no-store` دارد؛ API URL داخل Dockerfile نیست. فونت/CanvasKit باید از artifact محلی PWA ارائه شوند؛ check ساخت کلاینت این شرط را بررسی می‌کند.

Stage 0 محلی در [STAGE0.md](STAGE0.md) است. انتقال این بسته به سرور داخلی انتخاب‌شده، ثبت حساب، هزینه، DNS، deploy زنده و تغییر سرور **فقط پس از تصمیم و مجوز صریح مالک** است. در این کار اجرا نشده‌اند و **UNVERIFIED** هستند. Railway و معماری managed خارجی مسیر فعال این بسته نیستند.

## آماده‌سازی سرور، دستور دستی پس از مجوز

شبکه داخلی `proxy` فقط API و gateway را وصل می‌کند. alias `api-proxy` فقط در همین شبکه است و gateway IP ثابت `GATEWAY_PROXY_IP` دارد. API فقط همین IP با `/32` را برای forwarded address قابل اعتماد می‌داند؛ nginx `X-Forwarded-For` ورودی را با peer واقعی جایگزین می‌کند. PostgreSQL روی شبکه دیگری است و هیچ host port برای API/DB منتشر نمی‌شود. برای جلوگیری از تداخل با LAN/VPN/Docker دیگر، `PROXY_SUBNET` و `GATEWAY_PROXY_IP` را **با هم** در `.env` انتخاب کنید؛ IP gateway باید داخل همان subnet باشد. CIDR وسیع عمومی یا trust-all مجاز نیست. تنظیم proxy خارج Compose به‌صورت پیش‌فرض اعتماد ندارد.

1. مالک سرور، origin/IP، پرداخت قابل انجام، دسترسی بدون VPN از ایران و مسیر تمدید TLS را تأیید کند. قبل از استقرار، از حداقل دو اپراتور داخل ایران تست شبکه انجام شود.
2. Docker/Compose را نصب و snapshot/backup قابل بازیابی تهیه کنید. همان کد و imageهای versioned بررسی‌شده را به میزبان منتقل کنید؛ build در سرور الزام نیست. imageها را می‌توان با `docker save/load` آفلاین انتقال داد.
3. `.env.example` را به `.env` کپی و secretها را در محیط/secret management میزبان تولید کنید. نام schemaها، JWT issuer=`lifemate` و audience=`lifemate-api` تغییر نمی‌کند. روی انتقال دیتابیس، secret JWT را مطابق سیاست نشست حفظ یا با اطلاع کاربر rotate کنید؛ عوض کردن آن کاربران را خارج می‌کند.
4. گواهی معتبر برای همان origin را **مالک/اپراتور** تهیه و مسیرهای `TLS_CERT_PATH`/`TLS_KEY_PATH` را تنظیم کند. Compose به‌صورت خودکار Let's Encrypt، DNS یا سرویس خارجی را تغییر نمی‌دهد. برای عمومی کردن سرویس، mkcert مناسب کاربران عمومی نیست. تمدید گواهی باید توسط اپراتور زمان‌بندی و بعد از آن `docker compose exec gateway nginx -s reload` اجرا شود.
5. فقط پورت HTTPS لازم را در فایروال مجاز کنید. PostgreSQL/API port مستقیم منتشر نشود. `PUBLIC_APP_URL`/`CORS_ORIGINS` و runtime config باید به همان مبدأ اشاره کنند؛ redirect/CDN خارجی اضافه نشود.
6. بعد از backup و مجوز migrations، Compose را build/load کنید، DB را بالا بیاورید و به‌ترتیب `docker compose run --rm --no-deps db-provision`، `migrate` و `db-grants` را اجرا کنید؛ سپس API/gateway/backup با `--wait` شروع شوند. volume قدیمی قبل از این ترتیب به adoption صریح معتبر نیاز دارد؛ دستور عادی آن را تغییر نمی‌دهد. این دستورات برای اپراتور هستند؛ تیم این نوبت آن‌ها را روی میزبان زنده اجرا نکرده است.
7. smoke test با TLS معتبر و credential ساختگی و پذیرش Android/Safari/مجوزها را ثبت کنید. provider ایمیل/SMS تا انتخاب و پیکربندی مالک غیرفعال است؛ ثبت حساب pending، تحویل واقعی پیام نیست.

## rollback

imageها را پیش از rollout با tag یکتا و SHA ثبت کنید، مثل `API_IMAGE=lifeguide-api:<commit>` و `WEB_IMAGE=lifeguide-web:<commit>`. کپی خصوصی `.env`، نسخه config، fingerprint گواهی و آخرین backup معتبر را نگه دارید.

اگر schema با نسخه قبل سازگار است: نوشتن را متوقف، image tagهای قبلی را در `.env` برگردانید و **بدون build و بدون اجرای migration جدید** `docker compose up -d --no-build --no-deps api gateway` را اجرا کنید. سپس health، ورود و CRUD ساختگی را بررسی کنید. داده volume حفظ می‌شود. downgrade schema و restore داده واقعی نیاز به مجوز جدا دارند؛ روی schema ناسازگار فقط عوض کردن image معتبر نیست. قبل از restore، از وضع فعلی backup بگیرید. مراحل انتقال/بازگشت در [DOMESTIC_MIGRATION.md](DOMESTIC_MIGRATION.md) است.

## backup و health

`/live` حیات API، `/ready` ارتباط DB و `/health` probe سازگار قبلی است. gateway health داخلی روی 8081 است و publish نمی‌شود. cron backup از `backend/scripts/backup.sh` استفاده می‌کند؛ custom-format/no-owner/no-privileges. `pg_restore --list` فقط خوانایی archive را می‌سنجد، جای restore drill نیست. اجرای `bash scripts/restore-drill.sh --synthetic-only` دو DB تازه ایجاد می‌کند و هیچ DB موجود را restore/drop نمی‌کند. dumpها و TLS keys خارج Git و chat می‌مانند.

backup cron داخل container با UTC اجرا می‌شود، retention پیش‌فرض ۱۴ روز است. export/رمزگذاری/off-PC backup و restore زمان‌بندی‌شده بر عهده اپراتور است. container cron خاموش، PC خوابیده یا دیسک پر، backup جدید نمی‌سازد؛ status آن باید پایش شود. تغییر password در `.env` خودکار password role داخل PostgreSQL volume قدیمی را عوض نمی‌کند؛ برای rotation، runbook و مجوز عملیات DB لازم است.
