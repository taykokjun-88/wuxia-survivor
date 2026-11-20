/**
 * 武侠幸存者 · 后端（Google Apps Script，绑定在一个 Google 表格上）
 *
 * 模式参照「知识岛」：
 *   - 玩家 Players   ≈ 学生 Students：PIN 加盐哈希（salt + pinHash）、会话令牌（token + tokenExp）、失败锁定（fails + lockUntil）
 *   - 邀请 Invites   ≈ 班级 Classes ：凭邀请码才能注册（可限次数、可关闭）
 *   - 日志 Logs / 反馈 Feedback 同名同结构
 *   - 排行 Scores    ≈ Fun Math Leaderboard：追加式的成绩表
 * 后台就是这张表本身（直接改单元格即可）+ 表格上方的「武侠后台」菜单。
 *
 * 接口：Web 应用，POST（Content-Type: text/plain 的 JSON，避免 CORS 预检）或 GET（只读：ping / board）。
 * 部署步骤见 backend/README.md。
 */

var VERSION = 1;

var SHEETS = {
  invites:  '邀请 Invites',
  players:  '玩家 Players',
  scores:   '排行 Scores',
  logs:     '日志 Logs',
  feedback: '反馈 Feedback'
};

var HEADERS = {
  invites:  ['代码 Code', '名称 Name', '开放 Active', '建立 Created', '可用次数 MaxUses(0=不限)', '已用 Used', '备注 Note',
             '昵称名单 Roster(可选，逗号分隔)', '到期 Expires(可选，填日期=当天有效)'],
  players:  ['昵称 Nickname', '邀请码 Invite', 'salt', 'pinHash', '建立 Created', '最后登入 Last login', 'token', 'tokenExp',
             'fails', 'lockUntil', '封禁 Banned', '最后更新 Updated', '局数 Runs', '通关 Wins', '最高分 BestScore',
             '最快通关秒 BestWinSec', '最高等级 BestLevel', '总击杀 Kills', '流派 School', 'state', '最后提交 LastSubmit', '修为 Exp'],
  scores:   ['时间 Time', '昵称 Nickname', '结果 Result', '得分 Score', '用时秒 Seconds', '等级 Level', '击杀 Kills',
             '击败Boss数 Bosses', '流派 School', '起手 Starter', '轻功 Qinggong', '强化 Enhance', '构筑 Build', '版本 Version', '设备 Device'],
  logs:     ['时间 Time', '类型 Kind', '昵称 Nickname', '信息 Message', '位置 Where', '详情 Detail', '设备 Device'],
  feedback: ['id', '时间 Time', '昵称 Nickname', '类型 Type', '位置 Where', '留言 Comment', '设备 Device', '状态 Status', '处理时间 Done at']
};

var CFG = {
  TOKEN_DAYS: 30,
  MAX_FAILS: 5,
  LOCK_MIN: 10,
  NICK_RE: /^[一-龥A-Za-z0-9_\-·]{2,12}$/,
  PIN_RE: /^\d{4,8}$/,
  BOARD_SIZE: 20,
  MAX_SECONDS: 1800,
  SUBMIT_GAP_SEC: 20,
  FEEDBACK_PER_DAY: 20,
  STATE_MAX: 2000,        // 客户端一次能发来的存档大小
  STATE_STORE_MAX: 8000   // 服务器保存的存档总大小（含背包）
};

// 列下标（0 起）
var P = { nick: 0, invite: 1, salt: 2, hash: 3, created: 4, last: 5, token: 6, exp: 7, fails: 8, lock: 9, banned: 10,
          updated: 11, runs: 12, wins: 13, bestScore: 14, bestWin: 15, bestLevel: 16, kills: 17, school: 18, state: 19, lastSubmit: 20, xp: 21 };

// ---------------------------------------------------------------- 时间 / 工具
function now() { return new Date().getTime(); }
function iso(ms) { return new Date(ms === undefined ? now() : ms).toISOString(); }
/** 单元格里的时间 → 毫秒。Google 表格会把 ISO 字符串自动转成 Date 对象，两种都要认。 */
function toMs(v) {
  if (v instanceof Date) return v.getTime();
  var t = Date.parse(v);
  return isFinite(t) ? t : 0;
}

/** 昵称名单：逗号/顿号/分号/空白/换行分隔，不分大小写 */
function parseRoster(v) {
  return String(v === undefined || v === null ? '' : v).split(/[,，、;；\s]+/)
    .map(function (x) { return x.trim().toLowerCase(); }).filter(function (x) { return x !== ''; });
}

/** 到期时刻（毫秒）。只填了日期（0 点整）视为当天有效，到当天结束；空值返回 0 = 不限 */
function expiryEnd(v) {
  if (v === '' || v === undefined || v === null) return 0;
  var ms = toMs(v);
  if (!ms) return 0;
  var d = new Date(ms);
  if (d.getHours() === 0 && d.getMinutes() === 0 && d.getSeconds() === 0) ms += 86400000 - 1;
  return ms;
}

function truthy(v) {
  var s = String(v).toLowerCase();
  return v === true || s === 'true' || s === '1' || s === '是' || s === 'yes' || s === 'y';
}

function sha256hex(text) {
  var bytes = Utilities.computeDigest(Utilities.DigestAlgorithm.SHA_256, text, Utilities.Charset.UTF_8);
  return bytes.map(function (b) { return ('0' + ((b < 0 ? b + 256 : b) & 0xff).toString(16)).slice(-2); }).join('');
}

function hashPin(salt, pin) { return sha256hex(salt + ':' + pin); }
function newSalt() { return Utilities.getUuid().replace(/-/g, ''); }
function newToken() { return (Utilities.getUuid() + Utilities.getUuid()).replace(/-/g, ''); }

function out(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj)).setMimeType(ContentService.MimeType.JSON);
}
function ok(extra) { var o = { ok: true }; for (var k in extra) o[k] = extra[k]; return o; }
function fail(err, msg, extra) { var o = { ok: false, err: err, msg: msg }; for (var k in extra) o[k] = extra[k]; return o; }

function book() { return SpreadsheetApp.getActiveSpreadsheet(); }
function sheet(key) {
  var s = book().getSheetByName(SHEETS[key]);
  if (!s) { setup(); s = book().getSheetByName(SHEETS[key]); }
  return s;
}

function str(v, max) { return String(v === undefined || v === null ? '' : v).slice(0, max); }
function num(v) { var n = Number(v); return isFinite(n) ? n : NaN; }

// ---------------------------------------------------------------- 初始化（可重复运行）
function setup() {
  var ss = book();
  Object.keys(SHEETS).forEach(function (key) {
    var s = ss.getSheetByName(SHEETS[key]);
    if (!s) s = ss.insertSheet(SHEETS[key]);
    var h = HEADERS[key];
    var cur = s.getRange(1, 1, 1, h.length).getValues()[0];
    var same = true;
    for (var i = 0; i < h.length; i++) if (cur[i] !== h[i]) same = false;
    if (!same) s.getRange(1, 1, 1, h.length).setValues([h]);
    s.setFrozenRows(1);
  });
  // 这些列必须是纯文本：否则昵称 "007" 会变成数字 7，长十六进制串可能被当成科学计数法
  var TEXT_COLS = { invites: [1, 8], players: [1, 2, 3, 4, 7], scores: [2], logs: [3], feedback: [1, 3] };
  Object.keys(TEXT_COLS).forEach(function (key) {
    var s = ss.getSheetByName(SHEETS[key]);
    TEXT_COLS[key].forEach(function (c) { s.getRange(1, c, s.getMaxRows(), 1).setNumberFormat('@'); });
  });
  return 'ok';
}

// ---------------------------------------------------------------- 入口
function doGet(e) {
  var p = (e && e.parameter) || {};
  var res;
  try {
    if (p.action === 'ping') res = ok({ v: VERSION, time: iso() });
    else if (p.action === 'board') res = board(p);
    else res = fail('bad_action', '未知请求');
  } catch (err) { res = serverError(err, 'doGet'); }
  return out(res);
}

function doPost(e) {
  var res;
  try {
    var req = JSON.parse((e && e.postData && e.postData.contents) || '{}');
    res = dispatch(req);
  } catch (err) { res = serverError(err, 'doPost'); }
  return out(res);
}

function serverError(err, where) {
  try { writeLog('error', '', String(err && err.message || err), where, String(err && err.stack || ''), ''); } catch (e2) {}
  return fail('server', '服务器出错了，请稍后再试');
}

function dispatch(req) {
  var a = req.action;
  if (a === 'ping') return ok({ v: VERSION, time: iso() });
  if (a === 'board') return board(req);
  var lock = LockService.getScriptLock();
  lock.waitLock(15000);
  try {
    switch (a) {
      case 'register':  return register(req);
      case 'login':     return login(req);
      case 'resume':    return resume(req);
      case 'logout':    return logout(req);
      case 'submit':    return submitScore(req);
      case 'saveState': return saveState(req);
      case 'enhance':   return enhanceGear(req);
      case 'feedback':  return addFeedback(req);
      case 'log':       return addLog(req);
    }
  } finally { lock.releaseLock(); }
  return fail('bad_action', '未知请求');
}

// ---------------------------------------------------------------- 玩家读写
function loadPlayers() {
  var s = sheet('players');
  var last = s.getLastRow();
  if (last < 2) return { sheet: s, rows: [] };
  return { sheet: s, rows: s.getRange(2, 1, last - 1, HEADERS.players.length).getValues() };
}

/** 返回 {idx(0起，对应表格行 idx+2), row, sheet} 或 null；昵称不分大小写 */
function findPlayer(nick) {
  var pl = loadPlayers();
  var want = String(nick || '').trim().toLowerCase();
  for (var i = 0; i < pl.rows.length; i++) {
    if (String(pl.rows[i][P.nick]).toLowerCase() === want && want !== '') return { idx: i, row: pl.rows[i], sheet: pl.sheet };
  }
  return null;
}

function savePlayer(found) {
  found.sheet.getRange(found.idx + 2, 1, 1, HEADERS.players.length).setValues([found.row]);
}

/** 邀请码 → 群名称（邀请表里的「名称」列）；找不到返回空串 */
function groupName(code) {
  var inv = sheet('invites');
  var last = inv.getLastRow();
  if (last < 2 || !code) return '';
  var rows = inv.getRange(2, 1, last - 1, 2).getValues();
  for (var i = 0; i < rows.length; i++) if (String(rows[i][0]).toUpperCase() === String(code).toUpperCase()) return String(rows[i][1]);
  return '';
}

function profile(row) {
  var state = readState(row);
  var xp = Math.max(0, Math.floor(Number(row[P.xp]) || 0));
  return {
    nick: row[P.nick], school: String(row[P.school] || ''), state: state,
    exp: xp, level: metaLevel(xp), alloc: state.alloc || {},
    talents: state.talents || {}, items: state.items || [], equip: state.equip || {},
    silver: Math.max(0, Math.floor(Number(state.silver) || 0)), enh: state.enh || {}, cleared: state.cleared || {},
    invite: String(row[P.invite] || ''), group: groupName(row[P.invite]),
    bests: { score: Number(row[P.bestScore]) || 0, winSec: Number(row[P.bestWin]) || 0, level: Number(row[P.bestLevel]) || 0,
             runs: Number(row[P.runs]) || 0, wins: Number(row[P.wins]) || 0 }
  };
}

/** 校验昵称 + 令牌；成功返回 found，失败返回 {err: 响应对象} */
function authed(req) {
  var f = findPlayer(req.nick);
  if (!f || !req.token || String(f.row[P.token]) !== String(req.token) || Number(f.row[P.exp]) < now())
    return { err: fail('bad_token', '登录已过期，请重新登录') };
  if (truthy(f.row[P.banned])) return { err: fail('banned', '这个账号已被停用') };
  return { found: f };
}

function issueToken(f) {
  var tok = newToken();
  f.row[P.token] = tok;
  f.row[P.exp] = now() + CFG.TOKEN_DAYS * 86400000;
  return tok;
}

// ---------------------------------------------------------------- 注册 / 登录
function register(req) {
  var nick = String(req.nick || '').trim();
  var pin = String(req.pin || '');
  var code = String(req.code || '').trim().toUpperCase();
  if (!CFG.NICK_RE.test(nick)) return fail('bad_nick', '昵称要 2–12 个字：中文、字母、数字、下划线');
  if (!CFG.PIN_RE.test(pin)) return fail('bad_pin', 'PIN 要是 4–8 位数字');
  if (findPlayer(nick)) return fail('nick_taken', '这个昵称已经有人用了');

  var inv = sheet('invites');
  var last = inv.getLastRow();
  var rows = last < 2 ? [] : inv.getRange(2, 1, last - 1, HEADERS.invites.length).getValues();
  var hit = -1;
  for (var i = 0; i < rows.length; i++) if (String(rows[i][0]).toUpperCase() === code && code !== '') hit = i;
  if (hit < 0) return fail('bad_code', '邀请码不正确');
  var r = rows[hit];
  if (!truthy(r[2])) return fail('code_closed', '这个邀请码已关闭');
  var end = expiryEnd(r[8]);
  if (end && now() > end) return fail('code_expired', '这个邀请码已过期');
  var roster = parseRoster(r[7]);
  if (roster.length > 0 && roster.indexOf(nick.toLowerCase()) < 0)
    return fail('not_on_roster', '这个邀请码只允许名单里的昵称注册，请用管理员给你的昵称');
  var max = Number(r[4]) || 0;
  if (max > 0 && (Number(r[5]) || 0) >= max) return fail('code_full', '这个邀请码的名额已满');

  var salt = newSalt();
  var row = [];
  for (var c = 0; c < HEADERS.players.length; c++) row.push('');
  row[P.nick] = nick; row[P.invite] = code; row[P.salt] = salt; row[P.hash] = hashPin(salt, pin);
  row[P.created] = iso(); row[P.last] = iso(); row[P.fails] = 0; row[P.lock] = 0; row[P.banned] = false; row[P.updated] = iso();
  row[P.runs] = 0; row[P.wins] = 0; row[P.bestScore] = 0; row[P.bestWin] = 0; row[P.bestLevel] = 0; row[P.kills] = 0;
  row[P.school] = ''; row[P.state] = '{}'; row[P.lastSubmit] = '';
  var found = { row: row };
  var tok = issueToken(found);
  sheet('players').appendRow(row);
  inv.getRange(hit + 2, 6).setValue((Number(r[5]) || 0) + 1);
  writeLog('info', nick, '注册', 'register', code, str(req.device, 120));
  var p = profile(row); p.token = tok;
  return ok(p);
}

function login(req) {
  var f = findPlayer(req.nick);
  var bad = fail('bad_login', '昵称或 PIN 不正确');
  if (!f) return bad;
  var row = f.row;
  if (truthy(row[P.banned])) return fail('banned', '这个账号已被停用');
  var wait = Number(row[P.lock]) - now();
  if (wait > 0) return fail('locked', '尝试次数太多，请 ' + Math.ceil(wait / 60000) + ' 分钟后再试', { minutes: Math.ceil(wait / 60000) });
  if (hashPin(String(row[P.salt]), String(req.pin || '')) !== String(row[P.hash])) {
    row[P.fails] = (Number(row[P.fails]) || 0) + 1;
    var res = bad;
    if (row[P.fails] >= CFG.MAX_FAILS) {
      row[P.lock] = now() + CFG.LOCK_MIN * 60000; row[P.fails] = 0;
      res = fail('locked', '尝试次数太多，请 ' + CFG.LOCK_MIN + ' 分钟后再试', { minutes: CFG.LOCK_MIN });
      writeLog('warn', row[P.nick], '登录失败过多，已锁定', 'login', '', str(req.device, 120));
    } else {
      res = fail('bad_login', '昵称或 PIN 不正确', { left: CFG.MAX_FAILS - row[P.fails] });
    }
    savePlayer(f);
    return res;
  }
  row[P.fails] = 0; row[P.lock] = 0; row[P.last] = iso();
  var tok = issueToken(f);
  savePlayer(f);
  var p = profile(row); p.token = tok;
  return ok(p);
}

function resume(req) {
  var a = authed(req);
  if (a.err) return a.err;
  var f = a.found;
  f.row[P.exp] = now() + CFG.TOKEN_DAYS * 86400000;
  f.row[P.last] = iso();
  savePlayer(f);
  var p = profile(f.row); p.token = String(f.row[P.token]);
  return ok(p);
}

function logout(req) {
  var f = findPlayer(req.nick);
  if (f && String(f.row[P.token]) === String(req.token)) { f.row[P.token] = ''; f.row[P.exp] = 0; savePlayer(f); }
  return ok({});
}

// BEGIN GENERATED (tools/sync_talents.py)
var TALENT_GATE = 3;
var TALENTS = {"gang_force":["gang",0,3],"gang_body":["gang",0,2],"gang_crit":["gang",1,3],"gang_armor":["gang",1,2],"gang_ying":["gang",2,3],"gang_dragon":["gang",2,2],"gang_cm":["gang",3,3],"gang_force2":["gang",3,2],"gang_emp":["gang",4,3],"gang_vajra":["gang",4,2],"gang_regen":["gang",5,2],"gang_ying2":["gang",5,3],"gang_peak":["gang",6,1],"gang_force3":["gang",6,4],"rou_regen":["rou",0,3],"rou_body":["rou",0,2],"rou_neili":["rou",1,3],"rou_med":["rou",1,2],"rou_med2":["rou",2,3],"rou_shield":["rou",2,2],"rou_block":["rou",3,3],"rou_petal":["rou",3,2],"rou_heal":["rou",4,3],"rou_finger":["rou",4,2],"rou_full":["rou",5,2],"rou_cut":["rou",5,3],"rou_peak":["rou",6,1],"rou_armor":["rou",6,4],"ling_step":["ling",0,3],"ling_luck":["ling",0,2],"ling_cd":["ling",1,3],"ling_qg":["ling",1,2],"ling_crit":["ling",2,3],"ling_palm":["ling",2,2],"ling_exp":["ling",3,3],"ling_dodge":["ling",3,2],"ling_cd2":["ling",4,3],"ling_waste":["ling",4,2],"ling_luck2":["ling",5,2],"ling_cm":["ling",5,3],"ling_peak":["ling",6,1],"ling_step2":["ling",6,4]};
var GEAR = {"slots":["weapon","coat","pants","boots","charm"],"weights":[60,30,9,1],"invMax":40,"mini":1,"bossMin":1,"bossExtra":0.5,"enh":{"max":10,"bonus":0.08,"costBase":[12,30,70,160],"costExp":1.6},"silver":{"perScore":120,"cap":300,"winBonus":60,"comp":0.5,"discard":[3,10,40,120],"max":999999}};
var MAPS = {"black_wind":{"minTimes":[180,330,480],"finalT":600,"minWin":620,"requires":""},"guangming":{"minTimes":[180,360,540],"finalT":780,"minWin":800,"requires":""}};
var DIFF = {"expMeta":0.5,"dropBonus":0.0,"raritySkew":0.5};
// END GENERATED

// ---------------------------------------------------------------- 局外成长（scripts/meta.gd 里有同一份，共用 meta_vectors.json 测试）
var META = { MAX_LEVEL: 50, PER_LEVEL: 3, ATTR_CAP: 99, EXP_CAP: 400, WIN_BONUS: 40, FIRST_WIN_BONUS: 100,
             ATTRS: ['pow', 'agi', 'vit', 'int', 'luk'] };
function metaNeed(l) { return 40 + 6 * l; }
function metaLevel(exp) {
  var l = 1, t = 0;
  while (l < META.MAX_LEVEL && t + metaNeed(l) <= exp) { t += metaNeed(l); l++; }
  return l;
}
/** 综合难度（1~3）：怪物数量 / 血量 / 速度三个百分比（100~300，步长 10）的平均；不合法的值按 100 算 */
function diffComp(d) {
  var sum = 0, ks = ['count', 'hp', 'speed'];
  d = (typeof d === 'object' && d !== null) ? d : {};
  for (var i = 0; i < ks.length; i++) {
    var v = Number(d[ks[i]]);
    if (!(v >= 100 && v <= 300) || v % 10 !== 0) v = 100;
    sum += v;
  }
  return sum / 300;
}
function metaRunExp(score, won, first, comp) {
  var x = Math.min(META.EXP_CAP, Math.round(score / 80));
  if (won) x += META.WIN_BONUS + (first ? META.FIRST_WIN_BONUS : 0);
  return Math.round(x * (1 + ((comp || 1) - 1) * DIFF.expMeta));
}
function metaEffective(p) {
  p = Math.max(0, Math.min(META.ATTR_CAP, p));
  var e = Math.min(p, 30);
  if (p > 30) e += 0.6 * (Math.min(p, 60) - 30);
  if (p > 60) e += 0.3 * (p - 60);
  return e;
}
/** 属性分配校验：只能是五种属性、0~99 的整数、总和不超过已获得的点数。返回规范化结果或 null */
function cleanAlloc(a, level) {
  if (typeof a !== 'object' || a === null) return null;
  var out = {}, sum = 0;
  for (var i = 0; i < META.ATTRS.length; i++) {
    var k = META.ATTRS[i], v = Number(a[k] || 0);
    if (!(v >= 0 && v <= META.ATTR_CAP) || Math.floor(v) !== v) return null;
    out[k] = v; sum += v;
  }
  return sum <= META.PER_LEVEL * (level - 1) ? out : null;
}

/** 天赋校验：节点存在、不超过上限；每个有点数的节点，本系「更低层」投入合计 ≥ 层号 × TALENT_GATE；总点数 ≤ 局外等级 */
function cleanTalents(t, level) {
  if (typeof t !== 'object' || t === null || Array.isArray(t)) return null;
  var out = {}, total = 0, ids = Object.keys(t);
  for (var i = 0; i < ids.length; i++) {
    var id = ids[i], n = TALENTS[id], v = Number(t[id]);
    if (!n || !(v >= 0 && v <= n[2]) || Math.floor(v) !== v) return null;
    if (v > 0) { out[id] = v; total += v; }
  }
  if (total > level) return null;
  var all = Object.keys(out);
  for (var a = 0; a < all.length; a++) {
    var na = TALENTS[all[a]], lower = 0;
    for (var b = 0; b < all.length; b++) { var nb = TALENTS[all[b]]; if (nb[0] === na[0] && nb[1] < na[1]) lower += out[all[b]]; }
    if (lower < na[1] * TALENT_GATE) return null;
  }
  return out;
}

/** 装备编码 "部位.稀有度.种子"（服务器只认自己发过的编码） */
function gearValid(code) {
  var p = String(code).split('.');
  return p.length === 3 && GEAR.slots.indexOf(p[0]) >= 0 && /^\d+$/.test(p[1]) && Number(p[1]) < GEAR.weights.length && /^\d{1,7}$/.test(p[2]);
}
/** 强化：第 lv → lv+1 级的银两（稀有度越高越贵；客户端 Gear.enhance_cost 里有同一份，测试用共用向量校验） */
function enhCost(r, lv) { return Math.round(GEAR.enh.costBase[r] * Math.pow(lv + 1, GEAR.enh.costExp)); }
/** 一局结算得到的银两（客户端 Meta.run_silver 是同一份公式） */
function silverForRun(score, won, comp) {
  var x = Math.min(GEAR.silver.cap, Math.round(score / GEAR.silver.perScore));
  if (won) x += GEAR.silver.winBonus;
  return Math.round(x * (1 + ((comp || 1) - 1) * GEAR.silver.comp));
}
function addSilver(state, n) { state.silver = Math.min(GEAR.silver.max, Math.max(0, Math.floor(Number(state.silver) || 0)) + Math.max(0, Math.floor(n))); }
function gearWeight(i, comp) { return GEAR.weights[i] * (1 + ((comp || 1) - 1) * DIFF.raritySkew * i); }
function gearRoll(comp) {
  var total = 0, i;
  for (i = 0; i < GEAR.weights.length; i++) total += gearWeight(i, comp);
  var x = Math.random() * total, r = 0;
  for (i = 0; i < GEAR.weights.length; i++) { x -= gearWeight(i, comp); if (x < 0) { r = i; break; } }
  return GEAR.slots[Math.floor(Math.random() * GEAR.slots.length)] + '.' + r + '.' + (1 + Math.floor(Math.random() * 999999));
}
/** 掉落：每个被击败的小 Boss 固定 1 件；大 Boss（通关）GEAR.bossMin 件，另有 GEAR.bossExtra 的几率再多 1 件（共 1~2 件）。
 *  返回新掉落的编码，并写进 state.items（超过上限先丢最低稀有度、最早的未穿戴装备） */
function gearDrops(state, comp, minis, won) {
  var n = minis + (won ? GEAR.bossMin + (Math.random() < GEAR.bossExtra ? 1 : 0) : 0), codes = [];
  state.items = Array.isArray(state.items) ? state.items : [];
  for (var i = 0; i < n; i++) { var c = gearRoll(comp); codes.push(c); state.items.push(c); }
  var worn = {}, eq = state.equip || {};
  Object.keys(eq).forEach(function (k) { worn[eq[k]] = true; });
  while (state.items.length > GEAR.invMax) {
    var worst = -1, wr = 99;
    for (var j = 0; j < state.items.length; j++) {
      if (worn[state.items[j]]) continue;
      var r = Number(state.items[j].split('.')[1]);
      if (r < wr) { wr = r; worst = j; }
    }
    if (worst < 0) break;
    if (state.enh) delete state.enh[state.items[worst]];
    state.items.splice(worst, 1);
  }
  return codes;
}
/** 旧存档里的装备编码：稀有度超过现有档数的（旧版有 5 档）降到最高档 */
function gearFix(code) {
  var p = String(code).split('.');
  if (p.length === 3 && /^\d+$/.test(p[1]) && Number(p[1]) >= GEAR.weights.length) p[1] = String(GEAR.weights.length - 1);
  return p.join('.');
}
function readState(row) {
  var st = {};
  try { st = JSON.parse(row[P.state] || '{}'); } catch (e) {}
  st = st && typeof st === 'object' ? st : {};
  if (Array.isArray(st.items)) st.items = st.items.map(gearFix);
  if (st.equip && typeof st.equip === 'object') Object.keys(st.equip).forEach(function (k) { st.equip[k] = gearFix(st.equip[k]); });
  if (st.enh && typeof st.enh === 'object') { var ne = {}; Object.keys(st.enh).forEach(function (k) { ne[gearFix(k)] = st.enh[k]; }); st.enh = ne; }
  return st;
}

// ---------------------------------------------------------------- 成绩
/** 得分公式（客户端 scripts/score.gd 里有同一份，测试用同一组向量校验） */
function computeScore(s) {
  var base = s.kills + s.level * 100 + s.bosses * 1000;
  if (s.won) base += 5000 + Math.max(0, 900 - s.seconds) * 10;
  return Math.round(base);
}

function validateRun(req) {
  var s = {
    won: truthy(req.won),
    seconds: num(req.seconds), level: num(req.level), kills: num(req.kills), bosses: num(req.bosses)
  };
  if (!(s.seconds >= 30 && s.seconds <= CFG.MAX_SECONDS)) return fail('bad_run', '成绩无效（用时）');
  if (!(s.level >= 1 && s.level <= 99 && Math.floor(s.level) === s.level)) return fail('bad_run', '成绩无效（等级）');
  if (!(s.kills >= 0 && s.kills <= 30000 && Math.floor(s.kills) === s.kills)) return fail('bad_run', '成绩无效（击杀）');
  if (!(s.bosses >= 0 && s.bosses <= 4 && Math.floor(s.bosses) === s.bosses)) return fail('bad_run', '成绩无效（Boss）');
  if (s.kills > s.seconds * 40) return fail('bad_run', '成绩无效（击杀速度）');
  if (s.level > 5 + s.seconds / 5) return fail('bad_run', '成绩无效（等级速度）');
  var mp = MAPS[String(req.map || 'black_wind')];
  if (!mp) return fail('bad_run', '成绩无效（地图）');
  if (s.won && (s.seconds < mp.minWin || s.bosses < 1)) return fail('bad_run', '成绩无效（通关）');
  s.map = String(req.map || 'black_wind');
  return { run: s };
}

function submitScore(req) {
  var a = authed(req);
  if (a.err) return a.err;
  var v = validateRun(req);
  if (v.ok === false) { writeLog('warn', req.nick, '拒绝成绩', 'submit', JSON.stringify(req).slice(0, 300), str(req.device, 120)); return v; }
  var run = v.run, f = a.found, row = f.row;
  var req0 = MAPS[run.map].requires;
  if (req0) { var cl = readState(row).cleared; if (!cl || !cl[req0]) return fail('locked', '这张地图还没解锁（需要先通关前一关）'); }
  // 提交间隔只看上一次「提交成绩」的时间（不能用 Updated：创建角色的云存档也会更新它）
  if (now() - toMs(row[P.lastSubmit]) < CFG.SUBMIT_GAP_SEC * 1000) return fail('too_fast', '提交太频繁，请稍后再试');

  var score = computeScore(run);
  var preBest = { score: Number(row[P.bestScore]) || 0, win: Number(row[P.bestWin]) || 0, level: Number(row[P.bestLevel]) || 0 };   // 分地图成绩的旧数据迁移用：改版前所有成绩都来自黑风寨
  var school = str(req.school, 16), starter = str(req.starter, 24), qg = str(req.qinggong, 24), enh = str(req.enhance, 40);
  var build = str(typeof req.build === 'string' ? req.build : JSON.stringify(req.build || []), 600);
  sheet('scores').appendRow([iso(), row[P.nick], run.won ? '通关' : '阵亡', score, Math.round(run.seconds), run.level, run.kills,
                             run.bosses, school, starter, qg, enh, build, str(req.version, 12), str(req.device, 120)]);

  var best = score > (Number(row[P.bestScore]) || 0);
  var firstWin = run.won && !(Number(row[P.wins]) > 0);
  var comp = diffComp(req.difficulty);
  var gained = metaRunExp(score, run.won, firstWin, comp);
  var oldLevel = metaLevel(Number(row[P.xp]) || 0);
  row[P.xp] = Math.max(0, Math.floor(Number(row[P.xp]) || 0)) + gained;
  row[P.runs] = (Number(row[P.runs]) || 0) + 1;
  row[P.kills] = (Number(row[P.kills]) || 0) + run.kills;
  if (best) row[P.bestScore] = score;
  if (run.level > (Number(row[P.bestLevel]) || 0)) row[P.bestLevel] = run.level;
  if (run.won) {
    row[P.wins] = (Number(row[P.wins]) || 0) + 1;
    var bw = Number(row[P.bestWin]) || 0;
    if (bw === 0 || run.seconds < bw) row[P.bestWin] = Math.round(run.seconds);
  }
  var drops = [];
  var stt = readState(row);
  // 分地图最佳成绩（地图榜用）：第一次写入时，把改版前的总成绩当作黑风寨成绩
  var mb = stt.mapBests && typeof stt.mapBests === 'object' && !Array.isArray(stt.mapBests) ? stt.mapBests : null;
  if (!mb) { mb = {}; if (preBest.score > 0 || preBest.level > 0) mb.black_wind = { score: preBest.score, win: preBest.win, level: preBest.level }; }
  var cur = mb[run.map] || { score: 0, win: 0, level: 0 };
  if (score > cur.score) cur.score = score;
  if (run.level > cur.level) cur.level = run.level;
  if (run.won && (!cur.win || run.seconds < cur.win)) cur.win = Math.round(run.seconds);
  mb[run.map] = cur;
  stt.mapBests = mb;
  var silverGained = silverForRun(score, run.won, comp);
  addSilver(stt, silverGained);
  // 掉落：每个被击败的小 Boss 1 件，通关（大 Boss）1~2 件；小 Boss 的数量不能超过该用时内已刷出的个数
  var minis = Math.max(0, Math.min(3, run.bosses - (run.won ? 1 : 0)));
  var spawned = 0, mts = MAPS[run.map].minTimes;
  for (var mi = 0; mi < mts.length; mi++) if (run.seconds >= mts[mi]) spawned++;
  if (run.won) { stt.cleared = stt.cleared && typeof stt.cleared === 'object' ? stt.cleared : {}; stt.cleared[run.map] = true; }
  drops = gearDrops(stt, comp, Math.min(minis, spawned), run.won);
  row[P.state] = JSON.stringify(stt);
  row[P.updated] = iso();
  row[P.lastSubmit] = iso();
  savePlayer(f);

  var ranks = {
    score: rankOf(row[P.nick], 'score'),
    speed: rankOf(row[P.nick], 'speed'),
    level: rankOf(row[P.nick], 'level')
  };
  var pr = profile(row);
  return ok({ score: score, best: best, ranks: ranks, bests: pr.bests, gained: gained, exp: pr.exp, level: pr.level, levelUp: pr.level > oldLevel, drops: drops, comp: comp, silverGained: silverGained, silver: pr.silver, cleared: pr.cleared });
}

// ---------------------------------------------------------------- 排行榜
var BOARD = {
  score: { col: P.bestScore, asc: false },
  speed: { col: P.bestWin,   asc: true },
  level: { col: P.bestLevel, asc: false }
};

var BOARD_FIELD = { score: 'score', speed: 'win', level: 'level' };

function boardRows(kind, group, map) {
  var spec = BOARD[kind];
  var pl = loadPlayers();
  var list = [];
  var want = String(group || '').toUpperCase();
  pl.rows.forEach(function (r) {
    if (truthy(r[P.banned])) return;
    if (want && String(r[P.invite]).toUpperCase() !== want) return;
    var v = Number(r[spec.col]) || 0;
    if (map) {     // 地图榜：取该玩家在这张地图上的最佳；没有记录 = 没打过
      var mbs = readState(r).mapBests;
      v = mbs && mbs[map] ? Number(mbs[map][BOARD_FIELD[kind]]) || 0 : 0;
    }
    if (v <= 0) return;
    list.push({ nick: String(r[P.nick]), value: v, school: String(r[P.school] || ''), wins: Number(r[P.wins]) || 0 });
  });
  list.sort(function (x, y) { return spec.asc ? x.value - y.value : y.value - x.value; });
  return list;
}

function rankOf(nick, kind) {
  var list = boardRows(kind);
  for (var i = 0; i < list.length; i++) if (list[i].nick.toLowerCase() === String(nick).toLowerCase()) return i + 1;
  return 0;
}

function board(req) {
  var kind = String(req.kind || 'score');
  if (!BOARD[kind]) return fail('bad_kind', '未知的榜单');
  var group = String(req.group || '');
  var map = String(req.map || '');
  if (map && !MAPS[map]) return fail('bad_map', '未知的地图');
  var list = boardRows(kind, group, map);
  var me = null;
  var want = String(req.nick || '').toLowerCase();
  var rows = list.slice(0, CFG.BOARD_SIZE).map(function (e, i) { e.rank = i + 1; return e; });
  if (want) for (var i = 0; i < list.length; i++) if (list[i].nick.toLowerCase() === want) me = { rank: i + 1, value: list[i].value };
  return ok({ kind: kind, rows: rows, me: me, total: list.length, group: group ? groupName(group) : '', map: map });
}

// ---------------------------------------------------------------- 云存档 / 反馈 / 日志
function saveState(req) {
  var a = authed(req);
  if (a.err) return a.err;
  var st = req.state;
  if (typeof st !== 'object' || st === null || Array.isArray(st)) return fail('bad_state', '存档格式不对');
  if (JSON.stringify(st).length > CFG.STATE_MAX) return fail('bad_state', '存档太大');
  var row = a.found.row, old = readState(row);
  var lv = metaLevel(Number(row[P.xp]) || 0);
  var school = row[P.school];
  if (st.school !== undefined) {
    school = String(st.school || '');
    if (school !== '' && !/^[a-z_]{1,16}$/.test(school)) return fail('bad_state', '存档格式不对');
    old.school = school;
  }
  if (st.alloc !== undefined) {
    var clean = cleanAlloc(st.alloc, lv);
    if (!clean) return fail('bad_state', '属性点分配不合法');
    old.alloc = clean;
  }
  if (st.talents !== undefined) {
    var tl = cleanTalents(st.talents, lv);
    if (!tl) return fail('bad_state', '天赋加点不合法');
    old.talents = tl;
  }
  // 背包只能由服务器发放（通关掉落）；客户端只能「丢弃」和「穿戴」自己背包里已有的装备
  var items = Array.isArray(old.items) ? old.items.slice() : [];
  if (st.discard !== undefined) {
    if (!Array.isArray(st.discard) || st.discard.length > GEAR.invMax) return fail('bad_state', '丢弃列表不对');
    for (var i = 0; i < st.discard.length; i++) {
      var at = items.indexOf(String(st.discard[i]));
      if (at < 0) return fail('bad_state', '背包里没有这件装备');
      addSilver(old, GEAR.silver.discard[Number(items[at].split('.')[1])] || 0);      // 丢弃（分解）换银两
      if (old.enh) delete old.enh[items[at]];
      items.splice(at, 1);
    }
    old.items = items;
  }
  var equip = old.equip && typeof old.equip === 'object' ? old.equip : {};
  if (st.equip !== undefined) {
    if (typeof st.equip !== 'object' || st.equip === null || Array.isArray(st.equip)) return fail('bad_state', '穿戴格式不对');
    equip = {};
    var slots = Object.keys(st.equip);
    for (var j = 0; j < slots.length; j++) {
      var code = String(st.equip[slots[j]]);
      if (GEAR.slots.indexOf(slots[j]) < 0 || !gearValid(code) || code.split('.')[0] !== slots[j] || items.indexOf(code) < 0)
        return fail('bad_state', '这件装备不能穿在这里');
      equip[slots[j]] = code;
    }
  }
  // 被丢掉的装备不能还穿着
  Object.keys(equip).forEach(function (k) { if (items.indexOf(equip[k]) < 0) delete equip[k]; });
  old.equip = equip;
  var text = JSON.stringify(old);
  if (text.length > CFG.STATE_STORE_MAX) return fail('bad_state', '存档太大');
  row[P.state] = text;
  row[P.school] = school;
  row[P.updated] = iso();
  savePlayer(a.found);
  return ok({ items: old.items || [], equip: equip, silver: Math.floor(Number(old.silver) || 0), enh: old.enh || {} });
}

/** 铁匠强化：消耗银两把背包里一件装备 +1（上限 GEAR.enh.max）；银两和强化等级都以服务器为准 */
function enhanceGear(req) {
  var a = authed(req);
  if (a.err) return a.err;
  var code = String(req.code || ''), row = a.found.row, st = readState(row);
  var items = Array.isArray(st.items) ? st.items : [];
  if (!gearValid(code) || items.indexOf(code) < 0) return fail('bad_state', '背包里没有这件装备');
  st.enh = st.enh && typeof st.enh === 'object' ? st.enh : {};
  var lv = Math.floor(Number(st.enh[code]) || 0);
  if (lv >= GEAR.enh.max) return fail('enh_max', '已经强化到顶了');
  var cost = enhCost(Number(code.split('.')[1]), lv);
  var have = Math.floor(Number(st.silver) || 0);
  if (have < cost) return fail('no_silver', '银两不够（需要 ' + cost + '，现有 ' + have + '）');
  st.silver = have - cost;
  st.enh[code] = lv + 1;
  row[P.state] = JSON.stringify(st);
  row[P.updated] = iso();
  savePlayer(a.found);
  return ok({ silver: st.silver, level: lv + 1, cost: cost, enh: st.enh });
}

function addFeedback(req) {
  var a = authed(req);
  if (a.err) return a.err;
  var comment = str(req.comment, 500).trim();
  if (comment.length < 2) return fail('bad_feedback', '请写点内容');
  var s = sheet('feedback');
  var last = s.getLastRow();
  var since = now() - 86400000, count = 0;
  if (last >= 2) s.getRange(2, 1, last - 1, 3).getValues().forEach(function (r) {
    if (String(r[2]) === String(a.found.row[P.nick]) && toMs(r[1]) > since) count++;
  });
  if (count >= CFG.FEEDBACK_PER_DAY) return fail('too_many', '今天的反馈次数已用完');
  var type = ['bug', 'balance', 'idea', 'other'].indexOf(req.type) >= 0 ? req.type : 'other';
  s.appendRow([Utilities.getUuid().slice(0, 8), iso(), a.found.row[P.nick], type, str(req.where, 60), comment, str(req.device, 120), '待处理', '']);
  return ok({});
}

function writeLog(kind, nick, message, where, detail, device) {
  sheet('logs').appendRow([iso(), kind, nick, str(message, 200), str(where, 60), str(detail, 500), str(device, 120)]);
}

function addLog(req) {
  var a = authed(req);
  if (a.err) return ok({});    // 没登录的日志直接丢弃，防止被刷
  writeLog(['error', 'warn', 'info'].indexOf(req.kind) >= 0 ? req.kind : 'info', a.found.row[P.nick],
           req.message, req.where, req.detail, req.device);
  return ok({});
}

// ---------------------------------------------------------------- 后台菜单（表格上方「武侠后台」）
function onOpen() {
  SpreadsheetApp.getUi().createMenu('武侠后台')
    .addItem('初始化 / 修复表头', 'setup')
    .addSeparator()
    .addItem('新建邀请码', 'adminNewInvite')
    .addItem('开启 / 关闭邀请码', 'adminToggleInvite')
    .addItem('重设玩家 PIN', 'adminResetPin')
    .addItem('封禁 / 解封玩家', 'adminToggleBan')
    .addSeparator()
    .addItem('清空排行榜（新赛季）', 'adminClearScores')
    .addToUi();
}

function ask(title, prompt) {
  var ui = SpreadsheetApp.getUi();
  var r = ui.prompt(title, prompt, ui.ButtonSet.OK_CANCEL);
  return r.getSelectedButton() === ui.Button.OK ? r.getResponseText().trim() : null;
}
function tell(msg) { SpreadsheetApp.getUi().alert(msg); }

function makeCode() {
  var chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789', s = '';
  for (var i = 0; i < 6; i++) s += chars.charAt(Math.floor(Math.random() * chars.length));
  return s;
}

function adminNewInvite() {
  var name = ask('新建邀请码', '给这个邀请码起个名字（比如"篮球群朋友"）：');
  if (name === null) return;
  var max = ask('新建邀请码', '最多可注册几人？（0 = 不限）：');
  if (max === null) return;
  var roster = ask('新建邀请码', '只允许这些昵称注册？（逗号分隔；留空 = 不限）：');
  if (roster === null) return;
  var exp = ask('新建邀请码', '到期日期（如 2026-12-31，当天有效；留空 = 不限）：');
  if (exp === null) return;
  var expires = '';
  if (exp !== '') {
    var m = /^(\d{4})-(\d{1,2})-(\d{1,2})$/.exec(exp);
    if (!m) { tell('日期格式不对，请用 2026-12-31 这样的写法'); return; }
    expires = new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]));
  }
  var code = makeCode();
  sheet('invites').appendRow([code, name, true, iso(), Number(max) || 0, 0, '', roster, expires]);
  tell('邀请码：' + code + '\n把它发给朋友，注册时填写。\n（同一个人注册后，排行榜里可以选择只看这个群。）');
  return code;
}

function adminToggleInvite() {
  var code = ask('开启 / 关闭邀请码', '邀请码：');
  if (code === null) return;
  var inv = sheet('invites');
  var last = inv.getLastRow();
  var rows = last < 2 ? [] : inv.getRange(2, 1, last - 1, 3).getValues();
  for (var i = 0; i < rows.length; i++) {
    if (String(rows[i][0]).toUpperCase() === code.toUpperCase()) {
      var now_open = !truthy(rows[i][2]);
      inv.getRange(i + 2, 3).setValue(now_open);
      tell(rows[i][0] + '（' + rows[i][1] + '）' + (now_open ? ' 已开启' : ' 已关闭：不能再用它注册，已注册的玩家不受影响'));
      return;
    }
  }
  tell('找不到这个邀请码');
}

function adminResetPin() {
  var nick = ask('重设玩家 PIN', '玩家昵称：');
  if (nick === null) return;
  var f = findPlayer(nick);
  if (!f) { tell('找不到这个玩家'); return; }
  var pin = ask('重设玩家 PIN', '新的 PIN（4–8 位数字）：');
  if (pin === null) return;
  if (!CFG.PIN_RE.test(pin)) { tell('PIN 要是 4–8 位数字'); return; }
  var salt = newSalt();
  f.row[P.salt] = salt; f.row[P.hash] = hashPin(salt, pin);
  f.row[P.token] = ''; f.row[P.exp] = 0; f.row[P.fails] = 0; f.row[P.lock] = 0;
  savePlayer(f);
  tell('已重设。请把新 PIN 告诉 ' + f.row[P.nick] + '。');
}

function adminToggleBan() {
  var nick = ask('封禁 / 解封玩家', '玩家昵称：');
  if (nick === null) return;
  var f = findPlayer(nick);
  if (!f) { tell('找不到这个玩家'); return; }
  var now_banned = !truthy(f.row[P.banned]);
  f.row[P.banned] = now_banned;
  if (now_banned) { f.row[P.token] = ''; f.row[P.exp] = 0; }
  savePlayer(f);
  tell(f.row[P.nick] + (now_banned ? ' 已封禁（不再出现在排行榜）' : ' 已解封'));
}

function adminClearScores() {
  var ui = SpreadsheetApp.getUi();
  var r = ui.alert('清空排行榜', '会删除全部成绩记录，并把所有玩家的最高分、局数清零（账号保留）。继续吗？', ui.ButtonSet.YES_NO);
  if (r !== ui.Button.YES) return;
  var s = sheet('scores');
  if (s.getLastRow() > 1) s.deleteRows(2, s.getLastRow() - 1);
  var pl = loadPlayers();
  pl.rows.forEach(function (row, i) {
    row[P.runs] = 0; row[P.wins] = 0; row[P.bestScore] = 0; row[P.bestWin] = 0; row[P.bestLevel] = 0; row[P.kills] = 0;
    pl.sheet.getRange(i + 2, 1, 1, HEADERS.players.length).setValues([row]);
  });
  tell('已清空，新赛季开始。');
}
