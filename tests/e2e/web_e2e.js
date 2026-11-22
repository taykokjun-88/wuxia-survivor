// 网页版端到端测试：真实的 Godot 网页导出 + 模拟 Apps Script 后端（backend/test/mock_server.js）+ Chromium。
// 覆盖：注册 → 创建角色 → 排行榜 → 反馈 → 刷新自动登录 → 退出 → 错误 PIN → 再登录 → 打完一局并上传成绩 → 排行榜。
// 运行：tests/e2e/run.sh（会自己构建网页、启动两个本地服务器）。需要 playwright。
// 注意：软件渲染（SwiftShader）下帧率很低，帧率数字没有参考意义；这里只验证流程是否正确。
const { chromium } = require('playwright');
const fs = require('fs');
const OUT = process.env.E2E_OUT || '/tmp/e2e_shots';
fs.mkdirSync(OUT, { recursive: true });
const GAME = 'http://localhost:8077/index.html?api=http://localhost:8099/exec';
const state = async () => (await fetch('http://localhost:8099/admin/state')).json();
let fails = 0;
const ok = (c, m) => { if (!c) fails++; console.log((c ? '  ✓ ' : '  ✗ ') + m); };

(async () => {
  const browser = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 720 } });   // 同一上下文 = 同一浏览器存储
  const page = await ctx.newPage();
  const logs = [];
  page.on('console', (m) => logs.push(m.type() + ': ' + m.text()));
  page.on('pageerror', (e) => logs.push('PAGEERROR: ' + e.message));
  page.on('requestfailed', (r) => logs.push('REQFAILED: ' + r.url()));
  const shot = (n) => page.screenshot({ path: `${OUT}/${n}.png` });
  const boot = async (url) => { await page.goto(url); await page.waitForSelector('canvas'); await page.waitForTimeout(7500); };
  const pickChar = async () => { await shot('char_select'); await page.keyboard.press('Enter'); await page.waitForTimeout(2500); };   // 登录后先是选人界面：Enter = 进入上次的角色

  await boot(GAME);
  await shot('01_auth');
  // 没有游客入口：登录界面只能登录或注册（注册必须有邀请码）
  let st = await state(); ok(st.players === 3, '开始时服务器有 3 个预置玩家');
  await page.mouse.click(400, 305); await page.waitForTimeout(400);                // 切到「注册」
  // 错误的邀请码 → 被拒绝，不会创建账号
  await page.keyboard.type('Tester1'); await page.keyboard.press('Tab');
  await page.keyboard.type('2468'); await page.keyboard.press('Tab');
  await page.keyboard.type('WRONG1'); await page.keyboard.press('Enter');
  await page.waitForTimeout(3000); await shot('01b_wrong_code');
  st = await state(); ok(st.players === 3, '错误的邀请码不能注册（服务器玩家数仍为 ' + st.players + '）');
  // 改成正确的邀请码（不分大小写）
  await page.mouse.click(320, 452); await page.waitForTimeout(400);                  // 点进邀请码输入框（软件渲染很慢，操作要放慢）
  await page.keyboard.press('Control+A'); await page.waitForTimeout(400);
  await page.keyboard.type('friend'); await page.waitForTimeout(500);
  await page.keyboard.press('Enter');
  await page.waitForTimeout(3500);
  st = await state(); ok(st.players === 4, '正确的邀请码可以注册（服务器玩家数 ' + st.players + '）');
  await page.keyboard.press('Enter'); await page.waitForTimeout(2500);              // 创建角色（默认名「无名武者」）→ 进入竹溪村
  st = await state(); ok(st.chars === 1, '创建角色在服务器上（角色数 ' + st.chars + '）');
  await shot('02_town');
  // 本机后端才允许 ?npc=<id>：开局直接站到某个 NPC 面前（测试用，免得在软件渲染里计时走路）
  await boot(GAME + '&npc=innkeeper'); await pickChar(); await shot('02b_innkeeper');
  // 掌柜 → 排行榜
  await page.keyboard.press('e'); await page.waitForTimeout(800);
  await page.keyboard.press('1'); await page.waitForTimeout(3000); await shot('03_board');
  await page.keyboard.press('Escape'); await page.waitForTimeout(1500);
  // 掌柜 → 反馈
  await page.keyboard.press('e'); await page.waitForTimeout(800);
  await page.keyboard.press('2'); await page.waitForTimeout(1500);
  await page.keyboard.type('e2e feedback');
  await page.mouse.click(552, 540); await page.waitForTimeout(2500);
  st = await state(); ok(st.feedback.length === 2 && String(st.feedback[1][5]).includes('e2e feedback'), '反馈已写入表格');
  await page.waitForTimeout(1500);
  // 刷新 → 自动登录，回到村子
  await boot(GAME + '&npc=innkeeper'); await pickChar(); await shot('04_after_reload');
  // 掌柜 → 退出登录 → 错误 PIN → 正确 PIN
  await page.keyboard.press('e'); await page.waitForTimeout(800);
  await page.keyboard.press('4'); await page.waitForTimeout(2500);                  // 退出登录（3 是切换角色）
  await page.keyboard.type('Tester1'); await page.keyboard.press('Tab'); await page.keyboard.type('0000'); await page.keyboard.press('Enter');
  await page.waitForTimeout(2500); await shot('05_wrong_pin');
  await page.mouse.click(320, 425); await page.keyboard.press('Control+A'); await page.keyboard.type('2468'); await page.keyboard.press('Enter');
  await page.waitForTimeout(3000); await shot('06_relogin');
  await page.waitForTimeout(9000);                                                  // 村子在软件渲染下很慢，等浏览器把登录状态写进本地存储再刷新
  // 打完一局（加速 4 倍；本机后端才允许 speed 参数）
  await boot(GAME + '&speed=4&npc=clerk'); await pickChar();
  await page.keyboard.press('e'); await page.waitForTimeout(800);                  // 驿卒
  await page.keyboard.press('1'); await page.waitForTimeout(600);                  // 出发历练
  await page.keyboard.press('1'); await page.waitForTimeout(1500);                 // 黑风寨 → 开局界面
  await shot('06b_loadout');
  await page.keyboard.press('Enter'); await page.waitForTimeout(1000);              // 开始闯荡
  const t0 = Date.now();
  for (;;) {
    for (let i = 0; i < 6; i++) { await page.keyboard.press('1'); await page.waitForTimeout(1500); }   // 升级选卡选第一张
    st = await state();
    if (st.scores >= 4 || Date.now() - t0 > 420000) break;
  }
  await page.waitForTimeout(1500); await shot('07_end');
  ok(st.scores === 4, '成绩已上传（表格里共 ' + st.scores + ' 条）');
  await page.keyboard.press('b'); await page.waitForTimeout(3500); await shot('08_board_after_run');

  const errs = logs.filter((l) => /error|FAILED|PAGEERROR/i.test(l));
  ok(errs.length === 0, '浏览器控制台无错误' + (errs.length ? '：' + errs.slice(0, 3).join(' | ') : ''));
  console.log(fails ? `\n失败 ${fails} 项` : '\n全部通过');
  await browser.close();
  process.exit(fails ? 1 : 0);
})();
