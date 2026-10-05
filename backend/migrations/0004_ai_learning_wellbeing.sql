create table if not exists learning_goal (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references app_user(id) on delete cascade,
  subject_id uuid references academic_subject(id) on delete set null,
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
