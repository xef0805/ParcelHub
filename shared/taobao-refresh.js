// 仅在淘宝待取网页中沿用官方刷新参数，并确认本轮清单查询已完成。
// 不发起额外接口调用；仅移除本页官方首屏快照，不改登录信息。
(() => {
  if (location.hostname !== 'pages-fast.m.taobao.com'
      || location.pathname !== '/wow/z/uniapp/1100333/last-mile-fe/m-end-school-tab/home'
      || window.__tutuTaobaoFreshness) return;
  const listAPI = 'mtop.cainiao.pickup.plus.querymultistapackages4xy';
  const pending = new Set();
  const installed = new WeakSet();
  let serial = 0, outcome = 'waiting', completedAt = 0;
  let manifest = null;
  let removedSnapshot = false;
  function discardPageSnapshot() {
    // 官方 FCC 把旧 DOM 盖在实时页面上，原本依赖 jstracker.fsp 才移除。
    const snapshot = document.getElementById?.('fcc-snapshot-placeholder');
    if (snapshot) { snapshot.remove(); removedSnapshot = true; }
    try {
      // 当前官方首页 Gft 未传 version，缓存键为 fcc-cache-- + pathname。
      window.localStorage?.removeItem('fcc-cache--' + location.pathname);
    } catch { /* 存储不可用不影响官方请求或清单读取。 */ }
  }
  function pageText() {
    discardPageSnapshot();
    const livePage = document.getElementById?.('ice-container');
    // 即使实时主体尚为空，也不回退读取主体外的旧快照。
    return (livePage || document.body)?.innerText || '';
  }
  discardPageSnapshot();
  document.addEventListener('DOMContentLoaded', discardPageSnapshot);
  const tabs = ['PENDING_PICKUP', 'TRACKING', 'SIGNED', 'RETURNED'];
  const read = () => ({
    state: pending.size || (outcome === 'ready' && Date.now() - completedAt < 500) ? 'loading' : outcome,
    serial, completedAt, manifest, removedSnapshot
  });
  function verify(snapshot) {
    if (snapshot.state === 'login_required') return snapshot;
    discardPageSnapshot();
    const query = read();
    const count = query.manifest?.pendingCount;
    const countMismatch = Number.isInteger(count)
      && ((snapshot.state === 'ready' && snapshot.expectedCount !== count)
        || (snapshot.state === 'filtered_empty' && count > 0));
    const knownManifest = query.manifest?.fullList === true && (query.manifest.schema === 'components'
      ? query.manifest.activeTab === 'PENDING_PICKUP'
      : query.manifest.schema === 'legacy' && Number.isInteger(query.manifest.legacyPackageCount));
    // 当次接口明确返回零件且待取分组为空，旧 DOM 不应阻止空清单确认。
    // 保留原生两次独立读取确认，接口失败、缺组或组数矛盾不能走此分支。
    const pageAllowsEmpty = snapshot.state !== 'error' || snapshot.retryable === true;
    if (query.state === 'ready' && knownManifest && query.manifest.responseEmpty && pageAllowsEmpty) {
      return {state: 'filtered_empty', message: '正在确认空清单，记录暂时保留',
        parcels: [], expectedCount: null, readAt: snapshot.readAt};
    }
    // 成功状态只代表 MTOP 传输成功；未知业务响应不能为旧 DOM 或空页背书。
    const confirmedEmpty = count === 0 || query.manifest?.legacyEmpty === true;
    if (query.state === 'ready' && knownManifest && !snapshot.retryable && !countMismatch
        && (snapshot.state !== 'filtered_empty' || confirmedEmpty)) return snapshot;
    const state = query.state === 'login_required' ? 'login_required'
      : ['error', 'other_tab'].includes(query.state)
        || (query.state === 'ready' && !knownManifest) ? 'error' : 'loading';
    return {state, message: state === 'login_required' ? '请重新登录淘宝'
      : query.state === 'other_tab' ? '请切回淘宝待取件'
      : state === 'error' ? '同步失败，记录已保留' : '正在确认最新清单…',
      parcels: [], expectedCount: null, readAt: snapshot.readAt};
  }
  Object.defineProperty(window, '__tutuTaobaoFreshness', {value: Object.freeze({read, verify, pageText})});
  function install() {
    const mtop = window.lib?.mtop;
    if (!mtop || typeof mtop.request !== 'function' || installed.has(mtop)) return;
    const original = mtop.request;
    mtop.request = function(params, success, failure) {
      const api = String(params?.api || '').toLowerCase();
      if (api !== listAPI) return original.apply(this, arguments);
      let options;
      // 此字段来自官方页面自身的刷新路径，在 MTOP 生成签名之前添加。
      try {
        const data = typeof params.data === 'string' ? JSON.parse(params.data) : params.data;
        if (!data || typeof data !== 'object' || Array.isArray(data)) return original.apply(this, arguments);
        options = {...params, data: {...data, refresh: true,
          activeTab: data.activeTab || 'PENDING_PICKUP'}};
      } catch { return original.apply(this, arguments); }
      // 官方 MTOP 会将 options.data 原地转成 JSON 字符串，先保留标签值。
      const requestedTab = options.data.activeTab;
      // POINT_0 是官方全站默认值；指定站点、柜组或时间范围均不算完整清单。
      const fullList = (!options.data.stationCode || options.data.stationCode === 'POINT_0')
        && !options.data.cbntGrpId && !options.data.checkTime && !options.data.createTime;
      const id = ++serial;
      pending.add(id);outcome = 'loading';manifest = null;
      let settled = false;
      function finish(response) {
        if (settled) return;
        settled = true;pending.delete(id);
        if (id !== serial) return;
        const codes = Array.isArray(response?.ret) ? response.ret.map(String) : [];
        // MTOP 会自行尝试更新请求 token；最终仍失败也不等于账号已退出。
        // 普通错误保留记录并允许下轮同步，只有官方会话失效才要求用户登录。
        outcome = codes.some(code => /^SUCCESS(?:::|$)/.test(code)) ? 'ready'
          : codes.some(code => /SESSION_EXPIRED|SID_INVALID|AUTH_REJECT|NEED_LOGIN/.test(code)) ? 'login_required' : 'error';
        if (outcome === 'ready') {
          // 与官方 main.js 的请求适配器一致：onReceiveData 取 data.result || data.data。
          // 仅保留旧版直接业务对象兼容，不递归猜测任意字段或解析任意字符串。
          const outer = response?.data;
          const envelope = outer?.result ? 'result' : outer?.data ? 'data' : 'direct';
          const body = outer?.result || outer?.data || outer;
          const components = body?.componentList;
          const tabInfo = Array.isArray(components) ? components.find(part => part?.componentCode === 'tabInfo')?.data : null;
          const active = Array.isArray(tabInfo) ? tabInfo.find(tab => tab?.active === true)?.tabKey : null;
          const count = Array.isArray(tabInfo) ? tabInfo.find(tab => tab?.tabKey === 'PENDING_PICKUP')?.count : null;
          const pendingGroups = Array.isArray(components)
            ? components.find(part => part?.componentCode === 'stationPkgGroup')?.data?.stationGroupList : null;
          const groups = body?.staPkgAssembles;
          const legacyCount = Array.isArray(groups) && groups.every(group => Array.isArray(group?.certainPkgList))
            ? groups.reduce((count, group) => count + group.certainPkgList.length, 0) : null;
          manifest = {schema: Array.isArray(components) ? 'components'
            : Array.isArray(groups) ? 'legacy' : 'unknown', envelope,
            businessSuccess: typeof body?.success === 'boolean' ? body.success : null,
            componentCount: Array.isArray(components) ? components.length : null,
            pendingGroupCount: Array.isArray(pendingGroups) ? pendingGroups.length : null,
            responseEmpty: count === 0 && active === 'PENDING_PICKUP'
              && Array.isArray(pendingGroups) && pendingGroups.length === 0 && !(legacyCount > 0),
            stationGroupPresent: Array.isArray(components) && components.some(part => part?.componentCode === 'stationPkgGroup'),
            emptyComponentPresent: Array.isArray(components) && components.some(part => part?.componentCode === 'noPackage'),
            legacyGroupCount: Array.isArray(groups) ? groups.length : null,
            legacyPackageCount: legacyCount,
            legacyEmpty: Array.isArray(groups) && groups.length === 0 && !!body?.noPkgInfoResp,
            fullList, requestedTab: tabs.includes(requestedTab) ? requestedTab : null,
            activeTab: tabs.includes(active) ? active : null,
            pendingCount: Number.isInteger(count) && count >= 0 && count <= 10000 ? count
              : !Array.isArray(components) && Number.isInteger(legacyCount) && legacyCount <= 10000 ? legacyCount : null};
          if (body?.success === false) outcome = 'error';
          else if ((active && active !== 'PENDING_PICKUP') || requestedTab !== 'PENDING_PICKUP') outcome = 'other_tab';
        }
        discardPageSnapshot();
        completedAt = Date.now();
      }
      const callback = fn => typeof fn === 'function' ? function(response) {
        finish(response);return fn.apply(this, arguments);
      } : fn;
      try {
        const result = original.call(this, options, callback(success), callback(failure));
        if (result && typeof result.then === 'function') result.then(finish, finish);
        return result;
      } catch (error) { finish(null);throw error; }
    };
    installed.add(mtop);
  }
  // 外部库的 load 事件先于业务脚本执行；轮询兼容动态加载的 MTOP。
  document.addEventListener('load', install, true);
  document.addEventListener('DOMContentLoaded', install);
  const timer = setInterval(install, 25);
  setTimeout(() => clearInterval(timer), 30000);
  install();
})();
