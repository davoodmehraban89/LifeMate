# School lifecycle implementation plan

> Use the existing Node/PostgreSQL and Flutter offline infrastructure. Do not deploy or change live access.

- [ ] Write a failing real-entrypoint lifecycle test and record the 404 baseline.
- [ ] Add migration0019 with versions, term active state, account-scoped mutation ledger and legacy-path database guards.
- [ ] Add owner-only lifecycle router with bounded input/list, idempotency, CAS and archival.
- [ ] Run real PostgreSQL lifecycle tests and legacy subject/class regression checks.
- [ ] Write Flutter failing tests for explicit setup and durable exact-body retries.
- [ ] Add scoped lifecycle mutation helper and Persian RTL management screen; integrate only SchoolPage.
- [ ] Run focused Flutter tests/analyzer and report exact output to coordinating lead.
- [ ] Lead integrates router/role policy, runs aggregate/Compose/build/CI checks and updates delivery evidence.
