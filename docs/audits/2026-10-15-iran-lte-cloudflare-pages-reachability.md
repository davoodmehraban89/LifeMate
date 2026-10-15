# LifeGuide — Iran LTE cannot open Cloudflare Pages QA

**Date:** 2026-10-15
**Severity:** RELEASE BLOCKER for all Iran no-VPN clients; remains unresolved.
**Owner evidence:** User independently opened `https://lifeguide-qa.pages.dev/` with an Iranian mobile carrier and **VPN off** and reported the page **does not open**. No screenshot or browser error code was supplied, so failure phase (DNS resolution / TCP timeout / TLS / Safari blank screen / Flutter bootstrap stall) **is not established**.

## Confirmed service-side findings

- Connected Cloudflare account `ace6f7219be1e7d9ac5bacd59c05fbe2`, Pages project `lifeguide-qa`, production branch `infra/lifeguide-cloudflare-qa` is **successfully deployed**; latest observed deployment `a84ef939-0c20-47f0-90d6-e1989c9bf8ac` SHA `deaaa4caf7696243bc4b1203004a32db5fe2a4d7` was `success`.
- `/health` responds JSON `status=ok,component=pwa_gateway_only,backend=not_connected` to independent requests outside Iranian networks. The HTML `/`, `/config.json` and `/main.dart.js` were fetched successfully from a non-Iranian network. This **does not** establish Iran reachability or full Flutter runtime render.
- Cloudflare account has **no `lifeguide.ir` zone**, Pages project has **no custom domain**; provider returned `access.api.error.not_enabled`, so Cloudflare Zero Trust Access is **not** configured for the account.
- GitHub latest CI run `38681124039` succeeded in all jobs; tests run on GitHub, **not an Iranian carrier**.
- Supabase `LifeGuide-QA` private schema and 20 SQL migrations remain independent. No real REST family API or SMS service activated. Kavenegar `lifeguideotp` template has been rejected after its registered `app.lifeguide.ir` failed provider review with a 504.
- Cloudflare official troubleshooting: ISP-level blocking of assigned Cloudflare shared IPs is possible and Cloudflare **cannot** rotate/dedicate those IPs on Free/Pro/Business. Source: https://developers.cloudflare.com/support/troubleshooting/general-troubleshooting/potential-isp-blocking/
- Existing app hostname `app.lifeguide.ir` still goes through Arvan and the old Railway path (broken on user's mobile network). **No DNS or production change performed**.

## Diagnostic matrix — ask owner to test on the exact same LTE, VPN off

| URL | Meaning of a successful response | If unreachable |
| --- | --- | --- |
| `https://lifeguide-qa.pages.dev/health` | Tiny Cloudflare Pages Function; proves host/DNS/TLS/edge HTTP for this network, no Flutter JS required | Diagnose network/host/DNS/TLS/block; do not blame Flutter |
| `https://lifeguide-qa.pages.dev/` | HTML + app bootstrap | If health works but app is blank or loading, check JS/CanvasKit/bootstrap/Safari runtime |
| `https://lifemate-staging.pages.dev/` | Independent **existing** Pages project on same shared root domain (older static app, not QA API) | If both pages.dev hosts fail but external websites work, strong indicator of domain/IP or provider-specific filtering; still not conclusive without DNS/TLS traces |
| `https://iqkrwxeprxvdiubdfcrb.supabase.co/functions/v1/lifeguide-qa-health` | Expected **401 Unauthorized** means encrypted request reached Supabase JWT gate; **do not** send a token | If connection fails, Supabase edge also needs an Iran-reachability strategy; never expose service keys |

**Ask for exact Safari error text/screenshot** and mobile operator. No phone, IP, personal credentials or screenshots of secrets required; do not store private IP/OTP in project records. Test alternative Iranian Wi-Fi if available to isolate operator specificity.

## Decision rules

1. If `/health` cannot load on Iran LTE: **block Cloudflare direct custom-domain cutover**, even if QA HTTP and global build green. A pure CNAME with the user's own .ir name may help name/SNI-based filtering but cannot fix blocked Cloudflare destination IP; requires a tested Iran-side network proof.
2. If `/health` is reachable but `/` stalls: inspect Flutter bundle resources, CanvasKit, and Safari JS launch, not DNS alone.
3. If Supabase JWT-only health function also unreachable: Cloudflare/Supabase external-only hosting is not a viable sole path for Iran; evaluate an **Iran-reachable edge/front** (for example an existing authorized Arvan CDN configuration) and test origin HTTPS/Host headers, backend security, provider terms and quota in an isolated subdomain. CDN-to-CDN chaining and native Cloudflare Pages validation are not guaranteed to work. **No untested proxy/domain change**.
4. The user's **no-card / zero-hosting-fee** constraint remains in force. Never promise perpetual free/reliable external delivery; published pages can still be filtered.
5. No production DNS change or submission of Kavenegar provider re-review while the reviewable website is unreachable. No real SMS attempted.

**Current state:** DEPLOYED BUT UNREACHABLE IN OWNER'S IRAN-LTE TEST, NOT ACCEPTED. No definitive attribution to ISP blocking, DNS/SNI or page JS until diagnostic data arrives.
