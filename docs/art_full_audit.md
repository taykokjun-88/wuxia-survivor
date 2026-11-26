# 全量美术与攻击特效核查报告（立绘 / Sprite / 敌人 / 110 个攻击 VFX）

本报告覆盖仓库内全部美术资源：
- **立绘 / 选人图 / 胜负与标题界面**：19 张（`assets/portraits/`、`assets/char_select/`、`assets/ui/screens/`）
- **4 流派主角局内 + 小镇 Sprite**：49 张条图（`assets/sprites/{player,sword,blade,spear}/`、`assets/town/hero*/`）
- **敌人与 Boss Sprite**：74 张条图（`assets/enemies/`）
- **全部攻击与受击特效 VFX**：110 张条图（`assets/vfx/*.png`）

> 自动化基础校验：全部 110 张 VFX 均为合法 `RGBA` 透明图，且 100% 在 `scripts/` 或 `data/game_data.json` 中被引用，无孤立废弃文件。

---

## 一、P0 严重异常（局内肉眼可见错位 / 几乎不可见，建议优先重绘）

| 编号 | 资源路径 | 尺寸 / 帧数 | 问题描述 |
|---|---|---|---|
| **A1** | `assets/sprites/spear/block.png` | `624×156` (4帧) | **角色外观完全不符**：缺红头带、缺左肩银甲、改穿亮蓝长袍，脸型与头身比均与 `spear/idle.png`、`spear/walk.png` 和立绘不一致。 |
| **A2** | `assets/enemies/blade_attack.png` | `704×176` (4帧) | **与待机图不是同一个人**：`assets/enemies/blade.png` 是红头巾山贼刀客，而 `blade_attack.png` 是棕发紫白袍刺客（第 1~2 帧无红头巾，第 4 帧变双刀）。 |
| **V1** | `assets/vfx/sw_zhongjian.png` | `1536×256` (6帧) | **沉渊重剑特效几乎全黑不可见**：可见像素平均亮度仅 **`21.5/255`**，在暗色地面上几乎完全看不出剑气。建议重绘为亮银/墨青描金的重剑破风弧光。 |
| **V2** | `assets/vfx/fx_xiangmo.png` | `1536×256` (6帧) | **定海铁杖特效过暗、后半段消失**：可见像素平均亮度仅 **`34.6/255`**，第 4~6 帧几乎完全黑透明。建议重绘为高亮金铜震地冲击波。 |

---

## 二、P1 明显瑕疵（建议重绘或提亮增强）

| 编号 | 资源路径 | 尺寸 / 帧数 | 问题描述 |
|---|---|---|---|
| **V3** | `assets/vfx/fx_blade_xuanxu.png` | `1024×256` (4帧) | **幽微藏锋刀过细弱**：最大单帧覆盖率仅 **`7.39%`**、平均亮度 `57.9`，第 4 帧几乎空白，辨识度不足。 |
| **V4** | `assets/vfx/hit_impact.png` | `768×192` (4帧) | **通用受击火花过小且缺后半帧**：最大覆盖率 **`6.63%`**，第 3~4 帧完全空白，打击反馈偏弱。 |
| **V5** | `assets/vfx/fx_blade_bleed_pop.png` | `1024×256` (4帧) | **流血爆裂偏暗**：平均亮度 **`31.5/255`**，暗红色在深色草地/石地上对比度偏低，建议加入亮朱红高光边缘。 |
| **V6** | `assets/vfx/fx_blade_wuhu.png` | `1024×256` (4帧) | **五煞断岳刀造型偏兽爪**：当前为三道橙红兽爪抓痕（与 `boss_claw_slash.png` 高度雷同），与“重刀劈砍”意象不完全贴合。 |

---

## 三、P2 风格与细节微调（非破坏性，按需统一）

| 编号 | 资源路径 | 问题描述 |
|---|---|---|
| **P1** | `assets/char_select/sword.png` vs `assets/portraits/sword_hero.jpg` | 选人图是束冠纯白袍（无葫芦、无青领）；立绘是青丝带披发、青白内领、腰挂酒葫芦。局内/小镇 Sprite 偏立绘配色。 |
| **P2** | `assets/ui/screens/victory_blade.jpg` | 刀客斗笠背在身后且手持直剑，与立绘/Sprite 的「头戴斗笠 + 弯刀」略有出入。 |
| **P3** | `assets/ui/screens/victory_spear.jpg` & `defeat_spear.jpg` | 杨家将胜负界面为正面全身角色构图，而武者/剑侠/刀客为水墨背影（胜）与兵器特写（败），构图体系不完全统一。 |
| **P4** | `assets/sprites/spear/{idle,dash,hurt,death,slash,thrust,ult}.png` | 除 `walk.png` 与小镇 `hero_spear/*` 外，其余战斗动作暂未画背上的白蜡杆长棍（次要细节）。 |

---

## 四、已核查通过项

- **武者（拳掌）**：`redraw_18` 修复后，8 套局内动作 + 3 套小镇行走 + 立绘 + 选人图配色与发型全部一致。
- **剑侠**：`redraw_19` 统一觉醒披发后，普通与觉醒动作 + 小镇行走一致性良好。
- **刀客**：7 套局内动作 + 3 套小镇行走 + 立绘 + 选人图一致性极高。
- **敌人与 Boss**：除 `blade_attack.png`（A2）外，其余 73 张敌人与三大关卡 Boss/精英动作均前后一致、无错帧。
- **攻击特效**：其余 104 张 VFX 亮度、帧序、透明通道与对应招式意象匹配良好。
