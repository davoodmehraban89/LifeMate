import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import pg from 'pg';

const { Client } = pg;
const databaseUrl = process.env.DATABASE_URL;
const client = new Client(
  databaseUrl
    ? {
        connectionString: databaseUrl,
        ssl:
          process.env.PGSSLMODE === 'require'
            ? { rejectUnauthorized: false }
            : false,
      }
    : {
        host: process.env.PGHOST,
        port: Number(process.env.PGPORT ?? 5432),
        database: process.env.PGDATABASE,
        user: process.env.PGUSER,
        password: process.env.PGPASSWORD,
        ssl:
          process.env.PGSSLMODE === 'require'
            ? { rejectUnauthorized: false }
            : false,
      },
);

await client.connect();
try {
  await client.query("select pg_advisory_lock(hashtextextended('lifemate_schema_migration',0))");
  await client.query(`
    create table if not exists schema_migration (
      filename text primary key,
      applied_at timestamptz not null default now()
    )
  `);
  await client.query('alter table schema_migration add column if not exists sha256 text');

  const dir = path.resolve('migrations');
  const files = (await fs.readdir(dir))
    .filter((name) => /^\d+_.*\.sql$/.test(name))
    .sort();

  for (const filename of files) {
    const source = await fs.readFile(path.join(dir, filename), 'utf8');
    const checksum = crypto.createHash('sha256').update(source).digest('hex');
    const exists = await client.query(
      'select sha256 from schema_migration where filename=$1',
      [filename],
    );
    if (exists.rowCount) {
      const stored = exists.rows[0].sha256;
      if (stored && stored !== checksum) throw new Error(`Applied migration changed: ${filename}`);
      if (!stored) console.warn(`UNVERIFIED historical migration checksum: ${filename}`);
      continue;
    }

    // Existing files contain their own outer BEGIN/COMMIT. Keep the schema
    // and ledger insert in ONE transaction instead of committing the SQL early.
    const trimmed = source.trim();
    const sql = /^begin\s*;/i.test(trimmed) && /commit\s*;$/i.test(trimmed)
      ? trimmed.replace(/^begin\s*;/i, '').replace(/commit\s*;$/i, '')
      : source;
    await client.query('begin');
    try {
      await client.query(sql);
      await client.query(
        'insert into schema_migration(filename,sha256) values($1,$2)',
        [filename,checksum],
      );
      await client.query('commit');
      console.log('applied', filename);
    } catch (error) {
      await client.query('rollback');
      throw error;
    }
  }
} finally {
  await client.end();
}
