begin;

alter table profile add column profile_category text;

-- Legacy presentation choices are the only migration hint. Family membership
-- and guardian permissions never define a person's independent category.
update profile set profile_category=case theme_preference
  when 'girl_pink' then 'girl_minor'
  when 'boy_blue' then 'boy_minor'
  else 'adult'
end;

alter table profile alter column profile_category set default 'adult';
alter table profile alter column profile_category set not null;
alter table profile add constraint profile_category_allowed
  check(profile_category in ('girl_minor','boy_minor','adult'));

commit;
