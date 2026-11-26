# Redraw 20：全量美术与特效修复单

对应核查报告：`docs/art_full_audit.md`

## 已直接修复（5 张 VFX，Pillow 亮度/光晕与缺失帧修复）
- [x] `assets/vfx/sw_zhongjian.png`（沉渊重剑，1536×256，6 帧）：由几乎全黑不可见提亮为亮银青重剑气浪，6 帧全清晰可见。
- [x] `assets/vfx/fx_xiangmo.png`（定海铁杖，1536×256，6 帧）：由过暗/后半段消失提亮为金铜冲击波，6 帧连贯扩散。
- [x] `assets/vfx/fx_blade_bleed_pop.png`（流血爆裂，1024×256，4 帧）：提亮暗红血雾并增加朱红高光核心。
- [x] `assets/vfx/fx_blade_xuanxu.png`（幽微藏锋刀，1024×256，4 帧）：增厚银白月牙刀光并补全第 4 帧消散余波。
- [x] `assets/vfx/hit_impact.png`（通用受击火花，768×192，4 帧）：提亮第 1~2 帧火花并补全第 3~4 帧扩散消散星环。

---

## 待 Gemini 图像生成重绘（因 `gemini-3.1-flash-image` 配额暂满，可直接粘给 Gemini Web 或等配额恢复后自动执行）

### P0（2 张角色 Sprite 错图）
1. **`assets/sprites/spear/block.png`**（`624×156`，4 帧）
   - 参考图：`assets/sprites/spear/idle.png` + `assets/portraits/spear_hero.jpg`
   - Prompt：
     > 2D pixel-art wuxia game sprite sheet on a solid bright magenta (#FF00FF) background, 4 equally spaced horizontal frames in 1 row showing a defensive spear blocking animation facing right. Character must EXACTLY match the reference sprite and portrait: young Song dynasty Yang family spear general, spiky black topknot hair, red headband with trailing ribbons, dark navy-blue martial tunic, silver metal left shoulder pauldron, red waist sash, dark pants, holding a long red-tasseled silver spear diagonally across the chest to block attacks. Crisp pixel art matching exact proportions and scale of idle.png, no ground shadow, no text.

2. **`assets/enemies/blade_attack.png`**（`704×176`，4 帧）
   - 参考图：`assets/enemies/blade.png`
   - Prompt：
     > 2D pixel-art wuxia game enemy sprite sheet on a solid bright magenta (#FF00FF) background, 4 equally spaced horizontal frames in 1 row showing a melee saber slash attack facing right. Character must EXACTLY match the reference enemy sprite: bandit saberman wearing a red headband tied at the back, dark navy-blue martial tunic, red belt, dark pants, wielding ONE curved Chinese saber (dao). Frame 1 windup, frame 2 overhead slash, frame 3 wide cut follow-through, frame 4 recovery. Crisp pixel art matching exact proportions and palette of blade.png, no ground shadow, no text.

### P1（1 张刀法特效造型替换）
3. **`assets/vfx/fx_blade_wuhu.png`**（`1024×256`，4 帧，五煞断岳刀）
   - Prompt：
     > 2D wuxia action RPG attack VFX sprite sheet on pure solid black (#000000) background, 4 equally spaced horizontal frames in 1 row showing a fierce heavy saber (dao) cleaving crescent slash wave in glowing fiery orange-gold and white-hot edge (NO beast claw marks). Frame 1 windup spark, frame 2-3 wide bold fiery orange-gold curved blade slash arc, frame 4 dissipating embers. No text, no grid lines.

### P2（立绘与胜负界面风格统一，4 张）
4. **`assets/char_select/sword.png`**（`512×512` 透明底）：按 `assets/portraits/sword_hero.jpg` 统一为青丝带披发、白袍青内领、腰间棕酒葫芦。
5. **`assets/ui/screens/victory_blade.jpg`**：按 `assets/portraits/blade_hero.jpg` 统一为头戴斗笠、手持弯刀的崖边水墨背影构图（与 `victory_fist.jpg` / `victory_sword.jpg` 保持同系列构图）。
6. **`assets/ui/screens/victory_spear.jpg`**：统一为杨家将崖边持红缨枪背影望云海的水墨风构图（与另外三流派胜利图统一）。
7. **`assets/ui/screens/defeat_spear.jpg`**：统一为雨夜断崖斜插红缨枪与白蜡杆的水墨兵器特写构图（与另外三流派败北图统一）。
