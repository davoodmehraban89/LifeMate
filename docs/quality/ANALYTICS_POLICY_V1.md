# LifeMate — Analytics Policy v1

## Principle
Product analytics answers whether flows work; it does not become a shadow copy of private user content.

## Allowed event shape
Use stable event names plus low-sensitivity categorical/boolean metadata. Examples: `auth_signup_completed`, `family_invite_accepted`, `task_completed`, `pwa_install_prompt_shown`, `notification_permission_result`, `study_session_completed`.

## Never send to PostHog/product analytics
- passwords, tokens, recovery links;
- raw AI/wellbeing transcripts;
- journal/private free text;
- assignment/task free-text content unless an explicit future use case is separately approved;
- precise sensitive safety-event narrative;
- email/phone as event properties unless a specific operational requirement and privacy review approve it.

## Identity
Use internal pseudonymous user/profile identifiers where needed for product analysis. Family identifiers are pseudonymous. Analytics identity does not grant application authorization.

## Feature flags
AI/wellbeing and other higher-risk capabilities launch behind server-respected feature flags where appropriate. A client flag is not a security boundary.

## Retention
Analytics retention and deletion behavior must be configured before production based on actual product needs and deployment obligations; default to less data and shorter retention when uncertain.