export const STORAGE_KEY = 'parcelhub.preview.v1';

export function demoState() {
  const make = (id, title, providerID, station, pickupCode, carrier, trackingNumber) => ({
    id, title, providerID, station, pickupCode, carrier, trackingNumber,
    addedAt: new Date().toISOString(), collectedAt: null, isDemo: true
  });
  return { version: 1, customProviders: [], parcels: [
    make('demo-1', '日常用品', 'cainiao', '梧桐里 · 菜鸟驿站', '2-06-218', '中通', 'DEMO-CN-001'),
    make('demo-2', '书与文具', 'cainiao', '梧桐里 · 菜鸟驿站', '3-02-086', '圆通', 'DEMO-CN-002'),
    make('demo-3', '一份小惊喜', 'yishoufa', '梧桐里 · 驿收发', 'A-12-039', '顺丰', 'DEMO-YSF-001'),
    make('demo-4', '生活小物', 'fcbox', '梧桐里 · 东门丰巢柜', '008 426', '申通', 'DEMO-FC-001')
  ] };
}

const clean = value => typeof value === 'string' ? value.trim() : '';
const same = (a, b) => a.trim().toLowerCase() === b.trim().toLowerCase();

export function validateParcel(input, providers, parcels) {
  if (!clean(input.title)) return '请填写包裹名称';
  if (!clean(input.station)) return '请填写取件地点';
  if (!clean(input.pickupCode)) return '请填写取件码';
  if (!providers.some(p => p.id === input.providerID)) return '请选择取件平台';
  if (input.title.length > 60 || input.station.length > 100 || input.pickupCode.length > 40) return '填写内容过长，请缩短后重试';
  if (clean(input.trackingNumber) && parcels.some(p => !p.isDemo && same(p.trackingNumber, input.trackingNumber) && same(p.carrier, input.carrier || ''))) {
    return '已存在相同快递公司和运单号的记录';
  }
  return null;
}

export function addParcel(state, input, providers) {
  const error = validateParcel(input, providers, state.parcels);
  if (error) throw new Error(error);
  const parcel = {
    id: crypto.randomUUID(), title: clean(input.title), station: clean(input.station),
    pickupCode: clean(input.pickupCode), providerID: input.providerID, carrier: clean(input.carrier),
    trackingNumber: clean(input.trackingNumber), addedAt: new Date().toISOString(), collectedAt: null, isDemo: false
  };
  return { ...state, parcels: [parcel, ...state.parcels] };
}

export function toggleCollected(state, id) {
  return { ...state, parcels: state.parcels.map(p => p.id === id ? { ...p, collectedAt: p.collectedAt ? null : new Date().toISOString() } : p) };
}

export function addProvider(state, input, providers) {
  const name = clean(input.name), miniProgramName = clean(input.miniProgramName);
  if (!name || !miniProgramName) throw new Error('请填写平台名称和微信搜索词');
  if (name.length > 20 || miniProgramName.length > 40) throw new Error('平台名称或搜索词过长');
  if (providers.some(p => same(p.name, name))) throw new Error('这个平台已经存在');
  const provider = { id: `custom-${crypto.randomUUID()}`, name, shortName: [...name][0], miniProgramName,
    color: '#479981', symbol: 'square.stack.3d.up.fill', kind: '自定义平台', website: '', featured: false };
  return { ...state, customProviders: [...state.customProviders, provider] };
}

export function filterParcels(state, providers, { collected = false, providerID = 'all', search = '' } = {}) {
  const term = search.trim().toLocaleLowerCase();
  return state.parcels.filter(p => Boolean(p.collectedAt) === collected && (collected || p.inLatestOfficialSnapshot !== false) && (providerID === 'all' || p.providerID === providerID) &&
    (!term || [p.title, p.station, p.pickupCode, p.trackingNumber, p.carrier, providers.find(s => s.id === p.providerID)?.name || '']
      .join(' ').toLocaleLowerCase().includes(term)));
}

export function validateSavedState(value, catalog) {
  if (!value || value.version !== 1 || !Array.isArray(value.parcels) || !Array.isArray(value.customProviders)) throw new Error('不支持的本地数据格式');
  const ids = new Set(catalog.map(p => p.id));
  for (const p of value.customProviders) {
    if (!p || typeof p.id !== 'string' || !p.id.startsWith('custom-') || ids.has(p.id) ||
        !['name', 'shortName', 'miniProgramName', 'kind', 'symbol'].every(k => typeof p[k] === 'string') ||
        !/^#[0-9a-f]{6}$/i.test(p.color) || p.website !== '' || p.featured !== false) throw new Error('平台配置损坏');
    ids.add(p.id);
  }
  const parcelIDs = new Set();
  for (const p of value.parcels) {
    if (!p || !['id', 'title', 'station', 'pickupCode', 'carrier', 'trackingNumber', 'addedAt'].every(k => typeof p[k] === 'string') ||
        !ids.has(p.providerID) || typeof p.isDemo !== 'boolean' || parcelIDs.has(p.id) ||
        !(p.collectedAt === null || typeof p.collectedAt === 'string')) throw new Error('包裹记录损坏');
    parcelIDs.add(p.id);
  }
  return { ...value, parcels: value.parcels.map(p => p.source === 'cainiao-web' ? { ...p, providerID: 'taobao' } : p) };
}

export function mergeOfficialSnapshot(state, snapshot) {
  if (snapshot?.state !== 'ready' || !Array.isArray(snapshot.parcels) || snapshot.expectedCount !== snapshot.parcels.length) {
    throw new Error('官方待取件尚未完整读取，原有记录保持不变');
  }
  const rows = snapshot.parcels;
  for (const row of rows) {
    if (!['taobao', 'cainiao'].includes(row.providerID) || !['title', 'station', 'pickupCode', 'carrier', 'trackingNumber'].every(k => typeof row[k] === 'string' && row[k].trim())) {
      throw new Error('官方记录缺少必要字段，未更新');
    }
  }
  const keys = rows.map(p => `${p.carrier}:${p.trackingNumber.toUpperCase()}`);
  if (new Set(keys).size !== keys.length) throw new Error('官方记录出现重复，未更新');
  const parcels = state.parcels.map(p => ['cainiao-web', 'taobao-web'].includes(p.source) ? { ...p, inLatestOfficialSnapshot: false } : { ...p });
  for (const row of rows) {
    const index = parcels.findIndex(p => !p.isDemo && ['taobao', 'cainiao'].includes(p.providerID) && same(p.carrier, row.carrier) && same(p.trackingNumber, row.trackingNumber));
    const previous = index >= 0 ? parcels[index] : null;
    const incoming = { ...previous, ...row, id: previous?.id || crypto.randomUUID(),
      addedAt: previous?.addedAt || snapshot.readAt, collectedAt: null, isDemo: false,
      providerID: 'taobao', source: 'taobao-web', lastReadAt: snapshot.readAt, inLatestOfficialSnapshot: true };
    if (index >= 0) parcels[index] = incoming;
    else parcels.unshift(incoming);
  }
  return { ...state, parcels, lastOfficialReadAt: snapshot.readAt };
}
