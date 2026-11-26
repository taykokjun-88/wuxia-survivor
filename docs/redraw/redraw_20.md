# Redraw 20：全量美术与特效核查修复单（待确认后执行）

对应核查报告：`docs/art_full_audit.md`

## 批次 1（P0 — 角色错图与全黑特效）
1. **`assets/sprites/spear/block.png`** (`624×156`, 4 帧)
   - 参考 `assets/sprites/spear/idle.png` 与 `assets/portraits/spear_hero.jpg` 重绘：黑色竖扎发、红头带、深蓝战袍、左肩银甲护肩、红腰带、横枪格挡姿势（4 帧连贯）。
2. **`assets/enemies/blade_attack.png`** (`704×176`, 4 帧)
   - 参考 `assets/enemies/blade.png` 重绘：保持完全相同的红头巾深蓝布衣山贼刀客外观，4 帧单手弯刀挥砍动作。
3. **`assets/vfx/sw_zhongjian.png`** (`1536×256`, 6 帧，沉渊重剑)
   - 重绘高对比度厚重剑气弧光：外缘银白+亮青蓝剑芒，内层深墨青气浪，6 帧蓄势→横斩→余波消散，确保在暗色地图中清晰可见。
4. **`assets/vfx/fx_xiangmo.png`** (`1536×256`, 6 帧，定海铁杖)
   - 重绘高亮金铜色重杖砸地冲击波：金光碎石与环形气浪逐帧扩散至第 6 帧消散，避免第 4~6 帧变黑消失。

## 批次 2（P1 — 偏暗/过细/造型偏差特效）
5. **`assets/vfx/fx_blade_xuanxu.png`** (`1024×256`, 4 帧，幽微藏锋刀)
   - 增强银白月牙刀光厚度与微蓝气劲拖尾，4 帧完整渐变消散。
6. **`assets/vfx/hit_impact.png`** (`768×192`, 4 帧，通用命中火花)
   - 补全第 3~4 帧扩散星芒火花，提高打击清晰度。
7. **`assets/vfx/fx_blade_bleed_pop.png`** (`1024×256`, 4 帧，流血爆裂)
   - 在暗红血雾中加入亮朱红高光刃芒与飞溅粒子，提高暗地表对比度。
8. **`assets/vfx/fx_blade_wuhu.png`** (`1024×256`, 4 帧，五煞断岳刀)
   - 由三道兽爪痕改为刚猛烈焰橙金宽刃劈砍刀气，与 `boss_claw_slash.png` 区分。
