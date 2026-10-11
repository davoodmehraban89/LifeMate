import test from 'node:test';
import assert from 'node:assert/strict';
import {validateAssessmentDefinition,gradeAssessment} from '../src/learning_assessment.js';

const questions=[{id:'q1',objectiveId:'counting',promptFa:'چند تا؟',choices:[{id:'a',textFa:'۲'},{id:'b',textFa:'۳'}],correctChoiceId:'a',explanationFa:'دو چیز را یکی‌یکی می‌شماریم.',remediationFa:'با دو مهره دوباره تمرین کن.'}];
test('assessment needs reviewed objective, real choices and explanatory remediation',()=>{
 assert.deepEqual(validateAssessmentDefinition(questions),questions);
 for(const bad of [[],[{}],[{...questions[0],correctChoiceId:'unknown'}],[{...questions[0],explanationFa:''}],[questions[0],questions[0]]])assert.throws(()=>validateAssessmentDefinition(bad));
});
test('server computes results, refuses missing/duplicate choices and never promises mastery',()=>{
 assert.equal(gradeAssessment(questions,[{questionId:'q1',choiceId:'a'}]).resultLabel,'answered_correctly');
 const wrong=gradeAssessment(questions,[{questionId:'q1',choiceId:'b'}]);
 assert.equal(wrong.correctCount,0);assert.equal(wrong.resultLabel,'needs_practice');assert.ok(wrong.feedback[0].remediationFa);
 for(const bad of [[],[{questionId:'q1',choiceId:'x'}],[{questionId:'q2',choiceId:'a'}],[{questionId:'q1',choiceId:'a'},{questionId:'q1',choiceId:'b'}]])assert.throws(()=>gradeAssessment(questions,bad));
});
