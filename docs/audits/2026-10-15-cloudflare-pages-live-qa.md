# LifeGuide: Cloudflare Pages independent QA deployment verification

Date: 2026-10-15  
Mode: actual deployed **static PWA staging** (NOT a complete functional backend or production release)

## Provider inventory and source

- Product **LifeGuide**; GitHub repository `davoodmehraban89/LifeMate`.
- Supabase Free `DM Studio` → `LifeGuide-QA`, project `iqkrwxeprxvdiubdfcrb`, PG17.11, 20 app migrations in private `lifeguide_qa` schema, default-deny RLS. Existing `Finora ERP – Production` untouched.
- Cloudflare Pages account `ace6f7219be1e7d9ac5bacd59c05fbe2`.
- **Existing/unchanged** Pages `lifemate-staging.pages.dev` from `deployment-static` (last success 2026-10-06).
- **New** Pages `lifeguide-qa.pages.dev`, GitHub source branch `infra/lifeguide-cloudflare-qa`, build script `bash scripts/build-cloudflare-pages-qa.sh`, published folder `apps/lifemate/build/web`.
- At checkpoint, Pages production deployment `1a64a095-c1da-40b5-98ec-3d662d379e92`, SHA `3291d0cddaa92c4d88f0e8b945beb79956cf7f4f`, **status success**. Previous deployment `9bfb30df-8ad0-4f4e-ade2-9ec77350543b` also success. Build logs showed pinned Flutter release build, Pages Functions compiled, **51 static assets** uploaded (first deployment), asset publish success.

## Actual public network checks using independent HTTP fetch

QA hostname: **https://lifeguide-qa.pages.dev/**

| URL | Result | Interpretation |
| --- | --- | --- |
| `/` | HTML retrieved; title **LifeGuide / لایف‌گاید**, `lang=fa` and startup text | Static index is served; not proof Flutter full render in Safari |
| `/config.json` | JSON `{"apiBaseUrl":"/api","apiFallbackUrls":[]}` | No silent fallback to Railway or third-party services |
| `/health` | HTTP 200 JSON `{"status":"ok","component":"pwa_gateway_only","product":"LifeGuide","backend":"not_connected"}` | Frontend gateway only |
| `/ready` | HTTP 503 | Correctly refuses to claim ready backend |
| `/api/health` | HTTP 503 | Correctly refuses HTML fallback; **real REST API not deployed** |

No claim that Flutter's interactive auth, Android APK, cross-device task sync, Kavenegar API send or database login function works at this URL; none has been validated or enabled.

## Domain / provider incident

Owner's LTE screenshot shows **Arvan-proxied `https://app.lifeguide.ir/` HTTP 504 Gateway Timeout** (2026-10-15 04:01 UTC). Authoritative DNS is at Arvan; unrelated, existing Railway origin (no longer active deployment target) uses older `main` build. No Railway deployment or DNS change was performed here. Kavenegar rejected the `lifeguideotp` template because **the registered app URL was not inspectable**; support ticket instructs requesting another review after full access restored.

Cloudflare Pages official docs allow **externally hosted DNS for a subdomain**. Full switch of the apex nameservers is *not* required. **Do not change CNAME yet**: first stage full family API and verify the mobile PWA + Iran LTE, then associate `app.lifeguide.ir` as a Cloudflare Pages custom domain, and obtain explicit owner approval before editing Arvan's `app` record. Confirm any existing Arvan CDN/proxy/TLS rule does not continue routing to Railway.

## Verification limits and next tasks

- GitHub Actions run `38680750623` at latest check: **Backend success, Security success, Flutter in progress**. Wait for full CI before marking final pipeline green.
- No DNS / real accounts / payment / registered family data / API keys / live SMS were changed.
- QA Supabase DB is ready at **database layer only**. Need a reviewed authenticated server adapter preserving the v0.7.1 JWT and guardian/family authorization semantics. Supabase Edge should only host server-side code; never put `service_role`, Postgres password, Kavenegar key or privileged bearer in frontend or Git.
- Until full authenticated API, keep Cloudflare `/api/*` **fail closed (503 JSON)** and `/ready` 503. Passing the health endpoint alone must not be presented as ready.
- Need real-user acceptance on iPhone Safari and Android **inside Iran without VPN**; remote HTTP tests cannot reproduce their conditions. Kavenegar pattern remains rejected; no paid SMS testing authorized.
- Production DNS, real data migration, signing/releasing APK, and changes to Finora are outside scope.

References: [ADR 0013](../decisions/0013-cloudflare-supabase-kavenegar-stack.md), [Supabase schema proof](2026-10-15-supabase-full-schema-family-acceptance.md), [Kavenegar instructions](../operations/KAVENEGAR_SMS_SETUP.md), GitHub Draft PR15.
