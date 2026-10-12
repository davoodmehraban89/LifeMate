# LifeGuide — authentication limits behind a shared family connection

The production middleware currently sends every `/v1/auth/` request into the
same IP bucket (10 requests per 600 seconds). Capability discovery, session
refresh and logout therefore consume the budget for login and recovery. Three
independent clients sharing a home/public IP can receive 429 while reopening.

Only literal `GET /v1/auth/capabilities` uses the existing bounded general
budget (120/60). Only literal `POST /v1/auth/refresh` and
`POST /v1/auth/logout` share a separate IP session budget (60/600), configured
through `RATE_LIMIT_SESSION_MAX` and `RATE_LIMIT_SESSION_WINDOW_SECONDS`.
Other authentication methods/paths retain the strict 10/600 budget, including
case variants and trailing/nested paths that Express may otherwise match.
Authentication/token validation, hashed refresh storage and rotation remain
unchanged. Public health and OPTIONS behavior and the pinned-proxy allowlist
remain unchanged. This does not implement a distributed limiter or per-account
quotas; multiple processes still have their existing independent IP buckets.

Acceptance uses one uninterrupted real production entrypoint, default limits,
synthetic PostgreSQL and three independent users on the same loopback IP. Twelve
capability GETs precede real login; at least twelve successful refreshes rotate
tokens and invalidate old proofs independently checked in PostgreSQL. Ten strict
requests are accepted by the limiter, and the eleventh is 429 with Retry-After.
Wrong methods/near paths and forged forwarding headers cannot escape that
bucket. Session request 61 is 429; both session paths share the limit. Capabilities
remain bounded by the real general bucket. No bucket reset, fake clock, live
server restart, global quota increase or disabled middleware is used.
