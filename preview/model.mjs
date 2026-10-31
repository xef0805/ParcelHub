export const STORAGE_KEY = 'parcelhub.preview.v1';
export const DEFAULT_PROVIDER_IDS = ['taobao', 'tuxi', 'yishoufa', 'fcbox', 'sms'];

export function arrivalDay(daysAgo, readAt) {
  if(!Number.isInteger(daysAgo)||daysAgo<0||daysAgo>3650||typeof readAt!=='string')return null;
  const date=new Date(readAt);if(!Number.isFinite(date.getTime()))return null;
  date.setDate(date.getDate()-daysAgo);
  return `${date.getFullYear()}-${String(date.getMonth()+1).padStart(2,'0')}-${String(date.getDate()).padStart(2,'0')}`;
}
export function arrivalAge(day, now=new Date()) {
  if(typeof day!=='string'||!/^\d{4}-\d{2}-\d{2}$/.test(day)||!Number.isFinite(now.getTime()))return null;
  const date=new Date(day+'T00:00:00.000Z');
  if(!Number.isFinite(date.getTime())||date.toISOString().slice(0,10)!==day)return null;
  // 比较日历日期，避免夏令时的 23/25 小时日造成天数误差。
  const days=Math.round((Date.UTC(now.getFullYear(),now.getMonth(),now.getDate())-date.getTime())/86400000);
  return days>=0?days:null;
}
export function arrivalLabel(day, now=new Date(), language='zh-Hans') {
  const days=arrivalAge(day,now);if(days===null)return '';
  return language==='en'?(days===0?'Arrived today':`Arrived ${days}d ago`):(days===0?'今日到站':`${days}日前到站`);
}
export function nextParcelTitle(parcels, date=new Date()) {
  const day=arrivalDay(0,date.toISOString()),compact=day.replaceAll('-',''),short=compact.slice(4);
  let serial=1;
  for(const parcel of parcels.filter(p=>!p.isDemo&&new Date(p.addedAt).getFullYear()===date.getFullYear())){
    const title=String(parcel.title||''),prefix=[compact,day+' ',short].find(p=>title.startsWith(p));
    const match=prefix&&title.slice(prefix.length).match(/^(?:包裹|快件)(\d+)号$/);
    if(match&&Number.isSafeInteger(Number(match[1])+1))serial=Math.max(serial,Number(match[1])+1);
  }
  return `${short}包裹${serial}号`;
}
export function credentialProviders(state, catalog) {
  return orderedProviders(catalog, [], state.providerOrderIDs || []).filter(p => DEFAULT_PROVIDER_IDS.includes(p.id));
}
export function groupCollected(parcels) {
  const groups = new Map();
  for (const parcel of [...parcels].filter(p => p.collectedAt).sort((a, b) => Date.parse(b.collectedAt) - Date.parse(a.collectedAt))) {
    const date = new Date(parcel.collectedAt);
    if (Number.isNaN(date.getTime())) continue;
    const day = `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
    if (!groups.has(day)) groups.set(day, new Map());
    const stations = groups.get(day);
    if (!stations.has(parcel.station)) stations.set(parcel.station, []);
    stations.get(parcel.station).push(parcel);
  }
  return [...groups].map(([day, stations]) => ({ day, stations: [...stations].map(([station, parcels]) => ({ station, parcels })) }));
}

export function orderedProviders(catalog, custom = [], order = []) {
  const all = [...catalog, ...custom].filter(p => p.id !== 'manual');
  const ids = [...new Set(order)].filter(id => all.some(p => p.id === id));
  return [...ids.map(id => all.find(p => p.id === id)), ...all.filter(p => !ids.includes(p.id))];
}

export function reorderProvider(state, providers, id, destination) {
  const ids = providers.map(p => p.id);
  const from = ids.indexOf(id);
  if (from < 0 || !Number.isInteger(destination) || destination < 0 || destination >= ids.length) return state;
  ids.splice(from, 1);
  ids.splice(destination, 0, id);
  return { ...state, providerOrderIDs: ids };
}

export function bindStationCredential(state, station, providerID, providers) {
  if (!station.trim()) throw new Error('缺少取件地点');
  if (providerID && (providerID === 'manual' || !providers.some(p => p.id === providerID))) throw new Error('请选择有效身份码来源');
  const bindings = { ...(state.stationCredentials || {}) };
  if (providerID) bindings[station] = providerID;
  else delete bindings[station];
  return { ...state, stationCredentials: bindings };
}

export function boundStationProvider(state, station, providers) {
  const id = state.stationCredentials?.[station];
  return providers.find(p => p.id === id && p.id !== 'manual');
}

export function preferredCredentialProvider(state, providers) {
  const choices = providers.filter(p => p.id !== 'manual');
  const preferred = choices.find(p => p.id === state.preferredCredentialID);
  if (preferred) return preferred;
  const bound = [...new Set(Object.values(state.stationCredentials || {}))].map(id => choices.find(p => p.id === id)).filter(Boolean);
  return bound.length === 1 ? bound[0] : undefined;
}

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
  return null;
}

export const identityText = value => String(value || '').normalize('NFKC').replace(/\s/g,'').toUpperCase();
export function smsFingerprint(value) {
  let hash=14695981039346656037n;
  for(const byte of new TextEncoder().encode(identityText(value)))hash=BigInt.asUintN(64,(hash^BigInt(byte))*1099511628211n);
  return hash.toString(16);
}
export function canonicalCarrier(value) {
  const text=identityText(value);
  return [['菜鸟速递',['菜鸟速递','丹鸟']],['韵达',['韵达','YUNDA']],['中通',['中通','ZTO']],['圆通',['圆通','YTO']],['申通',['申通','STO']],['顺丰',['顺丰','S.F.','SF']],['京东',['京东','JDL']],['极兔',['极兔','J&T']],['德邦',['德邦','DEPPON']],['EMS',['EMS']],['邮政',['邮政']]].find(([,names])=>names.some(name=>text.includes(name)))?.[0]||text;
}
const fullTracking = value => /^[A-Z0-9-]{6,40}$/.test(identityText(value));
export const pickupCredentials = parcel => parcel.credentials || [{providerID:parcel.providerID,station:parcel.station,pickupCode:parcel.pickupCode,source:parcel.source||'manual',isCurrent:parcel.inLatestOfficialSnapshot!==false,lastSeenAt:parcel.lastReadAt||parcel.addedAt}];
export function attachCredential(parcel, credential) {
  const credentials=pickupCredentials(parcel).map(p=>({...p}));
  const index=credentials.findIndex(p=>p.providerID===credential.providerID&&p.source===credential.source&&p.station===credential.station);
  if(index<0)credentials.push(credential);else credentials[index]=credential;
  return {...parcel,credentials};
}
export function matchParcel(incoming, records, now=Date.now()) {
  const company=canonicalCarrier(incoming.carrier),number=identityText(incoming.trackingNumber);
  const compatible=p=>!company||!canonicalCarrier(p.carrier)||company===canonicalCarrier(p.carrier);
  const strong=records.map((p,i)=>({p,i})).filter(({p})=>!p.isDemo&&fullTracking(number)&&fullTracking(p.trackingNumber)&&identityText(p.trackingNumber)===number&&compatible(p));
  if(strong.length>1)throw new Error('有多条可能相同的记录，请补全快递公司和完整运单号后再导入');
  if(strong.length)return strong[0].i;
  const weak=records.map((p,i)=>({p,i})).filter(({p})=>{
    if(p.isDemo||!compatible(p)||Math.abs(now-Date.parse(p.addedAt))>=72*3600000)return false;
    if(fullTracking(number)&&fullTracking(p.trackingNumber)&&number!==identityText(p.trackingNumber))return false;
    const incomingHash=incoming.smsFingerprint||(incoming.smsOriginal?smsFingerprint(incoming.smsOriginal):null);
    const previousHash=p.smsFingerprint||(p.smsOriginal?smsFingerprint(p.smsOriginal):null);
    if(incomingHash&&incomingHash===previousHash)return true;
    return !p.collectedAt&&!p.deletedAt&&company&&canonicalCarrier(p.carrier)===company&&identityText(p.station)===identityText(incoming.station)&&identityText(p.pickupCode)===identityText(incoming.pickupCode);
  });
  if(weak.length>1)throw new Error('有多条可能相同的记录，请补全快递公司和完整运单号后再导入');
  return weak[0]?.i??-1;
}
export function coalesceParcels(records) {
  const result=[];
  for(const p of records){
    const index=!p.isDemo&&fullTracking(p.trackingNumber)&&canonicalCarrier(p.carrier)?result.findIndex(q=>!q.isDemo&&identityText(q.trackingNumber)===identityText(p.trackingNumber)&&canonicalCarrier(q.carrier)===canonicalCarrier(p.carrier)):-1;
    if(index<0){result.push({...p});continue;}
    let merged=result[index];for(const credential of pickupCredentials(p))merged=attachCredential(merged,credential);
    merged.addedAt=Date.parse(merged.addedAt)<Date.parse(p.addedAt)?merged.addedAt:p.addedAt;
    merged.awaitingArrival=merged.awaitingArrival===true&&p.awaitingArrival===true;
    if(!merged.arrivedOn&&identityText(merged.station)===identityText(p.station))merged.arrivedOn=p.arrivedOn;
    if(p.collectedAt&&(!merged.collectedAt||Date.parse(p.collectedAt)>=Date.parse(merged.collectedAt))){merged.collectedAt=p.collectedAt;merged.collectionConfirmedBySync=p.collectionConfirmedBySync;}
    merged.manualPendingOverride=merged.manualPendingOverride===true||p.manualPendingOverride===true?true:null;
    merged.deletedAt=merged.deletedAt||p.deletedAt;
    merged.smsFingerprint=merged.smsFingerprint||p.smsFingerprint||(p.smsOriginal?smsFingerprint(p.smsOriginal):null);
    if(p.smsOriginal&&(!merged.smsOriginal||Date.parse(p.smsImportedAt)>Date.parse(merged.smsImportedAt)))Object.assign(merged,{smsOriginal:p.smsOriginal,smsSender:p.smsSender,smsImportedAt:p.smsImportedAt,smsFingerprint:p.smsFingerprint||smsFingerprint(p.smsOriginal)});
    if(merged.deletedAt)Object.assign(merged,{smsOriginal:null,smsSender:null,smsImportedAt:null});
    result[index]=merged;
  }return result;
}
export function addParcel(state, input, providers) {
  const error=validateParcel(input,providers,state.parcels);if(error)throw new Error(error);
  if(input.smsOriginal?.length>8000)throw new Error('短信内容过长，请只粘贴本条取件通知');
  const now=new Date().toISOString();
  const arrivedOn=input.arrivedOn??(input.source==='sms'?arrivalDay(0,now):null);
  if(arrivedOn!==null&&(arrivalAge(arrivedOn)===null||arrivalAge(arrivedOn)>7))throw new Error('到站日期仅支持今天及前7天');
  const parcel={id:crypto.randomUUID(),title:clean(input.title),station:clean(input.station),pickupCode:clean(input.pickupCode),providerID:input.providerID,
    arrivedOn,
    carrier:clean(input.carrier),trackingNumber:identityText(input.trackingNumber),addedAt:now,collectedAt:null,isDemo:false,source:input.source==='sms'?'sms':'manual',
    ...(input.smsOriginal?.trim()?{smsOriginal:input.smsOriginal,smsSender:clean(input.smsSender)||clean(input.carrier)||'取件通知',smsImportedAt:now,smsFingerprint:smsFingerprint(input.smsOriginal)}:{})};
  const parcels=coalesceParcels(state.parcels),index=matchParcel(parcel,parcels);
  if(index<0){
    if(/^\d{4}包裹\d+号$/.test(parcel.title))parcel.title=nextParcelTitle(parcels,new Date(now));
    parcels.unshift(parcel);
  }else{
    const previous=parcels[index];if(previous.deletedAt)throw new Error('该包裹的已取记录已删除，不会重复导入');
    let merged={...previous,trackingNumber:previous.trackingNumber||parcel.trackingNumber,carrier:previous.carrier||parcel.carrier,arrivedOn:previous.arrivedOn||parcel.arrivedOn};
    if(previous.awaitingArrival===true)Object.assign(merged,{awaitingArrival:false,station:parcel.station,pickupCode:parcel.pickupCode,providerID:parcel.providerID,source:parcel.source});
    if(parcel.smsOriginal&&identityText(parcel.smsOriginal)!==identityText(previous.smsOriginal))Object.assign(merged,{smsOriginal:parcel.smsOriginal,smsSender:parcel.smsSender,smsImportedAt:now,smsFingerprint:parcel.smsFingerprint});
    parcels[index]=attachCredential(merged,{providerID:parcel.providerID,station:parcel.station,pickupCode:parcel.pickupCode,source:parcel.source,isCurrent:true,lastSeenAt:now});
  }
  return {...state,parcels,lastImportWasDuplicate:index>=0};
}
export function addTracking(state,input){
  const number=identityText(input.trackingNumber),carrier=clean(input.carrier),title=clean(input.title);
  if(/[\r\n]/.test(input.trackingNumber||''))throw new Error('每次请只导入一个完整运单号');
  if(!/^[A-Z0-9]{8,40}$/.test(number)||!/[0-9]/.test(number)||/^1[3-9]\d{9}$/.test(number))throw new Error('请填写8–40位完整运单号，不能使用手机号');
  if(title.length>60||carrier.length>30)throw new Error('填写内容过长');
  const parcel={id:crypto.randomUUID(),title:title||(carrier?carrier+'包裹':'单号导入包裹'),providerID:'manual',station:'',pickupCode:'',carrier,trackingNumber:number,addedAt:new Date().toISOString(),collectedAt:null,isDemo:false,source:'tracking',awaitingArrival:true};
  const parcels=coalesceParcels(state.parcels),index=matchParcel(parcel,parcels);
  if(index<0)parcels.unshift(parcel);else{
    if(parcels[index].deletedAt)throw new Error('该包裹记录已删除，不会重复导入');
    parcels[index]={...parcels[index],carrier:parcels[index].carrier||carrier};
  }
  return {...state,parcels,lastImportWasDuplicate:index>=0};
}
export function filterWatching(state){return state.parcels.filter(p=>!p.isDemo&&!p.deletedAt&&!p.collectedAt&&p.awaitingArrival===true);}
export function deleteCollected(state,id){
  return {...state,parcels:state.parcels.map(p=>p.id===id&&p.collectedAt?{...p,deletedAt:new Date().toISOString(),smsFingerprint:p.smsFingerprint||(p.smsOriginal?smsFingerprint(p.smsOriginal):null),smsOriginal:null,smsSender:null,smsImportedAt:null}:p)};
}
export function toggleCollected(state, id) {
  return { ...state, parcels: state.parcels.map(p => p.id === id && !p.deletedAt ? { ...p, collectedAt: p.collectedAt ? null : new Date().toISOString(), manualPendingOverride: p.collectedAt ? true : null, collectionConfirmedBySync: null } : p) };
}

export function filterParcels(state, providers, { collected = false, providerID = 'all', search = '' } = {}) {
  const term = search.trim().toLocaleLowerCase();
  return state.parcels.filter(p => !p.deletedAt && Boolean(p.collectedAt) === collected && (collected || (p.awaitingArrival!==true && (p.manualPendingOverride===true || (pickupCredentials(p).some(c=>c.source.endsWith('-web')) ? pickupCredentials(p).some(c=>c.source.endsWith('-web')&&c.isCurrent) : p.inLatestOfficialSnapshot !== false)))) && (providerID === 'all' || p.providerID === providerID) &&
    (!term || [p.title, p.station, p.pickupCode, p.trackingNumber, p.carrier, providers.find(s => s.id === p.providerID)?.name || '']
      .join(' ').toLocaleLowerCase().includes(term)));
}

export function validateSavedState(value, catalog) {
  if (!value || value.version !== 1 || !Array.isArray(value.parcels) || !Array.isArray(value.customProviders)) throw new Error('不支持的本地数据格式');
  const ids = new Set([...catalog.map(p => p.id),'pdd','cainiao','jd','mamayz','panda']);
  for (const p of value.customProviders) {
    if (!p || typeof p.id !== 'string' || !p.id.startsWith('custom-') || ids.has(p.id) ||
        !['name', 'shortName', 'miniProgramName', 'kind', 'symbol'].every(k => typeof p[k] === 'string') ||
        !/^#[0-9a-f]{6}$/i.test(p.color) || p.website !== '' || p.featured !== false) throw new Error('平台配置损坏');
    ids.add(p.id);
  }
  if (value.enabledProviderIDs !== undefined && (!Array.isArray(value.enabledProviderIDs) || value.enabledProviderIDs.some(id => typeof id !== 'string'))) throw new Error('平台配置损坏');
  if (value.identityBindings !== undefined && (!value.identityBindings || Array.isArray(value.identityBindings) || typeof value.identityBindings !== 'object'
      || Object.entries(value.identityBindings).some(([id, binding]) => !ids.has(id) || !binding || !['shareCode', 'launchURL'].includes(binding.kind)
        || typeof binding.value !== 'string' || typeof binding.confirmed !== 'boolean'))) throw new Error('身份码入口配置损坏');
  const parcelIDs = new Set();
  for (const p of value.parcels) {
    if (!p || !['id', 'title', 'station', 'pickupCode', 'carrier', 'trackingNumber', 'addedAt'].every(k => typeof p[k] === 'string') ||
        !ids.has(p.providerID) || typeof p.isDemo !== 'boolean' || parcelIDs.has(p.id) ||
        !(p.collectedAt === null || typeof p.collectedAt === 'string')) throw new Error('包裹记录损坏');
    for (const key of ['smsOriginal','smsSender','smsImportedAt','smsFingerprint','deletedAt','arrivedOn']) {
      if (p[key] !== undefined && p[key] !== null && typeof p[key] !== 'string') throw new Error('短信记录损坏');
    }
    if(p.awaitingArrival!==undefined&&p.awaitingArrival!==null&&typeof p.awaitingArrival!=='boolean')throw new Error('包裹状态损坏');
    if(p.manualPendingOverride!==undefined&&p.manualPendingOverride!==null&&typeof p.manualPendingOverride!=='boolean')throw new Error('包裹状态损坏');
    if(p.collectionConfirmedBySync!==undefined&&p.collectionConfirmedBySync!==null&&typeof p.collectionConfirmedBySync!=='boolean')throw new Error('包裹状态损坏');
    if (p.smsOriginal?.length > 8000 || (p.credentials !== undefined && p.credentials !== null && (!Array.isArray(p.credentials)
        || p.credentials.some(c=>!c||!['providerID','station','pickupCode','source','lastSeenAt'].every(k=>typeof c[k]==='string')||typeof c.isCurrent!=='boolean')))) throw new Error('取件凭证损坏');
    parcelIDs.add(p.id);
  }
  return { ...value, customProviders:[], enabledProviderIDs:DEFAULT_PROVIDER_IDS, stationCredentials:Object.fromEntries(Object.entries(value.stationCredentials||{}).filter(([,id])=>DEFAULT_PROVIDER_IDS.includes(id))),identityBindings:Object.fromEntries(Object.entries(value.identityBindings||{}).filter(([id])=>DEFAULT_PROVIDER_IDS.includes(id))), parcels:coalesceParcels(value.parcels.map(p=>({...p,providerID:p.source==='cainiao-web'?'taobao':catalog.some(c=>c.id===p.providerID)?p.providerID:'manual'}))) };
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
  const keys=rows.map(p=>canonicalCarrier(p.carrier)+':'+identityText(p.trackingNumber));
  if(new Set(keys).size!==keys.length)throw new Error('官方记录出现重复，未更新');
  const importedAt=new Date().toISOString();
  const parcels=coalesceParcels(state.parcels).map(p=>({...p,
    ...(['taobao-web','cainiao-web'].includes(p.source)?{inLatestOfficialSnapshot:false}:{}),
    credentials:pickupCredentials(p).map(c=>['taobao-web','cainiao-web'].includes(c.source)?{...c,isCurrent:false}:{...c})}));
  for(const row of rows){
    const index=matchParcel(row,parcels,Date.parse(snapshot.readAt)||Date.now()),previous=index>=0?parcels[index]:null;
    const shouldName=!previous||(['taobao-web','cainiao-web'].includes(previous.source)&&previous.title===row.title&&!previous.smsOriginal);
    const title=shouldName?nextParcelTitle(parcels,new Date(previous?.addedAt||importedAt)):previous.title;
    let incoming={...previous,...row,title,id:previous?.id||crypto.randomUUID(),addedAt:previous?.addedAt||importedAt,collectedAt:previous?.collectedAt||null,isDemo:false,
      arrivedOn:arrivalDay(row.arrivalDaysAgo,snapshot.readAt)||(identityText(previous?.station)===identityText(row.station)?previous?.arrivedOn:null),
      providerID:'taobao',source:'taobao-web',lastReadAt:snapshot.readAt,inLatestOfficialSnapshot:true,awaitingArrival:false};
    incoming=attachCredential(incoming,{providerID:'taobao',station:row.station,pickupCode:row.pickupCode,source:'taobao-web',isCurrent:true,lastSeenAt:snapshot.readAt});
    if(index>=0)parcels[index]=incoming;else parcels.unshift(incoming);
  }
  const confirmedAt=new Date().toISOString();
  for(const parcel of parcels){
    const credentials=pickupCredentials(parcel);
    if(!parcel.isDemo&&!parcel.collectedAt&&!parcel.deletedAt&&parcel.awaitingArrival!==true&&parcel.manualPendingOverride!==true
      &&credentials.some(c=>['taobao-web','cainiao-web'].includes(c.source))&&!credentials.some(c=>c.source.endsWith('-web')&&c.isCurrent)){
      parcel.collectedAt=confirmedAt;parcel.collectionConfirmedBySync=true;
    }
  }
  return {...state,parcels,lastOfficialReadAt:snapshot.readAt};
}
