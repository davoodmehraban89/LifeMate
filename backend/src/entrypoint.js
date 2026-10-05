const runtimeEnv = process.env.NODE_ENV || 'production';
process.env.NODE_ENV = 'test';
import express from 'express';
import {
  operationalErrorHandler,
  rateLimit,
  requestContext,
  requestTelemetry,
} from './operations.js';

const { app, pool } = await import('./server.js');
process.env.NODE_ENV = runtimeEnv;

const outer = express();
outer.disable('x-powered-by');
outer.use(requestContext);
outer.use(requestTelemetry);
outer.use(rateLimit);

outer.get('/live', (_req, res) => {
  res.json({ status: 'ok', service: 'lifemate-api' });
});

outer.get('/ready', async (_req, res) => {
  try {
    const result = await pool.query('select 1 as ok');
    if (result.rows[0]?.ok !== 1) return res.status(503).json({ status: 'degraded' });
    res.json({ status: 'ok', database: 'ready' });
  } catch {
    res.status(503).json({ status: 'degraded', database: 'unavailable' });
  }
});

outer.use(app);
outer.use(operationalErrorHandler);

const port = Number(process.env.PORT ?? 8080);
outer.listen(port, () => console.log(JSON.stringify({ type: 'startup', service: 'lifemate-api', port })));
