// Three synthetic accounts for local Android/PWA acceptance. Not a live seed.
import argon2 from 'argon2';
import pg from 'pg';
if (process.env.ALLOW_SYNTHETIC_SEED !== 'yes') throw new Error('ALLOW_SYNTHETIC_SEED=yes required');
const password = process.env.SYNTHETIC_PASSWORD;
if (typeof password !== 'string' || password.length < 10) throw new Error('Provide a random synthetic password of at least 10 characters');
const members = [
  { id: 'a0000000-0000-4000-8000-000000000001', email: 'stage0-child@lifeguide.test', name: 'فرزند آزمایشی', role: 'teen_minor', theme: 'boy_blue', category: 'boy_minor' },
  { id: 'a0000000-0000-4000-8000-000000000002', email: 'stage0-mother@lifeguide.test', name: 'مادر آزمایشی', role: 'parent_guardian', theme: 'adult_blue', category: 'adult' },
  { id: 'a0000000-0000-4000-8000-000000000003', email: 'stage0-father@lifeguide.test', name: 'پدر آزمایشی', role: 'parent_guardian', theme: 'adult_blue', category: 'adult' },
];
const familyId = 'a1000000-0000-4000-8000-000000000001';
const pool = new pg.Pool();
const client = await pool.connect();
try {
  await client.query('begin');
  const hash = await argon2.hash(password, { type: argon2.argon2id });
  for (const member of members) {
    const subject = `stage0-synthetic-family:${member.id}`;
    const existing = await client.query('select id,identity_subject from app_user where id=$1 or email_normalized=$2 for update', [member.id, member.email]);
    if (existing.rowCount && (existing.rowCount !== 1 || existing.rows[0].id !== member.id || existing.rows[0].identity_subject !== subject)) throw new Error('Refusing to modify a non-fixture account');
    await client.query('insert into app_user(id,identity_subject,email_normalized,email_verified_at) values($1,$2,$3,now()) on conflict(id) do nothing', [member.id, subject, member.email]);
    await client.query('insert into profile(user_id,display_name,theme_preference,profile_category) values($1,$2,$3,$4) on conflict(user_id) do update set display_name=excluded.display_name,theme_preference=excluded.theme_preference,profile_category=excluded.profile_category', [member.id, member.name, member.theme, member.category]);
    await client.query('insert into auth_credential(user_id,password_hash) values($1,$2) on conflict(user_id) do update set password_hash=excluded.password_hash', [member.id, hash]);
  }
  const family = await client.query('select created_by from family_workspace where id=$1 for update', [familyId]);
  if (family.rowCount && family.rows[0].created_by !== members[1].id) throw new Error('Refusing to modify a non-fixture family');
  await client.query("insert into family_workspace(id,name,created_by) values($1,'LifeGuide Synthetic Stage0 Family',$2) on conflict(id) do nothing", [familyId, members[1].id]);
  for (const member of members) {
    await client.query('insert into family_membership(family_id,user_id,role,is_admin) values($1,$2,$3,$4) on conflict(family_id,user_id) do update set role=excluded.role,ended_at=null,is_admin=excluded.is_admin', [familyId, member.id, member.role, member.role === 'parent_guardian']);
  }
  for (const parent of members.slice(1)) {
    await client.query('insert into guardian_relationship(family_id,guardian_user_id,minor_user_id) values($1,$2,$3) on conflict(family_id,guardian_user_id,minor_user_id) do update set active=true', [familyId, parent.id, members[0].id]);
  }
  await client.query('commit');
  console.log('Synthetic Stage0 child/mother/father accounts and permitted guardian relationships ready. Password not logged.');
} catch (error) {
  await client.query('rollback');
  throw error;
} finally {
  client.release();
  await pool.end();
}
