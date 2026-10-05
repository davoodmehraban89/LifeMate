import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const src=fs.readFileSync(new URL('../src/phase4.js',import.meta.url),'utf8');
const migration=fs.readFileSync(new URL('../migrations/0004_ai_learning_wellbeing.sql',import.meta.url),'utf8');

test('phase4 schema contains learning wellbeing guide and proposal boundaries',()=>{
 for(const table of ['learning_goal','learning_checkin','wellbeing_checkin','ai_guide_session','ai_guide_message','ai_plan_proposal']) assert.match(migration,new RegExp(`create table if not exists ${table}`));
 assert.match(migration,/visibility in \('private','guardian_summary'\)/);
 assert.match(migration,/status in \('proposed','accepted','rejected'\)/);
});

test('AI guide is advisory and has urgent safety path',()=>{
 assert.match(src,/urgent_review/);
 assert.match(src,/medicalDiagnosis:false/);
 assert.match(src,/automaticAction:false/);
 assert.match(src,/خدمات اضطراری محلی/);
});

test('wellbeing reads are owner scoped',()=>{
 assert.match(src,/wellbeing_checkin where owner_user_id=\$1/);
 assert.doesNotMatch(src,/guardian.*note/i);
});
