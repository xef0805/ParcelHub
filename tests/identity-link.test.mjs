import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { readFile } from 'node:fs/promises';
const parse=vm.runInNewContext(await readFile(new URL('../shared/identity-link.js',import.meta.url),'utf8'));

test('微信分享口令不能当成外部跳转链接，其他平台口令不能错绑',()=>{
  const result=parse('#小程序://兔喜生活/Example123','兔喜生活');
  assert.equal(result.kind,'shareCode');assert.equal(result.resolvedURL,undefined);
  assert.match(parse('#小程序://其他平台/Example123','兔喜生活').error,/属于/);
});
test('只接受完整官方短链接或真实 Scheme，不允许猜票据和任意网站',()=>{
  for(const value of ['https://wxmpurl.cn/example','https://wxaurl.cn/example','weixin://dl/business/?t=official-ticket'])assert.equal(parse(value).kind,'launchURL');
  for(const value of ['weixin://','weixin://dl/business/?appid=madeup','https://wxmpurl.cn.evil.test/example','https://wxmpurl.cn@evil.test/example','javascript:alert(1)','http://wxmpurl.cn/example'])assert.ok(parse(value).error,value);
});
test('官方桌面页只读取同名小程序公开票据，跳过示例与其他目标；不执行脚本',()=>{
  const html=`window.data={nickname:'小程序示例',url_scheme:'weixin://dl/business/?t=mock'};
    window.data={nickname:'兔喜生活',url_scheme:'weixin://dl/business/?t=official-test',query:''};
    throw new Error('不可执行页面脚本');`;
  assert.equal(parse('https://wxmpurl.cn/example','兔喜生活',html).resolvedURL,'weixin://dl/business/?t=official-test');
  assert.ok(parse('https://wxmpurl.cn/example','丰巢',html).error);
  assert.ok(parse('https://wxmpurl.cn/example','兔喜生活',"window.data={nickname:'兔喜生活',url_scheme:'javascript:alert(1)'}").error);
});
test('链接失效页和页面格式变化均失败，不改成根微信或伪造身份码',()=>{
  assert.ok(parse('https://wxmpurl.cn/example','兔喜生活','链接已失效').error);
  assert.ok(parse('https://wxmpurl.cn/example','兔喜生活','<html>请登录</html>').error);
});
