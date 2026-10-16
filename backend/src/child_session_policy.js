// Experimental identity work is deliberately unavailable in production.
// This switch is not a consent policy or permission to use real child data.
export const childSandboxEnabled = env => ['test', 'development'].includes(env.NODE_ENV)
  && env.ENABLE_CHILD_IDENTITY_SANDBOX === 'true';

export async function managedChildAccessActive(client, userId, issuerId, env) {
  if (!childSandboxEnabled(env) || !issuerId) return false;
  return (await client.query(`select 1 from managed_child mc
    join child_consent cc on cc.child_user_id=mc.user_id and cc.revoked_at is null
    join app_user u on u.id=mc.user_id and u.disabled_at is null and u.is_managed_child
    join family_workspace f on f.id=mc.family_id and f.archived_at is null
    join family_membership m on m.family_id=mc.family_id and m.user_id=mc.user_id
      and m.ended_at is null and m.role='teen_minor' and not m.is_admin
    where mc.user_id=$1 and is_active_guardian(mc.family_id,$2,mc.user_id)`, [userId, issuerId])).rowCount > 0;
}

export function childSessionRouteAllowed(req) {
  if (req.method !== 'GET') return false;
  // Compare literal original paths: encoded/case/slash variants never expand
  // these permissions. Avoid router-relative req.path and prefix wildcards.
  const path = (req.originalUrl ?? req.url ?? '').split('?')[0];
  return ['/v1/profile', '/v1/families', '/v1/child-visibility',
    '/v1/education/catalog', '/v1/calendar/iran'].includes(path)
    || /^\/v1\/education\/units\/[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}(?:\/assessment)?$/i.test(path)
      && path.startsWith('/v1/education/units/');
}
