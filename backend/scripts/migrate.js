import fs from 'node:fs/promises';
import path from 'node:path';
import pg from 'pg';

const { Client } = pg;
const databaseUrl = process.env.DATABASE_URL;
if (!databaseUrl) throw new Error('DATABASE_URL is required');

const client = new Client({
  connectionString: databaseUrl,
  ssl: databaseUrl.includes('localhost') ? false : { rejectUnauthorized: false },
});

await client.connect();
try {
  await client.query(`
    create table if not exists schema_migration (
      filename text primary key,
      applied_at timestamptz not null default now()
    )
  `);

  const dir = path.resolve('migrations');
  const files = (await fs.readdir(dir))
    .filter((name) => /^\d+_.*\.sql$/.test(name))
    .sort();

  for (const filename of files) {
    const exists = await client.query(
      'select 1 from schema_migration where filename=$1',
      [filename],
    );
    if (exists.rowCount) continue;

    const sql = await fs.readFile(path.join(dir, filename), 'utf8');
    await client.query('begin');
    try {
      await client.query(sql);
      await client.query(
        'insert into schema_migration(filename) values($1)',
        [filename],
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
