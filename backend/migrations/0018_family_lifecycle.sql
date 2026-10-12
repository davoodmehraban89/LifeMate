begin;

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
