# Reviewed education and consented content feedback

Status: owner-authorized local implementation packet, 2026-10-09. This spec
extends the school-library design after the owner's stricter review requirement.
It does not authorize a live migration, external AI, content publication or deploy.

## Learning and publication boundary

Public metadata and a working embed are research leads, not reviewed instruction.
Every current researched video remains **DRAFT**. The learner catalogue must not
present these as trusted published teaching; the current fully reviewed count is
zero. A source can later be Aparat or another legally embeddable free provider,
but a new provider needs its own rights, player, privacy and technical review.

Before publication a human content reviewer watches the complete lesson and
checks each explanation, worked step, exercise and answer against the latest
official Iranian textbook for the specific grade, track, book code, edition,
chapter and pages. The record must identify the official edition/source, video
identity, review date/reviewer, precise alignment, omissions, inaccuracies,
age-appropriate language and accessibility/clarity limits. Metadata/search checks
cannot replace this review. A mismatch, incomplete review, removed video or
unknown free-access permission blocks publication. Corrections are versioned and
reviewed again; old evidence must not silently certify a changed video or book.

Grade/track selects curriculum, not intelligence, gender stereotypes, family
authority or permanent identity. Learners can begin midyear and revisit any
available lesson without deleting older plans/progress. Viewing time and a
self-reported completion remain separate from demonstrated understanding.

## Pedagogy and assessment specification

The [public-source evidence review](../../research/learning-evidence-2026-10-09.md)
includes the IES2007 instruction/study practice guide, EEF2021 feedback and EEF2025
metacognition guidance, plus Khan2024 mastery workflow documentation. These informed the subsequent migration0015 assessment infrastructure in this
branch: real server grading, private attempts and explanatory feedback. The
feedback router remains separate. No real reviewed question bank or full unit
exam is published or certified by either packet.

For each publishable lesson, record learning objectives and prerequisite concepts;
review a short retrieval check after instruction, worked examples and supported
practice followed by progressively independent practice. Feedback explains the
reasoning and a useful next action, rather than only a score. Offer a later spaced
retrieval opportunity and a way to revisit a misconception. Metacognitive prompts
ask the learner to plan, explain their approach and reflect, without claiming that
confidence or watch duration proves understanding.

Question wording, correct answers, explanations and plausible distractors require
the same textbook/age review. Unit exams should sample the declared objectives
and disclose coverage gaps. A mastery threshold, automated adaptive sequence or
claim of educational effectiveness needs its own assessment design and evidence;
it is not inferred from another product's workflow. Future lesson/quiz versions
must be explicit so old attempts are not silently scored against changed answers.

Adult/family topics—parenting, couples, siblings and work—are future content
domains with separate appropriateness and review criteria. They do not create a
content-admin grant, change a child's sharing policy or turn AI into a psychologist.
Future age-appropriate assistance must not diagnose, claim complete understanding,
or automatically expose a child's abuse disclosure to parents/admins. Private chat,
notes and health data remain outside this feedback feature.

## Consent and feedback flow

A learner or parent may voluntarily choose a category and write a new summary for
the content team. This is a separate explicit action, not permission inherited
from a chat, parent role, video click or account settings. The form previews the
exact submitted summary and requires an unchecked explicit sharing choice.

Suggested Persian explanation:

> فقط همین خلاصه برای بررسی محتوای آموزشی ارسال می‌شود. گفت‌وگو، یادداشت و
> اطلاعات سلامت شما همراه آن ارسال نمی‌شود. نام، اطلاعات تماس یا شرح موضوعات
> خصوصی و آسیب را در این بازخورد ننویسید. بررسی توسط مسئول محتوا انجام می‌شود؛
> دریافت بازخورد به معنی تأیید مشکل یا وعدهٔ اصلاح نیست.

The API accepts exactly the user's chosen bounded summary; it does not read,
summarize, attach or export chat/notes/health. It does not attempt an unreliable
PII detector. Plain-text rendering and parameterized SQL protect the transport/
display boundary but do not establish that a voluntarily typed summary contains
no sensitive information.

## Implemented small backend contract

`createLearningFeedbackRouter({pool, auth})` mounts under `/v1`. Authentication
checks the current account/session. Owner identity derives only from it.

`POST /v1/education/feedback` accepts these fields and rejects unknown fields:

```json
{
  "mutationId": "UUID",
  "unitId": null,
  "category": "topic_request",
  "summary": "A new, explicitly chosen summary of up to 1000 characters",
  "shareWithContentTeam": true
}
```

`unitId` can be null or an existing public-catalogue unit UUID, including a DRAFT
unit for reviewer feedback. It does not authorize reading unpublished teaching or
any user's progress. Categories are `inaccurate`, `edition_mismatch`,
`broken_video`, `unclear`, and `topic_request`. The summary is a nonblank string,
at most1000 Unicode code points, with no NUL. Consent must be literal `true`.
Owner/child overrides, private-chat attachments and other fields are rejected.

New submissions return201; identical owner-scoped mutation retries return200 with
the same feedback ID. A canonical request hash detects changed-payload UUID reuse
and returns409. The acknowledgement names the mutation and feedback ID with
`accepted` or `already_applied`; receipt is not a promise that the report is correct.

Feedback response fields are `id`, `mutationId`, `unitId`, `category`, `summary`,
`shareWithContentTeam`, `status`, `version`, `createdAt`, `updatedAt` and
`withdrawnAt`. No account/contact, chat, note or health fields are returned.
New status is `received`. Durable per-user rolling limits are5 new submissions
per hour and20 per day;429 includes `Retry-After`. Identical retries do not consume
quota, and withdrawal/restart does not reset it. Owner-row locking makes
concurrent retries and limit checks atomic.

`GET /v1/me/education-feedback` returns only the caller's rows, newest first,
up to100 per page with an optional UUID `cursor` and `nextCursor`. No `childId`,
owner override or family-role read is available. A cursor must belong to the same
caller; missing/foreign cursor IDs use the same404 result.

`DELETE /v1/me/education-feedback/:id` withdraws only the caller's feedback and
returns204, including a repeated withdrawal. Missing/foreign IDs return404.
Withdrawal removes the stored summary and sharing consent and increments the
version once. Minimal ID/request-hash/time/category/unit tombstone remains for
idempotency and rate limits. A matching POST retry returns that redacted tombstone
and never republishes its old summary; changed payload still returns409. There is
no guarantee of retracting something a future authorized reviewer already read.

Migration0014 adds only `learning_content_feedback`, linked to `app_user` and
`learning_unit` from0013. Existing migrations/checksums remain unchanged. The shared
runtime role policy must cover this table; no new content-admin role is granted here.

## Human review and future operations

Stored review statuses are `received`, `triaged`, `planned`, `released`, `declined`;
withdrawal is separate. This packet provides no status-update/admin/other-user API,
exporter, email/SMS sender, external AI or automation trigger. Real moderation and
review-team access remain a future explicit policy. Until then, any manual database
inspection is limited to separately approved local synthetic fixtures.

The intended future owner workflow is: consented summary → manual content triage
→ approved, minimized R&D brief → developer work → tests/review → versioned PR.
Never use raw private chat as an R&D brief and never auto-publish/deploy from a
feedback row. A released status requires a human-reviewed actual change; receipt
must not be presented as an automatic improvement promise.

## Acceptance and limits

Use actual loopback HTTP and migrated synthetic PostgreSQL to verify consent and
input rejection, owner/family/outsider isolation, hash conflicts and concurrent
duplicate suppression, real restart persistence, per-user durable hourly/daily
limits, withdrawal and tombstone retries. Seed unrelated private chat-like/notes/
health records only in synthetic fixtures and prove the feedback result/logs never
contain them. Inspect SQL state independently of HTTP responses. Register the
router in the real entrypoint through the coordinating owner, not a fake auth handler.

No media review, published teaching, pedagogical effectiveness, quiz engine,
real feedback administration, real delivery or live migration is certified by
these backend tests. Each remains a separate acceptance gate.

## Actual backend verification, 2026-10-09

Migration0014 was applied only to the existing isolated local synthetic test
database after the library migration0013 and an exclusive test window were
confirmed. The unchanged migrator checked the prior ledger and applied the new
table. No live database or privilege transition ran.

Node22.23.3 input tests were first observed failing2/2, then passing2/2. The actual
production entrypoint/HTTP/PostgreSQL run first passed those2 and failed all8 new
route cases with404 before implementation. Final focused run passed10/10 with
zero failures/skips, including consent rejection, guardian/admin isolation,
independent SQL checks, concurrent retry/quota enforcement, a real API process
restart, redacted tombstone retry,20/day quota and100-row paging with preserved
microsecond cursor boundaries.

The final complete backend runner passed **145/145**, zero failures/skips, in26.13s.
An earlier144/145 run exposed a library test assertion that queried a stable unit
without its owner filter; the library owner corrected the test and the complete
suite was rerun. This was not a feedback product failure. Syntax and repository
diff checks passed. The synthetic database window was then released.

The coordinating owner registers the router and updates the shared runtime table
policy. Client feedback/withdrawal and malformed-ack behavior are independently
owned and must receive their own final acceptance; backend PASS is not a claim
that the frontend, administration, teaching or deployment is complete.
