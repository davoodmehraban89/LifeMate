# آرام / Life Guide — وضعیت واقعی در ۲۰۲۶-۱۰-۰۸

بازیابی از `test/role-entry-apk@796d6bec16841020323bf67275f60c38048a0374` و توسعه در `fix/local-task-persistence` با worktree مستقل انجام شد. مخزن تاریخی Aram با LifeMate یکسان فرض نشده است.

**محصول کامل یا آماده استفاده عملیاتی نیست.** ادعاهای COMPLETE/READY در گزارش تاریخی پایین، با ممیزی فعلی تأیید نمی‌شوند. APK قبلی فقط سه آزمون ورود/پروفایل داشت و عملیات رکورد در LocalRoleTestApi نمایشی بود.

## بسته فعلی ماندگاری محلی

- حالت بدون Login به `LocalOnlyApi` و سند نسخه‌دار `lifeguide.local_data.v1` در SharedPreferencesAsync (DataStore در Android) منتقل می‌شود: شناسه یکتا، نوشتن سریالی، اعتبارسنجی، خطای آشکار و توقف نشست در خطای native نامطمئن تا force-stop، ویرایش و بایگانی `cancelled`.
- پروفایل قدیمی غیرمخرب خوانده می‌شود؛ نام/تم/شناسه پروفایل پایدار و نوع پروفایل مستقل از نقش خانواده است. چند پروفایل و تعویض دسته هنوز رابط ندارند.
- داده فقط روی دستگاه است؛ Sync و backup سرور، رمزنگاری اختصاصی، احراز هویت یا حفظ داده بعد از uninstall ندارد. ظرفیت سند آزمایشی ۱ MiB است؛ فراتر از آن خطا می‌دهد.
- خانواده، مدرسه ساختاریافته، check-in، سلامت، AI و اعلان واقعی در حالت محلی قابل ثبت ساختگی نیستند. برنامه دارای Login همچنان HttpIdentityApi و PostgreSQL دارد و با این بسته عملیاتیِ کامل اعلام نمی‌شود.
- بایگانی رکورد را حفظ و از فهرست فعال پنهان می‌کند؛ رابط مشاهده/بازگردانی آرشیو هنوز موجود نیست.
- unit/widget از پلاگین حافظه‌ای استفاده می‌کنند؛ آزمون Android با پلاگین واقعی و چهار اجرای فرایند جدا، شاهد مستقلی است. نتیجه اجرا و Artifact در گزارش تحویل ثبت می‌شود.

## خط مبنا و مسدودکننده‌ها

- Flutter 3.47.6 / Dart 3.13.5 بازیابی شدند. هشت آزمون قبلی: هفت پاس و یک شکست متن حداقل رمز؛ analyze یک import بی‌استفاده داشت. دو RED ناپدیدشدن تکلیف و برگشت نام را بازتولید کردند.
- PostgreSQL مستقل: شش migration، چهار فایل SQL، ۱۳/۱۳ Node، syntax و backup/restore محلی پاس شدند؛ آزمون‌های محدود، امنیت کامل را اثبات نمی‌کنند.
- چند نقص واقعی لاگ حساس، لغو حساب/سرپرست/اشتراک و نوشتن/CORS Phase 6 بازتولید شده و در بسته محلی اصلاح نشده‌اند.
- profile_category در schema/API Production هنوز وجود ندارد؛ سلامت opt-in، AI واقعی، push و Offline/Sync دارای Login ناقص‌اند. کش نسخه دارای Login کاربرمحور نیست.
- مهاجرت Cloudflare/Neon تأییدشده نیست؛ سرویس زنده، DNS، مجوزها یا استقرار تغییر نکردند.

گزارش‌ها: [عملکرد و داده](docs/audits/2026-10-08-functional-persistence.md)، [Backend و حریم خصوصی](docs/audits/2026-10-08-backend-audit.md)، [مخزن و زیرساخت](docs/audits/2026-10-08-recovery-infrastructure.md)، [برنامه اجرا](docs/superpowers/plans/2026-10-08-local-persistence-repair.md)، [تحویل](docs/audits/2026-10-08-delivery.md).

ترتیب بعدی: اصلاح نقص‌های واقعی Backend با آزمون entrypoint، سپس profile_category و پروفایل API، خانواده/مجوز و Offline/Sync؛ سلامت و AI بعد از هسته داده. Merge و انتشار عمومی در این بسته انجام نمی‌شوند.

---

## آرشیو گزارش تاریخی ۲۰۲۶-۱۰-۰۵ — تأیید فعلی محسوب نمی‌شود

**Last updated:** 2026-10-05
**Phase:** Phase 5 — Hardening, Observability & Release — COMPLETE
**Repository:** `davoodmehraban89/LifeMate`
**Working product name:** LifeMate — approved

## Transfer checkpoint
Phases 1–5 engineering core are complete. LifeMate now has the foundation/identity, planner-school-family core, advisory learning/wellbeing guides, and the operational hardening/release-readiness layer required for a controlled beta. Public production release and minor-sensitive external AI/voice exposure remain intentionally gated and require separate explicit approval.

## Five-phase roadmap
1. **Foundation, Product Contract & UX Direction** — COMPLETE
2. **Product Foundation & Identity** — COMPLETE
3. **Planner, School & Family Core** — COMPLETE
4. **AI Guides, Learning & Wellbeing** — COMPLETE
5. **Hardening, Observability & Release** — COMPLETE

## Accepted architecture baseline
- Flutter Android + responsive Web/PWA; future packaged/native iOS path preserved.
- Provider-neutral Node API + PostgreSQL; Railway remains staging host.
- LifeMate-owned identity/session adapter; server-side relationship-aware authorization.
- Offline client support does not replace server authority.
- AI guides are advisory and plan proposals require explicit acceptance.
- Wellbeing/AI transcripts remain owner-private; family membership does not grant transcript access.

## Phase 4 completed vertical slice
Learning goal → learning check-in → wellbeing check-in → AI guide session → safety classification → advisory response → explicit plan proposal → accept/reject decision. No guide response silently mutates planner state.

### Verified Phase 4 gates
- Migration `0004_ai_learning_wellbeing.sql` defines seven Phase 4 tables, including the separate `wellbeing_safety_event` ledger, and owner-oriented indexes.
- Phase 4 API implements learning goals/check-ins, private/guardian-summary wellbeing check-ins, AI sessions/messages, explicit proposal decisions, guardian wellbeing summaries and privacy-preserving family guidance.
- High-risk self-harm language follows a fixed urgent-support path and writes a separate safety signal; ordinary family membership never grants raw wellbeing notes or AI transcripts.
- Study/planner/wellbeing guidance is advisory, non-diagnostic and never silently mutates planner data.
- Flutter includes interactive guide chat, learning goals/check-ins, wellbeing check-ins, guardian summary and parent family-guidance flows.
- ADR `docs/decisions/0004-ai-learning-wellbeing-safety.md` records privacy, provider, voice and production safety gates.

## Phase 5 completed scope
- Production-entrypoint request correlation, security headers, privacy-safe structured request/error telemetry and bounded request bodies.
- Configurable general/auth/AI fixed-window rate limits with HTTP 429 and `Retry-After`.
- Separate `/live` and database-backed `/ready` operational probes while retaining `/health` compatibility.
- PostgreSQL-native backup/restore scripts plus an automated CI data round-trip restore drill.
- Release regression gates for backend tests/syntax/audit/schema, secret scanning, Flutter format/analyze/tests, Web release build, Android build and PWA install/RTL metadata.
- Deployment, rollback, backup/restore, incident-response and production-readiness runbooks plus changelog/version discipline.
- Railway staging API function hardened with request IDs, security headers, rate limiting, `/live`, `/ready` and privacy-safe error handling; staging tracing and auto-instrumentation enabled.

### Verified Phase 5 gates
- Red-first operations contract was observed failing before the hardening implementation; subsequent backend contract/integration tests passed.
- GitHub Actions run 165 at branch commit `125c44f55827dc5ed26d81fe821969348db4598e` completed successfully: security, backend and Flutter jobs all green.
- Backend run 165 passed migrations, authorization tests, dependency audit, 11 Node tests, syntax checks, 28-table schema verification and the backup/restore data round-trip drill.
- Flutter run 165 passed formatting, analysis, widget/tests, PWA release metadata checks, Web release build and Android debug build.
- Railway staging deployment `0cd21bed-5cba-494b-afef-7f45312f2fdf` is SUCCESS/online with no reported warnings or critical issues after Phase 5 hardening.
- Railway staging source inspection confirms the operational middleware and `/live` + `/ready` routes are deployed; external AI/voice remain unenabled and Phase 4 AI continues in local-fallback mode.

## Production-gate items intentionally deferred
Jurisdiction-specific legal/guardian consent review; final safety severity taxonomy; emergency resource localization; external AI provider privacy/retention review; wellbeing retention/export/deletion policy; voice-provider privacy review; production push-provider configuration; final device beta acceptance. These are release gates, not missing Phase 5 engineering-core work.

## Release status
Engineering phases 1–5: COMPLETE.
Controlled family beta: READY FOR OWNER-APPROVED DEVICE TESTING.
Public production deployment/release: NOT PERFORMED.

## Guardrail
AI/wellbeing production exposure stays disabled until dedicated safety/legal/provider gates pass. Production deploys, destructive migrations, public release and sensitive access changes require explicit action-specific approval.
