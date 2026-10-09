# ADR0011 — Stage 0 credential and browser isolation

Date:2026-10-09. Status: accepted for local synthetic engineering/PR scope. This decision does not authorize any live privilege transition, deployment or real-data migration.

## Context

The shared online stack already implements identity, family authorization, planner and stable offline mutations. Its Compose API still used the bootstrap database administrator. Multiple browser documents could also rotate the same refresh token or rewrite one durable queue concurrently. A compiled-client regression showed that a delayed refresh followed by forced expiry could erase an unsent mutation.

## Decision

Keep one Express/PostgreSQL backend and existing protocol/schema identifiers. Use separate canonical `lifeguide_migrator`, `lifeguide_api` and `lifeguide_backup` credentials, with bootstrap available only to short-lived provisioning/operator jobs. Migrator owns application objects without superuser/database ownership; API gets required DML/functions without DDL or migration-ledger writes; backup only reads. Preflight rejects excessive existing privileges/ownership before changes. Existing object ownership transfer requires stopped writers, an explicit previous owner and a fresh validated backup; no wildcard ownership repair or automatic live transition.

For each secure origin/browser profile, acquire the exclusive `lifeguide.active-instance.v1` Web Lock before loading Flutter or accessing runtime config, credentials, cache and sync. Hold it for document lifetime, including background use. A second or unsupported instance stops with a Persian retry screen. Lifecycle guards reject stale document responses and storage access. This is deliberately simpler than token/queue sharing between tabs; independent devices still synchronize through the server.

Forced expiry clears credentials and active access, invalidates old store handles, and quarantines durable account/endpoint data without changing its bytes. Recovery requires authenticating the same account against the same endpoint. Another account cannot read/replay it. Deliberate logout or endpoint changes retain their explicit discard policy.

## Consequences and verification

Separate secrets and the provisioning → migrate → grants order become operational requirements. A dedicated database/cluster is the supported baseline; unrelated database/schema privilege repair needs separate review. Default privileges and future application functions need intentional migration review. Database roles reduce credential blast radius and do not replace server-side user/family authorization or create tenant RLS.

Close all old browser documents once on upgrade because old code cannot be retroactively locked. Web Locks compatibility, real Safari installation, true BFCache restoration, encrypted off-PC backups and real-host role transition remain UNVERIFIED until their own execution. See [design](../superpowers/specs/2026-10-09-stage0-isolation-hardening-design.md), [role runbook](../operations/DATABASE_ROLES.md) and [actual evidence](../audits/2026-10-09-isolation-verification.md).
