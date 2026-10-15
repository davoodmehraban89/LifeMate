# LifeGuide — Kavenegar VerifyLookup SMS OTP configuration (QA only)

Status: **ADAPTER SOURCE PREPARED, LIVE SMS DISABLED / UNVERIFIED**  
Prepared: 2026-10-15  
Source branch: `infra/lifeguide-supabase-qa`  
Provider confirmed by owner screenshots: Kavenegar `console.kavenegar.com`. Owner's masked API key is visible only in their own authenticated console; it was **not retrieved or stored**.

## Exact pattern to create in Kavenegar console

Path: اعتبارسنجی → ایجاد الگوی جدید

| Kavenegar field | QA / LifeGuide value |
| --- | --- |
| نوع استفاده | موبایل اپلیکیشن |
| نام الگو (template) | `lifeguideotp` |
| نوع ارسال | پیامک |
| ارسال مجدد با مسیر جایگزین | غیرفعال |
| متن الگو | See below |

```text
کد تأیید LifeGuide: %token

اعتبار کد: ۵ دقیقه
این کد را در اختیار دیگران قرار ندهید.
```

- Keep the literal **`%token`** intact. Its value is generated server-side as a six-digit number (may have a leading zero).
- Name of system **LifeGuide** is included. Provider must approve the SMS template before sending is enabled.
- Do **not** paste the API key, reveal the key with the eye icon, copy the key into chat, screenshots, Flutter, PWA or public GitHub.
- Account balance in owner screenshot is 50,000 rials; that is a **finite prepaid balance**, not free SMS. No actual SMS should be sent during preparations without owner approval for charged sends.

Official API documentation:
- https://github.com/kavenegar/kavenegar-node — `VerifyLookup({ receptor, token, template })`
- https://www.postman.com/kavenegarrestapi/kavenegar-s-public-workspace/documentation/v5ppwag/kavenegar-rest-api — endpoint `GET /v1/<API-KEY>/verify/lookup.json` with `receptor`, `token`, `template`, optional `type=sms`.

## Actual code preparation

- Dedicated backend module: `backend/src/kavenegar_sms.js`, selected only with explicit `SMS_PROVIDER=kavenegar`.
- `backend/src/auth_delivery.js` retains the original disabled/default and HTTPS webhook behavior; it is **not** switched on by default.
- Example environment keys:
  - `SMS_PROVIDER=kavenegar`
  - `SMS_LIVE_ENABLED=true` only after explicit owner authorization for live sending.
  - `KAVENEGAR_TEMPLATE_APPROVED=true` only after the provider approves this exact template.
  - `KAVENEGAR_TEMPLATE=lifeguideotp`
  - `KAVENEGAR_API_KEY=<secret value in server/secret manager ONLY>`
- Adapter restricts to Iranian mobile numbers normalized by existing LifeGuide `normalizePhone()` as `+989XXXXXXXXX`; Kavenegar receives `09XXXXXXXXX`.
- Fixed official HTTPS API host, redirect disabled, 10s maximum timeout, sanitized provider errors, no provider response/error body in logs, no automatic retries (Kavenegar `VerifyLookup` has **no idempotency key**, so retry could produce duplicate and charge again).
- A provider return status 200 is **acceptance only**, never proof of handset delivery. Failure response 200 with `return.status != 200` is treated as failed.
- LifeGuide's current original auth flow supplies 6-digit OTP, 5-minute expiry, recipient request limits, maximum failed attempts, and independent session checks. This adapter is **delivery only** and must never issue sessions or bypass guardian authorization.

## Gates remaining

1. Owner completes/obtains approval for `lifeguideotp` pattern. Only ask for the pattern **name and approval status**, no secret.
2. CI must confirm synthetic mocked transport tests, syntax/security and all Backend regression tests on the isolated branch. No live provider API or real phone send is exercised by mocked tests.
3. Prepare an **approved secure backend runtime** (existing Node/Express currently has no online host) and separate Supabase QA application schema/auth authorization parity. The Supabase `LifeGuide-QA` database plus `lifeguide-qa-health` probe are **not** a functioning family API.
4. Put Kavenegar key in a **private secret manager** for that runtime only, after owner approves credential placement. Never read key back to chat or logs.
5. Obtain separate owner approval for **one real paid SMS** to an owner-controlled test phone. Check approval of pattern, actual reception, repeat/expired code behavior and sanitized provider response; record no phone/OTP in report.
6. Only after that and successful API integration separately discuss switching public `app.lifeguide.ir`/Android/PWA or releasing production.
7. Confirm provider reachability and permitted access from the final hosting environment; do not assume foreign server can reach Kavenegar API.

This preparation changes neither Supabase QA secret configuration nor the live `app.lifeguide.ir` deployment. The original SQL application tables, Android/Safari tests and real SMS remain **UNVERIFIED**.
