# 计划书 18（给 Gemini）：需要查证的资料（授权 / 署名）

> 游戏里新增了「致谢」页（登录界面和小镇菜单里都能打开），内容来自 `data/credits.json` / `docs/credits.md`。下面这些条目**我这边没法联网核实**，请 Gemini 逐项查证，并按末尾的格式回复，我再填进去。
> 查证原则：以**官方页面**为准（作者网站、Freesound、Kenney、Incompetech 等），不要凭印象；查不到就写「查不到」，不要猜。

## 一、背景音乐（作者与许可）
游戏里的曲目文件名 → 我记录的曲名。请找出**真实作者、官方来源链接、许可证（含版本）、署名格式要求、是否允许剪辑 / 调整响度 / 淡入淡出、是否允许商用**：

| 用在哪 | 曲名（我记录的） | 目前缺什么 |
|---|---|---|
| 登录界面 | Imperial China Cinematic | 作者、许可全部缺 |
| 小镇 | Guzheng City | 作者、许可全部缺 |
| 小 Boss | Boss Fight（Alexander Nakarada） | 许可证和署名格式未核实 |
| 大 Boss | Dragon Slayer（Makai Symphony） | 许可证和署名格式未核实 |
| 黑风寨 | Asian Drums（Kevin MacLeod） | 已核对，请复查是否 CC BY 4.0 |
| 光明顶 | Wuxia 3（PeriTune） | 已核对，请复查 |
| 桃花岛 | Eastern Thought（Kevin MacLeod） | 已核对，请复查 |

> 提示：Kevin MacLeod / Alexander Nakarada / Makai Symphony 的曲子一般要求在作品里署名，署名的**标准写法**请照官方给的格式抄。

## 二、音效采样（许可）
`docs/credits.md` 里列了一批 Freesound / Kenney 的作者与包名，请逐个确认**许可证是否真的是 CC0（或 CC BY）**，并给出**官方链接**。重点复查：
1. **qubodup & Slave2theLight — Sword Slash Attack**：我记录为 CC BY 3.0，请确认，并给出标准署名格式。
2. **Qvantor** 的三个包（Cinematic Booms Trailer Hits、Success、Level Up / Reward Sounds）：CC0？
3. **Kenney** 的 Impact Sounds、UI Audio、RPG Audio：CC0？
4. 其余 14 位作者（CastIronCarousel、GammaGool、Bertsz、Vrymaa、Kinoton、nanliu_music、Jagadamba、Sadiquecat、michorvath、steprock、LiamG_SFX、JohnBuhr、AardsReal、Kane53126、courtneyeck）：每人的作品是否都是 CC0；**其中有没有哪个是 CC BY / CC BY-NC**（NC 版本不能用于游戏，必须告诉我）。

## 三、字体 / 引擎
- **霞鹜文楷（LXGW WenKai）**：确认许可证是 SIL OFL 1.1，以及「裁剪字库后再分发」是否允许、是否需要保留版权声明。
- **Godot Engine 4**：确认 MIT 许可要求的署名写法（游戏里放在致谢页即可）。

## 四、Gemini 自己生成的美术 / 音效
- 请确认：用 Gemini 生成的**图片和音频**，目前服务条款是否允许放进**免费分发**的游戏里？是否要求声明「由 AI 生成」？有无商用限制？（给出条款链接和日期。）

## 五、回复格式（方便我直接粘贴）
每一项一行，格式：
`场景 / 作品 | 作者 | 许可证（版本） | 官方链接 | 署名写法 | 备注（能否剪辑 / 商用 / 需不需要加密）`
查不到的写「查不到：原因」。
