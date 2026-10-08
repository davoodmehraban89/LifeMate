import crypto from 'node:crypto';

const buckets = new Map();
const nowSeconds = () => Math.floor(Date.now() / 1000);
const positiveInt = (value, fallback) => {
  const n = Number(value);
  return Number.isInteger(n) && n > 0 ? n : fallback;
};

export function requestContext(req, res, next) {
  const incoming = String(req.headers['x-request-id'] ?? '');
  const requestId = /^[A-Za-z0-9._:-]{8,128}$/.test(incoming)
    ? incoming
    : crypto.randomUUID();
  req.requestId = requestId;
  req.requestStartedAt = process.hrtime.bigint();
  res.setHeader('X-Request-Id', requestId);
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('X-Frame-Options', 'DENY');
  res.setHeader('Referrer-Policy', 'no-referrer');
  res.setHeader('Permissions-Policy', 'camera=(), microphone=(), geolocation=()');
  res.setHeader('Cross-Origin-Resource-Policy', 'same-site');
  next();
}

export function requestTelemetry(req, res, next) {
  res.on('finish', () => {
    if (process.env.NODE_ENV === 'test' || process.env.LOG_REQUESTS === 'false') return;
    const start = req.requestStartedAt ?? process.hrtime.bigint();
    const durationMs = Number(process.hrtime.bigint() - start) / 1e6;
    const event = {
      type: 'http_request',
      requestId: req.requestId,
      method: req.method,
      path: req.route?.path ?? req.path,
      status: res.statusCode,
      durationMs: Math.round(durationMs * 10) / 10,
    };
    console.log(JSON.stringify(event));
  });
  next();
}

function clientKey(req) {
  return req.socket?.remoteAddress || 'unknown';
}

function profileFor(req) {
  const path = req.path;
  if (path.startsWith('/v1/auth/')) {
    return {
      name: 'auth',
      limit: positiveInt(process.env.RATE_LIMIT_AUTH_MAX, 10),
      windowSeconds: positiveInt(process.env.RATE_LIMIT_AUTH_WINDOW_SECONDS, 10 * 60),
    };
  }
  if (/^\/v1\/ai\//.test(path) || /\/family-guidance$/.test(path)) {
    return {
      name: 'ai',
      limit: positiveInt(process.env.RATE_LIMIT_AI_MAX, 30),
      windowSeconds: positiveInt(process.env.RATE_LIMIT_AI_WINDOW_SECONDS, 10 * 60),
    };
  }
  return {
    name: 'general',
    limit: positiveInt(process.env.RATE_LIMIT_GENERAL_MAX, 120),
    windowSeconds: positiveInt(process.env.RATE_LIMIT_GENERAL_WINDOW_SECONDS, 60),
  };
}

export function rateLimit(req, res, next) {
  if (process.env.NODE_ENV === 'test' || req.method === 'OPTIONS' || req.path === '/live' || req.path === '/ready' || req.path === '/health') {
    return next();
  }
  const profile = profileFor(req);
  const now = nowSeconds();
  const windowStart = Math.floor(now / profile.windowSeconds) * profile.windowSeconds;
  const key = `${profile.name}:${clientKey(req)}:${windowStart}`;
  const count = (buckets.get(key) ?? 0) + 1;
  buckets.set(key, count);

  if (buckets.size > 10000) {
    for (const storedKey of buckets.keys()) {
      const storedWindow = Number(storedKey.split(':').at(-1));
      if (storedWindow + 3600 < now) buckets.delete(storedKey);
    }
  }

  const remaining = Math.max(0, profile.limit - count);
  res.setHeader('RateLimit-Limit', String(profile.limit));
  res.setHeader('RateLimit-Remaining', String(remaining));
  if (count > profile.limit) {
    const retryAfter = Math.max(1, windowStart + profile.windowSeconds - now);
    res.setHeader('Retry-After', String(retryAfter));
    return res.status(429).json({ error: 'rate_limited' });
  }
  next();
}

export function operationalErrorHandler(err, req, res, _next) {
  const event = {
    type: 'http_error',
    requestId: req.requestId,
    method: req.method,
    path: req.route?.path ?? req.path,
    errorClass: err?.name || 'Error',
  };
  if (process.env.NODE_ENV !== 'test') console.error(JSON.stringify(event));
  if (res.headersSent) {
    // Passing the original error to Express would print its raw message/stack.
    res.destroy();
    return;
  }
  if (err?.type === 'entity.parse.failed') {
    return res.status(400).json({ error: 'invalid_json', requestId: req.requestId });
  }
  if (err?.type === 'entity.too.large') {
    return res.status(413).json({ error: 'request_body_too_large', requestId: req.requestId });
  }
  if (err?.code === 'CORS_ORIGIN_DENIED') {
    return res.status(403).json({ error: 'cors_origin_denied', requestId: req.requestId });
  }
  res.status(500).json({ error: 'internal_error', requestId: req.requestId });
}
