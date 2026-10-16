# Approved mobile navigation — Flutter implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. Implement task-by-task; preserve the existing client and API.

**Goal:** Replace the authenticated entry with the approved, compact home menu and separate working destinations, including a selected task detail using the existing server-backed planner.
**Architecture:** Flutter HomeShell owns primary navigation; a small presentation-only mobile_home.dart supplies the approved warm/teal menu. Existing EducationLibraryPage, StudyHub, family/report, notification and account/sync pages remain authoritative. Task detail delegates mutations to the existing PlanSync; no new database or authentication model.
**Tech stack:** Flutter/Dart, existing HTTP API, PlanSync and user-scoped OfflineStore.
**Spec:** design-review/mobile-v1/README.md and exports/LifeGuide-overview.png, approved by owner in this conversation on2026-10-16.

## Global constraints
- No merge, deployment, live endpoint/DNS/database changes, external AI/SMS or real data.
- Existing Flutter only; React design remains a reference. All screenshots/fixtures synthetic.
- Profile category controls presentation only; server remains permission authority.
- No fake counts, video, quiz, session durations, parent visibility or alarm claims.
- Preserve pending changes, logout/scope gates, review capabilities and disabled sensitive guide.
- One small draft PR stacked on design PR30; full product phase1/online hosting acceptance is still incomplete.

## Review focus
- Small screens320/390 and large text: six child menus reachable, no overflow; scroll only when space/accessibility requires it.
- Profile failure/change or missing family: no wrong-role navigation, retry and correct home after context reload.
- Shared/view-only tasks: detail cannot offer mutation/timer controls; backend permissions unchanged.
- Pending offline creation: edits remain queued; no study until server ACK; conflicts stay visible.
- Back/account/scope transitions: selected item is correct; preserve root logout/cache isolation and invalidate obsolete routes as before.

### Task1 — Home and separate destinations
**Files:** lib/main.dart; new lib/mobile_home.dart; test/mobile_navigation_test.dart; existing online_ui_test.dart as needed for intentional menu labels.
**Consumes:** IdentityApi.getProfile(), existing pages and HomeShell callbacks.
**Produces:** compact HomeMenu (profile name, child/adult layout, selection callback); HomeShell routes every main menu to its existing API-backed page, root back returns home.
- [x] Write tests against existing HomeShell for six menus and back at320/390, profile name, adult presentation independent from family membership, profile failure retry.
- [x] Run focused Flutter tests; expect missing home/menu assertions (RED).
- [x] Implement approved palette/layout and reuse existing destinations; preserve drawer capabilities/scope/logout.
- [x] Run focused tests and full suite; expect all PASS. Commit.

### Task2 — Selected task detail
**Files:** lib/phase3_ui.dart; new lib/plan_details_ui.dart; test/mobile_navigation_test.dart.
**Consumes:** selected plan map, PlanItemDialog and PlanSync mutation outcomes; task kind/status/visibility/owner/version.
**Produces:** PlanDetailsPage with correct selected content, edit/complete/archive via existing caller, server-ACK/pending states; approved presentation without fake data.
- [x] Tests: selecting second item opens its own detail; edit and completion show ACK/queued state; archive confirmation; shared non-owner view is read-only; pending cannot start study.
- [x] Run focused tests before implementation; expect absent detail route (RED).
- [x] Delegate actions to existing planner logic; retain existing popup actions for compatibility and scope guards.
- [x] Run focused tests and full suite, formatting/analyze; expect all PASS. Commit.

### Task3 — Evidence and delivery
**Files:** docs/ux/mobile-navigation implementation receipt; PROJECT_STATE.md; design status.
**Consumes:** final Flutter source, local synthetic Node+PostgreSQL API and compiled web build if available.
**Produces:** real build and interaction receipts/screenshot, draft PR; explicit UNVERIFIED physical devices, signing, hosting and managed-child legacy API gates.
- [x] Run flutter analyze/test; build web --release --no-web-resources-cdn --pwa-strategy=none and bundle local resources.
- [x] Exercise compiled client through local synthetic API/PostgreSQL; independent read-after-write if fixture setup available. Never reuse live or real-data hosts.
- [x] Independent wholebranch review; fix important findings with regression checks.
- [x] Record commands/results/limits, commit and open draft PR. No merge/deploy. Stop and report this delivery.
