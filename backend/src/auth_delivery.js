import crypto from 'node:crypto';
import nodemailer from 'nodemailer';

// Provider ports have no authority to create/verify users or issue sessions.
export class SmsProvider {
  configured = false;
  status = 'UNVERIFIED';
  async sendOtp(_message) { return { delivered: false, reason: 'provider_unconfigured' }; }
}

class WebhookSmsProvider extends SmsProvider {
  configured = true;
  status = 'CONFIGURED_UNVERIFIED';
  #url; #token; #fetch; #timeout;
  constructor({ url, token, fetchImpl, timeoutMs }) {
    super();
    this.#url = url; this.#token = token; this.#fetch = fetchImpl; this.#timeout = timeoutMs;
  }
  async sendOtp({ phone, code, expiresIn, idempotencyKey }) {
    if (typeof phone !== 'string' || typeof code !== 'string' ||
        !/^\+[1-9]\d{7,14}$/.test(phone) || !/^\d{6}$/.test(code) ||
        !Number.isInteger(expiresIn) || expiresIn < 1 || expiresIn > 300 ||
        typeof idempotencyKey !== 'string' || !/^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$/i.test(idempotencyKey)) throw new Error('sms_provider_input_invalid');
    const signal = AbortSignal.timeout(this.#timeout);
    let response;
    try {
      response = await this.#fetch(this.#url, {
        method: 'POST', redirect: 'error', signal,
        headers: { Authorization: `Bearer ${this.#token}`, 'Content-Type': 'application/json', 'Idempotency-Key': idempotencyKey },
        body: JSON.stringify({ phone, code, expiresIn }),
      });
    } catch {
      const error = new Error(signal.aborted ? 'sms_provider_timeout' : 'sms_provider_unavailable');
      // Transport failure has uncertain acceptance; a later explicit retry is safer.
      error.retryable = false;
      throw error;
    }
    // Do not read or serialize a webhook response body, which may contain secrets.
    try { await response?.body?.cancel(); } catch { /* Discard only. */ }
    if (!response?.ok) {
      const error = new Error('sms_provider_rejected');
      error.retryable = response?.status === 429 || (response?.status >= 500 && response?.status <= 599);
      throw error;
    }
    // A 2xx confirms webhook acceptance, never handset delivery.
    return { delivered: true };
  }
}

export function createSmsProvider({ env = process.env, fetchImpl = fetch, timeoutMs = 10000 } = {}) {
  const selection = String(env.SMS_PROVIDER ?? '').trim().toLowerCase();
  if (['', 'none', 'disabled'].includes(selection)) return new SmsProvider();
  if (selection !== 'webhook') throw new Error('sms_provider_unsupported');
  let url;
  try { url = new URL(env.SMS_PROVIDER_URL); } catch { throw new Error('sms_provider_url_invalid'); }
  if (url.protocol !== 'https:' || !url.hostname || url.username || url.password || url.hash) throw new Error('sms_provider_url_invalid');
  const token = env.SMS_PROVIDER_TOKEN;
  if (typeof token !== 'string' || token.length < 32 || token.length > 4096 || !/^[A-Za-z0-9._~+/-]+=*$/.test(token)) throw new Error('sms_provider_token_invalid');
  const boundedTimeout = Number.isInteger(timeoutMs) && timeoutMs > 0 && timeoutMs <= 10000 ? timeoutMs : 10000;
  return new WebhookSmsProvider({ url: url.href, token, fetchImpl, timeoutMs: boundedTimeout });
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
