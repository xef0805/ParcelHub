import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { addParcel, bindStationCredential, credentialProviders, deleteCollected, filterParcels, mergeOfficialSnapshot, reorderProvider, toggleCollected, validateSavedState } from '../preview/model.mjs';

const catalog = JSON.parse(await readFile(new URL('../shared/catalog.json', import.meta.url), 'utf8'));
const base = () => ({ version: 1, customProviders: [], parcels: [] });
const row = { providerID: 'taobao', title: '虚构包裹', station: '测试驿站', pickupCode: '1-2-0003', carrier: '中通', trackingNumber: 'TESTZTO00001' };
const snapshot = parcels => ({ state: 'ready', expectedCount: parcels.length, readAt: new Date().toISOString(), parcels });

test('短信与官方合并、排序、自动归档、恢复、删除及再次导入构成完整流程', () => {
  const sms = { ...row, providerID: 'manual', title: '1031包裹1号', source: 'sms', smsOriginal: '【中通】取件码1-2-0003，单号TESTZTO00001，已到测试驿站。' };
  let state = addParcel(base(), sms, catalog);
  state = bindStationCredential(state, row.station, 'sms', catalog);
  state = mergeOfficialSnapshot(state, snapshot([row]));
  const id = state.parcels[0].id;
  state = reorderProvider(state, credentialProviders(state, catalog), 'sms', 0);
  state = validateSavedState(JSON.parse(JSON.stringify(state)), catalog);
  assert.equal(state.parcels.length, 1);
  assert.equal(state.parcels[0].smsOriginal, sms.smsOriginal);
  assert.equal(credentialProviders(state, catalog)[0].id, 'sms');
  assert.equal(state.stationCredentials[row.station], 'sms');
  state = mergeOfficialSnapshot(state, snapshot([]));
  assert.equal(filterParcels(state, catalog).length, 0);
  assert.equal(filterParcels(state, catalog, { collected: true })[0].id, id);
  state = toggleCollected(state, id);
  state = mergeOfficialSnapshot(state, snapshot([]));
  assert.equal(filterParcels(state, catalog)[0].id, id);
  assert.equal(filterParcels(state, catalog, { collected: true }).length, 0);
  state = deleteCollected(toggleCollected(state, id), id);
  state = mergeOfficialSnapshot(state, snapshot([row]));
  assert.equal(filterParcels(state, catalog).length, 0);
  assert.equal(filterParcels(state, catalog, { collected: true }).length, 0);
  assert.equal(state.parcels.length, 1);
  assert.equal(state.parcels[0].smsOriginal, null);
  assert.throws(() => addParcel(state, sms, catalog), /已删除/);
  assert.equal(state.stationCredentials[row.station], 'sms');
});

test('反复排序及保存读取不丢平台、不改包裹或绑定，边界操作保持原状', () => {
  const initial = bindStationCredential(mergeOfficialSnapshot(base(), snapshot([row])), row.station, 'taobao', catalog);
  let state = initial;
  const expected = ['sms', 'fcbox', 'yishoufa', 'tuxi', 'taobao'];
  for (const [index, id] of expected.entries()) {
    state = reorderProvider(state, credentialProviders(state, catalog), id, index);
  }
  state = validateSavedState(JSON.parse(JSON.stringify(state)), catalog);
  assert.deepEqual(credentialProviders(state, catalog).map(p => p.id), expected);
  assert.deepEqual(state.parcels, initial.parcels);
  assert.deepEqual(state.stationCredentials, initial.stationCredentials);
  for (const destination of [-1, 5, 0.5, NaN]) {
    assert.equal(reorderProvider(state, credentialProviders(state, catalog), 'sms', destination), state);
  }
});

test('异常清单不能改写记录，自动归档时间在刷新和保存后保持不变', () => {
  const arrived = mergeOfficialSnapshot(base(), snapshot([row]));
  const archived = mergeOfficialSnapshot(arrived, snapshot([]));
  const before = JSON.stringify(archived);
  for (const invalid of ['error', 'login_required', 'loading', 'filtered_empty']) {
    assert.throws(() => mergeOfficialSnapshot(archived, { ...snapshot([]), state: invalid }));
    assert.equal(JSON.stringify(archived), before);
  }
  const reloaded = validateSavedState(JSON.parse(before), catalog);
  const repeated = mergeOfficialSnapshot(reloaded, snapshot([]));
  assert.equal(repeated.parcels[0].collectedAt, archived.parcels[0].collectedAt);
  assert.equal(repeated.parcels[0].collectionConfirmedBySync, true);
});
