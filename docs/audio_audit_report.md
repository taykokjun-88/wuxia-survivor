# 音频版权与体积审计报告（C 线）

> 由 `python3 tools/audit_audio.py --write-report` 自动生成。

## 一、核心结论
- **BGM 共 7 首（14.48 MB）**：5 首 CC BY 4.0 可保留（需署名），**2 首存在商用风险（`guangming.ogg` PeriTune、`final_boss.ogg` Makai Symphony）**。
- **SFX 共 122 个（19.67 MB）**：**已清除全部 23 个未播放的旧版单声道兜底残留文件**。现存音效中 **116 个为 Gemini SFX v2**、**6 个为 Kenney RPG Audio（CC0）**，**已无任何 CC BY-NC（LiamG_SFX / Vrymaa / Jagadamba）音效文件**。
- **体积优化空间**：当前 `assets/sfx/` 全部为未压缩 44.1kHz PCM WAV（其中 116 个为双声道，占 19.67 MB）。后续如网页包逼近 70 MB 红线，将双声道 WAV 降为单声道或转为 OGG Vorbis 预计可立省 **12~16 MB**。

## 二、BGM 逐首清单（7 首）
| 文件 | 大小 | 来源 / 曲目 | 许可 | 状态 | 处理建议 |
|---|---:|---|---|---|---|
| `assets/bgm/black_wind.ogg` | 1.29 MB | Kevin MacLeod — Asian Drums | CC BY 4.0 | **OK** | 保留，需署名 |
| `assets/bgm/boss.ogg` | 1.00 MB | Alexander Nakarada — Boss Fight | CC BY 4.0 | **OK** | 保留，需署名 |
| `assets/bgm/final_boss.ogg` | 2.01 MB | Makai Symphony — Dragon Slayer | Custom Terms (禁止单独再分发，曲名含旧IP词) | **WARN-Commercial** | V1.0 前建议换曲 |
| `assets/bgm/guangming.ogg` | 2.95 MB | PeriTune — Wuxia 3 | PeriTune Terms (商用需核实授权/加密条款) | **WARN-Commercial** | V1.0 前向 PeriTune 官网核实或换曲 |
| `assets/bgm/login.ogg` | 2.24 MB | Shane Ivers — Imperial China Cinematic | CC BY 4.0 | **OK** | 保留，需署名 |
| `assets/bgm/taohua.ogg` | 3.83 MB | Kevin MacLeod — Eastern Thought | CC BY 4.0 | **OK** | 保留，需署名 |
| `assets/bgm/town.ogg` | 1.15 MB | Kevin MacLeod — Guzheng City | CC BY 4.0 | **OK** | 保留，需署名 |

## 三、SFX 分类汇总（122 个）
| 来源 | 数量 | 许可 | 状态 | 说明 |
|---|---:|---|---|---|
| Google Gemini SFX v2（双声道 WAV） | 116 | AI-Gemini | **OK** | 已覆盖全部战斗/技能/Boss/UI/命中/受击/格挡/八卦音效；需真人试听挑刺 |
| Kenney — RPG Audio（单声道 WAV） | 6 | CC0 | **OK** | `card_pick_1..2.wav`、`footstep_1..4.wav` |
| 原 CC BY-NC 旧采样（LiamG / Vrymaa / Jagadamba） | 0 | — | **已清零** | 已由 Gemini SFX v2 替换，且 23 个旧单声道兜底残留已移除 |

## 四、V1.0 音频剩余动作
1. 【你】试听 116 个 Gemini SFX v2，记下不满意的音效名（可按类型重做/调响度）。
2. 【你】敲定 `guangming.ogg`（PeriTune）与 `final_boss.ogg`（Makai Symphony）的替换方案（CC0 曲库 / 买授权 / AI 原创 / 委托）。
3. 【我】新曲接入后运行 `python3 tools/audit_audio.py --strict`，确保 0 告警通过 V1.0 出口门禁。
