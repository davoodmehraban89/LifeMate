import crypto from 'node:crypto';
import { isIP } from 'node:net';
import { rateLimitProfile } from './operations.js';

const digestDomain = 'lifeguide:auth-ip:v1\0';

function canonicalIp(value) {
  const address = String(value ?? '');
  if (isIP(address) === 4) return address;
  if (isIP(address) !== 6) throw new Error('Invalid client address');
  const canonical = new URL(`http://[${address}]`).hostname.slice(1, -1);
  // Socket addresses can represent the same IPv4 client as mapped IPv6.
  const mapped = /^::ffff:([a-f0-9]{1,4}):([a-f0-9]{1,4})$/.exec(canonical);
  if (!mapped) return canonical;
  const upper = Number.parseInt(mapped[1], 16), lower = Number.parseInt(mapped[2], 16);
  return `${upper >> 8}.${upper & 255}.${lower >> 8}.${lower & 255}`;
}

/** Shared fixed-window budgets for auth and session routes. Forwarded headers
 * are deliberately never read here: Express req.ip reflects the separately
 * validated, operator-pinned trusted-proxy configuration.
 */
export function createAuthIpRateLimit({ pool, jwtSecret, env = process.env }) {
  if (typeof jwtSecret !== 'string' || jwtSecret.length < 32) throw new Error('Invalid auth limiter signing secret');
  return async function authIpRateLimit(req, res, next) {
    if (env.NODE_ENV === 'test' || req.method === 'OPTIONS') return next();
    const profile = rateLimitProfile(req, env);
    if (!['auth', 'session'].includes(profile.name)) return next();
    let client;
    try {
      const digest = crypto.createHmac('sha256', jwtSecret).update(digestDomain)
        .update(canonicalIp(req.ip || req.socket?.remoteAddress)).digest('hex');
      client = await pool.connect();
      await client.query("begin; set local lock_timeout='2s'; set local statement_timeout='3s'");
      // Lock the stable digest/profile, not a precomputed window. A waiting
      // request samples the PostgreSQL clock only after acquiring this lock.
      await client.query("select pg_advisory_xact_lock(hashtextextended('lifeguide:auth-ip:' || $1 || ':' || $2,0))", [profile.name, digest]);
      const result = await client.query(`
        with clock as (select statement_timestamp() as instant),
        quota_window as (select to_timestamp(floor(extract(epoch from instant)/$3::integer)*$3::integer) as start from clock)
        insert into auth_ip_rate_limit(quota_profile,client_digest,window_start,window_end,request_count)
        select $1,$2,start,start+make_interval(secs=>$3::integer),1 from quota_window
        on conflict(quota_profile,client_digest,window_start) do update
          set request_count=auth_ip_rate_limit.request_count+1
        returning request_count,
          greatest(1,ceil(extract(epoch from window_end-statement_timestamp())))::integer as retry_after`,
      [profile.name, digest, profile.windowSeconds]);
      await client.query('commit');
      const row = result.rows[0];
      const count = Number(row.request_count);
      // The in-memory middleware must not charge these routes a second time.
      req.authRateLimitCharged = true;
      res.setHeader('RateLimit-Limit', String(profile.limit));
      res.setHeader('RateLimit-Remaining', String(Math.max(0, profile.limit - count)));
      if (count > profile.limit) {
        res.setHeader('Retry-After', String(row.retry_after));
        return res.status(429).json({ error: 'rate_limited' });
      }
      return next();
    } catch {
      if (client) await client.query('rollback').catch(() => {});
      // Database/key/address failures never fall back to a per-process quota.
      // Do not expose or log connection strings, raw IPs, or PostgreSQL errors.
      res.setHeader('Retry-After', '5');
      return res.status(503).json({ error: 'temporarily_unavailable' });
    } finally { client?.release(); }
  };
}

/** Explicit local/operator housekeeping hook; no timer, worker or external
 * scheduler is started. Each call deletes at most 500 expired metadata rows.
 * Current windows are retained, so housekeeping cannot reopen an active quota.
 */
export async function pruneExpiredAuthRateLimits(pool, batchSize = 500) {
  if (!Number.isInteger(batchSize) || batchSize < 1 || batchSize > 500) throw new Error('Invalid auth limiter cleanup batch');
  const result = await pool.query(`with expired as (
    select quota_profile,client_digest,window_start from auth_ip_rate_limit
    where window_end<=statement_timestamp() order by window_end
    limit $1 for update skip locked
  ) delete from auth_ip_rate_limit b using expired e
    where b.quota_profile=e.quota_profile and b.client_digest=e.client_digest and b.window_start=e.window_start`, [batchSize]);
  return result.rowCount;
}
