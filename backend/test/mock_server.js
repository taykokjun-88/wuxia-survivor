// 本地模拟 Google Apps Script Web 应用，用来对"真实的游戏网页"做端到端测试。
// 运行真正的 backend/Code.gs（经 harness 的 Google 服务模拟），并模仿 Apps Script 的两个关键行为：
//   1. POST /exec 会 302 重定向到另一个地址取回结果（浏览器 fetch 会自动跟随）
//   2. 不支持 CORS 预检：OPTIONS 一律 405 且不带 CORS 头——游戏端若不小心触发预检，这里就会失败，和真 Google 一样
// 用法：node backend/test/mock_server.js [端口]
const http = require('http');
const { makeEnv } = require('./harness');

const port = Number(process.argv[2] || 8099);
const env = makeEnv({ autoConvert: true });          // 模拟"表格自作聪明"
env.ctx.__clock = Date.now() - 20 * 60000;
env.invite('FRIEND', '测试朋友', true, 0);

// 预置几个玩家和成绩（用可控时钟，满足提交间隔），之后切换回真实时钟
function seed(nick, pin, runs) {
  const r = env.call({ action: 'register', nick, pin, code: 'FRIEND' });
  for (const run of runs) {
    env.advance(30000);
    env.call(Object.assign({ action: 'submit', nick, token: r.token, school: 'fist', starter: 'chain_fist', qinggong: 'tashue', build: '[]', version: '0.3' }, run));
  }
}
seed('小明', '1234', [{ won: true, seconds: 745, level: 36, kills: 6100, bosses: 4 }]);
seed('阿杰', '1234', [{ won: false, seconds: 420, level: 19, kills: 1500, bosses: 1 }]);
seed('Lee', '1234', [{ won: true, seconds: 810, level: 33, kills: 5200, bosses: 4 }]);
require('vm').runInContext('now = function () { return Date.now(); }', env.ctx);

const results = new Map();
let seq = 0;
const CORS = { 'Access-Control-Allow-Origin': '*' };

function redirect(res, payload) {
  const id = String(++seq);
  results.set(id, payload);
  setTimeout(() => {
    res.writeHead(302, Object.assign({ Location: `http://localhost:${port}/r/${id}` }, CORS));
    res.end();
  }, 150);   // 模拟网络延迟
}

http.createServer((req, res) => {
  const url = new URL(req.url, `http://localhost:${port}`);
  if (req.method === 'OPTIONS') { res.writeHead(405); return res.end(); }   // 不支持预检
  if (url.pathname === '/exec' && req.method === 'GET') {
    const params = Object.fromEntries(url.searchParams);
    return redirect(res, JSON.stringify(env.get(params)));
  }
  if (url.pathname === '/exec' && req.method === 'POST') {
    const ct = String(req.headers['content-type'] || '');
    let body = '';
    req.on('data', (c) => (body += c));
    req.on('end', () => {
      if (!ct.startsWith('text/plain')) console.log('警告：POST 的 Content-Type 不是 text/plain：', ct);
      let out;
      try { out = JSON.stringify(JSON.parse(env.ctx.doPost({ postData: { contents: body } }).text)); }
      catch (e) { out = JSON.stringify({ ok: false, err: 'server' }); }
      redirect(res, out);
    });
    return;
  }
  const m = url.pathname.match(/^\/r\/(\d+)$/);
  if (m && results.has(m[1]) && req.method === 'GET') {
    res.writeHead(200, Object.assign({ 'Content-Type': 'application/json; charset=utf-8' }, CORS));
    return res.end(results.get(m[1]));
  }
  if (url.pathname === '/admin/state') {     // 仅测试用：查看表格内容
    res.writeHead(200, Object.assign({ 'Content-Type': 'application/json; charset=utf-8' }, CORS));
    return res.end(JSON.stringify({ players: env.sheetRows('players').length - 1, feedback: env.sheetRows('feedback'), scores: env.sheetRows('scores').length - 1, chars: env.sheetRows('chars').length - 1, logs: env.sheetRows('logs').length - 1 }));
  }
  res.writeHead(404); res.end();
}).listen(port, () => console.log(`mock apps script ready on :${port}`));
