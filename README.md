# 群侠千招

> 英文参考名：Heroes of Thousand Arts

Godot 4.4 · 武侠题材 Survivor-like · 独立开发 · 网页版（朋友间非商业试玩）

## 🎮 开始游戏

**👉 [点这里直接玩（网页版）](https://taykokjun-88.github.io/wuxia-survivor/)**

<https://taykokjun-88.github.io/wuxia-survivor/>

电脑浏览器打开即可，不用安装；需要**邀请码**注册账号（向作者索取）。每个账号最多 **5 个角色**，三个流派：**武者 / 剑侠 / 刀客**。

> 招式、角色均为**原创命名**（「类」某某武学），不使用任何受版权保护的作品名称。美术由 AI 绘图工具制作，音乐音效来自免费授权素材（署名见 [`docs/credits.md`](docs/credits.md)）。

## 玩法概览

- **流派**：
  - **武者**（拳掌）：内力深厚，靠**盈境**（内力高）增伤；**蓄劲**——每次出手攒劲，满 100 打出「寸劲震爆」；真气爆发 = 10 秒「**拳掌无敌**」（无敌、每下出手触发寸劲、30% 真伤，期间内力不恢复）。
  - **剑侠**：吃速度 / 攻速 / 敏捷；起手可选**无迹九变剑**——整局只有这一招，靠「九变」强化：9 层破兵微步、18 层万法皆破、27 层真·无迹九变剑。
  - **刀客**：吃气血；**刀魂**越多刀法越强，4 个刀法出手耗血，气血降到 20% 触发「**真·霸刀破岳**」（10 秒免耗血、回复翻倍）。
- **一局**：黑风寨 10 分钟（3 个小 Boss + 大 Boss「黑风寨主」）；赤焰巅 13 分钟（局外 Lv5 可进，建议装备分 20）。升级时三选一（新招式 / 新心法 / 强化已有项目），**每次强化有品质**（白 / 蓝 / 紫 / 金，50% / 25% / 18% / 7%）。**另觅机缘**：局外每满 5 级，局内多 3 次重抽升级卡。
- **局外成长（按角色）**：修为 → 局外等级（满级 50）；属性点（每级 3 点）；**天赋树**（刚 / 柔 / 灵三个框，每框 33 点，每级 2 点，三系点满 99 点后出现各职业专属的第 100 点「极」）；**装备**（武器 / 上衣 / 下半身 / 鞋子 / 配饰，4 档稀有度，通关掉落）；**铁匠**用银两强化装备。
- **小镇「竹溪村」**：WASD 走动，靠近 NPC 按 E——驿卒（出发 / 选地图）、武馆师父（属性与天赋）、铁匠（强化 / 整备装备）、掌柜（排行榜 / 反馈 / 切换角色 / 退出登录）、茶馆老包（图鉴）、药师（暂未开张）。
- **排行榜**：总分 / 最快通关 / 最高等级，**按地图、按角色**；可只看本群。

| 操作 | 按键 |
|---|---|
| 移动（自动攻击） | WASD / 方向键 |
| 轻功（冲刺 / 瞬移，耗内力） | 空格 / Shift |
| 真气爆发 | E |
| 升级 / 秘籍选择 | 1 / 2 / 3 或鼠标点击；**R = 另觅机缘** |
| 收起 / 展开 HUD | Tab |
| 暂停 | Esc |

## 在线玩（网页版）

目标平台是**浏览器**，发给朋友直接点链接玩，不需要安装。

- 构建：`tools/build_web.sh`（需要 Godot 4.4.1 + Web 导出模板），产物在 `export/web/`。
- 本地预览：`cd export/web && python3 -m http.server 8000`，打开 <http://localhost:8000>。
- 发布：仓库里带了 `.github/workflows/pages.yml`，在仓库 Settings → Pages 里把 Source 选成 "GitHub Actions"，推送后自动构建并发布到 GitHub Pages。
- 体积：`index.wasm` 约 44MB（服务器 gzip 后约 10MB）+ 游戏数据包，首次加载需要几秒。
- 单线程导出（`variant/thread_support=false`），不需要 COOP/COEP 响应头，普通静态托管就能跑。
- 网页音频要用「流式」播放（`audio/general/default_playback_type.web=0`），否则 OGG / 采样会没声音。

## 账号、角色与排行榜（Google 表格 + Apps Script）

**没有游客模式**：必须有账号才能玩。注册需要**邀请码**（昵称 + PIN + 邀请码），后台可以设置多个邀请码，每个码就是一个「群」（可限人数、昵称名单、到期日期）。**登录后先进选人界面**：每个账号最多 5 个角色，可创建（选流派 + 起名字）/ 删除；每个角色有自己的局外等级、天赋、装备、银两和通关进度。可以在游戏里提反馈。`data/config.json` 里的 `api_url` 留空时：桌面版（本地调试）单机玩（单机存档同样支持 5 个角色）；**网页版会提示「在线服务还没有配置好」**。

- 后端是一张 Google 表格 + 一段 Apps Script（`backend/Code.gs`）：PIN 加盐哈希、令牌、失败锁定、邀请码、日志、反馈；表：玩家 / 角色 / 排行 / 日志 / 反馈 / 邀请。成绩、掉落、银两、强化、天赋校验都在服务器端（客户端不能伪造）。
- **部署步骤见 [`backend/README.md`](backend/README.md)**；部署后把网址填进 `data/config.json`。**每次改了 `backend/Code.gs` 都要重新部署**（部署 → 管理部署 → 新版本），旧账号的进度会自动迁移成第一个角色。
- 排行榜得分公式：击杀数 + 等级×100 + 击败 Boss 数×1000；通关另加 5000 + (900 − 用时秒)×10（最少 0）。

## 运行（桌面编辑器）

1. 安装 [Godot 4.4+](https://godotengine.org/download)（标准版即可）。
2. 用 Godot 打开本目录的 `project.godot`，按 F5。

## 目录结构

```
data/game_data.json        所有数值：技能 / 心法 / 轻功 / 敌人 / 地图 / 天赋 / 装备 / 流派（只改表，不动代码）
scripts/data.gd            Autoload：读表、注册输入、加载字体
scripts/save.gd            Autoload：存档（多角色：流派 / 局外成长 / 天赋 / 装备）
scripts/net.gd             Autoload：账号 / 角色 / 排行榜 / 反馈（调用后端）
scripts/sfx.gd, bgm.gd     Autoload：音效（含变体轮换）/ 背景音乐
scripts/world.gd           游戏世界：模拟 + 绘制（step(dt) 与渲染无关，可无头测试）
scripts/skills/            技能基类 + 三个流派的招式行为与专属强化
scripts/boss_ai.gd         Boss 技能与阶段；enemy.gd / projectile.gd 敌人与弹体数据
scripts/talents.gd, talent_tree.gd   天赋规则 + 三个框的天赋树界面
scripts/gear.gd, meta.gd   装备 / 局外成长公式（后端有同一份，测试用共用向量校验）
scripts/hud.gd, main.gd    HUD / 各种界面；状态机 + 输入 + 相机
scripts/town.gd            小镇
backend/                   Google Apps Script 后端 + Node 测试 / 模拟服务器
tools/                     美术处理 / 字体裁剪 / 音效生成 / 测试脚本
tests/                     无头模拟测试、截图脚本、网页端到端测试、测试 bot
docs/                      设计稿、美术需求、开发状态（status.md）
```

完整的开发状态与设计演变见 [`docs/status.md`](docs/status.md)，流派设计见 `docs/design_*.md`。

## 测试

```bash
# 一键：后端（Node）+ 游戏（Godot 无头）
tools/run_all_tests.sh

# 网页端到端（真实网页 + 模拟后端 + Chromium，较慢，需要 playwright）
tests/e2e/run.sh

# 只跑一部分：TEST_ONLY=upgrade | cards | blade | plan6 | chars | survive | boss | dugu | matrix | full ...
TEST_ONLY=plan6 godot --headless --path . res://tests/sim_test.tscn

# 平衡报告：多种子存活（SCHOOL=fist|sword|blade）/ Boss 战耗时（MAP=guangming）
SCHOOL=blade TEST_ONLY=survive godot --headless --path . res://tests/sim_test.tscn
SCHOOL=sword MAP=guangming TEST_ONLY=boss godot --headless --path . res://tests/sim_test.tscn

# 真实渲染截图（需要显示或 xvfb）
SHOT_DIR=/tmp/shots xvfb-run -a godot --path . --rendering-driver opengl3 res://tests/shot.tscn
```

> 测试 bot 只会基本的走位和随机选择，数值只能当粗略参考，真实手感需要人来玩。

## 字体

浏览器里没有系统字体可回退，所以**自带中文字体**：霞鹜文楷（LXGW WenKai，SIL OFL 协议，见 `assets/fonts/OFL.txt`），
已裁剪成常用字（约 1.7MB / 字重）。`main.ttf` 是正文，`main_bold.ttf` 用于「极」等需要突出的字。
新增文案用到了字库里没有的生僻字时，重新运行 `python3 tools/subset_font.py`（见脚本注释）。

## 角色 sprite 流水线

AI 出的洋红底条带 → `tools/process_sprites.py` → 游戏用 sprite（透明底、统一缩放、共用 28 色调色板、脚底对齐）。
工具会自动处理 AI 出图的常见毛病：紫色动态模糊拖影、帧交界的细竖线、飘在外面的深色碎块（靠近角色的浅色特效如拳风、气劲弧、速度线会保留）。
游戏启动时读取 `assets/sprites/player/anim.json`，**缺哪条动画就回退到待机**，所以交一条处理一条，游戏代码不用改。

```bash
pip install pillow numpy scipy
S=assets/sprites/source
python3 tools/process_sprites.py palette $S/*.jpg --colors 32            # 用全部素材建共用调色板（加新素材后要重建并重跑全部动画）
python3 tools/process_sprites.py strip $S/idle.jpg  idle  --frames 4 --use 1,3,4,3 --fps 4
python3 tools/process_sprites.py strip $S/walk.jpg  walk  --frames 6 --use 5,6 --ref-frame 5 --fps 6
python3 tools/process_sprites.py strip $S/punch.jpg punch --frames 4 --fps 16 --once
python3 tools/process_sprites.py strip $S/palm.jpg  palm  --frames 4 --use 1,3,4 --fps 12 --once --scale-mode image
python3 tools/process_sprites.py strip $S/dash.jpg  dash  --frames 3 --fps 14 --once --scale-mode image --align keep
python3 tools/process_sprites.py strip $S/ult.jpg   ult   --frames 4 --fps 8  --once --scale-mode image
python3 tools/process_sprites.py strip $S/death.jpg death --frames 4 --fps 6  --once --scale-mode image
python3 tools/process_sprites.py strip $S/hurt.jpg  hurt  --frames 2 --fps 10 --once --scale-mode image
```

- `--use 1,3,4,3`：只用并重排其中几帧（跳过出坏的帧）；`--ref-frame`：缩放参考帧，应选**站姿**的那一帧；
  `--scale-mode image`：没有站姿的动画按图高比例缩放；`--align keep`：保留帧间高低（冲刺腾空）。
- 主角约 56 像素高，格子 96×96（出拳的手臂会伸出 64 的格子）。

**当前动画状态**：idle ✅　punch ✅　palm ✅（跳过了第 2 帧）　dash ✅　hurt ✅　death ✅　ult ✅　walk ⚠️（源图前 4 帧腿被拖影盖住，只用了第 5、6 帧，等重出）

动画名：`idle walk dash hurt death punch palm ult`。游戏自动选择：静止 idle、移动 walk、冲刺 dash、受击 hurt、
阵亡 death；连山贯日拳 / 裂脉震拳 / 沉岳铁拳出招播放 punch，其余武者技能播放 palm，真气爆发播放 ult。

敌人后续按同一比例出图（山贼/刀客约 36、官兵约 44、精英约 56、Boss 约 110）。

## 美术与音频素材

- 立绘 / 封面 / 结算图 / 小镇 / 地图 / 敌人 / 图标 / 特效：AI 绘图工具制作后用 `tools/process_*.py` 处理（去洋红底、切帧、统一缩放）。绘图需求文档在 `docs/redraw/`（按批次的重画计划书）；没有素材的部分自动用程序画的占位图。
- **天赋树**每个框的背景：`assets/ui/talent_bg/<流派>_<系>.jpg`（9 张）；**选人界面**角色全身像：`assets/char_select/<流派>.png`。
- **音效**：真实采样（CC0 / CC-BY）经 `tools/build_sfx_real.py` 裁切 / 变调 / 叠加 / 统一响度；命中 / 受击等有 3 个变体随机轮换。**背景音乐**按场景切换（登录 / 小镇 / 黑风寨 / 小 Boss / 大 Boss），暂停菜单可分别开关音乐和音效。来源与署名见 [`docs/credits.md`](docs/credits.md)。

## 路线图

| 里程碑 | 状态 |
|---|---|
| 三个流派（武者 / 剑侠 / 刀客）、10 个心法、6 个轻功、升级品质与强化、另觅机缘 | ✅ |
| 账号 / 多角色 / 邀请码 / 排行榜（按地图、按角色）/ 反馈 | ✅ |
| 局外成长：等级 / 属性点 / 天赋树（三个框 + 极）/ 装备 / 铁匠强化 | ✅ |
| 小镇、选人界面、网页导出、中文字体、音乐与真实音效 | ✅ |
| 第 1、2 关：黑风寨、赤焰巅 | ✅ |
| 赤焰巅配乐（等作者提供曲子） | 待做 |
| 第 3、4、5 关（占位「？？？」）、第 6 关：绝顶试剑 | 待做 |
| 长兵流派、药师 | 待做 |
| 真实游玩后的平衡调整（三个流派 / Boss 时长 / 「极」强度） | 持续 |
