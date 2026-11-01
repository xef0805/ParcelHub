import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { readFile } from 'node:fs/promises';
import { addParcel, arrivalDay, arrivalLabel, mergeOfficialSnapshot, nextParcelTitle, toggleCollected, validateSavedState } from '../preview/model.mjs';

const read = vm.runInNewContext(await readFile(new URL('../shared/cainiao-reader.js', import.meta.url), 'utf8'));
const catalog = JSON.parse(await readFile(new URL('../shared/catalog.json', import.meta.url), 'utf8'));
const row = { providerID: 'taobao', title: '测试包裹', station: '测试驿站', pickupCode: '1-2-0001', carrier: '中通', trackingNumber: 'TESTZTO000001' };
const observed = new Date(2026, 9, 31, 23, 58);
const readSMS = vm.runInNewContext(await readFile(new URL('../shared/sms-reader.js', import.meta.url), 'utf8'));
const snapshot = (extra = {}, date = observed) => ({ state: 'ready', expectedCount: 1, readAt: date.toISOString(), parcels: [{ ...row, ...extra }] });

test('从各自卡片读取今日与多日前到站信息，不借相邻包裹日期', () => {
  const page = ['待取件', '2', '测试驿站', '1-2-0001', '今日到站', '中通 TESTZTO000001', '1-2-0002', '已到2天', '中通 TESTZTO000002', '还有包裹未显示？'].join('\n');
  assert.deepEqual(Array.from(read(page).parcels, p => p.arrivalDaysAgo), [0, 2]);
  assert.deepEqual(Array.from(read(page.replace('今日到站\n', '')).parcels, p => p.arrivalDaysAgo), [undefined, 2]);
  for (const [text, days] of [['昨日到站', 1], ['3日前到站', 3], ['3天前到站', 3], ['已到站4天', 4]]) {
    assert.equal(read(page.replace('今日到站', text)).parcels[0].arrivalDaysAgo, days);
  }
  assert.equal(read(page.replace('今日到站', '今日到站\n已到2天')).parcels[0].arrivalDaysAgo, undefined);
  assert.equal(read(page.replace('今日到站', '已到99999天')).parcels[0].arrivalDaysAgo, undefined);
});

test('到站日期跨午夜、跨月与跨年按日历计算，非法或未来日期不编造标签', () => {
  assert.equal(arrivalDay(0, observed.toISOString()), '2026-10-31');
  assert.equal(arrivalDay(2, observed.toISOString()), '2026-10-29');
  assert.equal(arrivalLabel('2026-10-31', new Date(2026, 10, 1, 0, 1)), '昨天到站');
  assert.equal(arrivalLabel('2026-10-31', observed), '今日到站');
  assert.equal(arrivalLabel('2026-12-31', new Date(2027, 0, 1)), '昨天到站');
  assert.equal(arrivalLabel('2024-02-29', new Date(2024, 2, 1)), '昨天到站');
  assert.equal(arrivalLabel('2026-10-30', new Date(2026, 10, 1)), '前天到站');
  assert.equal(arrivalLabel('2026-10-29', new Date(2026, 10, 1)), '已到站3天');
  assert.equal(arrivalLabel('2026-10-29', observed, 'en'), 'Arrived 2 days ago');
  assert.equal(arrivalLabel('2026-10-30', observed, 'en'), 'Arrived yesterday');
  assert.equal(arrivalLabel('2026-10-28', observed, 'en'), 'Arrived 3 days ago');
  for (const age of [undefined, null, -1, 1.5, '2', 3651]) assert.equal(arrivalDay(age, observed.toISOString()), null);
  assert.equal(arrivalDay(1, 'invalid'), null);
  for (const value of [undefined, null, '', '2026-02-30', '2026-13-01', '2026-11-01']) assert.equal(arrivalLabel(value, observed), '');
});

test('反复同步、保存、归档和恢复不重置到站日期，同地点漏读时保留已知日期', () => {
  let state = mergeOfficialSnapshot({ version: 1, customProviders: [], parcels: [] }, snapshot({ arrivalDaysAgo: 2 }));
  assert.equal(state.parcels[0].arrivedOn, '2026-10-29');
  state = mergeOfficialSnapshot(state, snapshot({ arrivalDaysAgo: 3 }, new Date(2026, 10, 1, 1)));
  state = validateSavedState(JSON.parse(JSON.stringify(state)), catalog);
  assert.equal(state.parcels[0].arrivedOn, '2026-10-29');
  state = mergeOfficialSnapshot(state, snapshot());
  assert.equal(state.parcels[0].arrivedOn, '2026-10-29');
  const empty = { ...snapshot(), expectedCount: 0, parcels: [] };
  state = mergeOfficialSnapshot(state, empty);
  assert.ok(state.parcels[0].collectedAt);
  assert.equal(state.parcels[0].arrivedOn, '2026-10-29');
  state = toggleCollected(state, state.parcels[0].id);
  assert.equal(state.parcels[0].arrivedOn, '2026-10-29');
  state = mergeOfficialSnapshot(state, snapshot({ station: '另一测试驿站' }));
  assert.equal(state.parcels[0].arrivedOn, null);
});

test('旧存档缺失到站日期时不拿导入或同步时间冒充，下一次读到后补全', () => {
  let state = mergeOfficialSnapshot({ version: 1, customProviders: [], parcels: [] }, snapshot());
  assert.equal(arrivalLabel(state.parcels[0].arrivedOn, observed), '');
  const id = state.parcels[0].id;
  state = mergeOfficialSnapshot(state, snapshot({ arrivalDaysAgo: 1 }));
  assert.equal(state.parcels[0].id, id);
  assert.equal(arrivalLabel(state.parcels[0].arrivedOn, observed), '昨天到站');
});

test('跨日离线使用本地日期，旧网页的今日到站不能重置同地点已知日期', () => {
  let state = mergeOfficialSnapshot({ version: 1, customProviders: [], parcels: [] }, snapshot({ arrivalDaysAgo: 0 }));
  const nextDay = new Date(2026, 10, 1, 9, 0);
  const offline = validateSavedState(JSON.parse(JSON.stringify(state)), catalog);
  assert.equal(arrivalLabel(offline.parcels[0].arrivedOn, nextDay), '昨天到站');
  state = mergeOfficialSnapshot(offline, snapshot({ arrivalDaysAgo: 0 }, nextDay));
  assert.equal(state.parcels[0].arrivedOn, '2026-10-31');
  assert.equal(arrivalLabel(state.parcels[0].arrivedOn, nextDay), '昨天到站');
  state = mergeOfficialSnapshot(state, snapshot({ station: '新测试驿站', arrivalDaysAgo: 0 }, nextDay));
  assert.equal(state.parcels[0].arrivedOn, '2026-11-01');
});

test('短信到站日期默认今天，可选前7天边界，未来和更早日期在保存层被拒绝', () => {
  const now = new Date(), today = arrivalDay(0, now.toISOString());
  const sms = { ...row, source: 'sms', smsOriginal: '【中通】测试驿站取件码1-2-0001。' };
  const base = () => ({ version: 1, customProviders: [], parcels: [] });
  assert.equal(addParcel(base(), sms, catalog).parcels[0].arrivedOn, today);
  const earliest = arrivalDay(7, now.toISOString());
  assert.equal(addParcel(base(), { ...sms, arrivedOn: earliest }, catalog).parcels[0].arrivedOn, earliest);
  const future = new Date(now); future.setDate(future.getDate() + 1);
  for (const arrivedOn of [arrivalDay(8, now.toISOString()), arrivalDay(0, future.toISOString()), '2026-02-30', '']) {
    assert.throws(() => addParcel(base(), { ...sms, arrivedOn }, catalog), /前7天/);
  }
});

test('官方与短信共用当天序号，重复补充短信不改已有名称或到站日期', () => {
  const today = arrivalDay(0, new Date().toISOString()), short = today.replaceAll('-', '').slice(4);
  let state = mergeOfficialSnapshot({ version: 1, customProviders: [], parcels: [] }, snapshot({ title: '中通包裹', arrivalDaysAgo: 2 }));
  const original = state.parcels[0];
  assert.equal(original.title, `${short}包裹1号`);
  const smsTitle = readSMS('', state.parcels, today).title;
  assert.equal(smsTitle, nextParcelTitle(state.parcels));
  state = addParcel(state, { ...row, title: smsTitle, source: 'sms', trackingNumber: 'TESTZTO000002', smsOriginal: '【中通】另一测试包裹，取件码1-2-0002。' }, catalog);
  assert.equal(state.parcels[0].title, `${short}包裹2号`);
  const rows = [{ ...row, title: '中通包裹', arrivalDaysAgo: 2 }, { ...row, title: '中通包裹', trackingNumber: 'TESTZTO000003' }];
  state = mergeOfficialSnapshot(state, { ...snapshot(), expectedCount: 2, parcels: rows });
  assert.equal(state.parcels.find(p => p.trackingNumber === 'TESTZTO000003').title, `${short}包裹3号`);
  state = addParcel(state, { ...row, title: `${short}包裹4号`, source: 'sms', smsOriginal: '【中通】补充已有包裹的通知，取件码1-2-0001。' }, catalog);
  const same = state.parcels.find(p => p.id === original.id);
  assert.equal(same.title, original.title);
  assert.equal(same.arrivedOn, original.arrivedOn);
  assert.equal(state.parcels.length, 3);
  assert.equal(nextParcelTitle(state.parcels), `${short}包裹4号`);
});

test('旧官方通用名称升级为日期序号，已有手动名称和正式序号保持不变', () => {
  let state = mergeOfficialSnapshot({ version: 1, customProviders: [], parcels: [] }, snapshot({ title: '中通包裹' }));
  const expected = state.parcels[0].title;
  state.parcels[0].title = '中通包裹';
  state = mergeOfficialSnapshot(state, snapshot({ title: '中通包裹' }));
  assert.equal(state.parcels[0].title, expected);
  state.parcels[0].title = '自己起的名称';
  assert.equal(mergeOfficialSnapshot(state, snapshot({ title: '中通包裹' })).parcels[0].title, '自己起的名称');
});

test('导入表单打开后新增了官方包裹，保存短信时重新分配序号避免重名', () => {
  let state = mergeOfficialSnapshot({ version: 1, customProviders: [], parcels: [] }, snapshot());
  const staleTitle = nextParcelTitle(state.parcels);
  state = mergeOfficialSnapshot(state, { ...snapshot(), expectedCount: 2, parcels: [row, { ...row, trackingNumber: 'TESTZTO000002' }] });
  const next = nextParcelTitle(state.parcels);
  state = addParcel(state, { ...row, title: staleTitle, source: 'sms', trackingNumber: 'TESTZTO000003', smsOriginal: '【中通】第三个测试包裹，取件码1-2-0003。' }, catalog);
  assert.equal(state.parcels[0].title, next);
  assert.equal(new Set(state.parcels.map(p => p.title)).size, 3);
});
