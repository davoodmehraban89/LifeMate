import { env } from 'cloudflare:workers';
import { httpServerHandler } from 'cloudflare:node';

process.env.NODE_ENV = process.env.NODE_ENV || 'production';
process.env.PORT = '8787';
process.env.DATABASE_URL = env.NEON_DATABASE_URL || env.DATABASE_URL;
process.env.JWT_SECRET = env.JWT_SECRET;
process.env.CORS_ORIGINS = env.CORS_ORIGINS || '';
process.env.PUBLIC_APP_URL = env.PUBLIC_APP_URL || '';
process.env.EMAIL_FROM = env.EMAIL_FROM || '';
process.env.RESEND_API_KEY = env.RESEND_API_KEY || '';

if (!process.env.DATABASE_URL) throw new Error('NEON_DATABASE_URL or DATABASE_URL is required');

await import('./entrypoint.js');

export default httpServerHandler({ port: 8787 });
