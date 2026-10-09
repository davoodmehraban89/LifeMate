**Historical snapshot — retained as decision/evidence history. Current product: LifeGuide; current execution status: PROJECT_STATE.md.**

# LifeMate — Permission & Visibility Matrix v0

**Status:** Phase 1 working contract
**Purpose:** establish a concrete baseline for UX and server-side authorization design. Detailed age/jurisdiction policy remains pending.

## Roles
- **Owner/Admin** — workspace administration.
- **Parent/Guardian** — guardian relationship to one or more minors.
- **Teen/Minor** — minor family member.
- **Adult Member** — non-guardian adult family member.

`Owner/Admin` is an administrative role, not an automatic right to read every private item.

## Baseline matrix

| Resource / action | Owner/Admin | Parent/Guardian | Teen owner | Other member | Baseline visibility |
|---|---|---|---|---|---|
| Own profile/settings | own only | own only | own only | own only | Private |
| Family membership list | manage | view | view | view | Family |
| Invite/remove member | manage | policy-dependent | no | no | Admin action |
| Family roles/policies | manage | view / limited proposal | view relevant | view relevant | Family/Admin |
| Own private task/event | no automatic read | no automatic read | manage | no | Private |
| Family task/event | manage if authorized | create/manage if authorized | create/manage if authorized | create/manage if authorized | Family/Selected |
| Teen school schedule | no automatic read unless guardian/admin policy | view | manage | no | Teen + Guardian |
| Teen homework/exams | no automatic read unless guardian/admin policy | view/support | manage | no | Teen + Guardian |
| Teen grade/progress report | no automatic read unless guardian/admin policy | view | view/manage source data | no | Teen + Guardian |
| Teen private journal/reflection | no | no routine transcript access | manage | no | Private |
| Teen AI wellbeing transcript | no | no routine transcript access | access own | no | Private with separate safety path |
| Teen wellbeing trend/parent insight | no automatic read unless guardian relation | view if policy permits | view own | no | Guardian summary |
| Immediate safety event | policy/audit only as required | safety policy may notify | receives appropriate support UX | no | Safety-Controlled |
| Parent private note | no automatic read | manage own | no | no | Private |
| Shared family goal/routine | manage if authorized | participate | participate | participate | Family/Selected |

## Enforcement principles
1. Authorization is relationship-aware: `Parent` is meaningful only in relation to the relevant minor.
2. Administrative ownership does not erase content privacy.
3. Safety-controlled access is not a general-purpose backdoor to private data.
4. AI context retrieval uses the same effective permissions as product APIs.
5. Sensitive policy changes and safety access require auditable events.
6. Removing a member revokes future access; historical retention/deletion behavior requires a separate data-retention decision.

## Open Phase 1 decisions
- Exact age bands and whether visibility defaults change with age.
- Whether both guardians must approve specific privacy-policy changes.
- Rules for a guardian relationship ending or being disputed.
- Jurisdiction-specific parental consent/data rights.
- Exact safety-event thresholds and notification recipients.
- Retention/export/deletion rules for wellbeing data.
