// Compiled-browser regression helper. Call only with a dedicated NEW synthetic
// actor in the local HTTPS acceptance harness; pass its independent API result.
// Reads real Chromium semantics. Does not change UI state, APIs or TLS settings.
const assert = require('node:assert/strict');

const statuses = {
  not_started: 'شروع نشده',
  in_progress: 'در حال یادگیری',
  completed: 'تکمیل طبق گزارش من',
};

async function assertLearningProgressSemantics(page, progress) {
  const origin = new URL(page.url());
  assert.equal(origin.origin, 'https://127.0.0.1:8445',
    'Use only the isolated synthetic local HTTPS stack.');
  assert(progress && Object.hasOwn(statuses, progress.status),
    'Provide the independent API progress snapshot, not a guessed UI label.');
  assert.equal(progress.source, 'self_reported');
  assert.equal(progress.pending_sync === true, false,
    'This compiled-browser check requires an acknowledged server snapshot.');
  assert(Number.isInteger(progress.version) && progress.version > 0);
  assert(typeof progress.updatedAt === 'string' &&
    /(?:Z|[+-]\d{2}:\d{2})$/.test(progress.updatedAt) &&
    Number.isFinite(Date.parse(progress.updatedAt)));

  const label = `پیشرفت شخصی: ${statuses[progress.status]}\nآخرین ثبت سرور: ${progress.updatedAt}`;
  const status = page.getByRole('status', {name: label, exact: true});
  await status.waitFor({state: 'attached', timeout: 20000});
  assert.equal(await status.count(), 1,
    'Progress and server timestamp must share one accessible status node.');
  assert.equal(await status.getAttribute('aria-label'), label);

  const session = await page.context().newCDPSession(page);
  try {
    const {nodes} = await session.send('Accessibility.getFullAXTree');
    const matches = nodes.filter(node => !node.ignored &&
      node.role?.value === 'status' && node.name?.value === label);
    assert.equal(matches.length, 1,
      'The updated label must appear in Chromium accessibility, not only DOM attributes.');
    assert.equal(nodes.filter(node => !node.ignored &&
      node.role?.value === 'StaticText' && node.name?.value?.startsWith('پیشرفت شخصی:')).length, 0,
      'Do not duplicate progress announcements through excluded child Text widgets.');
    return {status: 'PASS', role: 'status', serverVersion: progress.version,
      includesSelfReportedStatus: true, includesServerTimestamp: true,
      accessibleStatusNodeCount: matches.length};
  } finally {
    await session.detach();
  }
}

module.exports = {assertLearningProgressSemantics};
