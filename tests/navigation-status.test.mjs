import test from 'node:test';
import assert from 'node:assert/strict';
import { ModalNavigation } from '../preview/modal-navigation.mjs';
import { statusForSnapshot, SERVICE_MESSAGES, OfficialEmptyConfirmation } from '../preview/service-status.mjs';
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
  for (const state of ['login_required', 'loading', 'error', 'filtered_empty']) {
    const before = JSON.stringify(records);
    assert.throws(() => mergeOfficialSnapshot(records, { state, parcels: [], expectedCount: 0 }));
    assert.equal(JSON.stringify(records), before);
    assert.match(statusForSnapshot({ state }), /保留/);
  }
  assert.equal(statusForSnapshot({ state: 'login_required' }), SERVICE_MESSAGES.login);
  assert.equal(statusForSnapshot({ state: 'filtered_empty' }), SERVICE_MESSAGES.phoneFilter);
  assert.notEqual(statusForSnapshot({ state: 'loading' }), statusForSnapshot({ state: 'error' }));
  assert.equal(statusForSnapshot({ state: 'ready' }), null);
});

test('空清单确认不接受相同快照重放、过期读数、加载/登录打断或矛盾数据', () => {
  const candidate = {state:'filtered_empty',parcels:[],expectedCount:null,readAt:'2026-10-31T04:00:00.000Z'};
  const later = {...candidate,readAt:'2026-10-31T04:00:00.750Z'};
  const confirmation = new OfficialEmptyConfirmation();
  assert.equal(confirmation.accepting(candidate).state,'filtered_empty');
  assert.equal(confirmation.accepting(candidate).state,'filtered_empty');
  assert.equal(confirmation.accepting(later).state,'ready');
  for (const interrupt of [{state:'loading'}, {state:'login_required'}, {state:'error'}, {state:'ready',parcels:[],expectedCount:0},
    {...candidate,readAt:'invalid'}, {...candidate,parcels:[{id:'partial'}]}, {...candidate,expectedCount:1}]) {
    confirmation.reset();
    confirmation.accepting(candidate);
    confirmation.accepting(interrupt);
    assert.equal(confirmation.accepting(later).state,'filtered_empty');
  }
  confirmation.reset();
  confirmation.accepting(candidate);
  assert.equal(confirmation.accepting({...later,readAt:'2026-10-31T04:00:06.000Z'}).state,'filtered_empty');
  confirmation.reset();
  assert.equal(confirmation.accepting(later).state,'filtered_empty');
});
