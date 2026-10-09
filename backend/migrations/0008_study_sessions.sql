begin;

-- Reuse the existing planner; its legacy status remains compatible.
alter table plan_item add column activity_version bigint not null default 0;
alter table plan_item add column if not exists version bigint not null default 0;
alter table plan_item add constraint plan_item_id_owner_unique unique(id,owner_user_id);

create function plan_item_revision() returns trigger language plpgsql as $$
begin
  new.version := old.version+1;
  return new;
end $$;
create trigger plan_item_revision before update on plan_item
for each row execute function plan_item_revision();

create table study_session (
  id uuid primary key,
  child_user_id uuid not null references app_user(id) on delete cascade,
  plan_item_id uuid not null,
  source text not null check(source in ('timer','self_reported')),
  status text not null check(status in ('running','paused','completed','archived')),
  started_at timestamptz not null,
  ended_at timestamptz,
  last_event_at timestamptz not null,
  recorded_duration_seconds integer not null default 0 check(recorded_duration_seconds>=0),
  version integer not null default 1 check(version>0),
  last_sync_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  archived_at timestamptz,
  foreign key(plan_item_id,child_user_id) references plan_item(id,owner_user_id) on delete cascade,
  check(ended_at is null or ended_at>=started_at),
  check(last_event_at>=started_at)
);
create index study_session_owner_idx on study_session(child_user_id,started_at desc);
create index study_session_plan_idx on study_session(plan_item_id) where archived_at is null;

create table study_interval (
  id bigint generated always as identity primary key,
  session_id uuid not null references study_session(id) on delete cascade,
  starts_at timestamptz not null,
  ends_at timestamptz,
  check(ends_at is null or ends_at>=starts_at)
);
create index study_interval_session_idx on study_interval(session_id,starts_at);
create unique index study_interval_one_running_idx on study_interval(session_id) where ends_at is null;

create table activity_state_event (
  id bigint generated always as identity primary key,
  plan_item_id uuid not null references plan_item(id) on delete cascade,
  actor_user_id uuid not null references app_user(id),
  state text not null check(state in ('planned','started','paused','completed','verified')),
  source text not null check(source in ('client_timer','self_reported','guardian_confirmation')),
  occurred_at timestamptz not null,
  accepted_at timestamptz not null default now(),
  version bigint not null check(version>0),
  confirmation text,
  unique(plan_item_id,version),
  check((state='verified' and source='guardian_confirmation' and char_length(confirmation) between 1 and 1000)
        or (state<>'verified' and source<>'guardian_confirmation' and confirmation is null))
);
create index activity_state_latest_idx on activity_state_event(plan_item_id,version desc);

-- A separate ledger avoids changing existing planner/offline sync protocol.
create table study_mutation (
  user_id uuid not null references app_user(id) on delete cascade,
  id uuid not null,
  request_hash text not null,
  response_body jsonb not null,
  response_status integer not null,
  accepted_at timestamptz not null default now(),
  primary key(user_id,id)
);

commit;
