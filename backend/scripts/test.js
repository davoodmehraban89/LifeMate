import { readdirSync } from 'node:fs';
import { spawnSync } from 'node:child_process';

// Tests never inherit an operator's live delivery or AI configuration.
// Database/JWT fixture inputs remain available; individual fixtures can inject local providers.
const env = { ...process.env, NODE_ENV: 'test', SMS_PROVIDER: 'disabled' };
for (const key of ['SMS_PROVIDER_URL', 'SMS_PROVIDER_TOKEN', 'EMAIL_FROM', 'RESEND_API_KEY',
  'SMTP_HOST', 'SMTP_PORT', 'SMTP_USER', 'SMTP_PASSWORD', 'AI_API_KEY', 'AI_BASE_URL', 'AI_MODEL', 'OPENAI_API_KEY']) env[key] = '';
env.SMTP_SECURE = 'false';
const files = readdirSync(new URL('../tests/', import.meta.url))
  .filter((file) => !file.startsWith('.') && file.endsWith('.test.js')).sort()
  .map((file) => `tests/${file}`);
const result = spawnSync(process.execPath, ['--test', ...process.argv.slice(2), ...files], {
  cwd: new URL('../', import.meta.url), env, stdio: 'inherit',
});
if (result.error) throw new Error('test_runner_start_failed');
process.exit(result.status ?? 1);
