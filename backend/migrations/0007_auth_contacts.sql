begin;

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
