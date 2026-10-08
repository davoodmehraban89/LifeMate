**Historical snapshot — retained as decision/evidence history. Current product: LifeGuide; current execution status: PROJECT_STATE.md.**

# LifeMate — Information Architecture & Primary Journeys v1

## Navigation model
### Teen / personal mobile
Bottom navigation: **Today · Planner · School · AI · Me**. Family-shared context appears inside Today/Planner and a Family section under Me; it is not allowed to dominate the teen experience.

### Parent / adult mobile
Bottom navigation: **Today · Planner · Family · Guide · Me**. School/teen support is entered from the relevant child inside Family rather than treating the adult as a student.

### Web / tablet
Adaptive navigation rail/sidebar with the same destinations. Content hierarchy changes responsively; permissions and domain semantics do not.

## Core surfaces
- **Today:** next action, time-sensitive items, study/family commitments, lightweight check-in.
- **Planner:** calendar, tasks, routines/goals, reminder controls.
- **School:** timetable, subjects, assignments, exams, study/revision.
- **Family:** members, shared calendar/items, invitations, role/visibility settings, child support views.
- **AI/Guide:** context-aware guides with visible scope and privacy cues.
- **Me/Settings:** profile, life contexts, account/security, notifications, privacy, appearance, language.

## Journey 1 — New family owner
Create account → verify email → create Family Workspace → choose own role → invite members → review default visibility policy → land on Today. Invitations are revocable/expiring and never transmit a password.

## Journey 2 — Teen joins family
Open invitation → create/attach independent account → verify email as applicable → see plain-language explanation of what parents can and cannot see → set school context → land on Teen Today. Privacy explanation is part of onboarding, not buried in legal text.

## Journey 3 — Build a school week
Create academic year/term → add subjects → add repeating class schedule → add assignments/exams → LifeMate surfaces Today/Week workload → teen schedules study sessions → reminders follow schedule changes.

## Journey 4 — Parent support review
Parent opens Family → selects child → sees authorized upcoming workload, completion/progress and support summary → receives suggested conversation/support action → cannot silently open routine private wellbeing transcripts.

## Journey 5 — Share a plan item
Creator makes task/event → chooses Private / Selected Members / Parent-Guardian / Family where applicable → recipients see clear source/owner → changes notify only affected members → creator can change future visibility subject to safety/audit policy.

## Journey 6 — Password recovery
Forgot password → enter email → generic success response prevents account enumeration → secure time-limited recovery link → set new password → existing session/security policy applied → confirmation shown.

## Journey 7 — Missed work recovery
Task/study session becomes overdue → no shaming copy → offer complete / reschedule / break into steps / ask Study Coach → dependent reminders update after confirmed change.

## Journey 8 — Wellbeing conversation
Teen enters Guide → sees privacy scope → conversation/check-in → general reflective support → if ordinary: remains private under policy; if safety threshold is met: separate safety flow is invoked with clear user-facing messaging appropriate to the event.

## Accessibility & RTL baseline
- Persian RTL is native layout direction, not mirrored as an afterthought.
- Minimum touch target 44×44 CSS px / platform-equivalent.
- Do not encode status by color alone.
- Dynamic text scaling must not clip primary actions.
- Motion must respect reduced-motion preference.
- Contrast target: WCAG 2.2 AA for normal product UI.
- Teen copy is supportive and concise; avoid punitive productivity language.

## Prototype screen inventory
Welcome/Login; Forgot Password; Reset Password; Create/Join Family; Teen Privacy Explainer; Teen Today; Parent Today; Planner Day/Week; Task Editor; School Overview; Subject; Assignment/Exam Editor; Study Session; Family Overview; Child Support Summary; Sharing Sheet; AI Guide Home; Wellbeing Privacy Sheet; Settings/Security/Notifications/Privacy.