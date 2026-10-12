# ADR0014 — Separate content operations from family permissions

Date: 2026-10-11. Status: Accepted for authorized local implementation; live grants/publication remain gated.

Existing learner feedback is voluntary chosen text, with withdrawal. To turn it into reviewable development work, add independent expiring/revocable content capabilities. A family parent/admin never gains cross-user content access by implication. Runtime credentials cannot grant capabilities or publish catalogue definitions.

Review statuses use the existing received/triaged/planned/declined vocabulary. Versioned transitions and actor-scoped UUID acknowledgements make retries safe. `released` cannot be set by this API; a later publication workflow must supply real evidence and separate approval.

Development briefs contain public catalogue metadata, category counts and fixed tasks only. User/reviewer free text, source feedback identifiers and private contacts/chats/notes/health are excluded. Every retrieval checks source consent/version/status and current capabilities. Withdrawal invalidates the brief; previously copied material cannot be remotely erased, so copies must remain minimal and be revalidated before action.

The operator client uses a memory-only online inbox and explicit retry for durable ID/version/status mutation intents. Errors and revocation clear rows instead of presenting stale summaries as current. External AI, automatic messaging, publishing and deployments remain disabled. This provides an auditable human-controlled research loop, not autonomous changes to the product.

See [design](../superpowers/specs/2026-10-11-content-operations-design.md) and [plan](../superpowers/plans/2026-10-11-content-operations.md). Actual verification receipts will be added after execution.
