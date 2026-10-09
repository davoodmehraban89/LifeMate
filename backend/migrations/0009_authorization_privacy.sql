begin;

create or replace function can_view_student_academic(p_viewer uuid, p_student uuid) returns boolean
language sql stable as $$
  select p_viewer=p_student or exists(
    select 1 from guardian_relationship g
     where g.guardian_user_id=p_viewer
       and g.minor_user_id=p_student
       and is_active_guardian(g.family_id,p_viewer,p_student)
  )
$$;

create or replace function can_view_plan_item(p_viewer uuid, p_item uuid) returns boolean
language sql stable as $$
  select exists(
    select 1 from plan_item p
     where p.id=p_item
       and (
         p.owner_user_id=p_viewer
         or (
           p.family_id is not null
           and is_active_family_member(p.family_id,p.owner_user_id)
           and is_active_family_member(p.family_id,p_viewer)
           and (
             p.visibility='family'
             or (
               p.visibility='parent_guardian'
               and is_active_guardian(p.family_id,p_viewer,p.owner_user_id)
             )
             or (
               p.visibility='selected_members'
               and exists(
                 select 1 from sharing_grant sg
                  where sg.resource_type='plan_item'
                    and sg.resource_id=p.id
                    and sg.grantee_user_id=p_viewer
                    and sg.granted_by=p.owner_user_id
               )
             )
           )
         )
       )
  )
$$;

-- Remove grants that are already invalid; later rejoining must not restore them.
delete from sharing_grant sg
 where sg.resource_type='plan_item'
   and not exists(
     select 1 from plan_item p
      where p.id=sg.resource_id
        and p.visibility='selected_members'
        and p.family_id is not null
        and sg.granted_by=p.owner_user_id
        and is_active_family_member(p.family_id,p.owner_user_id)
        and is_active_family_member(p.family_id,sg.grantee_user_id)
   );

create function revoke_changed_plan_item_grants() returns trigger
language plpgsql as $$
begin
  if new.visibility <> 'selected_members'
     or new.family_id is distinct from old.family_id
     or new.owner_user_id is distinct from old.owner_user_id then
    delete from sharing_grant where resource_type='plan_item' and resource_id=new.id;
  end if;
  return new;
end
$$;

create trigger plan_item_revoke_changed_grants
after update of visibility,family_id,owner_user_id on plan_item
for each row execute function revoke_changed_plan_item_grants();

create function revoke_ended_membership_grants() returns trigger
language plpgsql as $$
begin
  if tg_op='DELETE' or new.ended_at is not null then
    delete from sharing_grant sg
     using plan_item p
     where sg.resource_type='plan_item'
       and sg.resource_id=p.id
       and p.family_id=old.family_id
       and (p.owner_user_id=old.user_id or sg.grantee_user_id=old.user_id);
  end if;
  return null;
end
$$;

create trigger family_membership_revoke_ended_grants
after update of ended_at or delete on family_membership
for each row execute function revoke_ended_membership_grants();

commit;
