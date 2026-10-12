begin;

alter table life_context add column version integer not null default 1 check(version>0);
alter table life_context add column updated_at timestamptz not null default now();
alter table academic_year add column version integer not null default 1 check(version>0);
alter table academic_year add column updated_at timestamptz not null default now();
alter table academic_term add column active boolean not null default true;
alter table academic_term add column version integer not null default 1 check(version>0);
alter table academic_term add column updated_at timestamptz not null default now();

create table school_lifecycle_mutation (
  owner_user_id uuid not null references app_user(id) on delete cascade,
  mutation_id uuid not null,
  entity_type text not null check(entity_type in('contexts','years','terms')),
  entity_id uuid not null,
  operation text not null check(operation in('create','update','archive')),
  request_hash text not null check(char_length(request_hash)=64),
  applied_version integer not null check(applied_version>0),
  accepted_at timestamptz not null default now(),
  primary key(owner_user_id,mutation_id)
);

-- The same owner-row lock is used by the new router and these guards. It
-- serializes ancestor archival/date edits against the old create APIs too.
create function school_lifecycle_context_guard() returns trigger language plpgsql set search_path=public,pg_catalog as $$
begin
  perform 1 from app_user where id=new.user_id for update;
  if tg_op='UPDATE' then
    if new.user_id<>old.user_id then raise exception 'school_owner_immutable' using errcode='23514'; end if;
    if new.kind<>old.kind and exists(select 1 from academic_year where life_context_id=old.id) then
      raise exception 'school_context_kind_in_use' using errcode='23514';
    end if;
    new.version=old.version+1; new.updated_at=clock_timestamp();
  end if;
  return new;
end $$;
create trigger school_lifecycle_context_guard before insert or update on life_context for each row execute function school_lifecycle_context_guard();

create function school_lifecycle_year_guard() returns trigger language plpgsql set search_path=public,pg_catalog as $$
declare context_row life_context;
begin
  perform 1 from app_user where id=new.student_user_id for update;
  if tg_op='UPDATE' and (new.student_user_id<>old.student_user_id or new.life_context_id<>old.life_context_id) then
    raise exception 'school_parent_immutable' using errcode='23514';
  end if;
  select * into context_row from life_context where id=new.life_context_id for share;
  if context_row.id is null or context_row.user_id<>new.student_user_id or context_row.kind<>'student' then
    raise exception 'school_parent_forbidden' using errcode='23514';
  end if;
  if new.active and not context_row.active then raise exception 'school_parent_inactive' using errcode='23514'; end if;
  if char_length(trim(new.title)) not between 1 and 120 then raise exception 'school_invalid_title' using errcode='23514'; end if;
  if tg_op='UPDATE' then
    if exists(select 1 from academic_term where academic_year_id=old.id and (starts_on<new.starts_on or ends_on>new.ends_on)) then
      raise exception 'school_dates_in_use' using errcode='23514';
    end if;
    new.version=old.version+1; new.updated_at=clock_timestamp();
  end if;
  return new;
end $$;
create trigger school_lifecycle_year_guard before insert or update on academic_year for each row execute function school_lifecycle_year_guard();

create function school_lifecycle_term_guard() returns trigger language plpgsql set search_path=public,pg_catalog as $$
declare year_row academic_year; context_row life_context;
begin
  select * into year_row from academic_year where id=new.academic_year_id;
  perform 1 from app_user where id=year_row.student_user_id for update;
  select * into year_row from academic_year where id=new.academic_year_id for share;
  select * into context_row from life_context where id=year_row.life_context_id for share;
  if tg_op='UPDATE' and new.academic_year_id<>old.academic_year_id then raise exception 'school_parent_immutable' using errcode='23514'; end if;
  if year_row.id is null or context_row.id is null or context_row.user_id<>year_row.student_user_id or context_row.kind<>'student' then
    raise exception 'school_parent_forbidden' using errcode='23514';
  end if;
  if new.active and (not year_row.active or not context_row.active) then raise exception 'school_parent_inactive' using errcode='23514'; end if;
  if new.starts_on<year_row.starts_on or new.ends_on>year_row.ends_on then raise exception 'school_dates_outside_parent' using errcode='23514'; end if;
  if char_length(trim(new.title)) not between 1 and 120 then raise exception 'school_invalid_title' using errcode='23514'; end if;
  if tg_op='UPDATE' then
    if exists(select 1 from class_session c join subject s on s.id=c.subject_id where s.academic_term_id=old.id and c.recurrence_until is not null and (c.recurrence_until<new.starts_on or c.recurrence_until>new.ends_on)) then
      raise exception 'school_dates_in_use' using errcode='23514';
    end if;
    new.version=old.version+1; new.updated_at=clock_timestamp();
  end if;
  return new;
end $$;
create trigger school_lifecycle_term_guard before insert or update on academic_term for each row execute function school_lifecycle_term_guard();

create function school_lifecycle_subject_guard() returns trigger language plpgsql set search_path=public,pg_catalog as $$
declare parent_row record;
begin
  perform 1 from app_user where id=new.student_user_id for update;
  if tg_op='UPDATE' and new.student_user_id<>old.student_user_id then raise exception 'school_owner_immutable' using errcode='23514'; end if;
  select t.active as term_active,y.active as year_active,l.active as context_active,y.student_user_id,l.user_id,l.kind
    into parent_row from academic_term t join academic_year y on y.id=t.academic_year_id join life_context l on l.id=y.life_context_id where t.id=new.academic_term_id for share of t,y,l;
  if not found or parent_row.student_user_id<>new.student_user_id or parent_row.user_id<>new.student_user_id then
    raise exception 'school_parent_forbidden' using errcode='23514';
  end if;
  if new.archived_at is null and (not parent_row.term_active or not parent_row.year_active or not parent_row.context_active or parent_row.kind<>'student') then
    raise exception 'school_parent_inactive' using errcode='23514';
  end if;
  return new;
end $$;
create trigger school_lifecycle_subject_guard before insert or update on subject for each row execute function school_lifecycle_subject_guard();

create function school_lifecycle_class_guard() returns trigger language plpgsql set search_path=public,pg_catalog as $$
declare parent_row record; owner_id uuid;
begin
  select student_user_id into owner_id from subject where id=new.subject_id;
  perform 1 from app_user where id=owner_id for update;
  select s.archived_at,t.active as term_active,y.active as year_active,l.active as context_active,t.starts_on,t.ends_on
    into parent_row from subject s join academic_term t on t.id=s.academic_term_id join academic_year y on y.id=t.academic_year_id join life_context l on l.id=y.life_context_id where s.id=new.subject_id for share of s,t,y,l;
  if not found then raise exception 'school_parent_forbidden' using errcode='23514'; end if;
  if new.archived_at is null then
    if parent_row.archived_at is not null or not parent_row.term_active or not parent_row.year_active or not parent_row.context_active then
      raise exception 'school_parent_inactive' using errcode='23514';
    end if;
    if new.recurrence_until is not null and (new.recurrence_until<parent_row.starts_on or new.recurrence_until>parent_row.ends_on) then
      raise exception 'school_dates_outside_parent' using errcode='23514';
    end if;
  end if;
  return new;
end $$;
create trigger school_lifecycle_class_guard before insert or update on class_session for each row execute function school_lifecycle_class_guard();

commit;
