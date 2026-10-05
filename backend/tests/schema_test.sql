\set ON_ERROR_STOP on

begin;

insert into app_user(id, identity_subject, email_normalized) values
('00000000-0000-0000-0000-000000000001','parent-1','parent@example.test'),
('00000000-0000-0000-0000-000000000002','teen-1','teen@example.test'),
('00000000-0000-0000-0000-000000000003','other-1','other@example.test');

insert into family_workspace(id,name,created_by) values
('10000000-0000-0000-0000-000000000001','Test Family','00000000-0000-0000-0000-000000000001');

insert into family_membership(family_id,user_id,role,is_admin) values
('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000001','parent_guardian',true),
('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002','teen_minor',false);

insert into guardian_relationship(family_id,guardian_user_id,minor_user_id) values
('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002');

do $$
begin
  if not is_active_family_member('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002') then raise exception 'teen must be active family member'; end if;
  if is_active_family_member('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000003') then raise exception 'outsider must not be family member'; end if;
  if not is_family_admin('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000001') then raise exception 'parent admin capability missing'; end if;
  if is_family_admin('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002') then raise exception 'teen must not inherit admin capability'; end if;
  if not is_active_guardian('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002') then raise exception 'guardian relation missing'; end if;
  if is_active_guardian('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000002') then raise exception 'outsider must not become guardian'; end if;
end $;

update family_membership
set ended_at=now()
where family_id='10000000-0000-0000-0000-000000000001'
  and user_id='00000000-0000-0000-0000-000000000002';

do $
begin
  if is_active_family_member('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002') then raise exception 'removed teen must not remain active member'; end if;
  if is_active_guardian('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002') then raise exception 'guardian relationship must deactivate when minor membership ends'; end if;
end $;

rollback;
