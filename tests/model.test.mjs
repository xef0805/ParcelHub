import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { demoState, addParcel, addProvider, toggleCollected, filterParcels, validateSavedState, orderedProviders, reorderProvider, bindStationCredential, boundStationProvider, preferredCredentialProvider, credentialProviders, enableProvider, removeProvider, groupCollected } from '../preview/model.mjs';

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

test('身份码排序保存顺序、过滤历史无效项，新增平台仍出现', () => {
  const sorted = orderedProviders(catalog, [], ['jd', 'taobao', 'jd', 'missing']);
  assert.equal(sorted[0].id, 'jd');
  assert.equal(sorted[1].id, 'taobao');
  assert.equal(sorted.some(p => p.id === 'manual'), false);
  const next = reorderProvider(demoState(), sorted, 'taobao', 0);
  assert.equal(orderedProviders(catalog, [], next.providerOrderIDs)[0].id, 'taobao');
  assert.equal(orderedProviders([...catalog, { id: 'new' }], [], next.providerOrderIDs).at(-1).id, 'new');
  assert.equal(reorderProvider(next, sorted, 'missing', 0), next);
});

test('地点首次绑定、保存恢复、更换和解绑互不影响其他地点', () => {
  const original = demoState();
  const first = bindStationCredential(original, '北门驿站', 'taobao', catalog);
  const second = bindStationCredential(first, '南门驿站', 'jd', catalog);
  const restored = JSON.parse(JSON.stringify(second));
  assert.equal(boundStationProvider(restored, '北门驿站', catalog).id, 'taobao');
  const changed = bindStationCredential(restored, '北门驿站', 'cainiao', catalog);
  assert.equal(boundStationProvider(changed, '北门驿站', catalog).id, 'cainiao');
  assert.equal(boundStationProvider(changed, '南门驿站', catalog).id, 'jd');
  assert.equal(boundStationProvider(bindStationCredential(changed, '北门驿站', '', catalog), '北门驿站', catalog), undefined);
  assert.equal(original.stationCredentials, undefined);
  assert.throws(() => bindStationCredential(first, '北门驿站', 'manual', catalog));
});

test('已有常用身份码可直接打开，多种地点绑定时不擅自猜测', () => {
  const one = { stationCredentials: { '北门': 'taobao', '南门': 'taobao' } };
  assert.equal(preferredCredentialProvider(one, catalog).id, 'taobao');
  const multiple = { stationCredentials: { '北门': 'taobao', '南门': 'jd' } };
  assert.equal(preferredCredentialProvider(multiple, catalog), undefined);
  assert.equal(preferredCredentialProvider({ ...multiple, preferredCredentialID: 'jd' }, catalog).id, 'jd');
});

test('首次只启用淘宝、拼多多、兔喜；旧地点绑定与自定义平台保留', () => {
  const initial={version:1,customProviders:[],parcels:[]};
  assert.deepEqual(credentialProviders(initial,catalog).map(p=>p.id).sort(),['pdd','taobao','tuxi']);
  const old=addProvider({...initial,stationCredentials:{北门:'jd'}},{name:'旧入口',miniProgramName:'旧入口'},catalog);
  const active=credentialProviders(old,catalog).map(p=>p.id);
  assert.ok(active.includes('jd'));assert.ok(active.includes(old.customProviders[0].id));
  assert.ok(!active.includes('cainiao'));
});

test('删除入口清理常用、地点与链接绑定，保留所有包裹；全部删除后不会被默认平台复活', () => {
  const initial={...demoState(),preferredCredentialID:'fcbox',stationCredentials:{北门:'fcbox',南门:'taobao'},identityBindings:{fcbox:{kind:'launchURL',value:'https://wxmpurl.cn/example',confirmed:true}}};
  const next=removeProvider(initial,'fcbox',catalog);
  assert.deepEqual(next.parcels,initial.parcels);assert.deepEqual(next.stationCredentials,{南门:'taobao'});
  assert.equal(next.preferredCredentialID,null);assert.equal(next.identityBindings.fcbox,undefined);
  assert.equal(credentialProviders(next,catalog).some(p=>p.id==='fcbox'),false);
  const readded=enableProvider(next,'fcbox',catalog);
  assert.equal(credentialProviders(readded,catalog).filter(p=>p.id==='fcbox').length,1);
  let empty=next;for(const p of credentialProviders(next,catalog))empty=removeProvider(empty,p.id,catalog);
  assert.equal(credentialProviders(JSON.parse(JSON.stringify(empty)),catalog).length,0);
  assert.throws(()=>enableProvider(empty,'unknown',catalog),/尚未适配/);
});

test('已取记录按本地日期倒序，同一天同地点归组；恢复待取后移出历史', () => {
  const records=[
    {id:'old',station:'北门',collectedAt:'2026-10-24T12:00:00'},
    {id:'first',station:'北门',collectedAt:'2026-10-25T13:00:00'},
    {id:'other',station:'南门',collectedAt:'2026-10-25T14:00:00'},
    {id:'last',station:'北门',collectedAt:'2026-10-25T15:00:00'},
    {id:'pending',station:'北门',collectedAt:null}];
  const grouped=groupCollected(records);
  assert.deepEqual(grouped.map(p=>p.day),['2026-10-25','2026-10-24']);
  assert.deepEqual(grouped[0].stations.find(s=>s.station==='北门').parcels.map(p=>p.id),['last','first']);
  assert.equal(groupCollected(toggleCollected({parcels:records},'last').parcels)[0].stations.find(s=>s.station==='北门').parcels.length,1);
});
