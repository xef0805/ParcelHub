const originals = new WeakMap();
const attributes = new WeakMap();

export function displayPreferences(value = {}) {
  return {
    appearance: ['system', 'light', 'dark'].includes(value.appearance) ? value.appearance : 'system',
    language: value.language === 'en' ? 'en' : 'zh-Hans'
  };
}

export function translated(text, language, dictionary) {
  if (language !== 'en') return text;
  const trimmed = text.trim();
  const result = dictionary[trimmed];
  return result === undefined ? text : text.replace(trimmed, () => result);
}

// 只替换界面文本；用户内容、输入值和第三方页面不参与翻译。
export function localizeDOM(root, language, dictionary) {
  const document = root.ownerDocument || root;
  const walker = document.createTreeWalker(root, 4);
  for (let node = walker.nextNode(); node; node = walker.nextNode()) {
    if (node.parentElement?.closest('script,style,textarea,[data-user-content]')) continue;
    let saved = originals.get(node);
    if (!saved || node.nodeValue !== saved.output) saved = { original: node.nodeValue };
    const output = translated(saved.original, language, dictionary);
    originals.set(node, { original: saved.original, output });
    if (node.nodeValue !== output) node.nodeValue = output;
  }
  for (const element of root.querySelectorAll('[placeholder],[aria-label],[title]')) {
    if (element.closest('[data-user-content]')) continue;
    const saved = attributes.get(element) || {};
    for (const name of ['placeholder', 'aria-label', 'title']) {
      if (!element.hasAttribute(name)) continue;
      const value = element.getAttribute(name);
      const original = saved[name]?.output === value ? saved[name].original : value;
      const output = translated(original, language, dictionary);
      saved[name] = { original, output };
      if (output !== value) element.setAttribute(name, output);
    }
    attributes.set(element, saved);
  }
}
