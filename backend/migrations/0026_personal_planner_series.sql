begin;

create table planner_series (
  id uuid primary key,
  owner_user_id uuid not null references app_user(id) on delete cascade,
  title text not null check (char_length(title) between 1 and 240),
  kind plan_item_kind not null check (kind in ('task','event','routine')),
  timezone text not null check (char_length(timezone) between 1 and 100),
  starts_on date not null,
  until_on date,
  frequency text not null check (frequency in ('daily','weekly')),
  interval_days smallint not null check (interval_days in (1,2)),
  slots jsonb not null check (jsonb_typeof(slots)='array'),
  reminder_minutes integer[] not null default '{}',
  request_hash text not null check (request_hash ~ '^[a-f0-9]{64}$'),
  materialized_through date,
  version bigint not null default 1,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(id,owner_user_id),
  check (until_on is null or until_on>=starts_on),
  check (frequency<>'weekly' or interval_days=1)
);
create index planner_series_owner_idx on planner_series(owner_user_id,created_at) where archived_at is null;

alter table plan_item add column ends_at timestamptz;
alter table plan_item add constraint plan_item_end_order check (ends_at is null or (starts_at is not null and ends_at>starts_at));
alter table plan_item add column series_id uuid;
alter table plan_item add column original_occurrence_date date;
alter table plan_item add constraint plan_item_series_owner_fk foreign key(series_id,owner_user_id)
  references planner_series(id,owner_user_id) on delete cascade;
alter table plan_item add constraint plan_item_series_date_pair check ((series_id is null)=(original_occurrence_date is null));
alter table plan_item add constraint plan_item_series_private check (series_id is null or (visibility='private' and family_id is null));
alter table plan_item add constraint plan_item_series_occurrence_unique unique(series_id,original_occurrence_date);

revoke all on planner_series from public;
commit;
