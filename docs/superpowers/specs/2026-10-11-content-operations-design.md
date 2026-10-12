# LifeGuide — consented content operations

Date: 2026-10-11. Authorized scope: local code, synthetic tests, documentation and feature PRs. Production grants, publishing, external messages, deployment and real data are outside this packet.

## Problem and acceptance

The existing feedback API stores an explicitly chosen learner summary and supports withdrawal, but has no working review inbox or development brief. Family membership must never confer platform-content authority. Implement a real PostgreSQL-backed workflow with independent capabilities, versioned status updates, durable retry acknowledgement and a Persian operator interface. Preserve catalogue publication gates; feedback approval does not publish media or assessments.

Acceptance: an ordinary parent is denied; a synthetic explicitly granted operator can list consented summaries, triage one, plan it and prepare a metadata-only brief. Withdrawal, expired/revoked grants and stale versions close access. A lost acknowledgement can be retried without repeating a mutation. Closing/reopening retains only mutation intent metadata; summaries and grants are not cached. A brief must be revalidated before copying and becomes unavailable after any source withdrawal/change. Tests must run against real synthetic PostgreSQL and widget/browser substitutes, with actual devices labelled UNVERIFIED.

## Contract

- `GET /v1/me/content-capabilities`: `{permissions:[]}` by default. Explicit grants: `feedback.read`, `feedback.review`, `brief.prepare`. No role inference or HTTP grant route. Separate local-only synthetic capability CLI; runtime DB role can only read the grant table.
- `GET /v1/content-review/feedback`: bounded UUID cursor pagination and allowlisted status, only currently consented/unwithdrawn rows; return id, public unit id, category, chosen summary, status, version and timestamps. Never owner id, contact information, chat, health, notes or profile.
- `PATCH /v1/content-review/feedback/:id`: `{mutationId,expectedVersion,status}`. Transitions: received → triaged/declined; triaged → planned/declined; planned → triaged/declined; declined → triaged. `released` is not writable. Compare-and-swap, actor-scoped request hash ledger and exact server acknowledgement. Replays return current state; withdrawal wins. Missing/withdrawn rows 404, stale/invalid transitions 409.
- `POST /v1/content-review/briefs`: `{mutationId,feedback:[{id,expectedVersion}]}`; at most20 currently planned, consented sources. Requires read and brief capabilities. Output contains only public catalogue context, category counts and fixed research task text; no submitted/reviewer free text or feedback/contact/owner identifiers. Public unit identifiers are allowed.
- `GET /v1/content-review/briefs/:id`: re-check current permissions and source status/version/consent; invalidated briefs return409, never their old payload. Store a restricted source linkage internally, not in exported output.

## Safety and client behavior

Check grants on every request and lock consistently with revocation and withdrawal. Audit identifiers, actor and status changes rather than user text. Existing private learning progress/attempts remain owner-only. The UI loads actual capabilities and defaults to hidden; it never substitutes parent/admin membership. The inbox is online-only, memory-only, clears on failed refresh/auth/revocation, and rejects late responses across identity/endpoint generations. Review mutation journals store only IDs, versions, status and stable UUIDs in the existing account/endpoint namespace. Explicit retry reuses the identical body; no automatic offline moderation.

The brief is a research starting point, not a diagnosis, an instruction to deploy or evidence that requested teaching is correct. Copying cannot magically revoke a previously copied document; the runbook must require revalidation and avoid storing personal text. External AI/messages and autonomous publication stay disabled. Full video viewing, rights, current textbook mapping and qualified assessment review remain separate publication gates.

## Coordinated ownership

Backend content-operations specialist owns migration0016, dedicated router, capability CLI and DB policy. Client specialist owns new content-review UI/journal. Accessibility specialist owns existing education status semantics. Research specialist owns a draft grade1 math pilot and source evidence. Root owns integration, shared docs/version, full verification, commits and PR. Independent audit and reporting tasks use separate files.

## Remaining local work

Follow the completion-gap audit: owner review/history UI, explicit report periods, goal retry/version contract and CRUD interface, school setup/lifecycle, family lifecycle and safe offline shell. These are engineering tasks, not proof of a fully reviewed first-through-twelfth-grade school or real Safari/device acceptance.
