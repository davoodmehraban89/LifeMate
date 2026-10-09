const publicPort = Number(process.env.PORT ?? 8080);
process.env.NODE_ENV = process.env.NODE_ENV || 'production';
import express from 'express';
import {
  configureTrustedProxy,
  operationalErrorHandler,
  rateLimit,
  requestContext,
  requestTelemetry,
} from './operations.js';

const { app, pool } = await import('./server.js');

const outer = express();
outer.disable('x-powered-by');
configureTrustedProxy(outer);
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
outer.listen(publicPort, () => console.log(JSON.stringify({ type: 'startup', service: 'lifemate-api', port: publicPort })));
