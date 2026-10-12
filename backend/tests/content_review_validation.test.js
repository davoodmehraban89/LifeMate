import test from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import { normalizeReviewMutation, normalizeBriefRequest } from '../src/content_review.js';

test('review mutations allow only explicit statuses and reject inferred identities or text', () => {
  const body={mutationId:crypto.randomUUID(),expectedVersion:1,status:'triaged'};
  assert.deepEqual(normalizeReviewMutation(body),body);
  for(const extra of [{status:'released'},{status:'received'},{expectedVersion:0},
    {expectedVersion:'1'},{mutationId:'bad'},{ownerUserId:crypto.randomUUID()},
    {summary:'copied text'},{role:'admin'}]) assert.equal(normalizeReviewMutation({...body,...extra}),null);
});

test('brief requests are bounded source/version references, never private text', () => {
  const body={mutationId:crypto.randomUUID(),feedback:[{id:crypto.randomUUID(),expectedVersion:2}]};
  assert.deepEqual(normalizeBriefRequest(body),body);
  for(const extra of [{feedback:[]},{feedback:Array.from({length:21},()=>({id:crypto.randomUUID(),expectedVersion:1}))},
    {feedback:[body.feedback[0],body.feedback[0]]},{summary:'private text'},
    {feedback:[{...body.feedback[0],ownerUserId:crypto.randomUUID()}]},
    {feedback:[{...body.feedback[0],expectedVersion:'2'}]}]) assert.equal(normalizeBriefRequest({...body,...extra}),null);
});
