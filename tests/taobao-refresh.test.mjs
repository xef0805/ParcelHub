import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import {readFile} from 'node:fs/promises';
import {mergeOfficialSnapshot, filterParcels} from '../preview/model.mjs';

const source = await readFile(new URL('../shared/taobao-refresh.js', import.meta.url), 'utf8');
const api = 'mtop.cainiao.pickup.plus.queryMultiStaPackages4Xy';
const success = {ret: ['SUCCESS::调用成功'], data: {privateTestValue: 'not-for-status'}};
function setup(request, path = '/wow/z/uniapp/1100333/last-mile-fe/m-end-school-tab/home') {
  let now = 1000;
  const listeners = new Map(), intervals = [];
  const window = {lib: {mtop: {request}}};
  const context = vm.createContext({window, location: {hostname: 'pages-fast.m.taobao.com', pathname: path},
    document: {addEventListener: (event, callback) => listeners.set(event, callback)},
    Date: {now: () => now}, setInterval: fn => (intervals.push(fn), intervals.length), setTimeout() {}, clearInterval() {}});
  vm.runInContext(source, context);
  return {window, read: () => window.__tutuTaobaoFreshness?.read(), advance: ms => now += ms, listeners, intervals,
    inject: () => vm.runInContext(source, context)};
}
const tick = async () => { await Promise.resolve();await Promise.resolve(); };

test('普通取件查询沿用官方 refresh:true，保留其他参数，不修改原始对象或 Promise', async () => {
  let captured, owner;
  const promise = Promise.resolve(success);
  const h = setup(function(params) {captured = params;owner = this;return promise;});
  const input = {api, data: {stationCode: 'TEST', activeTab: 'PENDING_PICKUP', refresh: false}, timeout: 1000};
  const original = JSON.stringify(input);
  const returned = h.window.lib.mtop.request(input);
  assert.equal(returned, promise);
  assert.equal(owner, h.window.lib.mtop);
  assert.equal(captured.data.refresh, true);
  assert.equal(captured.data.stationCode, 'TEST');
  assert.equal(captured.data.activeTab, 'PENDING_PICKUP');
  assert.equal(captured.timeout, 1000);
  assert.equal(JSON.stringify(input), original);
  assert.equal(h.read().state, 'loading');
  await tick();
  assert.equal(h.read().state, 'loading');
  h.advance(500);
  assert.equal(h.read().state, 'ready');
  assert.ok(!JSON.stringify(h.read()).includes('privateTestValue'));
});

test('旧 DOM、未调用清单接口及无关请求不能证明刷新成功；其他业务请求完全保持原样', async () => {
  let args;
  const h = setup(function() {args = [...arguments];return Promise.resolve(success);});
  assert.equal(h.read().state, 'waiting');
  const input = {api: 'mtop.cainiao.pickup.waybill.createCollectionTask', data: {action: 'unchanged'}};
  const callback = () => {};
  await h.window.lib.mtop.request(input, callback);
  assert.equal(args[0], input);
  assert.equal(args[1], callback);
  h.advance(10000);
  assert.equal(h.read().state, 'waiting');
});

test('兼容 JSON 字符串数据与官方回调，原样转交响应及回调返回值', () => {
  let captured, returnValue;
  const h = setup((params, callback) => {captured = params;returnValue = callback(success);return 'original-return';});
  const input = {api, data: '{"stationCode":"TEST"}'};
  assert.equal(h.window.lib.mtop.request(input, response => {assert.equal(response, success);return 42;}), 'original-return');
  assert.equal(returnValue, 42);
  assert.equal(captured.data.refresh, true);
  assert.equal(input.data, '{"stationCode":"TEST"}');
  h.advance(500);
  assert.equal(h.read().state, 'ready');
});

test('接口报错、登录失效和同步异常不能把旧卡片标为最新', async () => {
  for (const [ret, state] of [['FAIL_SYS_SESSION_EXPIRED::登录失效', 'login_required'], ['FAIL_SYS_TOKEN_EXOIRED::令牌过期', 'login_required'], ['FAIL_SYS_SERVICE_FAULT::请求失败', 'error']]) {
    const error = {ret: [ret]};
    const h = setup(() => Promise.reject(error));
    await assert.rejects(h.window.lib.mtop.request({api, data: {}}), value => value === error);
    await tick();h.advance(500);
    assert.equal(h.read().state, state);
  }
  const error = new Error('test network error'), h = setup(() => {throw error;});
  assert.throws(() => h.window.lib.mtop.request({api, data: {}}), value => value === error);
  assert.equal(h.read().state, 'error');
});

test('并发查询等待全部结束，旧查询的迟到结果不能覆盖较新查询失败', async () => {
  const complete = [];
  const h = setup(() => new Promise((resolve, reject) => complete.push({resolve, reject})));
  const first = h.window.lib.mtop.request({api, data: {}});
  const second = h.window.lib.mtop.request({api, data: {}});
  complete[1].reject({ret: ['FAIL_SYS_SERVICE_FAULT']});
  await assert.rejects(second);await tick();h.advance(500);
  assert.equal(h.read().state, 'loading');
  complete[0].resolve(success);await first;await tick();
  assert.equal(h.read().state, 'error');
});

test('兼容旧版清单接口但不猜它的刷新参数；畸形请求保留官方处理', async () => {
  let captured;
  const h = setup(params => {captured = params;return Promise.resolve(success);});
  const input = {api: 'mtop.cainiao.pickup.xiaoyuan.queryMultisitePkgs', data: {pageNum: 1}};
  await h.window.lib.mtop.request(input);await tick();h.advance(500);
  assert.equal(captured, input);
  assert.equal(h.read().state, 'ready');
  const invalid = setup(params => {captured = params;return Promise.resolve(success);});
  const bad = {api, data: '{invalid'};
  await invalid.window.lib.mtop.request(bad);await tick();
  assert.equal(captured, bad);
  assert.equal(invalid.read().state, 'waiting');
});

test('延迟加载 MTOP 可安装，重复脚本及库 load 事件不重复包装；身份码页不注入', async () => {
  let calls = 0;
  const h = setup(null);
  h.window.lib.mtop.request = () => {calls++;return Promise.resolve(success);};
  h.listeners.get('load')();
  const installed = h.window.lib.mtop.request;
  h.inject();h.listeners.get('load')();h.intervals[0]();
  assert.equal(h.window.lib.mtop.request, installed);
  await installed({api, data: {}});await tick();h.advance(500);
  assert.equal(calls, 1);
  assert.equal(h.read().serial, 1);
  assert.equal(h.read().state, 'ready');
  const identity = setup(() => {}, '/wow/z/uniapp/1100410/last-mile-fe/m-end-identity-code/home');
  assert.equal(identity.read(), undefined);
});

test('实际导入门禁拒绝旧清单和旧空页；成功的新清单才归档已取件', async () => {
  const catalog = JSON.parse(await readFile(new URL('../shared/catalog.json', import.meta.url), 'utf8'));
  const row = {providerID: 'taobao', title: '测试包裹', station: '测试驿站', pickupCode: '1-2-0003', carrier: '中通', trackingNumber: 'TESTZTO00001'};
  const snapshot = parcels => ({state: 'ready', message: '', parcels, expectedCount: parcels.length, readAt: new Date().toISOString()});
  const state = mergeOfficialSnapshot({version: 1, customProviders: [], parcels: []}, snapshot([row]));
  const before = JSON.stringify(state);
  let complete;
  const h = setup(() => new Promise(resolve => {complete = resolve;}));
  const verify = h.window.__tutuTaobaoFreshness.verify;
  for (const parcels of [[row], []]) {
    const blocked = verify(snapshot(parcels));
    assert.equal(blocked.state, 'loading');
    assert.equal(blocked.parcels.length, 0);
    assert.equal(blocked.expectedCount, null);
    assert.throws(() => mergeOfficialSnapshot(state, blocked));
    assert.equal(JSON.stringify(state), before);
  }
  const promise = h.window.lib.mtop.request({api, data: {}});
  complete(success);await promise;await tick();
  assert.equal(verify(snapshot([])).state, 'loading');
  h.advance(500);
  const next = mergeOfficialSnapshot(state, verify(snapshot([])));
  assert.equal(filterParcels(next, catalog).length, 0);
  assert.equal(filterParcels(next, catalog, {collected: true}).length, 1);
});

test('实际门禁转交登录和错误，查询失败及新查询进行中均不能复用上次成功', async () => {
  let response = success;
  const h = setup(() => Promise.resolve(response));
  const verify = h.window.__tutuTaobaoFreshness.verify;
  const snapshot = {state: 'ready', parcels: [{trackingNumber: 'PRIVATE_TEST'}], expectedCount: 1, readAt: new Date().toISOString()};
  for (const state of ['error', 'login_required']) {
    const failure = {...snapshot, state};
    assert.equal(verify(failure), failure);
  }
  await h.window.lib.mtop.request({api, data: {}});await tick();h.advance(500);
  assert.equal(verify(snapshot), snapshot);
  response = {ret: ['FAIL_SYS_SERVICE_FAULT']};
  const retry = h.window.lib.mtop.request({api, data: {}});
  assert.equal(verify(snapshot).state, 'loading');
  await retry;await tick();h.advance(500);
  assert.equal(verify(snapshot).state, 'error');
  assert.ok(!JSON.stringify(verify(snapshot)).includes('PRIVATE_TEST'));
  response = {ret: ['FAIL_SYS_SESSION_EXPIRED']};
  await h.window.lib.mtop.request({api, data: {}});await tick();
  assert.equal(verify(snapshot).state, 'login_required');
});
