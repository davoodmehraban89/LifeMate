begin;
set local lock_timeout='5s';
set local statement_timeout='120s';
set local search_path=lifeguide_qa,extensions,pg_catalog;
do $preflight$ begin
 if current_database()<>'postgres' or to_regnamespace('lifeguide_qa') is null
 or to_regclass('lifeguide_qa.setup_probe') is null
 or not exists(select 1 from pg_extension where extname='pgcrypto')
 or has_schema_privilege('anon','lifeguide_qa','USAGE')
 or has_schema_privilege('authenticated','lifeguide_qa','USAGE')
 then raise exception 'lifeguide_qa_preflight_denied'; end if;
end $preflight$;
create table if not exists lifeguide_qa.schema_migration (
 filename text primary key,
 sha256 text not null check (sha256 ~ '^[a-f0-9]{64}$'),
 applied_at timestamptz not null default now()
);
-- Original LifeGuide migration 0001_identity_family.sql


-- existing pgcrypto is untouched

create type member_role as enum ('parent_guardian','teen_minor','adult_member');
create type invitation_status as enum ('pending','accepted','revoked','expired');
create type visibility_scope as enum ('private','selected_members','parent_guardian','family','safety_controlled');

create table app_user (
  id uuid primary key default gen_random_uuid(),
  identity_subject text not null unique,
  email_normalized text not null unique check (email_normalized = lower(email_normalized)),
  email_verified_at timestamptz,
  created_at timestamptz not null default now(),
  disabled_at timestamptz
);

create table profile (
  user_id uuid primary key references app_user(id) on delete cascade,
  display_name text not null check (char_length(display_name) between 1 and 100),
  birth_date date,
  theme_preference text check (theme_preference in ('girl_pink','boy_blue','adult_blue','custom')),
  updated_at timestamptz not null default now()
);

create table family_workspace (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 120),
  created_by uuid not null references app_user(id),
  created_at timestamptz not null default now(),
  archived_at timestamptz
);

create table family_membership (
  family_id uuid not null references family_workspace(id) on delete cascade,
  user_id uuid not null references app_user(id) on delete cascade,
  role member_role not null,
  is_admin boolean not null default false,
  joined_at timestamptz not null default now(),
  ended_at timestamptz,
  primary key (family_id, user_id)
);

create table guardian_relationship (
  family_id uuid not null,
  guardian_user_id uuid not null,
  minor_user_id uuid not null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  primary key (family_id, guardian_user_id, minor_user_id),
  foreign key (family_id, guardian_user_id) references family_membership(family_id, user_id) on delete cascade,
  foreign key (family_id, minor_user_id) references family_membership(family_id, user_id) on delete cascade,
  check (guardian_user_id <> minor_user_id)
);

create table family_invitation (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references family_workspace(id) on delete cascade,
  invited_email_normalized text not null check (invited_email_normalized = lower(invited_email_normalized)),
  intended_role member_role not null,
  intended_theme text check (intended_theme in ('girl_pink','boy_blue','adult_blue','custom')),
  token_digest text not null unique,
  status invitation_status not null default 'pending',
  invited_by uuid not null references app_user(id),
  expires_at timestamptz not null,
  accepted_by uuid references app_user(id),
  created_at timestamptz not null default now(),
  accepted_at timestamptz,
  check (expires_at > created_at)
);

create table access_audit (
  id bigint generated always as identity primary key,
  actor_user_id uuid references app_user(id),
  family_id uuid references family_workspace(id),
  action text not null,
  target_type text not null,
  target_id text,
  occurred_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);

create index family_membership_user_idx on family_membership(user_id) where ended_at is null;
create index family_membership_admin_idx on family_membership(family_id, is_admin) where ended_at is null and is_admin;
create index family_invitation_pending_idx on family_invitation(family_id, invited_email_normalized) where status = 'pending';
create index access_audit_family_time_idx on access_audit(family_id, occurred_at desc);

create function is_active_family_member(p_family uuid, p_user uuid) returns boolean
language sql stable as $$
  select exists(
    select 1 from family_membership m
    where m.family_id=p_family and m.user_id=p_user and m.ended_at is null
  )
$$;

create function is_family_admin(p_family uuid, p_user uuid) returns boolean
language sql stable as $$
  select exists(
    select 1 from family_membership m
    where m.family_id=p_family and m.user_id=p_user and m.ended_at is null and m.is_admin
  )
$$;

create function is_active_guardian(p_family uuid, p_guardian uuid, p_minor uuid) returns boolean
language sql stable as $$
  select exists(
    select 1 from guardian_relationship g
    join family_membership gm
      on gm.family_id=g.family_id
     and gm.user_id=g.guardian_user_id
     and gm.ended_at is null
     and gm.role='parent_guardian'
    join family_membership mm
      on mm.family_id=g.family_id
     and mm.user_id=g.minor_user_id
     and mm.ended_at is null
     and mm.role='teen_minor'
    where g.family_id=p_family
      and g.guardian_user_id=p_guardian
      and g.minor_user_id=p_minor
      and g.active
  )
$$;


insert into lifeguide_qa.schema_migration(filename,sha256)
values ('0001_identity_family.sql',encode(digest(convert_to($qa_original_0001$begin;

create extension if not exists pgcrypto;

create type member_role as enum ('parent_guardian','teen_minor','adult_member');
create type invitation_status as enum ('pending','accepted','revoked','expired');
create type visibility_scope as enum ('private','selected_members','parent_guardian','family','safety_controlled');

create table app_user (
  id uuid primary key default gen_random_uuid(),
  identity_subject text not null unique,
  email_normalized text not null unique check (email_normalized = lower(email_normalized)),
  email_verified_at timestamptz,
  created_at timestamptz not null default now(),
  disabled_at timestamptz
);

create table profile (
  user_id uuid primary key references app_user(id) on delete cascade,
  display_name text not null check (char_length(display_name) between 1 and 100),
  birth_date date,
  theme_preference text check (theme_preference in ('girl_pink','boy_blue','adult_blue','custom')),
  updated_at timestamptz not null default now()
);

create table family_workspace (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 120),
  created_by uuid not null references app_user(id),
  created_at timestamptz not null default now(),
  archived_at timestamptz
);

create table family_membership (
  family_id uuid not null references family_workspace(id) on delete cascade,
  user_id uuid not null references app_user(id) on delete cascade,
  role member_role not null,
  is_admin boolean not null default false,
  joined_at timestamptz not null default now(),
  ended_at timestamptz,
  primary key (family_id, user_id)
);

create table guardian_relationship (
  family_id uuid not null,
  guardian_user_id uuid not null,
  minor_user_id uuid not null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  primary key (family_id, guardian_user_id, minor_user_id),
  foreign key (family_id, guardian_user_id) references family_membership(family_id, user_id) on delete cascade,
  foreign key (family_id, minor_user_id) references family_membership(family_id, user_id) on delete cascade,
  check (guardian_user_id <> minor_user_id)
);

create table family_invitation (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references family_workspace(id) on delete cascade,
  invited_email_normalized text not null check (invited_email_normalized = lower(invited_email_normalized)),
  intended_role member_role not null,
  intended_theme text check (intended_theme in ('girl_pink','boy_blue','adult_blue','custom')),
  token_digest text not null unique,
  status invitation_status not null default 'pending',
  invited_by uuid not null references app_user(id),
  expires_at timestamptz not null,
  accepted_by uuid references app_user(id),
  created_at timestamptz not null default now(),
  accepted_at timestamptz,
  check (expires_at > created_at)
);

create table access_audit (
  id bigint generated always as identity primary key,
  actor_user_id uuid references app_user(id),
  family_id uuid references family_workspace(id),
  action text not null,
  target_type text not null,
  target_id text,
  occurred_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);

create index family_membership_user_idx on family_membership(user_id) where ended_at is null;
create index family_membership_admin_idx on family_membership(family_id, is_admin) where ended_at is null and is_admin;
create index family_invitation_pending_idx on family_invitation(family_id, invited_email_normalized) where status = 'pending';
create index access_audit_family_time_idx on access_audit(family_id, occurred_at desc);

create function is_active_family_member(p_family uuid, p_user uuid) returns boolean
language sql stable as $$
  select exists(
    select 1 from family_membership m
    where m.family_id=p_family and m.user_id=p_user and m.ended_at is null
  )
$$;

create function is_family_admin(p_family uuid, p_user uuid) returns boolean
language sql stable as $$
  select exists(
    select 1 from family_membership m
    where m.family_id=p_family and m.user_id=p_user and m.ended_at is null and m.is_admin
  )
$$;

create function is_active_guardian(p_family uuid, p_guardian uuid, p_minor uuid) returns boolean
language sql stable as $$
  select exists(
    select 1 from guardian_relationship g
    join family_membership gm
      on gm.family_id=g.family_id
     and gm.user_id=g.guardian_user_id
     and gm.ended_at is null
     and gm.role='parent_guardian'
    join family_membership mm
      on mm.family_id=g.family_id
     and mm.user_id=g.minor_user_id
     and mm.ended_at is null
     and mm.role='teen_minor'
    where g.family_id=p_family
      and g.guardian_user_id=p_guardian
      and g.minor_user_id=p_minor
      and g.active
  )
$$;

commit;
$qa_original_0001$,'UTF8'),'sha256'),'hex'));
-- Original LifeGuide migration 0002_auth.sql


create table auth_credential (
  user_id uuid primary key references app_user(id) on delete cascade,
  password_hash text not null,
  password_changed_at timestamptz not null default now(),
  failed_attempts integer not null default 0 check (failed_attempts >= 0),
  locked_until timestamptz
);

create type auth_token_kind as enum ('email_verification','password_reset');
create table auth_token (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references app_user(id) on delete cascade,
  kind auth_token_kind not null,
  token_digest text not null unique,
  expires_at timestamptz not null,
  used_at timestamptz,
  created_at timestamptz not null default now(),
  check (expires_at > created_at)
);
create index auth_token_active_idx on auth_token(user_id, kind, expires_at) where used_at is null;

create table auth_session (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references app_user(id) on delete cascade,
  refresh_digest text not null unique,
  expires_at timestamptz not null,
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now()
);
create index auth_session_user_active_idx on auth_session(user_id, expires_at) where revoked_at is null;


insert into lifeguide_qa.schema_migration(filename,sha256)
values ('0002_auth.sql',encode(digest(convert_to($qa_original_0002$begin;

create table auth_credential (
  user_id uuid primary key references app_user(id) on delete cascade,
  password_hash text not null,
  password_changed_at timestamptz not null default now(),
  failed_attempts integer not null default 0 check (failed_attempts >= 0),
  locked_until timestamptz
);

create type auth_token_kind as enum ('email_verification','password_reset');
create table auth_token (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references app_user(id) on delete cascade,
  kind auth_token_kind not null,
  token_digest text not null unique,
  expires_at timestamptz not null,
  used_at timestamptz,
  created_at timestamptz not null default now(),
  check (expires_at > created_at)
);
create index auth_token_active_idx on auth_token(user_id, kind, expires_at) where used_at is null;

create table auth_session (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references app_user(id) on delete cascade,
  refresh_digest text not null unique,
  expires_at timestamptz not null,
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now()
);
create index auth_session_user_active_idx on auth_session(user_id, expires_at) where revoked_at is null;

commit;
$qa_original_0002$,'UTF8'),'sha256'),'hex'));
-- Original LifeGuide migration 0003_planner_school_family.sql


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


insert into lifeguide_qa.schema_migration(filename,sha256)
values ('0003_planner_school_family.sql',encode(digest(convert_to($qa_original_0003$begin;

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
$qa_original_0003$,'UTF8'),'sha256'),'hex'));
-- Original LifeGuide migration 0004_ai_learning_wellbeing.sql
create table if not exists learning_goal (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references app_user(id) on delete cascade,
  subject_id uuid references subject(id) on delete set null,
  title text not null,
  target text,
  status text not null default 'active' check (status in ('active','completed','archived')),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists learning_checkin (
  id uuid primary key default gen_random_uuid(), owner_user_id uuid not null references app_user(id) on delete cascade,
  learning_goal_id uuid references learning_goal(id) on delete set null,
  confidence smallint check(confidence between 1 and 5), difficulty smallint check(difficulty between 1 and 5), note text,
  created_at timestamptz not null default now()
);
create table if not exists wellbeing_checkin (
  id uuid primary key default gen_random_uuid(), owner_user_id uuid not null references app_user(id) on delete cascade,
  mood smallint not null check(mood between 1 and 5), energy smallint check(energy between 1 and 5), stress smallint check(stress between 1 and 5), note text,
  visibility text not null default 'private' check(visibility in ('private','guardian_summary')),
  created_at timestamptz not null default now()
);
create table if not exists ai_guide_session (
  id uuid primary key default gen_random_uuid(), owner_user_id uuid not null references app_user(id) on delete cascade,
  guide_kind text not null check(guide_kind in ('study','planner','wellbeing')),
  status text not null default 'active' check(status in ('active','closed')),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists ai_guide_message (
  id uuid primary key default gen_random_uuid(), session_id uuid not null references ai_guide_session(id) on delete cascade,
  author text not null check(author in ('user','assistant','system')), body text not null,
  safety_class text not null default 'ordinary' check(safety_class in ('ordinary','supportive','urgent_review')),
  created_at timestamptz not null default now()
);
create table if not exists ai_plan_proposal (
  id uuid primary key default gen_random_uuid(), owner_user_id uuid not null references app_user(id) on delete cascade,
  session_id uuid references ai_guide_session(id) on delete set null, title text not null, proposal jsonb not null,
  status text not null default 'proposed' check(status in ('proposed','accepted','rejected')),
  created_at timestamptz not null default now(), decided_at timestamptz
);
create index if not exists learning_goal_owner_idx on learning_goal(owner_user_id,status);
create index if not exists wellbeing_checkin_owner_idx on wellbeing_checkin(owner_user_id,created_at desc);
create index if not exists ai_guide_session_owner_idx on ai_guide_session(owner_user_id,created_at desc);

create table if not exists wellbeing_safety_event (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references app_user(id) on delete cascade,
  source_session_id uuid references ai_guide_session(id) on delete set null,
  severity text not null check(severity in ('urgent_review')),
  status text not null default 'open' check(status in ('open','acknowledged','closed')),
  created_at timestamptz not null default now(),
  acknowledged_at timestamptz
);
create index if not exists wellbeing_safety_event_owner_idx on wellbeing_safety_event(owner_user_id,created_at desc);
insert into lifeguide_qa.schema_migration(filename,sha256)
values ('0004_ai_learning_wellbeing.sql',encode(digest(convert_to($qa_original_0004$create table if not exists learning_goal (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references app_user(id) on delete cascade,
  subject_id uuid references subject(id) on delete set null,
  title text not null,
  target text,
  status text not null default 'active' check (status in ('active','completed','archived')),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists learning_checkin (
  id uuid primary key default gen_random_uuid(), owner_user_id uuid not null references app_user(id) on delete cascade,
  learning_goal_id uuid references learning_goal(id) on delete set null,
  confidence smallint check(confidence between 1 and 5), difficulty smallint check(difficulty between 1 and 5), note text,
  created_at timestamptz not null default now()
);
create table if not exists wellbeing_checkin (
  id uuid primary key default gen_random_uuid(), owner_user_id uuid not null references app_user(id) on delete cascade,
  mood smallint not null check(mood between 1 and 5), energy smallint check(energy between 1 and 5), stress smallint check(stress between 1 and 5), note text,
  visibility text not null default 'private' check(visibility in ('private','guardian_summary')),
  created_at timestamptz not null default now()
);
create table if not exists ai_guide_session (
  id uuid primary key default gen_random_uuid(), owner_user_id uuid not null references app_user(id) on delete cascade,
  guide_kind text not null check(guide_kind in ('study','planner','wellbeing')),
  status text not null default 'active' check(status in ('active','closed')),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists ai_guide_message (
  id uuid primary key default gen_random_uuid(), session_id uuid not null references ai_guide_session(id) on delete cascade,
  author text not null check(author in ('user','assistant','system')), body text not null,
  safety_class text not null default 'ordinary' check(safety_class in ('ordinary','supportive','urgent_review')),
  created_at timestamptz not null default now()
);
create table if not exists ai_plan_proposal (
  id uuid primary key default gen_random_uuid(), owner_user_id uuid not null references app_user(id) on delete cascade,
  session_id uuid references ai_guide_session(id) on delete set null, title text not null, proposal jsonb not null,
  status text not null default 'proposed' check(status in ('proposed','accepted','rejected')),
  created_at timestamptz not null default now(), decided_at timestamptz
);
create index if not exists learning_goal_owner_idx on learning_goal(owner_user_id,status);
create index if not exists wellbeing_checkin_owner_idx on wellbeing_checkin(owner_user_id,created_at desc);
create index if not exists ai_guide_session_owner_idx on ai_guide_session(owner_user_id,created_at desc);

create table if not exists wellbeing_safety_event (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references app_user(id) on delete cascade,
  source_session_id uuid references ai_guide_session(id) on delete set null,
  severity text not null check(severity in ('urgent_review')),
  status text not null default 'open' check(status in ('open','acknowledged','closed')),
  created_at timestamptz not null default now(),
  acknowledged_at timestamptz
);
create index if not exists wellbeing_safety_event_owner_idx on wellbeing_safety_event(owner_user_id,created_at desc);
$qa_original_0004$,'UTF8'),'sha256'),'hex'));
-- Original LifeGuide migration 0005_iran_family_learning.sql

alter table profile add column if not exists household_persona text check (household_persona in ('mother','father','child','adult')), add column if not exists sex text check (sex in ('female','male','unspecified'));
create table education_profile (user_id uuid primary key references app_user(id) on delete cascade,country_code char(2) not null default 'IR' check(country_code='IR'),stage text not null check(stage in('primary_1','primary_2','secondary_1','secondary_2')),national_grade smallint not null check(national_grade between 1 and 12),local_year smallint not null check(local_year between 1 and 3),school_name text,school_year text not null,updated_at timestamptz not null default now(),check((stage='primary_1' and national_grade between 1 and 3 and local_year=national_grade)or(stage='primary_2' and national_grade between 4 and 6 and local_year=national_grade-3)or(stage='secondary_1' and national_grade between 7 and 9 and local_year=national_grade-6)or(stage='secondary_2' and national_grade between 10 and 12 and local_year=national_grade-9)));
create table curriculum_subject (id uuid primary key default gen_random_uuid(),country_code char(2) not null default 'IR',school_year text not null,national_grade smallint not null check(national_grade between 1 and 12),code text not null,name_fa text not null,sort_order smallint not null default 0,unique(country_code,school_year,national_grade,code));
create table textbook_catalog (id uuid primary key default gen_random_uuid(),curriculum_subject_id uuid not null references curriculum_subject(id) on delete cascade,title_fa text not null,publisher text not null default 'سازمان پژوهش و برنامه‌ریزی آموزشی',source_host text not null default 'chap.sch.ir' check(source_host in('chap.sch.ir','medu.gov.ir')),source_url text not null check(source_url~'^https://'),redistribution_status text not null default 'link_only' check(redistribution_status in('link_only','licensed_bundle')),unique(curriculum_subject_id,title_fa));
create table iran_calendar_event (id uuid primary key default gen_random_uuid(),jalali_year smallint not null check(jalali_year between 1300 and 1600),jalali_month smallint not null check(jalali_month between 1 and 12),jalali_day smallint not null check(jalali_day between 1 and 31),title_fa text not null,is_official_holiday boolean not null default false,source_name text not null,source_url text not null check(source_url~'^https://'),unique(jalali_year,jalali_month,jalali_day,title_fa));
alter table notification_preference add column if not exists in_app_banner boolean not null default true,add column if not exists push_enabled boolean not null default false,add column if not exists planner_reminders boolean not null default true,add column if not exists school_reminders boolean not null default true,add column if not exists calendar_reminders boolean not null default true,add column if not exists cycle_reminders boolean not null default false,add column if not exists sensitive_preview boolean not null default false;
create table menstrual_cycle_entry (id uuid primary key default gen_random_uuid(),owner_user_id uuid not null references app_user(id) on delete cascade,starts_on date not null,ends_on date,predicted_next_on date,symptoms text[] not null default '{}',notes text,reminder_enabled boolean not null default false,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),check(ends_on is null or ends_on>=starts_on),check(predicted_next_on is null or predicted_next_on>starts_on));
create index menstrual_cycle_owner_date_idx on menstrual_cycle_entry(owner_user_id,starts_on desc);
insert into curriculum_subject(school_year,national_grade,code,name_fa,sort_order) values ('1405-1406',7,'fa','فارسی',10),('1405-1406',7,'writing','نگارش',20),('1405-1406',7,'math','ریاضی',30),('1405-1406',7,'science','علوم تجربی',40),('1405-1406',7,'social','مطالعات اجتماعی',50),('1405-1406',7,'arabic','عربی',60),('1405-1406',7,'quran','قرآن',70),('1405-1406',7,'religion','پیام‌های آسمان',80),('1405-1406',7,'english','انگلیسی',90),('1405-1406',7,'worktech','کار و فناوری',100),('1405-1406',7,'thinking','تفکر و سبک زندگی',110),('1405-1406',7,'pe','تربیت بدنی و سلامت',120) on conflict do nothing;
insert into textbook_catalog(curriculum_subject_id,title_fa,source_url) select id,name_fa,'https://chap.sch.ir/' from curriculum_subject where school_year='1405-1406' and national_grade=7 on conflict do nothing;
insert into iran_calendar_event(jalali_year,jalali_month,jalali_day,title_fa,is_official_holiday,source_name,source_url) values (1405,1,1,'آغاز نوروز',true,'تقویم رسمی کشور ۱۴۰۵ — مرکز تقویم مؤسسه ژئوفیزیک دانشگاه تهران','https://calendar.ut.ac.ir/'),(1405,1,2,'عید نوروز',true,'تقویم رسمی کشور ۱۴۰۵ — مرکز تقویم مؤسسه ژئوفیزیک دانشگاه تهران','https://calendar.ut.ac.ir/'),(1405,1,3,'عید نوروز',true,'تقویم رسمی کشور ۱۴۰۵ — مرکز تقویم مؤسسه ژئوفیزیک دانشگاه تهران','https://calendar.ut.ac.ir/'),(1405,1,4,'عید نوروز',true,'تقویم رسمی کشور ۱۴۰۵ — مرکز تقویم مؤسسه ژئوفیزیک دانشگاه تهران','https://calendar.ut.ac.ir/'),(1405,1,12,'روز جمهوری اسلامی ایران',true,'تقویم رسمی کشور ۱۴۰۵ — مرکز تقویم مؤسسه ژئوفیزیک دانشگاه تهران','https://calendar.ut.ac.ir/'),(1405,1,13,'روز طبیعت',true,'تقویم رسمی کشور ۱۴۰۵ — مرکز تقویم مؤسسه ژئوفیزیک دانشگاه تهران','https://calendar.ut.ac.ir/'),(1405,3,14,'رحلت امام خمینی',true,'تقویم رسمی کشور ۱۴۰۵ — مرکز تقویم مؤسسه ژئوفیزیک دانشگاه تهران','https://calendar.ut.ac.ir/'),(1405,3,15,'قیام ۱۵ خرداد',true,'تقویم رسمی کشور ۱۴۰۵ — مرکز تقویم مؤسسه ژئوفیزیک دانشگاه تهران','https://calendar.ut.ac.ir/'),(1405,11,22,'پیروزی انقلاب اسلامی ایران',true,'تقویم رسمی کشور ۱۴۰۵ — مرکز تقویم مؤسسه ژئوفیزیک دانشگاه تهران','https://calendar.ut.ac.ir/'),(1405,12,29,'روز ملی شدن صنعت نفت ایران',true,'تقویم رسمی کشور ۱۴۰۵ — مرکز تقویم مؤسسه ژئوفیزیک دانشگاه تهران','https://calendar.ut.ac.ir/') on conflict do nothing;

insert into lifeguide_qa.schema_migration(filename,sha256)
values ('0005_iran_family_learning.sql',encode(digest(convert_to($qa_original_0005$begin;
alter table profile add column if not exists household_persona text check (household_persona in ('mother','father','child','adult')), add column if not exists sex text check (sex in ('female','male','unspecified'));
create table education_profile (user_id uuid primary key references app_user(id) on delete cascade,country_code char(2) not null default 'IR' check(country_code='IR'),stage text not null check(stage in('primary_1','primary_2','secondary_1','secondary_2')),national_grade smallint not null check(national_grade between 1 and 12),local_year smallint not null check(local_year between 1 and 3),school_name text,school_year text not null,updated_at timestamptz not null default now(),check((stage='primary_1' and national_grade between 1 and 3 and local_year=national_grade)or(stage='primary_2' and national_grade between 4 and 6 and local_year=national_grade-3)or(stage='secondary_1' and national_grade between 7 and 9 and local_year=national_grade-6)or(stage='secondary_2' and national_grade between 10 and 12 and local_year=national_grade-9)));
create table curriculum_subject (id uuid primary key default gen_random_uuid(),country_code char(2) not null default 'IR',school_year text not null,national_grade smallint not null check(national_grade between 1 and 12),code text not null,name_fa text not null,sort_order smallint not null default 0,unique(country_code,school_year,national_grade,code));
create table textbook_catalog (id uuid primary key default gen_random_uuid(),curriculum_subject_id uuid not null references curriculum_subject(id) on delete cascade,title_fa text not null,publisher text not null default 'سازمان پژوهش و برنامه‌ریزی آموزشی',source_host text not null default 'chap.sch.ir' check(source_host in('chap.sch.ir','medu.gov.ir')),source_url text not null check(source_url~'^https://'),redistribution_status text not null default 'link_only' check(redistribution_status in('link_only','licensed_bundle')),unique(curriculum_subject_id,title_fa));
create table iran_calendar_event (id uuid primary key default gen_random_uuid(),jalali_year smallint not null check(jalali_year between 1300 and 1600),jalali_month smallint not null check(jalali_month between 1 and 12),jalali_day smallint not null check(jalali_day between 1 and 31),title_fa text not null,is_official_holiday boolean not null default false,source_name text not null,source_url text not null check(source_url~'^https://'),unique(jalali_year,jalali_month,jalali_day,title_fa));
alter table notification_preference add column if not exists in_app_banner boolean not null default true,add column if not exists push_enabled boolean not null default false,add column if not exists planner_reminders boolean not null default true,add column if not exists school_reminders boolean not null default true,add column if not exists calendar_reminders boolean not null default true,add column if not exists cycle_reminders boolean not null default false,add column if not exists sensitive_preview boolean not null default false;
create table menstrual_cycle_entry (id uuid primary key default gen_random_uuid(),owner_user_id uuid not null references app_user(id) on delete cascade,starts_on date not null,ends_on date,predicted_next_on date,symptoms text[] not null default '{}',notes text,reminder_enabled boolean not null default false,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),check(ends_on is null or ends_on>=starts_on),check(predicted_next_on is null or predicted_next_on>starts_on));
create index menstrual_cycle_owner_date_idx on menstrual_cycle_entry(owner_user_id,starts_on desc);
insert into curriculum_subject(school_year,national_grade,code,name_fa,sort_order) values ('1405-1406',7,'fa','فارسی',10),('1405-1406',7,'writing','نگارش',20),('1405-1406',7,'math','ریاضی',30),('1405-1406',7,'science','علوم تجربی',40),('1405-1406',7,'social','مطالعات اجتماعی',50),('1405-1406',7,'arabic','عربی',60),('1405-1406',7,'quran','قرآن',70),('1405-1406',7,'religion','پیام‌های آسمان',80),('1405-1406',7,'english','انگلیسی',90),('1405-1406',7,'worktech','کار و فناوری',100),('1405-1406',7,'thinking','تفکر و سبک زندگی',110),('1405-1406',7,'pe','تربیت بدنی و سلامت',120) on conflict do nothing;
insert into textbook_catalog(curriculum_subject_id,title_fa,source_url) select id,name_fa,'https://chap.sch.ir/' from curriculum_subject where school_year='1405-1406' and national_grade=7 on conflict do nothing;
insert into iran_calendar_event(jalali_year,jalali_month,jalali_day,title_fa,is_official_holiday,source_name,source_url) values (1405,1,1,'آغاز نوروز',true,'تقویم رسمی کشور ۱۴۰۵ — مرکز تقویم مؤسسه ژئوفیزیک دانشگاه تهران','https://calendar.ut.ac.ir/'),(1405,1,2,'عید نوروز',true,'تقویم رسمی کشور ۱۴۰۵ — مرکز تقویم مؤسسه ژئوفیزیک دانشگاه تهران','https://calendar.ut.ac.ir/'),(1405,1,3,'عید نوروز',true,'تقویم رسمی کشور ۱۴۰۵ — مرکز تقویم مؤسسه ژئوفیزیک دانشگاه تهران','https://calendar.ut.ac.ir/'),(1405,1,4,'عید نوروز',true,'تقویم رسمی کشور ۱۴۰۵ — مرکز تقویم مؤسسه ژئوفیزیک دانشگاه تهران','https://calendar.ut.ac.ir/'),(1405,1,12,'روز جمهوری اسلامی ایران',true,'تقویم رسمی کشور ۱۴۰۵ — مرکز تقویم مؤسسه ژئوفیزیک دانشگاه تهران','https://calendar.ut.ac.ir/'),(1405,1,13,'روز طبیعت',true,'تقویم رسمی کشور ۱۴۰۵ — مرکز تقویم مؤسسه ژئوفیزیک دانشگاه تهران','https://calendar.ut.ac.ir/'),(1405,3,14,'رحلت امام خمینی',true,'تقویم رسمی کشور ۱۴۰۵ — مرکز تقویم مؤسسه ژئوفیزیک دانشگاه تهران','https://calendar.ut.ac.ir/'),(1405,3,15,'قیام ۱۵ خرداد',true,'تقویم رسمی کشور ۱۴۰۵ — مرکز تقویم مؤسسه ژئوفیزیک دانشگاه تهران','https://calendar.ut.ac.ir/'),(1405,11,22,'پیروزی انقلاب اسلامی ایران',true,'تقویم رسمی کشور ۱۴۰۵ — مرکز تقویم مؤسسه ژئوفیزیک دانشگاه تهران','https://calendar.ut.ac.ir/'),(1405,12,29,'روز ملی شدن صنعت نفت ایران',true,'تقویم رسمی کشور ۱۴۰۵ — مرکز تقویم مؤسسه ژئوفیزیک دانشگاه تهران','https://calendar.ut.ac.ir/') on conflict do nothing;
commit;$qa_original_0005$,'UTF8'),'sha256'),'hex'));
-- Original LifeGuide migration 0006_iran_calendar_1405_holidays.sql

insert into iran_calendar_event(jalali_year,jalali_month,jalali_day,title_fa,is_official_holiday,source_name,source_url) values
(1405,1,1,'عید سعید فطر و آغاز نوروز',true,'تقویم رسمی کشور ۱۴۰۵','https://calendar.ut.ac.ir/'),
(1405,1,2,'تعطیل عید سعید فطر و عید نوروز',true,'تقویم رسمی کشور ۱۴۰۵','https://calendar.ut.ac.ir/'),
(1405,1,25,'شهادت امام جعفر صادق (ع)',true,'تقویم رسمی کشور ۱۴۰۵','https://calendar.ut.ac.ir/'),
(1405,3,6,'عید سعید قربان',true,'تقویم رسمی کشور ۱۴۰۵','https://calendar.ut.ac.ir/'),
(1405,3,14,'عید سعید غدیر خم و رحلت امام خمینی',true,'تقویم رسمی کشور ۱۴۰۵','https://calendar.ut.ac.ir/'),
(1405,4,3,'تاسوعای حسینی',true,'تقویم رسمی کشور ۱۴۰۵','https://calendar.ut.ac.ir/'),
(1405,4,4,'عاشورای حسینی',true,'تقویم رسمی کشور ۱۴۰۵','https://calendar.ut.ac.ir/'),
(1405,5,13,'اربعین حسینی',true,'تقویم رسمی کشور ۱۴۰۵','https://calendar.ut.ac.ir/'),
(1405,5,21,'رحلت حضرت رسول اکرم (ص) و شهادت امام حسن مجتبی (ع)',true,'تقویم رسمی کشور ۱۴۰۵','https://calendar.ut.ac.ir/'),
(1405,5,22,'شهادت امام رضا (ع)',true,'تقویم رسمی کشور ۱۴۰۵','https://calendar.ut.ac.ir/'),
(1405,5,30,'شهادت امام حسن عسکری (ع)',true,'تقویم رسمی کشور ۱۴۰۵','https://calendar.ut.ac.ir/'),
(1405,6,8,'ولادت حضرت رسول اکرم (ص) و امام جعفر صادق (ع)',true,'تقویم رسمی کشور ۱۴۰۵','https://calendar.ut.ac.ir/'),
(1405,8,22,'شهادت حضرت فاطمه زهرا (س)',true,'تقویم رسمی کشور ۱۴۰۵','https://calendar.ut.ac.ir/'),
(1405,10,2,'ولادت امام علی (ع) و روز پدر',true,'تقویم رسمی کشور ۱۴۰۵','https://calendar.ut.ac.ir/'),
(1405,10,16,'مبعث حضرت رسول اکرم (ص)',true,'تقویم رسمی کشور ۱۴۰۵','https://calendar.ut.ac.ir/'),
(1405,11,4,'ولادت حضرت قائم (عج) و نیمه شعبان',true,'تقویم رسمی کشور ۱۴۰۵','https://calendar.ut.ac.ir/'),
(1405,12,9,'شهادت حضرت علی (ع)',true,'تقویم رسمی کشور ۱۴۰۵','https://calendar.ut.ac.ir/'),
(1405,12,19,'عید سعید فطر',true,'تقویم رسمی کشور ۱۴۰۵','https://calendar.ut.ac.ir/'),
(1405,12,20,'تعطیل به مناسبت عید سعید فطر',true,'تقویم رسمی کشور ۱۴۰۵','https://calendar.ut.ac.ir/')
on conflict do nothing;

insert into lifeguide_qa.schema_migration(filename,sha256)
values ('0006_iran_calendar_1405_holidays.sql',encode(digest(convert_to($qa_original_0006$begin;
insert into iran_calendar_event(jalali_year,jalali_month,jalali_day,title_fa,is_official_holiday,source_name,source_url) values
(1405,1,1,'عید سعید فطر و آغاز نوروز',true,'تقویم رسمی کشور ۱۴۰۵','https://calendar.ut.ac.ir/'),
(1405,1,2,'تعطیل عید سعید فطر و عید نوروز',true,'تقویم رسمی کشور ۱۴۰۵','https://calendar.ut.ac.ir/'),
(1405,1,25,'شهادت امام جعفر صادق (ع)',true,'تقویم رسمی کشور ۱۴۰۵','https://calendar.ut.ac.ir/'),
(1405,3,6,'عید سعید قربان',true,'تقویم رسمی کشور ۱۴۰۵','https://calendar.ut.ac.ir/'),
(1405,3,14,'عید سعید غدیر خم و رحلت امام خمینی',true,'تقویم رسمی کشور ۱۴۰۵','https://calendar.ut.ac.ir/'),
(1405,4,3,'تاسوعای حسینی',true,'تقویم رسمی کشور ۱۴۰۵','https://calendar.ut.ac.ir/'),
(1405,4,4,'عاشورای حسینی',true,'تقویم رسمی کشور ۱۴۰۵','https://calendar.ut.ac.ir/'),
(1405,5,13,'اربعین حسینی',true,'تقویم رسمی کشور ۱۴۰۵','https://calendar.ut.ac.ir/'),
(1405,5,21,'رحلت حضرت رسول اکرم (ص) و شهادت امام حسن مجتبی (ع)',true,'تقویم رسمی کشور ۱۴۰۵','https://calendar.ut.ac.ir/'),
(1405,5,22,'شهادت امام رضا (ع)',true,'تقویم رسمی کشور ۱۴۰۵','https://calendar.ut.ac.ir/'),
(1405,5,30,'شهادت امام حسن عسکری (ع)',true,'تقویم رسمی کشور ۱۴۰۵','https://calendar.ut.ac.ir/'),
(1405,6,8,'ولادت حضرت رسول اکرم (ص) و امام جعفر صادق (ع)',true,'تقویم رسمی کشور ۱۴۰۵','https://calendar.ut.ac.ir/'),
(1405,8,22,'شهادت حضرت فاطمه زهرا (س)',true,'تقویم رسمی کشور ۱۴۰۵','https://calendar.ut.ac.ir/'),
(1405,10,2,'ولادت امام علی (ع) و روز پدر',true,'تقویم رسمی کشور ۱۴۰۵','https://calendar.ut.ac.ir/'),
(1405,10,16,'مبعث حضرت رسول اکرم (ص)',true,'تقویم رسمی کشور ۱۴۰۵','https://calendar.ut.ac.ir/'),
(1405,11,4,'ولادت حضرت قائم (عج) و نیمه شعبان',true,'تقویم رسمی کشور ۱۴۰۵','https://calendar.ut.ac.ir/'),
(1405,12,9,'شهادت حضرت علی (ع)',true,'تقویم رسمی کشور ۱۴۰۵','https://calendar.ut.ac.ir/'),
(1405,12,19,'عید سعید فطر',true,'تقویم رسمی کشور ۱۴۰۵','https://calendar.ut.ac.ir/'),
(1405,12,20,'تعطیل به مناسبت عید سعید فطر',true,'تقویم رسمی کشور ۱۴۰۵','https://calendar.ut.ac.ir/')
on conflict do nothing;
commit;
$qa_original_0006$,'UTF8'),'sha256'),'hex'));
-- Original LifeGuide migration 0007_auth_contacts.sql


alter table app_user alter column email_normalized drop not null;
alter table app_user add column phone_normalized text unique;
alter table app_user add column phone_verified_at timestamptz;
alter table app_user add constraint app_user_phone_format
  check (phone_normalized is null or phone_normalized ~ '^\+[1-9][0-9]{7,14}$');
alter table app_user add constraint app_user_contact_required
  check (email_normalized is not null or phone_normalized is not null);

alter table family_invitation alter column invited_email_normalized drop not null;
alter table family_invitation add column invited_phone_normalized text;
alter table family_invitation add constraint family_invitation_contact_required
  check (num_nonnulls(invited_email_normalized,invited_phone_normalized)=1);
alter table family_invitation add constraint family_invitation_phone_format
  check (invited_phone_normalized is null or invited_phone_normalized ~ '^\+[1-9][0-9]{7,14}$');

create table auth_delivery_attempt (
  id uuid primary key default gen_random_uuid(),
  recipient_digest text not null check (recipient_digest ~ '^[a-f0-9]{64}$'),
  purpose text not null check (purpose in ('email_verification','password_reset','phone_otp')),
  user_id uuid references app_user(id) on delete set null,
  status text not null default 'pending'
    check (status in ('pending','accepted','failed','unconfigured','not_needed')),
  requested_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index auth_delivery_recipient_window_idx
  on auth_delivery_attempt(recipient_digest,purpose,requested_at desc);

create table auth_phone_challenge (
  id uuid primary key,
  user_id uuid references app_user(id) on delete cascade,
  purpose text not null check (purpose in ('verify','login','recovery')),
  code_digest text not null check (code_digest ~ '^[a-f0-9]{64}$'),
  attempts smallint not null default 0 check (attempts between 0 and 5),
  expires_at timestamptz not null,
  used_at timestamptz,
  created_at timestamptz not null default now(),
  check (expires_at > created_at)
);
create index auth_phone_challenge_owner_idx on auth_phone_challenge(user_id,created_at desc);


insert into lifeguide_qa.schema_migration(filename,sha256)
values ('0007_auth_contacts.sql',encode(digest(convert_to($qa_original_0007$begin;

alter table app_user alter column email_normalized drop not null;
alter table app_user add column phone_normalized text unique;
alter table app_user add column phone_verified_at timestamptz;
alter table app_user add constraint app_user_phone_format
  check (phone_normalized is null or phone_normalized ~ '^\+[1-9][0-9]{7,14}$');
alter table app_user add constraint app_user_contact_required
  check (email_normalized is not null or phone_normalized is not null);

alter table family_invitation alter column invited_email_normalized drop not null;
alter table family_invitation add column invited_phone_normalized text;
alter table family_invitation add constraint family_invitation_contact_required
  check (num_nonnulls(invited_email_normalized,invited_phone_normalized)=1);
alter table family_invitation add constraint family_invitation_phone_format
  check (invited_phone_normalized is null or invited_phone_normalized ~ '^\+[1-9][0-9]{7,14}$');

create table auth_delivery_attempt (
  id uuid primary key default gen_random_uuid(),
  recipient_digest text not null check (recipient_digest ~ '^[a-f0-9]{64}$'),
  purpose text not null check (purpose in ('email_verification','password_reset','phone_otp')),
  user_id uuid references app_user(id) on delete set null,
  status text not null default 'pending'
    check (status in ('pending','accepted','failed','unconfigured','not_needed')),
  requested_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index auth_delivery_recipient_window_idx
  on auth_delivery_attempt(recipient_digest,purpose,requested_at desc);

create table auth_phone_challenge (
  id uuid primary key,
  user_id uuid references app_user(id) on delete cascade,
  purpose text not null check (purpose in ('verify','login','recovery')),
  code_digest text not null check (code_digest ~ '^[a-f0-9]{64}$'),
  attempts smallint not null default 0 check (attempts between 0 and 5),
  expires_at timestamptz not null,
  used_at timestamptz,
  created_at timestamptz not null default now(),
  check (expires_at > created_at)
);
create index auth_phone_challenge_owner_idx on auth_phone_challenge(user_id,created_at desc);

commit;
$qa_original_0007$,'UTF8'),'sha256'),'hex'));
-- Original LifeGuide migration 0008_study_sessions.sql


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


insert into lifeguide_qa.schema_migration(filename,sha256)
values ('0008_study_sessions.sql',encode(digest(convert_to($qa_original_0008$begin;

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
$qa_original_0008$,'UTF8'),'sha256'),'hex'));
-- Original LifeGuide migration 0009_authorization_privacy.sql


create or replace function can_view_student_academic(p_viewer uuid, p_student uuid) returns boolean
language sql stable as $$
  select p_viewer=p_student or exists(
    select 1 from guardian_relationship g
     where g.guardian_user_id=p_viewer
       and g.minor_user_id=p_student
       and is_active_guardian(g.family_id,p_viewer,p_student)
  )
$$;

create or replace function can_view_plan_item(p_viewer uuid, p_item uuid) returns boolean
language sql stable as $$
  select exists(
    select 1 from plan_item p
     where p.id=p_item
       and (
         p.owner_user_id=p_viewer
         or (
           p.family_id is not null
           and is_active_family_member(p.family_id,p.owner_user_id)
           and is_active_family_member(p.family_id,p_viewer)
           and (
             p.visibility='family'
             or (
               p.visibility='parent_guardian'
               and is_active_guardian(p.family_id,p_viewer,p.owner_user_id)
             )
             or (
               p.visibility='selected_members'
               and exists(
                 select 1 from sharing_grant sg
                  where sg.resource_type='plan_item'
                    and sg.resource_id=p.id
                    and sg.grantee_user_id=p_viewer
                    and sg.granted_by=p.owner_user_id
               )
             )
           )
         )
       )
  )
$$;

-- Remove grants that are already invalid; later rejoining must not restore them.
delete from sharing_grant sg
 where sg.resource_type='plan_item'
   and not exists(
     select 1 from plan_item p
      where p.id=sg.resource_id
        and p.visibility='selected_members'
        and p.family_id is not null
        and sg.granted_by=p.owner_user_id
        and is_active_family_member(p.family_id,p.owner_user_id)
        and is_active_family_member(p.family_id,sg.grantee_user_id)
   );

create function revoke_changed_plan_item_grants() returns trigger
language plpgsql as $$
begin
  if new.visibility <> 'selected_members'
     or new.family_id is distinct from old.family_id
     or new.owner_user_id is distinct from old.owner_user_id then
    delete from sharing_grant where resource_type='plan_item' and resource_id=new.id;
  end if;
  return new;
end
$$;

create trigger plan_item_revoke_changed_grants
after update of visibility,family_id,owner_user_id on plan_item
for each row execute function revoke_changed_plan_item_grants();

create function revoke_ended_membership_grants() returns trigger
language plpgsql as $$
begin
  if tg_op='DELETE' or new.ended_at is not null then
    delete from sharing_grant sg
     using plan_item p
     where sg.resource_type='plan_item'
       and sg.resource_id=p.id
       and p.family_id=old.family_id
       and (p.owner_user_id=old.user_id or sg.grantee_user_id=old.user_id);
  end if;
  return null;
end
$$;

create trigger family_membership_revoke_ended_grants
after update of ended_at or delete on family_membership
for each row execute function revoke_ended_membership_grants();


insert into lifeguide_qa.schema_migration(filename,sha256)
values ('0009_authorization_privacy.sql',encode(digest(convert_to($qa_original_0009$begin;

create or replace function can_view_student_academic(p_viewer uuid, p_student uuid) returns boolean
language sql stable as $$
  select p_viewer=p_student or exists(
    select 1 from guardian_relationship g
     where g.guardian_user_id=p_viewer
       and g.minor_user_id=p_student
       and is_active_guardian(g.family_id,p_viewer,p_student)
  )
$$;

create or replace function can_view_plan_item(p_viewer uuid, p_item uuid) returns boolean
language sql stable as $$
  select exists(
    select 1 from plan_item p
     where p.id=p_item
       and (
         p.owner_user_id=p_viewer
         or (
           p.family_id is not null
           and is_active_family_member(p.family_id,p.owner_user_id)
           and is_active_family_member(p.family_id,p_viewer)
           and (
             p.visibility='family'
             or (
               p.visibility='parent_guardian'
               and is_active_guardian(p.family_id,p_viewer,p.owner_user_id)
             )
             or (
               p.visibility='selected_members'
               and exists(
                 select 1 from sharing_grant sg
                  where sg.resource_type='plan_item'
                    and sg.resource_id=p.id
                    and sg.grantee_user_id=p_viewer
                    and sg.granted_by=p.owner_user_id
               )
             )
           )
         )
       )
  )
$$;

-- Remove grants that are already invalid; later rejoining must not restore them.
delete from sharing_grant sg
 where sg.resource_type='plan_item'
   and not exists(
     select 1 from plan_item p
      where p.id=sg.resource_id
        and p.visibility='selected_members'
        and p.family_id is not null
        and sg.granted_by=p.owner_user_id
        and is_active_family_member(p.family_id,p.owner_user_id)
        and is_active_family_member(p.family_id,sg.grantee_user_id)
   );

create function revoke_changed_plan_item_grants() returns trigger
language plpgsql as $$
begin
  if new.visibility <> 'selected_members'
     or new.family_id is distinct from old.family_id
     or new.owner_user_id is distinct from old.owner_user_id then
    delete from sharing_grant where resource_type='plan_item' and resource_id=new.id;
  end if;
  return new;
end
$$;

create trigger plan_item_revoke_changed_grants
after update of visibility,family_id,owner_user_id on plan_item
for each row execute function revoke_changed_plan_item_grants();

create function revoke_ended_membership_grants() returns trigger
language plpgsql as $$
begin
  if tg_op='DELETE' or new.ended_at is not null then
    delete from sharing_grant sg
     using plan_item p
     where sg.resource_type='plan_item'
       and sg.resource_id=p.id
       and p.family_id=old.family_id
       and (p.owner_user_id=old.user_id or sg.grantee_user_id=old.user_id);
  end if;
  return null;
end
$$;

create trigger family_membership_revoke_ended_grants
after update of ended_at or delete on family_membership
for each row execute function revoke_ended_membership_grants();

commit;
$qa_original_0009$,'UTF8'),'sha256'),'hex'));
-- Original LifeGuide migration 0010_planner_sync.sql


alter table plan_item add column if not exists version bigint not null default 0;
alter table plan_item alter column version set default 1;
alter table plan_item add column planned_duration_seconds integer
  check(planned_duration_seconds is null or planned_duration_seconds between 0 and 86400);
update plan_item set planned_duration_seconds=duration_minutes*60 where duration_minutes is not null;

alter table sync_mutation drop constraint sync_mutation_pkey;
alter table sync_mutation add primary key(user_id,id);
alter table sync_mutation drop constraint sync_mutation_operation_check;
alter table sync_mutation add constraint sync_mutation_operation_check
  check(operation in ('create','update','complete','reschedule','archive'));
alter table sync_mutation add column request_hash text;
alter table sync_mutation add column canonical_item jsonb;

create or replace function is_active_family_member(p_family uuid,p_user uuid) returns boolean
language sql stable as $$
  select exists(select 1 from family_membership m join family_workspace f on f.id=m.family_id
    where m.family_id=p_family and m.user_id=p_user and m.ended_at is null and f.archived_at is null)
$$;
create or replace function is_active_guardian(p_family uuid,p_guardian uuid,p_minor uuid) returns boolean
language sql stable as $$
  select exists(select 1 from guardian_relationship g
    join family_workspace f on f.id=g.family_id and f.archived_at is null
    join family_membership gm on gm.family_id=g.family_id and gm.user_id=g.guardian_user_id
      and gm.ended_at is null and gm.role='parent_guardian'
    join family_membership mm on mm.family_id=g.family_id and mm.user_id=g.minor_user_id
      and mm.ended_at is null and mm.role='teen_minor'
    where g.family_id=p_family and g.guardian_user_id=p_guardian and g.minor_user_id=p_minor and g.active)
$$;
create or replace function is_family_admin(p_family uuid,p_user uuid) returns boolean
language sql stable as $$
  select exists(select 1 from family_membership m join family_workspace f on f.id=m.family_id
    where m.family_id=p_family and m.user_id=p_user and m.ended_at is null and m.is_admin and f.archived_at is null)
$$;

-- Legacy planner PATCH/sync writes still record explicit self-reported activity
-- transitions. Dedicated study/activity writes already advance activity_version.
create function plan_item_legacy_activity() returns trigger language plpgsql as $$
begin
  if new.status is distinct from old.status and new.activity_version=old.activity_version
     and new.status<>'cancelled' then
    new.activity_version := old.activity_version+1;
    insert into activity_state_event(plan_item_id,actor_user_id,state,source,occurred_at,version)
    values(new.id,new.owner_user_id,
      case new.status when 'completed' then 'completed' when 'in_progress' then 'started' else 'planned' end,
      'self_reported',coalesce(new.completed_at,new.updated_at),new.activity_version);
  end if;
  return new;
end $$;
create trigger plan_item_legacy_activity before update on plan_item
for each row execute function plan_item_legacy_activity();


insert into lifeguide_qa.schema_migration(filename,sha256)
values ('0010_planner_sync.sql',encode(digest(convert_to($qa_original_0010$begin;

alter table plan_item add column if not exists version bigint not null default 0;
alter table plan_item alter column version set default 1;
alter table plan_item add column planned_duration_seconds integer
  check(planned_duration_seconds is null or planned_duration_seconds between 0 and 86400);
update plan_item set planned_duration_seconds=duration_minutes*60 where duration_minutes is not null;

alter table sync_mutation drop constraint sync_mutation_pkey;
alter table sync_mutation add primary key(user_id,id);
alter table sync_mutation drop constraint sync_mutation_operation_check;
alter table sync_mutation add constraint sync_mutation_operation_check
  check(operation in ('create','update','complete','reschedule','archive'));
alter table sync_mutation add column request_hash text;
alter table sync_mutation add column canonical_item jsonb;

create or replace function is_active_family_member(p_family uuid,p_user uuid) returns boolean
language sql stable as $$
  select exists(select 1 from family_membership m join family_workspace f on f.id=m.family_id
    where m.family_id=p_family and m.user_id=p_user and m.ended_at is null and f.archived_at is null)
$$;
create or replace function is_active_guardian(p_family uuid,p_guardian uuid,p_minor uuid) returns boolean
language sql stable as $$
  select exists(select 1 from guardian_relationship g
    join family_workspace f on f.id=g.family_id and f.archived_at is null
    join family_membership gm on gm.family_id=g.family_id and gm.user_id=g.guardian_user_id
      and gm.ended_at is null and gm.role='parent_guardian'
    join family_membership mm on mm.family_id=g.family_id and mm.user_id=g.minor_user_id
      and mm.ended_at is null and mm.role='teen_minor'
    where g.family_id=p_family and g.guardian_user_id=p_guardian and g.minor_user_id=p_minor and g.active)
$$;
create or replace function is_family_admin(p_family uuid,p_user uuid) returns boolean
language sql stable as $$
  select exists(select 1 from family_membership m join family_workspace f on f.id=m.family_id
    where m.family_id=p_family and m.user_id=p_user and m.ended_at is null and m.is_admin and f.archived_at is null)
$$;

-- Legacy planner PATCH/sync writes still record explicit self-reported activity
-- transitions. Dedicated study/activity writes already advance activity_version.
create function plan_item_legacy_activity() returns trigger language plpgsql as $$
begin
  if new.status is distinct from old.status and new.activity_version=old.activity_version
     and new.status<>'cancelled' then
    new.activity_version := old.activity_version+1;
    insert into activity_state_event(plan_item_id,actor_user_id,state,source,occurred_at,version)
    values(new.id,new.owner_user_id,
      case new.status when 'completed' then 'completed' when 'in_progress' then 'started' else 'planned' end,
      'self_reported',coalesce(new.completed_at,new.updated_at),new.activity_version);
  end if;
  return new;
end $$;
create trigger plan_item_legacy_activity before update on plan_item
for each row execute function plan_item_legacy_activity();

commit;
$qa_original_0010$,'UTF8'),'sha256'),'hex'));
revoke all on schema lifeguide_qa from public,anon,authenticated,service_role;
revoke all on all tables in schema lifeguide_qa from public,anon,authenticated,service_role;
revoke all on all sequences in schema lifeguide_qa from public,anon,authenticated,service_role;
revoke all on all functions in schema lifeguide_qa from public,anon,authenticated,service_role;
do $lockdown$ declare rowrecord record; begin
 for rowrecord in select c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace
 where n.nspname='lifeguide_qa' and c.relkind in ('r','p') loop
 execute format('alter table %I.%I enable row level security','lifeguide_qa',rowrecord.relname);
 execute format('alter table %I.%I force row level security','lifeguide_qa',rowrecord.relname);
 end loop;
end $lockdown$;
commit;