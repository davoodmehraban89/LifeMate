# LifeMate — Conceptual Domain Model v1

## Identity
- **Account** — authentication identity; credentials/session are not family-shared.
- **Profile** — person-facing identity and preferences.
- **LifeContext** — Student, Work, Personal or future contexts attached to Profile.

## Family
- **FamilyWorkspace** — tenant/boundary for family-shared data.
- **Membership** — Profile ↔ FamilyWorkspace with status and administrative capabilities.
- **GuardianRelationship** — explicit adult ↔ minor relationship; permissions depend on this relation, not only generic role names.
- **Invitation** — expiring/revocable join intent.
- **SharingGrant** — resource-level audience/visibility representation where policy allows.

## Planning
- **PlanItem** — common scheduling identity for task/event/study/family commitments where shared fields are useful.
- **Task** — actionable item with status, priority, duration and optional due time.
- **CalendarEvent** — time-bound commitment.
- **Routine** — repeatable behavior/template.
- **Goal** — outcome with optional linked plan items.
- **Reminder** — delivery rule linked to a resource; obsolete reminders are cancelled on completion/reschedule.

## School
- **AcademicYear** → **Term**.
- **Subject** belongs to a Student LifeContext and academic period.
- **ClassSession** represents timetable occurrences/rules.
- **Assignment**, **Exam**, **StudySession**, **Grade**, **RevisionPlan** attach to Subject/period as appropriate.

## Wellbeing / AI
- **GuideSession** — AI interaction session with explicit guide type and context scope.
- **CheckIn** — structured self-reported mood/energy/stress signals; not a diagnosis.
- **ParentInsight** — derived, policy-controlled support summary; never assumed to equal raw transcript.
- **SafetyEvent** — separately governed event for defined safety escalation conditions.
- **AIProposal** — suggested plan/action requiring user confirmation unless a future policy explicitly permits safe automation.

## Governance
- **AuditEvent** — immutable security/policy-relevant event metadata.
- **NotificationPreference** and **QuietHours** — per-profile delivery policy.
- **DeviceSubscription** — push endpoint/device metadata without becoming identity authority.

## Ownership invariants
- Personal resources have an owning Profile.
- Family resources have a FamilyWorkspace and creator/owner semantics.
- School resources belong to the student's Profile/LifeContext, not to the parent account.
- Guardian visibility is computed from relationship + resource policy + age/safety policy.
- Admin capability never implies blanket read access to private content.
- AI retrieval is downstream of the same authorization decision as human-facing APIs.

## Data lifecycle principles
Membership removal revokes future access. Retention/export/deletion rules for shared and wellbeing data are explicit policy decisions; no cascade behavior is assumed merely because a relationship ends.