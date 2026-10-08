import express from 'express';
import { operationalErrorHandler, requestContext } from '../../src/operations.js';

// Exercise the actual error middleware over HTTP after response headers are sent.
const app = express();
app.use(requestContext);
let failStream;
let streamRequestId;
app.get('/partial-error', (req, res, next) => {
  streamRequestId = req.requestId;
  failStream = () => next(new Error(process.env.STREAM_ERROR_MARKER));
  res.setHeader('Content-Type', 'text/plain');
  res.write('started');
});
app.post('/trigger-error', (_req, res) => {
  res.status(204).end();
  failStream();
  // Express schedules fallback error logging during next(err). This later
  // callback lets the client wait for that logging opportunity before shutdown.
  setImmediate(() => console.error(JSON.stringify({ type: 'stream_error_drained', requestId: streamRequestId })));
});
app.use(operationalErrorHandler);
const server = app.listen(0, '127.0.0.1', () => {
  console.log(JSON.stringify({ type: 'stream_fixture_ready', port: server.address().port }));
});
