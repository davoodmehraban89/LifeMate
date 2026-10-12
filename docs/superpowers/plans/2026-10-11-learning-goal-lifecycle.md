# Private learning goal lifecycle

Scope: existing PostgreSQL learning goals, not new AI/wellbeing or sharing.

1. Add migration0017: monotonically versioned goals, nullable archived timestamp,
   owner-scoped mutation UUID/request-hash ledger with durable applied version.
2. Preserve unversioned HTTP clients; their edits also advance goal version.
   Modern create supplies stable goal UUID + mutation UUID + expectedVersion0;
   modern edit/archive requires expectedVersion and rejects stale writes409.
3. Serialize all goal writes by active account row and goal row. Owner checks
   apply on every read/write; guardian membership never grants private goals.
   Legacy nonowner reads keep concealed404. Modern foreign-ID writes return403.
4. Replay an accepted request with the same hash without duplicate writes.
   Return the current goal, including an archived tombstone, and original
   mutation acknowledgement. A reused UUID with another body fails409.
   Keep linked learning check-in history; archive never deletes it.
5. Flutter HTTP screen: create/read/edit/complete/archive with explicit errors,
   pending intent and manual sync. Persist intent before sending, validate exact
   mutation/account/goal/version acknowledgement, namespace by API+account.
   Unacknowledged or conflicted writes remain recoverable. FakeAPI hub remains
   available only to existing explicit test clients.
6. RED/GREEN: real local synthetic PostgreSQL HTTP restart/replay, concurrent
   stale writes, subject ownership, guardian/other-family denial, archived retry;
   widget/offline tests for lost acknowledgement, reopen, errors and isolation.

Publication/deployment, real device acceptance and foreign data are out of scope.
