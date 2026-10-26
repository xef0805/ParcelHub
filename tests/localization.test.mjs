import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { displayPreferences, translated } from '../preview/i18n.mjs';

const dictionary = JSON.parse(await readFile(new URL('../preview/locales/en.json', import.meta.url), 'utf8'));
test('显示设置兼容旧存档，未知设置回退且不修改原对象', () => {
  const original = { appearance: 'invalid', language: 'fr', parcels: ['保留记录'] };
  assert.deepEqual(displayPreferences(original), { appearance: 'system', language: 'zh-Hans' });
  assert.deepEqual(displayPreferences({ appearance: 'dark', language: 'en' }), { appearance: 'dark', language: 'en' });
  assert.deepEqual(original.parcels, ['保留记录']);
  assert.equal(original.appearance, 'invalid');
});
test('翻译保留空白和未知内容，中文选择不改写原文', () => {
  assert.equal(translated('  设置\n', 'en', dictionary), '  Settings\n');
  for (const text of ['【韵达】取件码01-2-0003', '测试北门驿站', 'SF123456789012']) {
    assert.equal(translated(text, 'en', dictionary), text);
  }
  assert.equal(translated('设置', 'zh-Hans', dictionary), '设置');
});
test('原生与预览翻译资源一致，格式占位符完整保留', async () => {
  for (const language of ['en', 'zh-Hans']) {
    const text = await readFile(new URL(`../ios/ParcelHub/${language}.lproj/Localizable.strings`, import.meta.url), 'utf8');
    const entries = text.trim().split(/\r?\n/).map(line => {
      const match = line.match(/^("(?:\\.|[^"\\])*") = ("(?:\\.|[^"\\])*");$/u);
      assert.ok(match, 'Localizable.strings 行格式错误');
      return [JSON.parse(match[1]), JSON.parse(match[2])];
    });
    assert.equal(new Set(entries.map(([key]) => key)).size, entries.length);
    assert.deepEqual(Object.fromEntries(entries), Object.fromEntries(Object.entries(dictionary).map(([key, value]) => [key, language === 'en' ? value : key])));
    for (const [key, value] of entries) assert.deepEqual(value.match(/%(?:lld|@)/g) || [], key.match(/%(?:lld|@)/g) || []);
  }
});
