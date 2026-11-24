# B 线美术走查对照图与初审发现

> 由 `python3 tools/make_art_audit_sheets.py` 自动生成。`export_presets.cfg` 已排除 `docs/*`，本目录不占网页包体积。

## 一、本目录文件清单
| 文件 | 内容 |
|---|---|
| `sprite_sword.png` | 剑客全部 13 套局内动画逐帧 + 小镇 3 方向 |
| `sprite_blade.png` | 刀客全部 7 套局内动画逐帧 + 小镇 3 方向 |
| `sprite_spear.png` | 杨家将全部 9 套局内动画逐帧 + 小镇 3 方向 |
| `assets_xinfa_qinggong_shi.png` | 心法 10 + 轻功 6 + 无迹九变剑 9 式 名称 ↔ 图标对照表 |
| `assets_enemies_bosses.png` | 黑风寨 / 赤焰巅 / 海棠屿全部杂兵与 Boss 精灵 ↔ 立绘对照表 |
| `assets_gear_weapons.png` | 4 职业 40 件武器图标 + 20 个分流派装备部位图标对照表 |
| `assets_portraits_ui.png` | 4 职业立绘 / 选人全身像 / 登录封面 / 选关横幅 / 10 张胜负结算图（含 IP 文字走查） |

## 二、AI 初审已发现的明显问题（已预整理进 `docs/redraw/redraw_19.md` 草稿）

### 1. 杨家将（`sprite_spear.png`）— 差异最大，建议优先重画
- **局内 `walk.png`（6 帧）与其余 8 套动作不一致**：`walk` 穿着素色深蓝衣、没有银色肩甲、红发带不明显、长枪竖背在身后；而 `idle / dash / slash / thrust / block / ult / hurt / death` 都是带银色肩甲 + 飘动红发带 + 持枪前指的武将造型。
- **小镇三方向（`hero_down / side / up`）与局内不一致**：小镇版是蓬松棕发、无明显红发带，外观偏向另一角色。

### 2. 剑客（`sprite_sword.png`）
- **觉醒态 `true_idle.png`（4 帧）与 `true_walk` / `true_thrust` / `finish` 不一致**：`true_idle` 是紫白色刺猬发 + 紫气，而 `true_walk` / `true_thrust` / `finish` 是棕发 + 白金长袍。
- **小镇三方向**：发色偏棕，局内常规动作偏深蓝黑发（轻微差异，你决定要不要统一）。

### 3. 刀客（`sprite_blade.png`）
- 整体一致性最好（斗笠 + 暗红黑衣 + 弯刀在全部局内动作和小镇三方向高度统一）。仅 `ult` 第 1~4 帧红领巾略亮，可按你实机观感决定是否微调。

### 4. 心法与轻功图标（`assets_xinfa_qinggong_shi.png`）
以下 4 张图标仍残留改名前的旧意象，与现名不匹配：
- **`灵犀飞针录`（`lingxi`）**：图标是**向日葵**（原「葵花宝典」残留），应改为飞针 / 灵犀意象。
- **`寒月玄录`（`puti`）**：图标是**紫色鬼爪卷轴**（原「九阴真经」残留），应改为寒月 / 古籍意象。
- **`履雪无踪`（`tashue`）**：图标是**金色飞燕**，与「踏雪 / 履雪」名称不符（更像轻功「飞燕」）。
- **`乘风掠影`（`yufeng`）**：图标是**一苇渡江**（浪花上漂芦苇），与现名关联弱。
- 无迹九变剑 9 式图标整体风格统一，与各自机制对应清晰。

### 5. 三关怪物与 Boss（`assets_enemies_bosses.png`）
- 第二关赤焰巅、第三关海棠屿的 8 个 Boss 精灵与立绘高度一致（`redraw_16` 已生效）。
- **第一关黑风寨**的 4 个 Boss（独眼秤砣 / 算盘精 / 醉酒屠夫 / 黑风铁锅王）目前**无立绘**，可决定 V1.0 是否补齐或保持现状。

### 6. 武器与装备部位图标（`assets_gear_weapons.png`）— **已直接修复接入！**
- 排查发现 `assets/icons/fist_weapons/w1~w10.png`、`sword_weapons/w1~w10.png`（共 20 件武器图标，与武器名称 1 对 1 吻合）以及 `assets/icons/gear/{fist,sword,blade,spear}_{coat,pants,boots,charm}.png`（16 个分流派防具/配饰图标）都早已画好但未接进配置与代码。
- 现已全部接入 `data/game_data.json` 与 `scripts/hud.gd`，4 职业 40 件武器与分流派防具均已显示专属图标。

### 7. 立绘 / 封面 / 横幅 / 结算图（`assets_portraits_ui.png`）
- **B5 IP 文字核查通过**：封面、登录 Logo、三张选关横幅、赤焰巅标题字（`决战赤焰巅`）、10 张结算插画均**无任何原作 IP 文字残留**；海棠屿横幅已为垂丝海棠。
- 风格小注：`victory_spear.jpg` / `defeat_spear.jpg` 与前三职业的「悬崖背影 / 雨夜插地兵器」构图不同，可按喜好决定是否统一。
