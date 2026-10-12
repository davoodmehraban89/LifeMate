import test from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {normalizeRoleMutation,normalizeAdminTransfer,normalizeInvitationRevoke} from '../src/family_lifecycle.js';

test('family lifecycle mutations require explicit stable IDs and integer versions, never role inference',()=>{
  const mutationId=crypto.randomUUID(),targetUserId=crypto.randomUUID();
  assert.deepEqual(normalizeRoleMutation({mutationId,expectedVersion:1,role:'adult_member'}),{mutationId,expectedVersion:1,role:'adult_member'});
  assert.ok(normalizeAdminTransfer({mutationId,targetUserId,expectedVersion:1,expectedActorVersion:2}));
  assert.ok(normalizeInvitationRevoke({mutationId,expectedVersion:1,action:'revoke'}));
  for(const extra of [{role:'mother'},{isAdmin:true},{ownerUserId:targetUserId},{expectedVersion:'1'},{expectedVersion:0}]){
    assert.equal(normalizeRoleMutation({mutationId,expectedVersion:1,role:'adult_member',...extra}),null);
  }
  assert.equal(normalizeAdminTransfer({mutationId,targetUserId,expectedVersion:1}),null);
  assert.equal(normalizeInvitationRevoke({mutationId,expectedVersion:1,action:'accept'}),null);
});
