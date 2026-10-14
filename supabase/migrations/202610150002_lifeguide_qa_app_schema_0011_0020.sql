begin;
set local lock_timeout='5s';
set local statement_timeout='120s';
set local search_path=lifeguide_qa,extensions,pg_catalog;
do $preflight$ begin
 if current_database()<>'postgres'
 or to_regnamespace('lifeguide_qa') is null
 or to_regclass('lifeguide_qa.schema_migration') is null
 or (select count(*) from lifeguide_qa.schema_migration)<>10
 or has_schema_privilege('anon','lifeguide_qa','USAGE')
 or has_schema_privilege('authenticated','lifeguide_qa','USAGE')
 then raise exception 'lifeguide_qa_second_phase_preflight_denied'; end if;
end $preflight$;
-- Original LifeGuide migration 0011_profile_category.sql


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


insert into lifeguide_qa.schema_migration(filename,sha256)
values ('0011_profile_category.sql',encode(digest(convert_to($qa_original_0011$begin;

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
$qa_original_0011$,'UTF8'),'sha256'),'hex'));
-- Original LifeGuide migration 0012_school_archive.sql


alter table subject add column archived_at timestamptz;
alter table subject add column updated_at timestamptz;
update subject set updated_at=created_at;
alter table subject alter column updated_at set default now();
alter table subject alter column updated_at set not null;
create index subject_active_owner_idx on subject(student_user_id,created_at desc) where archived_at is null;

alter table class_session add column archived_at timestamptz;
alter table class_session add column updated_at timestamptz;
update class_session set updated_at=created_at;
alter table class_session alter column updated_at set default now();
alter table class_session alter column updated_at set not null;
create index class_session_active_subject_idx on class_session(subject_id,weekday,starts_at) where archived_at is null;

alter table learning_checkin add column archived_at timestamptz;
alter table learning_checkin add column updated_at timestamptz;
alter table learning_checkin add column occurred_at timestamptz;
update learning_checkin set updated_at=created_at,occurred_at=created_at;
alter table learning_checkin alter column updated_at set default now();
alter table learning_checkin alter column updated_at set not null;
alter table learning_checkin alter column occurred_at set default now();
alter table learning_checkin alter column occurred_at set not null;
alter table learning_checkin add column source text not null default 'self_reported' check(source='self_reported');
create index learning_checkin_active_owner_idx on learning_checkin(owner_user_id,occurred_at desc) where archived_at is null;


insert into lifeguide_qa.schema_migration(filename,sha256)
values ('0012_school_archive.sql',encode(digest(convert_to($qa_original_0012$begin;

alter table subject add column archived_at timestamptz;
alter table subject add column updated_at timestamptz;
update subject set updated_at=created_at;
alter table subject alter column updated_at set default now();
alter table subject alter column updated_at set not null;
create index subject_active_owner_idx on subject(student_user_id,created_at desc) where archived_at is null;

alter table class_session add column archived_at timestamptz;
alter table class_session add column updated_at timestamptz;
update class_session set updated_at=created_at;
alter table class_session alter column updated_at set default now();
alter table class_session alter column updated_at set not null;
create index class_session_active_subject_idx on class_session(subject_id,weekday,starts_at) where archived_at is null;

alter table learning_checkin add column archived_at timestamptz;
alter table learning_checkin add column updated_at timestamptz;
alter table learning_checkin add column occurred_at timestamptz;
update learning_checkin set updated_at=created_at,occurred_at=created_at;
alter table learning_checkin alter column updated_at set default now();
alter table learning_checkin alter column updated_at set not null;
alter table learning_checkin alter column occurred_at set default now();
alter table learning_checkin alter column occurred_at set not null;
alter table learning_checkin add column source text not null default 'self_reported' check(source='self_reported');
create index learning_checkin_active_owner_idx on learning_checkin(owner_user_id,occurred_at desc) where archived_at is null;

commit;
$qa_original_0012$,'UTF8'),'sha256'),'hex'));
-- Original LifeGuide migration 0013_aparat_learning_library.sql

alter table education_profile add column track_code text;
update education_profile set track_code='common' where national_grade<10;
alter table education_profile add constraint education_profile_track_check check ((national_grade<10 and track_code='common') or (national_grade>=10 and (track_code is null or track_code in ('math','experimental','humanities'))));
alter table curriculum_subject add column subject_code text;
alter table textbook_catalog add column stable_book_key text unique, add column book_code text, add column track_codes text[] not null default '{common}', add column variant text not null default 'standard' check(variant in('standard','experimental','religious_variant','gifted')), add column edition_verification text not null default 'unverified' check(edition_verification in('verified','unverified')), add column sequence_verification text not null default 'unverified' check(sequence_verification in('official_toc','provider_index','unverified')), add column source_evidence_url text, add column alignment_notes_fa text not null default 'چاپ و انطباق منابع تأیید نشده است.';
create table learning_unit (
 id uuid primary key default gen_random_uuid(),textbook_id uuid not null references textbook_catalog(id),unit_key text not null check(unit_key~'^[a-z0-9][a-z0-9-]{0,79}$'),title_fa text not null,order_index integer not null check(order_index>0),index_kind text not null check(index_kind in('page','lesson','chapter')),source_evidence_url text not null,active boolean not null default true,unique(textbook_id,unit_key)
);
create index learning_unit_order_idx on learning_unit(textbook_id,order_index,unit_key);
create table learning_video_resource (
 id uuid primary key default gen_random_uuid(),unit_id uuid not null references learning_unit(id),aparat_id text not null check(aparat_id~'^[A-Za-z0-9]{5,64}$'),canonical_aparat_id text check(canonical_aparat_id is null or canonical_aparat_id~'^[A-Za-z0-9]{5,64}$'),title_fa text not null,creator_name text not null,creator_url text not null check(creator_url~'^https://www\.aparat\.com/[A-Za-z0-9_.-]+$'),source_evidence_url text not null,verification_status text not null check(verification_status in('index_verified','metadata_verified','embed_verified')),pedagogical_review text not null default 'unverified' check(pedagogical_review in('unverified','full_reviewed')),duration_seconds integer check(duration_seconds is null or duration_seconds>0),free_access boolean,checked_at timestamptz not null,quality_notes_fa text not null,publication_status text not null default 'draft' check(publication_status in('draft','published','withdrawn')),review_record jsonb,material_hash text not null check(material_hash~'^[a-f0-9]{64}$'),unique(unit_id,aparat_id),
 constraint full_review_before_publication check(publication_status<>'published' or (
 free_access is true and pedagogical_review='full_reviewed' and verification_status in('metadata_verified','embed_verified') and jsonb_typeof(review_record)='object'
 and length(trim(coalesce(review_record->>'reviewerName','')))>0 and length(trim(coalesce(review_record->>'reviewedAt','')))>0
 and coalesce(review_record->>'watchedEntireVideo'='true',false) and coalesce(review_record->>'editionAligned'='true',false)
 and coalesce(review_record->>'accuracyApproved'='true',false) and coalesce(review_record->>'suitabilityApproved'='true',false)
 and coalesce(review_record->>'embedRightsApproved'='true',false) and coalesce(review_record->>'questionCoverageReviewed'='true',false)
 and length(trim(coalesce(review_record->>'alignmentNotes','')))>0 and length(trim(coalesce(review_record->>'accuracyNotes','')))>0
 and length(trim(coalesce(review_record->>'suitabilityNotes','')))>0 and length(trim(coalesce(review_record->>'embedRightsEvidence','')))>0
 and length(trim(coalesce(review_record->>'questionCoverageNotes','')))>0
 ))
);
create index learning_video_unit_publication_idx on learning_video_resource(unit_id,publication_status);
create function validate_learning_publication() returns trigger language plpgsql as $$
declare book record; reviewed timestamptz;
begin
 if new.publication_status='published' then
  select t.book_code,t.edition_verification,t.source_evidence_url book_evidence_url,s.school_year,u.unit_key,u.source_evidence_url unit_evidence_url,u.active into book from learning_unit u join textbook_catalog t on t.id=u.textbook_id join curriculum_subject s on s.id=t.curriculum_subject_id where u.id=new.unit_id;
  if not book.active or new.review_record->>'materialHash' is distinct from new.material_hash or new.review_record->>'bookEvidenceUrl' is distinct from book.book_evidence_url or new.review_record->>'unitEvidenceUrl' is distinct from book.unit_evidence_url or book.edition_verification<>'verified' or book.school_year='unknown' or new.review_record->>'bookCode' is distinct from book.book_code or new.review_record->>'schoolYear' is distinct from book.school_year or new.review_record->>'unitKey' is distinct from book.unit_key then raise exception 'full review must match verified book edition and unit' using errcode='23514'; end if;
  begin reviewed:=(new.review_record->>'reviewedAt')::timestamptz; exception when others then raise exception 'invalid review timestamp' using errcode='23514'; end;
  if reviewed is null or reviewed>now() then raise exception 'invalid review timestamp' using errcode='23514'; end if;
 end if;
 return new;
end $$;
create trigger learning_publication_guard before insert or update on learning_video_resource for each row execute function validate_learning_publication();
create table learning_progress (
 owner_user_id uuid not null references app_user(id) on delete cascade,unit_id uuid not null references learning_unit(id),status text not null check(status in('not_started','in_progress','completed')),source text not null check(source='self_reported'),version bigint not null check(version>0),updated_at timestamptz not null default now(),primary key(owner_user_id,unit_id)
);
create table learning_progress_mutation (
 owner_user_id uuid not null references app_user(id) on delete cascade,mutation_id uuid not null,unit_id uuid not null references learning_unit(id),request_hash text not null check(length(request_hash)=64),acknowledgement jsonb not null,accepted_at timestamptz not null default now(),primary key(owner_user_id,mutation_id)
);
alter table plan_item add column learning_unit_id uuid references learning_unit(id);

insert into lifeguide_qa.schema_migration(filename,sha256)
values ('0013_aparat_learning_library.sql',encode(digest(convert_to($qa_original_0013$begin;
alter table education_profile add column track_code text;
update education_profile set track_code='common' where national_grade<10;
alter table education_profile add constraint education_profile_track_check check ((national_grade<10 and track_code='common') or (national_grade>=10 and (track_code is null or track_code in ('math','experimental','humanities'))));
alter table curriculum_subject add column subject_code text;
alter table textbook_catalog add column stable_book_key text unique, add column book_code text, add column track_codes text[] not null default '{common}', add column variant text not null default 'standard' check(variant in('standard','experimental','religious_variant','gifted')), add column edition_verification text not null default 'unverified' check(edition_verification in('verified','unverified')), add column sequence_verification text not null default 'unverified' check(sequence_verification in('official_toc','provider_index','unverified')), add column source_evidence_url text, add column alignment_notes_fa text not null default 'چاپ و انطباق منابع تأیید نشده است.';
create table learning_unit (
 id uuid primary key default gen_random_uuid(),textbook_id uuid not null references textbook_catalog(id),unit_key text not null check(unit_key~'^[a-z0-9][a-z0-9-]{0,79}$'),title_fa text not null,order_index integer not null check(order_index>0),index_kind text not null check(index_kind in('page','lesson','chapter')),source_evidence_url text not null,active boolean not null default true,unique(textbook_id,unit_key)
);
create index learning_unit_order_idx on learning_unit(textbook_id,order_index,unit_key);
create table learning_video_resource (
 id uuid primary key default gen_random_uuid(),unit_id uuid not null references learning_unit(id),aparat_id text not null check(aparat_id~'^[A-Za-z0-9]{5,64}$'),canonical_aparat_id text check(canonical_aparat_id is null or canonical_aparat_id~'^[A-Za-z0-9]{5,64}$'),title_fa text not null,creator_name text not null,creator_url text not null check(creator_url~'^https://www\.aparat\.com/[A-Za-z0-9_.-]+$'),source_evidence_url text not null,verification_status text not null check(verification_status in('index_verified','metadata_verified','embed_verified')),pedagogical_review text not null default 'unverified' check(pedagogical_review in('unverified','full_reviewed')),duration_seconds integer check(duration_seconds is null or duration_seconds>0),free_access boolean,checked_at timestamptz not null,quality_notes_fa text not null,publication_status text not null default 'draft' check(publication_status in('draft','published','withdrawn')),review_record jsonb,material_hash text not null check(material_hash~'^[a-f0-9]{64}$'),unique(unit_id,aparat_id),
 constraint full_review_before_publication check(publication_status<>'published' or (
 free_access is true and pedagogical_review='full_reviewed' and verification_status in('metadata_verified','embed_verified') and jsonb_typeof(review_record)='object'
 and length(trim(coalesce(review_record->>'reviewerName','')))>0 and length(trim(coalesce(review_record->>'reviewedAt','')))>0
 and coalesce(review_record->>'watchedEntireVideo'='true',false) and coalesce(review_record->>'editionAligned'='true',false)
 and coalesce(review_record->>'accuracyApproved'='true',false) and coalesce(review_record->>'suitabilityApproved'='true',false)
 and coalesce(review_record->>'embedRightsApproved'='true',false) and coalesce(review_record->>'questionCoverageReviewed'='true',false)
 and length(trim(coalesce(review_record->>'alignmentNotes','')))>0 and length(trim(coalesce(review_record->>'accuracyNotes','')))>0
 and length(trim(coalesce(review_record->>'suitabilityNotes','')))>0 and length(trim(coalesce(review_record->>'embedRightsEvidence','')))>0
 and length(trim(coalesce(review_record->>'questionCoverageNotes','')))>0
 ))
);
create index learning_video_unit_publication_idx on learning_video_resource(unit_id,publication_status);
create function validate_learning_publication() returns trigger language plpgsql as $$
declare book record; reviewed timestamptz;
begin
 if new.publication_status='published' then
  select t.book_code,t.edition_verification,t.source_evidence_url book_evidence_url,s.school_year,u.unit_key,u.source_evidence_url unit_evidence_url,u.active into book from learning_unit u join textbook_catalog t on t.id=u.textbook_id join curriculum_subject s on s.id=t.curriculum_subject_id where u.id=new.unit_id;
  if not book.active or new.review_record->>'materialHash' is distinct from new.material_hash or new.review_record->>'bookEvidenceUrl' is distinct from book.book_evidence_url or new.review_record->>'unitEvidenceUrl' is distinct from book.unit_evidence_url or book.edition_verification<>'verified' or book.school_year='unknown' or new.review_record->>'bookCode' is distinct from book.book_code or new.review_record->>'schoolYear' is distinct from book.school_year or new.review_record->>'unitKey' is distinct from book.unit_key then raise exception 'full review must match verified book edition and unit' using errcode='23514'; end if;
  begin reviewed:=(new.review_record->>'reviewedAt')::timestamptz; exception when others then raise exception 'invalid review timestamp' using errcode='23514'; end;
  if reviewed is null or reviewed>now() then raise exception 'invalid review timestamp' using errcode='23514'; end if;
 end if;
 return new;
end $$;
create trigger learning_publication_guard before insert or update on learning_video_resource for each row execute function validate_learning_publication();
create table learning_progress (
 owner_user_id uuid not null references app_user(id) on delete cascade,unit_id uuid not null references learning_unit(id),status text not null check(status in('not_started','in_progress','completed')),source text not null check(source='self_reported'),version bigint not null check(version>0),updated_at timestamptz not null default now(),primary key(owner_user_id,unit_id)
);
create table learning_progress_mutation (
 owner_user_id uuid not null references app_user(id) on delete cascade,mutation_id uuid not null,unit_id uuid not null references learning_unit(id),request_hash text not null check(length(request_hash)=64),acknowledgement jsonb not null,accepted_at timestamptz not null default now(),primary key(owner_user_id,mutation_id)
);
alter table plan_item add column learning_unit_id uuid references learning_unit(id);
commit;
$qa_original_0013$,'UTF8'),'sha256'),'hex'));
-- Original LifeGuide migration 0014_learning_feedback.sql


-- A consented, explicitly chosen summary, never a copy of private chat/notes.
-- Withdrawal redacts the summary while preserving retry and rate-limit receipts.
create table learning_content_feedback (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references app_user(id) on delete cascade,
  mutation_id uuid not null,
  request_hash text not null check(request_hash ~ '^[0-9a-f]{64}$'),
  unit_id uuid references learning_unit(id),
  category text not null check(category in
    ('inaccurate','edition_mismatch','broken_video','unclear','topic_request')),
  summary text,
  share_with_content_team boolean not null,
  consented_at timestamptz not null default now(),
  status text not null default 'received'
    check(status in ('received','triaged','planned','released','declined')),
  version integer not null default 1 check(version > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  withdrawn_at timestamptz,
  unique(owner_user_id,mutation_id),
  check (
    (withdrawn_at is null and share_with_content_team=true and summary is not null
      and char_length(summary) between 1 and 1000 and length(trim(summary))>0)
    or
    (withdrawn_at is not null and share_with_content_team=false and summary is null)
  )
);

create index learning_feedback_owner_time_idx
  on learning_content_feedback(owner_user_id,created_at desc,id desc);


insert into lifeguide_qa.schema_migration(filename,sha256)
values ('0014_learning_feedback.sql',encode(digest(convert_to($qa_original_0014$begin;

-- A consented, explicitly chosen summary, never a copy of private chat/notes.
-- Withdrawal redacts the summary while preserving retry and rate-limit receipts.
create table learning_content_feedback (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references app_user(id) on delete cascade,
  mutation_id uuid not null,
  request_hash text not null check(request_hash ~ '^[0-9a-f]{64}$'),
  unit_id uuid references learning_unit(id),
  category text not null check(category in
    ('inaccurate','edition_mismatch','broken_video','unclear','topic_request')),
  summary text,
  share_with_content_team boolean not null,
  consented_at timestamptz not null default now(),
  status text not null default 'received'
    check(status in ('received','triaged','planned','released','declined')),
  version integer not null default 1 check(version > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  withdrawn_at timestamptz,
  unique(owner_user_id,mutation_id),
  check (
    (withdrawn_at is null and share_with_content_team=true and summary is not null
      and char_length(summary) between 1 and 1000 and length(trim(summary))>0)
    or
    (withdrawn_at is not null and share_with_content_team=false and summary is null)
  )
);

create index learning_feedback_owner_time_idx
  on learning_content_feedback(owner_user_id,created_at desc,id desc);

commit;
$qa_original_0014$,'UTF8'),'sha256'),'hex'));
-- Original LifeGuide migration 0015_learning_assessment.sql

create table learning_assessment (
 id uuid primary key default gen_random_uuid(),
 unit_id uuid not null references learning_unit(id),
 version integer not null default 1 check(version>0),
 questions jsonb not null check(jsonb_typeof(questions)='array' and jsonb_array_length(questions) between 1 and 20),
 content_hash text not null check(content_hash~'^[a-f0-9]{64}$'),
 context_hash text not null check(context_hash~'^[a-f0-9]{64}$'),
 publication_status text not null default 'draft' check(publication_status in('draft','published','withdrawn')),
 review_record jsonb,
 created_at timestamptz not null default now(),
 check(publication_status<>'published' or coalesce(
  jsonb_typeof(review_record)='object' and length(trim(review_record->>'reviewerName'))>0
  and (review_record->>'accuracyApproved')='true' and (review_record->>'suitabilityApproved')='true'
  and (review_record->>'editionAligned')='true' and (review_record->>'objectiveCoverageApproved')='true'
  and (review_record->>'contentHash')=content_hash and (review_record->>'contextHash')=context_hash
  and length(trim(review_record->>'reviewNotes'))>0,false))
);
create index learning_assessment_unit_idx on learning_assessment(unit_id,publication_status,version desc);
create function validate_learning_assessment_publication() returns trigger language plpgsql as $$
declare b record; reviewed timestamptz;
begin
 if TG_OP='UPDATE' and new.questions is distinct from old.questions then
  if new.publication_status='published' or new.version<=old.version or new.content_hash=old.content_hash then
   raise exception 'changed assessment needs a new version/hash and draft review' using errcode='23514';
  end if;
 end if;
 if new.publication_status='published' then
  select t.book_code,t.edition_verification,s.school_year,u.unit_key into b
   from learning_unit u join textbook_catalog t on t.id=u.textbook_id
   join curriculum_subject s on s.id=t.curriculum_subject_id where u.id=new.unit_id and u.active;
  if b.edition_verification is distinct from 'verified' or b.school_year='unknown'
   or new.review_record->>'bookCode' is distinct from b.book_code
   or new.review_record->>'schoolYear' is distinct from b.school_year
   or new.review_record->>'unitKey' is distinct from b.unit_key then
   raise exception 'assessment must match reviewed verified book edition and unit' using errcode='23514';
  end if;
  begin reviewed:=(new.review_record->>'reviewedAt')::timestamptz;
   exception when others then raise exception 'invalid assessment review timestamp' using errcode='23514'; end;
  if reviewed is null or reviewed>now() then raise exception 'invalid assessment review timestamp' using errcode='23514'; end if;
 end if;
 return new;
end $$;
create trigger learning_assessment_publication_guard before insert or update on learning_assessment
 for each row execute function validate_learning_assessment_publication();
create table learning_assessment_attempt (
 id uuid primary key default gen_random_uuid(),owner_user_id uuid not null references app_user(id) on delete cascade,
 mutation_id uuid not null,assessment_id uuid not null references learning_assessment(id),
 unit_id uuid not null references learning_unit(id),assessment_version integer not null,
 request_hash text not null check(request_hash~'^[a-f0-9]{64}$'),answers jsonb not null,
 confidence text not null check(confidence in('unsure','somewhat','confident')),
 question_snapshot jsonb not null,acknowledgement jsonb not null,
 created_at timestamptz not null default now(),unique(owner_user_id,mutation_id)
);
create index learning_attempt_owner_idx on learning_assessment_attempt(owner_user_id,unit_id,created_at desc);
create table learning_review_schedule (
 owner_user_id uuid not null references app_user(id) on delete cascade,unit_id uuid not null references learning_unit(id),
 last_attempt_id uuid not null references learning_assessment_attempt(id),next_review_at timestamptz not null,
 schedule_policy text not null default 'pilot-1-or-3-days' check(schedule_policy='pilot-1-or-3-days'),
 primary key(owner_user_id,unit_id)
);

insert into lifeguide_qa.schema_migration(filename,sha256)
values ('0015_learning_assessment.sql',encode(digest(convert_to($qa_original_0015$begin;
create table learning_assessment (
 id uuid primary key default gen_random_uuid(),
 unit_id uuid not null references learning_unit(id),
 version integer not null default 1 check(version>0),
 questions jsonb not null check(jsonb_typeof(questions)='array' and jsonb_array_length(questions) between 1 and 20),
 content_hash text not null check(content_hash~'^[a-f0-9]{64}$'),
 context_hash text not null check(context_hash~'^[a-f0-9]{64}$'),
 publication_status text not null default 'draft' check(publication_status in('draft','published','withdrawn')),
 review_record jsonb,
 created_at timestamptz not null default now(),
 check(publication_status<>'published' or coalesce(
  jsonb_typeof(review_record)='object' and length(trim(review_record->>'reviewerName'))>0
  and (review_record->>'accuracyApproved')='true' and (review_record->>'suitabilityApproved')='true'
  and (review_record->>'editionAligned')='true' and (review_record->>'objectiveCoverageApproved')='true'
  and (review_record->>'contentHash')=content_hash and (review_record->>'contextHash')=context_hash
  and length(trim(review_record->>'reviewNotes'))>0,false))
);
create index learning_assessment_unit_idx on learning_assessment(unit_id,publication_status,version desc);
create function validate_learning_assessment_publication() returns trigger language plpgsql as $$
declare b record; reviewed timestamptz;
begin
 if TG_OP='UPDATE' and new.questions is distinct from old.questions then
  if new.publication_status='published' or new.version<=old.version or new.content_hash=old.content_hash then
   raise exception 'changed assessment needs a new version/hash and draft review' using errcode='23514';
  end if;
 end if;
 if new.publication_status='published' then
  select t.book_code,t.edition_verification,s.school_year,u.unit_key into b
   from learning_unit u join textbook_catalog t on t.id=u.textbook_id
   join curriculum_subject s on s.id=t.curriculum_subject_id where u.id=new.unit_id and u.active;
  if b.edition_verification is distinct from 'verified' or b.school_year='unknown'
   or new.review_record->>'bookCode' is distinct from b.book_code
   or new.review_record->>'schoolYear' is distinct from b.school_year
   or new.review_record->>'unitKey' is distinct from b.unit_key then
   raise exception 'assessment must match reviewed verified book edition and unit' using errcode='23514';
  end if;
  begin reviewed:=(new.review_record->>'reviewedAt')::timestamptz;
   exception when others then raise exception 'invalid assessment review timestamp' using errcode='23514'; end;
  if reviewed is null or reviewed>now() then raise exception 'invalid assessment review timestamp' using errcode='23514'; end if;
 end if;
 return new;
end $$;
create trigger learning_assessment_publication_guard before insert or update on learning_assessment
 for each row execute function validate_learning_assessment_publication();
create table learning_assessment_attempt (
 id uuid primary key default gen_random_uuid(),owner_user_id uuid not null references app_user(id) on delete cascade,
 mutation_id uuid not null,assessment_id uuid not null references learning_assessment(id),
 unit_id uuid not null references learning_unit(id),assessment_version integer not null,
 request_hash text not null check(request_hash~'^[a-f0-9]{64}$'),answers jsonb not null,
 confidence text not null check(confidence in('unsure','somewhat','confident')),
 question_snapshot jsonb not null,acknowledgement jsonb not null,
 created_at timestamptz not null default now(),unique(owner_user_id,mutation_id)
);
create index learning_attempt_owner_idx on learning_assessment_attempt(owner_user_id,unit_id,created_at desc);
create table learning_review_schedule (
 owner_user_id uuid not null references app_user(id) on delete cascade,unit_id uuid not null references learning_unit(id),
 last_attempt_id uuid not null references learning_assessment_attempt(id),next_review_at timestamptz not null,
 schedule_policy text not null default 'pilot-1-or-3-days' check(schedule_policy='pilot-1-or-3-days'),
 primary key(owner_user_id,unit_id)
);
commit;
$qa_original_0015$,'UTF8'),'sha256'),'hex'));
-- Original LifeGuide migration 0016_content_review.sql


-- Explicit content-operation capabilities are independent of family/profile/JWT roles.
-- No default grants and no application HTTP grant endpoint.
create table content_capability_grant (
  user_id uuid not null references app_user(id) on delete cascade,
  permission text not null check(permission in ('feedback.read','feedback.review','brief.prepare')),
  granted_at timestamptz not null default now(),
  expires_at timestamptz not null,
  revoked_at timestamptz,
  primary key(user_id,permission),
  check(expires_at>granted_at)
);

-- Operator-only privilege history contains no copied feedback or contact details.
create table content_capability_audit (
  id uuid primary key default gen_random_uuid(),
  target_user_id uuid not null references app_user(id) on delete cascade,
  permission text not null check(permission in ('feedback.read','feedback.review','brief.prepare')),
  action text not null check(action in ('grant','revoke')),
  occurred_at timestamptz not null default now(),
  expires_at timestamptz
);

create table content_review_brief (
  id uuid primary key default gen_random_uuid(),
  actor_user_id uuid not null references app_user(id) on delete cascade,
  source_count integer not null check(source_count between 1 and 20),
  created_at timestamptz not null default now()
);
create table content_review_brief_source (
  brief_id uuid not null references content_review_brief(id) on delete cascade,
  feedback_id uuid not null references learning_content_feedback(id) on delete cascade,
  feedback_version integer not null check(feedback_version>0),
  primary key(brief_id,feedback_id)
);

-- Store only references/hashes: retries always reconstruct CURRENT consenting state.
create table content_review_mutation (
  actor_user_id uuid not null references app_user(id) on delete cascade,
  mutation_id uuid not null,
  operation text not null check(operation in ('review','brief')),
  request_hash text not null check(request_hash~'^[0-9a-f]{64}$'),
  feedback_id uuid references learning_content_feedback(id) on delete cascade,
  brief_id uuid references content_review_brief(id) on delete cascade,
  accepted_at timestamptz not null default now(),
  primary key(actor_user_id,mutation_id),
  check((operation='review' and feedback_id is not null and brief_id is null)
     or (operation='brief' and feedback_id is null and brief_id is not null))
);
create table content_review_audit (
  id uuid primary key default gen_random_uuid(),
  actor_user_id uuid not null references app_user(id) on delete cascade,
  feedback_id uuid not null references learning_content_feedback(id) on delete cascade,
  before_status text not null check(before_status in ('received','triaged','planned','declined')),
  after_status text not null check(after_status in ('triaged','planned','declined')),
  before_version integer not null check(before_version>0),
  after_version integer not null check(after_version=before_version+1),
  occurred_at timestamptz not null default now()
);
create index content_review_visible_idx on learning_content_feedback(status,created_at desc,id desc)
  where withdrawn_at is null and share_with_content_team=true;
create index content_review_brief_feedback_idx on content_review_brief_source(feedback_id);


insert into lifeguide_qa.schema_migration(filename,sha256)
values ('0016_content_review.sql',encode(digest(convert_to($qa_original_0016$begin;

-- Explicit content-operation capabilities are independent of family/profile/JWT roles.
-- No default grants and no application HTTP grant endpoint.
create table content_capability_grant (
  user_id uuid not null references app_user(id) on delete cascade,
  permission text not null check(permission in ('feedback.read','feedback.review','brief.prepare')),
  granted_at timestamptz not null default now(),
  expires_at timestamptz not null,
  revoked_at timestamptz,
  primary key(user_id,permission),
  check(expires_at>granted_at)
);

-- Operator-only privilege history contains no copied feedback or contact details.
create table content_capability_audit (
  id uuid primary key default gen_random_uuid(),
  target_user_id uuid not null references app_user(id) on delete cascade,
  permission text not null check(permission in ('feedback.read','feedback.review','brief.prepare')),
  action text not null check(action in ('grant','revoke')),
  occurred_at timestamptz not null default now(),
  expires_at timestamptz
);

create table content_review_brief (
  id uuid primary key default gen_random_uuid(),
  actor_user_id uuid not null references app_user(id) on delete cascade,
  source_count integer not null check(source_count between 1 and 20),
  created_at timestamptz not null default now()
);
create table content_review_brief_source (
  brief_id uuid not null references content_review_brief(id) on delete cascade,
  feedback_id uuid not null references learning_content_feedback(id) on delete cascade,
  feedback_version integer not null check(feedback_version>0),
  primary key(brief_id,feedback_id)
);

-- Store only references/hashes: retries always reconstruct CURRENT consenting state.
create table content_review_mutation (
  actor_user_id uuid not null references app_user(id) on delete cascade,
  mutation_id uuid not null,
  operation text not null check(operation in ('review','brief')),
  request_hash text not null check(request_hash~'^[0-9a-f]{64}$'),
  feedback_id uuid references learning_content_feedback(id) on delete cascade,
  brief_id uuid references content_review_brief(id) on delete cascade,
  accepted_at timestamptz not null default now(),
  primary key(actor_user_id,mutation_id),
  check((operation='review' and feedback_id is not null and brief_id is null)
     or (operation='brief' and feedback_id is null and brief_id is not null))
);
create table content_review_audit (
  id uuid primary key default gen_random_uuid(),
  actor_user_id uuid not null references app_user(id) on delete cascade,
  feedback_id uuid not null references learning_content_feedback(id) on delete cascade,
  before_status text not null check(before_status in ('received','triaged','planned','declined')),
  after_status text not null check(after_status in ('triaged','planned','declined')),
  before_version integer not null check(before_version>0),
  after_version integer not null check(after_version=before_version+1),
  occurred_at timestamptz not null default now()
);
create index content_review_visible_idx on learning_content_feedback(status,created_at desc,id desc)
  where withdrawn_at is null and share_with_content_team=true;
create index content_review_brief_feedback_idx on content_review_brief_source(feedback_id);

commit;
$qa_original_0016$,'UTF8'),'sha256'),'hex'));
-- Original LifeGuide migration 0017_learning_goal_mutations.sql
alter table learning_goal add column version integer not null default 1 check(version > 0);
alter table learning_goal add column archived_at timestamptz;
update learning_goal set archived_at=updated_at where status='archived';
alter table learning_goal add constraint learning_goal_archive_state check((status='archived')=(archived_at is not null));
alter table learning_goal add constraint learning_goal_id_owner_unique unique(id,owner_user_id);

create table learning_goal_mutation (
  owner_user_id uuid not null references app_user(id) on delete cascade,
  mutation_id uuid not null,
  goal_id uuid not null,
  operation text not null check(operation in ('create','update','archive')),
  request_hash text not null check(request_hash ~ '^[a-f0-9]{64}$'),
  applied_version integer not null check(applied_version > 0),
  accepted_at timestamptz not null default now(),
  primary key(owner_user_id,mutation_id),
  foreign key(goal_id,owner_user_id) references learning_goal(id,owner_user_id) on delete cascade
);
create index learning_goal_mutation_goal_idx on learning_goal_mutation(owner_user_id,goal_id);
insert into lifeguide_qa.schema_migration(filename,sha256)
values ('0017_learning_goal_mutations.sql',encode(digest(convert_to($qa_original_0017$alter table learning_goal add column version integer not null default 1 check(version > 0);
alter table learning_goal add column archived_at timestamptz;
update learning_goal set archived_at=updated_at where status='archived';
alter table learning_goal add constraint learning_goal_archive_state check((status='archived')=(archived_at is not null));
alter table learning_goal add constraint learning_goal_id_owner_unique unique(id,owner_user_id);

create table learning_goal_mutation (
  owner_user_id uuid not null references app_user(id) on delete cascade,
  mutation_id uuid not null,
  goal_id uuid not null,
  operation text not null check(operation in ('create','update','archive')),
  request_hash text not null check(request_hash ~ '^[a-f0-9]{64}$'),
  applied_version integer not null check(applied_version > 0),
  accepted_at timestamptz not null default now(),
  primary key(owner_user_id,mutation_id),
  foreign key(goal_id,owner_user_id) references learning_goal(id,owner_user_id) on delete cascade
);
create index learning_goal_mutation_goal_idx on learning_goal_mutation(owner_user_id,goal_id);
$qa_original_0017$,'UTF8'),'sha256'),'hex'));
-- Original LifeGuide migration 0018_family_lifecycle.sql


alter table family_membership add column version integer not null default 1 check(version>0),
  add column updated_at timestamptz not null default now();
update family_membership set updated_at=joined_at;
create function membership_lifecycle_revision() returns trigger language plpgsql as $$
begin
  if new.role is distinct from old.role or new.is_admin is distinct from old.is_admin
     or new.ended_at is distinct from old.ended_at or new.joined_at is distinct from old.joined_at then
    new.version:=old.version+1;
    new.updated_at:=statement_timestamp();
  else
    new.version:=old.version;
    new.updated_at:=old.updated_at;
  end if;
  return new;
end $$;
create trigger family_membership_lifecycle_revision before update on family_membership
  for each row execute function membership_lifecycle_revision();

alter table family_invitation add column version integer not null default 1 check(version>0),
  add column updated_at timestamptz not null default now();
update family_invitation set updated_at=created_at;
create function invitation_lifecycle_revision() returns trigger language plpgsql as $$
begin
  if new.status is distinct from old.status or new.expires_at is distinct from old.expires_at
     or new.intended_role is distinct from old.intended_role or new.intended_theme is distinct from old.intended_theme
     or new.invited_email_normalized is distinct from old.invited_email_normalized
     or new.invited_phone_normalized is distinct from old.invited_phone_normalized
     or new.invited_by is distinct from old.invited_by or new.token_digest is distinct from old.token_digest
     or new.accepted_by is distinct from old.accepted_by or new.accepted_at is distinct from old.accepted_at then
    new.version:=old.version+1;
    new.updated_at:=statement_timestamp();
  else
    new.version:=old.version;
    new.updated_at:=old.updated_at;
  end if;
  return new;
end $$;
create trigger family_invitation_lifecycle_revision before update on family_invitation
  for each row execute function invitation_lifecycle_revision();

create table family_lifecycle_mutation (
  actor_user_id uuid not null references app_user(id) on delete cascade,
  mutation_id uuid not null,
  family_id uuid not null references family_workspace(id) on delete cascade,
  operation text not null check(operation in ('role','admin_transfer','invitation_revoke')),
  request_hash text not null check(request_hash~'^[0-9a-f]{64}$'),
  target_id uuid not null,
  accepted_at timestamptz not null default now(),
  primary key(actor_user_id,mutation_id)
);


insert into lifeguide_qa.schema_migration(filename,sha256)
values ('0018_family_lifecycle.sql',encode(digest(convert_to($qa_original_0018$begin;

alter table family_membership add column version integer not null default 1 check(version>0),
  add column updated_at timestamptz not null default now();
update family_membership set updated_at=joined_at;
create function membership_lifecycle_revision() returns trigger language plpgsql as $$
begin
  if new.role is distinct from old.role or new.is_admin is distinct from old.is_admin
     or new.ended_at is distinct from old.ended_at or new.joined_at is distinct from old.joined_at then
    new.version:=old.version+1;
    new.updated_at:=statement_timestamp();
  else
    new.version:=old.version;
    new.updated_at:=old.updated_at;
  end if;
  return new;
end $$;
create trigger family_membership_lifecycle_revision before update on family_membership
  for each row execute function membership_lifecycle_revision();

alter table family_invitation add column version integer not null default 1 check(version>0),
  add column updated_at timestamptz not null default now();
update family_invitation set updated_at=created_at;
create function invitation_lifecycle_revision() returns trigger language plpgsql as $$
begin
  if new.status is distinct from old.status or new.expires_at is distinct from old.expires_at
     or new.intended_role is distinct from old.intended_role or new.intended_theme is distinct from old.intended_theme
     or new.invited_email_normalized is distinct from old.invited_email_normalized
     or new.invited_phone_normalized is distinct from old.invited_phone_normalized
     or new.invited_by is distinct from old.invited_by or new.token_digest is distinct from old.token_digest
     or new.accepted_by is distinct from old.accepted_by or new.accepted_at is distinct from old.accepted_at then
    new.version:=old.version+1;
    new.updated_at:=statement_timestamp();
  else
    new.version:=old.version;
    new.updated_at:=old.updated_at;
  end if;
  return new;
end $$;
create trigger family_invitation_lifecycle_revision before update on family_invitation
  for each row execute function invitation_lifecycle_revision();

create table family_lifecycle_mutation (
  actor_user_id uuid not null references app_user(id) on delete cascade,
  mutation_id uuid not null,
  family_id uuid not null references family_workspace(id) on delete cascade,
  operation text not null check(operation in ('role','admin_transfer','invitation_revoke')),
  request_hash text not null check(request_hash~'^[0-9a-f]{64}$'),
  target_id uuid not null,
  accepted_at timestamptz not null default now(),
  primary key(actor_user_id,mutation_id)
);

commit;
$qa_original_0018$,'UTF8'),'sha256'),'hex'));
-- Original LifeGuide migration 0019_school_lifecycle.sql


alter table life_context add column version integer not null default 1 check(version>0);
alter table life_context add column updated_at timestamptz not null default now();
alter table academic_year add column version integer not null default 1 check(version>0);
alter table academic_year add column updated_at timestamptz not null default now();
alter table academic_term add column active boolean not null default true;
alter table academic_term add column version integer not null default 1 check(version>0);
alter table academic_term add column updated_at timestamptz not null default now();

create table school_lifecycle_mutation (
  owner_user_id uuid not null references app_user(id) on delete cascade,
  mutation_id uuid not null,
  entity_type text not null check(entity_type in('contexts','years','terms')),
  entity_id uuid not null,
  operation text not null check(operation in('create','update','archive')),
  request_hash text not null check(char_length(request_hash)=64),
  applied_version integer not null check(applied_version>0),
  accepted_at timestamptz not null default now(),
  primary key(owner_user_id,mutation_id)
);

-- The same owner-row lock is used by the new router and these guards. It
-- serializes ancestor archival/date edits against the old create APIs too.
create function school_lifecycle_context_guard() returns trigger language plpgsql set search_path=lifeguide_qa,pg_catalog as $$
begin
  perform 1 from app_user where id=new.user_id for update;
  if tg_op='UPDATE' then
    if new.user_id<>old.user_id then raise exception 'school_owner_immutable' using errcode='23514'; end if;
    if new.kind<>old.kind and exists(select 1 from academic_year where life_context_id=old.id) then
      raise exception 'school_context_kind_in_use' using errcode='23514';
    end if;
    new.version=old.version+1; new.updated_at=clock_timestamp();
  end if;
  return new;
end $$;
create trigger school_lifecycle_context_guard before insert or update on life_context for each row execute function school_lifecycle_context_guard();

create function school_lifecycle_year_guard() returns trigger language plpgsql set search_path=lifeguide_qa,pg_catalog as $$
declare context_row life_context;
begin
  perform 1 from app_user where id=new.student_user_id for update;
  if tg_op='UPDATE' and (new.student_user_id<>old.student_user_id or new.life_context_id<>old.life_context_id) then
    raise exception 'school_parent_immutable' using errcode='23514';
  end if;
  select * into context_row from life_context where id=new.life_context_id for share;
  if context_row.id is null or context_row.user_id<>new.student_user_id or context_row.kind<>'student' then
    raise exception 'school_parent_forbidden' using errcode='23514';
  end if;
  if new.active and not context_row.active then raise exception 'school_parent_inactive' using errcode='23514'; end if;
  if char_length(trim(new.title)) not between 1 and 120 then raise exception 'school_invalid_title' using errcode='23514'; end if;
  if tg_op='UPDATE' then
    if exists(select 1 from academic_term where academic_year_id=old.id and (starts_on<new.starts_on or ends_on>new.ends_on)) then
      raise exception 'school_dates_in_use' using errcode='23514';
    end if;
    new.version=old.version+1; new.updated_at=clock_timestamp();
  end if;
  return new;
end $$;
create trigger school_lifecycle_year_guard before insert or update on academic_year for each row execute function school_lifecycle_year_guard();

create function school_lifecycle_term_guard() returns trigger language plpgsql set search_path=lifeguide_qa,pg_catalog as $$
declare year_row academic_year; context_row life_context;
begin
  select * into year_row from academic_year where id=new.academic_year_id;
  perform 1 from app_user where id=year_row.student_user_id for update;
  select * into year_row from academic_year where id=new.academic_year_id for share;
  select * into context_row from life_context where id=year_row.life_context_id for share;
  if tg_op='UPDATE' and new.academic_year_id<>old.academic_year_id then raise exception 'school_parent_immutable' using errcode='23514'; end if;
  if year_row.id is null or context_row.id is null or context_row.user_id<>year_row.student_user_id or context_row.kind<>'student' then
    raise exception 'school_parent_forbidden' using errcode='23514';
  end if;
  if new.active and (not year_row.active or not context_row.active) then raise exception 'school_parent_inactive' using errcode='23514'; end if;
  if new.starts_on<year_row.starts_on or new.ends_on>year_row.ends_on then raise exception 'school_dates_outside_parent' using errcode='23514'; end if;
  if char_length(trim(new.title)) not between 1 and 120 then raise exception 'school_invalid_title' using errcode='23514'; end if;
  if tg_op='UPDATE' then
    if exists(select 1 from class_session c join subject s on s.id=c.subject_id where s.academic_term_id=old.id and c.recurrence_until is not null and (c.recurrence_until<new.starts_on or c.recurrence_until>new.ends_on)) then
      raise exception 'school_dates_in_use' using errcode='23514';
    end if;
    new.version=old.version+1; new.updated_at=clock_timestamp();
  end if;
  return new;
end $$;
create trigger school_lifecycle_term_guard before insert or update on academic_term for each row execute function school_lifecycle_term_guard();

create function school_lifecycle_subject_guard() returns trigger language plpgsql set search_path=lifeguide_qa,pg_catalog as $$
declare parent_row record;
begin
  perform 1 from app_user where id=new.student_user_id for update;
  if tg_op='UPDATE' and new.student_user_id<>old.student_user_id then raise exception 'school_owner_immutable' using errcode='23514'; end if;
  select t.active as term_active,y.active as year_active,l.active as context_active,y.student_user_id,l.user_id,l.kind
    into parent_row from academic_term t join academic_year y on y.id=t.academic_year_id join life_context l on l.id=y.life_context_id where t.id=new.academic_term_id for share of t,y,l;
  if not found or parent_row.student_user_id<>new.student_user_id or parent_row.user_id<>new.student_user_id then
    raise exception 'school_parent_forbidden' using errcode='23514';
  end if;
  if new.archived_at is null and (not parent_row.term_active or not parent_row.year_active or not parent_row.context_active or parent_row.kind<>'student') then
    raise exception 'school_parent_inactive' using errcode='23514';
  end if;
  return new;
end $$;
create trigger school_lifecycle_subject_guard before insert or update on subject for each row execute function school_lifecycle_subject_guard();

create function school_lifecycle_class_guard() returns trigger language plpgsql set search_path=lifeguide_qa,pg_catalog as $$
declare parent_row record; owner_id uuid;
begin
  select student_user_id into owner_id from subject where id=new.subject_id;
  perform 1 from app_user where id=owner_id for update;
  select s.archived_at,t.active as term_active,y.active as year_active,l.active as context_active,t.starts_on,t.ends_on
    into parent_row from subject s join academic_term t on t.id=s.academic_term_id join academic_year y on y.id=t.academic_year_id join life_context l on l.id=y.life_context_id where s.id=new.subject_id for share of s,t,y,l;
  if not found then raise exception 'school_parent_forbidden' using errcode='23514'; end if;
  if new.archived_at is null then
    if parent_row.archived_at is not null or not parent_row.term_active or not parent_row.year_active or not parent_row.context_active then
      raise exception 'school_parent_inactive' using errcode='23514';
    end if;
    if new.recurrence_until is not null and (new.recurrence_until<parent_row.starts_on or new.recurrence_until>parent_row.ends_on) then
      raise exception 'school_dates_outside_parent' using errcode='23514';
    end if;
  end if;
  return new;
end $$;
create trigger school_lifecycle_class_guard before insert or update on class_session for each row execute function school_lifecycle_class_guard();


insert into lifeguide_qa.schema_migration(filename,sha256)
values ('0019_school_lifecycle.sql',encode(digest(convert_to($qa_original_0019$begin;

alter table life_context add column version integer not null default 1 check(version>0);
alter table life_context add column updated_at timestamptz not null default now();
alter table academic_year add column version integer not null default 1 check(version>0);
alter table academic_year add column updated_at timestamptz not null default now();
alter table academic_term add column active boolean not null default true;
alter table academic_term add column version integer not null default 1 check(version>0);
alter table academic_term add column updated_at timestamptz not null default now();

create table school_lifecycle_mutation (
  owner_user_id uuid not null references app_user(id) on delete cascade,
  mutation_id uuid not null,
  entity_type text not null check(entity_type in('contexts','years','terms')),
  entity_id uuid not null,
  operation text not null check(operation in('create','update','archive')),
  request_hash text not null check(char_length(request_hash)=64),
  applied_version integer not null check(applied_version>0),
  accepted_at timestamptz not null default now(),
  primary key(owner_user_id,mutation_id)
);

-- The same owner-row lock is used by the new router and these guards. It
-- serializes ancestor archival/date edits against the old create APIs too.
create function school_lifecycle_context_guard() returns trigger language plpgsql set search_path=public,pg_catalog as $$
begin
  perform 1 from app_user where id=new.user_id for update;
  if tg_op='UPDATE' then
    if new.user_id<>old.user_id then raise exception 'school_owner_immutable' using errcode='23514'; end if;
    if new.kind<>old.kind and exists(select 1 from academic_year where life_context_id=old.id) then
      raise exception 'school_context_kind_in_use' using errcode='23514';
    end if;
    new.version=old.version+1; new.updated_at=clock_timestamp();
  end if;
  return new;
end $$;
create trigger school_lifecycle_context_guard before insert or update on life_context for each row execute function school_lifecycle_context_guard();

create function school_lifecycle_year_guard() returns trigger language plpgsql set search_path=public,pg_catalog as $$
declare context_row life_context;
begin
  perform 1 from app_user where id=new.student_user_id for update;
  if tg_op='UPDATE' and (new.student_user_id<>old.student_user_id or new.life_context_id<>old.life_context_id) then
    raise exception 'school_parent_immutable' using errcode='23514';
  end if;
  select * into context_row from life_context where id=new.life_context_id for share;
  if context_row.id is null or context_row.user_id<>new.student_user_id or context_row.kind<>'student' then
    raise exception 'school_parent_forbidden' using errcode='23514';
  end if;
  if new.active and not context_row.active then raise exception 'school_parent_inactive' using errcode='23514'; end if;
  if char_length(trim(new.title)) not between 1 and 120 then raise exception 'school_invalid_title' using errcode='23514'; end if;
  if tg_op='UPDATE' then
    if exists(select 1 from academic_term where academic_year_id=old.id and (starts_on<new.starts_on or ends_on>new.ends_on)) then
      raise exception 'school_dates_in_use' using errcode='23514';
    end if;
    new.version=old.version+1; new.updated_at=clock_timestamp();
  end if;
  return new;
end $$;
create trigger school_lifecycle_year_guard before insert or update on academic_year for each row execute function school_lifecycle_year_guard();

create function school_lifecycle_term_guard() returns trigger language plpgsql set search_path=public,pg_catalog as $$
declare year_row academic_year; context_row life_context;
begin
  select * into year_row from academic_year where id=new.academic_year_id;
  perform 1 from app_user where id=year_row.student_user_id for update;
  select * into year_row from academic_year where id=new.academic_year_id for share;
  select * into context_row from life_context where id=year_row.life_context_id for share;
  if tg_op='UPDATE' and new.academic_year_id<>old.academic_year_id then raise exception 'school_parent_immutable' using errcode='23514'; end if;
  if year_row.id is null or context_row.id is null or context_row.user_id<>year_row.student_user_id or context_row.kind<>'student' then
    raise exception 'school_parent_forbidden' using errcode='23514';
  end if;
  if new.active and (not year_row.active or not context_row.active) then raise exception 'school_parent_inactive' using errcode='23514'; end if;
  if new.starts_on<year_row.starts_on or new.ends_on>year_row.ends_on then raise exception 'school_dates_outside_parent' using errcode='23514'; end if;
  if char_length(trim(new.title)) not between 1 and 120 then raise exception 'school_invalid_title' using errcode='23514'; end if;
  if tg_op='UPDATE' then
    if exists(select 1 from class_session c join subject s on s.id=c.subject_id where s.academic_term_id=old.id and c.recurrence_until is not null and (c.recurrence_until<new.starts_on or c.recurrence_until>new.ends_on)) then
      raise exception 'school_dates_in_use' using errcode='23514';
    end if;
    new.version=old.version+1; new.updated_at=clock_timestamp();
  end if;
  return new;
end $$;
create trigger school_lifecycle_term_guard before insert or update on academic_term for each row execute function school_lifecycle_term_guard();

create function school_lifecycle_subject_guard() returns trigger language plpgsql set search_path=public,pg_catalog as $$
declare parent_row record;
begin
  perform 1 from app_user where id=new.student_user_id for update;
  if tg_op='UPDATE' and new.student_user_id<>old.student_user_id then raise exception 'school_owner_immutable' using errcode='23514'; end if;
  select t.active as term_active,y.active as year_active,l.active as context_active,y.student_user_id,l.user_id,l.kind
    into parent_row from academic_term t join academic_year y on y.id=t.academic_year_id join life_context l on l.id=y.life_context_id where t.id=new.academic_term_id for share of t,y,l;
  if not found or parent_row.student_user_id<>new.student_user_id or parent_row.user_id<>new.student_user_id then
    raise exception 'school_parent_forbidden' using errcode='23514';
  end if;
  if new.archived_at is null and (not parent_row.term_active or not parent_row.year_active or not parent_row.context_active or parent_row.kind<>'student') then
    raise exception 'school_parent_inactive' using errcode='23514';
  end if;
  return new;
end $$;
create trigger school_lifecycle_subject_guard before insert or update on subject for each row execute function school_lifecycle_subject_guard();

create function school_lifecycle_class_guard() returns trigger language plpgsql set search_path=public,pg_catalog as $$
declare parent_row record; owner_id uuid;
begin
  select student_user_id into owner_id from subject where id=new.subject_id;
  perform 1 from app_user where id=owner_id for update;
  select s.archived_at,t.active as term_active,y.active as year_active,l.active as context_active,t.starts_on,t.ends_on
    into parent_row from subject s join academic_term t on t.id=s.academic_term_id join academic_year y on y.id=t.academic_year_id join life_context l on l.id=y.life_context_id where s.id=new.subject_id for share of s,t,y,l;
  if not found then raise exception 'school_parent_forbidden' using errcode='23514'; end if;
  if new.archived_at is null then
    if parent_row.archived_at is not null or not parent_row.term_active or not parent_row.year_active or not parent_row.context_active then
      raise exception 'school_parent_inactive' using errcode='23514';
    end if;
    if new.recurrence_until is not null and (new.recurrence_until<parent_row.starts_on or new.recurrence_until>parent_row.ends_on) then
      raise exception 'school_dates_outside_parent' using errcode='23514';
    end if;
  end if;
  return new;
end $$;
create trigger school_lifecycle_class_guard before insert or update on class_session for each row execute function school_lifecycle_class_guard();

commit;
$qa_original_0019$,'UTF8'),'sha256'),'hex'));
-- Original LifeGuide migration 0020_content_publication_audit.sql


-- Identifier/hash-only journal. No chosen feedback, reviewer prose or private
-- learner data is copied. HTTP runtime receives SELECT only on this table.
create table content_publication_audit (
  mutation_id uuid primary key,
  entity_type text not null check(entity_type in ('video','assessment')),
  entity_id uuid not null,
  operation text not null check(operation in ('publish','withdraw','draft_assessment')),
  request_hash text not null check(request_hash ~ '^[a-f0-9]{64}$'),
  applied_content_hash text not null check(applied_content_hash ~ '^[a-f0-9]{64}$'),
  applied_context_hash text not null check(applied_context_hash ~ '^[a-f0-9]{64}$'),
  applied_version integer check(applied_version is null or applied_version>0),
  applied_status text not null check(applied_status in ('draft','published','withdrawn')),
  operator_role text not null,
  accepted_at timestamptz not null default statement_timestamp(),
  synthetic_only boolean not null default true check(synthetic_only)
);


insert into lifeguide_qa.schema_migration(filename,sha256)
values ('0020_content_publication_audit.sql',encode(digest(convert_to($qa_original_0020$begin;

-- Identifier/hash-only journal. No chosen feedback, reviewer prose or private
-- learner data is copied. HTTP runtime receives SELECT only on this table.
create table content_publication_audit (
  mutation_id uuid primary key,
  entity_type text not null check(entity_type in ('video','assessment')),
  entity_id uuid not null,
  operation text not null check(operation in ('publish','withdraw','draft_assessment')),
  request_hash text not null check(request_hash ~ '^[a-f0-9]{64}$'),
  applied_content_hash text not null check(applied_content_hash ~ '^[a-f0-9]{64}$'),
  applied_context_hash text not null check(applied_context_hash ~ '^[a-f0-9]{64}$'),
  applied_version integer check(applied_version is null or applied_version>0),
  applied_status text not null check(applied_status in ('draft','published','withdrawn')),
  operator_role text not null,
  accepted_at timestamptz not null default statement_timestamp(),
  synthetic_only boolean not null default true check(synthetic_only)
);

commit;
$qa_original_0020$,'UTF8'),'sha256'),'hex'));
revoke all on schema lifeguide_qa from public,anon,authenticated,service_role;
revoke all on all tables in schema lifeguide_qa from public,anon,authenticated,service_role;
revoke all on all sequences in schema lifeguide_qa from public,anon,authenticated,service_role;
revoke all on all functions in schema lifeguide_qa from public,anon,authenticated,service_role;
alter default privileges in schema lifeguide_qa revoke all on tables from public,anon,authenticated,service_role;
alter default privileges in schema lifeguide_qa revoke all on sequences from public,anon,authenticated,service_role;
alter default privileges in schema lifeguide_qa revoke execute on functions from public,anon,authenticated,service_role;
do $lockdown$ declare rowrecord record; begin
 for rowrecord in select c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace
 where n.nspname='lifeguide_qa' and c.relkind in ('r','p') loop
 execute format('alter table %I.%I enable row level security','lifeguide_qa',rowrecord.relname);
 execute format('alter table %I.%I force row level security','lifeguide_qa',rowrecord.relname);
 end loop;
end $lockdown$;
commit;