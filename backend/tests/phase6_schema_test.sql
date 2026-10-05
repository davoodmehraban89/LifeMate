\set ON_ERROR_STOP on

do $$
begin
  if not exists(select 1 from information_schema.columns where table_name='profile' and column_name='household_persona') then raise exception 'household persona missing'; end if;
  if not exists(select 1 from information_schema.tables where table_name='education_profile') then raise exception 'education profile missing'; end if;
  if not exists(select 1 from information_schema.tables where table_name='menstrual_cycle_entry') then raise exception 'cycle table missing'; end if;
  if (select count(*) from curriculum_subject where national_grade=7 and school_year='1405-1406') < 10 then raise exception 'grade 7 catalog incomplete'; end if;
  if not exists(select 1 from curriculum_subject where national_grade=7 and name_fa='ریاضی') then raise exception 'grade 7 mathematics missing'; end if;
  if exists(select 1 from textbook_catalog where source_host not in ('chap.sch.ir','medu.gov.ir') or source_url !~ '^https://') then raise exception 'untrusted textbook source'; end if;
  if not exists(select 1 from information_schema.columns where table_name='notification_preference' and column_name='sensitive_preview') then raise exception 'sensitive preview control missing'; end if;
end $$;
