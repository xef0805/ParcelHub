import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import vm from 'node:vm';
const classify=vm.runInNewContext(await readFile(new URL('../shared/import-reader.js',import.meta.url),'utf8'));
test('剪贴板取件短信优先进入短信导入，并保留原文',()=>{
  const text='【顺丰】取件码01-2-0001，运单号SF123456789012，已到测试站。';
  const result=classify(text);assert.equal(result.kind,'sms');assert.equal(result.text,text);
});
test('识别单独或带标签的完整运单号，并给出可核对的物流提示',()=>{
  assert.equal(classify(' sf123456789012 ').trackingNumber,'SF123456789012');
  assert.equal(classify('SF123456789012').carrier,'顺丰');
  assert.equal(classify('【中通】运单号：123456789012').carrier,'中通');
  assert.equal(classify('123456789012').carrier,'');
  assert.equal(classify('运单号：ＪＤ１２３４５６７８９０').trackingNumber,'JD1234567890');
});
test('凭码取件通知也进入短信页，链接中的取件码文字不能触发',()=>{
  assert.equal(classify('【韵达】请凭01-2-0003到测试南门驿站取件。').kind,'sms');
  assert.equal(classify('https://example.com/取件码ABC123'),null);
});
test('不把手机号、验证码、身份证号、普通文字、网址或多单当作单号提示',()=>{
  for(const text of ['13800000000','123456','验证码12345678','DBPASSWORD','110101199001010011','https://example.com/SF123456789012','SF123456789012\nJD123456789012','单号SF123456789012，单号JD123456789012'])assert.equal(classify(text),null,text);
});
test('空剪贴板与超长内容不弹导入提示',()=>{
  assert.equal(classify(''),null);assert.equal(classify('A'.repeat(8001)),null);
});
