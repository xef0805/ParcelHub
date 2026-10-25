import { STORAGE_KEY, addParcel, toggleCollected, filterParcels, validateSavedState, mergeOfficialSnapshot, credentialProviders, deleteCollected, pickupCredentials, groupCollected, reorderProvider, bindStationCredential, boundStationProvider } from './model.mjs';
const $ = selector => document.querySelector(selector);
const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const modal = $('#modal');
const testing = new URLSearchParams(location.search).get('test') === '1';
const key = testing ? 'tutu.preview.test.v1' : STORAGE_KEY;
let catalog = [], assets = [], state, readSMS, parseIdentityLink, sorting = false, readonly = false, currentPage = 'packages', dragState;
let toastTimer;
const providers = () => [...catalog, ...state.customProviders];
const ordered = () => credentialProviders(state, catalog);
const mark = id => {
  if(id==='sms')return '<span class="mark sms-mark">✉</span>';
  const brand = assets.find(x => x.id === id);
  return `<span class="mark">${brand ? `<img src="${esc(brand.preview)}" alt="${esc(brand.name)}">` : '▣'}</span>`;
};
const carrierID = company => [['韵达','yunda'],['中通','zto'],['申通','sto'],['圆通','yto'],['顺丰','sf'],['京东','jd'],['极兔','jtexpress'],['德邦','deppon'],['EMS','ems'],['邮政','post'],['菜鸟','cainiao']].find(([name]) => company.toUpperCase().includes(name))?.[1];
function notify(text) { $('#toast').textContent = text; $('#toast').hidden = false; clearTimeout(toastTimer); toastTimer = setTimeout(() => $('#toast').hidden = true, 3000); }
function save(next) {
  if (readonly) throw new Error('本地数据异常，暂不覆盖原记录');
  localStorage.setItem(key, JSON.stringify(next)); state = next; render();
}
function page(name) {
  currentPage = ['packages','providers','my'].includes(name) ? name : 'packages';
  document.querySelectorAll('.page').forEach(p => p.hidden = p.id !== `page-${currentPage}`);
  document.querySelectorAll('[data-page]').forEach(b => b.classList.toggle('active', b.dataset.page === currentPage));
  history.replaceState(null, '', `${location.pathname}${location.search}#${currentPage}`); window.scrollTo({top:0});
}
const trashIcon='<svg viewBox="0 0 24 24" width="23" height="23" aria-hidden="true"><path d="M4 7h16M9 7V4h6v3M6 7l1 14h10l1-14M10 10v7M14 10v7" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>';
function card(p) {
  const provider=providers().find(x=>x.id===p.providerID);
  const alternatives=pickupCredentials(p).filter(c=>c.isCurrent&&c.pickupCode!==p.pickupCode);
  const article=`<article class="parcel-card"><div class="parcel-top">${mark(carrierID(p.carrier)||p.providerID)}<div class="parcel-info"><h3>${esc(p.title)}</h3><p>${esc(p.carrier||'快递')} · ${p.smsOriginal?'含短信凭证':esc(provider?.name||'历史记录')}</p></div><button class="collect-button" data-collect="${esc(p.id)}">${p.collectedAt?'恢复待取':'我已取件'}</button></div><div class="code-row"><strong>${esc(p.pickupCode)}</strong><button data-copy="${esc(p.id)}">复制</button></div>${p.trackingNumber?`<p class="tracking-line">运单号 ${esc(p.trackingNumber)}</p>`:''}${alternatives.map(c=>`<p class="tracking-line">${esc(providers().find(x=>x.id===c.providerID)?.name||'其他来源')}取件码 · ${esc(c.pickupCode)}</p>`).join('')}${p.smsOriginal?`<button class="sms-pass-button" data-sms="${esc(p.id)}">✉ 短信身份码</button>`:''}</article>`;
  return p.collectedAt?`<div class="history-swipe" data-history-swipe="${esc(p.id)}"><button class="history-delete" data-delete-collected="${esc(p.id)}" aria-label="删除${esc(p.title)}" tabindex="-1">${trashIcon}</button>${article}</div>`:article;
}
function smsView(id){
  const p=state.parcels.find(p=>p.id===id&&!p.deletedAt);if(!p)return;
  open(`${heading('短信身份码')}<div class="sms-conversation"><div class="sms-sender">${mark(carrierID(p.carrier))}<h3>${esc(p.smsSender||p.carrier||'取件通知')}</h3></div><div class="sms-time">短信凭证 · 本机保存<br>导入于 ${esc(new Date(p.smsImportedAt||p.addedAt).toLocaleString('zh-CN'))}</div><div class="sms-bubble">${esc(p.smsOriginal||'旧版本未保存短信原文，可重新导入补充。')}</div><p class="form-note">内容为你导入的短信原文，显示时间为导入时间。</p></div>`);
  modal.classList.add('sms-dialog');
}
function smsEntry(station){
  const rows=filterParcels({...state,parcels:state.parcels.filter(p=>!p.isDemo)},providers()).filter(p=>p.smsOriginal&&(!station||p.station===station||pickupCredentials(p).some(c=>c.station===station)));
  if(rows.length===1){smsView(rows[0].id);return;}
  open(`${heading('短信身份码')}<div class="binding-choices">${rows.length?rows.map(p=>`<button class="provider-tile" data-sms="${esc(p.id)}"><span class="detail"><strong>${esc(p.title)}</strong><small>${esc(p.station)} · ${esc(p.pickupCode)}</small></span><span>›</span></button>`).join(''):'<p class="hint">暂无待取短信凭证。导入取件短信后会保存原文；历史短信可在已取记录查看。</p>'}</div>`);
}
function render() {
  const records = {...state, parcels:state.parcels.filter(p => !p.isDemo)};
  const pending = filterParcels(records, providers());
  $('#pending-count').textContent = pending.length;
  $('#station-count').textContent = new Set(pending.map(p => p.station)).size;
  const visible = filterParcels(records, providers(), {search:$('#search').value});
  const stations = [...new Set(visible.map(p => p.station))];
  const stationLabel=station=>{const bound=boundStationProvider(state,station,providers());return !bound?'选择身份码':bound.id==='sms'?'短信身份码':bound.name+'身份码';};
  $('#parcel-list').innerHTML = visible.length ? stations.map(station => `<section class="station-group"><div class="station-tools"><h3 class="station-heading">⌖ ${esc(station)}</h3><button class="text-button" data-station="${esc(station)}">${esc(stationLabel(station))}</button></div>${visible.filter(p => p.station === station).map(card).join('')}</section>`).join('') : '<div class="empty"><strong>暂无待取包裹</strong>短信通知可点击“手动导入包裹”<br>已取历史已移至“我的”</div>';
  const collected = filterParcels(records, providers(), {collected:true, search:$('#history-search').value});
  $('#collected-count').textContent = filterParcels(records, providers(), {collected:true}).length;
  $('#collected-list').innerHTML = collected.length ? groupCollected(collected).map(group=>`<section class="history-day"><h3>${esc(group.day)}</h3>${group.stations.map(place=>`<section class="station-group"><h4>${esc(place.station)}</h4>${place.parcels.map(card).join('')}</section>`).join('')}</section>`).join('') : '<div class="empty">暂无已取记录</div>';
  const all = ordered();
  $('#provider-grid').classList.toggle('sorting', sorting);
  $('#provider-grid').innerHTML = all.map(p=>`<div class="provider-tile" ${sorting?`data-drag="${esc(p.id)}"`:`role="button" tabindex="0" data-entry="${esc(p.id)}" aria-label="打开${esc(p.name)}"`}>
    ${mark(p.id)}<div class="detail"><strong>${esc(p.name)}${p.id==='sms'?'':p.id==='fcbox'?'取件':'身份码'}</strong><small>${p.id==='sms'?'展示本机保存的取件短信':p.identityURL?'App 内官方网页':state.identityBindings?.[p.id]?.confirmed?'已绑定 · 直接打开小程序':'官方小程序 · 首次试开绑定'}</small></div>${sorting?`<button class="sort-handle" data-drag-handle="${esc(p.id)}" aria-label="拖动${esc(p.name)}排序"><svg viewBox="0 0 20 20"><path d="M3 5h14M3 10h14M3 15h14"/></svg></button>`:'<span>›</span>'}</div>`).join('');
  $('#sort-providers').textContent=sorting?'完成':'排序';
}
function open(content) { modal.classList.remove('sms-dialog'); $('#modal-content').innerHTML = content; if (!modal.open) modal.showModal(); }
const heading = title => `<div class="modal-head"><h2>${esc(title)}</h2><button class="close-modal" aria-label="关闭">✕</button></div>`;
async function copy(text) { try { await navigator.clipboard.writeText(text); notify('已复制'); } catch { notify('请手动选中复制'); } }
function entry(id, manage=false) {
  if(id==='sms'){smsEntry();return;}
  const provider = providers().find(p => p.id === id); if (!provider) return;
  if (state.preferredCredentialID !== id) save({ ...state, preferredCredentialID: id });
  if (provider.identityURL) {
    if (modal.open) modal.close();
    window.open(provider.identityURL, '_blank', 'noopener,noreferrer');
    return;
  }
  const binding = state.identityBindings?.[id];
  if (!manage && binding?.confirmed && parseIdentityLink(binding.value,provider.miniProgramName).kind==='launchURL') {
    if(modal.open)modal.close();
    window.open(binding.value,'_blank','noopener,noreferrer'); return;
  }
  open(`${heading(`${provider.name}小程序绑定`)}<div class="entry-brand">${mark(id)}<strong>${esc(provider.name)}</strong></div><p class="hint">首次试开并确认后，下次点击直接尝试打开对应小程序。不同平台的身份码不能通用。</p><div class="modal-form"><label class="field">小程序口令或官方跳转链接<textarea id="identity-link" spellcheck="false" placeholder="粘贴链接或 #小程序://…">${esc(binding?.value||provider.miniProgramURL||'')}</textarea></label><p class="form-note" id="link-note"></p><p class="error" id="link-error" role="alert" hidden></p><button class="button primary" id="try-link" hidden>试开${esc(provider.name)}</button><button class="button primary" id="confirm-link" hidden>确认已打开，保存绑定</button><button class="button secondary" id="save-share" hidden>保存口令（仍需在微信内打开）</button><button class="button secondary" id="copy-share" hidden>复制口令</button>${binding?'<button class="text-button" id="unbind-link">解除入口绑定</button>':''}</div><p class="hint">获取方式：微信打开「${esc(provider.miniProgramName)}」→ … → 添加到桌面；若打开 Safari，复制地址栏链接。不要粘贴身份码、密码或验证码。</p><p class="form-note">Windows 预览不能验证 iPhone 唤起微信的结果，需在手机上确认。</p>`);
  let tried='';
  const input=$('#identity-link');
  const update=()=>{
    tried=''; const result=parseIdentityLink(input.value,provider.miniProgramName);
    $('#link-note').textContent=result.message||result.error||'';
    $('#try-link').hidden=result.kind!=='launchURL';$('#confirm-link').hidden=true;
    $('#save-share').hidden=result.kind!=='shareCode';$('#copy-share').hidden=result.kind!=='shareCode';
  };
  input.oninput=update;update();
  $('#try-link').onclick=()=>{const result=parseIdentityLink(input.value,provider.miniProgramName);if(result.kind!=='launchURL')return;
    tried=result.value;window.open(tried,'_blank','noopener,noreferrer');$('#confirm-link').hidden=false;
    $('#link-note').textContent='请返回后确认刚才进入了正确小程序；预览本身无法判断。';};
  $('#confirm-link').onclick=()=>{if(!tried||tried!==input.value.trim())return;
    save({...state,identityBindings:{...state.identityBindings,[id]:{kind:'launchURL',value:tried,confirmed:true}}});modal.close();notify('已保存入口绑定');};
  $('#save-share').onclick=()=>{const result=parseIdentityLink(input.value,provider.miniProgramName);if(result.kind!=='shareCode')return;
    save({...state,identityBindings:{...state.identityBindings,[id]:{kind:'shareCode',value:result.value,confirmed:false}}});notify('已保存口令，仍需在微信内打开');};
  $('#copy-share').onclick=()=>copy(input.value.trim());
  if($('#unbind-link'))$('#unbind-link').onclick=()=>{const identityBindings={...state.identityBindings};delete identityBindings[id];save({...state,identityBindings});entry(id,true);notify('已解除入口绑定');};
}
function miniProgramSettings(){
  open(`${heading('小程序入口绑定')}<div class="binding-choices">${ordered().filter(p=>!p.identityURL&&p.id!=='sms').map(p=>`<button class="provider-tile" data-manage-link="${esc(p.id)}">${mark(p.id)}<span class="detail"><strong>${esc(p.name)}</strong><small>${state.identityBindings?.[p.id]?.confirmed?'已确认跳转链接':state.identityBindings?.[p.id]?.kind==='shareCode'?'已保存口令 · 不能直达':'未绑定'}</small></span><span>›</span></button>`).join('')}</div>`);
}
function stationEntry(station) {
  const bound = boundStationProvider(state, station, providers());
  if (bound) { if(bound.id==='sms')smsEntry(station);else entry(bound.id); return; }
  open(`${heading('选择地点身份码')}<p class="hint">为「${esc(station)}」选择一次，之后直接打开。更换请到“我的 → 设置 → 地点身份码绑定”。</p><div class="binding-choices">${ordered().map(p=>`<button class="provider-tile" data-bind-provider="${esc(p.id)}" data-bind-station="${esc(station)}">${mark(p.id)}<span class="detail"><strong>${esc(p.name)}</strong><small>${p.identityURL ? '直接打开官方身份码' : '官方入口指引，尚未直达动态码'}</small></span><span>›</span></button>`).join('')}</div>`);
}
function stationSettings() {
  const stations=[...new Set([...state.parcels.filter(p=>!p.isDemo).map(p=>p.station),...Object.keys(state.stationCredentials||{})])].sort();
  open(`${heading('地点身份码绑定')}<p class="hint">修改或取消各个地点的身份码绑定，设置立即保存。</p><div class="modal-form">${stations.length ? stations.map(station=>`<label class="field binding-field">${esc(station)}<select data-bind-station="${esc(station)}"><option value="">未绑定</option>${ordered().map(p=>`<option value="${esc(p.id)}" ${boundStationProvider(state,station,providers())?.id===p.id?'selected':''}>${esc(p.name)}</option>`).join('')}</select></label>`).join(''):'<p class="hint">添加包裹后，可在这里绑定取件地点。</p>'}</div><button class="text-button" id="back-settings">返回设置</button>`);
  document.querySelectorAll('select[data-bind-station]').forEach(select=>select.onchange=()=>{
    save(bindStationCredential(state,select.dataset.bindStation,select.value,providers()));notify('地点绑定已保存');
  });
  $('#back-settings').onclick=settings;
}
function parcelForm() {
  open(`${heading('手动导入包裹')}<form id="parcel-form" class="modal-form import-form" novalidate><p id="form-error" class="error import-error" role="alert" hidden></p><div class="import-intro"><strong>粘贴短信，自动整理</strong><span>识别取件码 · 记住地点 · 合并重复包裹</span></div><label class="field">粘贴完整取件短信（可选）<textarea id="sms" placeholder="例如：【韵达快递】您的快件已入库，取件码01-02-0003，请及时领取。"></textarea></label><p class="form-note" id="recognition-note">自动识别物流与取件码；地点优先取短信内容，否则沿用同一物流公司的最近记录。短信原文和导入时间仅保存在本机。</p><label class="field" id="candidate-field" hidden>选择本次要添加的取件码<select id="candidate-code"></select></label><label class="field">包裹名称<input name="title" maxlength="60" required></label><label class="field">取件平台<select name="providerID">${providers().filter(p=>p.id!=='sms').map(p=>`<option value="${esc(p.id)}" ${p.id==='manual'?'selected':''}>${esc(p.name)}</option>`).join('')}</select></label><label class="field">取件地点<input name="station" maxlength="100" required></label><label class="field">取件码<input name="pickupCode" maxlength="40" required autocapitalize="off"></label><div class="form-row"><label class="field">物流公司<input name="carrier" maxlength="30"></label><label class="field">完整快递单号<input name="trackingNumber" placeholder="建议补全，尾号不能去重" maxlength="80"></label></div><p class="form-note">完整单号用于跨平台去重；没有完整单号时，只能保守核对原文、地点和取件码。</p><button class="button primary" type="submit">确认添加</button></form>`);
  let smsSender='';
  const form=$('#parcel-form');
  form.elements.title.value=readSMS('',state.parcels).title;
  form.addEventListener('input',event=>{if(event.target.matches('input,select')){$('#form-error').hidden=true;event.target.removeAttribute('aria-invalid');}});
  $('#sms').addEventListener('input',()=>{
    if (!$('#sms').value.trim()) return;
    const parsed=readSMS($('#sms').value,state.parcels);smsSender=parsed.sender;
    for (const field of ['title','station','pickupCode','carrier','trackingNumber','providerID']) form.elements[field].value=parsed[field];
    $('#form-error').hidden=true;form.querySelectorAll('[aria-invalid]').forEach(el=>el.removeAttribute('aria-invalid'));
    $('#recognition-note').textContent=parsed.message;
    $('#candidate-field').hidden=parsed.codeCandidates.length<2;
    $('#candidate-code').innerHTML='<option value="">请选择</option>'+parsed.codeCandidates.map(code=>`<option>${esc(code)}</option>`).join('');
  });
  $('#candidate-code').onchange=event=>form.elements.pickupCode.value=event.target.value;
  form.addEventListener('submit',event=>{
    event.preventDefault();
    try {
      const input=Object.fromEntries(new FormData(form)); input.source=$('#sms').value.trim()?'sms':'manual';input.smsOriginal=$('#sms').value;input.smsSender=smsSender;
      const next=addParcel(state,input,providers());save(input.smsOriginal&&input.providerID==='manual'&&!next.stationCredentials?.[input.station]?bindStationCredential(next,input.station,'sms',providers()):next); modal.close(); page('packages'); notify('包裹已加入待取清单');
    } catch(error) { $('#form-error').hidden=false; $('#form-error').textContent=error.message;
      const missing=['title','station','pickupCode'].find(name=>!form.elements[name].value.trim());
      if(missing){form.elements[missing].focus({preventScroll:true});form.elements[missing].setAttribute('aria-invalid','true');}
      $('#form-error').scrollIntoView({block:'start',behavior:'smooth'}); }
  });
}
function monitoring(){
  open(`${heading('到站监控')}<div class="monitor-card"><strong>淘宝 · 前台自动检查</strong><p>登录后打开或返回 App 时检查，前台每两分钟检查。新件要先出现在官方清单中。</p></div>${['tuxi','yishoufa','fcbox'].map(id=>`<div class="monitor-card"><strong>${esc(providers().find(p=>p.id===id)?.name)}</strong><p>已核实小程序首页入口；包裹清单尚未接通，不能自动监控到站。</p></div>`).join('')}<p class="hint">短信仅手动粘贴；不读取短信收件箱、不使用快捷指令。本版不承诺锁屏或退出后持续监控。</p>`);
}
function settings() {
  open(`${heading('设置')}<label class="switch-row"><input type="checkbox" id="auto-sync" ${state.autoSyncEnabled===false?'':'checked'}>前台自动刷新待取清单</label><p class="hint">iPhone 版在打开或返回前台时检查，并在前台每两分钟检查一次。当前仅淘宝支持自动同步；锁屏后不承诺持续更新。</p><div class="entry-actions"><a class="button secondary" href="${esc(catalog.find(p=>p.id==='taobao').parcelsURL)}" target="_blank" rel="noopener noreferrer">淘宝登录与官方清单 ↗</a></div><div class="entry-actions"><button class="button secondary" id="manage-station-bindings">地点身份码绑定 ›</button><button class="button secondary" id="manage-mini-programs">小程序入口绑定 ›</button></div><div class="entry-actions"><button class="button secondary" id="show-monitoring">到站监控与接入状态 ›</button></div><h3>短信导入</h3><p class="hint">复制完整短信，自动识别取件码；沿用同一物流公司最近一次地点，名称按日期依次编号。保存前核对，不读取短信收件箱。</p><p class="hint">涂涂取件 0.6.0 · 本地开发预览</p>`);
  $('#auto-sync').onchange=event=>save({...state,autoSyncEnabled:event.target.checked});
  $('#show-monitoring').onclick=monitoring;$('#manage-station-bindings').onclick=stationSettings;$('#manage-mini-programs').onclick=miniProgramSettings;
}
async function refresh() {
  if (testing) { $('#sync-status').textContent='测试模式 · 不访问真实包裹快照'; return; }
  try {
    const response=await fetch('/api/official-snapshot',{cache:'no-store'});
    if (!response.ok) throw new Error('没有新的快照');
    const snapshot=await response.json();
    if (snapshot.readAt!==state.lastOfficialReadAt) save(mergeOfficialSnapshot(state,snapshot));
    $('#sync-status').textContent=`本机快照 ${new Date(snapshot.readAt).toLocaleString('zh-CN')} · 非网页实时同步`;
  }catch{ $('#sync-status').textContent='未读取新快照，保留当前记录；iPhone 登录后可前台同步'; }
}
document.addEventListener('click',event=>{
  const control=event.target.closest('button,[data-entry]');if(!control)return;
  if(control.dataset.page)page(control.dataset.page);
  if(control.dataset.entry&&Date.now()>suppressEntryUntil)entry(control.dataset.entry);
  if(control.dataset.manageLink)entry(control.dataset.manageLink,true);
  if(control.dataset.station)stationEntry(control.dataset.station);
  if(control.dataset.bindProvider){save(bindStationCredential(state,control.dataset.bindStation,control.dataset.bindProvider,providers()));if(control.dataset.bindProvider==='sms')smsEntry(control.dataset.bindStation);else entry(control.dataset.bindProvider);}
  if(control.dataset.sms)smsView(control.dataset.sms);
  if(control.dataset.deleteCollected){save(deleteCollected(state,control.dataset.deleteCollected));notify('已删除已取记录');}
  if(control.dataset.collect){save(toggleCollected(state,control.dataset.collect));notify('记录已更新');}
  if(control.dataset.copy){const p=state.parcels.find(p=>p.id===control.dataset.copy);if(p)copy(p.pickupCode);}
  if(control.classList.contains('close-modal'))modal.close();
});
document.addEventListener('keydown',event=>{if(event.key==='Enter'&&event.target.dataset.entry)entry(event.target.dataset.entry);});
const providerGrid=$('#provider-grid');
let swipe, suppressEntryUntil=0;
function finishDrag(commit=false){
  if(!dragState)return;
  const {id,targetID,frame}=dragState;cancelAnimationFrame(frame);
  document.querySelectorAll('.dragging,.drop-target').forEach(row=>{row.classList.remove('dragging','drop-target');row.style.transform='';});
  dragState=null;
  if(commit){const destination=ordered().findIndex(p=>p.id===targetID);if(destination>=0)save(reorderProvider(state,ordered(),id,destination));}
}
providerGrid.addEventListener('pointerdown',event=>{
  const handle=event.target.closest('[data-drag-handle]');if(!handle||!sorting)return;
  event.preventDefault();handle.setPointerCapture(event.pointerId);
  const row=handle.closest('[data-drag]');
  dragState={id:handle.dataset.dragHandle,targetID:handle.dataset.dragHandle,startY:event.clientY,startScroll:window.scrollY,x:event.clientX,y:event.clientY,row,frame:0};
  row.classList.add('dragging');
  const tick=()=>{
    if(!dragState)return;const d=dragState;
    if(d.y<85)window.scrollBy(0,-12);else if(d.y>innerHeight-100)window.scrollBy(0,12);
    d.row.style.transform=`translateY(${d.y-d.startY+window.scrollY-d.startScroll}px)`;
    const target=document.elementFromPoint(d.x,d.y)?.closest('[data-drag]');
    if(target&&target.dataset.drag!==d.id){
      d.targetID=target.dataset.drag;
      document.querySelectorAll('.drop-target').forEach(el=>el.classList.remove('drop-target'));target.classList.add('drop-target');
    }
    d.frame=requestAnimationFrame(tick);
  };dragState.frame=requestAnimationFrame(tick);
});
providerGrid.addEventListener('pointermove',event=>{if(dragState){dragState.x=event.clientX;dragState.y=event.clientY;}});
providerGrid.addEventListener('pointerup',()=>finishDrag(true));
providerGrid.addEventListener('pointercancel',()=>finishDrag(false));
providerGrid.addEventListener('lostpointercapture',()=>finishDrag(false));
providerGrid.addEventListener('keydown',event=>{
  const handle=event.target.closest('[data-drag-handle]');
  if(!handle||!['ArrowUp','ArrowDown'].includes(event.key))return;
  event.preventDefault();const id=handle.dataset.dragHandle;const index=ordered().findIndex(p=>p.id===id);
  save(reorderProvider(state,ordered(),id,index+(event.key==='ArrowUp'?-1:1)));
  document.querySelector(`[data-drag-handle="${CSS.escape(id)}"]`)?.focus();
});
$('#add-parcel').onclick=()=>parcelForm();
$('#sort-providers').onclick=()=>{finishDrag(false);sorting=!sorting;render();};$('#search').oninput=render;$('#history-search').oninput=render;
$('#show-collected').onclick=()=>{$('#history-panel').hidden=!$('#history-panel').hidden;};$('#show-settings').onclick=settings;
$('#refresh-snapshot').onclick=refresh;
$('.brand').onclick=event=>{event.preventDefault();page('packages');};
try {
  const [catalogResponse,assetResponse,readerResponse,linkResponse]=await Promise.all(['/shared/catalog.json','/shared/brand-assets.json','/shared/sms-reader.js','/shared/identity-link.js'].map(url=>fetch(url)));
  if (![catalogResponse,assetResponse,readerResponse,linkResponse].every(r=>r.ok))throw new Error('本地资源加载失败，请重启预览服务');
  catalog=await catalogResponse.json();assets=(await assetResponse.json()).brands;
  parseIdentityLink=Function('return '+await linkResponse.text())();
  readSMS=Function('return '+await readerResponse.text())();
  const stored=localStorage.getItem(key);
  state=stored?validateSavedState(JSON.parse(stored),catalog):{version:1,customProviders:[],parcels:[]};
  if(testing){
    $('#preview-notice').innerHTML='<span>本地测试模式 · 独立虚构记录</span> <button class="text-button" id="test-theme">切换外观</button>';
    const button=$('#test-theme');
    button.textContent=matchMedia('(prefers-color-scheme: dark)').matches?'浅色预览':'深色预览';
    button.onclick=()=>{
      const html=document.documentElement;
      const dark=html.classList.contains('theme-dark')||(!html.classList.contains('theme-light')&&matchMedia('(prefers-color-scheme: dark)').matches);
      html.classList.toggle('theme-dark',!dark);html.classList.toggle('theme-light',dark);
      button.textContent=dark?'深色预览':'浅色预览';
    };
  }
  page(location.hash.slice(1));render();await refresh();
  setInterval(()=>{if(!document.hidden&&state.autoSyncEnabled!==false)refresh();},120000);
  document.addEventListener('visibilitychange',()=>{if(!document.hidden&&state.autoSyncEnabled!==false)refresh();});
}catch(error){readonly=true;$('#warning').hidden=false;$('#warning').textContent=error.message+'。原有记录未覆盖。';}

document.addEventListener('pointerdown',event=>{
  const row=event.target.closest('[data-history-swipe]');if(!row||event.target.closest('button'))return;
  swipe={row,startX:event.clientX,startY:event.clientY,dx:row.classList.contains('swiped')?72:0,offset:row.classList.contains('swiped')?72:0,locked:false};
});
document.addEventListener('pointermove',event=>{
  if(!swipe)return;const dx=event.clientX-swipe.startX,dy=event.clientY-swipe.startY;
  if(!swipe.locked&&Math.abs(dy)>12){swipe=null;return;}
  if(!swipe.locked&&Math.abs(dx)>12){swipe.locked=true;swipe.row.setPointerCapture(event.pointerId);}
  if(swipe.locked){event.preventDefault();swipe.dx=Math.max(0,Math.min(76,swipe.offset+dx));swipe.row.querySelector('.parcel-card').style.transform=`translateX(${swipe.dx}px)`;}
},{passive:false});
const endHistorySwipe=()=>{if(!swipe)return;const {row,locked,dx}=swipe;
  if(locked){row.classList.toggle('swiped',dx>42);row.querySelector('.parcel-card').style.transform='';row.querySelector('.history-delete').tabIndex=dx>42?0:-1;suppressEntryUntil=Date.now()+400;}swipe=null;};
document.addEventListener('pointerup',endHistorySwipe);document.addEventListener('pointercancel',()=>{if(swipe){swipe.row.querySelector('.parcel-card').style.transform='';swipe=null;}});
document.addEventListener('keydown',event=>{if(event.key==='Delete'){const row=event.target.closest('[data-history-swipe]');if(row){row.classList.add('swiped');row.querySelector('.history-delete').tabIndex=0;row.querySelector('.history-delete').focus();}}});
