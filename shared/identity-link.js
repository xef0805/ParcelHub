(function parseIdentityLink(raw, expectedName = '', landingHTML = '') {
  const value = String(raw || '').trim();
  if (!value || value.length > 2048) return { error: '请粘贴完整的小程序口令或官方跳转链接' };
  const share = value.match(/^#小程序:\/\/([^/\s]+)\/([A-Za-z0-9_-]+)$/);
  if (share) {
    if (expectedName && share[1] !== expectedName) return { error: `这个口令属于「${share[1]}」，请选择对应平台` };
    return { kind: 'shareCode', value, message: '微信口令需复制到微信内打开。' };
  }
  // 只保存平台提供的完整票据，不用分享口令拼接或猜测微信 Scheme。
  if (/^weixin:\/\/dl\/business\/\?t=[A-Za-z0-9_%=-]+$/.test(value)
      || /^https:\/\/(?:wxaurl\.cn|wxmpurl\.cn)\/[A-Za-z0-9_/?=&%.-]+$/.test(value)) {
    let resolvedURL;
    if (landingHTML) {
      // 官方桌面链接页面公开给出的跳转票据；只读文本，不执行页面脚本。
      for (const block of String(landingHTML).matchAll(/window\.data\s*=\s*\{([^}]+)\}/g)) {
        const name = block[1].match(/nickname:\s*'([^']+)'/)?.[1];
        const scheme = block[1].match(/url_scheme:\s*'(weixin:[^']+)'/)?.[1];
        if (name === expectedName && /^weixin:\/\/dl\/business\/\?t=[A-Za-z0-9_%=-]+$/.test(scheme || '')) resolvedURL = scheme;
      }
      if (!resolvedURL) return { error: '未能核对官方链接的目标小程序，请重新获取链接后试开' };
    }
    return { kind: 'launchURL', value, resolvedURL, message: '先试开再绑定，链接失效时重新获取。' };
  }
  return { error: '暂不支持此链接。请使用完整的微信小程序口令或官方跳转链接，不要填写身份码。' };
})
