# 武侠幸存者（原型）

Godot 4.4 · 武侠题材 Survivor-like · 独立开发 · PC 优先

> 原型阶段：全部使用代码绘制的占位图形，用来验证玩法。招式、角色均为**原创命名**（"类"某某武学），不使用任何受版权保护的作品名称。

## 在线玩（网页版）

目标平台是**浏览器**，发给朋友直接点链接玩，不需要安装。

- 构建：`tools/build_web.sh`（需要 Godot 4.4.1 + Web 导出模板），产物在 `export/web/`。
- 本地预览：`cd export/web && python3 -m http.server 8000`，打开 <http://localhost:8000>。
- 发布：任意静态托管都行（GitHub Pages / itch.io / Netlify）。仓库里带了 `.github/workflows/pages.yml`，
  在仓库 Settings → Pages 里把 Source 选成 "GitHub Actions"，推送到 `main` 就会自动构建并发布。
- 体积：`index.wasm` 约 44MB（服务器 gzip 后约 10MB）+ 游戏数据包约 3MB，首次加载需要几秒。
- **存档**保存在每个人自己浏览器的 IndexedDB 里：不用服务器、朋友之间互不影响；
  清除浏览器数据或换浏览器/设备会丢存档。
- 使用单线程导出（`variant/thread_support=false`），所以不需要 COOP/COEP 响应头，普通静态托管就能跑。

## 账号与排行榜（Google 表格 + Apps Script）

**没有游客模式**：必须有账号才能玩。注册需要你发的**邀请码**（昵称 + PIN + 邀请码），后台可以设置多个邀请码，每个码就是一个"群"（可限人数、昵称名单、到期日期），排行榜可以只看本群。成绩上**排行榜**（总分 / 最快通关 / 最高等级），也能在游戏里提反馈；
角色流派存在云端，换设备登录也在。`data/config.json` 里的 `api_url` 留空时：桌面版（本地调试）单机玩；**网页版会提示"在线服务还没有配置好"**，不能进入游戏。

- 后端是一张 Google 表格 + 一段 Apps Script（`backend/Code.gs`），模式参照「知识岛」：PIN 加盐哈希、令牌、失败锁定、邀请码、日志、反馈。
- **部署步骤（约 10 分钟）见 [`backend/README.md`](backend/README.md)**，部署后把网址填进 `data/config.json`。
- 游戏流程：打开链接 → 登录 / 注册（注册要邀请码）→ 创建角色（首次）→ 开局 → 打完自动上传成绩，结算界面显示名次，按 B 看排行榜。
- 排行榜的得分公式：击杀数 + 等级×100 + 击败 Boss 数×1000；通关另加 5000 + (900 − 用时秒)×10（最少 0）。

## 运行（桌面编辑器）

1. 安装 [Godot 4.4+](https://godotengine.org/download)（标准版即可）。
2. 用 Godot 打开本目录的 `project.godot`，按 F5。

| 操作 | 按键 |
|---|---|
| 移动（自动攻击） | WASD / 方向键 |
| 轻功（冲刺 / 瞬移，耗内力） | 空格 / Shift |
| 真气爆发（耗满内力的范围大招） | E |
| 升级 / 秘籍选择 | 1 / 2 / 3 或鼠标点击 |
| 暂停 | Esc |

## 一局的流程（约 12 分钟）

0. **创建角色**（只在第一次，或点「重新创建角色」时出现）：选择武学流派（目前只有拳掌），写入存档 `user://save.json`。
1. **开局选择**：起手招式 3 选 1（连环拳 / 点穴指 / 流云掌）→ 轻功 6 选 1。
2. **升级三选一**：新招式 / 新心法 / 已有项目升级。槽位满了就不再刷新项。
3. **精英**每 80 秒出现，击败回复少量气血。
4. **小 Boss ×3**（3:00 / 6:30 / 10:00）：第一个掉**秘籍** → 三选一**专属强化**；之后每个把该强化**升一级**（最高 Lv3）。
5. **大 Boss「海岛剑尊」**（12:00）：击败即通关。（计划：掉落本流派装备，见设计稿。）

## 构筑系统（拳掌）

| 槽位 | 数量 | 说明 |
|---|---|---|
| 攻击技能 | 4 | 拳掌 9 选 4；每个技能最高 **12 层**（11 次升级），见下方「升级方向」 |
| 心法 | 2 | 10 选 2，各 3 级；按**标签**给不同技能加成，并带独特被动 |
| 轻功 | 1 | 开局 6 选 1：冲刺次数 / 瞬移 / 闪避 / 隐匿 / 加速等 |
| 专属强化 | 1 | 只能强化 1 个技能（"加一个机制"），小 Boss 可升到 Lv3 |

- **升级方向 × 档位**：技能升级不是固定的 Lv 表，每张升级卡是「一个方向 × 一个档位」。
  方向：加强伤害 / 减少冷却 / 增加范围 / 增加目标 / 增加增益（出招回内力）/ 增加减益（命中减速）/
  增加时长 / 增加治疗（命中回血）/ 增加打击次数（几率连续出招两次）/ 增加暴击。
  档位：**小成 / 中成 / 大成 / 灵机一动**，出现概率 50% / 30% / 15% / 5%
  （例：加强伤害 = +10% / +20% / +30% / +50%）。每个技能每次出 2 张不同方向的卡。
  所有数值在 `data/game_data.json` 的 `directions` / `tiers`。
- **角色升级成长**：每升 1 级，**基础伤害 +2%**（所有技能）、**气血上限 +4**、**防御 +0.2**
  （防御是固定减伤，但至少承受 25% 伤害）。数值在 `data/game_data.json` 的 `level_growth`。
- **满层标记**：技能图标右下角显示层数（1–11 是数字），升到 12 层时数字直接换成金色楷体「极」。
- **经验宝石**：落地 4 秒后自动飞向玩家，升级节奏只取决于击杀，不取决于敢不敢冲进怪堆里捡。
- **升级节奏**：打完一局（击败大 Boss）角色约 **Lv30–35**（`tuning.exp_mult` 控制）。
- **自动瞄准**：Boss 和精英在射程内时优先瞄准。
- **标签系统**：技能带标签（贯穿 近战 范围 控制 追踪 蓄力 多向 防御 连击 远程），心法按标签加成，新增技能自动生效。
- **内力**：轻功和大招耗内力；内力 ≥ 50% 时全部伤害 +25%。
- 天赋树（刚 / 柔 / 灵三条加点方向，并存、自由加点）属于局外成长，**尚未实现**。

完整设计见 [`docs/design_fist.md`](docs/design_fist.md)。

## 目录结构

```
data/game_data.json        所有数值：技能 / 心法 / 轻功 / 敌人 / 节奏（只改表，不动代码）
scripts/data.gd            Autoload：读表、注册输入、加载字体
scripts/save.gd            Autoload：存档（创建角色的流派；后续放天赋点、装备）
scripts/world.gd           游戏世界：模拟 + 绘制（step(dt) 与渲染无关，可无头测试）
scripts/skills/            技能基类 + 拳掌 9 个技能的行为与专属强化
scripts/enemy.gd           敌人数据（RefCounted，不用 Node，便于同屏上千）
scripts/projectile.gd      弹体数据
scripts/hud.gd             HUD、开局选择、升级/秘籍选择、结算
scripts/main.gd            状态机 + 输入 + 相机
tests/                     无头模拟测试、截图脚本、测试 bot
docs/                      设计稿
```

## 测试

```bash
# 一键：后端（Node）+ 游戏（Godot 无头）
tools/run_all_tests.sh

# 网页端到端（真实网页 + 模拟后端 + Chromium，较慢，需要 playwright）
tests/e2e/run.sh

# 完整无渲染测试：秘籍流程 / 9 个技能（含强化）伤害报告 / 10 个心法 / 6 个轻功 / 两局完整对局
godot --headless --path . res://tests/sim_test.tscn

# 只跑一部分（matrix = 技能伤害报告，full = 完整对局）
TEST_ONLY=matrix godot --headless --path . res://tests/sim_test.tscn

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
阵亡 death；连环拳 / 撼地拳 / 金刚拳出招播放 punch，其余拳掌技能播放 palm，真气爆发播放 ult。

敌人后续按同一比例出图（山贼/刀客约 36、官兵约 44、精英约 56、Boss 约 110）。

## 美术替换计划（nano banana → 像素）

目前所有图形都在 `world.gd` 的 `_draw_*` 里，是占位。接入 sprite 时：
- 角色/敌人：像素风，约 48×48，透明底 PNG，放入 `assets/sprites/`；
  3/4 侧视角，向左时水平翻转；纹理过滤已全局设为 Nearest。
- 为保持同屏性能，敌人将改用 `MultiMeshInstance2D` 批量绘制，不要给每个敌人建 `Sprite2D` 节点。
- AI 出图不是像素级精确，需要后处理（去洋红底、切帧、按脚底对齐、最近邻缩放、调色板量化），
  计划放在 `tools/`。

## 路线图

| 里程碑 | 状态 |
|---|---|
| M1–M4：槽位 / 标签 / 9 技能 / 10 心法 / 6 轻功 / 专属强化 / 小 Boss / 精英 | ✅ |
| 存档 + 创建角色（流派） | ✅ |
| 账号 / 排行榜 / 反馈 / 云端流派（Google 表格 + Apps Script） | ✅（待你部署后端） |
| 创建角色界面：立绘 + 像素形象预览 | ✅ |
| M5：局外等级 / 修为 / 五种属性点 / 天赋树（设计见 [`docs/design_meta.md`](docs/design_meta.md)，待你确认） | 待做 |
| 内力「气海」系统（三境 / 催动 / 入定 / 破绽） | 方案待确认 |
| M6：大 Boss 掉落装备（5 部位、稀有度、基础属性 + 特殊词条）+ 背包 | 待做 |
| 网页导出 + 中文字体 + 主角 sprite 接入（待机；其余动画待出图） | ✅ |
| 敌人 sprite + 渲染优化（插值、MultiMesh、对象池） | 待做 |
| 剑 / 刀 / 长兵流派 | 待做 |
