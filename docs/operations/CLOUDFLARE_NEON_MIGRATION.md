# Cloudflare Workers + Neon PostgreSQL migration

## Target
Life Guide clients -> Cloudflare Workers API -> Neon PostgreSQL. Railway remains rollback-only until the new path passes staging verification.

## Required secrets
Configure these as Cloudflare Worker secrets, never client variables:
- NEON_DATABASE_URL: pooled Neon PostgreSQL connection string with TLS.
- JWT_SECRET: existing production JWT signing secret, minimum 32 characters.
- RESEND_API_KEY when transactional email is enabled.

Configure CORS_ORIGINS, PUBLIC_APP_URL and EMAIL_FROM as environment variables appropriate to the deployed application.

## Database migration
1. Freeze schema-changing deployments during cutover.
2. Create a Neon project/database and obtain the pooled PostgreSQL connection string.
3. Take a fresh Railway PostgreSQL backup with pg_dump in custom format.
4. Restore into Neon with pg_restore.
5. Run the repository migrations against Neon and verify all migrations are applied.
6. Compare critical row counts and constraints for identity, profiles, families, memberships, guardians, sessions, planner, school, learning and wellbeing data.
7. Keep the Railway database intact and read-only/rollback-capable until acceptance checks pass.

Example operator commands (credentials supplied securely by the operator):

    pg_dump --format=custom --no-owner --no-acl "$RAILWAY_DATABASE_URL" > lifeguide-cutover.dump
    pg_restore --clean --if-exists --no-owner --no-acl --dbname "$NEON_DATABASE_URL" lifeguide-cutover.dump
    DATABASE_URL="$NEON_DATABASE_URL" npm run migrate

## Cloudflare Workers deployment
The Worker entrypoint is backend/src/worker.js and deployment configuration is backend/wrangler.jsonc. It reuses the existing Express API through Cloudflare's Node HTTP server adapter. PostgreSQL remains behind the server API; no database credentials are exposed to Flutter or the PWA.

Before deployment set Worker secrets NEON_DATABASE_URL and JWT_SECRET. Use the existing JWT secret during migration so valid sessions are not invalidated solely by infrastructure cutover.

## Acceptance checks
- /live returns 200.
- /ready returns 200 and database=ready.
- /health returns 200 against Neon.
- Authentication registration/verification/login/refresh/recovery tests pass.
- Family create/invite/guardian authorization tests pass.
- Planner, school, learning, wellbeing and privacy-boundary tests pass.
- PWA and Android staging clients use the Cloudflare API endpoint successfully.
- CORS permits only approved origins.
- Logs contain no database URLs, tokens, passwords or minor-sensitive content.

## Cutover and rollback
Do not delete Railway before acceptance. Point staging clients to Cloudflare first. After successful end-to-end verification, change production API routing to Cloudflare. Keep Railway available for a defined rollback window. If critical API/database verification fails, restore the previous client/API route to Railway and investigate without modifying the Neon copy destructively.

Railway removal is the final cleanup step only after the Cloudflare Workers + Neon PostgreSQL path is verified and explicit production cutover approval has been given.
