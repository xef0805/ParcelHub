import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { demoState, addParcel, toggleCollected, filterParcels, validateSavedState, orderedProviders, reorderProvider, bindStationCredential, boundStationProvider, preferredCredentialProvider, credentialProviders, deleteCollected, pickupCredentials, coalesceParcels, matchParcel, mergeOfficialSnapshot, groupCollected } from '../preview/model.mjs';

const catalog = JSON.parse(await readFile(new URL('../shared/catalog.json', import.meta.url), 'utf8'));
const draft = { title: '真实手动记录', station: '测试取件点', providerID: 'fcbox', pickupCode: '000012', carrier: '顺丰', trackingNumber: 'SF00001' };

test('取件码保留前导零；添加真实记录不会改变演示标记', () => {
  const initial = demoState(), next = addParcel(initial, draft, catalog);
  assert.equal(next.parcels[0].pickupCode, '000012');
  assert.equal(next.parcels[0].isDemo, false);
  assert.equal(initial.parcels.length, 4);
  assert.equal(next.parcels.filter(p => p.isDemo).length, 4);
});
test('重复运单按公司与完整单号合并，不同运单不因取件码相同被合并', () => {
  const first = addParcel(demoState(), draft, catalog);
  assert.equal(addParcel(first, { ...draft, trackingNumber: ' sf00001 ' }, catalog).parcels.length,5);
  assert.equal(addParcel(first, { ...draft, trackingNumber: 'SF00002' }, catalog).parcels.length, 6);
});
test('已取状态可恢复，演示与手动记录均支持', () => {
  const initial = demoState(), next = toggleCollected(initial, 'demo-1');
  assert.equal(filterParcels(next, catalog).length, 3);
  assert.equal(filterParcels(next, catalog, { collected: true }).length, 1);
  assert.equal(filterParcels(toggleCollected(next, 'demo-1'), catalog).length, 4);
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
  const sorted = orderedProviders(catalog, [], ['fcbox', 'taobao', 'fcbox', 'missing']);
  assert.equal(sorted[0].id, 'fcbox');
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
  const second = bindStationCredential(first, '南门驿站', 'tuxi', catalog);
  const restored = JSON.parse(JSON.stringify(second));
  assert.equal(boundStationProvider(restored, '北门驿站', catalog).id, 'taobao');
  const changed = bindStationCredential(restored, '北门驿站', 'yishoufa', catalog);
  assert.equal(boundStationProvider(changed, '北门驿站', catalog).id, 'yishoufa');
  assert.equal(boundStationProvider(changed, '南门驿站', catalog).id, 'tuxi');
  assert.equal(boundStationProvider(bindStationCredential(changed, '北门驿站', '', catalog), '北门驿站', catalog), undefined);
  assert.equal(original.stationCredentials, undefined);
  assert.throws(() => bindStationCredential(first, '北门驿站', 'manual', catalog));
});

test('已有常用身份码可直接打开，多种地点绑定时不擅自猜测', () => {
  const one = { stationCredentials: { '北门': 'taobao', '南门': 'taobao' } };
  assert.equal(preferredCredentialProvider(one, catalog).id, 'taobao');
  const multiple = { stationCredentials: { '北门': 'taobao', '南门': 'tuxi' } };
  assert.equal(preferredCredentialProvider(multiple, catalog), undefined);
  assert.equal(preferredCredentialProvider({ ...multiple, preferredCredentialID: 'tuxi' }, catalog).id, 'tuxi');
});

test('身份码固定为四个平台加短信，旧平台入口迁移移除但包裹保留',()=>{
  const old={...demoState(),enabledProviderIDs:['pdd'],stationCredentials:{北门:'jd',南门:'fcbox'},identityBindings:{pdd:{kind:'shareCode',value:'#小程序://拼多多/Example',confirmed:false}}};
  const restored=validateSavedState(old,catalog);
  assert.deepEqual(credentialProviders(restored,catalog).map(p=>p.id),['taobao','tuxi','yishoufa','fcbox','sms']);
  assert.deepEqual(restored.stationCredentials,{南门:'fcbox'});assert.deepEqual(restored.identityBindings,{});
  assert.equal(restored.parcels.length,old.parcels.length);assert.equal(restored.parcels[0].providerID,'manual');
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

const empty=()=>({version:1,customProviders:[],parcels:[]});
const smsDraft={...draft,title:'1026包裹1号',source:'sms',smsOriginal:'【顺丰】您的快件已到测试取件点，取件码000012，运单号SF00001。',smsSender:'顺丰'};
test('同一短信重复导入只保留一条与原导入时间，已取件不会复活',()=>{
  const first=addParcel(empty(),smsDraft,catalog),again=addParcel(first,smsDraft,catalog);
  assert.equal(again.parcels.length,1);assert.equal(again.parcels[0].smsOriginal,smsDraft.smsOriginal);
  assert.equal(again.parcels[0].smsImportedAt,first.parcels[0].smsImportedAt);
  const collected=toggleCollected(again,again.parcels[0].id);
  assert.equal(filterParcels(addParcel(collected,smsDraft,catalog),catalog).length,0);
});
test('短信与不同平台同运单合并，平台取件码与原文分别保留',()=>{
  const first=addParcel(empty(),smsDraft,catalog);
  const snapshot={state:'ready',expectedCount:1,readAt:new Date().toISOString(),parcels:[{...draft,providerID:'taobao',pickupCode:'1-2-003',title:'官方包裹',carrier:'顺丰速运'}]};
  const next=mergeOfficialSnapshot(first,snapshot);
  assert.equal(next.parcels.length,1);assert.equal(next.parcels[0].smsOriginal,smsDraft.smsOriginal);
  assert.deepEqual(pickupCredentials(next.parcels[0]).map(c=>c.pickupCode).sort(),['000012','1-2-003']);
  const other=addParcel(next,{...smsDraft,providerID:'tuxi',pickupCode:'A-12-039'},catalog);
  assert.equal(other.parcels.length,1);assert.equal(pickupCredentials(other.parcels[0]).length,3);
});
test('缺单号按近72小时同公司地点取件码保守合并，代码重用与不同公司不误合并',()=>{
  const first=addParcel(empty(),{...smsDraft,trackingNumber:''},catalog);
  assert.equal(addParcel(first,{...smsDraft,trackingNumber:'',smsOriginal:'不同通知正文'},catalog).parcels.length,1);
  assert.equal(addParcel(first,{...smsDraft,trackingNumber:'',carrier:'中通',smsOriginal:'其他快递通知'},catalog).parcels.length,2);
  const old={...first,parcels:first.parcels.map(p=>({...p,addedAt:'2025-01-01T00:00:00Z'}))};
  assert.equal(addParcel(old,{...smsDraft,trackingNumber:''},catalog).parcels.length,2);
});
test('尾号不当完整单号，相同尾号不同地点不能跨平台误合并；不明公司多匹配需要补信息',()=>{
  const first=addParcel(empty(),{...smsDraft,trackingNumber:'1234'},catalog);
  assert.equal(addParcel(first,{...smsDraft,trackingNumber:'1234',station:'另一测试地点',pickupCode:'9-9-9999',smsOriginal:'【顺丰】另一测试地点的通知，取件码9-9-9999，尾号1234。'},catalog).parcels.length,2);
  const two=[{...first.parcels[0],trackingNumber:'SHARED0001',carrier:'顺丰'},{...first.parcels[0],id:'other',trackingNumber:'SHARED0001',carrier:'中通'}];
  assert.throws(()=>matchParcel({...smsDraft,carrier:'',trackingNumber:'SHARED0001'},two),/补全/);
});
test('历史重复完整运单归并，保留各平台码和手动已取状态',()=>{
  const one=addParcel(empty(),smsDraft,catalog).parcels[0];
  const result=coalesceParcels([one,{...one,id:'other',providerID:'tuxi',pickupCode:'R-001',source:'tuxi-web',collectedAt:new Date().toISOString()}]);
  assert.equal(result.length,1);assert.ok(result[0].collectedAt);assert.equal(pickupCredentials(result[0]).length,2);
});
test('已取记录删除后隐藏并清除短信原文，重复导入与延迟官方快照不能复活',()=>{
  const first=addParcel(empty(),smsDraft,catalog);const collected=toggleCollected(first,first.parcels[0].id);
  const removed=deleteCollected(collected,collected.parcels[0].id);
  assert.equal(filterParcels(removed,catalog,{collected:true}).length,0);assert.equal(removed.parcels[0].smsOriginal,null);
  assert.throws(()=>addParcel(removed,smsDraft,catalog),/已删除/);
  const synced=mergeOfficialSnapshot(removed,{state:'ready',expectedCount:1,readAt:new Date().toISOString(),parcels:[{...draft,providerID:'taobao'}]});
  assert.equal(filterParcels(synced,catalog).length,0);assert.equal(filterParcels(synced,catalog,{collected:true}).length,0);
});
test('没有完整单号的短信删除原文后，短期重复导入仍被去重指纹拦截',()=>{
  const incoming={...smsDraft,trackingNumber:''};
  const first=addParcel(empty(),incoming,catalog),collected=toggleCollected(first,first.parcels[0].id);
  const removed=deleteCollected(collected,first.parcels[0].id);
  assert.ok(removed.parcels[0].smsFingerprint);assert.equal(removed.parcels[0].smsOriginal,null);
  assert.throws(()=>addParcel(removed,incoming,catalog),/已删除/);
});
test('损坏的原文或来源凭证必须拒绝读取，不能覆盖存档',()=>{
  const first=addParcel(empty(),smsDraft,catalog);
  assert.throws(()=>validateSavedState({...first,parcels:first.parcels.map(p=>({...p,smsOriginal:42}))},catalog),/损坏/);
  assert.throws(()=>validateSavedState({...first,parcels:first.parcels.map(p=>({...p,credentials:[{}]}))},catalog),/损坏/);
});
