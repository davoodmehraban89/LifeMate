// Offline local-file preparation only. Preserves existing secrets/settings.
import crypto from 'node:crypto';
import fs from 'node:fs/promises';
const envFile = new URL('../.env',import.meta.url);
if (process.argv[2] !== '--write' || process.argv.length !== 3) throw new Error('Use --write to append missing private local role settings');
let contents = await fs.readFile(envFile,'utf8');
const original = contents;
const additions=[];
for(const [prefix,user] of [['API','lifeguide_api'],['MIGRATOR','lifeguide_migrator'],['BACKUP','lifeguide_backup']]) {
  const userPattern = new RegExp(`^${prefix}_DB_USER=(.*)$`,'m');
  const existingUser=contents.match(userPattern)?.[1];
  if(existingUser && existingUser!==user) throw new Error('Configured application roles must use their canonical distinct names');
  if(!existingUser) {
    if(userPattern.test(contents)) contents=contents.replace(userPattern,`${prefix}_DB_USER=${user}`);
    else additions.push(`${prefix}_DB_USER=${user}`);
  }
  const passwordPattern = new RegExp(`^${prefix}_DB_PASSWORD=(.*)$`,'m');
  const existingPassword = contents.match(passwordPattern)?.[1];
  if(!existingPassword || existingPassword.startsWith('CHANGE_ME')) {
    const value=`${prefix}_DB_PASSWORD=${crypto.randomBytes(32).toString('hex')}`;
    if(passwordPattern.test(contents)) contents=contents.replace(passwordPattern,value);
    else additions.push(value);
  }
}
if(additions.length) {
  contents=contents.replace(/\s*$/,'')+'\n# Independent local application DB credentials\n'+additions.join('\n')+'\n';
}
if(contents!==original) {
  const temporary = new URL(`../.env.roles-${crypto.randomBytes(8).toString('hex')}.tmp`,import.meta.url);
  try {
    const file=await fs.open(temporary,'wx',0o600);
    try { await file.writeFile(contents); await file.sync(); } finally { await file.close(); }
    await fs.rename(temporary,envFile);
  } finally { await fs.rm(temporary,{force:true}); }
  console.log('Appended missing private role settings; existing values preserved. No database/server operation ran.');
} else console.log('Private role settings already present; preserved unchanged.');
