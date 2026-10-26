import { STORAGE_KEY, addParcel, filterWatching, toggleCollected, filterParcels, validateSavedState, mergeOfficialSnapshot, credentialProviders, deleteCollected, pickupCredentials, groupCollected, reorderProvider, bindStationCredential, boundStationProvider } from './model.mjs';
import { displayPreferences, localizeDOM } from './i18n.mjs';
import { ModalNavigation } from './modal-navigation.mjs';
import { SERVICE_MESSAGES, statusForSnapshot } from './service-status.mjs';
const english = await (await fetch('/preview/locales/en.json')).json();
const $ = selector => document.querySelector(selector);
const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const modal = $('#modal');
const testing = new URLSearchParams(location.search).get('test') === '1';
const key = testing ? 'tutu.preview.test.v1' : STORAGE_KEY;
let catalog = [], assets = [], state, readSMS, parseIdentityLink, classifyImport, sorting = false, readonly = false, currentPage = 'packages', dragState;
let toastTimer,clipboardCandidate,lastClipboardText='',testServiceState='normal';
const settingsNavigation=new ModalNavigation();let renderingSettings=false;
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
  localStorage.setItem(key, JSON.stringify(next)); state = next; applyDisplayPreferences(); render();
}
function applyDisplayPreferences() {
  const {appearance,language}=displayPreferences(state);
  document.documentElement.classList.toggle('theme-light',appearance==='light');
  document.documentElement.classList.toggle('theme-dark',appearance==='dark');
  document.documentElement.lang=language;
  localizeDOM(document.body,language,english);
}
new MutationObserver(()=>localizeDOM(document.body,displayPreferences(state).language,english))
  .observe(document.body,{subtree:true,childList:true,characterData:true,attributes:true,attributeFilter:['placeholder','aria-label','title']});
function page(name) {
  currentPage = ['packages','providers','my'].includes(name) ? name : 'packages';
  document.querySelectorAll('.page').forEach(p => p.hidden = p.id !== `page-${currentPage}`);
  document.querySelectorAll('[data-page]').forEach(b => b.classList.toggle('active', b.dataset.page === currentPage));
  history.replaceState(null, '', `${location.pathname}${location.search}#${currentPage}`); window.scrollTo({top:0});
}
const copyIcon='<svg viewBox="0 0 24 24" width="15" height="15" aria-hidden="true"><path d="M8 8h12v13H8zM16 8V3H3v13h5" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round"/></svg>';
const trashIcon='<svg viewBox="0 0 24 24" width="23" height="23" aria-hidden="true"><path d="M4 7h16M9 7V4h6v3M6 7l1 14h10l1-14M10 10v7M14 10v7" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>';
function card(p) {
  const provider=providers().find(x=>x.id===p.providerID);
  const alternatives=pickupCredentials(p).filter(c=>c.isCurrent&&c.pickupCode&&c.pickupCode!==p.pickupCode);
  const article=`<article class="parcel-card"><div class="parcel-top">${mark(carrierID(p.carrier)||p.providerID)}<div class="parcel-info"><h3 data-user-content>${esc(p.title)}</h3><p><span data-user-content>${esc(p.carrier||'快递')}</span> · <span>${p.smsOriginal?'含短信凭证':esc(provider?.name||'历史记录')}</span></p></div><button class="collect-button" data-collect="${esc(p.id)}">${p.collectedAt?'恢复待取':'我已取件'}</button></div><div class="code-row"><strong>${esc(p.pickupCode)}</strong>${p.collectedAt?'':`<button data-copy="${esc(p.id)}">复制</button>`}</div>${p.trackingNumber?`<div class="tracking-line"><span>运单号</span> <span data-user-content>${esc(p.trackingNumber)}</span><button class="copy-tracking" data-copy-tracking="${esc(p.id)}" aria-label="复制运单号">${copyIcon}</button></div>`:''}${p.collectedAt&&p.smsOriginal?`<button class="sms-pass-button" data-sms="${esc(p.id)}">✉ 短信身份码</button>`:''}${alternatives.map(c=>`<p class="tracking-line">${esc(providers().find(x=>x.id===c.providerID)?.name||'其他来源')}取件码 · ${esc(c.pickupCode)}</p>`).join('')}</article>`;
  return p.collectedAt?`<div class="history-swipe" data-history-swipe="${esc(p.id)}"><button class="history-delete" data-delete-collected="${esc(p.id)}" aria-label="删除${esc(p.title)}" tabindex="-1">${trashIcon}</button>${article}</div>`:article;
}
function smsView(id){
  const p=state.parcels.find(p=>p.id===id&&!p.deletedAt);if(!p)return;
  const date=new Date(p.smsImportedAt||p.addedAt),today=new Date();
  const time=date.toDateString()===today.toDateString()?date.toLocaleTimeString(displayPreferences(state).language==='en'?'en-US':'zh-CN',{hour:'2-digit',minute:'2-digit'}):date.toLocaleString(displayPreferences(state).language==='en'?'en-US':'zh-CN');
  open(`<button class="close-modal sms-back" aria-label="返回"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="m14 5-7 7 7 7" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/></svg></button><div class="sms-conversation"><div class="sms-sender">${mark(carrierID(p.carrier))}<h3>${esc(p.smsSender||p.carrier||'取件通知')}</h3></div><div class="sms-time">信息<br>${esc(time)}</div><div class="sms-bubble" data-user-content>${esc(p.smsOriginal||'未保存短信原文')}</div></div>`);
  modal.classList.add('sms-dialog');
}
function smsEntry(station){
  const rows=filterParcels({...state,parcels:state.parcels.filter(p=>!p.isDemo)},providers()).filter(p=>p.smsOriginal&&(!station||p.station===station||pickupCredentials(p).some(c=>c.station===station)));
  if(rows.length===1){smsView(rows[0].id);return;}
  open(`${heading('短信身份码')}<div class="binding-choices">${rows.length?rows.map(p=>`<button class="provider-tile" data-sms="${esc(p.id)}"><span class="detail"><strong data-user-content>${esc(p.title)}</strong><small>${esc(p.station)} · ${esc(p.pickupCode)}</small></span><span>›</span></button>`).join(''):'<p class="hint">暂无待取短信凭证。导入取件短信后会保存原文；历史短信可在已取记录查看。</p>'}</div>`);
}
function render() {
  const records = {...state, parcels:state.parcels.filter(p => !p.isDemo)};
  const pending = filterParcels(records, providers());
  $('#pending-count').textContent = pending.length;
  $('#transit-count').textContent = filterWatching(records).length;
  $('#station-count').textContent = new Set(pending.map(p => p.station)).size;
  const visible = filterParcels(records, providers(), {search:$('#search').value});
  const stations = [...new Set(visible.map(p => p.station))];
  const stationLabel=station=>{const bound=boundStationProvider(state,station,providers());return !bound?'选择身份码':bound.id==='sms'?'短信身份码':bound.name+'身份码';};
  $('#parcel-list').innerHTML = visible.length ? stations.map(station => `<section class="station-group"><div class="station-tools"><h3 class="station-heading" data-user-content>⌖ ${esc(station)}</h3><button class="text-button" data-station="${esc(station)}">${esc(stationLabel(station))}</button></div>${visible.filter(p => p.station === station).map(card).join('')}</section>`).join('') : '<div class="empty"><strong>暂无待取包裹</strong>短信通知可点击“手动导入包裹”<br>已取历史已移至“我的”</div>';
  const collected = filterParcels(records, providers(), {collected:true, search:$('#history-search').value});
  $('#collected-count').textContent = filterParcels(records, providers(), {collected:true}).length;
  $('#collected-list').innerHTML = collected.length ? groupCollected(collected).map(group=>`<section class="history-day"><h3>${esc(group.day)}</h3>${group.stations.map(place=>`<section class="station-group"><h4 data-user-content>${esc(place.station)}</h4>${place.parcels.map(card).join('')}</section>`).join('')}</section>`).join('') : '<div class="empty">暂无已取记录</div>';
  const watching=filterWatching(records).filter(p=>!$('#search').value.trim()||[p.title,p.carrier,p.trackingNumber].join(' ').toLowerCase().includes($('#search').value.trim().toLowerCase()));
  $('#watching-panel').hidden=!watching.length;
  $('#watching-count').textContent=watching.length;
  $('#watching-list').innerHTML=watching.map(p=>`<article class="parcel-card tracking-card"><div class="tracking-head"><div><h3 data-user-content>${esc(p.title)}</h3><div class="tracking-line"><span data-user-content>${esc(p.trackingNumber)}</span><button class="copy-tracking" data-copy-tracking="${esc(p.id)}" aria-label="复制运单号">${copyIcon}</button></div></div><span>待确认</span></div><div class="tracking-actions"><button class="text-button" data-complete-tracking="${esc(p.id)}">补充取件短信</button></div></article>`).join('');
  const all = ordered();
  $('#provider-grid').classList.toggle('sorting', sorting);
  $('#provider-grid').innerHTML = all.map(p=>`<div class="provider-tile" ${sorting?`data-drag="${esc(p.id)}"`:`role="button" tabindex="0" data-entry="${esc(p.id)}" aria-label="打开${esc(p.name)}"`}>
    ${mark(p.id)}<div class="detail"><strong>${esc(p.name)}${p.id==='sms'?'':p.id==='fcbox'?'取件':'身份码'}</strong><small>${p.id==='sms'?'展示本机保存的取件短信':p.identityURL?'App 内官方网页':state.identityBindings?.[p.id]?.confirmed?'已绑定 · 直接打开小程序':'官方小程序 · 首次试开绑定'}</small></div>${sorting?`<button class="sort-handle" data-drag-handle="${esc(p.id)}" aria-label="拖动${esc(p.name)}排序"><svg viewBox="0 0 20 20"><path d="M3 5h14M3 10h14M3 15h14"/></svg></button>`:'<span>›</span>'}</div>`).join('');
  $('#sort-providers').textContent=sorting?'完成':'排序';
}
function open(content) {
  if(!renderingSettings)settingsNavigation.clear();
  modal.classList.remove('sms-dialog','settings-dialog');
  const staging=document.createElement('div');staging.innerHTML=content;
  const header=staging.querySelector('.modal-head,.sms-back'),body=document.createElement('div');body.className='modal-body';
  if(header)header.remove();body.append(...staging.childNodes);
  $('#modal-content').replaceChildren(...(header?[header,body]:[body]));
  if(!modal.open)modal.showModal();body.scrollTop=0;
}
function renderSettingsRoute() {
  const route=settingsNavigation.current;if(!route)return;
  renderingSettings=true;
  try {route.render();} finally {renderingSettings=false;}
  const header=$('#modal .modal-head');
  if(header&&settingsNavigation.depth>1) {
    header.querySelector('.close-modal')?.remove();header.classList.add('settings-navigation-header');
    const back=document.createElement('button');back.className='navigation-back';back.setAttribute('aria-label','返回上一级');back.innerHTML='‹';back.onclick=backSettings;
    const spacer=document.createElement('span');spacer.className='navigation-spacer';spacer.setAttribute('aria-hidden','true');
    header.prepend(back);header.append(spacer);
  }
  $('#modal .modal-body').scrollTop=route.scrollTop;
}
function startSettings() {settingsNavigation.start(settings);renderSettingsRoute();}
function pushSettingsPage(render) {settingsNavigation.push(render,$('#modal .modal-body')?.scrollTop||0);renderSettingsRoute();}
function backSettings() {settingsNavigation.back();renderSettingsRoute();}
function finishModalAction() {if(settingsNavigation.depth>1)backSettings();else modal.close();}
modal.addEventListener('cancel',event=>{if(settingsNavigation.depth>1){event.preventDefault();backSettings();}});
modal.addEventListener('close',()=>settingsNavigation.clear());
const isOffline=()=>!navigator.onLine||(testing&&testServiceState==='offline');
function updateNetworkNotice() {
  $('#network-notice').hidden=!isOffline();$('#network-notice').textContent=SERVICE_MESSAGES.offline;
}
function serviceMessage() {return isOffline()?SERVICE_MESSAGES.offline:testing&&testServiceState==='wechatMissing'?SERVICE_MESSAGES.wechatMissing:testing&&testServiceState==='expiredLink'?SERVICE_MESSAGES.expiredLink:null;}
function openExternal(url) {
  const opened=window.open(url,'_blank');if(opened){opened.opener=null;return true;}return false;
}
function showEntryFailure(message) {
  const error=$('#entry-status');
  if(error) {
    error.hidden=false;error.textContent=message;
    if(!$('#modal .binding-guide')) {const guide=document.createElement('div');guide.innerHTML=bindingGuide();$('#modal .entry-brand')?.after(guide);}
    error.scrollIntoView({block:'start',behavior:'smooth'});
  } else notify(message);
}
function officialLogin() {
  settingsSubpage('淘宝登录与官方清单',`<p class="hint">请在淘宝官方页面完成登录，再返回刷新待取清单。</p><p id="login-error" class="error" role="alert" hidden></p><button class="button primary wide" id="open-official-login">打开淘宝登录</button>`);
  $('#open-official-login').onclick=()=>{const message=isOffline()?SERVICE_MESSAGES.offline:!openExternal(catalog.find(p=>p.id==='taobao').parcelsURL)?'页面未能打开，请允许打开官方页面后重试。':null;if(message){$('#login-error').hidden=false;$('#login-error').textContent=message;}};
}
const heading = title => `<div class="modal-head"><h2>${esc(title)}</h2><button class="close-modal" aria-label="关闭">✕</button></div>`;
async function copy(text) { try { await navigator.clipboard.writeText(text); notify('已复制'); } catch { notify('请手动选中复制'); } }
function bindingGuide() {
  return `<section class="binding-guide"><h3>如何获取小程序链接</h3><p class="form-note">截图以兔喜生活为例，其他平台以实际菜单为准。</p><div class="guide-steps">${[['binding-menu.jpg','1','打开小程序右上角“…” → 添加到桌面'],['binding-safari-url.jpg','2','在 Safari 复制地址栏完整链接']].map(([file,step,label])=>`<button type="button" class="guide-step" data-guide-image="${file}"><span class="guide-step-title"><b>${step}</b><span>${label}</span></span><img src="/preview/assets/${file}" alt="${label}"><small>点击截图可放大</small></button>`).join('')}</div><p class="form-note">复制地址栏链接后返回粘贴，无需继续添加到主屏幕。</p></section>`;
}
function entry(id, manage=false) {
  if(id==='sms'){smsEntry();return;}
  const provider = providers().find(p => p.id === id); if (!provider) return;
  if (state.preferredCredentialID !== id) save({ ...state, preferredCredentialID: id });
  if (provider.identityURL) {
    if (modal.open) modal.close();
    if(isOffline()){open(`${heading('暂时无法打开')}<p class="error">${SERVICE_MESSAGES.offline}</p>`);return;}
    if(!openExternal(provider.identityURL))notify('页面未能打开，请允许打开官方页面后重试。');
    return;
  }
  const binding = state.identityBindings?.[id];
  if (!manage && binding?.confirmed && parseIdentityLink(binding.value,provider.miniProgramName).kind==='launchURL') {
    if(modal.open)modal.close();
    const issue=serviceMessage();if(issue){entry(id,true);showEntryFailure(issue);return;}
    if(!openExternal(binding.value)){entry(id,true);showEntryFailure(SERVICE_MESSAGES.openFailed);}return;
  }
  open(`${heading(`${provider.name}小程序绑定`)}<p id="entry-status" class="error" role="alert" hidden></p><div class="entry-brand">${mark(id)}<strong>${esc(provider.name)}</strong></div><p class="hint">首次试开并确认后，下次点击直接尝试打开对应小程序。不同平台的身份码不能通用。</p>${binding?.confirmed?'':bindingGuide()}<div class="modal-form"><label class="field">小程序口令或官方跳转链接<textarea id="identity-link" spellcheck="false" placeholder="粘贴链接或 #小程序://…">${esc(binding?.value||provider.miniProgramURL||'')}</textarea></label><p class="form-note" id="link-note"></p><p class="error" id="link-error" role="alert" hidden></p><button class="button primary" id="try-link" hidden>试开${esc(provider.name)}</button><button class="button primary" id="confirm-link" hidden>确认已打开，保存绑定</button><button class="button secondary" id="save-share" hidden>保存口令（仍需在微信内打开）</button><button class="button secondary" id="copy-share" hidden>复制口令</button>${binding?'<button class="text-button" id="unbind-link">解除入口绑定</button>':''}</div><p class="form-note">仅粘贴入口链接，不要填写身份码或验证码。链接失效时请重新获取。</p>`);
  let tried='';
  const input=$('#identity-link');
  const update=()=>{
    tried=''; const result=parseIdentityLink(input.value,provider.miniProgramName);
    $('#link-note').textContent=result.message||'';$('#link-error').hidden=!result.error;$('#link-error').textContent=result.error||'';
    $('#try-link').hidden=result.kind!=='launchURL';$('#confirm-link').hidden=true;
    $('#save-share').hidden=result.kind!=='shareCode';$('#copy-share').hidden=result.kind!=='shareCode';
  };
  input.oninput=update;update();
  $('#try-link').onclick=()=>{const result=parseIdentityLink(input.value,provider.miniProgramName);if(result.kind!=='launchURL')return;
    const issue=serviceMessage();if(issue){showEntryFailure(issue);return;}
    if(!openExternal(result.value)){showEntryFailure(SERVICE_MESSAGES.openFailed);return;}
    tried=result.value;$('#confirm-link').hidden=false;$('#entry-status').hidden=true;
    $('#link-note').textContent='已请求打开小程序。若未打开，请确认微信可用；若提示链接失效，请重新获取。打开正确后再确认绑定。';};
  $('#confirm-link').onclick=()=>{if(!tried||tried!==input.value.trim())return;
    save({...state,identityBindings:{...state.identityBindings,[id]:{kind:'launchURL',value:tried,confirmed:true}}});finishModalAction();notify('已保存入口绑定');};
  $('#save-share').onclick=()=>{const result=parseIdentityLink(input.value,provider.miniProgramName);if(result.kind!=='shareCode')return;
    save({...state,identityBindings:{...state.identityBindings,[id]:{kind:'shareCode',value:result.value,confirmed:false}}});notify('已保存口令，仍需在微信内打开');};
  $('#copy-share').onclick=()=>copy(input.value.trim());
  if($('#unbind-link'))$('#unbind-link').onclick=()=>{const identityBindings={...state.identityBindings};delete identityBindings[id];save({...state,identityBindings});if(settingsNavigation.depth)renderSettingsRoute();else entry(id,true);notify('已解除入口绑定');};
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
  const stations=[...new Set([...state.parcels.filter(p=>!p.isDemo&&p.station).map(p=>p.station),...Object.keys(state.stationCredentials||{})])].sort();
  open(`${heading('地点身份码绑定')}<p class="hint">修改或取消各个地点的身份码绑定，设置立即保存。</p><div class="modal-form">${stations.length ? stations.map(station=>`<label class="field binding-field">${esc(station)}<select data-bind-station="${esc(station)}"><option value="">未绑定</option>${ordered().map(p=>`<option value="${esc(p.id)}" ${boundStationProvider(state,station,providers())?.id===p.id?'selected':''}>${esc(p.name)}</option>`).join('')}</select></label>`).join(''):'<p class="hint">添加包裹后，可在这里绑定取件地点。</p>'}</div>`);
  document.querySelectorAll('select[data-bind-station]').forEach(select=>select.onchange=()=>{
    save(bindStationCredential(state,select.dataset.bindStation,select.value,providers()));notify('地点绑定已保存');
  });

}
function parcelForm(initialSMS='', initialTrackingNumber='', initialCarrier='') {
  open(`${heading('手动导入包裹')}<form id="parcel-form" class="modal-form import-form" novalidate><p id="form-error" class="error import-error" role="alert" hidden></p><div class="import-intro"><strong>粘贴短信，自动整理</strong><span>识别取件码 · 记住地点 · 合并重复包裹</span></div><label class="field">粘贴完整取件短信（可选）<textarea id="sms" placeholder="例如：【韵达快递】您的快件已入库，取件码01-02-0003，请及时领取。"></textarea></label><p class="form-note" id="recognition-note">自动识别物流与取件码；地点优先取短信内容，否则沿用同一物流公司的最近记录。短信原文和导入时间仅保存在本机。</p><label class="field" id="candidate-field" hidden>选择本次要添加的取件码<select id="candidate-code"></select></label><label class="field">包裹名称<input name="title" maxlength="60" required></label><label class="field">取件平台<select name="providerID">${providers().filter(p=>p.id!=='sms').map(p=>`<option value="${esc(p.id)}" ${p.id==='manual'?'selected':''}>${esc(p.name)}</option>`).join('')}</select></label><label class="field">取件地点<input name="station" maxlength="100" required></label><label class="field">取件码<input name="pickupCode" maxlength="40" required autocapitalize="off"></label><div class="form-row"><label class="field">物流公司<input name="carrier" maxlength="30"></label><label class="field">完整快递单号<input name="trackingNumber" placeholder="建议补全，尾号不能去重" maxlength="80"></label></div><p class="form-note">完整单号用于跨平台去重；没有完整单号时，只能保守核对原文、地点和取件码。</p><button class="button primary" type="submit">确认添加</button></form>`);
  let smsSender='';
  const form=$('#parcel-form');
  form.elements.title.value=readSMS('',state.parcels).title;form.elements.trackingNumber.value=initialTrackingNumber;form.elements.carrier.value=initialCarrier;
  form.addEventListener('input',event=>{if(event.target.matches('input,select')){$('#form-error').hidden=true;event.target.removeAttribute('aria-invalid');}});
  $('#sms').addEventListener('input',()=>{
    if (!$('#sms').value.trim()) return;
    const parsed=readSMS($('#sms').value,state.parcels);smsSender=parsed.sender;
    for (const field of ['title','station','pickupCode','carrier','trackingNumber','providerID']) form.elements[field].value=parsed[field];
    $('#form-error').hidden=true;form.querySelectorAll('[aria-invalid]').forEach(el=>el.removeAttribute('aria-invalid'));
    if(!parsed.trackingNumber)form.elements.trackingNumber.value=initialTrackingNumber;
    if(!parsed.carrier)form.elements.carrier.value=initialCarrier;
    $('#recognition-note').textContent=parsed.message;
    $('#candidate-field').hidden=parsed.codeCandidates.length<2;
    $('#candidate-code').innerHTML='<option value="">请选择</option>'+parsed.codeCandidates.map(code=>`<option>${esc(code)}</option>`).join('');
  });
  $('#candidate-code').onchange=event=>form.elements.pickupCode.value=event.target.value;
  form.addEventListener('submit',event=>{
    event.preventDefault();
    try {
      const input=Object.fromEntries(new FormData(form)); input.source=$('#sms').value.trim()?'sms':'manual';input.smsOriginal=$('#sms').value;input.smsSender=smsSender;
      const next=addParcel(state,input,providers());save(input.smsOriginal&&input.providerID==='manual'&&!next.stationCredentials?.[input.station]?bindStationCredential(next,input.station,'sms',providers()):next); modal.close(); page('packages');
      if(next.lastImportWasDuplicate){open(`${heading('包裹已存在')}<p class="hint">已合并到原包裹，没有重复添加。原有取件状态保持不变。</p><button class="button primary wide" id="duplicate-ok">知道了</button>`);$('#duplicate-ok').onclick=()=>modal.close();}
      else notify('包裹已加入待取清单');
    } catch(error) { $('#form-error').hidden=false; $('#form-error').textContent=error.message;
      const missing=['title','station','pickupCode'].find(name=>!form.elements[name].value.trim());
      if(missing){form.elements[missing].focus({preventScroll:true});form.elements[missing].setAttribute('aria-invalid','true');}
      $('#form-error').scrollIntoView({block:'start',behavior:'smooth'}); }
  });
  if(initialSMS){$('#sms').value=initialSMS;$('#sms').dispatchEvent(new Event('input',{bubbles:true}));}
}
function duplicateNotice(message='已合并到原包裹，没有重复添加。原有取件状态保持不变。'){
  open(`${heading('包裹已存在')}<p class="hint">${esc(message)}</p><button class="button primary wide" id="duplicate-ok">知道了</button>`);$('#duplicate-ok').onclick=()=>modal.close();
}
function presentClipboardPrompt() {
  const prompt=$('#clipboard-modal');
  if(!clipboardCandidate||modal.open||$('#guide-modal').open)return;
  $('#clipboard-description').textContent='剪贴板中有取件短信';
  $('#clipboard-note').textContent='确认后进入导入页核对，不会自动保存。';
  $('#clipboard-import').textContent='去导入';
  if(!prompt.open)prompt.showModal();
}
modal.addEventListener('close',presentClipboardPrompt);
$('#clipboard-modal').addEventListener('cancel',()=>{clipboardCandidate=null;});
async function checkClipboard(manual=false) {
  if(testing&&!manual)return;
  if(state?.clipboardDetectionEnabled===false&&!manual)return;
  try {
    const text=await navigator.clipboard.readText();if(text===lastClipboardText)return;
    lastClipboardText=text;const recognized=classifyImport(text);clipboardCandidate=recognized?.kind==='sms'?recognized:null;
    if(!clipboardCandidate){$('#clipboard-modal').close();return;}
    presentClipboardPrompt();
  } catch {if(manual)notify('浏览器未授权读取剪贴板，请手动粘贴');}
}

function monitoring(){
  open(`${heading('到站监控')}<div class="monitor-card"><strong>淘宝 · 前台自动检查</strong><p>登录后打开或返回 App 时检查，前台每两分钟检查。新件要先出现在官方清单中。</p></div>${['tuxi','yishoufa','fcbox'].map(id=>`<div class="monitor-card"><strong>${esc(providers().find(p=>p.id===id)?.name)}</strong><p>已核实小程序首页入口；包裹清单尚未接通，不能自动监控到站。</p></div>`).join('')}<p class="hint">短信仅手动粘贴；不读取短信收件箱、不使用快捷指令。本版不承诺锁屏或退出后持续监控。</p>`);
}
const settingsIcons={appearance:'M12 3a9 9 0 1 0 0 18V3zm0 0a9 9 0 0 1 0 18',language:'M3 12h18M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18zm0 0c-4 5-4 13 0 18 4-5 4-13 0-18',notification:'M5 17h14l-2-3V9a5 5 0 0 0-10 0v5zm5 3h4',sync:'M4 9a8 8 0 0 1 14-3l2 3m0-5v5h-5M20 15a8 8 0 0 1-14 3l-2-3m0 5v-5h5',clipboard:'M9 4H5v17h14V4h-4M9 3h6v4H9zM8 12h8M8 16h6',pass:'M4 5h16v14H4zM8 9h2v6H8M14 9v6M17 9v6',link:'M10 14l4-4M8 16l-1 1a4 4 0 0 1-6-6l4-4a4 4 0 0 1 6 0M16 8l1-1a4 4 0 0 1 6 6l-4 4a4 4 0 0 1-6 0',data:'M4 4h16v13H9l-5 4V4zm4 5h8M8 13h6'};
function settingsIcon(name) {return `<span class="settings-icon icon-${name}"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="${settingsIcons[name]||settingsIcons.pass}" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/></svg></span>`;}
function settingsLink(id,title,icon,detail='') {return `<button class="settings-link" id="${id}">${settingsIcon(icon)}<span class="settings-row-title">${title}</span>${detail?`<small>${detail}</small>`:''}<span class="settings-chevron">›</span></button>`;}
function settingsToggle(id,title,icon,enabled) {return `<label class="settings-switch-row">${settingsIcon(icon)}<span class="settings-row-title">${title}</span><span class="ios-switch"><input id="${id}" type="checkbox" role="switch" aria-label="${title}" ${enabled?'checked':''}><span class="switch-track"></span></span></label>`;}
function settings() {
  const preferences=displayPreferences(state),appearance={system:'跟随系统',light:'浅色',dark:'深色'}[preferences.appearance];
  open(`${heading('设置')}<section class="ios-settings-section"><h3>通用</h3><div class="ios-settings-group">${settingsLink('appearance-settings','界面与显示','appearance',appearance)}${settingsLink('language-settings','语言','language',preferences.language==='en'?'English':'简体中文')}</div></section><section class="ios-settings-section"><h3>自动检查</h3><div class="ios-settings-group">${settingsToggle('auto-sync','前台自动刷新','sync',state.autoSyncEnabled!==false)}${settingsToggle('clipboard-detection','剪贴板智能识别','clipboard',state.clipboardDetectionEnabled!==false)}${settingsLink('settings-login','淘宝登录与官方清单','pass')}</div><p class="settings-footer">自动刷新仅支持淘宝，剪贴板导入需确认。</p></section><section class="ios-settings-section"><h3>身份码</h3><div class="ios-settings-group">${settingsLink('manage-station-bindings','地点身份码绑定','pass')}${settingsLink('manage-mini-programs','小程序入口绑定','link')}${settingsLink('show-monitoring','到站监控与接入状态','sync')}</div></section><section class="ios-settings-section"><h3>数据与隐私</h3><div class="ios-settings-group">${settingsLink('local-data-settings','短信与本地记录','data')}</div><p class="settings-footer">记录仅保存在本机，不读取短信收件箱。</p></section><p class="settings-version">涂涂取件 0.7.3</p>`);
  modal.classList.add('settings-dialog');
  $('#auto-sync').onchange=event=>save({...state,autoSyncEnabled:event.target.checked});
  $('#clipboard-detection').onchange=event=>{save({...state,clipboardDetectionEnabled:event.target.checked});if(!event.target.checked){clipboardCandidate=null;$('#clipboard-modal').close();}else{lastClipboardText='';checkClipboard();}};
  $('#appearance-settings').onclick=()=>pushSettingsPage(appearanceSettings);$('#language-settings').onclick=()=>pushSettingsPage(languageSettings);$('#settings-login').onclick=()=>pushSettingsPage(officialLogin);
  $('#show-monitoring').onclick=()=>pushSettingsPage(monitoring);$('#manage-station-bindings').onclick=()=>pushSettingsPage(stationSettings);$('#manage-mini-programs').onclick=()=>pushSettingsPage(miniProgramSettings);
  $('#local-data-settings').onclick=()=>pushSettingsPage(()=>settingsSubpage('短信与本地记录','<div class="settings-detail"><p>短信原文仅保存在本机，删除已取记录时会清除。</p><p>不会自动读取短信收件箱，导入前可核对内容。</p></div>'));
}
function settingsSubpage(title,content) {
  open(`${heading(title)}${content}`);
}
function appearanceSettings() {
  const selected=displayPreferences(state).appearance;
  settingsSubpage('界面与显示',`<div class="settings-group">${[['system','跟随系统'],['light','浅色'],['dark','深色']].map(([value,label])=>`<label class="choice-row"><input type="radio" name="appearance" value="${value}" ${selected===value?'checked':''}><span>${label}</span></label>`).join('')}</div><p class="hint">应用界面与短信凭证会随外观切换。官方身份码网页由平台控制，保留便于扫码的显示方式。</p>`);
  document.querySelectorAll('[name="appearance"]').forEach(input=>input.onchange=()=>save({...state,appearance:input.value}));
}
function languageSettings() {
  const selected=displayPreferences(state).language;
  settingsSubpage('语言',`<div class="settings-group">${[['zh-Hans','简体中文'],['en','English']].map(([value,label])=>`<label class="choice-row"><input type="radio" name="language" value="${value}" ${selected===value?'checked':''}><span data-user-content>${label}</span></label>`).join('')}</div><p class="hint">语言设置只改变应用界面，包裹名称、地点、短信原文及官方页面保持原样。</p>`);
  document.querySelectorAll('[name="language"]').forEach(input=>input.onchange=()=>save({...state,language:input.value}));
}
async function refresh() {
  updateNetworkNotice();
  const loginRequired=testing&&testServiceState==='login';
  $('#login-retry').hidden=!loginRequired;
  if(isOffline()){$('#sync-status').textContent=SERVICE_MESSAGES.offline;return;}
  if(loginRequired){$('#sync-status').textContent=SERVICE_MESSAGES.login;return;}
  if(testing){$('#sync-status').textContent='测试模式 · 不访问真实包裹快照';return;}
  try {
    const response=await fetch('/api/official-snapshot',{cache:'no-store'});
    if(!response.ok)throw new Error('snapshot-unavailable');
    const snapshot=await response.json(),issue=statusForSnapshot(snapshot);
    if(issue){$('#sync-status').textContent=issue;$('#login-retry').hidden=snapshot.state!=='login_required';return;}
    if(snapshot.readAt!==state.lastOfficialReadAt)save(mergeOfficialSnapshot(state,snapshot));
    $('#sync-status').textContent=`本机快照 ${new Date(snapshot.readAt).toLocaleString('zh-CN')} · 非网页实时同步`;
  } catch {$('#sync-status').textContent=isOffline()?SERVICE_MESSAGES.offline:'尚未取得可用的官方清单，已保留本地包裹。请登录后刷新。';}
}
window.addEventListener('offline',refresh);window.addEventListener('online',refresh);
$('#login-retry').onclick=officialLogin;
document.addEventListener('click',event=>{
  const control=event.target.closest('button,[data-entry]');if(!control)return;
  if(control.dataset.page)page(control.dataset.page);
  if(control.dataset.entry&&Date.now()>suppressEntryUntil)entry(control.dataset.entry);
  if(control.dataset.manageLink){const id=control.dataset.manageLink;if(settingsNavigation.depth)pushSettingsPage(()=>entry(id,true));else entry(id,true);}
  if(control.dataset.station)stationEntry(control.dataset.station);
  if(control.dataset.bindProvider){save(bindStationCredential(state,control.dataset.bindStation,control.dataset.bindProvider,providers()));if(control.dataset.bindProvider==='sms')smsEntry(control.dataset.bindStation);else entry(control.dataset.bindProvider);}
  if(control.dataset.completeTracking){const p=state.parcels.find(p=>p.id===control.dataset.completeTracking);if(p)parcelForm('',p.trackingNumber,p.carrier);}
  if(control.dataset.copyTracking){const p=state.parcels.find(p=>p.id===control.dataset.copyTracking);if(p){lastClipboardText=p.trackingNumber;copy(p.trackingNumber);}}
  if(control.dataset.sms)smsView(control.dataset.sms);
  if(['binding-menu.jpg','binding-safari-url.jpg'].includes(control.dataset.guideImage)){$('#guide-full-image').src='/preview/assets/'+control.dataset.guideImage;$('#guide-modal').showModal();}
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
$('#clipboard-import').onclick=()=>{if(!clipboardCandidate)return;const candidate=clipboardCandidate;clipboardCandidate=null;$('#clipboard-modal').close();page('packages');if(candidate.kind==='sms')parcelForm(candidate.text);};
$('#clipboard-dismiss').onclick=()=>{clipboardCandidate=null;$('#clipboard-modal').close();};
$('#close-guide').onclick=()=>$('#guide-modal').close();
$('#sort-providers').onclick=()=>{finishDrag(false);sorting=!sorting;render();};$('#search').oninput=render;$('#history-search').oninput=render;
$('#show-collected').onclick=()=>{$('#history-panel').hidden=!$('#history-panel').hidden;};$('#show-settings').onclick=startSettings;
$('#refresh-snapshot').onclick=refresh;
$('.brand').onclick=event=>{event.preventDefault();page('packages');};
try {
  const [catalogResponse,assetResponse,readerResponse,linkResponse,importResponse]=await Promise.all(['/shared/catalog.json','/shared/brand-assets.json','/shared/sms-reader.js','/shared/identity-link.js','/shared/import-reader.js'].map(url=>fetch(url)));
  if (![catalogResponse,assetResponse,readerResponse,linkResponse,importResponse].every(r=>r.ok))throw new Error('本地资源加载失败，请重启预览服务');
  catalog=await catalogResponse.json();assets=(await assetResponse.json()).brands;
  classifyImport=Function('return '+await importResponse.text())();
  parseIdentityLink=Function('return '+await linkResponse.text())();
  readSMS=Function('return '+await readerResponse.text())();
  const stored=localStorage.getItem(key);
  state=stored?validateSavedState(JSON.parse(stored),catalog):{version:1,customProviders:[],parcels:[]};
  if(testing){
    $('#preview-notice').innerHTML='<span>本地测试模式 · 独立虚构记录</span> <span><button class="text-button" id="test-clipboard">检测剪贴板</button><button class="text-button" id="test-theme">切换外观</button><select id="test-service-state" aria-label="异常场景"><option value="normal">正常</option><option value="offline">断网</option><option value="login">淘宝登录失效</option><option value="wechatMissing">未安装微信</option><option value="expiredLink">链接失效</option></select></span>';
    $('#test-clipboard').onclick=()=>checkClipboard(true);$('#test-service-state').onchange=event=>{testServiceState=event.target.value;refresh();};
    const button=$('#test-theme');
    button.textContent=matchMedia('(prefers-color-scheme: dark)').matches?'浅色预览':'深色预览';
    button.onclick=()=>{
      const html=document.documentElement;
      const dark=html.classList.contains('theme-dark')||(!html.classList.contains('theme-light')&&matchMedia('(prefers-color-scheme: dark)').matches);
      save({...state,appearance:dark?'light':'dark'});
      button.textContent=dark?'深色预览':'浅色预览';
    };
  }
  applyDisplayPreferences();page(location.hash.slice(1));render();await refresh();await checkClipboard();
  setInterval(()=>{if(!document.hidden&&state.autoSyncEnabled!==false)refresh();},120000);
  document.addEventListener('visibilitychange',()=>{if(!document.hidden){if(state.autoSyncEnabled!==false)refresh();checkClipboard();}});window.addEventListener('focus',()=>checkClipboard());
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
