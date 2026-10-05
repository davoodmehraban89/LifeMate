# LifeMate — Project State

**Last updated:** 2026-10-05
**Phase:** Phase 3 — Planner, School & Family Core — COMPLETE
**Repository:** `davoodmehraban89/LifeMate`
**Working product name:** LifeMate — approved

## Transfer checkpoint
Phases 1–3 are complete. Phase 3 adds the real Planner/Today core, school model and workload, family calendar/support summaries, relationship-aware sharing, reminders, offline cache/sync queue with conflict handling, Flutter RTL screens and expanded authorization/CI coverage. Railway staging has the Phase 3 API and migration active against PostgreSQL.

## Five-phase roadmap
1. **Foundation, Product Contract & UX Direction** — COMPLETE
2. **Product Foundation & Identity** — COMPLETE
3. **Planner, School & Family Core** — COMPLETE
4. **AI Guides, Learning & Wellbeing** — NEXT
5. **Hardening, Observability & Release**

## Accepted architecture baseline
- Client: Flutter for Android + app-centric responsive Web/PWA.
- iPhone/iPad initial distribution: Home Screen PWA; future packaged/native iOS path preserved.
- Backend: provider-neutral Node API + standard PostgreSQL. Railway is the current staging host; managed database/provider can be replaced without changing domain contracts.
- Identity: LifeMate-owned email/password/session adapter with Argon2id, verification/reset tokens, rotating refresh sessions and server-side authorization.
- Offline: local cache plus explicit mutation queue; server remains authoritative and rejects stale/conflicting writes.
- Authorization: relationship-aware and server-enforced; family admin is not blanket private-content access.

## Product/UX baseline
- Student navigation uses MyStudyLife as the primary IA benchmark: Today, Weekly Schedule, Calendar, Tasks, Exams/Grades, Focus, AI; LifeMate Family/Wellbeing extensions are additive.
- Parent/adult experiences share the platform while emphasizing Family, authorized progress/support information and guidance.
- Parent support focuses on authorized schedule/academic/support summaries, not routine private transcript surveillance.
- Visual language: warm, modern, calm, graphical, teen-friendly but non-childish; Persian RTL first-class. Default profile themes: daughter/teen girl = white + soft pink; son/teen boy = white + calm blue; parents/adults = white + calm blue.
- Figma remains UI source of truth; Canva is supporting visual/illustration exploration.
- Notion Project Hub is the management mirror; GitHub remains technical source of truth.

## Phase 3 completed vertical slice
Today/Planner → task/event/routine/goal/study-session creation and completion/rescheduling → reminder scheduling/claim/outbox → student life context → academic year/term/subject/class → assignments/exams/grades → family-visible calendar → guardian-authorized child support summary → offline cache/mutation queue → conflict/idempotency handling → CI/staging verification.

### Verified Phase 3 gates
- Migration `0003_planner_school_family.sql` defines the planner, academic, reminder, sharing and sync model.
- Database authorization matrix covers owner/private, family, guardian and removed-member denial behavior.
- Backend integration tests cover planner CRUD, academic setup, grades, guardian summaries, offline mutation application/idempotency and reminder outbox behavior.
- Phase 3 CI run 114 on implementation head `70cd274e8cb8b9fdf59bcc6bbd6889dbe4e09948` passed backend, security, Flutter formatting/static analysis/widget tests, Web release build and Android debug APK build. The following documentation-only commit does not alter executable code.
- Railway staging API is online and Phase 3 database smoke verification confirms 11 required tables, 3 authorization/reminder functions and the `0003_planner_school_family.sql` migration ledger entry.

## Phase 4 entry point
Build AI Guides, Learning & Wellbeing on top of the completed planner/school/family contracts. AI must remain advisory, age-appropriate, privacy-aware and relationship-aware; it must not silently broaden parent access beyond Phase 3 authorization contracts.

## Production-gate items intentionally deferred
These do not block the engineering foundation but do block public production of wellbeing/minor-sensitive AI features: jurisdiction-specific legal/guardian consent review; safety severity taxonomy; emergency resource localization; AI provider privacy/retention review; wellbeing retention/export/deletion policy.

## Guardrail
AI/wellbeing production exposure stays disabled until its dedicated safety/legal/provider gates pass. Production deploys, destructive migrations and sensitive access changes still require explicit action-specific approval.
