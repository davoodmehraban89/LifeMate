#!/usr/bin/env node
'use strict';

// Design-only checks: static fixtures, no application server or real identity.
// Every result below is measured in the launched Chromium process. This does
// not attest Safari, assistive technology, an installed PWA, or a real device.
const { chromium } = require('playwright');
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');

const packageRoot = path.resolve(__dirname, '..');
const base = new URL(process.env.DESIGN_BASE_URL || 'http://127.0.0.1:8772/LifeGuide-preview.html');
const receiptPath = path.resolve(process.env.DESIGN_RECEIPT || path.join(packageRoot, 'exports/verification.json'));
const screenshotsDir = path.join(path.dirname(receiptPath), 'screenshots');
const requestedWidths = [320, 360, 390];
const themes = ['calm', 'bright'];
const systemStates = ['normal', 'empty', 'loading', 'error', 'offline', 'conflict', 'session', 'rate-limit'];
const requiredMain = ['home', 'plan', 'courses', 'lesson', 'quiz', 'focus', 'family', 'reminders', 'settings', 'parent-home', 'report'];
const label = 'طرح تعاملی با داده ساختگی';
const started = new Date().toISOString();

const report = {
  schemaVersion: 2,
  scope: 'LifeGuide-Design-v2: static, fictional, interactive design only',
  status: 'FAIL',
  startedAt: started,
  command: 'NODE_PATH=/opt/codex/runtimes/codex-primary-runtime/dependencies/node/node_modules node tools/check.cjs',
  baseUrl: base.origin + base.pathname,
  browser: null,
  matrices: { widths: requestedWidths, themes, fontScale: [1, 2], systemStates },
  checks: [],
  failures: [],
  measurements: {
    auditedLayouts: 0, visibleTextNodes: 0, touchTargets: 0,
    minimumFontPx: null, minimumContrast: null, minimumTargetWidthPx: null,
    minimumTargetHeightPx: null, worstContrast: null, minimumFont: null,
    bidi: [],
  },
  screenshots: [],
  runtimeErrors: [],
  failedStaticRequests: [],
  externalRequests: [],
  forbiddenRequests: [],
  unverified: {
    safari: 'UNVERIFIED: Safari has not been run.',
    realDevice: 'UNVERIFIED: no physical Android/iPhone/iPad test has been performed.',
    iranReachability: 'UNVERIFIED: this local static check does not measure access from Iran.',
    videoPlayback: 'UNVERIFIED: no approved video source or real video playback is included.',
    studentUsability: 'UNVERIFIED: the ten-minute student test script has not been conducted.',
    backendAndPersistence: 'UNVERIFIED and outside scope: no server, sending, saving, or real authentication.',
  },
};
const failureKeys = new Set();
function fail(check, details) {
  const key = `${check}:${JSON.stringify(details)}`;
  if (!failureKeys.has(key)) {
    failureKeys.add(key);
    report.failures.push({ check, ...details });
  }
}
function checked(check, details = {}) {
  report.checks.push({ check, status: 'VERIFIED', result: 'PASS', ...details });
}
function safeRequest(url) {
  try { const parsed = new URL(url); return parsed.origin + parsed.pathname; }
  catch { return 'unparseable-url'; }
}
function writeReport() {
  report.finishedAt = new Date().toISOString();
  report.passed = report.failures.length === 0 && report.checks.length > 0;
  report.status = report.passed ? 'VERIFIED_DESIGN_ONLY' : 'FAIL';
  report.failureCount = report.failures.length;
  fs.mkdirSync(path.dirname(receiptPath), { recursive: true });
  fs.writeFileSync(receiptPath, JSON.stringify(report, null, 2) + '\n');
}

// This function runs inside Chromium so measurements use actual computed
// styles, browser line boxes and glyph positions, rather than token guesses.
function auditLayout({ expectedScreen, expectedState, expectedTheme, fontScale, requiredLabel }) {
  const problems = [];
  const stats = { textCount: 0, targetCount: 0, minimumFont: null, minimumContrast: null, minimumTargetWidth: null, minimumTargetHeight: null, fontSamples: [] };
  const phone = document.querySelector('.phone');
  const rectOf = (element) => {
    const r = element.getBoundingClientRect();
    return { x: +r.x.toFixed(2), y: +r.y.toFixed(2), width: +r.width.toFixed(2), height: +r.height.toFixed(2) };
  };
  const selector = (element) => {
    if (!element) return '(missing)';
    if (element.id) return '#' + element.id;
    const qa = element.getAttribute('data-qa');
    if (qa) return '[data-qa="' + qa + '"]';
    const classes = [...element.classList].slice(0, 3).map(c => '.' + c).join('');
    return element.tagName.toLowerCase() + classes;
  };
  const visible = (element) => {
    if (!(element instanceof Element)) return false;
    for (let current = element; current; current = current.parentElement) {
      const s = getComputedStyle(current);
      if (s.display === 'none' || s.visibility === 'hidden' || s.visibility === 'collapse' || Number(s.opacity) === 0 || current.hidden) return false;
    }
    return !!element.getClientRects().length;
  };
  const parseColor = (color) => {
    if (color === 'transparent') return [0, 0, 0, 0];
    const parts = color.match(/^rgba?\(([^)]+)\)$/);
    if (!parts) throw new Error('Unsupported computed color: ' + color);
    const nums = parts[1].split(/[\s,/]+/).filter(Boolean).map(Number);
    if (nums.length < 3 || nums.some(n => !Number.isFinite(n))) throw new Error('Invalid computed color: ' + color);
    return [nums[0], nums[1], nums[2], nums[3] ?? 1];
  };
  const over = (front, back) => {
    const alpha = front[3] + back[3] * (1 - front[3]);
    if (alpha === 0) return [0, 0, 0, 0];
    return [0, 1, 2].map(i => (front[i] * front[3] + back[i] * back[3] * (1 - front[3])) / alpha).concat(alpha);
  };
  const luminance = (color) => {
    const c = color.slice(0, 3).map(v => {
      const s = v / 255;
      return s <= 0.04045 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4;
    });
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
  };
  const contrast = (front, back) => {
    const a = luminance(front), b = luminance(back);
    return (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05);
  };
  const contrastFor = (element, foreground) => {
    const chain = [];
    for (let current = element; current; current = current.parentElement) chain.push(current);
    let bg = [255, 255, 255, 1];
    for (const ancestor of chain.reverse()) {
      const style = getComputedStyle(ancestor);
      if (style.backgroundImage !== 'none') throw new Error('Text contrast with a background image/gradient requires a pixel audit: ' + selector(ancestor));
      if (Number(style.opacity) !== 1) throw new Error('Text contrast with ancestor opacity requires a layer audit: ' + selector(ancestor));
      bg = over(parseColor(style.backgroundColor), bg);
    }
    const fg = over(parseColor(foreground), bg);
    return { ratio: contrast(fg, bg), foreground: fg.map((n, i) => i < 3 ? +n.toFixed(2) : n), background: bg.map((n, i) => i < 3 ? +n.toFixed(2) : n) };
  };
  if (!phone) return { problems: [{ type: 'missing-phone' }], stats };
  for (const [attribute, expected] of [['data-screen', expectedScreen], ['data-state', expectedState], ['data-theme', expectedTheme]]) {
    if (phone.getAttribute(attribute) !== expected) problems.push({ type: 'wrong-route', attribute, expected, actual: phone.getAttribute(attribute) });
  }
  const labels = [...phone.querySelectorAll('.prototype-label')].filter(visible);
  if (labels.length !== 1 || labels[0].textContent.trim() !== requiredLabel) problems.push({ type: 'prototype-label', count: labels.length });
  if (!phone.querySelector('main.screen-content')) problems.push({ type: 'missing-main-landmark' });
  if (phone.querySelector('.home-menu-card')) problems.push({ type: 'removed-home-menu-card-still-present' });
  const nav = phone.querySelector('.bottom-nav');
  if (nav && nav.querySelectorAll('button').length > 5) problems.push({ type: 'too-many-bottom-destinations', count: nav.querySelectorAll('button').length });
  if (document.querySelector('form')) problems.push({ type: 'real-form-present' });
  for (const input of document.querySelectorAll('input,textarea,[contenteditable]')) {
    if (input.matches('input[type="checkbox"],input[type="radio"]')) continue;
    if (input.isContentEditable || !input.readOnly && !input.disabled) problems.push({ type: 'editable-personal-value', selector: selector(input) });
    if (input.matches('input[type="tel"],input[type="email"]')) problems.push({ type: 'real-identity-field-type', selector: selector(input), inputType: input.type });
  }
  if (expectedScreen === 'home' && ['normal', 'offline', 'error'].includes(expectedState)) {
    const tasks = phone.querySelectorAll('[data-qa="today-task"]');
    if (tasks.length < 3 || tasks.length > 4) problems.push({ type: 'home-task-count', count: tasks.length, expected: 'three or four tasks' });
    if (phone.querySelectorAll('[data-qa="task-start"]').length !== tasks.length) problems.push({ type: 'home-task-action-missing' });
    if (!phone.querySelector('[role="progressbar"][aria-valuenow]')) problems.push({ type: 'home-progress-missing' });
    if (!phone.querySelector('header [data-action="go:reminders"]') || !phone.querySelector('header [data-action="go:student-report"]')) problems.push({ type: 'home-header-destination-missing' });
  }
  if (['empty', 'loading', 'error', 'offline', 'conflict', 'session', 'rate-limit'].includes(expectedState)) {
    const stateElement = phone.querySelector(`[data-qa="state-${expectedState}"]`);
    if (!stateElement || !visible(stateElement)) problems.push({ type: 'state-content-missing', expectedState });
    else if (expectedState !== 'loading' && !stateElement.textContent.trim()) problems.push({ type: 'state-without-text-label', expectedState });
    if (expectedState === 'loading' && (!stateElement?.matches('[aria-busy="true"]') || phone.querySelectorAll('.skeleton').length < 2)) problems.push({ type: 'loading-skeleton-missing' });
    if (expectedState === 'error' && !phone.querySelector('button[data-action="state:normal"]')) problems.push({ type: 'retry-control-missing' });
    if (expectedState === 'offline' && phone.querySelectorAll('[data-qa="queued-list"] li').length < 1) problems.push({ type: 'offline-queue-list-missing' });
    if (expectedState === 'conflict' && (!phone.querySelector('button[data-action="resolve:local"]') || !phone.querySelector('button[data-action="resolve:other"]'))) problems.push({ type: 'conflict-choice-missing' });
    if (expectedState === 'session' && !phone.querySelector('button[data-action="go:welcome"]')) problems.push({ type: 'session-reentry-missing' });
    if (expectedState === 'rate-limit' && (!/[۴4][۲2][۹9]/.test(stateElement?.textContent || '') || !phone.querySelector('button:disabled'))) problems.push({ type: 'rate-limit-cooldown-missing' });
  }
  if (expectedScreen === 'otp' && ['wrong', 'expired', 'cooldown'].includes(expectedState)) {
    const alert = phone.querySelector('[role="alert"]');
    const expectedWord = { wrong: 'اشتباه', expired: 'منقضی', cooldown: 'ثانیه' }[expectedState];
    if (!alert?.textContent.includes(expectedWord)) problems.push({ type: 'otp-state-message-missing', expectedState });
    if (expectedState === 'cooldown' && !phone.querySelector('button[data-action="noop"]:disabled')) problems.push({ type: 'otp-resend-not-disabled-during-cooldown' });
  }
  if (document.documentElement.scrollWidth > innerWidth + 1) problems.push({ type: 'document-horizontal-overflow', scrollWidth: document.documentElement.scrollWidth, viewportWidth: innerWidth });

  const bodyElements = [phone, ...phone.querySelectorAll('*')];
  for (const element of bodyElements) {
    if (!visible(element) || !(element instanceof HTMLElement)) continue;
    // Native controls expose internal scrolling metrics unrelated to layout.
    // Their actual outer bounds and targets are still audited below.
    if (!['INPUT', 'TEXTAREA', 'SELECT', 'OPTION'].includes(element.tagName) && element.clientWidth > 0 && element.scrollWidth > element.clientWidth + 1) {
      problems.push({ type: 'element-horizontal-overflow', selector: selector(element), clientWidth: element.clientWidth, scrollWidth: element.scrollWidth, rect: rectOf(element) });
    }
  }

  const textAudit = (element, text, rectangles) => {
    const style = getComputedStyle(element);
    const font = parseFloat(style.fontSize);
    const sample = text.replace(/\s+/g, ' ').trim().slice(0, 100);
    const location = { selector: selector(element), text: sample, rect: rectOf(element), fontSizePx: +font.toFixed(3) };
    stats.textCount++;
    stats.fontSamples.push({ selector: location.selector, text: sample, fontSizePx: font });
    if (!stats.minimumFont || font < stats.minimumFont.value) stats.minimumFont = { value: font, ...location };
    // A 200% root font must actually enlarge every text item; fixed px sizes
    // cannot silently pass by merely remaining above 12px.
    if (font < 12 * fontScale - 0.02) problems.push({ type: 'font-below-minimum', requiredPx: 12 * fontScale, ...location });
    try {
      const measured = contrastFor(element, style.color);
      if (!stats.minimumContrast || measured.ratio < stats.minimumContrast.value) stats.minimumContrast = { value: measured.ratio, ...location, ...measured };
      if (measured.ratio < 4.5 - 0.001) problems.push({ type: 'text-contrast', required: 4.5, ratio: +measured.ratio.toFixed(4), ...location, foreground: measured.foreground, background: measured.background });
    } catch (error) { problems.push({ type: 'unmeasurable-contrast', ...location, message: error.message }); }
    // Hidden/clip overflow may cut text permanently. Scrollable ancestors are
    // deliberately allowed: their offscreen text can be reached by scrolling.
    for (let ancestor = element; ancestor && phone.contains(ancestor); ancestor = ancestor.parentElement) {
      const ancestorStyle = getComputedStyle(ancestor);
      const clipsX = ['hidden', 'clip'].includes(ancestorStyle.overflowX);
      const clipsY = ['hidden', 'clip'].includes(ancestorStyle.overflowY);
      if (!clipsX && !clipsY) continue;
      // A phone frame legitimately bounds an independently scrollable main.
      if (ancestor === phone && element.closest('main.screen-content')) continue;
      const ancestorRect = ancestor.getBoundingClientRect();
      for (const r of rectangles) {
        if (r.width < 0.1 || r.height < 0.1) continue;
        if (clipsX && (r.left < ancestorRect.left - 1.5 || r.right > ancestorRect.right + 1.5) || clipsY && (r.top < ancestorRect.top - 2 || r.bottom > ancestorRect.bottom + 2)) {
          problems.push({ type: 'clipped-text', ...location, clippingAncestor: selector(ancestor), clippingRect: rectOf(ancestor), textRect: { x: +r.x.toFixed(2), y: +r.y.toFixed(2), width: +r.width.toFixed(2), height: +r.height.toFixed(2) } });
          break;
        }
      }
    }
  };
  const walker = document.createTreeWalker(phone, NodeFilter.SHOW_TEXT);
  while (walker.nextNode()) {
    const node = walker.currentNode, element = node.parentElement;
    if (!node.textContent.trim() || !element || !visible(element) || element.closest('script,style,template,option')) continue;
    const range = document.createRange(); range.selectNodeContents(node);
    const rectangles = [...range.getClientRects()];
    if (!rectangles.some(r => r.width > 0.1 && r.height > 0.1)) continue;
    textAudit(element, node.textContent, rectangles);
  }
  // A native input's current value and placeholder have no DOM Text node.
  for (const control of phone.querySelectorAll('input:not([type="hidden"]):not([type="checkbox"]):not([type="radio"]),textarea,select')) {
    if (!visible(control)) continue;
    const content = control.tagName === 'SELECT' ? control.selectedOptions[0]?.textContent : (control.value || control.placeholder);
    if (content) textAudit(control, content, []);
    if (control.matches('input[type="email"],input[type="tel"]') && !control.readOnly && !control.disabled) problems.push({ type: 'editable-real-identity-field', selector: selector(control) });
  }
  const targets = phone.querySelectorAll('button,input:not([type="hidden"]),select,textarea,a[href],[role="button"],[role="switch"],[role="tab"],summary');
  for (const target of targets) {
    if (!visible(target)) continue;
    const rect = target.getBoundingClientRect(), description = { selector: selector(target), text: (target.getAttribute('aria-label') || target.textContent || target.getAttribute('name') || '').trim().slice(0, 100), rect: rectOf(target), disabled: target.matches(':disabled') };
    stats.targetCount++;
    if (!stats.minimumTargetWidth || rect.width < stats.minimumTargetWidth.value) stats.minimumTargetWidth = { value: rect.width, ...description };
    if (!stats.minimumTargetHeight || rect.height < stats.minimumTargetHeight.value) stats.minimumTargetHeight = { value: rect.height, ...description };
    if (rect.width < 48 - 0.1 || rect.height < 48 - 0.1) problems.push({ type: 'touch-target', requiredWidthPx: 48, requiredHeightPx: 48, ...description });
  }
  return { problems, stats };
}

function updateMeasurements(audit, context) {
  const m = report.measurements, s = audit.stats;
  m.auditedLayouts++;
  m.visibleTextNodes += s.textCount;
  m.touchTargets += s.targetCount;
  if (s.minimumFont && (m.minimumFontPx === null || s.minimumFont.value < m.minimumFontPx)) {
    m.minimumFontPx = +s.minimumFont.value.toFixed(3); m.minimumFont = { ...context, ...s.minimumFont };
  }
  if (s.minimumContrast && (m.minimumContrast === null || s.minimumContrast.value < m.minimumContrast)) {
    m.minimumContrast = +s.minimumContrast.value.toFixed(6); m.worstContrast = { ...context, ...s.minimumContrast };
  }
  if (s.minimumTargetWidth && (m.minimumTargetWidthPx === null || s.minimumTargetWidth.value < m.minimumTargetWidthPx)) m.minimumTargetWidthPx = +s.minimumTargetWidth.value.toFixed(3);
  if (s.minimumTargetHeight && (m.minimumTargetHeightPx === null || s.minimumTargetHeight.value < m.minimumTargetHeightPx)) m.minimumTargetHeightPx = +s.minimumTargetHeight.value.toFixed(3);
  for (const problem of audit.problems) fail(problem.type, { ...context, ...problem });
}

async function navigate(page, screen, state = 'normal', theme = 'calm', fontScale = 1) {
  await page.evaluate(async ({ screen, state, theme, fontScale }) => {
    document.documentElement.style.fontSize = `${16 * fontScale}px`;
    await Promise.resolve(window.LifeGuideDesign.navigate(screen, state, theme));
    await document.fonts.ready;
    await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));
  }, { screen, state, theme, fontScale });
}

async function checkBidi(page) {
  await page.setViewportSize({ width: 390, height: 1000 });
  await navigate(page, 'math-bidi');
  const evidence = await page.evaluate(() => {
    const examples = ['−۳', '−۱۰', '۷ + (−۳)', '½'];
    const characterRect = (element, index) => {
      const walker = document.createTreeWalker(element, NodeFilter.SHOW_TEXT);
      let offset = index;
      while (walker.nextNode()) {
        const node = walker.currentNode;
        if (offset < node.length) {
          const range = document.createRange(); range.setStart(node, offset); range.setEnd(node, offset + 1);
          const r = range.getBoundingClientRect();
          return { left: +r.left.toFixed(3), right: +r.right.toFixed(3), top: +r.top.toFixed(3), bottom: +r.bottom.toFixed(3) };
        }
        offset -= node.length;
      }
      return null;
    };
    return examples.map(example => {
      const element = [...document.querySelectorAll('bdi.math[dir="ltr"][data-math]')].find(e => e.dataset.math === example);
      if (!element) return { example, passed: false, reason: 'missing bdi.math[dir=ltr] fixture' };
      const text = element.textContent.trim();
      const minusIndex = text.indexOf('−');
      const minus = minusIndex < 0 ? null : characterRect(element, minusIndex);
      const followingDigit = minusIndex < 0 ? null : characterRect(element, minusIndex + 1);
      const style = getComputedStyle(element);
      const passed = text === example && style.direction === 'ltr' && /isolate/.test(style.unicodeBidi) && (minusIndex < 0 || minus && followingDigit && minus.left < followingDigit.left && Math.abs(minus.top - followingDigit.top) < 2);
      return { example, text, direction: style.direction, unicodeBidi: style.unicodeBidi, minus, followingDigit, passed };
    });
  });
  report.measurements.bidi = evidence;
  for (const item of evidence) if (!item.passed) fail('bidi-minus-before-digit', item);
  fs.mkdirSync(screenshotsDir, { recursive: true });
  const filename = path.join(screenshotsDir, 'bidi-math-390.png');
  // Expand only this evidence capture, so all four mandatory examples are
  // visible together instead of being cut by the phone's scroll viewport.
  await page.locator('.phone').evaluate(phone => {
    Object.assign(phone.style, { height: 'auto', maxHeight: 'none', minHeight: '0', overflow: 'visible' });
    Object.assign(phone.querySelector('main.screen-content').style, { height: 'auto', maxHeight: 'none', minHeight: '0', flex: 'none', overflow: 'visible' });
  });
  await page.locator('.phone').screenshot({ path: filename });
  report.screenshots.push(path.relative(path.dirname(receiptPath), filename));
  if (evidence.every(item => item.passed)) checked('bidi: mandatory LTR islands and minus glyph left of following digit', { examples: evidence.length, screenshot: path.relative(path.dirname(receiptPath), filename), screenshotMode: '390px phone width, expanded scroll content to show every example together' });
}

async function checkNavigation(page, screens) {
  await page.setViewportSize({ width: 390, height: 844 });
  await navigate(page, 'home');
  const homeButtons = await page.locator('.phone .bottom-nav button').count();
  assert.ok(homeButtons > 0 && homeButtons <= 5, 'Student bottom navigation must contain one to five destinations.');
  const visited = [];
  for (let index = 0; index < homeButtons; index++) {
    await navigate(page, 'home');
    const button = page.locator('.phone .bottom-nav button').nth(index);
    const name = (await button.textContent()).trim();
    await button.click();
    const destination = await page.locator('.phone').getAttribute('data-screen');
    assert.ok(screens.some(screen => screen.id === destination), 'Bottom navigation must open an existing screen.');
    visited.push({ name, destination });
  }
  assert.equal(new Set(visited.map(v => v.destination)).size, homeButtons, 'Bottom destinations must not all route to the same fixture.');
  await navigate(page, 'parent-home');
  const parentButtons = await page.locator('.phone .bottom-nav button').count();
  assert.ok(parentButtons > 0 && parentButtons <= 5, 'Parent bottom navigation must contain one to five destinations.');
  for (let index = 0; index < parentButtons; index++) {
    await navigate(page, 'parent-home');
    await page.locator('.phone .bottom-nav button').nth(index).click();
    assert.equal(await page.locator('.phone').getAttribute('data-role'), 'parent', 'Parent navigation must not impersonate the child.');
  }
  for (const action of ['go:parent-reminders', 'go:report', 'go:parent-settings']) {
    await navigate(page, 'parent-home');
    await page.locator(`.phone header button[data-action="${action}"]`).click();
    assert.equal(await page.locator('.phone').getAttribute('data-role'), 'parent', 'Parent header must not enter a child account.');
  }
  await navigate(page, 'parent-settings');
  await page.locator('.phone button[data-action="go:parent-account-actions"]').click();
  assert.equal(await page.locator('.phone').getAttribute('data-role'), 'parent');
  for (const destination of ['parent-leave-family', 'parent-export-data', 'parent-delete-account']) {
    await navigate(page, 'parent-account-actions');
    await page.locator(`.phone button[data-action="go:${destination}"]`).click();
    assert.equal(await page.locator('.phone').getAttribute('data-role'), 'parent', 'Parent account management must remain in the parent role.');
    await page.locator('.phone button[data-action^="confirm:"]').click();
    assert.equal(await page.locator('.phone').getAttribute('data-screen'), 'parent-confirm-action');
    await page.locator('.phone input[type="checkbox"]').check();
    await page.locator('.phone button[data-action="go:parent-action-preview"]').click();
    assert.equal(await page.locator('.phone').getAttribute('data-role'), 'parent');
  }
  checked('clickable student navigation and separate parent navigation', { studentDestinations: visited, parentDestinationCount: parentButtons });
}

async function checkStateInteractions(page, screens) {
  const actions = [];
  await page.setViewportSize({ width: 390, height: 844 });
  for (const screen of screens) {
    for (const state of screen.states || ['normal']) {
      if (!['error', 'empty', 'offline', 'conflict', 'session', 'rate-limit'].includes(state)) continue;
      const variants = state === 'conflict' ? ['resolve:local', 'resolve:other'] : [state === 'session' ? 'go:welcome' : 'state:normal'];
      for (const action of variants) {
        await navigate(page, screen.id, state);
        // The component gallery intentionally contains its own error-banner
        // sample as well as the page's error state. Both retry controls have
        // identical semantics; exercise the first actual state control.
        await page.locator(`.phone button[data-action="${action}"]`).first().click();
        const after = await page.locator('.phone').getAttribute('data-state');
        assert.equal(after, 'normal', `${screen.id}/${state}/${action} must leave the error/system state.`);
        assert.equal(await page.locator('.phone').getAttribute('data-screen'), state === 'session' ? 'welcome' : screen.id);
        if (state === 'conflict') assert.match(await page.locator('.phone .toast').textContent(), /هیچ همگام‌سازی واقعی/);
        actions.push({ screen: screen.id, state, action, result: 'PASS' });
      }
    }
  }
  for (const state of ['wrong', 'expired']) {
    await navigate(page, 'otp', state);
    await page.locator('.phone button[data-action="state:cooldown"]').click();
    assert.equal(await page.locator('.phone').getAttribute('data-state'), 'cooldown');
    assert.equal(await page.locator('.phone button[data-action="noop"]').isDisabled(), true);
    await page.locator('.phone button[data-action="state:normal"]').click();
    assert.equal(await page.locator('.phone').getAttribute('data-state'), 'normal');
    actions.push({ screen: 'otp', state, action: 'resend cooldown -> simulated expiry -> normal', result: 'PASS' });
  }
  checked('retry, explicit conflict choices, offline reconnect, session re-entry, rate-limit and OTP cooldown controls change their fixture states', { actionCount: actions.length, actions });
}

async function checkQuiz(page) {
  await navigate(page, 'quiz');
  const answers = page.locator('[data-qa="quiz-answer"]');
  if (!await answers.count()) {
    fail('quiz-interaction', { message: 'Missing [data-qa=quiz-answer] interactive options.' }); return;
  }
  for (let question = 0; question < 10; question++) {
    assert.ok(await answers.count() >= 2, 'Each question needs at least two possible answers.');
    await answers.first().click();
    const next = page.locator('[data-qa="quiz-next"]');
    await next.click();
  }
  const result = page.locator('[data-qa="quiz-result"]');
  await result.waitFor({ state: 'visible' });
  const resultText = (await result.textContent()).trim();
  assert.ok(resultText.length > 0, 'The quiz must display its fictional score.');
  const review = page.locator('[data-qa="quiz-review"]');
  if (await review.count()) { await review.click(); assert.ok(await page.locator('[data-qa="answer-review"]').count() > 0, 'Answer review must show responses.'); }
  const retry = page.locator('[data-qa="quiz-retry"]');
  await retry.click();
  assert.ok(await page.locator('[data-qa="quiz-answer"]').count() >= 2, 'Retry must return to quiz questions.');
  checked('ten fictional quiz questions, displayed score, answer review and retry', { questionCount: 10, resultText });
}

async function checkBoard(page, expectedFrames) {
  await page.setViewportSize({ width: 1800, height: 1200 });
  await page.goto(new URL('?board=1', base).href, { waitUntil: 'networkidle' });
  await page.evaluate(() => document.fonts.ready);
  const board = await page.evaluate(requiredLabel => {
    const phones = [...document.querySelectorAll('.phone')];
    return phones.map(phone => ({ screen: phone.dataset.screen, state: phone.dataset.state, theme: phone.dataset.theme, label: phone.querySelector('.prototype-label')?.textContent.trim(), height: phone.getBoundingClientRect().height, overflow: [...phone.querySelectorAll('main.screen-content')].map(main => ({ scrollHeight: main.scrollHeight, clientHeight: main.clientHeight })) }));
  }, label);
  assert.ok(board.length >= 20, 'Complete board must contain at least twenty visible design frames.');
  assert.equal(board.length, expectedFrames.length, 'Board must render every declared board frame.');
  assert.ok(board.every(frame => frame.label === label), 'Every board frame must retain the fictional-design label.');
  checked('full board has every declared frame and design label', { frameCount: board.length, minimumRequired: 20, frames: board });
}

async function main() {
  let browser;
  try {
    assert.ok(['http:', 'https:'].includes(base.protocol), 'Use a local static HTTP(S) server.');
    assert.ok(['127.0.0.1', 'localhost', '[::1]'].includes(base.hostname), 'This design checker only opens a loopback static server; no live site is allowed.');
    browser = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || '/usr/bin/chromium', headless: true, args: ['--no-sandbox'] });
    report.browser = await browser.version();
    const context = await browser.newContext({ viewport: { width: 390, height: 844 }, locale: 'fa-IR' });
    await context.route('**/*', async route => {
      const request = route.request(), url = new URL(request.url());
      if (!['http:', 'https:'].includes(url.protocol)) return route.continue();
      if (url.origin !== base.origin) { report.externalRequests.push(safeRequest(request.url())); return route.abort('blockedbyclient'); }
      if (!['GET', 'HEAD'].includes(request.method()) || ['xhr', 'fetch', 'websocket', 'eventsource', 'ping'].includes(request.resourceType())) {
        report.forbiddenRequests.push({ url: safeRequest(request.url()), method: request.method(), resourceType: request.resourceType() });
        return route.abort('blockedbyclient');
      }
      return route.continue();
    });
    const page = await context.newPage();
    page.on('pageerror', error => report.runtimeErrors.push(error.message));
    page.on('response', response => {
      if (response.status() >= 400 && new URL(response.url()).origin === base.origin) report.failedStaticRequests.push({ url: safeRequest(response.url()), status: response.status() });
    });
    page.on('requestfailed', request => {
      if (new URL(request.url()).origin === base.origin) report.failedStaticRequests.push({ url: safeRequest(request.url()), failure: request.failure()?.errorText || 'failed' });
    });
    page.on('websocket', socket => report.forbiddenRequests.push({ url: safeRequest(socket.url()), resourceType: 'websocket' }));
    await page.goto(base.href, { waitUntil: 'networkidle' });
    await page.evaluate(() => document.fonts.ready);
    const contract = await page.evaluate(() => {
      const design = window.LifeGuideDesign;
      if (!design || !Array.isArray(design.screens) || typeof design.navigate !== 'function' || typeof design.reset !== 'function' || !Array.isArray(design.boardFrames)) return null;
      return { screens: design.screens, boardFrames: design.boardFrames };
    });
    assert.ok(contract, 'window.LifeGuideDesign must expose screens, boardFrames, navigate() and reset().');
    assert.ok(contract.screens.length >= 20, 'Screen inventory must include at least twenty distinct screens.');
    assert.equal(new Set(contract.screens.map(s => s.id)).size, contract.screens.length, 'Screen IDs must be unique.');
    for (const id of requiredMain) assert.ok(contract.screens.some(screen => screen.id === id), 'Missing required main screen: ' + id);
    checked('public design inspection contract and screen inventory', { screenCount: contract.screens.length, boardFrameCount: contract.boardFrames.length });
    await navigate(page, 'lesson');
    assert.equal(await page.locator('.phone video,.phone iframe,.phone object,.phone embed').count(), 0, 'Without an approved source the default lesson must not load a video/embed.');
    checked('default lesson has no video/embed source', { realVideoPlayback: 'UNVERIFIED' });
    const themeEvidence = [];
    for (const theme of themes) {
      await navigate(page, 'home', 'normal', theme);
      themeEvidence.push(await page.locator('.phone').evaluate(element => ({ theme: element.dataset.theme, primary: getComputedStyle(element).getPropertyValue('--primary').trim(), canvas: getComputedStyle(element).getPropertyValue('--canvas').trim(), bottomDestinations: [...element.querySelectorAll('.bottom-nav button')].map(button => button.textContent.trim()) })));
    }
    assert.notEqual(themeEvidence[0].primary + themeEvidence[0].canvas, themeEvidence[1].primary + themeEvidence[1].canvas, 'The two visual directions must actually change appearance.');
    assert.deepEqual(themeEvidence[0].bottomDestinations, themeEvidence[1].bottomDestinations, 'Visual directions must keep the same navigation structure.');
    checked('two visibly distinct directions retain the same navigation structure', { themes: themeEvidence });

    const layouts = [];
    for (const screen of contract.screens) {
      const states = [...new Set([...(screen.states || ['normal']), ...(requiredMain.includes(screen.id) || screen.main ? systemStates : [])])];
      for (const state of states) layouts.push({ screen: screen.id, state });
    }
    const initialFailureCount = report.failures.length;
    const normalFonts = new Map();
    for (const width of requestedWidths) {
      await page.setViewportSize({ width, height: 844 });
      for (const theme of themes) {
        for (const fontScale of [1, 2]) {
          for (const { screen, state } of layouts) {
            const auditContext = { screen, state, theme, viewportWidthPx: width, fontScale };
            try {
              await navigate(page, screen, state, theme, fontScale);
              const audit = await page.evaluate(auditLayout, { expectedScreen: screen, expectedState: state, expectedTheme: theme, fontScale, requiredLabel: label });
              updateMeasurements(audit, auditContext);
              const fontKey = `${width}:${theme}:${screen}:${state}`;
              if (fontScale === 1) normalFonts.set(fontKey, audit.stats.fontSamples);
              else {
                const originalFonts = normalFonts.get(fontKey) || [];
                for (let index = 0; index < originalFonts.length; index++) {
                  const original = originalFonts[index], enlarged = audit.stats.fontSamples[index];
                  if (!enlarged || original.selector !== enlarged.selector || original.text !== enlarged.text) {
                    fail('font-200-percent-coverage', { ...auditContext, message: 'Text changed between normal and enlarged layouts; cannot attest scaling.', original, enlarged });
                    break;
                  }
                  if (enlarged.fontSizePx < original.fontSizePx * 2 - 0.05) fail('font-did-not-enlarge-200-percent', { ...auditContext, selector: original.selector, text: original.text, originalPx: original.fontSizePx, enlargedPx: enlarged.fontSizePx });
                }
              }
            } catch (error) { fail('layout-evaluation', { ...auditContext, message: error.message }); }
          }
        }
      }
      console.log(`Measured width ${width}px: ${report.measurements.auditedLayouts} layouts; ${report.failures.length} cumulative failures.`);
    }
    if (report.failures.length === initialFailureCount) checked('rendered text >=12px, measured contrast >=4.5:1, targets >=48x48, no horizontal overflow or hidden text at 100% and 200%', { layouts: report.measurements.auditedLayouts, minimumFontPx: report.measurements.minimumFontPx, minimumContrast: report.measurements.minimumContrast, widths: requestedWidths, themes });

    for (const [name, action] of [
      ['bidi', () => checkBidi(page)],
      ['navigation', () => checkNavigation(page, contract.screens)],
      ['system-state-interactions', () => checkStateInteractions(page, contract.screens)],
      ['quiz', () => checkQuiz(page)],
      ['board', () => checkBoard(page, contract.boardFrames)],
    ]) {
      console.log(`Running interaction check: ${name}`);
      try { await action(); } catch (error) { fail(name, { message: error.message }); }
    }
    // An already loaded prototype must still change screens with all network
    // disabled, but this is not evidence of production offline synchronization.
    try {
      await page.goto(base.href, { waitUntil: 'networkidle' });
      await context.setOffline(true);
      await navigate(page, 'home');
      await page.locator('.phone .bottom-nav button').nth(1).click();
      assert.notEqual(await page.locator('.phone').getAttribute('data-screen'), 'home');
      await context.setOffline(false);
      checked('already loaded fixture remains locally navigable without network', { limitation: 'Not a PWA/service-worker/server-sync acceptance test.' });
    } catch (error) { fail('offline-design-navigation', { message: error.message }); await context.setOffline(false); }
    if (report.runtimeErrors.length) fail('javascript-runtime-errors', { errors: report.runtimeErrors });
    if (report.failedStaticRequests.length) fail('failed-local-static-assets', { requests: report.failedStaticRequests });
    if (report.externalRequests.length) fail('external-network-requests', { urls: [...new Set(report.externalRequests)] });
    if (report.forbiddenRequests.length) fail('server-or-authentication-connection', { requests: report.forbiddenRequests });
    if (!report.runtimeErrors.length && !report.externalRequests.length && !report.forbiddenRequests.length && !report.failedStaticRequests.length) checked('no JavaScript errors, failed static assets, external requests, or server/authentication traffic', { javascriptErrors: 0, failedStaticRequests: 0, externalRequests: 0, forbiddenRequests: 0 });
  } catch (error) {
    fail('checker-fatal-error', { message: error.message });
  } finally {
    if (browser) await browser.close();
    writeReport();
    console.log(JSON.stringify({ status: report.status, checksPassed: report.checks.length, measuredLayouts: report.measurements.auditedLayouts, failures: report.failureCount, minimumFontPx: report.measurements.minimumFontPx, minimumContrast: report.measurements.minimumContrast, receipt: receiptPath }, null, 2));
    if (!report.passed) {
      console.error(JSON.stringify(report.failures.slice(0, 20), null, 2));
      process.exitCode = 1;
    }
  }
}

module.exports = { auditLayout };
if (require.main === module) main();
