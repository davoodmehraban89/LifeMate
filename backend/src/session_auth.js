import jwt from 'jsonwebtoken';
import { childSandboxEnabled, childSessionRouteAllowed, managedChildAccessActive } from './child_session_policy.js';

// Every API router must check both the session and the current account state.
export function createSessionAuth({ pool, jwtSecret, env = process.env }) {
  return async (req, res, next) => {
    const raw = req.headers.authorization?.replace(/^Bearer\s+/i, '');
    try {
      const identity = jwt.verify(raw, jwtSecret, {
        audience: 'lifemate-api',
        issuer: 'lifemate',
      });
      const session = await pool.query(
        `select s.access_scope,s.child_issuer_user_id,u.is_managed_child
         from auth_session s join app_user u on u.id=s.user_id
         where s.id=$1 and s.user_id=$2 and s.revoked_at is null
           and s.expires_at>now() and u.disabled_at is null`,
        [identity.sid, identity.sub],
      );
      if (!session.rowCount) return res.status(401).json({ error: 'session_invalid' });
      const row = session.rows[0];
      if (row.is_managed_child || row.access_scope === 'child_education') {
        res.setHeader('Cache-Control', 'no-store');
        if (!childSandboxEnabled(env)) return res.status(503).json({ error: 'child_identity_sandbox_disabled' });
        if (!row.is_managed_child || row.access_scope !== 'child_education') return res.status(401).json({ error: 'session_invalid' });
        if (!await managedChildAccessActive(pool, identity.sub, row.child_issuer_user_id, env)) return res.status(401).json({ error: 'session_invalid' });
        if (!childSessionRouteAllowed(req)) return res.status(403).json({ error: 'child_session_scope_denied' });
      }
      // Claims supplied in a JWT cannot override the database scope/marker.
      identity.accessScope = row.access_scope;
      identity.managedChild = row.is_managed_child === true;
      req.identity = identity;
      next();
    } catch {
      res.status(401).json({ error: 'unauthorized' });
    }
  };
}
