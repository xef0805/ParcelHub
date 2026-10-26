import test from 'node:test';
import assert from 'node:assert/strict';
import { ModalNavigation } from '../preview/modal-navigation.mjs';
import { statusForSnapshot, SERVICE_MESSAGES } from '../preview/service-status.mjs';
import { mergeOfficialSnapshot } from '../preview/model.mjs';

test('设置三级页面逐级返回并恢复各自滚动位置，不越过根设置', () => {
  const root = () => 'settings', links = () => 'links', binding = () => 'binding';
  const nav = new ModalNavigation();
  nav.start(root); nav.push(links, 180); nav.push(binding, 72);
  assert.equal(nav.depth, 3);
  assert.equal(nav.back().render, links); assert.equal(nav.current.scrollTop, 72);
  assert.equal(nav.back().render, root); assert.equal(nav.current.scrollTop, 180);
  assert.equal(nav.back().render, root); assert.equal(nav.depth, 1);
  nav.clear(); assert.equal(nav.depth, 0); assert.equal(nav.current, undefined);
});
test('新的设置会话不继承上次关闭前的子页面', () => {
  const nav = new ModalNavigation();
  nav.start(() => 'old'); nav.push(() => 'child', 40);
  const fresh = () => 'fresh'; nav.start(fresh);
  assert.equal(nav.depth, 1); assert.equal(nav.current.render, fresh); assert.equal(nav.current.scrollTop, 0);
});
test('登录失效、加载和错误提示不同，非完整快照均不能清空原记录', () => {
  const records = { version: 1, customProviders: [], parcels: [{ id: 'keep', title: '保留原记录' }] };
  for (const state of ['login_required', 'loading', 'error']) {
    const before = JSON.stringify(records);
    assert.throws(() => mergeOfficialSnapshot(records, { state, parcels: [], expectedCount: 0 }));
    assert.equal(JSON.stringify(records), before);
    assert.match(statusForSnapshot({ state }), /保留/);
  }
  assert.equal(statusForSnapshot({ state: 'login_required' }), SERVICE_MESSAGES.login);
  assert.notEqual(statusForSnapshot({ state: 'loading' }), statusForSnapshot({ state: 'error' }));
  assert.equal(statusForSnapshot({ state: 'ready' }), null);
});
