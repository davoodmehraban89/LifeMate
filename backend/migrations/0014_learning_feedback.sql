begin;

-- A consented, explicitly chosen summary, never a copy of private chat/notes.
-- Withdrawal redacts the summary while preserving retry and rate-limit receipts.
create table learning_content_feedback (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references app_user(id) on delete cascade,
  mutation_id uuid not null,
  request_hash text not null check(request_hash ~ '^[0-9a-f]{64}$'),
  unit_id uuid references learning_unit(id),
  category text not null check(category in
    ('inaccurate','edition_mismatch','broken_video','unclear','topic_request')),
  summary text,
  share_with_content_team boolean not null,
  consented_at timestamptz not null default now(),
  status text not null default 'received'
    check(status in ('received','triaged','planned','released','declined')),
  version integer not null default 1 check(version > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  withdrawn_at timestamptz,
  unique(owner_user_id,mutation_id),
  check (
    (withdrawn_at is null and share_with_content_team=true and summary is not null
      and char_length(summary) between 1 and 1000 and length(trim(summary))>0)
    or
    (withdrawn_at is not null and share_with_content_team=false and summary is null)
  )
);

create index learning_feedback_owner_time_idx
  on learning_content_feedback(owner_user_id,created_at desc,id desc);

commit;
