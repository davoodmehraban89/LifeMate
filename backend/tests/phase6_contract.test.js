import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const read = (path) => fs.readFileSync(new URL(`../${path}`, import.meta.url), 'utf8');

test('final feature backend contract exists with privacy and Iran education guards', () => {
  const source = read('src/phase6.js');
  assert.match(source, /secondary_1/);
  assert.match(source, /menstrual/);
  assert.match(source, /notification/);
  assert.match(source, /calendar/);
  assert.match(source, /chap\.sch\.ir/);
  assert.doesNotMatch(source, /parent_guardian.*menstrual|guardian.*menstrual/i);
});

test('final migration defines required tables and grade 7 catalog', () => {
  const sql = read('migrations/0005_iran_family_learning.sql');
  for (const name of ['education_profile','curriculum_subject','textbook_catalog','iran_calendar_event','notification_preference','menstrual_cycle_entry']) {
    assert.match(sql, new RegExp(`create table(?: if not exists)? ${name}`, 'i'));
  }
  assert.match(sql, /secondary_1/);
  assert.match(sql, /\b7\b/);
  assert.match(sql, /ریاضی/);
});
