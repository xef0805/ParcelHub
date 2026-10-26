(function classifyImport(raw) {
  const text = String(raw || '').trim();
  if (!text || text.length > 8000) return null;
  const normalized = text.normalize('NFKC');
  const content = normalized.replace(/https?:\/\/[^\s，。；！]+/gi, '');
  if (/(?:取件码|提货码|取货码|提件码|取件密码|开柜码)\s*(?:是|为)?\s*[:：]?\s*[【[(]?\s*[A-Za-z0-9]/.test(content)
      || /(?:请)?凭\s*[A-Za-z0-9][A-Za-z0-9-]{2,23}\s*(?:到|至|前往|取件|领取)/.test(content)) {
    return { kind: 'sms', text, trackingNumber: '', carrier: '' };
  }
  if (/验证码|动态密码|登录密码/.test(normalized)) return null;
  const labelled = [...normalized.matchAll(/(?:运单号|快递单号|物流单号|单号)\s*(?:是|为)?\s*[:：]?\s*([A-Za-z0-9]{8,40})/g)].map(m => m[1].toUpperCase());
  if (new Set(labelled).size > 1) return null;
  if (!labelled.length && normalized.split(/\r?\n/).filter(line => line.trim()).length > 1) return null;
  const value = labelled[0] || normalized.replace(/\s/g, '').toUpperCase();
  if (!/^[A-Z0-9]{8,40}$/.test(value) || !/\d/.test(value) || /^1[3-9]\d{9}$/.test(value)) return null;
  if (!labelled.length && !/^(?:SF|JD|JDL|JT|JTX|YT|ZTO|STO|DB|EMS|LP)[A-Z0-9]{6,35}$/.test(value) && !/^\d{10,15}$/.test(value)) return null;
  const carrier = /顺丰/.test(normalized) || /^SF/.test(value) ? '顺丰'
    : /京东/.test(normalized) || /^JD/.test(value) ? '京东'
    : /极兔/.test(normalized) || /^JT/.test(value) ? '极兔'
    : /中通/.test(normalized) || /^ZTO/.test(value) ? '中通'
    : /圆通/.test(normalized) || /^YT/.test(value) ? '圆通'
    : /申通/.test(normalized) || /^STO/.test(value) ? '申通'
    : /韵达/.test(normalized) ? '韵达' : /德邦/.test(normalized) || /^DB/.test(value) ? '德邦' : /^EMS/.test(value) ? 'EMS' : '';
  return { kind: 'tracking', text, trackingNumber: value, carrier };
})
