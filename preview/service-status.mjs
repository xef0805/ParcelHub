export const SERVICE_MESSAGES = {
  offline: '当前网络不可用，已保留本地包裹。请联网后重试。',
  timeout: '连接超时，已保留本地包裹。请稍后重试。',
  login: '淘宝登录已失效或尚未登录，已保留本地包裹。请重新登录后刷新。',
  wechatMissing: '未检测到可用的微信。请先安装或打开微信，再返回重试。',
  openFailed: '无法打开微信。请手动打开微信后重试；仍失败时请重新获取小程序链接。',
  expiredLink: '链接已失效或无法核对目标。请在对应小程序重新获取完整链接，原绑定已保留。',
  unavailable: '官方服务暂时不可用，已保留本地记录。请稍后重试。',
  incomplete: '本轮未能读取完整淘宝清单，已保留本地包裹。请打开官方待取页核对后重试；若网页也缺件，请先检查账号及收件手机号。',
  phoneFilter: '淘宝网页未返回该手机号的待取件，已保留本地记录。若淘宝 App 中有包裹，请核对网页登录账号，并从右上角菜单在浏览器打开进行比较。'
};
export function statusForSnapshot(snapshot) {
  if (snapshot?.state === 'ready') return null;
  return snapshot?.state === 'login_required' ? SERVICE_MESSAGES.login
    : snapshot?.state === 'filtered_empty' ? SERVICE_MESSAGES.phoneFilter
    : snapshot?.state === 'loading' ? SERVICE_MESSAGES.incomplete : SERVICE_MESSAGES.unavailable;
}
