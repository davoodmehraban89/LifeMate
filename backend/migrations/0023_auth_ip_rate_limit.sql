begin;

-- Abuse-prevention metadata only: no IP, contact, account, or request body.
-- The digest is a domain-separated HMAC using the server signing secret.
create table auth_ip_rate_limit (
  quota_profile text not null check(quota_profile in ('auth','session')),
  client_digest text not null check(client_digest ~ '^[a-f0-9]{64}$'),
  window_start timestamptz not null,
  window_end timestamptz not null,
  request_count bigint not null check(request_count > 0),
  primary key(quota_profile,client_digest,window_start),
  check(window_end > window_start)
);
create index auth_ip_rate_limit_expiry on auth_ip_rate_limit(window_end);
revoke all on auth_ip_rate_limit from public;

commit;
