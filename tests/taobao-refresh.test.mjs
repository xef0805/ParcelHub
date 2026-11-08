import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import {readFile} from 'node:fs/promises';
import {mergeOfficialSnapshot, filterParcels} from '../preview/model.mjs';

const source = await readFile(new URL('../shared/taobao-refresh.js', import.meta.url), 'utf8');
const parsePage = vm.runInNewContext(await readFile(new URL('../shared/cainiao-reader.js', import.meta.url), 'utf8'));
const api = 'mtop.cainiao.pickup.plus.queryMultiStaPackages4Xy';
const success = {ret: ['SUCCESS::调用成功'], data: {result: {privateTestValue: 'not-for-status', componentList: [
  {componentCode: 'tabInfo', data: [{tabKey: 'PENDING_PICKUP', active: true}]}
]}}};
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

test('辅助查件接口不能证明完整清单已刷新；畸形请求保留官方处理', async () => {
  let captured;
  const h = setup(params => {captured = params;return Promise.resolve(success);});
  const input = {api: 'mtop.cainiao.pickup.xiaoyuan.queryMultisitePkgs', data: {pageNum: 1}};
  await h.window.lib.mtop.request(input);await tick();h.advance(500);
  assert.equal(captured, input);
  assert.equal(h.read().state, 'waiting');
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

test('实际门禁转交登录，页面错误等待本轮查询，失败及重试不能复用上次成功', async () => {
  let response = success;
  const h = setup(() => Promise.resolve(response));
  const verify = h.window.__tutuTaobaoFreshness.verify;
  const snapshot = {state: 'ready', parcels: [{trackingNumber: 'PRIVATE_TEST'}], expectedCount: 1, readAt: new Date().toISOString()};
  const login = {...snapshot, state: 'login_required'};
  const pageError = {...snapshot, state: 'error'};
  assert.equal(verify(login), login);
  assert.equal(verify(pageError).state, 'loading');
  await h.window.lib.mtop.request({api, data: {}});await tick();h.advance(500);
  assert.equal(verify(snapshot), snapshot);
  assert.equal(verify(pageError), pageError);
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

test('首次查询明确请求待取件，用户主动选择其他标签仍原样发送但不能导入', async () => {
  let captured;
  const h = setup(params => {captured = params;return Promise.resolve(success);});
  const original = {api, data: {stationCode: 'TEST'}};
  await h.window.lib.mtop.request(original);await tick();h.advance(500);
  assert.equal(captured.data.activeTab, 'PENDING_PICKUP');
  assert.equal(original.data.activeTab, undefined);
  for (const activeTab of ['TRACKING', 'SIGNED', 'RETURNED']) {
    await h.window.lib.mtop.request({api, data: {activeTab}});await tick();h.advance(500);
    assert.equal(captured.data.activeTab, activeTab);
    assert.equal(h.read().state, 'other_tab');
    assert.equal(h.window.__tutuTaobaoFreshness.verify({state: 'ready', parcels: [], readAt: 'test'}).state, 'error');
  }
});

test('复现空状态与旧数量冲突，等待新请求及页面更新后才导入新到包裹', async () => {
  let complete;
  const h = setup(() => new Promise(resolve => {complete = resolve;}));
  const verify = h.window.__tutuTaobaoFreshness.verify;
  const before = parsePage('待取件（1）\n未查到100****0000的包裹');
  assert.equal(before.state, 'error');
  assert.equal(before.retryable, true);
  assert.equal(verify(before).state, 'loading');
  const request = h.window.lib.mtop.request({api, data: {}});
  assert.equal(verify(before).state, 'loading');
  complete(success);await request;await tick();h.advance(500);
  assert.equal(verify(before).state, 'loading');
  const after = parsePage('待取件（1）\n测试北门驿站\n看包裹\n01-2-0003\n今日到站\n中通 TESTZTO00001\n还有包裹未显示？查询取件码');
  const verified = verify(after);
  assert.equal(verified.state, 'ready');
  const updated = mergeOfficialSnapshot({version: 1, customProviders: [], parcels: []}, JSON.parse(JSON.stringify(verified)));
  assert.equal(updated.parcels.length, 1);
  assert.equal(updated.parcels[0].trackingNumber, 'TESTZTO00001');
  assert.throws(() => mergeOfficialSnapshot(updated, verify(before)));
});

test('空页、残留卡片和数量矛盾仍不能清空，诊断只记录数量和布尔状态', async () => {
  const response = {ret: ['SUCCESS::test'], data: {componentList: [
    {componentCode: 'tabInfo', data: [{tabKey: 'PENDING_PICKUP', active: true, count: 0}]}
  ], mobile: 'PRIVATE_PHONE', waybillNo: 'PRIVATE_WAYBILL'}};
  const h = setup(() => Promise.resolve(response));
  await h.window.lib.mtop.request({api, data: {}});await tick();h.advance(500);
  const verify = h.window.__tutuTaobaoFreshness.verify;
  for (const text of [
    '待取件（1）\n未查到100****0000的包裹',
    '待取件\n0\n未查到100****0000的包裹\n01-2-0003',
    '待取件（1）\n暂无待取包裹'
  ]) {
    const snapshot = parsePage(text);
    assert.equal(verify(snapshot).state, 'loading');
    assert.equal(snapshot.diagnostics.badgeCount === null || typeof snapshot.diagnostics.badgeCount === 'number', true);
    assert.ok(!JSON.stringify(snapshot.diagnostics).includes('100****0000'));
    assert.ok(!JSON.stringify(snapshot.diagnostics).includes('01-2-0003'));
  }
  assert.equal(h.read().manifest.pendingCount, 0);
  assert.equal(h.read().manifest.activeTab, 'PENDING_PICKUP');
  assert.ok(!JSON.stringify(h.read()).includes('PRIVATE_'));
});

test('服务端返回其他活动标签时拒绝导入，未知响应只显示未知而不编造数量', async () => {
  let response = {ret: ['SUCCESS::test'], data: {componentList: [
    {componentCode: 'tabInfo', data: [{tabKey: 'SIGNED', active: true}, {tabKey: 'PENDING_PICKUP', count: 2}]}
  ]}};
  const h = setup(() => Promise.resolve(response));
  await h.window.lib.mtop.request({api, data: {}});await tick();h.advance(500);
  assert.equal(h.read().state, 'other_tab');
  assert.equal(h.read().manifest.pendingCount, 2);
  response = {ret: ['SUCCESS::test'], data: {result: {unrecognized: true}}};
  await h.window.lib.mtop.request({api, data: {}});await tick();h.advance(500);
  assert.equal(h.read().manifest.schema, 'unknown');
  assert.equal(h.read().manifest.pendingCount, null);
});

test('新响应仍有包裹时，旧空页不能归档；页面数量须与响应明确给出的待取数量相符', async () => {
  const h = setup(() => Promise.resolve({ret: ['SUCCESS::test'], data: {componentList: [
    {componentCode: 'tabInfo', data: [{tabKey: 'PENDING_PICKUP', active: true, count: 1}]}
  ]}}));
  await h.window.lib.mtop.request({api, data: {}});await tick();h.advance(500);
  const verify = h.window.__tutuTaobaoFreshness.verify;
  for (const text of ['待取件\n0\n暂无待取件', '待取件\n未查到100****0000的包裹']) {
    assert.equal(verify(parsePage(text)).state, 'loading');
  }
  const snapshot = {state: 'ready', expectedCount: 1, parcels: [{trackingNumber: 'TEST_ONLY'}], readAt: 'test'};
  assert.equal(verify(snapshot), snapshot);
  assert.equal(verify({...snapshot, expectedCount: 2}).state, 'loading');
});

test('官方库原地将 data 转成签名用 JSON 后，仍能确认待取标签且不改调用方数据', async () => {
  const input = {api, data: {stationCode: 'TEST'}};
  const h = setup(params => {
    params.data = JSON.stringify(params.data);
    return Promise.resolve(success);
  });
  await h.window.lib.mtop.request(input);await tick();h.advance(500);
  assert.equal(h.read().state, 'ready');
  assert.equal(h.read().manifest.requestedTab, 'PENDING_PICKUP');
  assert.equal(input.data.stationCode, 'TEST');
  assert.equal(input.data.activeTab, undefined);
});

// 包装路径依据 2026-11-08 核对的官方 main.js 模块7354，以下内容全部虚构。
test('按官方适配器解包 result 或 data，再核对本轮待取标签和数量', async () => {
  for (const envelope of ['result', 'data']) {
    const body = {componentList: [
      {componentCode: 'tabInfo', data: [{tabKey: 'PENDING_PICKUP', active: true, count: 2}]},
      {componentCode: 'stationPkgGroup', data: []}
    ], mobile: 'PRIVATE_PHONE', waybillNo: 'PRIVATE_WAYBILL'};
    const response = {ret: ['SUCCESS::test'], data: {[envelope]: body}};
    const before = JSON.stringify(response);
    const h = setup(() => Promise.resolve(response));
    await h.window.lib.mtop.request({api, data: {}});await tick();h.advance(500);
    assert.equal(h.read().manifest.schema, 'components');
    assert.equal(h.read().manifest.envelope, envelope);
    assert.equal(h.read().manifest.pendingCount, 2);
    assert.equal(h.read().manifest.activeTab, 'PENDING_PICKUP');
    assert.equal(h.read().manifest.stationGroupPresent, true);
    const verify = h.window.__tutuTaobaoFreshness.verify;
    const good = {state: 'ready', expectedCount: 2, parcels: [{}, {}], readAt: 'test'};
    assert.equal(verify(good), good);
    assert.equal(verify({...good, expectedCount: 0, parcels: []}).state, 'loading');
    assert.equal(verify(parsePage('待取件\n未查到100****0000的包裹')).state, 'loading');
    assert.equal(JSON.stringify(response), before);
    assert.ok(!JSON.stringify(h.read()).includes('PRIVATE_'));
  }
});

test('官方 result 优先于 data；旧结构诊断只输出组数、包裹数和明确空状态', async () => {
  let response = {ret: ['SUCCESS::test'], data: {
    result: {staPkgAssembles: [{certainPkgList: [{waybillNo: 'PRIVATE_TEST'}]}]},
    data: {componentList: []}
  }};
  const h = setup(() => Promise.resolve(response));
  await h.window.lib.mtop.request({api, data: {}});await tick();h.advance(500);
  assert.equal(h.read().manifest.schema, 'legacy');
  assert.equal(h.read().manifest.legacyGroupCount, 1);
  assert.equal(h.read().manifest.legacyPackageCount, 1);
  assert.equal(h.read().manifest.legacyEmpty, false);
  assert.ok(!JSON.stringify(h.read()).includes('PRIVATE_'));
  response = {ret: ['SUCCESS::test'], data: {data: {staPkgAssembles: [], noPkgInfoResp: {mobile: 'PRIVATE_PHONE'}}}};
  await h.window.lib.mtop.request({api, data: {}});await tick();h.advance(500);
  assert.equal(h.read().manifest.legacyEmpty, true);
  assert.equal(h.window.__tutuTaobaoFreshness.verify(parsePage('待取件\n未查到100****0000的包裹')).state, 'filtered_empty');
  assert.ok(!JSON.stringify(h.read()).includes('PRIVATE_'));
});

test('用户诊断中的未知成功响应、字符串和业务失败不能为旧清单或空清单背书', async () => {
  for (const data of [{result: {unknown: true}}, {data: 'PRIVATE_RESPONSE'}, {result: {success: false, componentList: []}}]) {
    const h = setup(() => Promise.resolve({ret: ['SUCCESS::test'], data}));
    await h.window.lib.mtop.request({api, data: {}});await tick();h.advance(500);
    const verify = h.window.__tutuTaobaoFreshness.verify;
    for (const snapshot of [
      {state: 'ready', expectedCount: 0, parcels: [], readAt: 'test'},
      {state: 'ready', expectedCount: 1, parcels: [{}], readAt: 'test'},
      parsePage('待取件\n未查到100****0000的包裹')
    ]) assert.equal(verify(snapshot).state, 'error');
    assert.ok(!JSON.stringify(h.read()).includes('PRIVATE_'));
  }
});

test('手机号空页只有得到本轮响应的零件证据才能进入二次空清单确认', async () => {
  let count;
  const h = setup(() => Promise.resolve({ret: ['SUCCESS::test'], data: {result: {componentList: [
    {componentCode: 'tabInfo', data: [{tabKey: 'PENDING_PICKUP', active: true, count}]},
    {componentCode: 'noPackage', data: {mobile: 'PRIVATE_PHONE'}}
  ]}}}));
  const snapshot = parsePage('待取件\n未查到100****0000的包裹');
  const verify = h.window.__tutuTaobaoFreshness.verify;
  for (const value of [undefined, 1, 0]) {
    count = value;
    await h.window.lib.mtop.request({api, data: {}});await tick();h.advance(500);
    assert.equal(verify(snapshot).state, value === 0 ? 'filtered_empty' : 'loading');
  }
});

test('解包后的旧清单不能被旧空页覆盖；缺少活动标签或残缺旧结构不能确认完整清单', async () => {
  for (const body of [
    {staPkgAssembles: [{certainPkgList: [{waybillNo: 'TEST_ONLY'}]}]},
    {staPkgAssembles: [{}]},
    {componentList: []},
    {componentList: [{componentCode: 'tabInfo', data: [{tabKey: 'PENDING_PICKUP', count: 0}]}]}
  ]) {
    const h = setup(() => Promise.resolve({ret: ['SUCCESS::test'], data: {result: body}}));
    await h.window.lib.mtop.request({api, data: {}});await tick();h.advance(500);
    const verify = h.window.__tutuTaobaoFreshness.verify;
    for (const snapshot of [
      parsePage('待取件\n0\n暂无待取件'),
      parsePage('待取件\n未查到100****0000的包裹')
    ]) assert.notEqual(verify(snapshot).state, snapshot.state);
  }
});
