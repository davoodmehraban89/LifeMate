# LifeGuide school lifecycle editor

Status: authorized local implementation; live migration and hardware acceptance are UNVERIFIED.

School remains an owner-private life context, independent of family permission and profile category. Existing subject/class APIs and linked homework/history are preserved. An explicit Persian RTL editor replaces quick setup that assumed September–June and created mathematics automatically.

## API and persistence

GET `/v1/school/lifecycle` returns `{contexts, years, terms, fetchedAt}` including inactive history, bounded to 500 rows per entity. Parent and guardian grants never permit lifecycle writes or private lifecycle reads. Dates are ISO Gregorian calendar dates; the interface identifies the calendar explicitly, accepts Persian digits and offers a date picker. The user chooses titles, context and date boundaries.

POST `/v1/school/lifecycle/{contexts|years|terms}/mutations` accepts `{mutationId, entityId, operation, expectedVersion, data}`. Create uses a client UUID and expected version zero; update/archive use the actual server version. The account-scoped hash ledger prevents duplicate inserts after a lost acknowledgement or restart. Changed reuse of a mutation UUID fails; stale expected versions fail with 409. Exact retries return current entity state and the original applied version/acceptance time, rather than resurrecting an old snapshot. Archived entities cannot be restored by this API.

The owner row serializes mutations. PostgreSQL triggers enforce ownership, active ancestors, student context for academic years, nested dates, class recurrence boundaries and parent-date edits on existing history even through legacy insert/update paths. Parent archival preserves every child row and linked task; descendant writes stop while its ancestor is inactive. No delete cascade is used by lifecycle operations.

## Client operation

Lifecycle mutation intent is persisted before network transmission using the existing account+endpoint store and stable UUID. Pending mutations are retried manually with exactly the same body. A pending create must be acknowledged before a child is attached; setup is deliberately explicit rather than an opaque sequence of non-idempotent writes. Pending/conflict state, last server receipt and archive effects are visible. Conflicts remain stored until the user explicitly selects current server state; server selection journals the local intent before removal.

Subject/class creation and existing editing use the real existing API. These endpoints are not idempotent, so an uncertain delivery is never automatically retried. The editor refetches current data and asks the user to inspect it before making a new request. No fabricated server acknowledgement is shown. No private school data is shared merely because the viewer is a parent.

## Acceptance

Real synthetic PostgreSQL plus the real HTTP entrypoint must prove create/read/update/archive, process restart, same-body lost-ACK replay, payload reuse rejection, version conflicts, cross-owner denial, invalid and out-of-parent dates, ancestor archive across both new and legacy paths, and retained linked homework. Flutter substitutes must prove explicit date selection/no hard-coded default subject, durable pending mutation/reopen/exact-body retry, malformed ACK rejection, account isolation and subject/class unknown-commit handling. Device/Safari and live migration remain UNVERIFIED until run separately.
