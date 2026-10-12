begin;

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
