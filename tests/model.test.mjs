import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { demoState, addParcel, addProvider, toggleCollected, filterParcels, validateSavedState } from '../preview/model.mjs';

const catalog = JSON.parse(await readFile(new URL('../shared/catalog.json', import.meta.url), 'utf8'));
const draft = { title: '真实手动记录', station: '测试取件点', providerID: 'fcbox', pickupCode: '000012', carrier: '顺丰', trackingNumber: 'SF00001' };

test('取件码保留前导零；添加真实记录不会改变演示标记', () => {
  const initial = demoState(), next = addParcel(initial, draft, catalog);
  assert.equal(next.parcels[0].pickupCode, '000012');
  assert.equal(next.parcels[0].isDemo, false);
  assert.equal(initial.parcels.length, 4);
  assert.equal(next.parcels.filter(p => p.isDemo).length, 4);
});
test('重复运单按公司与单号拦截，不用相同取件码误合并包裹', () => {
  const first = addParcel(demoState(), draft, catalog);
  assert.throws(() => addParcel(first, { ...draft, trackingNumber: ' sf00001 ' }, catalog), /已存在/);
  assert.equal(addParcel(first, { ...draft, trackingNumber: 'SF00002' }, catalog).parcels.length, 6);
});
test('已取状态可恢复，演示与手动记录均支持', () => {
  const initial = demoState(), next = toggleCollected(initial, 'demo-1');
  assert.equal(filterParcels(next, catalog).length, 3);
  assert.equal(filterParcels(next, catalog, { collected: true }).length, 1);
  assert.equal(filterParcels(toggleCollected(next, 'demo-1'), catalog).length, 4);
});
test('自定义平台可用于新包裹，且不假装已连接', () => {
  const next = addProvider(demoState(), { name: '测试驿站', miniProgramName: '测试驿站' }, catalog);
  const provider = next.customProviders[0];
  assert.equal(provider.website, '');
  assert.equal(provider.featured, false);
  assert.equal(addParcel(next, { ...draft, providerID: provider.id }, [...catalog, provider]).parcels[0].providerID, provider.id);
  assert.throws(() => addProvider(next, { name: '测试驿站', miniProgramName: '重复' }, [...catalog, provider]), /已经存在/);
});
test('搜索与平台和取件状态组合过滤', () => {
  const state = demoState();
  assert.equal(filterParcels(state, catalog, { providerID: 'fcbox', search: '008' }).length, 1);
  assert.equal(filterParcels(state, catalog, { providerID: 'cainiao', search: '008' }).length, 0);
  assert.equal(filterParcels(state, catalog, { search: '丰巢' }).length, 1);
});
test('损坏或未知版本的持久化数据不得静默覆盖', () => {
  assert.equal(validateSavedState(demoState(), catalog).version, 1);
  assert.throws(() => validateSavedState({ version: 2 }, catalog));
  const bad = demoState(); bad.parcels[0].providerID = 'missing';
  assert.throws(() => validateSavedState(bad, catalog), /损坏/);
});
test('空白必填项与不存在的平台被拦截', () => {
  assert.throws(() => addParcel(demoState(), { ...draft, pickupCode: ' ' }, catalog), /取件码/);
  assert.throws(() => addParcel(demoState(), { ...draft, providerID: 'missing' }, catalog), /取件平台/);
});
