begin;

-- Preserve legacy role/membership checks. Only the new sandbox model requires
-- versioned consent and a creator-authorized, accepted second-guardian invite.
create or replace function is_active_guardian(p_family uuid, p_guardian uuid, p_minor uuid) returns boolean
language sql stable as $$
  select exists(
    select 1 from guardian_relationship g
    join family_workspace f on f.id=g.family_id and f.archived_at is null
    join family_membership gm on gm.family_id=g.family_id and gm.user_id=g.guardian_user_id
      and gm.ended_at is null and gm.role='parent_guardian'
    join family_membership mm on mm.family_id=g.family_id and mm.user_id=g.minor_user_id
      and mm.ended_at is null and mm.role='teen_minor'
    join app_user gu on gu.id=gm.user_id and gu.disabled_at is null
    join app_user cu on cu.id=mm.user_id and cu.disabled_at is null
    where g.family_id=p_family and g.guardian_user_id=p_guardian
      and g.minor_user_id=p_minor and g.active
      and (not cu.is_managed_child or exists(
        select 1 from managed_child mc
        join child_consent cc on cc.child_user_id=mc.user_id and cc.revoked_at is null
          and cc.actor_user_id=mc.creator_user_id
          and cc.text_version='sandbox-child-consent-v1-not-legal'
          and cc.text_digest='5dbf640a23b538800c82791620c3a43947b7346d7eff179e6f7d5afe5a55b387'
        join profile gp on gp.user_id=g.guardian_user_id
          and gp.birth_date<=(current_date-interval '18 years')::date
        join profile cp on cp.user_id=mc.user_id
          and cp.birth_date<=current_date and cp.birth_date>(current_date-interval '18 years')::date
        where mc.user_id=g.minor_user_id and mc.family_id=g.family_id and not mm.is_admin
          and (g.guardian_user_id=mc.creator_user_id or exists(
            select 1 from guardian_invitation gi where gi.family_id=mc.family_id
              and gi.child_user_id=mc.user_id and gi.issuer_user_id=mc.creator_user_id
              and gi.guardian_user_id=g.guardian_user_id and gi.used_at is not null and gi.revoked_at is null
          ))
      ))
  )
$$;
commit;
