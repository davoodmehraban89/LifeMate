import express from 'express';

const categories = new Set(['girl_minor', 'boy_minor', 'adult']);
const themes = new Set(['girl_pink', 'boy_blue', 'adult_blue', 'custom']);

export function validBirthDate(value) {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value) || value.startsWith('0000-')) return false;
  const date = new Date(`${value}T00:00:00Z`);
  return Number.isFinite(date.getTime()) && date.toISOString().slice(0, 10) === value;
}

export function createProfileRouter({ pool, auth }) {
  const router = express.Router();
  router.use(auth);

  router.get('/', async (req, res) => {
    const result = await pool.query(
      `select u.id as user_id,p.display_name,p.birth_date,p.theme_preference,p.profile_category,
              u.email_normalized,u.email_verified_at,u.phone_normalized,u.phone_verified_at
       from profile p join app_user u on u.id=p.user_id where p.user_id=$1`,
      [req.identity.sub],
    );
    if (!result.rowCount) return res.status(404).json({ error: 'profile_not_found' });
    res.json(result.rows[0]);
  });

  router.patch('/', async (req, res) => {
    const body = req.body ?? {};
    const name = body.displayName == null ? null : String(body.displayName).trim();
    const theme = body.themePreference == null ? null : String(body.themePreference);
    const category = body.profileCategory;
    const birthDate = body.birthDate;
    if (name != null && (!name || name.length > 100)) return res.status(400).json({ error: 'invalid_display_name' });
    if (theme != null && !themes.has(theme)) return res.status(400).json({ error: 'invalid_theme' });
    if (Object.hasOwn(body, 'profileCategory') && !categories.has(category)) return res.status(400).json({ error: 'invalid_profile_category' });
    if (birthDate != null && !validBirthDate(birthDate)) return res.status(400).json({ error: 'invalid_birth_date' });
    const result = await pool.query(
      `update profile set display_name=coalesce($2,display_name),
              birth_date=coalesce($3::date,birth_date),
              theme_preference=coalesce($4,theme_preference),
              profile_category=coalesce($5,profile_category),updated_at=now()
       where user_id=$1 returning display_name,birth_date,theme_preference,profile_category`,
      [req.identity.sub, name, birthDate ?? null, theme, category ?? null],
    );
    if (!result.rowCount) return res.status(404).json({ error: 'profile_not_found' });
    res.json(result.rows[0]);
  });

  return router;
}
