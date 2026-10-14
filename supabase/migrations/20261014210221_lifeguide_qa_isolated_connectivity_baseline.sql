begin;
create schema if not exists lifeguide_qa;
revoke all on schema lifeguide_qa from public, anon, authenticated;
create table if not exists lifeguide_qa.setup_probe (
  id uuid primary key default gen_random_uuid(),
  probe_name text not null unique check (probe_name ~ '^synthetic_[a-z0-9_]{1,40}$'),
  created_at timestamptz not null default now()
);
alter table lifeguide_qa.setup_probe enable row level security;
alter table lifeguide_qa.setup_probe force row level security;
revoke all on lifeguide_qa.setup_probe from public, anon, authenticated;
comment on schema lifeguide_qa is 'Isolated LifeGuide QA preparation only. Never store real child data here.';
comment on table lifeguide_qa.setup_probe is 'Synthetic-only connectivity receipt; not a LifeGuide application table.';
commit;
