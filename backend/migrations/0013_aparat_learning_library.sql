begin;
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
