\set ON_ERROR_STOP on
insert into app_user(id,identity_subject,email_normalized,email_verified_at)
values('00000000-0000-4000-8000-000000000005','restore-smoke','restore-smoke@lifemate.test',now())
on conflict (id) do nothing;
insert into profile(user_id,display_name,theme_preference)
values('00000000-0000-4000-8000-000000000005','Restore Smoke','adult_blue')
on conflict (user_id) do nothing;
