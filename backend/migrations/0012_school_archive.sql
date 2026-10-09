begin;

alter table subject add column archived_at timestamptz;
alter table subject add column updated_at timestamptz;
update subject set updated_at=created_at;
alter table subject alter column updated_at set default now();
alter table subject alter column updated_at set not null;
create index subject_active_owner_idx on subject(student_user_id,created_at desc) where archived_at is null;

alter table class_session add column archived_at timestamptz;
alter table class_session add column updated_at timestamptz;
update class_session set updated_at=created_at;
alter table class_session alter column updated_at set default now();
alter table class_session alter column updated_at set not null;
create index class_session_active_subject_idx on class_session(subject_id,weekday,starts_at) where archived_at is null;

alter table learning_checkin add column archived_at timestamptz;
alter table learning_checkin add column updated_at timestamptz;
alter table learning_checkin add column occurred_at timestamptz;
update learning_checkin set updated_at=created_at,occurred_at=created_at;
alter table learning_checkin alter column updated_at set default now();
alter table learning_checkin alter column updated_at set not null;
alter table learning_checkin alter column occurred_at set default now();
alter table learning_checkin alter column occurred_at set not null;
alter table learning_checkin add column source text not null default 'self_reported' check(source='self_reported');
create index learning_checkin_active_owner_idx on learning_checkin(owner_user_id,occurred_at desc) where archived_at is null;

commit;
