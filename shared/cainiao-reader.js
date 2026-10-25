(function parseCainiaoPage(text) {
  const lines = String(text || '').split(/\r?\n/).map(line => line.trim()).filter(Boolean);
  const result = (state, message, parcels = [], expectedCount = null) => ({
    state, message, parcels, expectedCount, readAt: new Date().toISOString()
  });
  if (lines.some(line => /接口超时|网络异常|服务开小差|访问受限|请完成验证/.test(line))) {
    return result('error', '官方页面返回错误或验证要求，原有记录保持不变');
  }
  if (lines.some(line => /您需要登录|请先登录|账号密码登录/.test(line))) {
    return result('login_required', '请先在官方页面完成登录');
  }
  const start = lines.indexOf('待取件');
  if (start < 0 || !/^\d+$/.test(lines[start + 1] || '')) {
    return result('loading', '页面尚未显示完整的待取件数量，请等待后重试');
  }
  const expectedCount = Number(lines[start + 1]);
  if (expectedCount > 100) return result('error', '页面数量超出当前验证范围，暂不导入');
  if (expectedCount === 0 && !lines.some(line => /暂无待取|没有待取|全部取完/.test(line))) {
    return result('loading', '尚未确认官方空清单，保留原有记录');
  }
  const end = lines.findIndex((line, index) => index > start && /^还有包裹未显示/.test(line));
  const content = lines.slice(start + 2, end < 0 ? undefined : end);
  const codePattern = /^(?:取件码\s*[:：]?\s*)?([A-Za-z0-9]{1,4}-[A-Za-z0-9]{1,4}-[A-Za-z0-9]{1,12})$/;
  const carrierPattern = /^(圆通(?:速递)?|韵达(?:快递)?|中通(?:快递)?|申通(?:快递)?|顺丰(?:速运)?|极兔(?:速递)?|邮政(?:快递)?|EMS|京东(?:物流)?|德邦(?:快递)?|菜鸟速递|百世(?:快递)?|天天(?:快递)?)\s+([A-Za-z0-9]{6,40})$/i;
  const entries = [];
  for (let i = 0; i < content.length; i++) {
    const code = content[i].match(codePattern);
    if (!code) continue;
    let carrier = null;
    for (let j = i + 1; j < Math.min(content.length, i + 15); j++) {
      if (codePattern.test(content[j])) break;
      const match = content[j].match(carrierPattern);
      if (match) { carrier = match; break; }
    }
    // 取件码与运单号必须属于同一卡片，禁止把不完整解析当作完整同步。
    if (!carrier) return result('error', '包裹卡片结构发生变化，未导入部分结果');
    let station = '';
    for (let j = i - 1; j >= 0; j--) {
      if (/(驿站|快递柜|自提柜|代收点|快递服务站|取件点)$/.test(content[j]) && content[j].length < 120) {
        station = content[j]; break;
      }
    }
    if (!station) return result('error', '未能确认实际取件地点，暂不导入');
    entries.push({ providerID: 'cainiao', title: carrier[1] + '包裹', station,
      pickupCode: code[1], carrier: carrier[1], trackingNumber: carrier[2] });
  }
  const keys = entries.map(p => p.carrier + ':' + p.trackingNumber.toUpperCase());
  if (new Set(keys).size !== keys.length || entries.length !== expectedCount) {
    return result('error', '读取数量与官方待取件数量不一致，原有记录保持不变', [], expectedCount);
  }
  return result('ready', '已读取官方页面当前显示的待取件', entries, expectedCount);
})
