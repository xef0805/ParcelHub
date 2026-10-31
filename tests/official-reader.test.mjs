import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { readFile } from 'node:fs/promises';
import { mergeOfficialSnapshot, demoState, filterParcels } from '../preview/model.mjs';
import { OfficialEmptyConfirmation, SERVICE_MESSAGES } from '../preview/service-status.mjs';

const source = await readFile(new URL('../shared/cainiao-reader.js', import.meta.url), 'utf8');
const read = vm.runInNewContext(source);
test('明确的重新登录与会话过期文案不会被当作空清单', () => {
  for (const text of ['请重新登录', '登录状态已失效', '会话已过期']) {
    const result = read(`${text}\n待取件\n0\n暂无待取件`);
    assert.equal(result.state, 'login_required');
    assert.equal(result.expectedCount, null);
  }
});
// 以下均为虚构测试数据，不包含实际账号、真实运单或真实取件码。
const page = ['身份码', '待取件', '2', '追踪中', '已签收', '3', '测试社区菜鸟驿站',
  '看包裹', '01-2-0001', '今日到站', '本人 测* 100****0000', '圆通 TESTYT0000001',
  '其他问题', '看包裹', '02-3-0002', '已到2天', '本人 测* 100****0000', '韵达 TESTYD0000002',
  '还有包裹未显示？查询取件码', '广告内容', '03-1-0003', '申通 TESTST0000003'].join('\n');

test('从官方当前待取件区读取卡片，排除其他状态数量与下方广告', () => {
  const result = read(page);
  assert.equal(result.state, 'ready');
  assert.equal(result.expectedCount, 2);
  assert.equal(result.parcels.length, 2);
  assert.equal(result.parcels[0].pickupCode, '01-2-0001');
  assert.equal(result.parcels[1].trackingNumber, 'TESTYD0000002');
  assert.equal(result.parcels[0].station, '测试社区菜鸟驿站');
  assert.equal('phone' in result.parcels[0], false);
});

test('完整非空清单不被页面其他位置的推荐加载文案阻断', () => {
  for (const text of [page + '\n加载中', '加载中...\n' + page, page.replace('广告内容', '加载中')]) {
    const result = read(text);
    assert.equal(result.state, 'ready');
    assert.equal(result.parcels.length, 2);
    assert.equal(result.expectedCount, 2);
  }
  // 加载中的零件占位与残缺卡片仍不能成为完整快照。
  assert.notEqual(read('待取件\n0\n暂无待取包裹\n加载中').state, 'ready');
  assert.notEqual(read(page.replace('韵达 TESTYD0000002', '加载中')).state, 'ready');
});
test('接口超时、登录页和未加载数量不能解释成零包裹', () => {
  assert.equal(read('待取件\n0\n接口超时').state, 'error');
  assert.equal(read('您需要登录才能继续访问\n账号密码登录').state, 'login_required');
  assert.equal(read('身份码\n寄快递\n加载中').state, 'loading');
});
test('必须与官方数量一致，禁止部分读取覆盖完整清单', () => {
  assert.equal(read(page.replace('待取件\n2', '待取件\n3')).state, 'error');
  assert.equal(read(page.replace('圆通 TESTYT0000001', '尚未加载运单')).state, 'error');
});
test('明确显示零件时可以得到完整空快照', () => {
  const result = read('待取件\n0\n已签收\n4\n暂无待取包裹\n还有包裹未显示？查询取件码');
  assert.equal(result.state, 'ready');
  assert.equal(result.parcels.length, 0);
});

test('按手机号未查到包裹不能当作加载中或账号完整空清单，也不回传手机号', () => {
  for (const notice of ['未查到100****0000的包裹', '未查到\n100****0000\n›\n的包裹']) {
    const result = read(`输入包裹快递单号查询\n待取件\n追踪中\n已签收3\n已退回\n${notice}\n加载中`);
    assert.equal(result.state, 'filtered_empty');
    assert.equal(result.expectedCount, null);
    assert.equal(result.parcels.length, 0);
    assert.equal(result.message, SERVICE_MESSAGES.phoneFilter);
    assert.equal(JSON.stringify(result).includes('100****0000'), false);
    assert.throws(() => mergeOfficialSnapshot(demoState(), JSON.parse(JSON.stringify(result))));
  }
  assert.equal(read('待取件\n未查到包裹').state, 'loading');
  assert.equal(read('请重新登录\n待取件\n未查到100****0000的包裹').state, 'login_required');
});

test('取完后连续两次确认手机号空清单，移出淘宝旧件并保留其他来源、短信和历史', () => {
  const original = mergeOfficialSnapshot({version:1,customProviders:[],parcels:[]}, JSON.parse(JSON.stringify(read(page))));
  const example = original.parcels[0];
  original.parcels[0].smsOriginal = '虚构短信原文';
  original.parcels.push(
    {...example,id:'sms-only',trackingNumber:'SMS0000001',source:'sms',providerID:'manual',credentials:null},
    {...example,id:'other-source',trackingNumber:'TUXI000001',source:'tuxi-web',providerID:'tuxi',credentials:null},
    {...example,id:'collected',trackingNumber:'COLLECTED0001',collectedAt:'2026-10-30T00:00:00Z',credentials:null}
  );
  const text = '输入包裹快递单号查询\n待取件\n追踪中\n已签收5\n已退回\n未查到\n100****0000\n的包裹\n首页\n身份码\n我的\n加载中';
  const confirmation = new OfficialEmptyConfirmation();
  const first = confirmation.accepting({...JSON.parse(JSON.stringify(read(text))),readAt:'2026-10-31T04:00:00.000Z'});
  assert.equal(first.state,'filtered_empty');
  assert.throws(()=>mergeOfficialSnapshot(original,first));
  const second = confirmation.accepting({...JSON.parse(JSON.stringify(read(text))),readAt:'2026-10-31T04:00:00.750Z'});
  assert.equal(second.state,'ready');
  assert.equal(second.expectedCount,0);
  const updated = mergeOfficialSnapshot(original,second);
  assert.deepEqual(filterParcels(updated,[]).map(p=>p.id).sort(),['other-source','sms-only']);
  assert.equal(updated.parcels.length,original.parcels.length);
  assert.equal(updated.parcels.find(p=>p.id===example.id).smsOriginal,'虚构短信原文');
  assert.equal(filterParcels(updated,[],{collected:true}).length,1);
  assert.equal(original.parcels[0].inLatestOfficialSnapshot,true);
});

test('手机号空提示与正数量或残留取件卡片冲突时不能确认清空', () => {
  for (const text of [
    '待取件（1）\n未查到100****0000的包裹',
    '待取件\n0\n未查到100****0000的包裹\n01-2-0001'
  ]) assert.equal(read(text).state,'error');
  assert.equal(read('待取件\n追踪中\n已签收5\n您的2个手机号\n›\n都未查到包裹').state,'filtered_empty');
});
test('官方读取可合并已有手动记录，保留原记录标识和前导零', () => {
  const snapshot = JSON.parse(JSON.stringify(read(page)));
  const original = { version: 1, customProviders: [], parcels: [{ ...demoState().parcels[0], id: 'existing', isDemo: false,
    carrier: '圆通', trackingNumber: 'TESTYT0000001', source: 'manual', pickupCode: 'old' }] };
  const merged = mergeOfficialSnapshot(original, snapshot);
  assert.equal(merged.parcels.length, 2);
  assert.equal(merged.parcels.find(p => p.id === 'existing').pickupCode, '01-2-0001');
  assert.equal(merged.parcels.every(p => p.source === 'taobao-web' && p.providerID === 'taobao'), true);
  assert.equal(original.parcels[0].pickupCode, 'old');
});
test('本次清单不再出现的记录只移出当前快照，不伪造已取状态', () => {
  const first = mergeOfficialSnapshot(demoState(), JSON.parse(JSON.stringify(read(page))));
  const empty = JSON.parse(JSON.stringify(read('待取件\n0\n暂无待取包裹\n还有包裹未显示？查询取件码')));
  const next = mergeOfficialSnapshot(first, empty);
  const official = next.parcels.filter(p => p.source === 'taobao-web');
  assert.equal(official.length, 2);
  assert.equal(official.every(p => p.inLatestOfficialSnapshot === false && p.collectedAt === null), true);
  assert.throws(() => mergeOfficialSnapshot(first, { state: 'error' }), /未完整读取/);
});

test('无数字角标的明确空状态也能移除旧待取清单', () => {
  const first = mergeOfficialSnapshot({ version: 1, parcels: [], customProviders: [] }, JSON.parse(JSON.stringify(read(page))));
  const empty = JSON.parse(JSON.stringify(read('身份码\n待取件\n追踪中\n已签收\n你还没有待取包裹哦\n还有包裹未显示？查询取件码')));
  assert.equal(empty.state, 'ready');
  assert.equal(empty.expectedCount, 0);
  assert.equal(filterParcels(mergeOfficialSnapshot(first, empty), []).length, 0);
});

test('占位零、空白、加载、登录过期及区域外广告空文案不清空', () => {
  for (const text of ['', '待取件\n0', '待取件\n0\n暂无待取包裹\n加载中',
    '待取件\n0\n暂无待取包裹\n登录已失效', '待取件\n0\n暂无待取包裹\n请求超时',
    '待取件\n0\n还有包裹未显示？查询取件码\n暂无待取包裹', '待取件\n1\n暂无待取包裹']) {
    assert.notEqual(read(text).state, 'ready', text);
  }
});

test('支持待取件括号数量，空提示与残留卡片冲突时拒绝清空', () => {
  assert.equal(read(page.replace('待取件\n2', '待取件（2）')).parcels.length, 2);
  assert.equal(read(page.replace('待取件\n2', '待取件\n0\n暂无待取包裹')).state, 'error');
});

test('空快照只处理该官方来源，保留手动与其他来源和已取历史', () => {
  const first = mergeOfficialSnapshot({ version: 1, parcels: [], customProviders: [] }, JSON.parse(JSON.stringify(read(page))));
  const manual = { ...first.parcels[0], id: 'manual', providerID: 'fcbox', source: 'manual', trackingNumber:'MANUAL0001', credentials:null };
  const jd = { ...first.parcels[0], id: 'jd', providerID: 'tuxi', source: 'tuxi-web', trackingNumber:'TUXI0001', credentials:null };
  first.parcels[0].collectedAt = '2026-10-25T00:00:00Z';
  first.parcels.push(manual, jd);
  const empty = JSON.parse(JSON.stringify(read('待取件\n0\n暂无待取件')));
  const next = mergeOfficialSnapshot(first, empty);
  assert.deepEqual(filterParcels(next, []).map(p => p.id).sort(), ['jd', 'manual']);
  assert.equal(filterParcels(next, [], { collected: true }).length, 1);
  assert.equal(first.parcels.find(p => p.id === manual.id).inLatestOfficialSnapshot, true);
});

test('其他平台同运单归为同一包裹，各来源取件码独立保留', () => {
  const snapshot = JSON.parse(JSON.stringify(read(page)));
  const existing = { ...demoState().parcels[0], id: 'jd-same', providerID: 'jd', isDemo: false,
    carrier: '圆通', trackingNumber: 'TESTYT0000001', source: 'jd-web' };
  const next = mergeOfficialSnapshot({ version: 1, customProviders: [], parcels: [existing] }, snapshot);
  assert.equal(next.parcels.length, 2);
  const merged=next.parcels.find(p=>p.id===existing.id);
  assert.equal(merged.credentials.length,2);
  assert.ok(merged.credentials.some(p=>p.source==='jd-web'&&p.pickupCode===existing.pickupCode));
  assert.ok(merged.credentials.some(p=>p.source==='taobao-web'));
});

test('官方出库延迟时自动刷新不会复活手动已取的记录', () => {
  const snapshot = JSON.parse(JSON.stringify(read(page)));
  const first = mergeOfficialSnapshot({ version: 1, parcels: [], customProviders: [] }, snapshot);
  first.parcels[0].collectedAt = '2026-10-25T01:00:00Z';
  const next = mergeOfficialSnapshot(first, snapshot);
  assert.equal(filterParcels(next, []).length, 1);
  assert.equal(filterParcels(next, [], { collected: true }).length, 1);
});
