import test from 'node:test';
import assert from 'node:assert/strict';
import {parcelAction,undoParcelAction,saveParcelNote,saveStationPreference,stationName,sortedStations,syncAge} from '../preview/experience.mjs';
import {filterParcels,mergeOfficialSnapshot,validateSavedState,toggleCollected} from '../preview/model.mjs';
const row=(id,station='北门')=>({id,title:'测试包裹',providerID:'taobao',station,pickupCode:'01-02-0003',carrier:'中通',trackingNumber:'TESTZTO'+id,addedAt:'2026-11-16T00:00:00Z',isDemo:false,collectedAt:null,source:'taobao-web',inLatestOfficialSnapshot:true});
const initial=()=>({version:1,customProviders:[],parcels:[row('000001'),row('000002'),row('000003','南门')]});
const snapshot=parcels=>({state:'ready',parcels,expectedCount:parcels.length,readAt:'2026-11-16T01:00:00Z'});

test('批量操作只处理勾选且仍待取的同地点包裹，撤销保留新到件和备注',()=>{
  const state=initial();state.parcels.push({...row('000004'),collectedAt:'2026-11-15T00:00:00Z'});
  const action=parcelAction(state,['000001','000003','000004','missing'],'batch','北门');
  assert.equal(action.receipt.before.length,1);
  assert.equal(action.state.parcels[2].collectedAt,null);
  let current=saveParcelNote(action.state,'000001','新备注');current.parcels=[...current.parcels,row('000005')];
  const result=undoParcelAction(current,action.receipt);
  assert.equal(result.restored,1);assert.equal(result.state.parcels.length,5);assert.equal(result.state.parcels[0].note,'新备注');
  assert.equal(result.state.parcels[0].collectedAt,null);assert.equal(state.parcels[0].collectedAt,null);
});
test('标记已取后同步空清单，再撤销，包裹仍能在待取列表找到',()=>{
  const action=parcelAction(initial(),['000001'],'collect');
  const synced=mergeOfficialSnapshot(action.state,snapshot([]));
  const result=undoParcelAction(synced,action.receipt);
  assert.equal(result.restored,1);
  assert.ok(filterParcels(result.state,[]).some(p=>p.id==='000001'));
  assert.equal(result.state.parcels.find(p=>p.id==='000001').manualPendingOverride,true);
  assert.equal(result.state.parcels.find(p=>p.id==='000002').collectionConfirmedBySync,true);
});
test('删除立即清除持久化短信，撤销恢复同一记录的短信并保留同步更新',()=>{
  let state=initial();state.parcels[0]={...state.parcels[0],collectedAt:'2026-11-16T00:00:00Z',smsOriginal:'虚构短信',smsSender:'中通',smsImportedAt:'2026-11-16T00:00:00Z'};
  const action=parcelAction(state,['000001'],'delete');
  assert.equal(action.state.parcels[0].smsOriginal,null);
  const current={...action.state,parcels:action.state.parcels.map(p=>({...p,lastReadAt:'new-read'}))};
  const result=undoParcelAction(current,action.receipt);
  assert.equal(result.state.parcels[0].smsOriginal,'虚构短信');assert.equal(result.state.parcels[0].lastReadAt,'new-read');
  assert.equal(result.state.parcels[0].collectedAt,state.parcels[0].collectedAt);
});
test('旧撤销不能覆盖用户后续操作，也不恢复被删除的包裹',()=>{
  const action=parcelAction(initial(),['000001'],'collect');
  const changed=toggleCollected(action.state,'000001');
  assert.equal(undoParcelAction(changed,action.receipt).restored,0);
  const deleted=parcelAction(action.state,['000001'],'delete').state;
  assert.equal(undoParcelAction(deleted,action.receipt).restored,0);
});
test('备注经过自动同步与存档往返保留，并能参与搜索',()=>{
  const state=saveParcelNote(initial(),'000001','帮家人取');
  const merged=mergeOfficialSnapshot(state,snapshot([row('000001')]));
  const loaded=validateSavedState(JSON.parse(JSON.stringify(merged)),[{id:'taobao'}]);
  assert.equal(loaded.parcels.find(p=>p.id==='000001').note,'帮家人取');
  assert.equal(filterParcels(loaded,[],{search:'家人'}).length,1);
  assert.throws(()=>saveParcelNote(state,'000001','字'.repeat(121)));
});
test('地点别名与置顶只修改展示，不改变实际站点或身份码绑定',()=>{
  const state={...initial(),stationCredentials:{'北门':'taobao'}};
  const next=saveStationPreference(state,'北门','公司楼下',true);
  assert.equal(stationName(next,'北门'),'公司楼下');assert.equal(sortedStations(next,['南门','北门'])[0],'北门');
  assert.equal(next.parcels[0].station,'北门');assert.equal(next.stationCredentials['北门'],'taobao');
  assert.equal(filterParcels(next,[],{search:'公司楼下'}).length,2);
  assert.equal(stationName(saveStationPreference(next,'北门','',false),'北门'),'北门');
  assert.throws(()=>saveStationPreference(state,'北门','字'.repeat(41),false));
});
test('上次成功同步按本机时间计算，中英文、跨日和未来时间均可读',()=>{
  const now=new Date('2026-11-16T03:00:00Z');
  assert.equal(syncAge('2026-11-16T01:00:00Z',now),'2小时前');
  assert.equal(syncAge('2026-11-14T03:00:00Z',now),'2天前');
  assert.equal(syncAge(null,now),'尚未同步');assert.equal(syncAge('2026-11-17T03:00:00Z',now),'刚刚');
  assert.equal(syncAge('2026-11-16T01:00:00Z',now,'en'),'2 hours ago');
});
