# LifeGuide QA — factoreasy.ir hosting comparison and GitHub Pages rollout

Date: 2026-10-15  
Status: **REPOSITORY PREPARED — GitHub Pages not enabled, DNS untouched, no app/API release**

## Confirmed FactorEasy deployment (directly read from the owner's connected Cloudflare account)

Cloudflare DNS zone: `factoreasy.ir` (zone ID `10694ab31c24fd2fc58f5e6f3000c011`, currently active). Cloudflare nameservers `tegan.ns.cloudflare.com` and `josh.ns.cloudflare.com`.

| Type | Name | Destination | Cloudflare proxy |
|---|---|---|---|
| A | `factoreasy.ir` | `185.199.108.153` | **false (DNS-only)** |
| A | `factoreasy.ir` | `185.199.109.153` | **false** |
| A | `factoreasy.ir` | `185.199.110.153` | **false** |
| A | `factoreasy.ir` | `185.199.111.153` | **false** |
| CNAME | `www.factoreasy.ir` | `davoodmehraban89.github.io` | **false** |

Those are GitHub Pages origins, not an Arvan/Railway/CDN-proxied origin. Other mail records and third-party domains were not relevant and are not copied into LifeGuide.

Independent live public DNS+HTTP checks from **six Iranian probe networks (Tehran×3, Shiraz×2, Qom×1)**, Germany and Turkey:
- `factoreasy.ir` resolved in all eight to four expected `185.199.10x.153` addresses. Evidence: https://check-host.net/check-report/5112766akbe9
- `https://factoreasy.ir/index.html` returned **HTTP 200** on all eight nodes (Iran 0.259–0.399s). Evidence: https://check-host.net/check-report/5112767akcfa
- `davoodmehraban89.github.io` resolved to the correct GitHub Pages addresses from the same Iran nodes; unaffiliated root `https://davoodmehraban89.github.io/` responded **HTTP 404**, confirming transport (not a hosted index at that hostname). Evidence: https://check-host.net/check-report/5112768ek45b
- `pages.dev`, including `lifeguide-qa.pages.dev`, was altered to `10.10.34.35/.36` in six Iranian networks: https://check-host.net/check-report/511223e9k3e8

**Conclusion:** The robust, source-backed approach for Iran-LTE static delivery is **GitHub Pages with our own custom hostname and DNS-only records**. This does not prove that every Iranian mobile network can reach the exact future `qa.lifeguide.ir`, nor does it create a backend by itself.

## Why NOT blindly copy FactorEasy's A records

- FactorEasy uses an apex domain (`factoreasy.ir`). LifeGuide uses a **subdomain** `qa.lifeguide.ir` / `app.lifeguide.ir`, so official GitHub guidance requires a **CNAME** from the subdomain to `davoodmehraban89.github.io`, **without a repo path**. https://docs.github.com/en/pages/configuring-a-custom-domain-for-your-github-pages-site/managing-a-custom-domain-for-your-github-pages-site
- `lifeguide.ir` authoritative nameservers remain at Arvan (`d.ns.arvancdn.ir` and `s.ns.arvancdn.ir`). We do NOT need to move the entire zone to Cloudflare to reproduce the essential origin path.
- `app.lifeguide.ir` currently resolves to Arvan proxy A records `185.143.233.132`, `185.143.234.132`, still routed to previous Railway origin and shown as 504 from owner's Iran LTE. Do NOT overwrite production `app` until alternative QA fully verified.
- Independent `qa.lifeguide.ir` A/CNAME checks returned DNS `NXDOMAIN` before preparation. No record has been created as of this report.

## Prepared GitHub automation — no production publication yet

- GitHub public repo `davoodmehraban89/LifeMate`: `has_pages=false` on inspection, so GitHub Pages itself still needs **Settings → Pages → Build and deployment → Source = GitHub Actions** from the owner; the current connector has no Pages enabling action.
- Isolated branch: `infra/lifeguide-github-pages-qa`, forked from `infra/lifeguide-cloudflare-qa`. No merge to `main`, no effect on FactorEasy.
- `scripts/build-github-pages-qa.sh`: reuse prior verified Flutter 3.47.6 self-contained build, output `apps/lifemate/build/web`, strip Cloudflare-only `_headers`, create `.nojekyll` and a public `site-check.txt` indicating **STATIC_ONLY** and safe commit provenance. Verify `/api` config has **no fallback** to Railway or any other unverified API.
- `.github/workflows/lifeguide-github-pages-qa.yml`: automatically builds branch (GitHub Actions) and attempts Pages publication only to `github-pages` environment. Until repo Pages is enabled, the deploy may fail by design. Build may pass independently; check latest Actions logs.
- GitHub Pages is static hosting. It does NOT run the Node/Express+Argon2 backend, Kavenegar OTP, Pages Functions or Supabase SQL. On GitHub Pages, `/api/*` should stay absent (**HTTP 404**, not successful user operations). **Do NOT** add a SPA 200 fallback for `/api/*`. A browser UI may render but sign-in/family sync still fails until server-side API is built.
- Don't put `DATABASE_URL`, DB admin role, `SUPABASE_SERVICE_ROLE_KEY`, JWT secret or Kavenegar API key into repository secrets used in a static front-end bundle.

## Safe manual owner handoff; PHASE ONE only

1. Open `https://github.com/davoodmehraban89/LifeMate/settings/pages`, under **Build and deployment** set **Source: GitHub Actions**. No new GitHub plan or payment card; GitHub Docs support public repositories on GitHub Free.
2. Check workflow `LifeGuide GitHub Pages QA (static only)` under Actions. If branch-triggered deploy previously failed due Pages disabled, trigger a new QA-only push after configuration or re-run it; do not enable production `main` auto-deployment.
3. In the same Pages settings, **before creating external DNS**, set **Custom domain = `qa.lifeguide.ir`** and Save; this may require GitHub's domain ownership/DNS verification and Let's Encrypt issuance. GitHub warns DNS-before-domain could create subdomain-takeover risk.
4. Once Github UI accepts the custom hostname, go to **Arvan's `lifeguide.ir` DNS only** and add a new `CNAME`: name **`qa`**, value **`davoodmehraban89.github.io`**, **Arvan CDN/proxy disabled (DNS-only)**. Confirm zero incremental charges/plan changes before saving. Use a short TTL. **Do not touch** the current `app`, root `lifeguide.ir`, nameservers, mail or other applications.
5. Wait for DNS and GitHub Pages certificate provisioning to complete; Enforce HTTPS if/when it becomes available. This can require hours.
6. Verify `https://qa.lifeguide.ir/site-check.txt` and root `https://qa.lifeguide.ir/` with LTE VPN OFF on owner's iPhone, and independent Iranian probe locations. Make sure static HTML and Flutter scripts/icons load without third-party blocked CDN.
7. Verify `https://qa.lifeguide.ir/api/health` **does NOT return HTTP 200 / index.html**. It must not claim backend readiness. Sign-in and registration are intentionally NOT operational.
8. If any problem, remove only the **new `qa`** DNS record and unset the new QA custom hostname. The existing `app.lifeguide.ir` remains as-is.

No application/DNS cutover, SMS approval/review, live accounts or data migration are authorized by this test preparation.

## Production gate (do not skip)

Only after an authenticated server-side Supabase API is deployed with strict guardian/child authorization, negative HTTP/JWT tests, OTP approval, real user consent, offline idempotence and actual no-VPN iPhone/Android acceptance may the owner authorize changing `app.lifeguide.ir` from old Arvan/Railway to the new validated destination. An existing single GitHub Pages site normally has **one custom domain**; moving from `qa` to `app` requires an orderly cutover, not claiming both hostnames automatically share the same site.

Citations: https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages and https://docs.github.com/en/pages/getting-started-with-github-pages/configuring-a-publishing-source-for-your-github-pages-site
