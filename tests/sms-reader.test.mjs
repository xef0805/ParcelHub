import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { readFile } from 'node:fs/promises';
const read = vm.runInNewContext(await readFile(new URL('../shared/sms-reader.js', import.meta.url), 'utf8'));
const day = '2026-10-25';
const history = [
  { carrier: '韵达快递', station: '旧校区驿站', providerID: 'yishoufa', addedAt: '2026-10-22T10:00:00Z' },
  { carrier: '韵达', station: '北门快递超市', providerID: 'cainiao', addedAt: '2026-10-24T10:00:00Z', title: `${day} 快件1号` },
  { carrier: '圆通', station: '东门驿站', addedAt: '2026-10-25T10:00:00Z' },
  { carrier: '韵达', station: '演示地点', isDemo: true, addedAt: '2026-10-26T10:00:00Z' }
];
test('完整短信自动识别物流、前导零取件码，并沿用同公司最近地点和平台', () => {
  const result = read('【韵达快递】您的快件已入库，取件码：01-02-0003，请及时领取。', history, day);
  assert.equal(result.state, 'ready');
  assert.equal(result.carrier, '韵达');
  assert.equal(result.station, '北门快递超市');
  assert.equal(result.providerID, 'manual');
  assert.equal(result.pickupCode, '01-02-0003');
  assert.equal(result.title, '1025包裹2号');
  assert.equal(result.stationSource, 'history');
});
test('短信明确的新地点优先于历史地点；明确末端平台优先于历史平台', () => {
  const result = read('【丰巢】您的韵达包裹已存入南门丰巢快递柜，开柜码008 426。', history, day);
  assert.equal(result.station, '南门丰巢快递柜');
  assert.equal(result.providerID, 'fcbox');
  assert.equal(result.pickupCode, '008426');
  assert.equal(result.stationSource, 'sms');
});
test('无历史时不能根据快递公司猜测驿站；名称每日重新编号', () => {
  const result = read('【顺丰】取件码：000123。', history, '2026-10-26');
  assert.equal(result.providerID, 'manual');
  assert.equal(result.station, '');
  assert.equal(result.title, '1026包裹1号');
});
test('验证码、手机号、日期和链接里的数字不能当取件码', () => {
  for (const text of ['验证码123456，请勿泄露', '请联系13800000000', '取件码13800000000', '取件码2026-10-25', '点击https://example.com/取件码123456']) {
    assert.equal(read(text, [], day).pickupCode, '', text);
  }
});
test('多件短信列出候选，不擅自选第一件；同一码重复出现不重复', () => {
  const result = read('【中通】取件码01-2-0001；另一件取件码02-3-0002', [], day);
  assert.equal(result.state, 'choose_code');
  assert.equal(result.codeCandidates.length, 2);
  assert.equal(result.pickupCode, '');
  assert.equal(read('取件码000123，取件码000123', [], day).state, 'ready');
});
test('支持全角数字与凭码取件，只提取明确的运单号', () => {
  const result = read('【京东快递】请凭Ａ１-００２到北门驿站取件，运单号JDTEST0000123', [], day);
  assert.equal(result.pickupCode, 'A1-002');
  assert.equal(result.trackingNumber, 'JDTEST0000123');
  assert.equal(result.station, '北门驿站');
  assert.equal(read('【韵达】取件码为：000123，请到南门驿站取件', [], day).pickupCode, '000123');
});
test('解析结果不额外提取手机号；原文由保存层处理，编号按最大已用序号续排', () => {
  const result = read('【韵达】取件码000123，联系电话13800000000', [...history, { title: `${day} 快件8号` }], day);
  assert.equal(result.title, '1025包裹9号');
  assert.equal(JSON.stringify(result).includes('13800000000'), false);
  assert.equal('raw' in result, false);
});

test('新旧命名混用时按当天最大序号继续，不改写历史名称', () => {
  const records = [{title:'20261025包裹4号'}, {title:'2026-10-25 快件8号'}, {title:'20261024包裹99号'}, {title:'20261025包裹50号',isDemo:true}];
  assert.equal(read('',records,day).title,'1025包裹9号');
  assert.equal(records[1].title,'2026-10-25 快件8号');
});

test('短日期名称按当天序号续排，跨年同月日不影响本年编号；不把尾号当完整单号',()=>{
  const records=[{title:'1026包裹2号',addedAt:'2026-10-26T09:00:00'},{title:'1026包裹99号',addedAt:'2025-10-26T09:00:00'}];
  const result=read('【京东快递】取件码K-1-0001，您的快件尾号1234已送达测试校园服务站。',records,'2026-10-26');
  assert.equal(result.title,'1026包裹3号');assert.equal(result.trackingNumber,'');assert.equal(result.sender,'京东快递');
});
