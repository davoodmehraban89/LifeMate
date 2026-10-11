# LifeGuide: Iranian school library with in-page Aparat teaching

Status: implementation authorized by the owner on 2026-10-09; local/test work only. Updated for the owner's full content-review gate, assessment and family-feedback requirements. This extends Feature 1 and the real planner, rather than replacing identity, family, calendar, offline storage or study timers.

## User outcome

An authenticated learner selects grade 1–12 and, for grades 10–12, a track. The library shows corresponding books, ordered lessons/pages and only fully reviewed, published teaching resources. Research candidates remain draft; current metadata research does not count as full pedagogical review. The learner can start at any lesson midyear, explicitly record personal progress, and add a lesson to the existing durable study planner. Approved video plays in the same screen. Videos are never downloaded, rehosted or transcribed. See ADR0013 for formative assessment, explicit feedback and family-learning boundaries.

Initial upper-secondary content covers the three academic tracks (math, experimental sciences, humanities) unless the owner's pending clarification expands it. Vocational tracks remain an explicit content gap; the catalogue can add them later. A listed book is not evidence of a complete video course. Missing lessons and unverified edition alignment must remain visible.

## Data and API

- Additive migration 0013 extends `education_profile` with validated track selection, and extends the existing curriculum/textbook catalogue with stable book keys, edition/variant/source evidence. Existing migration files/checksums and grade-7 seed remain unchanged.
- Add ordered learning units and hash-only Aparat resources, linked to the textbook. Retain the original source hash and optional canonical metadata UID. Store title, author/channel, source, verification time, free-access evidence and review limitations, never media URLs or arbitrary embed HTML.
- Deterministic, transactional, idempotent catalogue import consumes checked public research JSON. Imports do not make external network calls or invent missing lessons. Official HTTP source references remain accurately labelled as references; playback uses HTTPS only.
- `GET /v1/education/library` returns selected education context and courses, with grade/track/year filters; `GET /v1/education/courses/:id` returns ordered units, source/edition warnings and only the caller's progress. Older/unknown editions are labelled and never silently relabelled as the selected year.
- `PUT /v1/me/learning-progress/:unitId` accepts status `not_started`, `in_progress` or `completed`, source `self_reported`, UUID `mutationId` and `expectedVersion`. Owner derives exclusively from the authenticated session. Mutation hashing, transaction locks and optimistic versions make retries idempotent and conflicts explicit. Read/update/reset survive restart. No parental watch-history or another-user progress endpoint is introduced.
- Extend canonical plan mutations with optional validated `learningUnitId`; do not misuse child-owned `subjectId` for a global textbook. Existing sharing rules, stable UUIDs, server acknowledgements and study-session interval model remain authoritative.

## Client and privacy

Persian RTL library has grade/track/year settings, subject/book search, availability counts, ordered units, direct midyear selection, previous/next navigation, resource credits and explicit self-reported progress. Empty courses explain the coverage gap. Progress uses the authenticated endpoint/account namespace, durable enqueue-before-send, accepted-server timestamps and conflicts retained for deliberate resolution. Cached metadata/progress are labelled stale/offline; streaming requires connectivity and is never described as offline-capable.

The Aparat iframe/WebView loads only after the learner explicitly chooses to load it. Accept bounded ASCII alphanumeric hashes and construct the canonical HTTPS embed URL internally. Web iframe uses `no-referrer`, a minimal sandbox and fullscreen permission without autoplay. Credentials, student identity, profile, grade and progress are never sent to Aparat. This is the owner's explicitly requested, narrow third-party video exception: API, fonts, CanvasKit and other application assets remain local; do not broaden app script/connect policies to provider CDNs. Aparat may handle IP/device metadata, advertising or cookies after interaction; LifeGuide cannot promise an ad-free player or control provider removal/access. External AI/voice and sensitive health features remain disabled.

Opening a frame, elapsed video time or a page load never proves studying, understanding or completion. Progress is the learner's explicit report. Planning launches the existing study timer; recorded time retains its existing disclosure. Changing grade does not delete plans/progress from earlier grades.

## Curation and acceptance

Select sources using textbook/edition alignment, lesson sequence, free-access evidence, named teacher, clarity/explanation/exercises and coverage. Search/index/metadata checks are distinct from watching a lesson or validating pedagogy; unperformed pedagogical review is UNVERIFIED. Paid previews, mismatched pagination, expired links and missing subjects are not presented as a complete free school.

Acceptance: import repeat preserves IDs/counts; grades and tracks filter correctly; missing/old/variant books are visibly distinguished; real authenticated HTTP + independent PostgreSQL verifies progress, restart, retry, conflict and owner isolation; planner linkage persists with stable sync IDs; Flutter tests verify library navigation, durable offline progress and no auto-completion; compiled web shows an in-page canonical iframe after explicit load and no third-party requests beforehand. Actual Android playback/fullscreen and Safari Add to Home Screen/playback remain UNVERIFIED until a real device is available.

No public deployment, live schema change, merge, provider signup or paid action is authorized by this design.
