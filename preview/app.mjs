import { STORAGE_KEY, addParcel, toggleCollected, filterParcels, validateSavedState, mergeOfficialSnapshot, credentialProviders, enableProvider, removeProvider, groupCollected, reorderProvider, bindStationCredential, boundStationProvider, preferredCredentialProvider } from './model.mjs';
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
function card(p) {
  const provider = providers().find(x => x.id === p.providerID);
  return `<article class="parcel-card"><div class="parcel-top">${mark(carrierID(p.carrier) || p.providerID)}<div class="parcel-info"><h3>${esc(p.title)}</h3><p>${esc(p.carrier || '快递')} · ${p.source === 'sms' ? '短信导入' : esc(provider?.name || '本地记录')}</p></div><button class="collect-button" data-collect="${esc(p.id)}" aria-label="${p.collectedAt ? '恢复待取' : '我已取件'}">${p.collectedAt ? '恢复待取' : '我已取件'}</button></div><div class="code-row"><strong>${esc(p.pickupCode)}</strong><button data-copy="${esc(p.id)}">复制</button></div></article>`;
}
function render() {
  const records = {...state, parcels:state.parcels.filter(p => !p.isDemo)};
  const pending = filterParcels(records, providers());
  $('#pending-count').textContent = pending.length;
  $('#station-count').textContent = new Set(pending.map(p => p.station)).size;
  const visible = filterParcels(records, providers(), {search:$('#search').value});
  const stations = [...new Set(visible.map(p => p.station))];
  $('#parcel-list').innerHTML = visible.length ? stations.map(station => `<section class="station-group"><div class="station-tools"><h3 class="station-heading">⌖ ${esc(station)}</h3><button class="text-button" data-station="${esc(station)}">${esc(boundStationProvider(state, station, providers())?.name ? boundStationProvider(state, station, providers()).name + '身份码' : '选择身份码')}</button></div>${visible.filter(p => p.station === station).map(card).join('')}</section>`).join('') : '<div class="empty"><strong>暂无待取包裹</strong>短信通知可点击“手动导入包裹”<br>已取历史已移至“我的”</div>';
  const collected = filterParcels(records, providers(), {collected:true, search:$('#history-search').value});
  $('#collected-count').textContent = filterParcels(records, providers(), {collected:true}).length;
  $('#collected-list').innerHTML = collected.length ? groupCollected(collected).map(group=>`<section class="history-day"><h3>${esc(group.day)}</h3>${group.stations.map(place=>`<section class="station-group"><h4>${esc(place.station)}</h4>${place.parcels.map(card).join('')}</section>`).join('')}</section>`).join('') : '<div class="empty">暂无已取记录</div>';
  const all = ordered();
  $('#provider-grid').classList.toggle('sorting', sorting);
  $('#provider-grid').innerHTML = all.map(p => `<div class="swipe-row" data-swipe="${esc(p.id)}">
    <button class="delete-provider" data-remove-provider="${esc(p.id)}" aria-label="删除${esc(p.name)}入口" tabindex="-1">删除</button>
    <div class="provider-tile" ${sorting ? `data-drag="${esc(p.id)}"` : `role="button" tabindex="0" data-entry="${esc(p.id)}" aria-label="打开${esc(p.name)}，右滑可删除"`}>
    ${mark(p.id)}<div class="detail"><strong>${esc(p.name)}${p.id === 'fcbox' ? '取件' : '身份码'}</strong><small>${p.identityURL ? 'App 内官方网页' : state.identityBindings?.[p.id]?.confirmed ? '已绑定 · 直接打开小程序' : p.miniProgramURL ? '已找到官方入口 · 首次试开绑定' : '小程序入口待绑定'}</small></div>${sorting ? `<button class="sort-handle" data-drag-handle="${esc(p.id)}" aria-label="拖动${esc(p.name)}排序"><svg viewBox="0 0 20 20" aria-hidden="true"><path d="M3 5h14M3 10h14M3 15h14"/></svg></button>` : '<span>›</span>'}</div></div>`).join('');
  $('#provider-empty').hidden = all.length > 0;
  $('#sort-providers').textContent = sorting ? '完成' : '排序';
  $('#add-provider').disabled = sorting;
}
function open(content) { $('#modal-content').innerHTML = content; if (!modal.open) modal.showModal(); }
const heading = title => `<div class="modal-head"><h2>${esc(title)}</h2><button class="close-modal" aria-label="关闭">✕</button></div>`;
async function copy(text) { try { await navigator.clipboard.writeText(text); notify('已复制'); } catch { notify('请手动选中复制'); } }
function entry(id, manage=false) {
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
  open(`${heading(`${provider.name}小程序绑定`)}<div class="entry-brand">${mark(id)}<strong>${esc(provider.name)}</strong></div><p class="hint">首次试开并确认后，下次点击直接尝试打开对应小程序。不同平台的身份码不能通用。</p><div class="modal-form"><label class="field">小程序口令或官方跳转链接<textarea id="identity-link" spellcheck="false" placeholder="粘贴链接或 #小程序://…">${esc(binding?.value||provider.miniProgramURL||'')}</textarea></label><p class="form-note" id="link-note"></p><p class="error" id="link-error" role="alert" hidden></p><button class="button primary" id="try-link" hidden>试开${esc(provider.miniProgramName)}</button><button class="button primary" id="confirm-link" hidden>确认已打开，保存绑定</button><button class="button secondary" id="save-share" hidden>保存口令（仍需在微信内打开）</button><button class="button secondary" id="copy-share" hidden>复制口令</button>${binding?'<button class="text-button" id="unbind-link">解除入口绑定</button>':''}</div><p class="hint">获取方式：微信打开「${esc(provider.miniProgramName)}」→ … → 添加到桌面；若打开 Safari，复制地址栏链接。不要粘贴身份码、密码或验证码。</p>${id==='pdd'?'<p class="form-note">拼多多与兔喜分开保留；拼多多的通用身份码入口仍待验证。</p>':''}<p class="form-note">Windows 预览不能验证 iPhone 唤起微信的结果，需在手机上确认。</p>`);
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
  open(`${heading('小程序入口绑定')}<div class="binding-choices">${ordered().filter(p=>!p.identityURL).map(p=>`<button class="provider-tile" data-manage-link="${esc(p.id)}">${mark(p.id)}<span class="detail"><strong>${esc(p.name)}</strong><small>${state.identityBindings?.[p.id]?.confirmed?'已确认跳转链接':state.identityBindings?.[p.id]?.kind==='shareCode'?'已保存口令 · 不能直达':'未绑定'}</small></span><span>›</span></button>`).join('')}</div>`);
}
function stationEntry(station) {
  const bound = boundStationProvider(state, station, providers());
  if (bound) { entry(bound.id); return; }
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
  open(`${heading('手动导入包裹')}<form id="parcel-form" class="modal-form" novalidate><p id="form-error" class="error import-error" role="alert" hidden></p><label class="field">粘贴完整取件短信（可选）<textarea id="sms" placeholder="例如：【韵达快递】您的快件已入库，取件码01-02-0003，请及时领取。"></textarea></label><p class="form-note" id="recognition-note">自动识别物流与取件码；地点优先取短信内容，否则沿用同一物流公司的最近记录。短信原文不会保存。</p><label class="field" id="candidate-field" hidden>选择本次要添加的取件码<select id="candidate-code"></select></label><label class="field">包裹名称<input name="title" maxlength="60" required></label><label class="field">取件平台<select name="providerID">${providers().map(p=>`<option value="${esc(p.id)}" ${p.id==='manual'?'selected':''}>${esc(p.name)}</option>`).join('')}</select></label><label class="field">取件地点<input name="station" maxlength="100" required></label><label class="field">取件码<input name="pickupCode" maxlength="40" required autocapitalize="off"></label><div class="form-row"><label class="field">物流公司<input name="carrier" maxlength="30"></label><label class="field">运单号（选填）<input name="trackingNumber" maxlength="80"></label></div><p class="form-note">核对后保存。历史地点可能变更，可直接修改。</p><button class="button primary" type="submit">确认添加</button></form>`);
  const form=$('#parcel-form');
  form.elements.title.value=readSMS('',state.parcels).title;
  form.addEventListener('input',event=>{if(event.target.matches('input,select')){$('#form-error').hidden=true;event.target.removeAttribute('aria-invalid');}});
  $('#sms').addEventListener('input',()=>{
    if (!$('#sms').value.trim()) return;
    const parsed=readSMS($('#sms').value,state.parcels);
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
      const input=Object.fromEntries(new FormData(form)); input.source=$('#sms').value.trim()?'sms':'manual';
      save(addParcel(state,input,providers())); modal.close(); page('packages'); notify('包裹已加入待取清单');
    } catch(error) { $('#form-error').hidden=false; $('#form-error').textContent=error.message;
      const missing=['title','station','pickupCode'].find(name=>!form.elements[name].value.trim());
      if(missing){form.elements[missing].focus({preventScroll:true});form.elements[missing].setAttribute('aria-invalid','true');}
      $('#form-error').scrollIntoView({block:'start',behavior:'smooth'}); }
  });
}
function providerForm() {
  const active=ordered().map(p=>p.id);
  const available=catalog.filter(p=>p.id!=='manual'&&!active.includes(p.id));
  open(`${heading('添加其他平台')}<p class="hint">选择即可添加平台入口；部分平台还需要绑定官方小程序链接。更多平台会逐步更新。</p><div class="binding-choices">${available.length?available.map(p=>`<button class="provider-tile" data-enable-provider="${esc(p.id)}">${mark(p.id)}<span class="detail"><strong>${esc(p.name)}</strong><small>${p.identityURL?'官方身份码网页':p.miniProgramURL?'已核实小程序首页链接':'小程序入口待绑定'}</small></span><span>＋</span></button>`).join(''):'<p class="hint">已添加全部现有平台。</p>'}</div>`);
}
function settings() {
  open(`${heading('设置')}<label class="switch-row"><input type="checkbox" id="auto-sync" ${state.autoSyncEnabled===false?'':'checked'}>前台自动刷新待取清单</label><p class="hint">iPhone 版在打开或返回前台时检查，并在前台每两分钟检查一次。当前仅淘宝支持自动同步；锁屏后不承诺持续更新。</p><div class="entry-actions"><a class="button secondary" href="${esc(catalog.find(p=>p.id==='taobao').parcelsURL)}" target="_blank" rel="noopener noreferrer">淘宝登录与官方清单 ↗</a></div><div class="entry-actions"><button class="button secondary" id="manage-station-bindings">地点身份码绑定 ›</button><button class="button secondary" id="manage-mini-programs">小程序入口绑定 ›</button></div><h3>短信导入</h3><p class="hint">复制完整短信，自动识别取件码；沿用同一物流公司最近一次地点，名称按日期依次编号。保存前核对，不读取短信收件箱。</p><p class="hint">涂涂取件 0.5.0 · 本地开发预览</p>`);
  $('#auto-sync').onchange=event=>save({...state,autoSyncEnabled:event.target.checked});
  $('#manage-station-bindings').onclick=stationSettings;$('#manage-mini-programs').onclick=miniProgramSettings;
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
  if(control.dataset.removeProvider){save(removeProvider(state,control.dataset.removeProvider,catalog));notify('入口与绑定已移除，包裹记录保留');}
  if(control.dataset.enableProvider){save(enableProvider(state,control.dataset.enableProvider,catalog));providerForm();notify('平台入口已添加');}
  if(control.dataset.station)stationEntry(control.dataset.station);
  if(control.dataset.bindProvider){save(bindStationCredential(state,control.dataset.bindStation,control.dataset.bindProvider,providers()));entry(control.dataset.bindProvider);}
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
$('#add-parcel').onclick=()=>parcelForm();$('#home-identity').onclick=()=>{const preferred=preferredCredentialProvider(state,ordered());if(preferred)entry(preferred.id);else page('providers');};$('#add-provider').onclick=providerForm;
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

providerGrid.addEventListener('pointerdown',event=>{
  const row=event.target.closest('.swipe-row');
  if(sorting||!row||event.target.closest('button'))return;
  swipe={row,startX:event.clientX,startY:event.clientY,dx:row.classList.contains('swiped')?76:0,offset:row.classList.contains('swiped')?76:0,locked:false};
});
providerGrid.addEventListener('pointermove',event=>{
  if(!swipe)return;const dx=event.clientX-swipe.startX,dy=event.clientY-swipe.startY;
  if(!swipe.locked&&Math.abs(dy)>12){swipe=null;return;}
  if(!swipe.locked&&Math.abs(dx)>12){swipe.locked=true;swipe.row.setPointerCapture(event.pointerId);}
  if(swipe.locked){event.preventDefault();swipe.dx=Math.max(0,Math.min(80,swipe.offset+dx));swipe.row.querySelector('.provider-tile').style.transform=`translateX(${swipe.dx}px)`;}
});
const endSwipe=()=>{if(!swipe)return;const {row,locked,dx}=swipe;
  if(locked){row.classList.toggle('swiped',dx>45);row.querySelector('.provider-tile').style.transform='';row.querySelector('.delete-provider').tabIndex=dx>45?0:-1;suppressEntryUntil=Date.now()+400;}swipe=null;};
providerGrid.addEventListener('pointerup',endSwipe);providerGrid.addEventListener('pointercancel',()=>{if(swipe){swipe.row.querySelector('.provider-tile').style.transform='';swipe=null;}});
providerGrid.addEventListener('keydown',event=>{if(event.key==='Delete'){const row=event.target.closest('.swipe-row');if(row){event.preventDefault();row.classList.add('swiped');row.querySelector('.delete-provider').tabIndex=0;row.querySelector('.delete-provider').focus();}}});
