begin;

alter table plan_item add column if not exists version bigint not null default 0;
alter table plan_item alter column version set default 1;
alter table plan_item add column planned_duration_seconds integer
  check(planned_duration_seconds is null or planned_duration_seconds between 0 and 86400);
update plan_item set planned_duration_seconds=duration_minutes*60 where duration_minutes is not null;

alter table sync_mutation drop constraint sync_mutation_pkey;
alter table sync_mutation add primary key(user_id,id);
alter table sync_mutation drop constraint sync_mutation_operation_check;
alter table sync_mutation add constraint sync_mutation_operation_check
  check(operation in ('create','update','complete','reschedule','archive'));
alter table sync_mutation add column request_hash text;
alter table sync_mutation add column canonical_item jsonb;

create or replace function is_active_family_member(p_family uuid,p_user uuid) returns boolean
language sql stable as $$
  select exists(select 1 from family_membership m join family_workspace f on f.id=m.family_id
    where m.family_id=p_family and m.user_id=p_user and m.ended_at is null and f.archived_at is null)
$$;
create or replace function is_active_guardian(p_family uuid,p_guardian uuid,p_minor uuid) returns boolean
language sql stable as $$
  select exists(select 1 from guardian_relationship g
    join family_workspace f on f.id=g.family_id and f.archived_at is null
    join family_membership gm on gm.family_id=g.family_id and gm.user_id=g.guardian_user_id
      and gm.ended_at is null and gm.role='parent_guardian'
    join family_membership mm on mm.family_id=g.family_id and mm.user_id=g.minor_user_id
      and mm.ended_at is null and mm.role='teen_minor'
    where g.family_id=p_family and g.guardian_user_id=p_guardian and g.minor_user_id=p_minor and g.active)
$$;
create or replace function is_family_admin(p_family uuid,p_user uuid) returns boolean
language sql stable as $$
  select exists(select 1 from family_membership m join family_workspace f on f.id=m.family_id
    where m.family_id=p_family and m.user_id=p_user and m.ended_at is null and m.is_admin and f.archived_at is null)
$$;

-- Legacy planner PATCH/sync writes still record explicit self-reported activity
-- transitions. Dedicated study/activity writes already advance activity_version.
create function plan_item_legacy_activity() returns trigger language plpgsql as $$
begin
  if new.status is distinct from old.status and new.activity_version=old.activity_version
     and new.status<>'cancelled' then
    new.activity_version := old.activity_version+1;
    insert into activity_state_event(plan_item_id,actor_user_id,state,source,occurred_at,version)
    values(new.id,new.owner_user_id,
      case new.status when 'completed' then 'completed' when 'in_progress' then 'started' else 'planned' end,
      'self_reported',coalesce(new.completed_at,new.updated_at),new.activity_version);
  end if;
  return new;
end $$;
create trigger plan_item_legacy_activity before update on plan_item
for each row execute function plan_item_legacy_activity();

commit;
