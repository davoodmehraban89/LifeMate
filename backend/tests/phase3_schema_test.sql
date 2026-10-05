\set ON_ERROR_STOP on
begin;

insert into app_user(id,identity_subject,email_normalized) values
('30000000-0000-0000-0000-000000000001','p3-parent','p3-parent@example.test'),
('30000000-0000-0000-0000-000000000002','p3-teen','p3-teen@example.test'),
('30000000-0000-0000-0000-000000000003','p3-other','p3-other@example.test');

insert into family_workspace(id,name,created_by) values
('31000000-0000-0000-0000-000000000001','P3 Family','30000000-0000-0000-0000-000000000001');

insert into family_membership(family_id,user_id,role,is_admin) values
('31000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','parent_guardian',true),
('31000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000002','teen_minor',false);

insert into guardian_relationship(family_id,guardian_user_id,minor_user_id) values
('31000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000002');

insert into plan_item(id,owner_user_id,family_id,kind,title,visibility,due_at) values
('32000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000002','31000000-0000-0000-0000-000000000001','task','Private teen','private',now()+interval '1 day'),
('32000000-0000-0000-0000-000000000002','30000000-0000-0000-0000-000000000002','31000000-0000-0000-0000-000000000001','assignment','Guardian item','parent_guardian',now()+interval '1 day'),
('32000000-0000-0000-0000-000000000003','30000000-0000-0000-0000-000000000001','31000000-0000-0000-0000-000000000001','event','Family event','family',now()+interval '1 day');

do $$
begin
  if not can_view_plan_item('30000000-0000-0000-0000-000000000002','32000000-0000-0000-0000-000000000001') then raise exception 'owner must see private item'; end if;
  if can_view_plan_item('30000000-0000-0000-0000-000000000001','32000000-0000-0000-0000-000000000001') then raise exception 'guardian must not see private item'; end if;
  if not can_view_plan_item('30000000-0000-0000-0000-000000000001','32000000-0000-0000-0000-000000000002') then raise exception 'guardian must see guardian item'; end if;
  if can_view_plan_item('30000000-0000-0000-0000-000000000003','32000000-0000-0000-0000-000000000002') then raise exception 'outsider must not see guardian item'; end if;
  if not can_view_plan_item('30000000-0000-0000-0000-000000000002','32000000-0000-0000-0000-000000000003') then raise exception 'family member must see family event'; end if;
  if not can_view_student_academic('30000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000002') then raise exception 'guardian academic access missing'; end if;
  if can_view_student_academic('30000000-0000-0000-0000-000000000003','30000000-0000-0000-0000-000000000002') then raise exception 'outsider academic access must fail'; end if;
end $$;

update family_membership set ended_at=now()
where family_id='31000000-0000-0000-0000-000000000001'
and user_id='30000000-0000-0000-0000-000000000001';

do $$
begin
  if can_view_plan_item('30000000-0000-0000-0000-000000000001','32000000-0000-0000-0000-000000000002') then raise exception 'removed guardian must lose plan access'; end if;
  if can_view_student_academic('30000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000002') then raise exception 'removed guardian must lose academic access'; end if;
end $$;

rollback;
