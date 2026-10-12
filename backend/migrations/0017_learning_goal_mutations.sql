alter table learning_goal add column version integer not null default 1 check(version > 0);
alter table learning_goal add column archived_at timestamptz;
update learning_goal set archived_at=updated_at where status='archived';
alter table learning_goal add constraint learning_goal_archive_state check((status='archived')=(archived_at is not null));
alter table learning_goal add constraint learning_goal_id_owner_unique unique(id,owner_user_id);

create table learning_goal_mutation (
  owner_user_id uuid not null references app_user(id) on delete cascade,
  mutation_id uuid not null,
  goal_id uuid not null,
  operation text not null check(operation in ('create','update','archive')),
  request_hash text not null check(request_hash ~ '^[a-f0-9]{64}$'),
  applied_version integer not null check(applied_version > 0),
  accepted_at timestamptz not null default now(),
  primary key(owner_user_id,mutation_id),
  foreign key(goal_id,owner_user_id) references learning_goal(id,owner_user_id) on delete cascade
);
create index learning_goal_mutation_goal_idx on learning_goal_mutation(owner_user_id,goal_id);
