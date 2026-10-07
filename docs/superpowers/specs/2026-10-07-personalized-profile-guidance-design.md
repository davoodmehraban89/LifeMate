# Life Guide Personalized Profile & Guidance Design

**Date:** 2026-10-07

## Goal
Replace the temporary role-entry model with a durable profile model that distinguishes **فرزند دختر**, **فرزند پسر**, and **بزرگسال**, while keeping the user's editable display name independent from profile type. This profile becomes the basis for relevant calendar/health capabilities and context-aware guidance without encoding behavioral stereotypes.

## Current-state findings
- The role-entry test build currently offers `فرزند / دانش‌آموز`, `مادر`, and `پدر`.
- `LocalRoleTestApi` stores the entry label in a final field, so `updateProfile()` returns an edited name but subsequent `getProfile()` still returns the original label. This explains why a child continues to appear as «فرزند».
- The existing PostgreSQL profile already stores `display_name`, `birth_date`, and a theme preference with girl/boy/adult variants, but it has no explicit profile category/sex-context field.
- Existing family membership roles (`parent_guardian`, `teen_minor`, `adult_member`) describe authorization/family responsibility and must not be overloaded to represent girl/boy.
- Existing wellbeing and AI-guidance flows already separate private notes from guardian summaries; this privacy boundary must be preserved.

## Product model
### Profile category
The first-run test experience offers exactly:
1. **فرزند دختر**
2. **فرزند پسر**
3. **بزرگسال**

The profile category is separate from family authorization role. Both child categories map to the minor/student shell; adult maps to the adult shell. Parent/guardian status is assigned inside family management, not on the first screen.

### Display name
After selecting a profile category, the user can set a display name. It is editable later from the profile area. A name such as «آرام» must persist across navigation and app restart and must replace generic labels such as «فرزند» wherever the personal name is intended.

### Personalization
Profile category is a capability/context signal, not a personality template.
- Girl/boy may select appropriate default visual theme.
- Biological/reproductive-health features are opt-in and shown only when relevant to the user's profile and choices.
- Menstrual-cycle tracking is never inferred merely from appearance or conversation. It is explicitly enabled by the user, stores sensitive health data separately, and can be disabled.
- Psychology, family guidance, and educational guidance may use age, user-stated preferences, goals, current state, and relevant profile context, but must not assume fixed temperament, interests, abilities, or communication style from sex/category alone.

## Health calendar
Introduce an optional health-calendar capability, initially focused on menstrual-cycle tracking for users for whom it is relevant.
- Explicit opt-in before collecting cycle data.
- Store cycle dates/settings separately from ordinary planner events.
- Default visibility is private.
- No raw cycle data is exposed to guardians by default.
- Guidance must be educational/supportive and must not diagnose disease or replace professional care.
- The ordinary calendar may display private health markers only for the profile owner when enabled.

## Guidance
The guidance context supplied to AI/advisory services may include only the minimum necessary profile context: age band, profile category when relevant, user communication preferences, current goal/context, and explicitly enabled health context. Sensitive health context is excluded unless the feature and the current interaction require it.

## Data architecture
Add an explicit profile category field rather than deriving it from theme:
- `profile_category`: `girl_minor | boy_minor | adult`
- Keep `member_role` unchanged for family authorization.
- Keep `theme_preference` independent so users can customize appearance.

Health-cycle data gets dedicated tables/records with owner-only access semantics and auditability rather than being embedded in generic planner notes.

## Test-build persistence
The security-bypassed APK remains a test-only entrypoint. Its selected category, display name, and opt-in settings must use local persistent storage so closing/reopening the APK does not reset the profile. Production API-backed behavior remains separate and is not weakened.

## UX
First run:
`انتخاب نوع پروفایل → وارد کردن/تأیید نام → HomeShell`.

Profile area:
- display name
- profile category
- date of birth/age information where supplied
- theme
- relevant optional health features
- family role/status shown separately

Changing profile category later requires confirmation because it changes feature availability, but must not delete data silently.

## Safety and privacy
- Treat reproductive-health and wellbeing content as sensitive.
- Minimize collection and sharing.
- Child private notes/conversations remain private except already-defined safety-controlled behavior.
- No diagnostic claims.
- No gender-based psychological stereotyping.
- Family permissions remain enforced by membership/guardian relationships, never by profile category.

## Acceptance criteria
1. Fresh test APK shows exactly «فرزند دختر»، «فرزند پسر»، «بزرگسال».
2. User can set «آرام» as display name and sees it after navigation and app restart.
3. Girl and boy child profiles both use student navigation; adult uses adult navigation.
4. Family authorization remains independent of profile category.
5. Theme defaults differ appropriately but are user-changeable.
6. Menstrual tracking is opt-in, private by default, and not shown for unrelated profiles unless profile settings are intentionally changed.
7. Guidance receives only relevant/minimized context and does not hard-code psychological stereotypes.
8. Existing wellbeing privacy behavior remains intact.
9. Automated tests cover entry choices, name persistence, shell routing, profile editing, sensitive-feature gating, and privacy boundaries.
10. Release APK is built only after Flutter/backend tests pass.
