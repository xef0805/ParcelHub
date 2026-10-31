export const SERVICE_MESSAGES = {
  offline: '网络未连接，记录已保留',
  timeout: '连接超时，记录已保留',
  login: '请重新登录淘宝，记录已保留',
  wechatMissing: '未检测到微信，请先安装或打开',
  openFailed: '微信未打开，请重试',
  expiredLink: '请重新获取链接，原绑定已保留',
  unavailable: '暂时无法连接，记录已保留',
  incomplete: '清单未读完整，记录已保留',
  phoneFilter: '正在确认空清单，记录暂时保留'
};
export function statusForSnapshot(snapshot) {
  if (snapshot?.state === 'ready') return null;
  return snapshot?.state === 'login_required' ? SERVICE_MESSAGES.login
    : snapshot?.state === 'filtered_empty' ? SERVICE_MESSAGES.phoneFilter
    : snapshot?.state === 'loading' ? SERVICE_MESSAGES.incomplete : SERVICE_MESSAGES.unavailable;
}

export class OfficialEmptyConfirmation {
  #previousEmptyAt = null;
  reset() { this.#previousEmptyAt = null; }
  accepting(snapshot) {
    if (snapshot?.state !== 'filtered_empty' || !Array.isArray(snapshot.parcels) || snapshot.parcels.length
        || (snapshot.expectedCount != null && snapshot.expectedCount !== 0)) {
      this.reset(); return snapshot;
    }
    const readAt = Date.parse(snapshot.readAt);
    if (!Number.isFinite(readAt)) { this.reset(); return snapshot; }
    const previous = this.#previousEmptyAt;
    this.#previousEmptyAt = readAt;
    if (previous === null || readAt <= previous || readAt - previous > 5000) return snapshot;
    this.reset();
    return { ...snapshot, state: 'ready', expectedCount: 0, message: '已确认淘宝当前待取页为空' };
  }
}
