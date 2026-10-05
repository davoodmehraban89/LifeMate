begin;

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
