# LifeMate — Product Specification v1

**Status:** Phase 1 baseline
**Date:** 2026-10-05

## 1. Product definition
LifeMate is a personal, family and learning companion. It begins with a teen-and-family scenario but must grow with a person across school years and later life. It is not a surveillance app, not only a student planner, and not a clinical mental-health product.

## 2. Primary V1 actors
- **Family Owner/Admin:** manages family workspace, membership and allowed family policies.
- **Parent/Guardian:** supports a minor through authorized planning, academic reports and meaningful support signals.
- **Teen:** manages school, personal planning, goals and AI-assisted learning/wellbeing experiences.
- **Adult Member:** uses personal/family planning with selective sharing.

Family size and composition are dynamic.

## 3. V1 product surfaces
### Today
A prioritized view of classes, tasks, study sessions, family items and the next useful action.

### Planner
Calendar, tasks, routines, goals, reminders, priorities, duration and rescheduling.

### School
Academic year/term, subjects, classes, homework, exams, study sessions and grade/progress foundation.

### Family
Membership, invitations, relationships/roles, family calendar and controlled sharing.

### Progress
Personal/academic completion and understandable parent-authorized summaries.

### AI Guides
Planner, Study Coach/Tutor, Wellbeing Companion and Parent/Family Coach, introduced only with explicit context permissions and safety rules.

## 4. Identity and account requirements
- Every person has an independent account.
- Email is the initial verified recovery channel.
- Forgot Password sends a secure time-limited reset path to the verified email.
- Change Password is available from authenticated settings.
- Family invitations must identify the target workspace and expire.
- Passwords are never shared between family members and parents do not receive a child's password.
- Username/mobile may be added as identifiers after the foundational identity flow is secure; they must not weaken recovery security.

## 5. Family and visibility contract
Conceptual visibility levels:
1. Private
2. Selected Members
3. Parent/Guardian
4. Family
5. Safety-Controlled

Parent access is meaningful but not equivalent to unrestricted access to every private teen conversation. Academic planning/reporting is parent-visible by policy; private journal/conversation content requires separate policy. Immediate safety handling is a separate system path.

## 6. Planning and reminders
- Tasks/events may have one or more lead-time reminders.
- Completion cancels obsolete reminders.
- Rescheduling updates dependent reminders.
- Missed work should trigger supportive recovery/reschedule options, not punitive messaging.
- Notification frequency and quiet hours must be configurable.
- Family-shared items notify only relevant members.

## 7. School contract
Core entities: AcademicYear, Term, Subject, ClassSession, Assignment, Exam, StudySession, Grade and RevisionPlan.

Useful student-planner capabilities identified during discovery remain in the feature inventory, including rotating schedules, homework/exam tracking, revision planning, focus sessions, unified calendar and AI-assisted planning. Inclusion in the inventory does not automatically mean inclusion in the first executable release.

## 8. AI contract
AI may:
- explain and tutor;
- propose study/life plans;
- break large tasks into steps;
- propose replanning after missed work;
- provide non-diagnostic wellbeing reflection and general coping suggestions;
- provide parent/family communication guidance.

AI must not:
- bypass data permissions;
- silently expose private teen content to parents;
- claim a medical/psychological diagnosis;
- impersonate a clinician;
- present itself as the user's exclusive or primary human-like relationship;
- perform sensitive/high-impact changes merely because a model suggested them.

## 9. Wellbeing and safety
The teen experience may support text and later voice conversation, mood/energy/stress check-ins and reflections. Parent experience should emphasize trends, actionable summaries and conversation guidance rather than routine transcript surveillance.

Safety handling must distinguish ordinary wellbeing data from immediate-risk events. Detailed thresholds, escalation behavior and jurisdiction-specific obligations are Phase 1 architecture/safety deliverables.

## 10. Distribution and experience
- Android: installable application.
- iPhone/iPad: polished PWA installed through Add to Home Screen.
- Web/Desktop: responsive application.
- Shared backend, identity, authorization and data model.
- Persian RTL is first-class.
- iPhone PWA must feel branded and app-like, with proper icon/entry experience and platform-aware behavior.

## 11. Visual product direction
Teen experience should be warm, modern, graphical, calm, inviting and age-appropriate without becoming childish. The visual system must age gracefully. Parent experience uses the same brand language with denser, more actionable information.

Brand deliverables include logo direction, app/PWA icon, favicon, splash/entry, login/onboarding, typography, color system, illustration language, empty states and light/dark considerations. Figma is the UI/UX source; Canva may provide illustration and educational visual assets.

## 12. Explicit V1 boundaries
The first executable product should not attempt:
- clinical diagnosis or treatment;
- continuous location tracking;
- social network/community features;
- deep integrations with every school/LMS;
- heavy gamification;
- a marketplace/plugin ecosystem;
- uncontrolled autonomous actions.

## 13. Phase 1 acceptance criteria
Phase 1 is complete when:
- five-phase roadmap and V1 scope are recorded;
- role/permission/visibility rules are explicit enough to design server authorization;
- primary information architecture and user journeys are documented;
- visual/brand brief is ready for prototype work;
- frontend/backend candidates have decision records with tradeoffs;
- safety/privacy boundaries have explicit unresolved items and owners;
- Phase 2 implementation can begin without inventing identity, family or distribution rules during coding.
