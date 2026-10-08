# LifeGuide — شواهد Stage 0

تاریخ: ۲۰۲۶-۱۰-۰۸ UTC. scope اجرا، Docker محلی Linux در محیط توسعه با **داده ساختگی** است. `.env` خصوصی، پروژه `lifeguide-stage0-audit`، HTTPS loopback `127.0.0.1:8443` و گواهی آزمون OpenSSL خارج Git استفاده شدند؛ mkcert/Windows مالک یا شبکه داخل ایران اجرا نشده‌اند. شاخه `feat/online-family-stage0`؛ SHA نهایی در گزارش تحویل ثبت می‌شود.

| اجرا | نتیجه مشاهده‌شده | حد اعتبار |
| --- | --- | --- |
| `docker version` / `docker compose version` | Engine 28.4.0، Compose 2.40.3 | فقط محیط Linux فعلی |
| `docker compose config --quiet` | exit0 | secrets چاپ نشد؛ startup نیست |
| `bash -n scripts/local-deploy.sh scripts/restore-drill.sh deployment/backup/*.sh` و Node `--check` smoke/seed | exit0 | syntax؛ اجرای Windows PS **UNVERIFIED** |
| build API/backup با npm lock و Node22 | موفق | اجرای اول npm شبکه fail شد؛ trusted build proxy/CA اضافه و TLS verification حفظ شد |
| migration نخست DB تازه، سپس تکرار و upgrade 0010 | 0001–0009 applied؛ تکرار بدون applied؛ 0010 بعداً applied | فقط DB ساختگی محلی؛ ledger idempotency مشاهده شد |
| `docker compose up -d --wait ... api backup` | PostgreSQL/API/backup healthy | این نتیجه UI/CRUD/Safari را تأیید نمی‌کند |
| startup backup + cron آزمایشی یک‌دقیقه‌ای | dump ساعت10:37:20 و dump scheduled10:38:00؛ archive list قابل خواندن | schedule خصوصی آزمون به default روزانه برگشت؛ restore جدا اجرا شد |
| `bash scripts/restore-drill.sh --synthetic-only` | **PASS** در15:23: حساب، policy خانواده/خصوصی، interval مطالعه و10migration | دو DB تازه، داده ساختگی؛ انتقال واقعی **UNVERIFIED** |
| `DOCKER_HOST=ssh://invalid.example bash scripts/local-deploy.sh` و restore-drill | هر دو با exit1 رد شدند، پیش از تماس remote | guard واقعی محلی؛ سرور زنده تغییر نکرد |

خروجی واقعی drill:

```text
DO
PASS synthetic PostgreSQL dump/restore: identity, family permissions, private task, paused study intervals and 10 migrations preserved.
```

خطاهای build اولیه پنهان نشده‌اند: image Flutter3.47.6 در registry Cirrus وجود نداشت؛ Dockerfile به commit رسمی Flutter pin شد. SHA-only checkout، SDK را `0.0.0-unknown` گزارش کرد؛ tag رسمی3.47.6 با همان SHA از GitHub fetch/verify شد. COPY فایل‌های checkout با permission600 به runtime غیرroot، خطای EACCES داد؛ COPY --chown=node:node اصلاح شد. اولین web compile هنگام توسعه هم‌زمان خطا داشت؛ از آن build هیچ gateway/APK معتبر گزارش نشده است.

HTTPS/PWA/API smoke نهایی بعد از ساخت نهایی gateway در همین گزارش افزوده می‌شود؛ تا قبل از آن **UNVERIFIED** است. TLS اعتماد گواهی، API round-trip و پذیرش مرورگر باید جدا گزارش شوند. اجرای حقیقی Safari/iPhone/Android، دسترسی بدون VPN از ایران، PowerShell مالک، APK release امضاشده، hosting/DNS/live deploy و migration داده واقعی **UNVERIFIED** هستند.
