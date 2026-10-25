import { STORAGE_KEY, addParcel, addProvider, toggleCollected, filterParcels, validateSavedState, mergeOfficialSnapshot } from './model.mjs';

const paths = {
  box: '<path d="m3 7 9-4 9 4-9 5zM3 7v10l9 5 9-5V7M12 12v10M7 5l9 5"/>',
  scan: '<path d="M8 3H3v5m13-5h5v5M3 16v5h5m13-5v5h-5M7 8v8m3-8v8m4-8v8m3-8v8"/>',
  settings: '<path d="M4 7h5m5 0h6M4 17h9m5 0h2"/><circle cx="11" cy="7" r="2"/><circle cx="15" cy="17" r="2"/>',
  plus: '<path d="M12 5v14M5 12h14"/>',
  search: '<circle cx="10.5" cy="10.5" r="6.5"/><path d="m16 16 5 5"/>',
  pin: '<path d="M19 10c0 5-7 11-7 11S5 15 5 10a7 7 0 0 1 14 0Z"/><circle cx="12" cy="10" r="2"/>',
  check: '<circle cx="12" cy="12" r="9"/><path d="m8 12 3 3 5-6"/>',
  undo: '<path d="M8 7H4V3m0 4a9 9 0 1 1-1 8"/>',
  copy: '<rect x="8" y="8" width="12" height="13" rx="2"/><path d="M16 8V3H3v13h5"/>',
  arrow: '<path d="M5 19 19 5M7 5h12v12"/>',
  chevron: '<path d="m9 5 7 7-7 7"/>',
  info: '<circle cx="12" cy="12" r="9"/><path d="M12 11v6m0-10h.01"/>',
  leaf: '<path d="M20 3c-9-1-16 4-15 11s11 8 14 0c1-3 1-7 1-11ZM5 20 15 9M9 15l-1-5m4 2 5 1"/>',
  shield: '<path d="m12 2 8 4v6c0 5-8 10-8 10S4 17 4 12V6zM8 11l3 3 5-6"/>',
  close: '<path d="m6 6 12 12M18 6 6 18"/>'
};
const icon = name => `<svg class="icon" viewBox="0 0 24 24" aria-hidden="true">${paths[name] || paths.box}</svg>`;
const esc = value => String(value).replace(/[&<>"']/g, char => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[char]));
const $ = selector => document.querySelector(selector);
const modal = $('#modal');
let state, catalog = [], readonly = false;
let filters = { collected: false, providerID: 'all', search: '' };
let toastTimer;
const providers = () => [...catalog, ...state.customProviders];
const mark = p => `<span class="provider-mark" style="--provider-color:${esc(p.color)}">${esc(p.shortName)}</span>`;

function notify(message) {
  $('#toast').textContent = message;
  $('#toast').hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { $('#toast').hidden = true; }, 2500);
}

function save(next) {
  if (readonly) throw new Error('本地数据异常，暂时无法保存，请保留现有数据并反馈问题');
  // 写入成功后才更新页面内存，避免保存失败却显示为成功。
  localStorage.setItem(STORAGE_KEY, JSON.stringify(next));
  state = next;
  render();
}

async function copy(text) {
  try { await navigator.clipboard.writeText(text); notify('已复制'); }
  catch { notify('复制受浏览器限制，请手动选中复制'); }
}

function switchPage(page) {
  document.querySelectorAll('.page').forEach(el => { el.hidden = el.id !== `page-${page}`; });
  document.querySelectorAll('[data-page]').forEach(el => el.classList.toggle('active', el.dataset.page === page));
  history.replaceState(null, '', `#${page}`);
  window.scrollTo({ top: 0 });
}

function render() {
  const list = providers();
  // 旧版演示记录仍保留在存储中，但不再混入实际使用页面。
  const records = state.parcels.filter(p => !p.isDemo && (p.collectedAt || p.inLatestOfficialSnapshot !== false));
  const pending = records.filter(p => !p.collectedAt);
  $('#pending-count').textContent = pending.length;
  $('#station-count').textContent = new Set(pending.map(p => p.station)).size;
  $('#nav-count').textContent = pending.length;
  $('#pending-tab-count').textContent = pending.length;
  $('#collected-tab-count').textContent = records.length - pending.length;
  $('#pending-tab').classList.toggle('selected', !filters.collected);
  $('#collected-tab').classList.toggle('selected', filters.collected);
  $('#provider-filters').innerHTML = [{ id: 'all', name: '全部' }, ...list.filter(p => records.some(x => x.providerID === p.id))]
    .map(p => `<button data-filter="${esc(p.id)}" class="${filters.providerID === p.id ? 'active' : ''}" aria-pressed="${filters.providerID === p.id}">${esc(p.name)}</button>`).join('');
  const visible = filterParcels({ ...state, parcels: records }, list, filters);
  const stations = [...new Set(visible.map(p => p.station))];
  $('#parcel-list').innerHTML = visible.length ? stations.map(station => {
    const parcels = visible.filter(p => p.station === station);
    return `<section class="station-group"><h2 class="station-heading">${icon('pin')}${esc(station)}<span>${parcels.length} 件</span></h2>${parcels.map(p => {
      const provider = list.find(s => s.id === p.providerID);
      return `<article class="parcel-card"><div class="parcel-top">${mark(provider)}<div class="parcel-info"><h3>${esc(p.title)}</h3><p>${esc(p.carrier || '快递')} · 来源${esc(provider.name)}<span class="record-tag">${['cainiao-web', 'taobao-web'].includes(p.source) ? '官方页面读取' : '手动添加'}</span></p></div><button class="collect-button" data-collect="${esc(p.id)}" aria-label="${p.collectedAt ? '恢复待取' : '标记已取'}：${esc(p.title)}" title="${p.collectedAt ? '恢复待取' : '标记已取'}">${icon(p.collectedAt ? 'undo' : 'check')}</button></div><div class="code-row"><strong>${esc(p.pickupCode)}</strong><button class="copy-button" data-copy="${esc(p.id)}">${icon('copy')}复制</button></div><div class="parcel-bottom"><button class="entry-link" data-entry="${esc(provider.id)}">${icon('scan')}官方取件入口</button><span>${['cainiao-web', 'taobao-web'].includes(p.source) ? '本次验证快照 · 非后台实时同步' : '状态需手动更新'}</span></div></article>`;
    }).join('')}</section>`;
  }).join('') : `<div class="empty">${icon('box')}<h3>${filters.search ? '没有找到匹配的本地记录' : filters.collected ? '还没有本地已取记录' : '官方待取件尚未读取'}</h3><p>${filters.search ? '试试其他关键词，或切换平台筛选。' : '这不代表你没有包裹。请先使用上方的官方待取件入口。'}</p></div>`;
  $('#quick-providers').innerHTML = catalog.filter(p => p.featured).map(p => `<button class="quick-provider" data-entry="${esc(p.id)}">${mark(p)}<span><strong>${esc(p.name)}</strong><small>${p.identityURL ? '打开官方身份码 · 需登录' : '尚未打通 · 手动指引'}</small></span>${icon('chevron')}</button>`).join('');
  $('#provider-grid').innerHTML = list.map(p => `<button class="provider-tile" data-entry="${esc(p.id)}">${mark(p)}<h2>${esc(p.name)}</h2><p>${esc(p.kind)} · ${p.identityURL ? '官方网页入口' : '尚未连接'}</p><span class="tile-foot">${p.identityURL ? '打开官方身份码' : '查看打开指引'} ${icon('arrow')}</span></button>`).join('');
}

function openModal(content) {
  $('#modal-content').innerHTML = content;
  modal.showModal();
}
const modalHeading = title => `<div class="modal-head"><h2 id="modal-title">${title}</h2><button class="close-modal" aria-label="关闭">${icon('close')}</button></div>`;

function entry(id) {
  const provider = providers().find(p => p.id === id);
  if (!provider) return;
  if (provider.id === 'taobao' && provider.identityURL) {
    openModal(`${modalHeading('淘宝取件')}<div class="entry-provider">${mark(provider)}<div><strong>官方身份码入口</strong><p>已验证：本人登录后显示身份码和真实待取件</p></div></div><p class="entry-warning">使用淘宝官方页面生成和刷新身份码，不在本地复制、缓存或重画条形码。不同浏览器需要分别登录；身份码是否可出库，以驿站要求为准。</p><div class="entry-actions"><a class="button primary official-action" href="${esc(provider.identityURL)}" target="_blank" rel="noopener noreferrer">打开官方身份码 ↗</a><a class="button secondary official-action" href="${esc(provider.parcelsURL)}" target="_blank" rel="noopener noreferrer">打开官方待取件 ↗</a></div><p class="form-note" style="margin-top:16px">当前浏览器清单使用本次验证读取的快照。iPhone 版可在官方页面内读取；网页预览仍使用本机快照。</p>`);
    return;
  }
  openModal(`${modalHeading('取件入口')}<div class="entry-provider">${mark(provider)}<div><strong>${esc(provider.name)}</strong><p>身份码及小程序自动跳转尚未接通</p></div></div><ol class="entry-steps"><li>打开微信，搜索「${esc(provider.miniProgramName)}」。</li><li>核对运营主体后，进入官方服务并登录。</li><li>查看其提供的取件码、身份码或开柜入口。</li></ol><p class="entry-warning">这里保存的是微信搜索词，尚未核验具体小程序标识及身份码页面。官网只作备用信息入口，不保证支持网页取件。</p><div class="entry-actions"><button class="button primary" id="copy-provider">${icon('copy')}复制微信搜索词</button>${provider.website ? `<a href="${esc(provider.website)}" target="_blank" rel="noopener noreferrer">查看平台官网 ↗</a>` : ''}</div>`);
  $('#copy-provider').addEventListener('click', () => copy(provider.miniProgramName));
}

function parcelForm() {
  openModal(`${modalHeading('添加包裹')}<p class="modal-subtitle">先手动记下来，取件时少翻几个页面。</p><form id="parcel-form" class="modal-form"><label class="field">包裹名称<input name="title" placeholder="例如：新买的书" maxlength="60" required></label><label class="field">取件平台<select name="providerID">${providers().map(p => `<option value="${esc(p.id)}">${esc(p.name)}</option>`).join('')}</select></label><label class="field">取件地点<input name="station" placeholder="例如：小区东门丰巢柜" maxlength="100" required></label><label class="field">取件码<input name="pickupCode" placeholder="保留字母、分隔符与前导零" maxlength="40" required autocapitalize="off"></label><div class="form-row"><label class="field">快递公司（选填）<input name="carrier" maxlength="30" placeholder="例如：顺丰"></label><label class="field">运单号（选填）<input name="trackingNumber" maxlength="80" placeholder="输入完整运单号" autocapitalize="off"></label></div><p class="form-note">仅保存到本机，不会连接平台或自动更新取件状态。</p><p id="form-error" class="form-error" role="alert" hidden></p><button class="button primary" type="submit">保存包裹</button></form>`);
  $('#parcel-form').addEventListener('submit', event => {
    event.preventDefault();
    try {
      const input = Object.fromEntries(new FormData(event.currentTarget));
      save(addParcel(state, input, providers()));
      filters = { collected: false, providerID: 'all', search: '' };
      $('#search').value = '';
      render();
      modal.close();
      switchPage('packages');
      notify('包裹已保存到本机');
    } catch (error) { $('#form-error').textContent = error.message; $('#form-error').hidden = false; }
  });
}

function providerForm() {
  openModal(`${modalHeading('添加取件平台')}<p class="modal-subtitle">先留一个入口，之后再接入更多能力。</p><form id="provider-form" class="modal-form"><label class="field">平台名称<input name="name" placeholder="例如：附近的快递驿站" maxlength="20" required></label><label class="field">微信搜索词<input name="miniProgramName" placeholder="填写对应的服务名称" maxlength="40" required></label><p class="form-note">添加后可保存手动取件记录、查看打开指引。不会自动获取包裹或生成身份码。</p><p id="form-error" class="form-error" role="alert" hidden></p><button class="button primary" type="submit">保存平台</button></form>`);
  $('#provider-form').addEventListener('submit', event => {
    event.preventDefault();
    try { save(addProvider(state, Object.fromEntries(new FormData(event.currentTarget)), providers())); modal.close(); notify('取件平台已添加'); }
    catch (error) { $('#form-error').textContent = error.message; $('#form-error').hidden = false; }
  });
}

document.querySelectorAll('[data-icon]').forEach(el => { el.innerHTML = icon(el.dataset.icon); });
document.addEventListener('click', event => {
  const button = event.target.closest('button');
  if (!button) return;
  if (button.dataset.page) switchPage(button.dataset.page);
  if (button.dataset.entry) entry(button.dataset.entry);
  if (button.dataset.filter) { filters.providerID = button.dataset.filter; render(); }
  if (button.dataset.copy) { const p = state.parcels.find(p => p.id === button.dataset.copy); if (p) copy(p.pickupCode); }
  if (button.dataset.collect) {
    try { const p = state.parcels.find(p => p.id === button.dataset.collect); save(toggleCollected(state, p.id)); notify(p.collectedAt ? '已恢复为待取' : '已标记为已取，可在已取记录中恢复'); }
    catch (error) { notify(error.message); }
  }
  if (button.classList.contains('close-modal')) modal.close();
});
$('#add-parcel').addEventListener('click', parcelForm);
$('#add-provider').addEventListener('click', providerForm);
$('#all-providers').addEventListener('click', () => switchPage('providers'));
$('.brand').addEventListener('click', event => { event.preventDefault(); switchPage('packages'); });
$('#pending-tab').addEventListener('click', () => { filters.collected = false; render(); });
$('#collected-tab').addEventListener('click', () => { filters.collected = true; render(); });
$('#search').addEventListener('input', event => { filters.search = event.target.value; render(); });
modal.addEventListener('click', event => {
  const bounds = modal.getBoundingClientRect();
  if (event.target === modal && (event.clientX < bounds.left || event.clientX > bounds.right || event.clientY < bounds.top || event.clientY > bounds.bottom)) modal.close();
});

try {
  const response = await fetch('/shared/catalog.json');
  if (!response.ok) throw new Error('平台配置加载失败');
  catalog = await response.json();
  const raw = localStorage.getItem(STORAGE_KEY);
  if (raw === null) {
    state = { version: 1, customProviders: [], parcels: [] };
    localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
  } else {
    try { state = validateSavedState(JSON.parse(raw), catalog); }
    catch {
      readonly = true;
      state = { version: 1, customProviders: [], parcels: [] };
      $('#warning').textContent = '原有本地数据读取失败。当前为只读状态，未覆盖原记录；请保留数据并反馈问题。';
      $('#warning').hidden = false;
    }
  }
  render();
  try {
    const snapshotResponse = await fetch('/api/official-snapshot', { cache: 'no-store' });
    if (snapshotResponse.ok) {
      const snapshot = await snapshotResponse.json();
      if (snapshot.readAt !== state.lastOfficialReadAt) save(mergeOfficialSnapshot(state, snapshot));
      $('#official-read-status').textContent = `已从官方页面读取 ${snapshot.parcels.length} 件 · ${new Date(snapshot.readAt).toLocaleString('zh-CN')}。本次验证快照，非持续后台同步。`;
    }
  } catch {
    $('#official-read-status').textContent = '本次验证快照未加载，保留原记录；请通过官方页面核对最新状态。';
  }
  const page = location.hash.slice(1);
  switchPage(['packages', 'providers', 'settings'].includes(page) ? page : 'packages');
} catch (error) {
  readonly = true;
  $('#warning').textContent = `无法启动预览：${error.message}。请使用项目的「打开预览.cmd」，并允许本地存储。`;
  $('#warning').hidden = false;
  document.querySelectorAll('button').forEach(button => { button.disabled = true; });
}
