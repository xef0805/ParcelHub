import {filterParcels, toggleCollected, deleteCollected} from './model.mjs';

export const stationName = (state, station) => state.stationPreferences?.[station]?.alias || station;
export function sortedStations(state, stations) {
  return [...new Set(stations)].sort((a,b) => Number(state.stationPreferences?.[b]?.pinned === true) - Number(state.stationPreferences?.[a]?.pinned === true)
    || stationName(state,a).localeCompare(stationName(state,b), 'zh-CN') || a.localeCompare(b));
}
export function saveStationPreference(state, station, alias, pinned) {
  if(typeof station !== 'string' || !station || typeof alias !== 'string' || [...alias.trim()].length > 40) throw new Error('地点名称最多40字');
  return {...state, stationPreferences:{...state.stationPreferences,[station]:{alias:alias.trim(),pinned:!!pinned}}};
}
export function saveParcelNote(state,id,note) {
  if(typeof note!=='string'||[...note.trim()].length>120)throw new Error('备注最多120字');
  return {...state,parcels:state.parcels.map(p=>p.id===id&&!p.deletedAt?{...p,note:note.trim()||null}:p)};
}
export function parcelAction(state, ids, kind, station) {
  const pending=new Set(filterParcels(state,[]).map(p=>p.id));
  const before=state.parcels.filter(p=>ids.includes(p.id)&&!p.deletedAt&&(kind==='delete'?!!p.collectedAt:kind==='batch'?pending.has(p.id)&&p.station===station:true));
  let next=state;
  for(const p of before)next=kind==='delete'?deleteCollected(next,p.id):toggleCollected(next,p.id);
  return {state:next,receipt:{kind,before,after:next.parcels.filter(p=>before.some(q=>q.id===p.id))}};
}
export function undoParcelAction(state,receipt) {
  let restored=0;
  const keys=receipt.kind==='delete'?['deletedAt','collectedAt']:['deletedAt','collectedAt','manualPendingOverride','collectionConfirmedBySync'];
  const fields=receipt.kind==='delete'?['deletedAt','smsOriginal','smsSender','smsImportedAt','smsFingerprint']:['collectedAt','manualPendingOverride','collectionConfirmedBySync'];
  const oldPending=new Set(filterParcels({parcels:receipt.before},[]).map(p=>p.id));
  const parcels=state.parcels.map(current=>{
    const old=receipt.before.find(p=>p.id===current.id),after=receipt.after.find(p=>p.id===current.id);
    if(!old||!after||!keys.every(k=>(current[k]??null)===(after[k]??null)))return current;
    let result={...current};for(const key of fields)result[key]=old[key]??null;
    if(receipt.kind!=='delete'&&oldPending.has(old.id)&&!filterParcels({parcels:[result]},[]).length)result.manualPendingOverride=true;
    restored++;return result;
  });
  return {state:{...state,parcels},restored};
}
export function syncAge(date,now=new Date(),language='zh-Hans') {
  const value=Date.parse(date);if(!Number.isFinite(value))return language==='en'?'Not synced yet':'尚未同步';
  const minutes=Math.max(0,Math.floor((now.getTime()-value)/60000));
  if(minutes<1)return language==='en'?'Just now':'刚刚';
  const count=minutes>=1440?Math.floor(minutes/1440):minutes>=60?Math.floor(minutes/60):minutes;
  const unit=minutes>=1440?'day':minutes>=60?'hour':'minute';
  return language==='en'?new Intl.RelativeTimeFormat('en',{numeric:'always'}).format(-count,unit):`${count}${unit==='day'?'天':unit==='hour'?'小时':'分钟'}前`;
}
