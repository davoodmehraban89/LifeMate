begin;
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
