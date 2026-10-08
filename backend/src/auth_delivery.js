import crypto from 'node:crypto';
import nodemailer from 'nodemailer';

// Provider ports have no authority to create/verify users or issue sessions.
export class SmsProvider {
  configured = false;
  status = 'UNVERIFIED';
  async sendOtp(_message) { return { delivered: false, reason: 'provider_unconfigured' }; }
}

export function createSmsProvider() {
  // No SMS carrier is selected or enabled. A real adapter needs explicit setup.
  return new SmsProvider();
}

export function createEmailProvider({ env = process.env, fetchImpl = fetch, transportFactory = nodemailer.createTransport } = {}) {
  const configured = env.NODE_ENV !== 'test' && Boolean(env.EMAIL_FROM && (env.RESEND_API_KEY || (env.SMTP_HOST && Number(env.SMTP_PORT) > 0)));
  return {
    configured,
    status: configured ? 'CONFIGURED_UNVERIFIED' : 'UNVERIFIED',
    async send({ to, subject, text, idempotencyKey }) {
      if (!configured) return { delivered: false, reason: 'provider_unconfigured' };
      if (env.RESEND_API_KEY) {
        const response = await fetchImpl('https://api.resend.com/emails', {
          method: 'POST', signal: AbortSignal.timeout(10000),
          headers: { Authorization: `Bearer ${env.RESEND_API_KEY}`, 'Content-Type': 'application/json', 'Idempotency-Key': idempotencyKey },
          body: JSON.stringify({ from: env.EMAIL_FROM, to: [to], subject, text }),
        });
        if (!response.ok) {
          const error = new Error('email_provider_rejected');
          error.retryable = response.status === 429 || response.status >= 500;
          throw error;
        }
        return { delivered: true };
      }
      const transport = transportFactory({
        host: env.SMTP_HOST, port: Number(env.SMTP_PORT), secure: env.SMTP_SECURE === 'true',
        connectionTimeout: 10000, greetingTimeout: 10000, socketTimeout: 10000,
        logger: false, debug: false,
        auth: env.SMTP_USER ? { user: env.SMTP_USER, pass: env.SMTP_PASSWORD } : undefined,
      });
      try {
        await transport.sendMail({ from: env.EMAIL_FROM, to, subject, text, messageId: `<${idempotencyKey}@lifeguide.invalid>` });
        return { delivered: true };
      } finally { transport.close?.(); }
    },
  };
}

export async function safelyDeliver(provider, message, { pool, attemptId, env = process.env } = {}) {
  let status = 'unconfigured';
  const idempotencyKey = attemptId ?? crypto.randomUUID();
  if (provider.configured) {
    for (let attempt = 0; attempt < 3; attempt++) {
      try {
        const result = await provider.send({ ...message, idempotencyKey });
        status = result?.delivered === true ? 'accepted' : 'failed';
        break;
      } catch (error) {
        status = 'failed';
        if (error?.retryable !== true || attempt === 2) break;
        await new Promise((resolve) => setTimeout(resolve, 250 * (2 ** attempt)));
      }
    }
  }
  if (pool && attemptId) {
    try { await pool.query('update auth_delivery_attempt set status=$2,updated_at=now() where id=$1', [attemptId, status]); }
    catch { /* Account/token is already committed; delivery bookkeeping cannot undo it. */ }
  }
  if (env.NODE_ENV !== 'test') {
    // Never serialize provider errors, recipients, tokens, message text or OTPs.
    console.log(JSON.stringify({ type: 'auth_delivery', status, attemptId: idempotencyKey }));
  }
  return { delivered: status === 'accepted', status };
}
