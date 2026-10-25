(function readPickupSMS(raw, history = [], day = '') {
  const text = String(raw || '').normalize('NFKC').slice(0, 8000);
  const content = text.replace(/https?:\/\/[^\s，。；！]+/gi, '');
  const aliases = [
    ['菜鸟速递', /菜鸟速递|丹鸟/], ['韵达', /韵达/], ['中通', /中通/], ['申通', /申通/],
    ['圆通', /圆通/], ['顺丰', /顺丰|S\.?F\.?\s*(?:EXPRESS|速运)/i], ['京东', /京东|JDL/i],
    ['极兔', /极兔|J\s*&\s*T/i], ['德邦', /德邦/], ['EMS', /\bEMS\b/i], ['邮政', /邮政/], ['百世', /百世/]
  ];
  const normalizeCarrier = value => aliases.find(([, pattern]) => pattern.test(String(value || '')))?.[0] || '';
  const carrier = normalizeCarrier(content);
  const recent = history.filter(p => !p.isDemo && carrier && normalizeCarrier(p.carrier) === carrier && p.station)
    .slice().sort((a, b) => {
      const latest = p => Math.max(...[p.addedAt, p.collectedAt].map(d => Date.parse(d || '') || 0));
      return latest(b) - latest(a);
    })[0];
  const platform = [
    ['yishoufa', /驿收发/], ['fcbox', /丰巢/], ['tuxi', /兔喜/],
    ['mamayz', /妈妈驿站/], ['panda', /熊猫快收/], ['cainiao', /菜鸟驿站/]
  ].find(([, pattern]) => pattern.test(content))?.[0];
  // 承运快递不等于末端平台：没有明确平台时沿用历史，否则留在“其他取件点”。
  const providerID = platform || recent?.providerID || 'manual';
  const codeCandidates = [];
  const addCode = candidate => {
    const code = candidate.replace(/\s+/g, '').replace(/[-]+$/, '');
    if (code.length < 3 || code.length > 24 || !/^[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*$/.test(code)
        || /^1[3-9]\d{9}$/.test(code) || /^400\d{7}$/.test(code) || /^\d{4}-\d{2}-\d{2}$/.test(code)) return;
    if (!codeCandidates.includes(code)) codeCandidates.push(code);
  };
  for (const match of content.matchAll(/(?:取件码|提货码|取货码|提件码|取件密码|开柜码)\s*(?:是|为)?\s*[:：]?\s*[【[(]?\s*([A-Za-z0-9][A-Za-z0-9 \t-]{1,30})/g)) addCode(match[1]);
  if (!codeCandidates.length) {
    for (const match of content.matchAll(/(?:请)?凭\s*([A-Za-z0-9][A-Za-z0-9-]{2,23})\s*(?:到|至|前往|取件|领取)/g)) addCode(match[1]);
  }
  let station = '';
  const place = content.match(/(?:已到达|已送达|已放至|已放在|已存入|已到|到达|存放在|放在)\s*([^，。；,;！!\n]{2,100})/)
    || content.match(/(?:前往|到|至)\s*([^，。；,;！!\n]{2,100}?)(?:取件|领取)/);
  if (place) {
    const candidate = place[1].split(/请凭|取件码|提货码|请于|请联系|联系电话|电话|客服/)[0].trim();
    if (/(?:驿站|快递柜|快递站|快递超市|取件点|代收点|服务站|自提点|丰巢|便利店|门卫|收发室|快递点)/.test(candidate)) station = candidate;
  }
  const stationSource = station ? 'sms' : recent ? 'history' : 'missing';
  station ||= recent?.station || '';
  const tracking = content.match(/(?:运单号|快递单号|单号)\s*[:：为]?\s*([A-Za-z0-9]{6,40})/i)?.[1] || '';
  const local = new Date();
  day ||= `${local.getFullYear()}-${String(local.getMonth() + 1).padStart(2, '0')}-${String(local.getDate()).padStart(2, '0')}`;
  const compactDay = day.replace(/-/g, '');
  const titles = history.filter(p => !p.isDemo).map(p => String(p.title || ''));
  let serial = 1;
  for (const title of titles) {
    const suffix = title.startsWith(compactDay) ? title.slice(compactDay.length)
      : title.startsWith(day + ' ') ? title.slice(day.length + 1) : '';
    const match = suffix.match(/^(?:包裹|快件)(\d+)号$/);
    if (match && Number.isSafeInteger(Number(match[1]))) serial = Math.max(serial, Number(match[1]) + 1);
  }
  const state = codeCandidates.length === 1 ? 'ready' : codeCandidates.length > 1 ? 'choose_code' : 'needs_code';
  const message = state === 'choose_code' ? '识别到多个取件码，请选择本次要添加的一件'
    : state === 'needs_code' ? '未明确识别取件码，请核对短信或手动填写'
    : stationSource === 'history' ? `已沿用上次${carrier}的取件地点，请确认本次仍在此处`
    : stationSource === 'missing' ? '已识别取件码，请补充取件地点' : '已从短信识别，请核对后保存';
  return { state, message, title: `${compactDay}包裹${serial}号`, carrier, providerID, station, stationSource,
    pickupCode: codeCandidates.length === 1 ? codeCandidates[0] : '', codeCandidates, trackingNumber: tracking };
})
