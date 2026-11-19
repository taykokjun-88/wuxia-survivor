# 美术提示词：招式特效 + 天赋经脉图

> 给 nano banana 用。生成后按文末「流程」处理、放进仓库，游戏会自动换上；没有素材的部分继续用程序画的占位图，所以可以一批一批地补。

---

## 一、招式特效（20 个）

### 通用风格块（每条提示词开头都带上）

```
Pixel art VFX sprite sheet for a 2D Chinese wuxia action game, top-down/side-neutral view.
Horizontal strip, ONE row, N equal-size square frames side by side, the effect centered in every frame.
PURE BLACK background (#000000) everywhere, no ground, no characters, no text, no frame borders, no shadows.
Glowing qi-energy look with HIGHLY SATURATED colors (the game background is light beige parchment, so avoid washed-out white;
use strong jade green / gold / vermilion / cyan / ink-blue), crisp pixel edges, limited palette (about 12 colors), bright core with darker saturated edges.
Consistent size and style across frames; the effect appears, peaks, then dissipates over the frames.
```

> 黑底是关键：游戏把「越亮越不透明」当作透明度，黑色会变成全透明。所以**效果里不要有深色的墨迹**（会被当成透明），要用发光的饱和色。

### 规格表（格子大小 × 帧数；出图时按 N 帧横排，每帧至少 256px，游戏里会缩小）

| id | 用在哪里 | 格子 | 帧数 | 方向 / 构图 | 颜色 |
|---|---|---|---|---|---|
| `proj_wave` | 裂岳掌 · 飞行的龙形掌风（循环） | 96 | 4 | **朝右**，头在右、尾拖在左 | 青玉 + 金边 |
| `proj_palm` | 流云掌 · 追踪掌印（循环） | 64 | 4 | **朝右**，一个发光的掌印，带小云气尾巴 | 青绿 + 白芯 |
| `proj_bolt` | 八荒拳 · 拳气（循环） | 48 | 4 | **朝右**，短促的拳形气弹 | 金黄 |
| `proj_finger` | 点穴指 · 指劲（循环） | 48 | 4 | **朝右**，一道细长尖锐的指劲光针 | 金 + 朱红点 |
| `slash_fist` | 连环拳 · 拳风弧光 | 192 | 5 | **朝右**：圆心在画面正中，弧光向右扫出，最远处接近画面右缘 | 金黄 + 白芯 |
| `slash_heavy` | 连环拳末拳 / 金刚拳 · 重击弧光 | 192 | 6 | 同上，更粗更猛，带碎裂的气浪 | 朱红 + 金 |
| `burst_wind` | 回风掌 · 环身掌风 | 256 | 6 | 以画面中心向四周扩散的旋转气环 | 青 + 淡蓝 |
| `burst_quake` | 撼地拳 · 落点冲击 | 256 | 7 | 中心向外炸开的冲击波 + 飞溅的碎石 | 朱红 + 土黄 |
| `burst_gold` | 点穴连锁 · 爆炸 | 256 | 6 | 中心金色气爆，带放射的细光点 | 金 |
| `ring_taiji` | 太极劲 · 化解反击 | 256 | 6 | 阴阳鱼状的双色旋转气环向外扩散 | 青玉 + 金 |
| `ring_qinggong` | 轻功 · 落点冲击 | 256 | 6 | 脚下扩散的气浪环，带向外的速度线 | 青绿 |
| `burst_ult` | 真气爆发（大招） | 256 | 8 | 巨大的金色气浪从中心炸开，层层外扩，最后消散成光点 | 金 + 朱红 |
| `burst_break` | 破罡（Boss 罡气被打破） | 256 | 7 | 青色的护罡光罩碎裂成碎片向外飞散 | 青 + 白芯 |
| `halo_empower` | 催动光晕（盈境出手时脚下闪一下） | 128 | 4 | 中心的青色小光环向外一闪 | 青 |
| `zone_crack` | 撼地拳强化 · 裂地（循环） | 256 | 4 | 地面放射状裂缝，缝里透出微光，轻微闪烁 | 土黄 + 朱红缝光 |
| `zone_vortex` | 回风掌强化 · 旋涡（循环） | 256 | 6 | 向中心收拢的气旋，旋转 | 青 + 白 |
| `hit_impact` | 普通命中火花 | 64 | 4 | 小小的一次迸发，中心点 + 几道短射线 | 白黄 + 金 |
| `hit_crit` | 暴击命中火花 | 96 | 5 | 更大更亮的星芒迸发 | 金 + 朱红 |
| `trail_dash` | 轻功冲刺拖尾 | 96 | 4 | **朝右**，向左拖出的残影气线 | 青 |
| `death_puff` | 敌人倒下的烟尘 | 96 | 5 | 一团向外散开的尘雾（用灰蓝 / 土黄发光色，不要纯黑） | 灰蓝 + 土黄 |

约定：**画面正中心是特效的原点**；标了「朝右」的，游戏会按飞行 / 出招方向旋转。

### 提示词模板

把上面的风格块放在最前面，再加一行具体描述。示例（`proj_wave`）：

```
[风格块] N = 4 frames. A flying dragon-shaped palm-wind projectile, FACING RIGHT (head at the right, a long trailing tail to the left),
jade-green energy with gold edges, subtle looping flicker between frames so it looks alive when looped. Effect fits within the central 80% of each frame.
```

其余可以照这个格式改：

- `slash_fist`：`N = 5. A crescent fist-wind slash arc sweeping to the RIGHT, the arc's center of curvature at the center of each frame, the arc grows from thin to wide then fades; golden yellow with a white-hot core.`
- `burst_quake`：`N = 7. A ground-impact shockwave exploding outward from the exact center, flying rock fragments, vermilion red and earth-yellow, peaks at frame 3 then dissipates.`
- `ring_taiji`：`N = 6. A yin-yang style two-tone swirling ring (jade green and gold) expanding outward from the center and fading.`
- `burst_break`：`N = 7. A cyan protective energy dome shatters into glass-like shards that fly outward, white-hot cracks, then fades.`
- `hit_impact`：`N = 4. A tiny impact spark burst: a bright center dot and a few short rays, white-yellow and gold, over in 4 frames.`

### 优先级（建议先出这 10 个，影响最大）

`proj_wave` `proj_palm` `proj_bolt` `proj_finger` `slash_fist` `slash_heavy` `burst_wind` `burst_quake` `hit_impact` `hit_crit`

---

## 二、天赋经脉图

> **状态：背景图 `assets/ui/meridian_bg.jpg` 和穴位图标 `assets/ui/talent/` 已完成并接入**（穴位坐标已按这张图重新对齐）。下面的提示词留作记录；`meridian_layout_guide.png` 是旧版式参考，已不再对应当前坐标。

天赋树现在是「六脉」经脉图：**刚**走双臂（撼岳脉 / 裂石脉），**柔**走躯干中线（守一脉 / 抱元脉），**灵**走双腿（踏云脉 / 追风脉），每条脉 7 个穴位，从丹田向外延伸。
穴位的圆点、连线、数字都是游戏自己画的，所以**背景图里不要画穴位圆点、连线和文字**，只要人体和氛围。

### 2.1 背景图 `assets/ui/meridian_bg.png`

把 **`docs/meridian_layout_guide.png`**（人体姿势和穴位位置的参考图）一起发给 banana，作为参考图。

```
Use the attached reference image ONLY for the body pose, proportions and position: a front-facing standing human figure, arms hanging slightly away from the body,
legs shoulder-width apart, head at the top, the glowing "dantian" point just below the navel at 55% of the image height.
Draw a Chinese wuxia "meridian chart" background in a dark ink-wash style: deep indigo-black aged paper texture, the human figure rendered in soft ink-wash
with faint translucent muscle and qi flow, slightly luminous skin-edge glow, a faint golden glow at the dantian, subtle misty clouds and ink splashes at the edges.
Keep the body in exactly the same position and size as in the reference. The figure must stay centered with margins on both sides.
IMPORTANT: no meridian lines, no acupoint circles, no numbers, no text, no calligraphy, no seals, no border. Portrait, aspect ratio about 2:3 (taller than wide).
```

- 比例：2:3 左右都行（游戏按「铺满 + 居中裁切」，不会变形）；图里人的位置和大小要和参考图一致，否则穴位会对不上。
- 出完发给我，我会按实际的人体微调 `data/game_data.json` 里 `talents.map` 的穴位坐标。
- 放到 `assets/ui/meridian_bg.png` 即可，游戏会自动用它替换占位剪影。

### 2.2 穴位图标 `assets/ui/talent/node_*.png`（可选）

洋红底（#ff00ff）、横向一排 4 个图标，从左到右：**未打通 / 可点击 / 已有点数 / 已满**。要出成**偏灰白色**，游戏会按经脉着色（刚=朱红、柔=青、灵=紫）。

```
Pixel art icon set for a skill tree, 4 icons in ONE horizontal row on a flat MAGENTA background (#ff00ff), each icon centered in an equal-width cell, 
no text. Style: Chinese acupuncture point / jade bead, in desaturated off-white and grey tones so it can be tinted by color later.
1) dull dark grey stone bead (locked, unlit); 2) a bead with a bright thin ring (available); 3) a glowing lit bead with a small inner flame (has points);
4) a radiant golden-white lotus-shaped bead with sparkle rays (maxed). Crisp pixel edges, limited palette, all four the same size.
```

---

## 三、流程

**特效**

```bash
# 1. 把 banana 的图存到 assets/vfx/source/<id>.jpg（黑底横向条带；这个目录有 .gdignore，不会被打进游戏包）
# 2. 处理（帧数 / 格子大小 / fps 有默认值，见 `python3 tools/process_vfx.py list`）
python3 tools/process_vfx.py strip assets/vfx/source/proj_wave.jpg proj_wave
python3 tools/process_vfx.py strip assets/vfx/source/burst_quake.jpg burst_quake --trim   # 对称的爆发类可以加 --trim 填满格子
python3 tools/process_vfx.py list            # 看完成了多少
```

处理后会得到 `assets/vfx/<id>.png` 和 `assets/vfx/vfx.json`，**提交这两样**（`source/` 里的原图可以不提交）。

**天赋图**

```bash
python3 tools/process_icons.py 图标源图.jpg          # 穴位图标 → assets/ui/talent/
# 背景图直接放到 assets/ui/meridian_bg.png
```
