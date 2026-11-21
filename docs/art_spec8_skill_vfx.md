> **已并入 `docs/art_spec9_yangjiajiang.md`（第三部分 C），以那份为准。**

# 美术计划书 8（给 Gemini）：招式差异化新特效 ×5

> 通用规格不变：**纯洋红底 #FF00FF（整张同一个颜色，不要偏紫 / 偏粉、不要渐变）**，像素风，光源左上，特效不要带文字。
> 每张是**横排帧条**，按下面写的帧数 × 格子边长排列（例：4 帧 × 192 → 768×192）。文件名覆盖 / 新增同名，**不要加版本后缀**。放 Drive 的 `wuxia-survivor-sword-assets` 文件夹，我来跑 `tools/process_vfx.py` 接入。

## 为什么要新图
这一轮把几个招式的机制改了（为了拉开职业差异），原来的特效只适合旧机制：

| # | 文件 | 对应招式 / 机制 | 帧 | 格子 | 说明 |
|---|---|---|---|---|---|
| 1 | `fx_blade_bleed_pop.png` | 刀客·狂风刀法：每第 4 次出刀引爆敌人身上的撕裂 | 4 | 192 | 暗红色：以敌人为中心**迸开的血色十字刀痕 + 飞溅的血点**（像素风，不血腥不写实；颜色偏深红 / 暗金），由小到大再迅速消散。第 1 帧小、第 3 帧最大 |
| 2 | `fist_whirl_ring.png` | 武者·落英神剑掌：内力越满连发 1~3 圈 | 4 | 192 | **一圈**由中心向外扩散的掌风环（水墨黑 + 淡金边，带几片飘散的落英花瓣）。程序会叠 1~3 个不同大小的环，所以这一张只画单环、居中、四周留白，第 4 帧淡出 |
| 3 | `sw_taiji_reflect.png` | 剑客·太极剑：把敌方弹幕原路打回 | 4 | 192 | 被弹开的瞬间：**一个小太极阴阳鱼图案**在命中点亮起并旋转，周围是青白色的反震波纹；第 1~2 帧最亮，之后淡出 |
| 4 | `proj_taiji_reflect.png` | 被打回的弹体（变成我方弹体） | 4 | 96，循环 | **朝右**的青白色光球 / 小阴阳鱼，拖一条短尾（太极的黑白对比，边缘有一点青光），可以略微旋转循环。要和敌方的红色弹体明显区分（现在敌方弹幕偏红橙） |
| 5 | `sw_qingsong_wave.png` | 剑客·青松剑法：剑锋前敌人 ≥2 个时的「松涛」 | 4 | 192 | **宽幅的松针形剑气弧**：青绿色的一道弧形剑光，边缘带细碎的松针 / 竹叶状的小光片，像一阵风吹过松林；比普通青松剑光（`sw_qingsong`）更宽更密，朝右，弧形从左下扫到右上 |

## 提示词参考（Gemini）
- 通用后缀：`pixel art game VFX sprite sheet, 4 frames in a horizontal strip, each frame 192x192, solid pure magenta #FF00FF background, no text, no shadows on the background, crisp pixels, light from top-left`
- 1：`a dark red slashing cross-shaped blood-spray burst, stylized not gory, expanding then fading, chinese wuxia style`
- 2：`a single expanding circular palm-wind ring in ink black with pale gold edge and a few drifting flower petals, centered, wuxia style`
- 3：`a small taichi yin-yang symbol flashing and rotating at an impact point with cyan-white shockwave ripples, wuxia style`
- 4：`a small cyan-white glowing orb with a tiny yin-yang pattern and a short trail, facing right, looping 4 frames, 96x96 per frame`
- 5：`a wide crescent sword-energy arc in jade green with pine-needle shaped shards along the edge, sweeping from lower-left to upper-right, wuxia style`

## 接入（我这边）
- `assets/vfx/vfx.json` 登记：1 号 `fps 20`、`world_size 200`；2 号 `world_size` 按半径缩放；3 号 `world_size 160`；4 号循环 `world_size 90`；5 号 `fps 20`、`world_size 260`。
- 代码里：引爆撕裂时播 1 号；落英掌每圈播 2 号；太极剑反弹时在每枚弹幕位置播 3 号并把弹体贴图换成 4 号；青松「松涛」时播 5 号。
- 没有这些图时，游戏照常用现有特效，不影响运行。
