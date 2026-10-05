import test, { after } from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import { app, pool } from '../src/server.js';

const server = app.listen(0);
const address = server.address();
const base = `http://127.0.0.1:${address.port}`;

after(async () => {
  await new Promise((resolve) => server.close(resolve));
  await pool.end();
});

async function request(path, { method='GET', body, token } = {}) {
  const response = await fetch(base + path, {
    method,
    headers: {
      'content-type': 'application/json',
      ...(token ? { authorization: `Bearer ${token}` } : {}),
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await response.text();
  return {
    status: response.status,
    body: text ? JSON.parse(text) : null,
  };
}

async function registerVerified(email, displayName) {
  const password = 'Phase3Pass!123';
  const reg = await request('/v1/auth/register', {
    method:'POST',
    body:{ email, displayName, password },
  });
  assert.equal(reg.status,201);
  assert.equal((await request('/v1/auth/verify-email',{
    method:'POST', body:{ token:reg.body.verificationToken },
  })).status,204);
  const login = await request('/v1/auth/login',{
    method:'POST', body:{ email, password },
  });
  assert.equal(login.status,200);
  return { token:login.body.accessToken, userId:reg.body.userId, password };
}

test('phase 3 planner school family vertical slice', async () => {
  const suffix = Date.now().toString(36);
  const parent = await registerVerified(`p3-parent-${suffix}@example.test`,'Phase3 Parent');
  const teen = await registerVerified(`p3-teen-${suffix}@example.test`,'Phase3 Teen');
  const outsider = await registerVerified(`p3-outsider-${suffix}@example.test`,'Phase3 Outsider');

  const family = await request('/v1/families',{
    method:'POST', token:parent.token,
    body:{ name:'Phase3 Family', role:'parent_guardian' },
  });
  assert.equal(family.status,201);

  const invite = await request(`/v1/families/${family.body.id}/invitations`,{
    method:'POST', token:parent.token,
    body:{ email:`p3-teen-${suffix}@example.test`, role:'teen_minor', themePreference:'girl_pink' },
  });
  assert.equal(invite.status,201);
  assert.equal((await request('/v1/invitations/accept',{
    method:'POST', token:teen.token, body:{ token:invite.body.invitationToken },
  })).status,204);

  const members = await request(`/v1/families/${family.body.id}/members`,{token:parent.token});
  const parentMember = members.body.members.find((x)=>x.user_id===parent.userId);
  const teenMember = members.body.members.find((x)=>x.user_id===teen.userId);
  assert.ok(parentMember && teenMember);

  assert.equal((await request(`/v1/families/${family.body.id}/guardians`,{
    method:'POST', token:parent.token,
    body:{guardianUserId:parent.userId,minorUserId:teen.userId},
  })).status,204);

  const ctx = await request('/v1/life-contexts',{
    method:'POST', token:teen.token,
    body:{kind:'student',title:'مدرسه'},
  });
  assert.equal(ctx.status,201);

  const year = await request('/v1/school/years',{
    method:'POST', token:teen.token,
    body:{
      lifeContextId:ctx.body.id,
      title:'سال تحصیلی ۱۴۰۵-۱۴۰۶',
      startsOn:'2026-09-01',
      endsOn:'2027-06-30',
    },
  });
  assert.equal(year.status,201);

  const term = await request(`/v1/school/years/${year.body.id}/terms`,{
    method:'POST', token:teen.token,
    body:{title:'نیمسال اول',startsOn:'2026-09-01',endsOn:'2027-01-31'},
  });
  assert.equal(term.status,201);

  const subject = await request(`/v1/school/terms/${term.body.id}/subjects`,{
    method:'POST', token:teen.token,
    body:{name:'ریاضی',teacherName:'دبیر ریاضی',colorKey:'pink'},
  });
  assert.equal(subject.status,201);

  const klass = await request(`/v1/school/subjects/${subject.body.id}/classes`,{
    method:'POST', token:teen.token,
    body:{weekday:2,startsAt:'08:00',endsAt:'09:30',location:'کلاس ۷'},
  });
  assert.equal(klass.status,201);

  const due = new Date(Date.now()+60*60*1000).toISOString();
  const assignment = await request('/v1/plan-items',{
    method:'POST', token:teen.token,
    body:{
      kind:'assignment',
      title:'تمرین فصل اول ریاضی',
      subjectId:subject.body.id,
      familyId:family.body.id,
      visibility:'parent_guardian',
      dueAt:due,
      priority:'high',
      durationMinutes:45,
      reminderMinutesBefore:[30,10],
    },
  });
  assert.equal(assignment.status,201);

  const privateTask = await request('/v1/plan-items',{
    method:'POST', token:teen.token,
    body:{kind:'task',title:'کار شخصی',visibility:'private',dueAt:due},
  });
  assert.equal(privateTask.status,201);

  const familyEvent = await request('/v1/plan-items',{
    method:'POST', token:parent.token,
    body:{
      kind:'event', title:'شام خانوادگی', familyId:family.body.id,
      visibility:'family', startsAt:due, reminderMinutesBefore:[15],
    },
  });
  assert.equal(familyEvent.status,201);

  const parentCalendar = await request(`/v1/families/${family.body.id}/calendar`,{token:parent.token});
  assert.equal(parentCalendar.status,200);
  assert.ok(parentCalendar.body.items.some((x)=>x.id===assignment.body.id));
  assert.ok(parentCalendar.body.items.some((x)=>x.id===familyEvent.body.id));
  assert.ok(!parentCalendar.body.items.some((x)=>x.id===privateTask.body.id));

  const outsiderOverview = await request(`/v1/school/${teen.userId}/overview`,{token:outsider.token});
  assert.equal(outsiderOverview.status,403);

  const parentOverview = await request(`/v1/school/${teen.userId}/overview`,{token:parent.token});
  assert.equal(parentOverview.status,200);
  assert.equal(parentOverview.body.subjects.length,1);
  assert.ok(parentOverview.body.workload.some((x)=>x.id===assignment.body.id));

  const parentPrivateAttempt = await request('/v1/plan-items',{token:parent.token});
  assert.equal(parentPrivateAttempt.status,200);
  assert.ok(!parentPrivateAttempt.body.items.some((x)=>x.id===privateTask.body.id));

  const grade = await request(`/v1/school/plan-items/${assignment.body.id}/grade`,{
    method:'PATCH', token:teen.token, body:{points:18,outOf:20},
  });
  assert.equal(grade.status,200);

  const support = await request(
    `/v1/families/${family.body.id}/children/${teen.userId}/support-summary`,
    {token:parent.token},
  );
  assert.equal(support.status,200);
  assert.ok(Array.isArray(support.body.upcoming));
  assert.equal(support.body.metrics.gradePercent,90);

  const outsiderSupport = await request(
    `/v1/families/${family.body.id}/children/${teen.userId}/support-summary`,
    {token:outsider.token},
  );
  assert.equal(outsiderSupport.status,403);

  const rescheduled = new Date(Date.now()+2*60*60*1000).toISOString();
  const update = await request(`/v1/plan-items/${assignment.body.id}`,{
    method:'PATCH', token:teen.token, body:{dueAt:rescheduled},
  });
  assert.equal(update.status,200);

  const reminderRows = await pool.query(
    'select minutes_before,status,scheduled_for from reminder where plan_item_id=$1 order by minutes_before',
    [assignment.body.id],
  );
  assert.equal(reminderRows.rowCount,2);
  assert.ok(reminderRows.rows.every((x)=>x.status==='scheduled'));

  const completed = await request(`/v1/plan-items/${assignment.body.id}`,{
    method:'PATCH', token:teen.token, body:{status:'completed'},
  });
  assert.equal(completed.status,200);
  const cancelled = await pool.query(
    "select count(*)::int as n from reminder where plan_item_id=$1 and status='cancelled'",
    [assignment.body.id],
  );
  assert.equal(cancelled.rows[0].n,2);

  const mutationId = crypto.randomUUID();
  const sync1 = await request('/v1/sync/mutations',{
    method:'POST', token:teen.token,
    body:{mutations:[{
      id:mutationId, entityType:'plan_item', entityId:privateTask.body.id,
      operation:'reschedule', clientUpdatedAt:new Date().toISOString(),
      payload:{dueAt:rescheduled},
    }]},
  });
  assert.equal(sync1.status,200);
  assert.equal(sync1.body.results[0].status,'accepted');

  const syncedRow = await pool.query(
    'select due_at from plan_item where id=$1',
    [privateTask.body.id],
  );
  assert.equal(
    new Date(syncedRow.rows[0].due_at).toISOString(),
    new Date(rescheduled).toISOString(),
  );

  const sync2 = await request('/v1/sync/mutations',{
    method:'POST', token:teen.token,
    body:{mutations:[{
      id:mutationId, entityType:'plan_item', entityId:privateTask.body.id,
      operation:'reschedule', clientUpdatedAt:new Date().toISOString(),
      payload:{dueAt:rescheduled},
    }]},
  });
  assert.equal(sync2.body.results[0].status,'already_applied');

  const reminderItem = await request('/v1/plan-items',{
    method:'POST', token:teen.token,
    body:{
      kind:'task',
      title:'یادآوری آزمایشی',
      visibility:'private',
      dueAt:new Date(Date.now()-60*1000).toISOString(),
      reminderMinutesBefore:[0],
    },
  });
  assert.equal(reminderItem.status,201);
  const claimed = await request('/v1/reminders/claim-due',{
    method:'POST', token:teen.token, body:{limit:10},
  });
  assert.equal(claimed.status,200);
  assert.ok(claimed.body.claimed >= 1);
  const notifications = await request('/v1/notification-outbox',{token:teen.token});
  assert.equal(notifications.status,200);
  assert.ok(
    notifications.body.notifications.some(
      (item)=>item.payload.planItemId===reminderItem.body.id,
    ),
  );
});
