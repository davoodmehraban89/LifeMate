begin;

alter table profile
  add column if not exists household_persona text check (household_persona in ('mother','father','child','adult')),
  add column if not exists sex text check (sex in ('female','male','unspecified'));

create table education_profile (
  user_id uuid primary key references app_user(id) on delete cascade,
  country_code char(2) not null default 'IR' check (country_code='IR'),
  stage text not null check (stage in ('primary_1','primary_2','secondary_1','secondary_2')),
  national_grade smallint not null check (national_grade between 1 and 12),
  local_year smallint not null check (local_year between 1 and 3),
  school_name text,
  school_year text not null,
  updated_at timestamptz not null default now(),
  check (
    (stage='primary_1' and national_grade between 1 and 3 and local_year=national_grade) or
    (stage='primary_2' and national_grade between 4 and 6 and local_year=national_grade-3) or
    (stage='secondary_1' and national_grade between 7 and 9 and local_year=national_grade-6) or
    (stage='secondary_2' and national_grade between 10 and 12 and local_year=national_grade-9)
  )
);

create table curriculum_subject (
  id uuid primary key default gen_random_uuid(),
  country_code char(2) not null default 'IR',
  school_year text not null,
  national_grade smallint not null check (national_grade between 1 and 12),
  code text not null,
  name_fa text not null,
  sort_order smallint not null default 0,
  unique(country_code,school_year,national_grade,code)
);

create table textbook_catalog (
  id uuid primary key default gen_random_uuid(),
  curriculum_subject_id uuid not null references curriculum_subject(id) on delete cascade,
  title_fa text not null,
  publisher text not null default 'سازمان پژوهش و برنامه‌ریزی آموزشی',
  source_host text not null default 'chap.sch.ir' check (source_host in ('chap.sch.ir','medu.gov.ir')),
  source_url text not null check (source_url ~ '^https://'),
  redistribution_status text not null default 'link_only' check (redistribution_status in ('link_only','licensed_bundle')),
  unique(curriculum_subject_id,title_fa)
);

create table iran_calendar_event (
  id uuid primary key default gen_random_uuid(),
  jalali_year smallint not null check (jalali_year between 1300 and 1600),
  jalali_month smallint not null check (jalali_month between 1 and 12),
  jalali_day smallint not null check (jalali_day between 1 and 31),
  title_fa text not null,
  is_official_holiday boolean not null default false,
  source_name text not null,
  source_url text not null check (source_url ~ '^https://'),
  unique(jalali_year,jalali_month,jalali_day,title_fa)
);

create table notification_preference (
  user_id uuid primary key references app_user(id) on delete cascade,
  in_app_banner boolean not null default true,
  push_enabled boolean not null default false,
  planner_reminders boolean not null default true,
  school_reminders boolean not null default true,
  calendar_reminders boolean not null default true,
  cycle_reminders boolean not null default false,
  sensitive_preview boolean not null default false,
  updated_at timestamptz not null default now()
);

create table menstrual_cycle_entry (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references app_user(id) on delete cascade,
  starts_on date not null,
  ends_on date,
  predicted_next_on date,
  symptoms text[] not null default '{}',
  notes text,
  reminder_enabled boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_on is null or ends_on >= starts_on),
  check (predicted_next_on is null or predicted_next_on > starts_on)
);
create index menstrual_cycle_owner_date_idx on menstrual_cycle_entry(owner_user_id,starts_on desc);

insert into curriculum_subject(school_year,national_grade,code,name_fa,sort_order) values
('1405-1406',7,'fa','فارسی',10),
('1405-1406',7,'writing','نگارش',20),
('1405-1406',7,'math','ریاضی',30),
('1405-1406',7,'science','علوم تجربی',40),
('1405-1406',7,'social','مطالعات اجتماعی',50),
('1405-1406',7,'arabic','عربی',60),
('1405-1406',7,'quran','قرآن',70),
('1405-1406',7,'religion','پیام‌های آسمان',80),
('1405-1406',7,'english','انگلیسی',90),
('1405-1406',7,'worktech','کار و فناوری',100),
('1405-1406',7,'thinking','تفکر و سبک زندگی',110),
('1405-1406',7,'pe','تربیت بدنی و سلامت',120)
on conflict do nothing;

insert into textbook_catalog(curriculum_subject_id,title_fa,source_url)
select id,name_fa,'https://chap.sch.ir/' from curriculum_subject
where school_year='1405-1406' and national_grade=7
on conflict do nothing;

-- Stable solar events/holidays for 1405. Lunar observances remain data-updatable rather than guessed.
insert into iran_calendar_event(jalali_year,jalali_month,jalali_day,title_fa,is_official_holiday,source_name,source_url) values
(1405,1,1,'آغاز نوروز',true,'تقویم رسمی کشور ۱۴۰۵ — مرکز تقویم مؤسسه ژئوفیزیک دانشگاه تهران','https://calendar.ut.ac.ir/'),
(1405,1,2,'عید نوروز',true,'تقویم رسمی کشور ۱۴۰۵ — مرکز تقویم مؤسسه ژئوفیزیک دانشگاه تهران','https://calendar.ut.ac.ir/'),
(1405,1,3,'عید نوروز',true,'تقویم رسمی کشور ۱۴۰۵ — مرکز تقویم مؤسسه ژئوفیزیک دانشگاه تهران','https://calendar.ut.ac.ir/'),
(1405,1,4,'عید نوروز',true,'تقویم رسمی کشور ۱۴۰۵ — مرکز تقویم مؤسسه ژئوفیزیک دانشگاه تهران','https://calendar.ut.ac.ir/'),
(1405,1,12,'روز جمهوری اسلامی ایران',true,'تقویم رسمی کشور ۱۴۰۵ — مرکز تقویم مؤسسه ژئوفیزیک دانشگاه تهران','https://calendar.ut.ac.ir/'),
(1405,1,13,'روز طبیعت',true,'تقویم رسمی کشور ۱۴۰۵ — مرکز تقویم مؤسسه ژئوفیزیک دانشگاه تهران','https://calendar.ut.ac.ir/'),
(1405,3,14,'رحلت امام خمینی',true,'تقویم رسمی کشور ۱۴۰۵ — مرکز تقویم مؤسسه ژئوفیزیک دانشگاه تهران','https://calendar.ut.ac.ir/'),
(1405,3,15,'قیام ۱۵ خرداد',true,'تقویم رسمی کشور ۱۴۰۵ — مرکز تقویم مؤسسه ژئوفیزیک دانشگاه تهران','https://calendar.ut.ac.ir/'),
(1405,11,22,'پیروزی انقلاب اسلامی ایران',true,'تقویم رسمی کشور ۱۴۰۵ — مرکز تقویم مؤسسه ژئوفیزیک دانشگاه تهران','https://calendar.ut.ac.ir/'),
(1405,12,29,'روز ملی شدن صنعت نفت ایران',true,'تقویم رسمی کشور ۱۴۰۵ — مرکز تقویم مؤسسه ژئوفیزیک دانشگاه تهران','https://calendar.ut.ac.ir/')
on conflict do nothing;

commit;