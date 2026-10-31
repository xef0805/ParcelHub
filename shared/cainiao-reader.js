(function parseCainiaoPage(text) {
  const lines = String(text || '').split(/\r?\n/).map(line => line.trim()).filter(Boolean);
  const result = (state, message, parcels = [], expectedCount = null) => ({
    state, message, parcels, expectedCount, readAt: new Date().toISOString()
  });
  if (lines.some(line => /接口超时|请求超时|网络异常|网络错误|服务开小差|系统繁忙|访问受限|请完成验证/.test(line))) {
    return result('error', '官方页面返回错误或验证要求，原有记录保持不变');
  }
  if (lines.some(line => /您需要登录|请先登录|账号密码登录|登录已失效|登录过期|请重新登录|登录状态已失效|会话已过期/.test(line))) {
    return result('login_required', '请先在官方页面完成登录');
  }
  // 推荐商品也显示“加载中”，不能用整页加载文案否定已完整读取的非空清单。
  const hasLoading = lines.some(line => /^(加载中|正在加载|正在刷新)[.。…]*$/.test(line));
  const start = lines.findIndex(line => /^待取件(?:\s*[（(]\s*\d+\s*[）)])?$/.test(line));
  if (start < 0) {
    return result('loading', '页面尚未显示完整的待取件数量，请等待后重试');
  }
  const end = lines.findIndex((line, index) => index > start && /^还有包裹未显示/.test(line));
  const section = lines.slice(start + 1, end < 0 ? undefined : end);
  const codePattern = /^(?:取件码\s*[:：]?\s*)?([A-Za-z0-9]{1,4}-[A-Za-z0-9]{1,4}-[A-Za-z0-9]{1,12})$/;
  const inlineCount = lines[start].match(/[（(]\s*(\d+)\s*[）)]/);
  const displayedCount = inlineCount ? Number(inlineCount[1]) : /^\d+$/.test(lines[start + 1] || '') ? Number(lines[start + 1]) : null;
  // 手机号空状态是待确认的空清单，由读取会话复读确认；不输出手机号。
  const compactSection = section.join('').replace(/\s/g, '');
  const selectedPhoneEmpty = /未查到(?:1\d{2}[*＊]{4}\d{4}|1\d{10})[›>❯→]*的包裹/.test(compactSection)
    || /您的\d+个手机号[›>❯→]*都未查到包裹/.test(compactSection);
  if (selectedPhoneEmpty) {
    if (displayedCount > 0 || section.some(line => codePattern.test(line))) {
      return result('error', '页面空状态与待取卡片不一致，保留原有记录');
    }
    return result('filtered_empty', '正在确认空清单，记录暂时保留');
  }
  // 空状态文案可能替代数字角标；仅接受明确完整的空清单提示，空白页面不能清空。
  const emptyPattern = /^(?:(?:暂无|暂时没有|还没有|你还没有|您还没有|没有)待取(?:件|包裹)(?:包裹)?(?:啦|了|哦)?|(?:包裹已)?全部取完(?:了)?|包裹都取完啦)[！!。~～]*$/;
  const explicitlyEmpty = section.some(line => emptyPattern.test(line));
  if (displayedCount === null && !explicitlyEmpty) {
    return result('loading', '页面数量或空状态尚未加载完整，请等待后重试');
  }
  if (displayedCount > 0 && explicitlyEmpty) return result('error', '页面数量与空状态不一致，保留原有记录');
  const expectedCount = displayedCount ?? 0;
  if (expectedCount > 100) return result('error', '页面数量超出当前验证范围，暂不导入');
  if (expectedCount === 0 && hasLoading) {
    return result('loading', '官方清单仍在加载，保留原有记录');
  }
  if (expectedCount === 0 && !explicitlyEmpty) {
    return result('loading', '尚未确认官方空清单，保留原有记录');
  }
  const content = section;
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
