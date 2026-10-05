\set ON_ERROR_STOP on
begin;

insert into app_user(id,identity_subject,email_normalized) values
('40000000-0000-0000-0000-000000000001','p4-owner','p4-owner@example.test');

insert into profile(user_id,display_name) values
('40000000-0000-0000-0000-000000000001','P4 Owner');

insert into learning_goal(id,owner_user_id,title,target) values
('41000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001','Goal','Target');

insert into learning_checkin(owner_user_id,learning_goal_id,confidence,difficulty,note) values
('40000000-0000-0000-0000-000000000001','41000000-0000-0000-0000-000000000001',4,3,'note');

insert into wellbeing_checkin(owner_user_id,mood,energy,stress,note,visibility) values
('40000000-0000-0000-0000-000000000001',4,3,2,'private note','private');

insert into ai_guide_session(id,owner_user_id,guide_kind) values
('42000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001','wellbeing');

insert into ai_guide_message(session_id,author,body,safety_class) values
('42000000-0000-0000-0000-000000000001','user','hello','ordinary');

insert into wellbeing_safety_event(owner_user_id,source_session_id,severity) values
('40000000-0000-0000-0000-000000000001','42000000-0000-0000-0000-000000000001','urgent_review');

insert into ai_plan_proposal(owner_user_id,session_id,title,proposal) values
('40000000-0000-0000-0000-000000000001','42000000-0000-0000-0000-000000000001','Plan','{"steps":[1,2]}'::jsonb);

do $$
begin
  begin
    insert into wellbeing_checkin(owner_user_id,mood,energy,stress)
    values('40000000-0000-0000-0000-000000000001',6,3,2);
    raise exception 'mood constraint failed to reject invalid value';
  exception when check_violation then null;
  end;

  begin
    insert into ai_guide_session(owner_user_id,guide_kind)
    values('40000000-0000-0000-0000-000000000001','diagnostician');
    raise exception 'guide kind constraint failed';
  exception when check_violation then null;
  end;
end $$;

rollback;
