// Dedicated Kavenegar VerifyLookup provider. Only call from a trusted backend.
// The provider's v1 API puts the API key in the HTTPS URL path; never log request URLs.
const iranPhone = /^\+989\d{9}$/;
const sixDigits = /^\d{6}$/;
const uuid = /^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$/i;
const keyPattern = /^[a-zA-Z0-9]{16,256}$/;
const templatePattern = /^[a-zA-Z][a-zA-Z0-9]{1,63}$/;

function providerError(code) {
  const error = new Error(code); // Never include provider response, key, phone or token.
  error.retryable = false; // VerifyLookup has no idempotency key: retry risks duplicate SMS.
  return error;
}

export function createKavenegarSmsProvider({ env = process.env, fetchImpl = fetch, timeoutMs = 10000 } = {}) {
  const apiKey = env.KAVENEGAR_API_KEY;
  const template = env.KAVENEGAR_TEMPLATE;
  if (typeof apiKey !== 'string' || !keyPattern.test(apiKey)) throw providerError('sms_provider_token_invalid');
  if (typeof template !== 'string' || !templatePattern.test(template)) throw providerError('sms_provider_template_invalid');
  const timeout = Number.isInteger(timeoutMs) && timeoutMs > 0 && timeoutMs <= 10000 ? timeoutMs : 10000;
  return new KavenegarSmsProvider({ apiKey, template, fetchImpl, timeout });
}

class KavenegarSmsProvider {
  configured = true;
  status = 'CONFIGURED_UNVERIFIED';
  #apiKey; #template; #fetch; #timeout;
  constructor({ apiKey, template, fetchImpl, timeout }) {
    this.#apiKey = apiKey;
    this.#template = template;
    this.#fetch = fetchImpl;
    this.#timeout = timeout;
  }

  async sendOtp({ phone, code, expiresIn, idempotencyKey }) {
    if (typeof phone !== 'string' || !iranPhone.test(phone) ||
        typeof code !== 'string' || !sixDigits.test(code) ||
        !Number.isInteger(expiresIn) || expiresIn < 1 || expiresIn > 300 ||
        typeof idempotencyKey !== 'string' || !uuid.test(idempotencyKey)) {
      throw providerError('sms_provider_input_invalid');
    }

    // Fixed official host: no user-controlled URL, HTTP fallback or redirects.
    // The +98XXXXXXXXXX identity is converted to Kavenegar's Iranian 09XXXXXXXXX.
    const url = new URL(`https://api.kavenegar.com/v1/${this.#apiKey}/verify/lookup.json`);
    url.search = new URLSearchParams({
      receptor: '0' + phone.slice(3),
      token: code,
      template: this.#template,
      type: 'sms',
    }).toString();

    const signal = AbortSignal.timeout(this.#timeout);
    let response;
    try {
      response = await this.#fetch(url.href, {
        method: 'GET',
        redirect: 'error',
        signal,
        headers: { Accept: 'application/json' },
      });
    } catch {
      throw providerError(signal.aborted ? 'sms_provider_timeout' : 'sms_provider_unavailable');
    }
    if (response?.status !== 200) {
      try { await response?.body?.cancel?.(); } catch { /* no body logging */ }
      throw providerError('sms_provider_rejected');
    }

    let payload;
    try {
      const raw = await response.text();
      if (raw.length > 8192) throw new Error('oversized_provider_response');
      payload = JSON.parse(raw);
    } catch {
      throw providerError('sms_provider_malformed_response');
    }
    if (payload?.return?.status !== 200 ||
        !payload.entries ||
        (Array.isArray(payload.entries) && !payload.entries.length)) {
      throw providerError('sms_provider_rejected');
    }
    // HTTP 200 and provider 200 only prove provider acceptance, not handset delivery.
    return { delivered: true };
  }
}
