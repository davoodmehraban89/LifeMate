begin;

create type life_context_kind as enum ('student','work','personal');
create type plan_item_kind as enum ('task','event','routine','goal','assignment','exam','study_session');
create type plan_item_status as enum ('planned','in_progress','completed','cancelled');
create type plan_priority as enum ('low','normal','high','urgent');
create type sharing_scope as enum ('private','selected_members','parent_guardian','family');
create type reminder_status as enum ('scheduled','claimed','sent','cancelled','failed');

create table life_context (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references app_user(id) on delete cascade,
  kind life_context_kind not null,
  title text not null check (char_length(title) between 1 and 120),
  active boolean not null default true,
  created_at timestamptz not null default now()
);
create index life_context_user_idx on life_context(user_id) where active;

create table academic_year (
  id uuid primary key default gen_random_uuid(),
  student_user_id uuid not null references app_user(id) on delete cascade,
  life_context_id uuid not null references life_context(id) on delete cascade,
  title text not null,
  starts_on date not null,
  ends_on date not null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  check (ends_on >= starts_on)
);
create index academic_year_student_idx on academic_year(student_user_id, starts_on desc);

create table academic_term (
  id uuid primary key default gen_random_uuid(),
  academic_year_id uuid not null references academic_year(id) on delete cascade,
  title text not null,
  starts_on date not null,
  ends_on date not null,
  created_at timestamptz not null default now(),
  check (ends_on >= starts_on)
);

create table subject (
  id uuid primary key default gen_random_uuid(),
  student_user_id uuid not null references app_user(id) on delete cascade,
  academic_term_id uuid not null references academic_term(id) on delete cascade,
  name text not null check (char_length(name) between 1 and 120),
  teacher_name text,
  color_key text,
  created_at timestamptz not null default now()
);
create index subject_student_term_idx on subject(student_user_id, academic_term_id);

create table class_session (
  id uuid primary key default gen_random_uuid(),
  subject_id uuid not null references subject(id) on delete cascade,
  weekday smallint not null check (weekday between 1 and 7),
  starts_at time not null,
  ends_at time not null,
  location text,
  recurrence_until date,
  created_at timestamptz not null default now(),
  check (ends_at > starts_at)
);
create index class_session_subject_weekday_idx on class_session(subject_id, weekday, starts_at);

create table plan_item (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references app_user(id) on delete cascade,
  family_id uuid references family_workspace(id) on delete cascade,
  subject_id uuid references subject(id) on delete set null,
  kind plan_item_kind not null,
  title text not null check (char_length(title) between 1 and 240),
  notes text,
  status plan_item_status not null default 'planned',
  priority plan_priority not null default 'normal',
  visibility sharing_scope not null default 'private',
  starts_at timestamptz,
  due_at timestamptz,
  duration_minutes integer check (duration_minutes is null or duration_minutes between 1 and 1440),
  recurrence_rule text,
  parent_item_id uuid references plan_item(id) on delete set null,
  grade_points numeric(8,2),
  grade_out_of numeric(8,2),
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (due_at is null or starts_at is null or due_at >= starts_at),
  check ((grade_points is null and grade_out_of is null) or (grade_points is not null and grade_out_of is not null and grade_out_of > 0))
);
create index plan_item_owner_time_idx on plan_item(owner_user_id, coalesce(starts_at,due_at), status);
create index plan_item_family_time_idx on plan_item(family_id, coalesce(starts_at,due_at)) where family_id is not null;
create index plan_item_subject_idx on plan_item(subject_id, kind, due_at) where subject_id is not null;

create table sharing_grant (
  resource_type text not null check (resource_type in ('plan_item')),
  resource_id uuid not null,
  grantee_user_id uuid not null references app_user(id) on delete cascade,
  granted_by uuid not null references app_user(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (resource_type, resource_id, grantee_user_id)
);
create index sharing_grant_grantee_idx on sharing_grant(grantee_user_id, resource_type, resource_id);

create table reminder (
  id uuid primary key default gen_random_uuid(),
  plan_item_id uuid not null references plan_item(id) on delete cascade,
  owner_user_id uuid not null references app_user(id) on delete cascade,
  minutes_before integer not null check (minutes_before between 0 and 10080),
  scheduled_for timestamptz not null,
  status reminder_status not null default 'scheduled',
  claimed_at timestamptz,
  delivered_at timestamptz,
  failure_reason text,
  created_at timestamptz not null default now(),
  unique(plan_item_id, owner_user_id, minutes_before)
);
create index reminder_due_idx on reminder(scheduled_for) where status='scheduled';

create table notification_preference (
  user_id uuid primary key references app_user(id) on delete cascade,
  reminders_enabled boolean not null default true,
  quiet_start time,
  quiet_end time,
  timezone text not null default 'Asia/Tehran',
  updated_at timestamptz not null default now()
);

create table notification_outbox (
  id bigint generated always as identity primary key,
  reminder_id uuid not null unique references reminder(id) on delete cascade,
  user_id uuid not null references app_user(id) on delete cascade,
  payload jsonb not null,
  available_at timestamptz not null default now(),
  delivered_at timestamptz,
  attempts integer not null default 0,
  last_error text
);
create index notification_outbox_pending_idx on notification_outbox(available_at) where delivered_at is null;

create table sync_mutation (
  id uuid primary key,
  user_id uuid not null references app_user(id) on delete cascade,
  entity_type text not null,
  entity_id uuid,
  operation text not null check (operation in ('create','update','complete','reschedule')),
  client_updated_at timestamptz not null,
  payload jsonb not null,
  accepted_at timestamptz not null default now(),
  unique(user_id,id)
);

create function can_view_student_academic(p_viewer uuid, p_student uuid) returns boolean
language sql stable as $$
  select p_viewer=p_student or exists(
    select 1
      from guardian_relationship g
      join family_membership gm
        on gm.family_id=g.family_id and gm.user_id=g.guardian_user_id and gm.ended_at is null
      join family_membership sm
        on sm.family_id=g.family_id and sm.user_id=g.minor_user_id and sm.ended_at is null
     where g.guardian_user_id=p_viewer
       and g.minor_user_id=p_student
       and g.active
  )
$$;

create function can_view_plan_item(p_viewer uuid, p_item uuid) returns boolean
language sql stable as $$
  select exists(
    select 1
      from plan_item p
     where p.id=p_item
       and (
         p.owner_user_id=p_viewer
         or exists(
           select 1 from sharing_grant sg
            where sg.resource_type='plan_item'
              and sg.resource_id=p.id
              and sg.grantee_user_id=p_viewer
         )
         or (
           p.visibility='family'
           and p.family_id is not null
           and is_active_family_member(p.family_id,p_viewer)
         )
         or (
           p.visibility='parent_guardian'
           and p.family_id is not null
           and is_active_guardian(p.family_id,p_viewer,p.owner_user_id)
         )
       )
  )
$$;

create function recompute_reminder_schedule(p_plan_item uuid) returns void
language plpgsql as $$
declare
  base_time timestamptz;
begin
  select coalesce(starts_at,due_at) into base_time from plan_item where id=p_plan_item;
  if base_time is null then
    update reminder set status='cancelled' where plan_item_id=p_plan_item and status in ('scheduled','claimed');
    return;
  end if;
  update reminder
     set scheduled_for = base_time - make_interval(mins => minutes_before),
         status = case when status in ('sent','failed') then status else 'scheduled' end,
         claimed_at = null
   where plan_item_id=p_plan_item
     and status <> 'cancelled';
end $$;

commit;
