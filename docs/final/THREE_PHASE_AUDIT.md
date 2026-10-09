**Historical snapshot — retained as decision/evidence history. Current product: LifeGuide; current execution status: PROJECT_STATE.md.**

# LifeMate — Final Three-Phase Audit

Date: 2026-10-05
Baseline: `main@22e1115179f11b28a031954692b05ea2d8794c33`

## Phase A — Functional and product review

### Confirmed existing
- Identity/session foundation and family workspaces.
- Planner, reminders, school years/terms/subjects, assignments/exams/grades.
- Parent/guardian relationship model and minor-aware authorization.
- Learning/wellbeing/AI advisory vertical slice with explicit plan acceptance.
- Offline cache/queue, responsive Flutter Web/PWA + Android shell.

### Gaps found
1. Family roles are technical (`parent_guardian`, `teen_minor`, `adult_member`) rather than explicit household personas (mother/father/child) with child sex, birth date/age and education profile.
2. School setup is generic/manual; it does not map Iranian stage + grade to a canonical subject/book catalog.
3. Grade 7 quick setup creates only Mathematics and uses Gregorian-style academic-year defaults.
4. Calendar UI is not Jalali-first and does not expose an official-Iran event/holiday catalog.
5. Reminder UX exists, but there is no unified notification preference model for banner/push/reminder categories.
6. No private menstrual-cycle tracker/reminder surface exists.
7. iOS project structure exists through Flutter, but the release gate does not build an iOS artifact; signed iOS distribution still requires Apple signing/provisioning on macOS.
8. Official textbook PDFs are not bundled. Bundling third-party/copyrighted binaries without a verified redistribution license is not acceptable; the product should keep official source metadata/links and allow lawful import/download.

## Phase B — Quality, data-integrity and cross-platform review

### Confirmed existing
- CI runs backend migrations, authorization tests, Node tests, syntax/schema checks, backup/restore drill, Flutter format/analyze/tests, Web release build, Android build and PWA metadata checks.
- Phase 5 branch and post-merge CI were green before this final phase.

### Gaps to close
- Add contract/schema tests for persona/profile privacy, Iranian education mapping, calendar source metadata, textbook catalog and menstrual privacy.
- Add Flutter tests for Jalali conversion/weekday semantics and Iranian grade mapping.
- Add release artifacts for installable Android APK and Web bundle; document iOS signing gate explicitly.

## Phase C — Security and privacy review

### Confirmed existing
- Server-side relationship-aware authorization.
- Private AI/wellbeing transcripts and separate safety ledger.
- Security headers, request IDs, rate limits, bounded request bodies, secret scanning, dependency audit and backup/restore drill.

### High-priority final controls
- Menstrual data must be owner-private by default and never inherited by family/guardian visibility.
- Child education/persona data must be mutable only by the child owner or an active guardian with explicit relationship.
- Calendar/textbook external URLs must be allowlisted to trusted official sources and never execute remote content.
- Notification preferences must not leak sensitive reminder titles to family members.
- No production AI/voice or public release is enabled by this feature phase.

## Final-phase scope

The remaining engineering scope is consolidated as **Feature 1 — Iranian Family & Learning Hub**:
- explicit mother/father/child persona metadata;
- Iranian education stage/grade profile and grade-aware subject catalog;
- Grade 7 curriculum starter catalog and official textbook-source metadata;
- Jalali-first calendar semantics, Iran weekend defaults and official-event data model;
- notification/reminder preferences;
- owner-private menstrual-cycle tracking and reminders;
- Web/Android release artifacts and iOS readiness documentation;
- full regression/security verification.

Public production deployment, App Store/Play Store publication, Apple signing credentials, external AI/voice enablement, and redistribution of textbook PDFs without verified rights remain external release gates rather than engineering omissions.