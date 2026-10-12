begin;

-- Explicit content-operation capabilities are independent of family/profile/JWT roles.
-- No default grants and no application HTTP grant endpoint.
create table content_capability_grant (
  user_id uuid not null references app_user(id) on delete cascade,
  permission text not null check(permission in ('feedback.read','feedback.review','brief.prepare')),
  granted_at timestamptz not null default now(),
  expires_at timestamptz not null,
  revoked_at timestamptz,
  primary key(user_id,permission),
  check(expires_at>granted_at)
);

-- Operator-only privilege history contains no copied feedback or contact details.
create table content_capability_audit (
  id uuid primary key default gen_random_uuid(),
  target_user_id uuid not null references app_user(id) on delete cascade,
  permission text not null check(permission in ('feedback.read','feedback.review','brief.prepare')),
  action text not null check(action in ('grant','revoke')),
  occurred_at timestamptz not null default now(),
  expires_at timestamptz
);

create table content_review_brief (
  id uuid primary key default gen_random_uuid(),
  actor_user_id uuid not null references app_user(id) on delete cascade,
  source_count integer not null check(source_count between 1 and 20),
  created_at timestamptz not null default now()
);
create table content_review_brief_source (
  brief_id uuid not null references content_review_brief(id) on delete cascade,
  feedback_id uuid not null references learning_content_feedback(id) on delete cascade,
  feedback_version integer not null check(feedback_version>0),
  primary key(brief_id,feedback_id)
);

-- Store only references/hashes: retries always reconstruct CURRENT consenting state.
create table content_review_mutation (
  actor_user_id uuid not null references app_user(id) on delete cascade,
  mutation_id uuid not null,
  operation text not null check(operation in ('review','brief')),
  request_hash text not null check(request_hash~'^[0-9a-f]{64}$'),
  feedback_id uuid references learning_content_feedback(id) on delete cascade,
  brief_id uuid references content_review_brief(id) on delete cascade,
  accepted_at timestamptz not null default now(),
  primary key(actor_user_id,mutation_id),
  check((operation='review' and feedback_id is not null and brief_id is null)
     or (operation='brief' and feedback_id is null and brief_id is not null))
);
create table content_review_audit (
  id uuid primary key default gen_random_uuid(),
  actor_user_id uuid not null references app_user(id) on delete cascade,
  feedback_id uuid not null references learning_content_feedback(id) on delete cascade,
  before_status text not null check(before_status in ('received','triaged','planned','declined')),
  after_status text not null check(after_status in ('triaged','planned','declined')),
  before_version integer not null check(before_version>0),
  after_version integer not null check(after_version=before_version+1),
  occurred_at timestamptz not null default now()
);
create index content_review_visible_idx on learning_content_feedback(status,created_at desc,id desc)
  where withdrawn_at is null and share_with_content_team=true;
create index content_review_brief_feedback_idx on content_review_brief_source(feedback_id);

commit;
