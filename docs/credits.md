# 素材来源与致谢

## 背景音乐（assets/bgm，原始 mp3 在 Google Drive 的 bgm 文件夹；游戏里用的是转成 ogg 的版本）
| 场景 | 曲目 | 作者 / 来源 |
|---|---|---|
| 登录界面 | Imperial China Cinematic | （请补充作者与许可） |
| 小镇 | Guzheng City | （请补充作者与许可） |
| 黑风寨 | Asian Drums | Kevin MacLeod (incompetech.com)，CC BY 4.0 |
| 光明顶 | Wuxia 3 | PeriTune (peritune.com)，CC BY 4.0（可商用，署名任意；若将来收费发售需对音频加密打包） |
| 桃花岛 | Eastern Thought | Kevin MacLeod (incompetech.com)，CC BY 4.0（必须署名） |
| 小 Boss | Boss Fight | Alexander Nakarada |
| 大 Boss | Dragon Slayer | Makai Symphony |

> 使用前请核对每首曲子的许可证（很多免费曲目要求署名，如 CC BY）。朋友间非商业试玩通常没问题，但署名要求要遵守。

## 字体
- 霞鹜文楷（LXGW WenKai），SIL OFL，见 `assets/fonts/OFL.txt`。

## 美术
- 像素精灵、立绘、封面、结算插画、图标、特效、建筑：由项目作者用 AI 绘图工具制作。

## 音效（assets/sfx，由 `tools/build_sfx_real.py` 裁切 / 变调 / 叠加 / 统一响度）
以下均为 CC0，另有一项 CC-BY（需署名）。采样来自 freesound.org 与 kenney.nl。
- **qubodup**（Iwan Gabovitch）：Free Whoosh Sound Pack（CC0）— 剑 / 刀 / 掌的挥动声。
- **qubodup & Slave2theLight**：Sword Slash Attack（**CC-BY 3.0**，署名）— 刀客「血刀经」、`bl_blood`。
- **Qvantor**：Cinematic Booms Trailer Hits、Success / Level Up / Reward Sounds（CC0）— 冲击、锣鸣、升级、通关。
- **Kenney**：Impact Sounds、UI Audio（CC0）— 命中、破甲、界面点击。
- **CastIronCarousel**：Punches（CC0）— 拳击命中。
- **GammaGool**（Powerful Slice）、**Bertsz**（Rock destroy）、**Vrymaa**（Sword Unsheathe）、**Kinoton**（Whoosh #1）、
  **nanliu_music**（古筝单音）、**Jagadamba**（锣）、**Sadiquecat**（C5 chime）、**michorvath**（Anvil Hit 2）、
  **steprock**（Treasure Chest Open）、**LiamG_SFX**（Arrow Fly-by）、**JohnBuhr**（Sword Clash）、**AardsReal**（Basic Metal Clang）、
  **Kane53126**（Body Thud）、**courtneyeck**（Falling body）— 均为 CC0。
- 原始文件放在作者的云端硬盘 `sfx_raw`（不进仓库）；重新生成：`python3 tools/build_sfx_real.py <原始采样目录>`。
- **Kenney**：RPG Audio（CC0）— 脚步声、翻页（升级选卡）。


---
## 查证结果（2026-11-22，由 Gemini 按官方页面核对；我没有独立复核）
**背景音乐**：登录曲 = Imperial China Cinematic，Shane Ivers（Silverman Sound），CC BY 4.0；小镇曲 = Guzheng City，Kevin MacLeod，CC BY 4.0；黑风寨 = Asian Drums，桃花岛 = Eastern Thought（均 Kevin MacLeod，CC BY 4.0）；光明顶 = Wuxia 3，PeriTune（署名任意；若将来收费发售需加密打包）；小 Boss = Boss Fight，Alexander Nakarada，CC BY 4.0；大 Boss = Dragon Slayer，Makai Symphony（官网自定义条款，第三方站标 CC BY-SA 3.0，禁止单独再分发音乐）。
**音效风险（需关注）**：LiamG_SFX 全部 CC BY-NC 4.0；Vrymaa、Jagadamba 含 CC BY-NC 4.0；CastIronCarousel 混合 CC0 / CC BY 3.0。**现在是朋友间免费试玩，NC 可以；若将来商业化，必须替换或逐条核对具体采样。** Kenney 的包请以下载包内 license.txt 为准（Gemini 查不到官网）。
**字体**：霞鹜文楷裁剪后分发须保留 OFL.txt 全文；裁剪版属修改版，不得用 `霞鹜` / `LXGW` 作为对外展示的字体主名（待核实 Reserved Font Name 条款）。
**引擎**：Godot，MIT，致谢页写明即可。
**AI 生成内容**：Google 条款不主张生成内容所有权，允许免费分发 / 商用；不强制标注，但不得欺骗性冒充纯人工创作，致谢页已注明。
