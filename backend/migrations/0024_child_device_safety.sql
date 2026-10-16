begin;

-- Synthetic-only child identity foundation. Runtime gate is mandatory and never
-- permits production. This migration does not approve legal consent or data hosting.
alter table app_user add column is_managed_child boolean not null default false;
alter table app_user drop constraint app_user_contact_required;
alter table app_user add constraint app_user_contact_required
  check (email_normalized is not null or phone_normalized is not null or is_managed_child);
alter table app_user add constraint managed_child_has_no_contact
  check (not is_managed_child or (email_normalized is null and phone_normalized is null));

alter table auth_session add column access_scope text not null default 'standard'
  check (access_scope in ('standard','child_education'));
alter table auth_session add column child_issuer_user_id uuid references app_user(id);

create table managed_child (
  user_id uuid primary key references app_user(id) on delete cascade,
  family_id uuid not null references family_workspace(id) on delete cascade,
  creator_user_id uuid not null references app_user(id),
  created_at timestamptz not null default clock_timestamp(),
  unique (family_id,user_id),
  check (user_id<>creator_user_id)
);

create table child_consent (
  child_user_id uuid primary key references managed_child(user_id) on delete cascade,
  actor_user_id uuid not null references app_user(id),
  text_version text not null check (text_version='sandbox-child-consent-v1-not-legal'),
  text_digest text not null check (text_digest ~ '^[a-f0-9]{64}$'),
  accepted_at timestamptz not null default clock_timestamp(),
  revoked_at timestamptz
);

create table child_device_invitation (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null,
  child_user_id uuid not null,
  issuer_user_id uuid not null references app_user(id),
  token_digest text not null unique check (token_digest ~ '^[a-f0-9]{64}$'),
  created_at timestamptz not null default clock_timestamp(),
  expires_at timestamptz not null,
  used_at timestamptz,
  revoked_at timestamptz,
  foreign key (family_id,child_user_id) references managed_child(family_id,user_id) on delete cascade
);
create index child_device_invitation_child_idx on child_device_invitation(child_user_id)
  where used_at is null and revoked_at is null;

create table guardian_invitation (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null,
  child_user_id uuid not null,
  issuer_user_id uuid not null references app_user(id),
  guardian_user_id uuid not null references app_user(id),
  token_digest text not null unique check (token_digest ~ '^[a-f0-9]{64}$'),
  created_at timestamptz not null default clock_timestamp(),
  expires_at timestamptz not null,
  used_at timestamptz,
  revoked_at timestamptz,
  foreign key (family_id,child_user_id) references managed_child(family_id,user_id) on delete cascade,
  check (guardian_user_id<>issuer_user_id and guardian_user_id<>child_user_id)
);
create index guardian_invitation_child_idx on guardian_invitation(child_user_id)
  where used_at is null and revoked_at is null;

revoke all on managed_child,child_consent,child_device_invitation,guardian_invitation from public;
commit;
