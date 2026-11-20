// 运行：node backend/test/backend.test.js
// 每个用例在两种模式下各跑一遍：plain（理想表格）和 smart（表格自作聪明：时间变 Date、纯数字串变数字）。
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const { makeEnv } = require('./harness');

const vectors = JSON.parse(fs.readFileSync(path.join(__dirname, 'score_vectors.json'), 'utf8'));
const ev = JSON.parse(fs.readFileSync(path.join(__dirname, 'enh_vectors.json'), 'utf8'));
const mv = JSON.parse(fs.readFileSync(path.join(__dirname, 'meta_vectors.json'), 'utf8'));
const cases = [];
const test = (name, fn) => cases.push({ name, fn });

const RUN = (o = {}) => Object.assign({ won: false, seconds: 300, level: 12, kills: 800, bosses: 0, school: 'fist', starter: 'chain_fist', qinggong: 'tashue', enhance: '', build: [], version: '0.1' }, o);
const MIN = 60000;

function env(mode) { const e = makeEnv({ autoConvert: mode === 'smart' }); e.invite('ABC234', '测试', true, 0); return e; }
function reg(e, nick, pin = '4815', code = 'ABC234') { return e.call({ action: 'register', nick, pin, code }); }
function submit(e, who, run) { e.advance(60 * 1000); return e.call(Object.assign({ action: 'submit', nick: who.nick, token: who.token }, run)); }

test('setup：建表、表头、可重复运行', (e) => {
  e.ctx.setup(); e.ctx.setup();
  for (const k of Object.keys(e.ctx.SHEETS)) {
    const rows = e.sheetRows(k);
    assert.strictEqual(JSON.stringify(rows[0]), JSON.stringify(e.ctx.HEADERS[k]), k + ' 表头');   // 跨 VM 的数组不能直接 deepEqual
  }
});

test('ping / 未知请求 / 坏 JSON', (e) => {
  assert.ok(e.get({ action: 'ping' }).ok);
  assert.strictEqual(e.call({ action: 'nope' }).err, 'bad_action');
  const r = JSON.parse(e.ctx.doPost({ postData: { contents: '{坏的' } }).text);
  assert.strictEqual(r.err, 'server');
  assert.ok(e.sheetRows('logs').length >= 2, '服务器错误应写入日志');
});

test('注册：校验与成功', (e) => {
  assert.strictEqual(reg(e, 'a').err, 'bad_nick');
  assert.strictEqual(reg(e, 'has space').err, 'bad_nick');
  assert.strictEqual(reg(e, '<script>').err, 'bad_nick');
  assert.strictEqual(reg(e, '小明', '12').err, 'bad_pin');
  assert.strictEqual(reg(e, '小明', 'abcd').err, 'bad_pin');
  assert.strictEqual(reg(e, '小明', '4815', 'WRONG1').err, 'bad_code');
  const r = reg(e, '小明', '48151623');
  assert.ok(r.ok, JSON.stringify(r));
  assert.ok(r.token && r.token.length >= 32);
  assert.strictEqual(r.nick, '小明');
  assert.strictEqual(reg(e, '小明').err, 'nick_taken');
  assert.strictEqual(reg(e, '小明'.toUpperCase() === '小明' ? '小明' : 'x').err, 'nick_taken');
  // PIN 不能明文落盘
  for (const row of e.sheetRows('players')) for (const cell of row) assert.notStrictEqual(String(cell), '48151623');
});

test('注册：昵称不分大小写唯一；数字昵称保留前导 0', (e) => {
  assert.ok(reg(e, 'Alice').ok);
  assert.strictEqual(reg(e, 'alice').err, 'nick_taken');
  assert.ok(reg(e, '007').ok);
  assert.ok(e.call({ action: 'login', nick: '007', pin: '4815' }).ok, '007 应能登录');
  assert.strictEqual(e.sheetRows('players')[2][0], '007');
});

test('邀请码：关闭 / 满员 / 计数', (e) => {
  e.invite('CLOSED', '关了', false, 0);
  e.invite('ONLY1X', '一个人', true, 1);
  assert.strictEqual(reg(e, 'p1', '4815', 'CLOSED').err, 'code_closed');
  assert.ok(reg(e, 'p1', '4815', 'only1x').ok, '邀请码不分大小写');
  assert.strictEqual(reg(e, 'p2', '4815', 'ONLY1X').err, 'code_full');
  const inv = e.sheetRows('invites').find((r) => r[0] === 'ONLY1X');
  assert.strictEqual(Number(inv[5]), 1);
});

test('邀请码：昵称名单（只有名单里的昵称能注册，不分大小写）', (e) => {
  e.invite('VIPONE', '核心朋友', true, 0, '阿杰，小明, Lee\n王五');
  assert.strictEqual(reg(e, '路人甲', '4815', 'VIPONE').err, 'not_on_roster');
  assert.ok(reg(e, '阿杰', '4815', 'VIPONE').ok, '名单里的昵称可以注册');
  assert.ok(reg(e, 'lee', '4815', 'VIPONE').ok, '名单不分大小写');
  assert.ok(reg(e, '王五', '4815', 'VIPONE').ok, '换行分隔的名字也认');
  assert.ok(reg(e, '路人乙', '4815', 'ABC234').ok, '没有名单的邀请码不受影响');
});

test('邀请码：到期（填日期 = 当天有效）', (e) => {
  const day = new Date(2027, 0, 15);                                  // 本地 2027-01-15 0 点（表格里只填日期的样子）
  e.invite('SOON01', '限时', true, 0, '', day);
  e.ctx.__clock = new Date(2027, 0, 15, 15, 0, 0).getTime();         // 当天下午
  assert.ok(reg(e, '赶上了', '4815', 'SOON01').ok, '到期当天还能用');
  e.ctx.__clock = new Date(2027, 0, 16, 9, 0, 0).getTime();          // 第二天
  assert.strictEqual(reg(e, '来晚了', '4815', 'SOON01').err, 'code_expired');
  const stamp = new Date(2027, 0, 10, 12, 30, 0);                     // 带具体时刻的到期：精确到点
  e.invite('SOON02', '精确', true, 0, '', stamp);
  e.ctx.__clock = new Date(2027, 0, 10, 12, 0, 0).getTime();
  assert.ok(reg(e, '准时', '4815', 'SOON02').ok);
  e.ctx.__clock = new Date(2027, 0, 10, 13, 0, 0).getTime();
  assert.strictEqual(reg(e, '迟到', '4815', 'SOON02').err, 'code_expired');
});

test('群：个人信息带群名；排行榜可只看本群', (e) => {
  e.invite('GRPAAA', '篮球群', true, 0);
  e.invite('GRPBBB', '读书会', true, 0);
  const a1 = reg(e, 'A1', '4815', 'GRPAAA'), a2 = reg(e, 'A2', '4815', 'grpaaa'), b1 = reg(e, 'B1', '4815', 'GRPBBB');
  assert.strictEqual(a1.group, '篮球群'); assert.strictEqual(a1.invite, 'GRPAAA');
  const b1login = e.call({ action: 'login', nick: 'B1', pin: '4815' });      // 登录会换令牌，之后用新令牌
  assert.strictEqual(b1login.group, '读书会');
  submit(e, a1, RUN({ level: 10, kills: 500 })); submit(e, a2, RUN({ level: 20, kills: 900 })); submit(e, b1login, RUN({ level: 30, kills: 1500 }));
  const all = e.get({ action: 'board', kind: 'score' });
  assert.strictEqual(all.total, 3);
  const g = e.get({ action: 'board', kind: 'score', group: 'GRPAAA', nick: 'A1' });
  assert.strictEqual(g.total, 2, '只含本群'); assert.deepStrictEqual(g.rows.map((r) => r.nick), ['A2', 'A1']);
  assert.strictEqual(g.me.rank, 2, '本群内的名次'); assert.strictEqual(g.group, '篮球群');
  assert.strictEqual(e.get({ action: 'board', kind: 'score', group: 'NOPE00' }).total, 0);
  assert.strictEqual(all.rows[0].nick, 'B1', '全体榜里 B1 分最高');
});

test('登录：成功换令牌、错误提示不泄露、锁定与解锁', (e) => {
  const r = reg(e, '阿杰', '2468');
  const l = e.call({ action: 'login', nick: '阿杰', pin: '2468' });
  assert.ok(l.ok); assert.notStrictEqual(l.token, r.token, '登录应换新令牌');
  assert.strictEqual(e.call({ action: 'login', nick: '不存在', pin: '2468' }).err, 'bad_login');
  const w = e.call({ action: 'login', nick: '阿杰', pin: '0000' });
  assert.strictEqual(w.err, 'bad_login'); assert.strictEqual(w.left, 4);
  assert.strictEqual(w.msg, e.call({ action: 'login', nick: '不存在', pin: '1' }).msg, '用户不存在与 PIN 错误提示一致');
  for (let i = 0; i < 3; i++) e.call({ action: 'login', nick: '阿杰', pin: '0000' });
  const lock = e.call({ action: 'login', nick: '阿杰', pin: '0000' });
  assert.strictEqual(lock.err, 'locked');
  assert.strictEqual(e.call({ action: 'login', nick: '阿杰', pin: '2468' }).err, 'locked', '锁定期间正确 PIN 也不行');
  e.advance(11 * MIN);
  assert.ok(e.call({ action: 'login', nick: '阿杰', pin: '2468' }).ok, '锁定到期后可登录');
});

test('令牌：resume / 过期 / logout', (e) => {
  const r = reg(e, '小红');
  const a = e.call({ action: 'resume', nick: '小红', token: r.token });
  assert.ok(a.ok); assert.strictEqual(a.token, r.token);
  assert.strictEqual(e.call({ action: 'resume', nick: '小红', token: 'bad' }).err, 'bad_token');
  e.call({ action: 'logout', nick: '小红', token: r.token });
  assert.strictEqual(e.call({ action: 'resume', nick: '小红', token: r.token }).err, 'bad_token', 'logout 后令牌失效');
  const l = e.call({ action: 'login', nick: '小红', pin: '4815' });
  e.advance(31 * 86400000);
  assert.strictEqual(e.call({ action: 'resume', nick: '小红', token: l.token }).err, 'bad_token', '30 天后过期');
});

test('成绩：校验规则', (e) => {
  const me = reg(e, '选手');
  const bad = (o, why) => assert.strictEqual(submit(e, me, RUN(o)).err, 'bad_run', why);
  bad({ seconds: 5 }, '用时太短');
  bad({ seconds: 99999 }, '用时太长');
  bad({ level: 0 }, '等级 0');
  bad({ level: 120 }, '等级过大');
  bad({ level: 1.5 }, '等级非整数');
  bad({ kills: -1 }, '击杀为负');
  bad({ kills: 100000 }, '击杀过大');
  bad({ seconds: 60, kills: 5000 }, '击杀速度不可能');
  bad({ seconds: 60, level: 60 }, '升级速度不可能');
  bad({ won: true, seconds: 400, bosses: 4, level: 20, kills: 2000 }, '12 分钟前不可能通关');
  bad({ won: true, seconds: 800, bosses: 0, level: 30, kills: 3000 }, '通关必须击败 Boss');
  assert.strictEqual(e.call({ action: 'submit', nick: '选手', token: 'bad', ...RUN() }).err, 'bad_token');
  assert.strictEqual(e.sheetRows('scores').length, 1, '被拒绝的成绩不应入表');
});

test('成绩：得分公式与客户端一致（共用向量）', (e) => {
  for (const v of vectors) assert.strictEqual(e.ctx.computeScore(v), v.score, JSON.stringify(v));
});

test('成绩：入表、最高记录、提交间隔', (e) => {
  const me = reg(e, '选手');
  e.call({ action: 'saveState', nick: '选手', token: me.token, state: { school: 'fist' } });   // 创建角色的云存档不应影响提交间隔
  const a = e.call({ action: 'submit', nick: '选手', token: me.token, ...RUN({ seconds: 300, level: 12, kills: 800 }) });
  assert.ok(a.ok, JSON.stringify(a)); assert.strictEqual(a.score, 800 + 1200); assert.ok(a.best);
  assert.strictEqual(e.call({ action: 'submit', nick: '选手', token: me.token, ...RUN() }).err, 'too_fast', '连续提交应被限速');
  const b = submit(e, me, RUN({ seconds: 200, level: 8, kills: 300 }));
  assert.ok(b.ok); assert.ok(!b.best, '更低的分数不应刷新最高记录');
  const w = submit(e, me, RUN({ won: true, seconds: 750, level: 38, kills: 6100, bosses: 4 }));
  assert.ok(w.ok); assert.strictEqual(w.score, 20400); assert.ok(w.best);
  assert.strictEqual(w.bests.wins, 1); assert.strictEqual(w.bests.runs, 3); assert.strictEqual(w.bests.winSec, 750);
  const w2 = submit(e, me, RUN({ won: true, seconds: 740, level: 30, kills: 4000, bosses: 4 }));
  assert.strictEqual(w2.bests.winSec, 740, '更快的通关刷新最快记录');
  assert.strictEqual(e.sheetRows('scores').length, 1 + 4);
  assert.deepStrictEqual(w.ranks, { score: 1, speed: 1, level: 1 });
});

test('排行榜：排序、我的名次、封禁排除、条数上限', (e) => {
  const names = [];
  for (let i = 0; i < 25; i++) {
    const n = 'P' + String(i).padStart(2, '0');
    const p = reg(e, n); names.push(n);
    submit(e, p, RUN({ level: 5 + i, kills: 100 + i * 10, seconds: 300 }));
    if (i % 5 === 0) submit(e, p, RUN({ won: true, seconds: 900 - i * 3, level: 30, kills: 3000, bosses: 4 }));
  }
  const b = e.get({ action: 'board', kind: 'score', nick: 'P03' });
  assert.ok(b.ok); assert.strictEqual(b.rows.length, 20); assert.strictEqual(b.total, 25);
  for (let i = 1; i < b.rows.length; i++) assert.ok(b.rows[i - 1].value >= b.rows[i].value, '分数降序');
  assert.ok(b.me && b.me.rank > 0);
  const sp = e.get({ action: 'board', kind: 'speed' });
  assert.strictEqual(sp.rows.length, 5, '只有通关过的人上最快榜');
  for (let i = 1; i < sp.rows.length; i++) assert.ok(sp.rows[i - 1].value <= sp.rows[i].value, '用时升序');
  assert.strictEqual(e.get({ action: 'board', kind: 'level' }).rows[0].value, 30 + 0);
  assert.strictEqual(e.get({ action: 'board', kind: 'xxx' }).err, 'bad_kind');
  // 封禁
  e.ctx.__ask = null;
  e.ui.queue.push('P24');
  e.ctx.adminToggleBan();
  const b2 = e.get({ action: 'board', kind: 'score' });
  assert.ok(!b2.rows.some((r) => r.nick === 'P24'), '被封禁的玩家不上榜');
});

test('云存档：保存 / 随登录返回 / 校验', (e) => {
  const me = reg(e, '存档君');
  assert.ok(e.call({ action: 'saveState', nick: '存档君', token: me.token, state: { school: 'fist' } }).ok);
  assert.strictEqual(e.call({ action: 'saveState', nick: '存档君', token: me.token, state: { school: 'Fist!!' } }).err, 'bad_state');
  assert.strictEqual(e.call({ action: 'saveState', nick: '存档君', token: me.token, state: 'x' }).err, 'bad_state');
  assert.strictEqual(e.call({ action: 'saveState', nick: '存档君', token: me.token, state: { school: 'fist', pad: 'x'.repeat(3000) } }).err, 'bad_state');
  assert.strictEqual(e.call({ action: 'saveState', nick: '存档君', token: 'bad', state: { school: 'fist' } }).err, 'bad_token');
  const l = e.call({ action: 'login', nick: '存档君', pin: '4815' });
  assert.strictEqual(l.school, 'fist'); assert.strictEqual(l.state.school, 'fist');
});

test('局外成长：公式与客户端一致（共用向量）', (e) => {
  for (const v of mv.levels) assert.strictEqual(e.ctx.metaLevel(v.exp), v.level, JSON.stringify(v));
  for (const v of mv.effective) assert.ok(Math.abs(e.ctx.metaEffective(v.points) - v.eff) < 1e-3, JSON.stringify(v));
  for (const v of mv.runExp) assert.strictEqual(e.ctx.metaRunExp(v.score, v.won, v.first, v.comp || 1), v.exp, JSON.stringify(v));
  for (const v of mv.comp) assert.ok(Math.abs(e.ctx.diffComp(v.d) - v.comp) < 1e-9, JSON.stringify(v));
});

test('局外成长：提交成绩得修为；首次通关额外奖励；升级', (e) => {
  const me = reg(e, '修行者');
  assert.strictEqual(me.exp, 0); assert.strictEqual(me.level, 1);
  const r1 = submit(e, me, RUN({ level: 12, kills: 800, seconds: 300 }));   // 得分 2000 → 25 修为
  assert.strictEqual(r1.gained, 25); assert.strictEqual(r1.exp, 25); assert.strictEqual(r1.level, 1); assert.strictEqual(r1.levelUp, false);
  const r2 = submit(e, me, RUN({ level: 12, kills: 800, seconds: 300 }));   // +25 = 50 → Lv2
  assert.strictEqual(r2.level, 2); assert.strictEqual(r2.levelUp, true);
  const w1 = submit(e, me, RUN({ won: true, seconds: 750, level: 38, kills: 6100, bosses: 4 }));   // 20400 → 255 + 40 + 100
  assert.strictEqual(w1.gained, 255 + 40 + 100);
  const w2 = submit(e, me, RUN({ won: true, seconds: 750, level: 38, kills: 6100, bosses: 4 }));
  assert.strictEqual(w2.gained, 255 + 40, '第二次通关没有首胜奖励');
  const l = e.call({ action: 'login', nick: '修行者', pin: '4815' });
  assert.strictEqual(l.exp, r2.exp + 395 + 295);
});

test('局外成长：属性分配校验、与 school 存档合并、重新登录返回', (e) => {
  const me = reg(e, '分配君');
  const save = (alloc) => e.call({ action: 'saveState', nick: '分配君', token: me.token, state: { school: 'fist', alloc } });
  assert.strictEqual(save({ pow: 1 }).err, 'bad_state', '1 级没有属性点');
  for (let i = 0; i < 4; i++) submit(e, me, RUN({ level: 38, kills: 6100, seconds: 750, won: true, bosses: 4 }));   // 大量修为 → 高等级
  const l0 = e.call({ action: 'login', nick: '分配君', pin: '4815' });
  assert.ok(l0.level >= 10);
  const budget = 3 * (l0.level - 1);
  assert.ok(e.call({ action: 'saveState', nick: '分配君', token: l0.token, state: { school: 'fist', alloc: { pow: 10, agi: 5, vit: 0, int: 0, luk: 0 } } }).ok);
  assert.strictEqual(e.call({ action: 'saveState', nick: '分配君', token: l0.token, state: { school: 'fist', alloc: { pow: 100 } } }).err, 'bad_state', '单项上限 99');
  assert.strictEqual(e.call({ action: 'saveState', nick: '分配君', token: l0.token, state: { school: 'fist', alloc: { pow: 1.5 } } }).err, 'bad_state');
  assert.strictEqual(e.call({ action: 'saveState', nick: '分配君', token: l0.token, state: { school: 'fist', alloc: { pow: -1 } } }).err, 'bad_state');
  assert.strictEqual(e.call({ action: 'saveState', nick: '分配君', token: l0.token, state: { school: 'fist', alloc: { pow: budget + 1 } } }).err, 'bad_state', '超过可用点数');
  assert.strictEqual(e.call({ action: 'saveState', nick: '分配君', token: l0.token, state: { school: 'fist', alloc: { hax: 5 } } }).err, undefined, '多余的键被忽略');
  assert.ok(e.call({ action: 'saveState', nick: '分配君', token: l0.token, state: { school: 'fist', alloc: { pow: 10, agi: 5 } } }).ok);
  assert.ok(e.call({ action: 'saveState', nick: '分配君', token: l0.token, state: { school: 'fist' } }).ok);   // 只带 school：不抹掉分配
  const l1 = e.call({ action: 'login', nick: '分配君', pin: '4815' });
  assert.strictEqual(l1.alloc.pow, 10); assert.strictEqual(l1.alloc.agi, 5); assert.strictEqual(l1.school, 'fist');
});

const WIN = () => RUN({ won: true, seconds: 750, level: 38, kills: 6100, bosses: 4 });
function levelUp(e, nick) { for (let i = 0; i < 4; i++) submit(e, nick, WIN()); return e.call({ action: 'login', nick: nick.nick, pin: '4815' }); }
const saveSt = (e, who, state) => e.call({ action: 'saveState', nick: who.nick, token: who.token, state });

test('天赋：节点表与 game_data.json 一致；校验规则', (e) => {
  const d = JSON.parse(fs.readFileSync(path.join(__dirname, '..', '..', 'data', 'game_data.json'), 'utf8'));
  const want = {};
  for (const [b, bd] of Object.entries(d.talents.branches)) bd.rows.forEach((row, r) => row.forEach((n) => { want[n.id] = [b, r, n.max]; }));
  assert.deepStrictEqual(JSON.parse(JSON.stringify(e.ctx.TALENTS)), want, '节点表不同步：运行 python3 tools/sync_talents.py');
  assert.strictEqual(e.ctx.TALENT_GATE, d.talents.row_gate);
  assert.deepStrictEqual(JSON.parse(JSON.stringify(e.ctx.GEAR.slots)), d.gear.slots.map((s) => s.id));
  assert.deepStrictEqual(JSON.parse(JSON.stringify(e.ctx.GEAR.weights)), d.gear.rarity.map((r) => r.weight));
  const me = reg(e, '天赋君'); const l0 = levelUp(e, me);
  const lv = l0.level; assert.ok(lv >= 10);
  const ok1 = (t) => saveSt(e, l0, { school: 'fist', talents: t });
  assert.ok(ok1({ gang_force: 3, gang_body: 2 }).ok, '第 0 层随便加');
  assert.strictEqual(ok1({ gang_crit: 1 }).err, 'bad_state', '第 1 层需要更低层投入 ≥3');
  assert.ok(ok1({ gang_force: 3, gang_crit: 3 }).ok, '低层 3 点解锁第 1 层');
  assert.strictEqual(ok1({ gang_force: 4 }).err, 'bad_state', '超过节点上限');
  assert.strictEqual(ok1({ nope: 1 }).err, 'bad_state', '未知节点');
  assert.strictEqual(ok1({ gang_force: 1.5 }).err, 'bad_state');
  assert.strictEqual(ok1({ gang_force: -1 }).err, 'bad_state');
  assert.strictEqual(ok1({ gang_peak: 1 }).err, 'bad_state', '第 6 层需要低层 18 点');
  assert.ok(ok1({ rou_regen: 3, ling_step: 3 }).ok, '三系可以同时加');
  // 总点数不超过等级：把三系前几层都加满试探
  const big = {}; let n = 0; for (const [id, v] of Object.entries(e.ctx.TALENTS)) { if (v[1] <= 2) { big[id] = v[2]; n += v[2]; } }
  assert.ok(n > lv, '测试前提：这组点数应超过可用点数 ' + n + ' vs ' + lv);
  assert.strictEqual(ok1(big).err, 'bad_state', '超过局外等级的总点数');
  assert.strictEqual(e.call({ action: 'login', nick: '天赋君', pin: '4815' }).talents.rou_regen, 3, '随登录返回');
  assert.ok(saveSt(e, e.call({ action: 'login', nick: '天赋君', pin: '4815' }), { school: 'fist' }).ok);
  assert.strictEqual(e.call({ action: 'login', nick: '天赋君', pin: '4815' }).talents.ling_step, 3, '只带 school 不抹掉天赋');
});

test('装备：通关掉落（服务器发放）、穿戴 / 丢弃校验、不能伪造', (e) => {
  const me = reg(e, '装备君');
  const r0 = submit(e, me, RUN());
  assert.deepStrictEqual(JSON.parse(JSON.stringify(r0.drops)), [], '阵亡不掉落');
  const w = submit(e, me, WIN());
  assert.ok(w.drops.length >= 4 && w.drops.length <= 5, '通关（3 个小 Boss + 大 Boss）掉 4~5 件');
  w.drops.forEach((c) => assert.ok(e.ctx.gearValid(c), c));
  let l = e.call({ action: 'login', nick: '装备君', pin: '4815' });
  assert.deepStrictEqual(JSON.parse(JSON.stringify(l.items)), JSON.parse(JSON.stringify(w.drops)), '背包 = 掉落');
  const code = w.drops[0], slot = code.split('.')[0];
  const s = (state) => saveSt(e, l, Object.assign({ school: 'fist' }, state));
  const relog = () => { l = e.call({ action: 'login', nick: '装备君', pin: '4815' }); return l; };
  assert.strictEqual(s({ equip: { [slot]: 'weapon.4.123456' } }).err, 'bad_state', '没发过的编码不能穿');
  assert.strictEqual(s({ equip: { [slot === 'weapon' ? 'coat' : 'weapon']: code } }).err, 'bad_state', '不能穿到别的部位');
  assert.strictEqual(s({ equip: { hat: code } }).err, 'bad_state', '没有这个部位');
  assert.strictEqual(s({ items: ['weapon.4.1'] }).ok, true, '客户端发来的 items 被忽略');
  assert.strictEqual(relog().items.length, w.drops.length, 'items 不能被客户端改写');
  assert.ok(s({ equip: { [slot]: code } }).ok);
  relog();
  assert.strictEqual(l.equip[slot], code);
  assert.strictEqual(s({ discard: ['weapon.0.999'] }).err, 'bad_state', '丢弃不存在的装备');
  assert.ok(s({ discard: [code] }).ok);
  relog();
  assert.ok(!l.items.includes(code) && !l.equip[slot], '丢弃后也不再穿着');
});

test('装备：背包上限，超过时先丢最低稀有度的未穿戴装备', (e) => {
  const me = reg(e, '背包君');
  for (let i = 0; i < 60; i++) submit(e, me, WIN());
  const l = e.call({ action: 'login', nick: '背包君', pin: '4815' });
  assert.ok(l.items.length <= e.ctx.GEAR.invMax, '背包 ' + l.items.length);
  assert.strictEqual(l.items.length, e.ctx.GEAR.invMax, '60 次通关 ≥ 60 件，应已满');
});

test('地图：按地图校验通关时长；通关记录；光明顶不再要求通关黑风寨', (e) => {
  const me = reg(e, '地图君');
  assert.strictEqual(submit(e, me, RUN({ won: true, seconds: 600, level: 30, kills: 3000, bosses: 4 })).err, 'bad_run', '黑风寨 600 秒通关太快');
  assert.strictEqual(submit(e, me, RUN({ map: 'nowhere' })).err, 'bad_run', '没有这张地图');
  assert.notStrictEqual(submit(e, me, RUN({ map: 'guangming' })).err, 'locked', '光明顶不再要求通关黑风寨');
  let l = e.call({ action: 'login', nick: '地图君', pin: '4815' });
  assert.strictEqual(JSON.stringify(l.cleared), '{}');
  const w = submit(e, l, RUN({ won: true, seconds: 640, level: 30, kills: 3000, bosses: 4 }));
  assert.ok(w.ok, JSON.stringify(w));
  l = e.call({ action: 'login', nick: '地图君', pin: '4815' });
  assert.strictEqual(l.cleared.black_wind, true, '通关记录');
  assert.ok(saveSt(e, l, { school: 'fist', cleared: { guangming: true } }).ok);
  l = e.call({ action: 'login', nick: '地图君', pin: '4815' });
  assert.ok(!l.cleared.guangming, '客户端不能自己写通关记录');
  assert.strictEqual(submit(e, l, RUN({ map: 'guangming', won: true, seconds: 820, level: 30, kills: 3000, bosses: 4 })).ok, true, '通关后可以打光明顶');
});

test('分地图榜：每张地图单独排名；旧成绩迁移为黑风寨；全部榜不变', (e) => {
  reg(e, '榜甲'); reg(e, '榜乙'); reg(e, '榜丙');
  const lg = (n) => e.call({ action: 'login', nick: n, pin: '4815' });
  const a = lg('榜甲'), b = lg('榜乙'), c = lg('榜丙');
  // 乙、丙各打一局黑风寨
  submit(e, b, RUN({ level: 10, kills: 500, seconds: 300 }));
  submit(e, c, RUN({ level: 20, kills: 1500, seconds: 300 }));
  // 甲：先通关黑风寨，再打光明顶
  const w1 = submit(e, a, RUN({ won: true, seconds: 640, level: 30, kills: 3000, bosses: 4 }));
  assert.ok(w1.ok, JSON.stringify(w1));
  const w2 = submit(e, a, RUN({ map: 'guangming', won: true, seconds: 820, level: 30, kills: 6000, bosses: 4 }));
  assert.ok(w2.ok, JSON.stringify(w2));
  const bw = e.get({ action: 'board', kind: 'score', map: 'black_wind' });
  assert.ok(bw.ok); assert.strictEqual(bw.map, 'black_wind'); assert.strictEqual(bw.total, 3, '三人都打过黑风寨');
  const gm = e.get({ action: 'board', kind: 'score', map: 'guangming', nick: '榜甲' });
  assert.strictEqual(gm.total, 1, '光明顶只有甲'); assert.strictEqual(gm.rows[0].nick, '榜甲'); assert.strictEqual(gm.me.rank, 1);
  const gsp = e.get({ action: 'board', kind: 'speed', map: 'guangming' });
  assert.strictEqual(gsp.rows[0].value, 820);
  const bsp = e.get({ action: 'board', kind: 'speed', map: 'black_wind' });
  assert.strictEqual(bsp.rows.length, 1); assert.strictEqual(bsp.rows[0].value, 640, '黑风寨最快通关不受光明顶成绩影响');
  assert.strictEqual(e.get({ action: 'board', kind: 'score', map: 'nowhere' }).err, 'bad_map');
  assert.strictEqual(e.get({ action: 'board', kind: 'score' }).total, 3, '不带地图 = 全部榜，和以前一样');
  // 旧数据迁移：模拟「改版前」的玩家（有总成绩、没有 mapBests）第一次提交光明顶 / 黑风寨成绩
  reg(e, '榜丁');
  const pl = e.sheetRows('players');
  const di = pl.findIndex((r) => r[0] === '榜丁');
  assert.ok(di > 0);
  const hdr = pl[0];
  const col = (n) => hdr.findIndex((h) => String(h).startsWith(n));
  pl[di][col('最高分')] = 5000;
  pl[di][col('最高等级')] = 25;
  const dl = lg('榜丁');
  const old = e.get({ action: 'board', kind: 'score', map: 'black_wind' });
  assert.ok(!old.rows.some((r) => r.nick === '榜丁'), '没有 mapBests 之前不上地图榜');
  assert.ok(submit(e, dl, RUN({ level: 8, kills: 300, seconds: 200 })).ok);
  const mig = e.get({ action: 'board', kind: 'score', map: 'black_wind' });
  const mine = mig.rows.find((r) => r.nick === '榜丁');
  assert.ok(mine && mine.value >= 5000, '旧总成绩迁移为黑风寨成绩：' + JSON.stringify(mine));
});

test('难度奖励：修为倍率 / 装备数量与稀有度随综合难度提高；非法难度按 100% 算', (e) => {
  const me = reg(e, '难度君');
  const hard = { count: 300, hp: 300, speed: 300 };
  const a = submit(e, me, Object.assign(RUN({ level: 12, kills: 800, seconds: 300 }), {}));                    // 2000 分 → 25
  const b = submit(e, me, Object.assign(RUN({ level: 12, kills: 800, seconds: 300 }), { difficulty: hard }));   // ×2 → 50
  assert.strictEqual(a.gained, 25); assert.strictEqual(b.gained, 50); assert.strictEqual(b.comp, 3);
  const bad = submit(e, me, Object.assign(RUN({ level: 12, kills: 800, seconds: 300 }), { difficulty: { count: 999, hp: 'x', speed: 155 } }));
  assert.strictEqual(bad.gained, 25, '非法的难度当 100%'); assert.strictEqual(bad.comp, 1);
  // 装备：统计 150 次通关的高稀有度占比（难度只提高稀有度，不改变件数）
  const stat = (diff) => {
    const p = reg(e, diff ? '难度高' : '难度低'); let n = 0, high = 0, total = 0;
    for (let i = 0; i < 150; i++) {
      const w = submit(e, p, Object.assign(WIN(), diff ? { difficulty: diff } : {}));
      n += w.drops.length;
      w.drops.forEach((c) => { total++; if (Number(c.split('.')[1]) >= 1) high++; });
    }
    return { n, rate: high / total };
  };
  const lo = stat(null), hi = stat(hard);
  assert.ok(Math.abs(hi.n - lo.n) < lo.n * 0.25, '难度不改变掉落件数 ' + lo.n + ' vs ' + hi.n);
  assert.ok(hi.rate > lo.rate + 0.12, '难度 300%：特别 / 稀有 / 传说占比更高 ' + lo.rate.toFixed(3) + ' → ' + hi.rate.toFixed(3));
});

test('装备：四档稀有度按 60 / 30 / 9 / 1 掉落；难度按比例提高后三档', (e) => {
  const roll = (comp) => { const c = [0, 0, 0, 0]; for (let i = 0; i < 20000; i++) c[Number(e.ctx.gearRoll(comp).split('.')[1])]++; return c.map((x) => x / 20000); };
  const base = roll(1);
  [0.60, 0.30, 0.09, 0.01].forEach((want, i) => assert.ok(Math.abs(base[i] - want) < Math.max(0.012, want * 0.3), `稀有度 ${i}：${base[i]} vs ${want}`));
  const hard = roll(3);
  assert.ok(hard[1] > base[1] && hard[2] > base[2] * 1.7 && hard[3] > base[3] * 1.8, '难度 ×3：特别 / 稀有 / 传说都按比例提高 ' + hard.join(','));
  assert.ok(hard[0] < base[0], '普通相应减少');
});

test('装备：小 Boss 固定掉 1 件，大 Boss（通关）掉 1~2 件；小 Boss 数量不能超过用时内已刷出的个数', (e) => {
  const me = reg(e, '掉落君');
  const r1 = submit(e, me, RUN({ seconds: 200, bosses: 1, level: 12, kills: 800 }));         // 3:00 的小 Boss 已刷出
  assert.strictEqual(r1.drops.length, 1, '阵亡也掉：1 个小 Boss = 1 件');
  const r2 = submit(e, me, RUN({ seconds: 420, bosses: 2, level: 20, kills: 1500 }));        // 6:30 后两个
  assert.strictEqual(r2.drops.length, 2);
  const r3 = submit(e, me, RUN({ seconds: 100, bosses: 3, level: 8, kills: 300 }));          // 才 100 秒不可能杀 3 个小 Boss
  assert.strictEqual(r3.drops.length, 0, '用时不够，不掉');
  const r4 = submit(e, me, RUN({ seconds: 250, bosses: 0, level: 10, kills: 500 }));
  assert.strictEqual(r4.drops.length, 0, '没杀 Boss 不掉');
  let ones = 0, twos = 0;
  for (let i = 0; i < 60; i++) { const w = submit(e, me, WIN()); const n = w.drops.length - 3; /* WIN：bosses 4 = 3 小 + 1 大 */ if (n === 1) ones++; else if (n === 2) twos++; else assert.fail('大 Boss 掉落 ' + n); }
  assert.ok(ones > 10 && twos > 10, '大 Boss 1 件 / 2 件都会出现 ' + ones + '/' + twos);
});

test('装备：旧存档里的 5 档稀有度编码自动降到第 4 档', (e) => {
  const me = reg(e, '老玩家');
  setState(e, '老玩家', (st) => { st.items = ['weapon.4.123', 'coat.1.5']; st.equip = { weapon: 'weapon.4.123' }; st.enh = { 'weapon.4.123': 3 }; });
  const l = e.call({ action: 'login', nick: '老玩家', pin: '4815' });
  assert.deepStrictEqual(JSON.parse(JSON.stringify(l.items)), ['weapon.3.123', 'coat.1.5']);
  assert.strictEqual(l.equip.weapon, 'weapon.3.123'); assert.strictEqual(l.enh['weapon.3.123'], 3);
});

function setState(e, nick, fn) { const f = e.ctx.findPlayer(nick); const st = JSON.parse(f.row[e.ctx.P.state] || '{}'); fn(st); f.row[e.ctx.P.state] = JSON.stringify(st); e.ctx.savePlayer(f); }

test('银两 / 强化：费用与银两公式和客户端一致（共用向量）', (e) => {
  ev.cost.forEach((row, r) => row.forEach((c, lv) => assert.strictEqual(e.ctx.enhCost(r, lv), c, `强化费用 稀有度${r} +${lv}`)));
  ev.silver.forEach(([score, won, comp, want]) => assert.strictEqual(e.ctx.silverForRun(score, won, comp), want, `银两 ${score} ${won} ${comp}`));
});

test('银两：每局结算得银两（阵亡也有），难度越高越多；登录返回', (e) => {
  const me = reg(e, '银两君');
  const a = submit(e, me, RUN({ level: 12, kills: 800, seconds: 300 }));      // 2000 分 → 17
  assert.strictEqual(a.silverGained, 17); assert.strictEqual(a.silver, 17);
  const b = submit(e, me, Object.assign(RUN({ level: 12, kills: 800, seconds: 300 }), { difficulty: { count: 300, hp: 300, speed: 300 } }));
  assert.strictEqual(b.silverGained, 34); assert.strictEqual(b.silver, 51);
  const l = e.call({ action: 'login', nick: '银两君', pin: '4815' });
  assert.strictEqual(l.silver, 51); assert.strictEqual(JSON.stringify(l.enh), '{}');
  const w = submit(e, l, WIN());
  assert.ok(w.silverGained >= 60, '通关有额外银两 ' + JSON.stringify(w));
});

test('强化：消耗银两、等级写入服务器、上限、校验；丢弃装备换银两并清除强化', (e) => {
  const me = reg(e, '铁匠客');
  const w = submit(e, me, WIN());
  const code = w.drops[0], r = Number(code.split('.')[1]);
  const E = (c) => e.call({ action: 'enhance', nick: '铁匠客', token: me.token, code: c });
  assert.strictEqual(E('weapon.0.777777').err, 'bad_state', '没有的装备不能强化');
  assert.strictEqual(E('乱写').err, 'bad_state');
  setState(e, '铁匠客', (st) => { st.silver = 0; });
  assert.strictEqual(E(code).err, 'no_silver', '银两不够');
  setState(e, '铁匠客', (st) => { st.silver = 100000; });
  let silver = 100000;
  for (let lv = 0; lv < e.ctx.GEAR.enh.max; lv++) {
    const x = E(code);
    assert.ok(x.ok, JSON.stringify(x));
    silver -= ev.cost[r][lv];
    assert.strictEqual(x.cost, ev.cost[r][lv]); assert.strictEqual(x.silver, silver); assert.strictEqual(x.level, lv + 1);
  }
  assert.strictEqual(E(code).err, 'enh_max', '到顶了');
  let l = e.call({ action: 'login', nick: '铁匠客', pin: '4815' });
  assert.strictEqual(l.enh[code], 10); assert.strictEqual(l.silver, silver, '登录返回强化等级和银两');
  // 客户端不能自己改 silver / enh
  saveSt(e, l, { school: 'fist', silver: 999999, enh: { [code]: 0 } });
  l = e.call({ action: 'login', nick: '铁匠客', pin: '4815' });
  assert.strictEqual(l.silver, silver, '客户端不能改银两'); assert.strictEqual(l.enh[code], 10, '客户端不能改强化等级');
  // 丢弃：换银两、清掉强化
  const d = saveSt(e, l, { school: 'fist', discard: [code] });
  assert.ok(d.ok);
  assert.strictEqual(d.silver, silver + e.ctx.GEAR.silver.discard[r]);
  assert.ok(!(code in d.enh), '丢弃后强化记录清除');
});

test('反馈：入表、类型兜底、限流', (e) => {
  const me = reg(e, '提意见');
  assert.strictEqual(e.call({ action: 'feedback', nick: '提意见', token: me.token, type: 'bug', comment: '' }).err, 'bad_feedback');
  assert.ok(e.call({ action: 'feedback', nick: '提意见', token: me.token, type: 'bug', where: '战斗', comment: '卡住了' }).ok);
  assert.ok(e.call({ action: 'feedback', nick: '提意见', token: me.token, type: '乱写', comment: '建议加音效' }).ok);
  const rows = e.sheetRows('feedback');
  assert.strictEqual(rows[2][3], 'other'); assert.strictEqual(rows[1][7], '待处理');
  for (let i = 0; i < 18; i++) e.call({ action: 'feedback', nick: '提意见', token: me.token, comment: '第' + i + '条' });
  assert.strictEqual(e.call({ action: 'feedback', nick: '提意见', token: me.token, comment: '太多了' }).err, 'too_many');
  e.advance(25 * 3600000);
  assert.ok(e.call({ action: 'feedback', nick: '提意见', token: me.token, comment: '隔天又可以了' }).ok);
});

test('日志：登录用户写入，未登录丢弃', (e) => {
  const me = reg(e, '记录员');
  const before = e.sheetRows('logs').length;
  assert.ok(e.call({ action: 'log', nick: '记录员', token: 'bad', kind: 'error', message: 'x' }).ok);
  assert.strictEqual(e.sheetRows('logs').length, before, '未登录的日志被丢弃');
  assert.ok(e.call({ action: 'log', nick: '记录员', token: me.token, kind: 'error', message: '出错了', where: 'world.gd', detail: '栈' }).ok);
  assert.strictEqual(e.sheetRows('logs').length, before + 1);
});

test('后台：新建邀请码 / 重设 PIN / 封禁 / 清空排行榜', (e) => {
  e.ui.queue.push('新朋友', '3', '', '');
  const code = e.ctx.adminNewInvite();
  assert.ok(/^[A-Z2-9]{6}$/.test(code));
  assert.ok(reg(e, '新人1', '4815', code).ok);
  const me = reg(e, '忘记PIN的人', '1111');
  e.ui.queue.push('忘记PIN的人', '2222');
  e.ctx.adminResetPin();
  assert.strictEqual(e.call({ action: 'login', nick: '忘记PIN的人', pin: '1111' }).err, 'bad_login', '旧 PIN 失效');
  assert.ok(e.call({ action: 'login', nick: '忘记PIN的人', pin: '2222' }).ok, '新 PIN 可用');
  assert.strictEqual(e.call({ action: 'resume', nick: '忘记PIN的人', token: me.token }).err, 'bad_token', '重设后旧令牌失效');
  // 开启 / 关闭邀请码
  e.ui.queue.push('abc234'); e.ctx.adminToggleInvite();
  assert.strictEqual(reg(e, '关了之后', '4815', 'ABC234').err, 'code_closed', '关闭后不能再用它注册');
  assert.ok(e.call({ action: 'login', nick: '新人1', pin: '4815' }).ok, '已注册的玩家不受影响');
  e.ui.queue.push('ABC234'); e.ctx.adminToggleInvite();
  assert.ok(reg(e, '开了之后', '4815', 'ABC234').ok, '重新开启后可以注册');
  e.ui.queue.push('XXXXXX'); e.ctx.adminToggleInvite();
  assert.ok(String(e.ui.alerts[e.ui.alerts.length - 1]).includes('找不到'));
  // 新建邀请码：带名单和到期日期
  e.ui.queue.push('限定', '1', '甲一, 乙二', '2099-12-31');
  const vip = e.ctx.adminNewInvite();
  assert.strictEqual(reg(e, '丙三', '4815', vip).err, 'not_on_roster');
  assert.ok(reg(e, '甲一', '4815', vip).ok);
  assert.strictEqual(reg(e, '乙二', '4815', vip).err, 'code_full', '人数上限 1');
  e.ui.queue.push('坏日期', '0', '', '明年');
  assert.strictEqual(e.ctx.adminNewInvite(), undefined, '日期格式不对不应创建');
  // 封禁后不能登录 / 续期
  const b = reg(e, '捣蛋鬼');
  e.ui.queue.push('捣蛋鬼'); e.ctx.adminToggleBan();
  assert.strictEqual(e.call({ action: 'login', nick: '捣蛋鬼', pin: '4815' }).err, 'banned');
  assert.strictEqual(e.call({ action: 'resume', nick: '捣蛋鬼', token: b.token }).err, 'bad_token');
  e.ui.queue.push('捣蛋鬼'); e.ctx.adminToggleBan();
  assert.ok(e.call({ action: 'login', nick: '捣蛋鬼', pin: '4815' }).ok, '解封后可登录');
  // 清空排行榜
  const s = reg(e, '选手Z'); submit(e, s, RUN());
  assert.ok(e.sheetRows('scores').length > 1);
  e.ctx.adminClearScores();
  assert.strictEqual(e.sheetRows('scores').length, 1);
  assert.strictEqual(e.get({ action: 'board', kind: 'score' }).total, 0);
  assert.ok(e.call({ action: 'login', nick: '选手Z', pin: '4815' }).ok, '账号保留');
});

let failed = 0;
for (const mode of ['plain', 'smart']) {
  for (const c of cases) {
    try { c.fn(env(mode)); console.log(`  ✓ [${mode}] ${c.name}`); }
    catch (err) { failed++; console.log(`  ✗ [${mode}] ${c.name}\n      ${String(err.stack || err).split('\n').slice(0, 4).join('\n      ')}`); }
  }
}
console.log(failed ? `\n失败 ${failed} 项` : `\n全部通过（${cases.length} 个用例 × 2 种表格模式）`);
process.exit(failed ? 1 : 0);
