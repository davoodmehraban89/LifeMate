\set ON_ERROR_STOP on
-- Synthetic records only, inserted into a newly-created drill database.
insert into app_user(id,identity_subject,email_normalized,email_verified_at) values
 ('00000000-0000-4000-8000-000000000006','restore-child','restore-child@lifeguide.test',now()),
 ('00000000-0000-4000-8000-000000000007','restore-other-parent','restore-other-parent@lifeguide.test',now());
insert into profile(user_id,display_name,theme_preference) values
 ('00000000-0000-4000-8000-000000000006','Synthetic child','boy_blue'),
 ('00000000-0000-4000-8000-000000000007','Synthetic unrelated parent','adult_blue');
insert into family_workspace(id,name,created_by) values
 ('00000000-0000-4000-8000-000000000005','LifeGuide synthetic migration family','00000000-0000-4000-8000-000000000005');
insert into family_membership(family_id,user_id,role,is_admin) values
 ('00000000-0000-4000-8000-000000000005','00000000-0000-4000-8000-000000000005','parent_guardian',true),
 ('00000000-0000-4000-8000-000000000005','00000000-0000-4000-8000-000000000006','teen_minor',false);
insert into guardian_relationship(family_id,guardian_user_id,minor_user_id) values
 ('00000000-0000-4000-8000-000000000005','00000000-0000-4000-8000-000000000005','00000000-0000-4000-8000-000000000006');
insert into plan_item(id,owner_user_id,family_id,kind,title,visibility) values
 ('00000000-0000-4000-8000-000000000005','00000000-0000-4000-8000-000000000006','00000000-0000-4000-8000-000000000005','assignment','Synthetic mathematics homework','parent_guardian'),
 ('00000000-0000-4000-8000-000000000006','00000000-0000-4000-8000-000000000006','00000000-0000-4000-8000-000000000005','task','Synthetic private task','private');
insert into study_session(id,child_user_id,plan_item_id,source,status,started_at,ended_at,last_event_at,recorded_duration_seconds) values
 ('00000000-0000-4000-8000-000000000005','00000000-0000-4000-8000-000000000006','00000000-0000-4000-8000-000000000005','timer','completed','2026-01-01T10:00:00Z','2026-01-01T10:15:00Z','2026-01-01T10:15:00Z',600);
insert into study_interval(session_id,starts_at,ends_at) values
 ('00000000-0000-4000-8000-000000000005','2026-01-01T10:00:00Z','2026-01-01T10:05:00Z'),
 ('00000000-0000-4000-8000-000000000005','2026-01-01T10:10:00Z','2026-01-01T10:15:00Z');
