// Explicit operations entrypoint; never imported or executed by the API.
import pg from 'pg';
import { prepareRoles,reconcileGrants } from './db-role-policy.js';

const args = process.argv.slice(2);
const mode = args.shift();
let adoptOwner,backupFile;
if (args.length) {
  if (mode !== '--prepare' || args[0] !== '--adopt-existing' || args[1] !== '--expected-owner' || args[3] !== '--backup-file' || args.length !== 5) {
    throw new Error('Usage: --prepare [--adopt-existing --expected-owner ROLE --backup-file PATH] or --grants');
  }
  adoptOwner=args[2]; backupFile=args[4];
}
if (!['--prepare','--grants'].includes(mode)) throw new Error('Use --prepare or --grants explicitly');
const client = new pg.Client();
try {
  await client.connect();
  if (mode === '--prepare') {
    const result = await prepareRoles(client,{adoptOwner,backupFile});
    console.log(`PASS database roles prepared; adoption=${result.adopted}; ${result.backupDigest ? `archive SHA256=${result.backupDigest} (decoding checked separately by operator helper)` : 'existing ownership preserved'}`);
  } else {
    await reconcileGrants(client);
    console.log('PASS database grants reconciled; API has no ledger/DDL rights and backup is read-only');
  }
} catch (error) {
  // No SQL, connection strings or credential contents in operator logs.
  console.error(`Database role operation failed: ${error.code ?? 'policy'}; ${error.code ? 'inspect role/ownership metadata without secrets' : error.message}`);
  process.exitCode=1;
} finally { await client.end(); }
