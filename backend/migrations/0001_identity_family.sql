begin;

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
