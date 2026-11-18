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
  invites:  ['代码 Code', '名称 Name', '开放 Active', '建立 Created', '可用次数 MaxUses(0=不限)', '已用 Used', '备注 Note'],
  players:  ['昵称 Nickname', '邀请码 Invite', 'salt', 'pinHash', '建立 Created', '最后登入 Last login', 'token', 'tokenExp',
             'fails', 'lockUntil', '封禁 Banned', '最后更新 Updated', '局数 Runs', '通关 Wins', '最高分 BestScore',
             '最快通关秒 BestWinSec', '最高等级 BestLevel', '总击杀 Kills', '流派 School', 'state', '最后提交 LastSubmit'],
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
  STATE_MAX: 2000
};

// 列下标（0 起）
var P = { nick: 0, invite: 1, salt: 2, hash: 3, created: 4, last: 5, token: 6, exp: 7, fails: 8, lock: 9, banned: 10,
          updated: 11, runs: 12, wins: 13, bestScore: 14, bestWin: 15, bestLevel: 16, kills: 17, school: 18, state: 19, lastSubmit: 20 };

// ---------------------------------------------------------------- 时间 / 工具
function now() { return new Date().getTime(); }
function iso(ms) { return new Date(ms === undefined ? now() : ms).toISOString(); }
/** 单元格里的时间 → 毫秒。Google 表格会把 ISO 字符串自动转成 Date 对象，两种都要认。 */
function toMs(v) {
  if (v instanceof Date) return v.getTime();
  var t = Date.parse(v);
  return isFinite(t) ? t : 0;
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
  var TEXT_COLS = { players: [1, 2, 3, 4, 7], scores: [2], logs: [3], feedback: [1, 3] };
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

function profile(row) {
  var state = {};
  try { state = JSON.parse(row[P.state] || '{}'); } catch (e) {}
  return {
    nick: row[P.nick], school: String(row[P.school] || ''), state: state,
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
  if (s.won && (s.seconds < 700 || s.bosses < 1)) return fail('bad_run', '成绩无效（通关）');
  return { run: s };
}

function submitScore(req) {
  var a = authed(req);
  if (a.err) return a.err;
  var v = validateRun(req);
  if (v.ok === false) { writeLog('warn', req.nick, '拒绝成绩', 'submit', JSON.stringify(req).slice(0, 300), str(req.device, 120)); return v; }
  var run = v.run, f = a.found, row = f.row;
  // 提交间隔只看上一次「提交成绩」的时间（不能用 Updated：创建角色的云存档也会更新它）
  if (now() - toMs(row[P.lastSubmit]) < CFG.SUBMIT_GAP_SEC * 1000) return fail('too_fast', '提交太频繁，请稍后再试');

  var score = computeScore(run);
  var school = str(req.school, 16), starter = str(req.starter, 24), qg = str(req.qinggong, 24), enh = str(req.enhance, 40);
  var build = str(typeof req.build === 'string' ? req.build : JSON.stringify(req.build || []), 600);
  sheet('scores').appendRow([iso(), row[P.nick], run.won ? '通关' : '阵亡', score, Math.round(run.seconds), run.level, run.kills,
                             run.bosses, school, starter, qg, enh, build, str(req.version, 12), str(req.device, 120)]);

  var best = score > (Number(row[P.bestScore]) || 0);
  row[P.runs] = (Number(row[P.runs]) || 0) + 1;
  row[P.kills] = (Number(row[P.kills]) || 0) + run.kills;
  if (best) row[P.bestScore] = score;
  if (run.level > (Number(row[P.bestLevel]) || 0)) row[P.bestLevel] = run.level;
  if (run.won) {
    row[P.wins] = (Number(row[P.wins]) || 0) + 1;
    var bw = Number(row[P.bestWin]) || 0;
    if (bw === 0 || run.seconds < bw) row[P.bestWin] = Math.round(run.seconds);
  }
  row[P.updated] = iso();
  row[P.lastSubmit] = iso();
  savePlayer(f);

  var ranks = {
    score: rankOf(row[P.nick], 'score'),
    speed: rankOf(row[P.nick], 'speed'),
    level: rankOf(row[P.nick], 'level')
  };
  return ok({ score: score, best: best, ranks: ranks, bests: profile(row).bests });
}

// ---------------------------------------------------------------- 排行榜
var BOARD = {
  score: { col: P.bestScore, asc: false },
  speed: { col: P.bestWin,   asc: true },
  level: { col: P.bestLevel, asc: false }
};

function boardRows(kind) {
  var spec = BOARD[kind];
  var pl = loadPlayers();
  var list = [];
  pl.rows.forEach(function (r) {
    if (truthy(r[P.banned])) return;
    var v = Number(r[spec.col]) || 0;
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
  var list = boardRows(kind);
  var me = null;
  var want = String(req.nick || '').toLowerCase();
  var rows = list.slice(0, CFG.BOARD_SIZE).map(function (e, i) { e.rank = i + 1; return e; });
  if (want) for (var i = 0; i < list.length; i++) if (list[i].nick.toLowerCase() === want) me = { rank: i + 1, value: list[i].value };
  return ok({ kind: kind, rows: rows, me: me, total: list.length });
}

// ---------------------------------------------------------------- 云存档 / 反馈 / 日志
function saveState(req) {
  var a = authed(req);
  if (a.err) return a.err;
  var st = req.state;
  if (typeof st !== 'object' || st === null) return fail('bad_state', '存档格式不对');
  var text = JSON.stringify(st);
  if (text.length > CFG.STATE_MAX) return fail('bad_state', '存档太大');
  var school = String(st.school || '');
  if (school !== '' && !/^[a-z_]{1,16}$/.test(school)) return fail('bad_state', '存档格式不对');
  a.found.row[P.state] = text;
  a.found.row[P.school] = school;
  a.found.row[P.updated] = iso();
  savePlayer(a.found);
  return ok({});
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
  var code = makeCode();
  sheet('invites').appendRow([code, name, true, iso(), Number(max) || 0, 0, '']);
  tell('邀请码：' + code + '\n把它发给朋友，注册时填写。');
  return code;
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
