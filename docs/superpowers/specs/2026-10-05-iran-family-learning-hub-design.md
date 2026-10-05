# Feature 1 — Iranian Family & Learning Hub Design

## Intent
Complete LifeMate's owner-testable family/school/planner experience for an Iranian household. A household can explicitly identify mother, father and children; a child can carry age/sex and Iranian education stage/grade; school setup can use a grade-aware curriculum catalog; planning is Jalali-first with Iranian week semantics and official-event metadata; sensitive menstrual tracking remains strictly private.

## Architecture
Add one final migration and a focused `phase6` API router rather than restructuring existing phases. Keep current technical authorization roles as the security layer and add household persona as profile metadata. Add canonical education/catalog tables that are safe to seed and user-specific enrollment/profile tables. Flutter consumes the new APIs through a dedicated final-feature surface while retaining Phase 3/4 flows.

## Privacy and security
- `menstrual_cycle_entry` is owner-only: no family or guardian read endpoint.
- Household persona is presentation metadata; it never grants authorization by itself.
- Child education profile writes require owner or active guardian relationship.
- Textbook catalog stores metadata and official-source URLs, not copyrighted PDF binaries.
- External textbook links are restricted to HTTPS and trusted official hosts.
- Notification preferences are per-user; sensitive reminder previews default off.

## Iranian education model
Stages: `primary_1` (grades 1–3), `primary_2` (4–6), `secondary_1` (7–9), `secondary_2` (10–12). Store canonical national grade 1–12. Grade 7 maps to `secondary_1`, local year 1.

The Grade 7 starter catalog includes Persian, Writing, Mathematics, Experimental Sciences, Social Studies, Arabic, Quran, Heavenly Messages, English, Work & Technology, Thinking & Lifestyle, and Physical Education/Health. Catalog rows are versioned by school year and can be updated without changing user records.

## Textbooks
LifeMate may show catalog metadata and links to official Ministry textbook distribution sources (for example `chap.sch.ir`) and may support user-initiated lawful download/import later. The repository will not embed textbook PDFs unless redistribution rights are verified.

## Calendar
- Jalali is the default presentation calendar for Iranian locale.
- Week starts Saturday; Thursday/Friday are configurable weekend defaults, with Friday treated as the statutory weekly holiday in the seeded policy.
- Official-event records are versioned by Jalali year and source provenance. 1405 data provenance points to the official calendar process (Calendar Center, Institute of Geophysics, University of Tehran / Supreme Council of Cultural Revolution approvals).
- Calendar data is data-driven so later annual updates do not require UI rewrites.

## Notifications
Per-user preferences cover in-app banner, push eligibility, reminder categories and sensitive-preview suppression. Existing reminder claims remain the delivery queue until a production push provider is configured.

## Menstrual tracking
Optional owner-private entries record start/end dates, symptoms/notes, predicted-next date and reminder opt-in. This is a personal wellness organizer, not diagnosis or contraception/fertility advice.

## Release acceptance
1. Existing regression suite remains green.
2. New schema/contract tests pass.
3. Flutter format/analyze/tests pass.
4. Web release build and Android APK build pass and artifacts are retained in CI.
5. iOS source compiles conceptually through Flutter project configuration; signed iOS binary remains gated on macOS + Apple signing credentials.
6. No production/public deployment occurs automatically.