import jwt from 'jsonwebtoken';

// Every API router must check both the session and the current account state.
export function createSessionAuth({ pool, jwtSecret }) {
  return async (req, res, next) => {
    const raw = req.headers.authorization?.replace(/^Bearer\s+/i, '');
    try {
      const identity = jwt.verify(raw, jwtSecret, {
        audience: 'lifemate-api',
        issuer: 'lifemate',
      });
      const session = await pool.query(
        `select 1 from auth_session s join app_user u on u.id=s.user_id
         where s.id=$1 and s.user_id=$2 and s.revoked_at is null
           and s.expires_at>now() and u.disabled_at is null`,
        [identity.sid, identity.sub],
      );
      if (!session.rowCount) return res.status(401).json({ error: 'session_invalid' });
      req.identity = identity;
      next();
    } catch {
      res.status(401).json({ error: 'unauthorized' });
    }
  };
}
