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
- `scripts/build-github-pages-qa.sh`: reuse Flutter 3.47.6 self-contained build, output `apps/lifemate/build/web`, strip Cloudflare-only `_headers`, create `.nojekyll` and public `site-check.txt` indicating **STATIC_ONLY**, commit provenance and selected base. **For the initial GitHub project Pages URL, explicitly build with `/LifeMate/` as Flutter base and point the unavailable API to `/LifeMate/api` (404).** For an owner-approved verified `qa.lifeguide.ir` custom domain, the workflow base must be changed to `/` and a new build tested. In either mode there is **no API fallback**, Railway origin or user sign-in backend.
- `.github/workflows/lifeguide-github-pages-qa.yml`: when on the QA branch, **checks `actions/configure-pages` before** the lengthy Flutter download/build, then uploads/publishes to `github-pages`. Until repo Pages is enabled, workflow should fail early by design. To test the new config, owner-approved integration of dependent draft PRs and a fresh QA branch push are required; check real Actions logs.
- GitHub Pages is static hosting. It does NOT run the Node/Express+Argon2 backend, Kavenegar OTP, Pages Functions or Supabase SQL. On GitHub Pages, `/api/*` should stay absent (**HTTP 404**, not successful user operations). **Do NOT** add a SPA 200 fallback for `/api/*`. A browser UI may render but sign-in/family sync still fails until server-side API is built.
- Don't put `DATABASE_URL`, DB admin role, `SUPABASE_SERVICE_ROLE_KEY`, JWT secret or Kavenegar API key into repository secrets used in a static front-end bundle.

## Safe manual owner handoff; PHASE ONE only

1. Open `https://github.com/davoodmehraban89/LifeMate/settings/pages`, under **Build and deployment** set **Source: GitHub Actions**. No new GitHub plan or payment card; GitHub Docs support public repositories on GitHub Free.
2. After reviewing and authorizing integration of the QA fix PRs, recheck `LifeGuide GitHub Pages QA (static only)` after a **new QA branch push**. The workflow is not on the default branch, so its `workflow_dispatch` button may not be offered until it exists there; a push to the QA branch is the supported trigger. Do not enable production `main` auto-deployment. Confirm the build artifact's `site-check.txt` declares `BASE=/LifeMate/`.
3. Initial smoke (no Arvan DNS edits): open `https://davoodmehraban89.github.io/LifeMate/site-check.txt` and `https://davoodmehraban89.github.io/LifeMate/` after a successful GitHub Pages deployment. The default `github.io` host may share an origin with other repositories; **use only synthetic/demo content, never actual child/family accounts or secrets on this hostname**. Check manifest, JS/CSS, CanvasKit, icons, PWA startup and that `/LifeMate/api/health` does not return a real API or app index. This is **static transport only**; no real user login or family data.
4. For a separate owner-approved custom-domain trial, **first** set **Custom domain = `qa.lifeguide.ir`** in Pages and Save. This may require GitHub ownership/DNS verification. Do NOT create DNS first; GitHub warns of subdomain takeover risk. Rebuild with `LIFEGUIDE_PAGES_BASE_HREF: /` **only after the custom hostname is accepted**, and verify root paths before saying Flutter is usable.
5. Once GitHub UI accepts the custom hostname and the owner gives separate explicit DNS approval, go to **Arvan's `lifeguide.ir` DNS only** and add a new `CNAME`: name **`qa`**, value **`davoodmehraban89.github.io`**, **Arvan CDN/proxy disabled (DNS-only)**. Confirm zero incremental charges/plan changes before saving. Use a short TTL. **Do not touch** the current `app`, root `lifeguide.ir`, nameservers, mail or other applications.
6. Wait for DNS and GitHub Pages certificate provisioning to complete; Enforce HTTPS if/when it becomes available. This can require hours.
7. Verify `https://qa.lifeguide.ir/site-check.txt` and root `https://qa.lifeguide.ir/` with LTE VPN OFF on owner's iPhone, and independent Iranian probe locations. Make sure static HTML and Flutter scripts/icons load without third-party blocked CDN.
8. Verify `https://qa.lifeguide.ir/api/health` **does NOT return HTTP 200 / index.html**. It must not claim backend readiness. Sign-in and registration are intentionally NOT operational.
9. If any problem, remove only the **new `qa`** DNS record and unset the new QA custom hostname. The existing `app.lifeguide.ir` remains as-is.

No application/DNS cutover, SMS approval/review, live accounts or data migration are authorized by this test preparation.

## Production gate (do not skip)

Only after an authenticated server-side Supabase API is deployed with strict guardian/child authorization, negative HTTP/JWT tests, OTP approval, real user consent, offline idempotence and actual no-VPN iPhone/Android acceptance may the owner authorize changing `app.lifeguide.ir` from old Arvan/Railway to the new validated destination. An existing single GitHub Pages site normally has **one custom domain**; moving from `qa` to `app` requires an orderly cutover, not claiming both hostnames automatically share the same site.

Citations: https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages and https://docs.github.com/en/pages/getting-started-with-github-pages/configuring-a-publishing-source-for-your-github-pages-site
