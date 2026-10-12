# LifeGuide — family lifecycle

Local synthetic implementation only; no live privilege changes or migration.
Family administration remains a current server-side membership capability. A
profile category/theme is never a grant of family authority.

Administrators list raw-pending invitations with a masked recipient hint and
current expiry status, then revoke with an explicit UUID/version mutation. No
token, digest or full contact is returned by the list/revoke API. Existing one-time
creation/link delivery is retained. Acceptance and lifecycle writes share the
family row lock, and expiry/session are checked after waiting.

Role changes and atomic admin transfer require active accounts/membership and
current admin authority. Version triggers cover legacy role/admin/end/rejoin and
invitation updates. Every mutation uses an actor-scoped hash receipt; retries
return current state rather than repeating changes. After transfer, an active
former administrator can acknowledge only the exact previously accepted mutation;
that does not allow a new privileged operation.

Transfer promotes the chosen active adult member and demotes the caller in one
transaction, preserving an active administrator. Teen-role targets and people
with a known under-18 birth date cannot become admins. Teen-to-adult role upgrades
require a known adult birth date. Existing adult-role members with no birth date
can receive explicit administrator transfer. Self-reported birth dates are not
legal age verification; consent/age assurance remains a separate gate.

Incompatible guardian links are deactivated. A role change removes affected
selected-member plan grants, which must be explicitly chosen again; restoring a
role never restores those links or grants. Transfer revokes the old administrator's
pending invitations so transferring back cannot revive old tokens. Archive,
membership removal and existing last-administrator protection remain in place.

Acceptance uses the actual entrypoint and independent PostgreSQL checks for
unauthorized/cross-family access, bounded projection/paging, CAS/retry/restart,
minor/disabled/ended-member rejection, one surviving admin under races, guardian
and selected-grant invalidation, and invite expiry/revocation while lock-blocked.
Physical-device and live-server acceptance remain UNVERIFIED.

The lock order is family row, all participating accounts in UUID order, their
editable profile rows in UUID order, then their memberships in UUID order. This
also serializes reciprocal writes across different families without actor-first
account deadlocks. The current age context is locked separately because profile
editing does not acquire the account lock. At commit, the session row is held
with `FOR SHARE`, then a separate statement checks current session and JWT expiry
using fresh database time after any lock wait; a failed check rolls back writes,
audit and mutation receipt together. No fixed sleep substitutes for a lock in
the race tests; they observe the real wait graph through `pg_blocking_pids`.

Known under-18 birth dates also prevent obtaining administration through new
family creation. Legacy family writes and invitation acceptance retain their
existing APIs and receive the same final current-session gate in the root-owned
server integration. Self-reported age remains an unverified legal/consent gate.
