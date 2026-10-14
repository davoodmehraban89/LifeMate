# ADR 0012 — Netlify Free as **candidate** for LifeGuide QA Node API (not deployed)

Date: 2026-10-15  
Status: **INVESTIGATE ONLY — NO HOST/ACCOUNT/DEPLOYMENT**

## Purpose

LifeGuide v0.7.1 is Node.js 22 / Express 5 / `argon2` native / `pg` / custom JWT-session family permissions. Supabase Free **LifeGuide-QA** currently hosts the already-migrated private PostgreSQL17 application model (20 original migrations; 59 private tables; deny-by-default RLS). Supabase managed Postgres **does not run the existing Express server** and its Edge Functions are not a verified replacement for Node native Argon2.

Owner cannot provide an international credit card, so no provider requiring a billing card, paid trial or out-of-band cost is suitable.

## Evidence from current provider documentation

- Netlify's updated Free plan: **$0/month with a HARD 300-credit monthly limit**, no auto recharge, which pauses the site if allowance is exhausted. https://docs.netlify.com/manage/accounts-and-billing/billing/billing-for-credit-based-plans/credit-based-pricing-plans/
- Netlify official free-plan announcement explicitly states **no credit card required**; still verify on the specific owner's account before taking any account action. https://www.netlify.com/blog/introducing-netlify-free-plan/
- Netlify's official Express guide describes `serverless-http` converting Express to Node Functions and redirects; support is documented, **not verified for this LifeGuide repo**. https://docs.netlify.com/build/frameworks/framework-setup-guides/express/
- Official function bundling docs allow `node_bundler = "esbuild"` and `external_node_modules` to include Node-native modules: https://docs.netlify.com/build/functions/configuration/

## Required implementation, **not yet done**

1. Confirm Netlify Free registration works for the owner **without card**, terms/accessibility from Iran without VPN, and no cost to deploy a private QA site. No Netlify connector is currently available via ChatGPT integration, and no account was assumed.
2. Create a new QA branch and deployment (not production `main`); bundle the **existing** Express Router with `serverless-http` and preserve request-context, errors, JWT/session checks and exact `/v1` route semantics; make any build/test commands compatible with Node22 and the native `argon2` build.
3. Fix or replace the existing **process-memory per-IP rate limiter** with a reliable shared server-side limiter before exposing authentication on stateless, autoscaled Functions. The existing DB per-phone cooldown helps OTP but is not adequate alone for password-login throttling. Need negative tests for multi-instance abuse, correct trusted-proxy behavior, sanitized logs.
4. Postgres connection strategy: use pooler/SSL and bounded connection pools; preserve app-level tenant/guardian permission functions. Private Supabase QA schema has **FORCED RLS, no policies and no client grants**. Design a dedicated least-privileged server role with scoped RLS policies before granting any access, and prohibit production app secrets in GitHub, PWA, Flutter or logs.
5. Configure **server-side-only** `DATABASE_URL`, `JWT_SECRET`, `KAVENEGAR_API_KEY` if explicitly approved later, plus CORS and origin; never put passwords/keys in a public browser bundle. Keep real SMS provider disabled until `lifeguideotp` is approved and owner approves one paid test.
6. Private synthetic child/parent E2E HTTP tests, including unauthorized 403, revocation, 4-second duration, session persistence and offline idempotency; full end-to-end QA on iPhone Safari/Android and from Iran without VPN.
7. Only after acceptance, separately discuss `https://app.lifeguide.ir` DNS/path migration. No automatic cutover.

## Decision

**Research candidate, not an adopted deployment architecture.** Netlify may solve the free Node hosting gap with less rework than replacing Express with Supabase Edge Auth, but suitability of Kavenegar networking, stable native Argon2 packaging, stateless rate limits, private Postgres role/RLS, quota and Iran access has not yet been verified. This document does NOT authorize account charges, live domain changes, actual SMS, production migration or new identity-provider substitution. Production hosting ADR0009 remains unchanged.
