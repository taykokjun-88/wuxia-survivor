/**
 * 群侠千招 · 后端（Google Apps Script，绑定在一个 Google 表格上）
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

var CODE_REV = 'v0.9-talents-2';   // 部署后访问 <网址>?action=ping 能看到这个值，用来确认部署的是最新代码
var VERSION = 1;

var SHEETS = {
  invites:  '邀请 Invites',
  players:  '玩家 Players',
  scores:   '排行 Scores',
  logs:     '日志 Logs',
  feedback: '反馈 Feedback',
  chars:    '角色 Characters'
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
// 角色表：前 22 列和玩家表同一个布局（昵称 = 所属账号；盐 / 哈希 / 令牌等登录列留空），后面多两列：角色 ID、角色名
HEADERS.chars = HEADERS.players.concat(['角色ID CharId', '角色名 CharName']);

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
  STATE_STORE_MAX: 8000,  // 服务器保存的存档总大小（含背包）
  MAX_CHARS: 5            // 每个账号最多 5 个角色
};

// 列下标（0 起）
var P = { nick: 0, invite: 1, salt: 2, hash: 3, created: 4, last: 5, token: 6, exp: 7, fails: 8, lock: 9, banned: 10,
          updated: 11, runs: 12, wins: 13, bestScore: 14, bestWin: 15, bestLevel: 16, kills: 17, school: 18, state: 19, lastSubmit: 20, xp: 21,
          cid: 22, cname: 23 };      // cid / cname：只在角色表里有

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
  var TEXT_COLS = { invites: [1, 8], players: [1, 2, 3, 4, 7], scores: [2], logs: [3], feedback: [1, 3], chars: [1, 23, 24] };
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
    if (p.action === 'ping') res = ok({ v: VERSION, rev: CODE_REV, time: iso(), schools: SCHOOLS });
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
  if (a === 'ping') return ok({ v: VERSION, rev: CODE_REV, time: iso(), schools: SCHOOLS });
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
      case 'getChar':   return getChar(req);
      case 'createChar': return createChar(req);
      case 'deleteChar': return deleteChar(req);
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
  found.sheet.getRange(found.idx + 2, 1, 1, found.row.length).setValues([found.row]);
}

// ---------------------------------------------------------------- 角色（每个账号最多 5 个；局外等级 / 天赋 / 装备 / 银两 / 通关记录都按角色存）
function blankChar() {
  var row = [];
  for (var c = 0; c < HEADERS.chars.length; c++) row.push('');
  row[P.created] = iso(); row[P.updated] = iso(); row[P.fails] = 0; row[P.lock] = 0; row[P.banned] = false;
  row[P.runs] = 0; row[P.wins] = 0; row[P.bestScore] = 0; row[P.bestWin] = 0; row[P.bestLevel] = 0; row[P.kills] = 0;
  row[P.school] = ''; row[P.state] = '{}'; row[P.lastSubmit] = ''; row[P.xp] = 0;
  return row;
}

function loadChars() {
  var s = sheet('chars');
  var last = s.getLastRow();
  if (last < 2) return { sheet: s, rows: [] };
  return { sheet: s, rows: s.getRange(2, 1, last - 1, HEADERS.chars.length).getValues() };
}

/** 某个账号的全部角色（按创建顺序）：[{idx, row, sheet}] */
function charsOf(nick) {
  var cl = loadChars(), out = [], want = String(nick || '').toLowerCase();
  for (var i = 0; i < cl.rows.length; i++) {
    if (String(cl.rows[i][P.nick]).toLowerCase() === want && want !== '') out.push({ idx: i, row: cl.rows[i], sheet: cl.sheet });
  }
  return out;
}

function findChar(nick, id) {
  var list = charsOf(nick);
  for (var i = 0; i < list.length; i++) if (String(list[i].row[P.cid]) === String(id)) return list[i];
  return null;
}

function newCharId() { return Utilities.getUuid().replace(/-/g, '').slice(0, 10); }

function addCharRow(acc, row) {
  var sh = sheet('chars');
  sh.appendRow(row);
  return { idx: sh.getLastRow() - 2, row: row, sheet: sh };
}

/** 旧账号（角色功能之前）的进度还在玩家表里：第一次用到角色时，把它变成第一个角色（角色名 = 昵称） */
function legacyChar(acc) {
  var r = acc.row, row = blankChar();
  row[P.nick] = r[P.nick]; row[P.invite] = r[P.invite];
  row[P.created] = r[P.created] || iso();
  row[P.runs] = r[P.runs] || 0; row[P.wins] = r[P.wins] || 0; row[P.bestScore] = r[P.bestScore] || 0; row[P.bestWin] = r[P.bestWin] || 0;
  row[P.bestLevel] = r[P.bestLevel] || 0; row[P.kills] = r[P.kills] || 0; row[P.school] = r[P.school] || '';
  row[P.state] = r[P.state] || '{}'; row[P.lastSubmit] = r[P.lastSubmit] || ''; row[P.xp] = r[P.xp] || 0;
  row[P.cid] = newCharId(); row[P.cname] = String(r[P.nick]);
  return addCharRow(acc, row);
}

function hasLegacyData(r) {
  var st = String(r[P.state] || '{}');
  return String(r[P.school] || '') !== '' || (Number(r[P.xp]) || 0) > 0 || (Number(r[P.runs]) || 0) > 0 || (st !== '{}' && st !== '');
}

/** 账号的角色列表；有旧进度而还没有角色时，自动迁移成第一个角色 */
function ensureChars(acc) {
  var list = charsOf(acc.row[P.nick]);
  if (list.length === 0 && hasLegacyData(acc.row)) list = [legacyChar(acc)];
  return list;
}

function charSummary(c) {
  var xp = Math.max(0, Math.floor(Number(c.row[P.xp]) || 0));
  return { id: String(c.row[P.cid]), name: String(c.row[P.cname]), school: String(c.row[P.school] || ''), level: metaLevel(xp), exp: xp,
           runs: Number(c.row[P.runs]) || 0, wins: Number(c.row[P.wins]) || 0 };
}

/** 校验昵称 + 令牌 + 角色：成功返回 {found: 角色, account: 账号}；没带 char 时用第一个角色（旧客户端 / 旧测试）；一个角色都没有时用旧进度建一个 */
function authedChar(req) {
  var a = authed(req);
  if (a.err) return a;
  var c = null;
  if (req.char !== undefined && req.char !== null && String(req.char) !== '') {
    c = findChar(a.found.row[P.nick], req.char);
    if (!c) return { err: fail('no_char', '找不到这个角色，请重新选择') };
  } else {
    var list = ensureChars(a.found);
    c = list.length ? list[0] : legacyChar(a.found);
  }
  return { found: c, account: a.found };
}

function getChar(req) {
  var a = authed(req);
  if (a.err) return a.err;
  var c = findChar(a.found.row[P.nick], req.char);
  if (!c) return fail('no_char', '找不到这个角色');
  var p = profile(a.found.row, c); p.token = String(a.found.row[P.token]);
  return ok(p);
}

function createChar(req) {
  var a = authed(req);
  if (a.err) return a.err;
  var name = String(req.name || '').trim(), school = String(req.school || '');
  if (!CFG.NICK_RE.test(name)) return fail('bad_name', '角色名要 2–12 个字：中文、字母、数字、下划线');
  if (SCHOOLS.indexOf(school) < 0) return fail('bad_school', '这个流派还没有开放');
  var list = ensureChars(a.found);
  if (list.length >= CFG.MAX_CHARS) return fail('chars_full', '最多只能有 ' + CFG.MAX_CHARS + ' 个角色，请先删除一个');
  for (var i = 0; i < list.length; i++) if (String(list[i].row[P.cname]).toLowerCase() === name.toLowerCase()) return fail('name_taken', '你已经有一个叫这个名字的角色了');
  var row = blankChar();
  row[P.nick] = a.found.row[P.nick]; row[P.invite] = a.found.row[P.invite]; row[P.school] = school;
  row[P.cid] = newCharId(); row[P.cname] = name;
  var c = addCharRow(a.found, row);
  writeLog('info', a.found.row[P.nick], '创建角色 ' + name + '（' + school + '）', 'createChar', '', str(req.device, 120));
  var p = profile(a.found.row, c); p.token = String(a.found.row[P.token]);
  return ok(p);
}

function deleteChar(req) {
  var a = authed(req);
  if (a.err) return a.err;
  var c = findChar(a.found.row[P.nick], req.char);
  if (!c) return fail('no_char', '找不到这个角色');
  c.sheet.deleteRows(c.idx + 2, 1);
  writeLog('info', a.found.row[P.nick], '删除角色 ' + c.row[P.cname], 'deleteChar', '', str(req.device, 120));
  var list = ensureChars(a.found);
  return ok({ chars: list.map(charSummary) });
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

/** 账号资料 + 一个角色的进度。c 缺省 = 第一个角色（没有角色就是空进度）。chars = 全部角色的摘要 */
function profile(row, c) {
  var acc = { row: row };
  var list = c ? charsOf(row[P.nick]) : ensureChars(acc);
  var cur = c || (list.length ? list[0] : null);
  var src = cur ? cur.row : blankChar();
  var state = readState(src);
  var xp = Math.max(0, Math.floor(Number(src[P.xp]) || 0));
  return {
    nick: row[P.nick], school: String(src[P.school] || ''), state: state,
    charId: cur ? String(cur.row[P.cid]) : '', charName: cur ? String(cur.row[P.cname]) : '',
    chars: list.map(charSummary),
    exp: xp, level: metaLevel(xp), alloc: state.alloc || {},
    talents: state.talents || {}, items: state.items || [], equip: state.equip || {},
    silver: Math.max(0, Math.floor(Number(state.silver) || 0)), enh: state.enh || {}, cleared: state.cleared || {},
    invite: String(row[P.invite] || ''), group: groupName(row[P.invite]),
    bests: { score: Number(src[P.bestScore]) || 0, winSec: Number(src[P.bestWin]) || 0, level: Number(src[P.bestLevel]) || 0,
             runs: Number(src[P.runs]) || 0, wins: Number(src[P.wins]) || 0 }
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
var SCHOOLS = ["fist", "sword", "blade", "spear"];
var TALENT_GATE = 3;
var TALENT_PER_LEVEL = 2;
var TALENT_JI_NEED = 99;
var TALENTS = {"gang_force":["gang",0,2,"legacy",0,[],0,0],"gang_body":["gang",0,2,"legacy",0,[],0,0],"gang_crit":["gang",1,2,"legacy",0,[],0,0],"gang_armor":["gang",1,2,"legacy",0,[],0,0],"gang_ying":["gang",2,2,"legacy",0,[],0,0],"gang_dragon":["gang",2,2,"legacy",0,[],0,0],"gang_cm":["gang",3,2,"legacy",0,[],0,0],"gang_force2":["gang",3,2,"legacy",0,[],0,0],"gang_emp":["gang",4,2,"legacy",0,[],0,0],"gang_vajra":["gang",4,3,"legacy",0,[],0,0],"gang_regen":["gang",5,3,"legacy",0,[],0,0],"gang_ying2":["gang",5,3,"legacy",0,[],0,0],"gang_peak":["gang",6,1,"legacy",0,[],0,0],"gang_force3":["gang",6,5,"legacy",0,[],0,0],"rou_regen":["rou",0,2,"legacy",0,[],0,0],"rou_body":["rou",0,2,"legacy",0,[],0,0],"rou_neili":["rou",1,2,"legacy",0,[],0,0],"rou_med":["rou",1,2,"legacy",0,[],0,0],"rou_med2":["rou",2,2,"legacy",0,[],0,0],"rou_shield":["rou",2,2,"legacy",0,[],0,0],"rou_block":["rou",3,2,"legacy",0,[],0,0],"rou_petal":["rou",3,2,"legacy",0,[],0,0],"rou_heal":["rou",4,2,"legacy",0,[],0,0],"rou_finger":["rou",4,3,"legacy",0,[],0,0],"rou_full":["rou",5,3,"legacy",0,[],0,0],"rou_cut":["rou",5,3,"legacy",0,[],0,0],"rou_peak":["rou",6,1,"legacy",0,[],0,0],"rou_armor":["rou",6,5,"legacy",0,[],0,0],"ling_step":["ling",0,2,"legacy",0,[],0,0],"ling_luck":["ling",0,2,"legacy",0,[],0,0],"ling_cd":["ling",1,2,"legacy",0,[],0,0],"ling_qg":["ling",1,2,"legacy",0,[],0,0],"ling_crit":["ling",2,2,"legacy",0,[],0,0],"ling_palm":["ling",2,2,"legacy",0,[],0,0],"ling_exp":["ling",3,2,"legacy",0,[],0,0],"ling_dodge":["ling",3,2,"legacy",0,[],0,0],"ling_cd2":["ling",4,2,"legacy",0,[],0,0],"ling_waste":["ling",4,3,"legacy",0,[],0,0],"ling_luck2":["ling",5,3,"legacy",0,[],0,0],"ling_cm":["ling",5,3,"legacy",0,[],0,0],"ling_peak":["ling",6,1,"legacy",0,[],0,0],"ling_step2":["ling",6,5,"legacy",0,[],0,0],"ji_peak":["ji",7,1,"legacy",0,[],0,0],"fg_a_1":["gang",1,3,"fist",0,[],0,0],"fg_a_2":["gang",3,3,"fist",8,[["fg_a_1","one"]],0,0],"fg_a_3":["gang",5,2,"fist",16,[["fg_a_2","full"]],0,0],"fg_a_4":["gang",7,1,"fist",26,[["fg_a_3","full"]],1,0],"fg_b_1":["gang",2,3,"fist",4,[],0,0],"fg_b_2":["gang",4,3,"fist",12,[["fg_b_1","one"]],0,0],"fg_b_3":["gang",6,2,"fist",20,[["fg_b_2","full"]],0,0],"fg_b_4":["gang",7,1,"fist",26,[["fg_b_3","full"]],1,0],"fg_c_1":["gang",2,3,"fist",4,[],0,0],"fg_c_2":["gang",4,3,"fist",12,[["fg_c_1","one"]],0,0],"fg_c_3":["gang",6,2,"fist",20,[["fg_c_2","full"]],0,0],"fg_c_4":["gang",7,1,"fist",26,[["fg_c_3","full"]],1,0],"fg_g_1":["gang",1,3,"fist",0,[],0,0],"fg_g_2":["gang",2,3,"fist",4,[["fg_g_1","one"]],0,0],"fg_g_3":["gang",3,3,"fist",8,[["fg_g_2","one"]],0,0],"fg_g_4":["gang",4,3,"fist",12,[["fg_g_3","full"]],0,0],"fg_g_5":["gang",5,4,"fist",16,[["fg_g_4","one"]],0,0],"fg_g_6":["gang",6,3,"fist",20,[["fg_g_5","one"]],0,0],"fg_g_7":["gang",7,2,"fist",26,[["fg_g_6","full"]],0,0],"fg_g_8":["gang",8,1,"fist",26,[["fg_g_7","full"]],1,0],"fg_peak":["gang",9,1,"fist",36,[],0,1],"fr_a_1":["rou",1,3,"fist",0,[],0,0],"fr_a_2":["rou",3,3,"fist",8,[["fr_a_1","one"]],0,0],"fr_a_3":["rou",5,2,"fist",16,[["fr_a_2","full"]],0,0],"fr_a_4":["rou",7,1,"fist",26,[["fr_a_3","full"]],1,0],"fr_b_1":["rou",2,3,"fist",4,[],0,0],"fr_b_2":["rou",4,3,"fist",12,[["fr_b_1","one"]],0,0],"fr_b_3":["rou",6,2,"fist",20,[["fr_b_2","full"]],0,0],"fr_b_4":["rou",7,1,"fist",26,[["fr_b_3","full"]],1,0],"fr_c_1":["rou",2,3,"fist",4,[],0,0],"fr_c_2":["rou",4,3,"fist",12,[["fr_c_1","one"]],0,0],"fr_c_3":["rou",6,2,"fist",20,[["fr_c_2","full"]],0,0],"fr_c_4":["rou",7,1,"fist",26,[["fr_c_3","full"]],1,0],"fr_g_1":["rou",1,3,"fist",0,[],0,0],"fr_g_2":["rou",2,3,"fist",4,[["fr_g_1","one"]],0,0],"fr_g_3":["rou",3,3,"fist",8,[["fr_g_2","one"]],0,0],"fr_g_4":["rou",4,3,"fist",12,[["fr_g_3","full"]],0,0],"fr_g_5":["rou",5,4,"fist",16,[["fr_g_4","one"]],0,0],"fr_g_6":["rou",6,3,"fist",20,[["fr_g_5","one"]],0,0],"fr_g_7":["rou",7,2,"fist",26,[["fr_g_6","full"]],0,0],"fr_g_8":["rou",8,1,"fist",26,[["fr_g_7","full"]],1,0],"fr_peak":["rou",9,1,"fist",36,[],0,1],"fl_a_1":["ling",1,2,"fist",0,[],0,0],"fl_a_2":["ling",3,3,"fist",8,[["fl_a_1","one"]],0,0],"fl_a_3":["ling",5,3,"fist",16,[["fl_a_2","full"]],0,0],"fl_a_4":["ling",7,1,"fist",26,[["fl_a_3","full"]],1,0],"fl_b_1":["ling",2,3,"fist",4,[],0,0],"fl_b_2":["ling",4,3,"fist",12,[["fl_b_1","one"]],0,0],"fl_b_3":["ling",6,2,"fist",20,[["fl_b_2","full"]],0,0],"fl_b_4":["ling",7,1,"fist",26,[["fl_b_3","full"]],1,0],"fl_c_1":["ling",2,3,"fist",4,[],0,0],"fl_c_2":["ling",4,3,"fist",12,[["fl_c_1","one"]],0,0],"fl_c_3":["ling",6,2,"fist",20,[["fl_c_2","full"]],0,0],"fl_c_4":["ling",7,1,"fist",26,[["fl_c_3","full"]],1,0],"fl_g_1":["ling",1,4,"fist",0,[],0,0],"fl_g_2":["ling",2,3,"fist",4,[["fl_g_1","one"]],0,0],"fl_g_3":["ling",3,3,"fist",8,[["fl_g_2","one"]],0,0],"fl_g_4":["ling",4,3,"fist",12,[["fl_g_3","full"]],0,0],"fl_g_5":["ling",5,3,"fist",16,[["fl_g_4","one"]],0,0],"fl_g_6":["ling",6,3,"fist",20,[["fl_g_5","one"]],0,0],"fl_g_7":["ling",7,2,"fist",26,[["fl_g_6","full"]],0,0],"fl_g_8":["ling",8,1,"fist",26,[["fl_g_7","full"]],1,0],"fl_peak":["ling",9,1,"fist",36,[],0,1],"fist_ji":["ji",10,1,"fist",0,[],0,0],"sg_a_1":["gang",1,3,"sword",0,[],0,0],"sg_a_2":["gang",3,3,"sword",8,[["sg_a_1","one"]],0,0],"sg_a_3":["gang",5,2,"sword",16,[["sg_a_2","full"]],0,0],"sg_a_4":["gang",7,1,"sword",26,[["sg_a_3","full"]],1,0],"sg_b_1":["gang",2,3,"sword",4,[],0,0],"sg_b_2":["gang",4,3,"sword",12,[["sg_b_1","one"]],0,0],"sg_b_3":["gang",6,2,"sword",20,[["sg_b_2","full"]],0,0],"sg_b_4":["gang",7,1,"sword",26,[["sg_b_3","full"]],1,0],"sg_c_1":["gang",2,3,"sword",4,[],0,0],"sg_c_2":["gang",4,3,"sword",12,[["sg_c_1","one"]],0,0],"sg_c_3":["gang",6,2,"sword",20,[["sg_c_2","full"]],0,0],"sg_c_4":["gang",7,1,"sword",26,[["sg_c_3","full"]],1,0],"sg_g_1":["gang",1,3,"sword",0,[],0,0],"sg_g_2":["gang",2,3,"sword",4,[["sg_g_1","one"]],0,0],"sg_g_3":["gang",4,4,"sword",12,[["sg_g_2","one"]],0,0],"sg_g_4":["gang",6,3,"sword",20,[["sg_g_3","full"]],0,0],"sg_g_5":["gang",7,4,"sword",26,[["sg_g_4","one"]],0,0],"sg_g_6":["gang",8,5,"sword",26,[["sg_g_5","full"]],0,0],"sg_peak":["gang",9,1,"sword",36,[],0,1],"sr_a_1":["rou",1,3,"sword",0,[],0,0],"sr_a_2":["rou",3,3,"sword",8,[["sr_a_1","one"]],0,0],"sr_a_3":["rou",5,2,"sword",16,[["sr_a_2","full"]],0,0],"sr_a_4":["rou",7,1,"sword",26,[["sr_a_3","full"]],1,0],"sr_b_1":["rou",2,3,"sword",4,[],0,0],"sr_b_2":["rou",4,3,"sword",12,[["sr_b_1","one"]],0,0],"sr_b_3":["rou",6,2,"sword",20,[["sr_b_2","full"]],0,0],"sr_b_4":["rou",7,1,"sword",26,[["sr_b_3","full"]],1,0],"sr_c_1":["rou",2,3,"sword",4,[],0,0],"sr_c_2":["rou",4,3,"sword",12,[["sr_c_1","one"]],0,0],"sr_c_3":["rou",6,2,"sword",20,[["sr_c_2","full"]],0,0],"sr_c_4":["rou",7,1,"sword",26,[["sr_c_3","full"]],1,0],"sr_g_1":["rou",1,3,"sword",0,[],0,0],"sr_g_2":["rou",2,4,"sword",4,[["sr_g_1","one"]],0,0],"sr_g_3":["rou",4,3,"sword",12,[["sr_g_2","one"]],0,0],"sr_g_4":["rou",6,3,"sword",20,[["sr_g_3","full"]],0,0],"sr_g_5":["rou",7,4,"sword",26,[["sr_g_4","one"]],0,0],"sr_g_6":["rou",8,5,"sword",26,[["sr_g_5","full"]],0,0],"sr_peak":["rou",9,1,"sword",36,[],0,1],"sl_a_1":["ling",1,3,"sword",0,[],0,0],"sl_a_2":["ling",2,1,"sword",4,[["sl_a_1","one"]],0,0],"sl_a_3":["ling",4,3,"sword",12,[["sl_a_2","full"]],0,0],"sl_a_4":["ling",5,2,"sword",16,[["sl_a_3","full"]],0,0],"sl_a_5":["ling",7,1,"sword",26,[["sl_a_4","full"]],1,0],"sl_b_1":["ling",1,4,"sword",0,[],0,0],"sl_b_2":["ling",2,2,"sword",4,[["sl_b_1","one"]],0,0],"sl_b_3":["ling",4,2,"sword",12,[["sl_b_2","full"]],0,0],"sl_b_4":["ling",5,2,"sword",16,[["sl_b_3","full"]],0,0],"sl_b_5":["ling",7,1,"sword",26,[["sl_b_4","full"]],1,0],"sl_c_1":["ling",1,3,"sword",0,[],0,0],"sl_c_2":["ling",2,2,"sword",4,[["sl_c_1","one"]],0,0],"sl_c_3":["ling",4,2,"sword",12,[["sl_c_2","full"]],0,0],"sl_c_4":["ling",5,2,"sword",16,[["sl_c_3","full"]],0,0],"sl_c_5":["ling",7,1,"sword",26,[["sl_c_4","full"]],1,0],"sl_d_1":["ling",1,3,"sword",0,[],0,0],"sl_d_2":["ling",3,2,"sword",8,[["sl_d_1","one"]],0,0],"sl_d_3":["ling",7,1,"sword",26,[["sl_d_2","full"]],1,0],"sl_e_1":["ling",1,3,"sword",0,[],0,0],"sl_e_2":["ling",3,2,"sword",8,[["sl_e_1","one"]],0,0],"sl_e_3":["ling",7,1,"sword",26,[["sl_e_2","full"]],1,0],"sl_f_1":["ling",1,3,"sword",0,[],0,0],"sl_f_2":["ling",3,2,"sword",8,[["sl_f_1","one"]],0,0],"sl_f_3":["ling",7,1,"sword",26,[["sl_f_2","full"]],1,0],"sl_peak":["ling",9,1,"sword",36,[],0,1],"sword_ji":["ji",10,1,"sword",0,[],0,0],"bg_a_1":["gang",1,3,"blade",0,[],0,0],"bg_a_2":["gang",3,3,"blade",8,[["bg_a_1","one"]],0,0],"bg_a_3":["gang",5,2,"blade",16,[["bg_a_2","full"]],0,0],"bg_a_4":["gang",7,1,"blade",26,[["bg_a_3","full"]],1,0],"bg_b_1":["gang",2,3,"blade",4,[],0,0],"bg_b_2":["gang",4,3,"blade",12,[["bg_b_1","one"]],0,0],"bg_b_3":["gang",6,2,"blade",20,[["bg_b_2","full"]],0,0],"bg_b_4":["gang",7,1,"blade",26,[["bg_b_3","full"]],1,0],"bg_c_1":["gang",2,3,"blade",4,[],0,0],"bg_c_2":["gang",4,3,"blade",12,[["bg_c_1","one"]],0,0],"bg_c_3":["gang",6,2,"blade",20,[["bg_c_2","full"]],0,0],"bg_c_4":["gang",7,1,"blade",26,[["bg_c_3","full"]],1,0],"bg_g_1":["gang",1,3,"blade",0,[],0,0],"bg_g_2":["gang",2,3,"blade",4,[["bg_g_1","one"]],0,0],"bg_g_3":["gang",3,3,"blade",8,[["bg_g_2","one"]],0,0],"bg_g_4":["gang",4,3,"blade",12,[["bg_g_3","full"]],0,0],"bg_g_5":["gang",5,4,"blade",16,[["bg_g_4","one"]],0,0],"bg_g_6":["gang",6,3,"blade",20,[["bg_g_5","one"]],0,0],"bg_g_7":["gang",7,2,"blade",26,[["bg_g_6","full"]],0,0],"bg_g_8":["gang",8,1,"blade",26,[["bg_g_7","full"]],1,0],"bg_peak":["gang",9,1,"blade",36,[],0,1],"br_a_1":["rou",1,3,"blade",0,[],0,0],"br_a_2":["rou",3,3,"blade",8,[["br_a_1","one"]],0,0],"br_a_3":["rou",5,2,"blade",16,[["br_a_2","full"]],0,0],"br_a_4":["rou",7,1,"blade",26,[["br_a_3","full"]],1,0],"br_b_1":["rou",2,3,"blade",4,[],0,0],"br_b_2":["rou",4,3,"blade",12,[["br_b_1","one"]],0,0],"br_b_3":["rou",6,2,"blade",20,[["br_b_2","full"]],0,0],"br_b_4":["rou",7,1,"blade",26,[["br_b_3","full"]],1,0],"br_c_1":["rou",2,3,"blade",4,[],0,0],"br_c_2":["rou",4,3,"blade",12,[["br_c_1","one"]],0,0],"br_c_3":["rou",6,2,"blade",20,[["br_c_2","full"]],0,0],"br_c_4":["rou",7,1,"blade",26,[["br_c_3","full"]],1,0],"br_g_1":["rou",1,3,"blade",0,[],0,0],"br_g_2":["rou",2,3,"blade",4,[["br_g_1","one"]],0,0],"br_g_3":["rou",3,3,"blade",8,[["br_g_2","one"]],0,0],"br_g_4":["rou",4,3,"blade",12,[["br_g_3","full"]],0,0],"br_g_5":["rou",5,4,"blade",16,[["br_g_4","one"]],0,0],"br_g_6":["rou",6,3,"blade",20,[["br_g_5","one"]],0,0],"br_g_7":["rou",7,2,"blade",26,[["br_g_6","full"]],0,0],"br_g_8":["rou",8,1,"blade",26,[["br_g_7","full"]],1,0],"br_peak":["rou",9,1,"blade",36,[],0,1],"bl_a_1":["ling",1,3,"blade",0,[],0,0],"bl_a_2":["ling",3,3,"blade",8,[["bl_a_1","one"]],0,0],"bl_a_3":["ling",5,2,"blade",16,[["bl_a_2","full"]],0,0],"bl_a_4":["ling",7,1,"blade",26,[["bl_a_3","full"]],1,0],"bl_b_1":["ling",2,3,"blade",4,[],0,0],"bl_b_2":["ling",4,3,"blade",12,[["bl_b_1","one"]],0,0],"bl_b_3":["ling",6,2,"blade",20,[["bl_b_2","full"]],0,0],"bl_b_4":["ling",7,1,"blade",26,[["bl_b_3","full"]],1,0],"bl_c_1":["ling",2,3,"blade",4,[],0,0],"bl_c_2":["ling",4,3,"blade",12,[["bl_c_1","one"]],0,0],"bl_c_3":["ling",6,2,"blade",20,[["bl_c_2","full"]],0,0],"bl_c_4":["ling",7,1,"blade",26,[["bl_c_3","full"]],1,0],"bl_g_1":["ling",1,4,"blade",0,[],0,0],"bl_g_2":["ling",2,3,"blade",4,[["bl_g_1","one"]],0,0],"bl_g_3":["ling",3,3,"blade",8,[["bl_g_2","one"]],0,0],"bl_g_4":["ling",4,3,"blade",12,[["bl_g_3","full"]],0,0],"bl_g_5":["ling",5,3,"blade",16,[["bl_g_4","one"]],0,0],"bl_g_6":["ling",6,3,"blade",20,[["bl_g_5","one"]],0,0],"bl_g_7":["ling",7,2,"blade",26,[["bl_g_6","full"]],0,0],"bl_g_8":["ling",8,1,"blade",26,[["bl_g_7","full"]],1,0],"bl_peak":["ling",9,1,"blade",36,[],0,1],"blade_ji":["ji",10,1,"blade",0,[],0,0],"pg_a_1":["gang",1,3,"spear",0,[],0,0],"pg_a_2":["gang",3,3,"spear",8,[["pg_a_1","one"]],0,0],"pg_a_3":["gang",5,2,"spear",16,[["pg_a_2","full"]],0,0],"pg_a_4":["gang",7,1,"spear",26,[["pg_a_3","full"]],1,0],"pg_b_1":["gang",2,3,"spear",4,[],0,0],"pg_b_2":["gang",4,3,"spear",12,[["pg_b_1","one"]],0,0],"pg_b_3":["gang",6,2,"spear",20,[["pg_b_2","full"]],0,0],"pg_b_4":["gang",7,1,"spear",26,[["pg_b_3","full"]],1,0],"pg_c_1":["gang",2,3,"spear",4,[],0,0],"pg_c_2":["gang",4,3,"spear",12,[["pg_c_1","one"]],0,0],"pg_c_3":["gang",6,2,"spear",20,[["pg_c_2","full"]],0,0],"pg_c_4":["gang",7,1,"spear",26,[["pg_c_3","full"]],1,0],"pg_g_1":["gang",1,3,"spear",0,[],0,0],"pg_g_2":["gang",2,3,"spear",4,[["pg_g_1","one"]],0,0],"pg_g_3":["gang",3,3,"spear",8,[["pg_g_2","one"]],0,0],"pg_g_4":["gang",4,3,"spear",12,[["pg_g_3","full"]],0,0],"pg_g_5":["gang",5,4,"spear",16,[["pg_g_4","one"]],0,0],"pg_g_6":["gang",6,3,"spear",20,[["pg_g_5","one"]],0,0],"pg_g_7":["gang",7,2,"spear",26,[["pg_g_6","full"]],0,0],"pg_g_8":["gang",8,1,"spear",26,[["pg_g_7","full"]],1,0],"pg_peak":["gang",9,1,"spear",36,[],0,1],"pr_a_1":["rou",1,3,"spear",0,[],0,0],"pr_a_2":["rou",3,3,"spear",8,[["pr_a_1","one"]],0,0],"pr_a_3":["rou",5,2,"spear",16,[["pr_a_2","full"]],0,0],"pr_a_4":["rou",7,1,"spear",26,[["pr_a_3","full"]],1,0],"pr_b_1":["rou",2,3,"spear",4,[],0,0],"pr_b_2":["rou",4,3,"spear",12,[["pr_b_1","one"]],0,0],"pr_b_3":["rou",6,2,"spear",20,[["pr_b_2","full"]],0,0],"pr_b_4":["rou",7,1,"spear",26,[["pr_b_3","full"]],1,0],"pr_c_1":["rou",2,3,"spear",4,[],0,0],"pr_c_2":["rou",4,3,"spear",12,[["pr_c_1","one"]],0,0],"pr_c_3":["rou",6,2,"spear",20,[["pr_c_2","full"]],0,0],"pr_c_4":["rou",7,1,"spear",26,[["pr_c_3","full"]],1,0],"pr_g_1":["rou",1,3,"spear",0,[],0,0],"pr_g_2":["rou",2,3,"spear",4,[["pr_g_1","one"]],0,0],"pr_g_3":["rou",3,3,"spear",8,[["pr_g_2","one"]],0,0],"pr_g_4":["rou",4,3,"spear",12,[["pr_g_3","full"]],0,0],"pr_g_5":["rou",5,4,"spear",16,[["pr_g_4","one"]],0,0],"pr_g_6":["rou",6,3,"spear",20,[["pr_g_5","one"]],0,0],"pr_g_7":["rou",7,2,"spear",26,[["pr_g_6","full"]],0,0],"pr_g_8":["rou",8,1,"spear",26,[["pr_g_7","full"]],1,0],"pr_peak":["rou",9,1,"spear",36,[],0,1],"pl_a_1":["ling",1,3,"spear",0,[],0,0],"pl_a_2":["ling",3,3,"spear",8,[["pl_a_1","one"]],0,0],"pl_a_3":["ling",5,2,"spear",16,[["pl_a_2","full"]],0,0],"pl_a_4":["ling",7,1,"spear",26,[["pl_a_3","full"]],1,0],"pl_b_1":["ling",2,3,"spear",4,[],0,0],"pl_b_2":["ling",4,3,"spear",12,[["pl_b_1","one"]],0,0],"pl_b_3":["ling",6,2,"spear",20,[["pl_b_2","full"]],0,0],"pl_b_4":["ling",7,1,"spear",26,[["pl_b_3","full"]],1,0],"pl_c_1":["ling",2,3,"spear",4,[],0,0],"pl_c_2":["ling",4,3,"spear",12,[["pl_c_1","one"]],0,0],"pl_c_3":["ling",6,2,"spear",20,[["pl_c_2","full"]],0,0],"pl_c_4":["ling",7,1,"spear",26,[["pl_c_3","full"]],1,0],"pl_g_1":["ling",1,3,"spear",0,[],0,0],"pl_g_2":["ling",2,3,"spear",4,[["pl_g_1","one"]],0,0],"pl_g_3":["ling",3,3,"spear",8,[["pl_g_2","one"]],0,0],"pl_g_4":["ling",4,3,"spear",12,[["pl_g_3","full"]],0,0],"pl_g_5":["ling",5,4,"spear",16,[["pl_g_4","one"]],0,0],"pl_g_6":["ling",6,3,"spear",20,[["pl_g_5","one"]],0,0],"pl_g_7":["ling",7,2,"spear",26,[["pl_g_6","full"]],0,0],"pl_g_8":["ling",8,1,"spear",26,[["pl_g_7","full"]],1,0],"pl_peak":["ling",9,1,"spear",36,[],0,1],"spear_ji":["ji",10,1,"spear",0,[],0,0]};
var GEAR = {"slots":["weapon","coat","pants","boots","charm"],"weights":[60,30,9,1],"invMax":40,"mini":1,"bossMin":1,"bossExtra":0.5,"enh":{"max":10,"bonus":0.08,"costBase":[12,30,70,160],"costExp":1.6},"silver":{"perScore":120,"cap":300,"winBonus":60,"comp":0.5,"discard":[3,10,40,120],"max":999999}};
var MAPS = {"black_wind":{"minTimes":[180,330,480],"finalT":600,"minWin":620,"requires":"","expMult":1.0,"runCap":400,"capLevel":15,"dropWeights":[70,27,3,0]},"guangming":{"minTimes":[180,360,540],"finalT":780,"minWin":800,"requires":"","expMult":2.0,"runCap":800,"capLevel":25,"dropWeights":[35,40,20,5]},"taohua":{"minTimes":[200,400,600],"finalT":840,"minWin":860,"requires":"guangming","expMult":3.0,"runCap":1200,"capLevel":32,"dropWeights":[15,35,35,15]}};
var DIFF = {"expMeta":0.5,"dropBonus":0.0,"raritySkew":0.5};
// END GENERATED

// ---------------------------------------------------------------- 局外成长（scripts/meta.gd 里有同一份，共用 meta_vectors.json 测试）
var META = { MAX_LEVEL: 50, PER_LEVEL: 3, ATTR_CAP: 99, EXP_CAP: 400, WIN_BONUS: 40, FIRST_WIN_BONUS: 100,
             ATTRS: ['pow', 'agi', 'vit', 'int', 'luk'] };
/** 升级曲线倍率（scripts/meta.gd 里有同一份）：1~15 级 ×0.75；15~30 → 2.2；30~40 → 3.5；40 以上 → 5.5 */
function metaCurve(l) {
  if (l <= 15) return 0.75;
  if (l <= 30) return 0.75 + (l - 15) * (1.45 / 15.0);
  if (l <= 40) return 2.2 + (l - 30) * 0.13;
  return 3.5 + (l - 40) * 0.2;
}
function metaNeed(l) { return Math.floor((40 + 6 * l) * metaCurve(l) + 0.5); }
function metaReach(level) { var t = 0; for (var l = 1; l < level; l++) t += metaNeed(l); return t; }
/** 地图的修为上限：cap_level 级再加半级；到了就不再给修为 */
function metaCapped(gained, cur, capLevel) {
  if (!(capLevel > 0)) return gained;
  var capExp = metaReach(capLevel) + Math.floor(metaNeed(capLevel) / 2);
  return Math.max(0, Math.min(gained, capExp - cur));
}
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
function metaRunExp(score, won, first, comp, mx, level) {
  var mm = mx && mx.expMult ? mx.expMult : 1, cap = mx && mx.runCap ? mx.runCap : META.EXP_CAP;
  var x = Math.min(cap, Math.round(score / 80 * mm));
  if (won) x += Math.round((META.WIN_BONUS + (first ? META.FIRST_WIN_BONUS : 0)) * mm);
  var low = (level > 0 && level <= 15) ? 1.5 : 1;   // 局外 1~15 级：修为 +50%
  return Math.round(x * (1 + ((comp || 1) - 1) * DIFF.expMeta) * low);
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

/** 天赋校验：节点存在、不超过上限；按「组」（legacy 旧树 / 各流派新树）分别检查：
 *  每组总点数 ≤ 局外等级 × TALENT_PER_LEVEL（每级 2 点）；极意需要本组其余节点共 TALENT_JI_NEED 点；
 *  旧树：本系「更低层」投入合计 ≥ 层号 × TALENT_GATE；
 *  新树：本系其余节点投入 ≥ 层门槛，前置节点（one=≥1 点 / full=点满）满足，巅峰需要本系至少一个终极。
 *  节点表项：[系, 层/行, 上限, 组, 层门槛, 前置, 终极?, 巅峰?] */
var TALENT_WHY = '';
function tfail(msg) { TALENT_WHY = msg; return null; }

function cleanTalents(t, level) {
  TALENT_WHY = '';
  if (typeof t !== 'object' || t === null || Array.isArray(t)) return tfail('格式不对');
  var out = {}, ids = Object.keys(t), i;
  for (i = 0; i < ids.length; i++) {
    var id = ids[i], n = TALENTS[id], v = Number(t[id]);
    if (!n) return tfail('服务器不认识节点 ' + id + '（后端代码是否已更新到最新版？）');
    if (!(v >= 0 && v <= n[2]) || Math.floor(v) !== v) return tfail('节点 ' + id + ' 点数超过上限');
    if (v > 0) out[id] = v;
  }
  var all = Object.keys(out), totals = {};
  for (i = 0; i < all.length; i++) { var g0 = TALENTS[all[i]][3]; totals[g0] = (totals[g0] || 0) + out[all[i]]; }
  for (var g in totals) if (totals[g] > level * TALENT_PER_LEVEL) return tfail('「' + g + '」组共 ' + totals[g] + ' 点，超过可用点数 ' + level * TALENT_PER_LEVEL + '（服务器记录的局外等级是 ' + level + '）');
  for (var a = 0; a < all.length; a++) {
    var na = TALENTS[all[a]], grp = na[3], bsum = 0, lower = 0, hasCap = false;
    if (na[0] === 'ji') {                       // 极意：本组其余节点共 TALENT_JI_NEED 点才出现
      if (totals[grp] - out[all[a]] < TALENT_JI_NEED) return tfail('极意需要本组其余节点共 ' + TALENT_JI_NEED + ' 点');
      continue;
    }
    for (var b = 0; b < all.length; b++) {
      var nb = TALENTS[all[b]];
      if (nb[3] !== grp || nb[0] !== na[0]) continue;
      if (all[b] !== all[a]) bsum += out[all[b]];
      if (nb[1] < na[1]) lower += out[all[b]];
      if (nb[6] && out[all[b]] > 0) hasCap = true;
    }
    if (grp === 'legacy') {
      if (lower < na[1] * TALENT_GATE) return tfail('节点 ' + all[a] + ' 的层数还没解锁');
    } else {
      if (bsum < na[4]) return tfail('节点 ' + all[a] + ' 需要本系其余节点已投入 ' + na[4] + ' 点');
      for (var r = 0; r < na[5].length; r++) {
        var rq = na[5][r], have = out[rq[0]] || 0;
        if (have < (rq[1] === 'full' ? TALENTS[rq[0]][2] : 1)) return tfail('节点 ' + all[a] + ' 的前置 ' + rq[0] + ' 没满足');
      }
      if (na[7] && !hasCap) return tfail('巅峰需要本系至少一个终极');
    }
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
function gearWeight(i, comp, w) { return (w && w.length > i ? w[i] : GEAR.weights[i]) * (1 + ((comp || 1) - 1) * DIFF.raritySkew * i); }
function gearRoll(comp, map) {
  var total = 0, i, w = map && MAPS[map] ? MAPS[map].dropWeights : null;
  for (i = 0; i < GEAR.weights.length; i++) total += gearWeight(i, comp, w);
  var x = Math.random() * total, r = 0;
  for (i = 0; i < GEAR.weights.length; i++) { x -= gearWeight(i, comp, w); if (x < 0) { r = i; break; } }
  return GEAR.slots[Math.floor(Math.random() * GEAR.slots.length)] + '.' + r + '.' + (1 + Math.floor(Math.random() * 999999));
}
/** 掉落：每个被击败的小 Boss 固定 1 件；大 Boss（通关）GEAR.bossMin 件，另有 GEAR.bossExtra 的几率再多 1 件（共 1~2 件）。
 *  返回新掉落的编码，并写进 state.items（超过上限先丢最低稀有度、最早的未穿戴装备） */
function gearDrops(state, comp, minis, won, map) {
  var n = minis + (won ? GEAR.bossMin + (Math.random() < GEAR.bossExtra ? 1 : 0) : 0), codes = [];
  state.items = Array.isArray(state.items) ? state.items : [];
  for (var i = 0; i < n; i++) { var c = gearRoll(comp, map); codes.push(c); state.items.push(c); }
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
  var a = authedChar(req);
  if (a.err) return a.err;
  var v = validateRun(req);
  if (v.ok === false) { writeLog('warn', req.nick, '拒绝成绩', 'submit', JSON.stringify(req).slice(0, 300), str(req.device, 120)); return v; }
  var run = v.run, f = a.found, row = f.row;
  // 幂等：同一局（客户端生成的 rid）只记一次。回应丢了、客户端补传时不会重复加修为 / 掉落 / 局数
  var rid = str(req.rid, 40);
  if (rid) {
    var st0 = readState(row);
    if (Array.isArray(st0.rids) && st0.rids.indexOf(rid) >= 0) {
      var pr0 = profile(a.account.row, f);
      return ok({ dup: true, score: 0, best: false, ranks: {}, bests: pr0.bests, gained: 0, capped: false, exp: pr0.exp, level: pr0.level, levelUp: false,
                  drops: [], comp: 1, silverGained: 0, silver: pr0.silver, cleared: pr0.cleared });
    }
  }
  var req0 = MAPS[run.map].requires;
  if (req0) { var cl = readState(row).cleared; if (!cl || !cl[req0]) return fail('locked', '这张地图还没解锁（需要先通关前一关）'); }
  // 提交间隔只看上一次「提交成绩」的时间（不能用 Updated：创建角色的云存档也会更新它）
  if (now() - toMs(row[P.lastSubmit]) < CFG.SUBMIT_GAP_SEC * 1000) return fail('too_fast', '提交太频繁，请稍后再试');

  var score = computeScore(run);
  var preBest = { score: Number(row[P.bestScore]) || 0, win: Number(row[P.bestWin]) || 0, level: Number(row[P.bestLevel]) || 0 };   // 分地图成绩的旧数据迁移用：改版前所有成绩都来自黑风寨
  var school = str(req.school, 16), starter = str(req.starter, 24), qg = str(req.qinggong, 24), enh = str(req.enhance, 40);
  var build = str(typeof req.build === 'string' ? req.build : JSON.stringify(req.build || []), 600);
  sheet('scores').appendRow([iso(), row[P.cname], run.won ? '通关' : '阵亡', score, Math.round(run.seconds), run.level, run.kills,
                             run.bosses, school, starter, qg, enh, build, str(req.version, 12), str(req.device, 120)]);

  var best = score > (Number(row[P.bestScore]) || 0);
  var firstWin = run.won && !(Number(row[P.wins]) > 0);
  var comp = diffComp(req.difficulty);
  var mm = MAPS[run.map];
  var gained0 = metaRunExp(score, run.won, firstWin, comp, mm, metaLevel(Number(row[P.xp]) || 0));
  var gained = metaCapped(gained0, Number(row[P.xp]) || 0, mm.capLevel);
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
  drops = gearDrops(stt, comp, Math.min(minis, spawned), run.won, run.map);
  if (rid) stt.rids = (Array.isArray(stt.rids) ? stt.rids : []).concat([rid]).slice(-30);
  row[P.state] = JSON.stringify(stt);
  row[P.updated] = iso();
  row[P.lastSubmit] = iso();
  savePlayer(f);

  var ranks = {
    score: rankOf(row[P.cid], 'score'),
    speed: rankOf(row[P.cid], 'speed'),
    level: rankOf(row[P.cid], 'level')
  };
  var pr = profile(a.account.row, f);
  return ok({ score: score, best: best, ranks: ranks, bests: pr.bests, gained: gained, capped: gained < gained0, exp: pr.exp, level: pr.level, levelUp: pr.level > oldLevel, drops: drops, comp: comp, silverGained: silverGained, silver: pr.silver, cleared: pr.cleared });
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
  var cl = loadChars();
  var banned = {};
  loadPlayers().rows.forEach(function (r) { if (truthy(r[P.banned])) banned[String(r[P.nick]).toLowerCase()] = true; });
  var list = [];
  var want = String(group || '').toUpperCase();
  cl.rows.forEach(function (r) {
    if (banned[String(r[P.nick]).toLowerCase()]) return;
    if (want && String(r[P.invite]).toUpperCase() !== want) return;
    var v = Number(r[spec.col]) || 0;
    if (map) {     // 地图榜：取该角色在这张地图上的最佳；没有记录 = 没打过
      var mbs = readState(r).mapBests;
      v = mbs && mbs[map] ? Number(mbs[map][BOARD_FIELD[kind]]) || 0 : 0;
    }
    if (v <= 0) return;
    list.push({ nick: String(r[P.cname]), owner: String(r[P.nick]), id: String(r[P.cid]), value: v, school: String(r[P.school] || ''), wins: Number(r[P.wins]) || 0 });
  });
  list.sort(function (x, y) { return spec.asc ? x.value - y.value : y.value - x.value; });
  return list;
}

function rankOf(id, kind) {
  var list = boardRows(kind);
  for (var i = 0; i < list.length; i++) if (list[i].id === String(id)) return i + 1;
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
  var wantId = String(req.char || '');
  if (wantId) { for (var j = 0; j < list.length; j++) if (list[j].id === wantId) { me = { rank: j + 1, value: list[j].value }; break; } }
  else if (want) for (var i = 0; i < list.length; i++) if (list[i].owner.toLowerCase() === want) { me = { rank: i + 1, value: list[i].value }; break; }
  return ok({ kind: kind, rows: rows, me: me, total: list.length, group: group ? groupName(group) : '', map: map });
}

// ---------------------------------------------------------------- 云存档 / 反馈 / 日志
function saveState(req) {
  var a = authedChar(req);
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
    if (!tl) return fail('bad_state', '天赋加点不合法：' + TALENT_WHY);
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
  var a = authedChar(req);
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
  [loadPlayers(), loadChars()].forEach(function (tbl) {
    tbl.rows.forEach(function (row, i) {
      row[P.runs] = 0; row[P.wins] = 0; row[P.bestScore] = 0; row[P.bestWin] = 0; row[P.bestLevel] = 0; row[P.kills] = 0;
      tbl.sheet.getRange(i + 2, 1, 1, row.length).setValues([row]);
    });
  });
  tell('已清空，新赛季开始。');
}
