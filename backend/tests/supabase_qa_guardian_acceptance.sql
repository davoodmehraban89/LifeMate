-- Synthetic-only DB acceptance. Execute ONLY against isolated Supabase project
-- LifeGuide-QA / iqkrwxeprxvdiubdfcrb. Never run against Finora or any real user DB.
-- All writes and relationship changes are intentionally ROLLED BACK.
begin;
set local search_path=lifeguide_qa,extensions,pg_catalog;
do $qa_guardian_test$
declare
 parent_a uuid := gen_random_uuid();
 parent_b uuid := gen_random_uuid();
 child_a uuid := gen_random_uuid();
 outsider uuid := gen_random_uuid();
 fam uuid := gen_random_uuid();
 shared_task uuid := gen_random_uuid();
 private_task uuid := gen_random_uuid();
 study_id uuid := gen_random_uuid();
 seconds int;
begin
 insert into lifeguide_qa.app_user(id,identity_subject,email_normalized) values
 (parent_a,'qa:mother:'||parent_a::text,'mother-'||parent_a::text||'@example.invalid'),
 (parent_b,'qa:father:'||parent_b::text,'father-'||parent_b::text||'@example.invalid'),
 (child_a,'qa:child:'||child_a::text,'child-'||child_a::text||'@example.invalid'),
 (outsider,'qa:outsider:'||outsider::text,'outsider-'||outsider::text||'@example.invalid');
 insert into lifeguide_qa.family_workspace(id,name,created_by)
 values (fam,'Synthetic LifeGuide QA Family',parent_a);
 insert into lifeguide_qa.family_membership(family_id,user_id,role,is_admin) values
 (fam,parent_a,'parent_guardian',true),
 (fam,parent_b,'parent_guardian',false),
 (fam,child_a,'teen_minor',false);
 insert into lifeguide_qa.guardian_relationship(family_id,guardian_user_id,minor_user_id)
 values (fam,parent_a,child_a),(fam,parent_b,child_a);
 if not lifeguide_qa.is_active_guardian(fam,parent_a,child_a)
    or not lifeguide_qa.is_active_guardian(fam,parent_b,child_a)
    or lifeguide_qa.is_active_guardian(fam,outsider,child_a)
    or not lifeguide_qa.can_view_student_academic(parent_a,child_a)
    or lifeguide_qa.can_view_student_academic(outsider,child_a)
 then raise exception 'qa_guardian_visibility_failed'; end if;
 insert into lifeguide_qa.plan_item(id,owner_user_id,family_id,kind,title,visibility)
 values (shared_task,child_a,fam,'assignment','Synthetic math task','parent_guardian'),
        (private_task,child_a,fam,'task','Synthetic private task','private');
 if not lifeguide_qa.can_view_plan_item(parent_a,shared_task)
    or not lifeguide_qa.can_view_plan_item(parent_b,shared_task)
    or lifeguide_qa.can_view_plan_item(outsider,shared_task)
    or lifeguide_qa.can_view_plan_item(parent_a,private_task)
    or not lifeguide_qa.can_view_plan_item(child_a,private_task)
 then raise exception 'qa_plan_privacy_failed'; end if;
 insert into lifeguide_qa.study_session(
   id,child_user_id,plan_item_id,source,status,started_at,ended_at,last_event_at,recorded_duration_seconds)
 values (study_id,child_a,shared_task,'timer','completed',
         now()-interval '4 seconds',now(),now(),4);
 select recorded_duration_seconds into seconds
 from lifeguide_qa.study_session where id=study_id;
 if seconds<>4 then raise exception 'qa_study_seconds_failed'; end if;
 update lifeguide_qa.guardian_relationship set active=false
 where family_id=fam and guardian_user_id=parent_b and minor_user_id=child_a;
 if lifeguide_qa.is_active_guardian(fam,parent_b,child_a)
    or lifeguide_qa.can_view_plan_item(parent_b,shared_task)
    or not lifeguide_qa.can_view_plan_item(parent_a,shared_task)
 then raise exception 'qa_guardian_revocation_failed'; end if;
end $qa_guardian_test$;
rollback;
