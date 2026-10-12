import test from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {localContentReviewConnection,normalizePublicationOperation} from '../src/content_publication.js';

test('publication operator rejects remote/default/runtime configuration and accepts only explicit loopback test URL',()=>{
  for(const env of [{},{DATABASE_URL:'postgres://local@127.0.0.1/lifeguide_test'},
    {CONTENT_REVIEW_DATABASE_URL:'postgres://local@127.0.0.1/production',CONTENT_REVIEW_SYNTHETIC_ONLY:'true'},
    {CONTENT_REVIEW_DATABASE_URL:'postgres://local@remote.example/lifeguide_test',CONTENT_REVIEW_SYNTHETIC_ONLY:'true'},
    {CONTENT_REVIEW_DATABASE_URL:'postgres://local@127.0.0.1/lifeguide_test?host=remote.example',CONTENT_REVIEW_SYNTHETIC_ONLY:'true'},
    {CONTENT_REVIEW_DATABASE_URL:'postgres://local@127.0.0.1/lifeguide_test?sslkey=/private/path',CONTENT_REVIEW_SYNTHETIC_ONLY:'true'},
    {CONTENT_REVIEW_DATABASE_URL:'postgres://local@127.0.0.1/lifeguide_test'},
    {CONTENT_REVIEW_DATABASE_URL:'postgres://local@127.0.0.1/contest',CONTENT_REVIEW_SYNTHETIC_ONLY:'true'}]) {
    assert.throws(()=>localContentReviewConnection(env));
  }
  assert.equal(new URL(localContentReviewConnection({CONTENT_REVIEW_DATABASE_URL:'postgres://operator@127.0.0.1/lifeguide_publication_test',CONTENT_REVIEW_SYNTHETIC_ONLY:'true'})).hostname,'127.0.0.1');
});

test('publication manifest accepts exact typed operation fields and refuses private or unbounded content',()=>{
  const base={schemaVersion:1,mutationId:crypto.randomUUID(),entityType:'video',entityId:crypto.randomUUID(),operation:'withdraw',
    expectedStatus:'published',expectedContentHash:'a'.repeat(64),expectedContextHash:'b'.repeat(64)};
  assert.equal(normalizePublicationOperation(base).operation,'withdraw');
  for(const value of [null,[],{...base,ownerUserId:crypto.randomUUID()},{...base,privateChat:'PRIVATE'},
    {...base,review:{watchedEntireVideo:'true'}},{...base,expectedContentHash:'wrong'},
    {...base,expectedVersion:1},{...base,operation:'deploy'},{...base,entityId:'wrong'}]) assert.throws(()=>normalizePublicationOperation(value));
});
