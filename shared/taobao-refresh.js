// 仅在淘宝待取网页中沿用官方刷新参数，并确认本轮清单查询已完成。
// 不发起额外接口调用，不保存请求参数、响应内容、账号或 Cookie。
(() => {
  if (location.hostname !== 'pages-fast.m.taobao.com'
      || location.pathname !== '/wow/z/uniapp/1100333/last-mile-fe/m-end-school-tab/home'
      || window.__tutuTaobaoFreshness) return;
  const listAPI = 'mtop.cainiao.pickup.plus.querymultistapackages4xy';
  const legacyAPI = 'mtop.cainiao.pickup.xiaoyuan.querymultisitepkgs';
  const pending = new Set();
  const installed = new WeakSet();
  let serial = 0, outcome = 'waiting', completedAt = 0;
  const read = () => ({
    state: pending.size || (outcome === 'ready' && Date.now() - completedAt < 500) ? 'loading' : outcome,
    serial, completedAt
  });
  function verify(snapshot) {
    if (snapshot.state === 'login_required' || snapshot.state === 'error') return snapshot;
    const query = read();
    if (query.state === 'ready') return snapshot;
    const state = query.state === 'login_required' ? 'login_required' : query.state === 'error' ? 'error' : 'loading';
    return {state, message: state === 'login_required' ? '请重新登录淘宝'
      : state === 'error' ? '同步失败，记录已保留' : '正在确认最新清单…',
      parcels: [], expectedCount: null, readAt: snapshot.readAt};
  }
  Object.defineProperty(window, '__tutuTaobaoFreshness', {value: Object.freeze({read, verify})});
  function install() {
    const mtop = window.lib?.mtop;
    if (!mtop || typeof mtop.request !== 'function' || installed.has(mtop)) return;
    const original = mtop.request;
    mtop.request = function(params, success, failure) {
      const api = String(params?.api || '').toLowerCase();
      if (api !== listAPI && api !== legacyAPI) return original.apply(this, arguments);
      let options = params;
      // 此字段来自官方页面自身的刷新路径，在 MTOP 生成签名之前添加。
      if (api === listAPI) {
        try {
          const data = typeof params.data === 'string' ? JSON.parse(params.data) : params.data;
          if (!data || typeof data !== 'object' || Array.isArray(data)) return original.apply(this, arguments);
          options = {...params, data: {...data, refresh: true}};
        } catch { return original.apply(this, arguments); }
      }
      const id = ++serial;
      pending.add(id);outcome = 'loading';
      let settled = false;
      function finish(response) {
        if (settled) return;
        settled = true;pending.delete(id);
        if (id !== serial) return;
        const codes = Array.isArray(response?.ret) ? response.ret.map(String) : [];
        outcome = codes.some(code => /^SUCCESS(?:::|$)/.test(code)) ? 'ready'
          : codes.some(code => /SESSION_EXPIRED|TOKEN_EXPIRED|TOKEN_EXOIRED|NEED_LOGIN/.test(code)) ? 'login_required' : 'error';
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
