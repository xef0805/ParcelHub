import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { readFile } from 'node:fs/promises';
import { mergeOfficialSnapshot, demoState } from '../preview/model.mjs';

const source = await readFile(new URL('../shared/cainiao-reader.js', import.meta.url), 'utf8');
const read = vm.runInNewContext(source);
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
test('官方读取可合并已有手动记录，保留原记录标识和前导零', () => {
  const snapshot = JSON.parse(JSON.stringify(read(page)));
  const original = { version: 1, customProviders: [], parcels: [{ ...demoState().parcels[0], id: 'existing', isDemo: false,
    carrier: '圆通', trackingNumber: 'TESTYT0000001', source: 'manual', pickupCode: 'old' }] };
  const merged = mergeOfficialSnapshot(original, snapshot);
  assert.equal(merged.parcels.length, 2);
  assert.equal(merged.parcels.find(p => p.id === 'existing').pickupCode, '01-2-0001');
  assert.equal(merged.parcels.every(p => p.source === 'cainiao-web'), true);
  assert.equal(original.parcels[0].pickupCode, 'old');
});
test('本次清单不再出现的记录只移出当前快照，不伪造已取状态', () => {
  const first = mergeOfficialSnapshot(demoState(), JSON.parse(JSON.stringify(read(page))));
  const empty = JSON.parse(JSON.stringify(read('待取件\n0\n暂无待取包裹\n还有包裹未显示？查询取件码')));
  const next = mergeOfficialSnapshot(first, empty);
  const official = next.parcels.filter(p => p.source === 'cainiao-web');
  assert.equal(official.length, 2);
  assert.equal(official.every(p => p.inLatestOfficialSnapshot === false && p.collectedAt === null), true);
  assert.throws(() => mergeOfficialSnapshot(first, { state: 'error' }), /未完整读取/);
});
