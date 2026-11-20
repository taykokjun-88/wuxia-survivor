# 计划书 5：音效搜寻清单（给 Gemini）

## 为什么要换
现在的音效是程序合成的，听感「软、拖、不干脆」。要换成**真实录制 / 高品质采样**的音效，招式要有「一下就到位」的打击感。

## 通用要求（每个文件都要符合）
- 格式：WAV 或 OGG，44.1kHz，单声道或立体声均可；单个文件 **≤ 200KB**。
- **起音必须干脆**：文件开头不留静音（0~5ms 内就出声），音头要有明显的瞬态（transient）。
- **尾巴要短**：不带长混响。打击 / 命中类 ≤ 0.25 秒；挥砍类 ≤ 0.4 秒；大招 / Boss ≤ 1.2 秒。
- 音量统一：峰值约 −3 dB，同类别响度接近。
- **同一类给 3 个变体**（命中 / 挥砍 / 受击），游戏里随机轮换，避免听腻。变体命名 `名字_1`、`名字_2`、`名字_3`。
- 版权：优先 **CC0**（freesound.org、opengameart.org、kenney.nl、sonniss GDC 免费包、pixabay）；CC-BY 也行，但要记下 **作者 + 链接 + 授权**，我写进 `docs/credits.md`。
- 风格：写实、国风偏冷兵器 / 武侠电影质感。不要科幻、不要卡通「biu / boing」、不要 8-bit 电子音。

## 搜索关键词建议
`sword swing` `katana slash` `blade whoosh` `sword hit flesh` `sword clash metal` `punch impact` `body hit thud` `palm strike` `wind whoosh` `gong hit` `taiko drum hit` `guzheng pluck` `chinese bell` `armor hit` `shield block` `bow release` `arrow whoosh` `wood impact` `stone crack` `coin pickup` `level up chime`

## A. 剑法（高、细、带金属「铮」）
| 文件名 | 用在哪 | 想要的听感 |
|---|---|---|
| sw_slash | 基础挥剑 | 细而快的剑气划空 whoosh，0.2s，末尾带一点点金属嗡 |
| sw_thrust | 直刺 | 尖锐的「嗖」+ 短促刺入声 |
| sw_proj | 飞剑 / 剑气射出 | 弓弦般的短促释放 + 破空 |
| sw_ring | 剑气环绕 / 回旋 | 连续金属摩擦 / 短促旋转 whoosh |
| sw_multi | 多剑齐发 | 3~5 个很快的 whoosh 连串 |
| sw_heavy | 重剑一击 | 低沉大力挥舞 + 重击落地 |
| sw_blink | 瞬移 / 闪现剑 | 一声「唰」+ 细微空气爆裂 |
| sw_snake | 灵蛇（软剑） | 带颤抖的金属嘶鸣 |
| sw_yitian | 倚天剑（大招） | 一声清亮长剑出鞘 + 低沉共鸣，≤1s |
| dugu_flash / dugu_awaken | 独孤九剑出招 / 觉醒 | 极干脆的「叮」+ 一道很快的剑气；觉醒带低鸣 |

## B. 刀法（宽、重、有体感）
| 文件名 | 用在哪 | 听感 |
|---|---|---|
| bl_slash | 基础劈砍 | 厚重刀锋破空，比剑低、宽 |
| bl_heavy | 重刀劈 | 重重落下 + 低频冲击 |
| bl_spin | 回旋斩 | 连续的低沉旋转 whoosh |
| bl_wheel | 刀轮 / 连环 | 2~3 次快速砍 |
| bl_proj | 刀气飞出 | 低沉破空 |
| bl_blood | 耗血 / 血刀 | 撕裂声 + 闷哼般的低频（不要真的血腥尖叫） |
| bl_fire | 燃木刀 | 火焰点燃 whoosh + 噼啪 |
| bl_quake | 破岳震地 | 石头裂开 + 低频震动，≤0.8s |
| bl_dragon | 屠龙刀 | 沉重金属 + 龙吟般的低频共鸣，≤1.2s |

## C. 拳掌（闷、低频、有冲击）
| 文件名 | 用在哪 | 听感 |
|---|---|---|
| fist_punch | 基础拳 | 结实的拳击肉体「砰」，低频饱满 |
| fist_finger | 一指 / 点穴 | 短促尖锐的「啵」+ 气流 |
| fist_vajra | 金刚拳 | 厚重金属感的拳击 |
| fist_quake | 震地拳 | 地面重击 + 碎石 |
| palm_soft | 绵掌 | 柔和的气流「呼」 |
| palm_wave | 掌风 / 波 | 一股压缩空气推出 |
| palm_multi | 连环掌 | 3~4 次快速气流拍击 |
| palm_dragon | 降龙十八掌 | 低沉龙吟 + 巨大气爆，≤1s |

## D. 命中 / 受击 / 死亡（最影响「干脆感」，每类 3 个变体）
| 文件名 | 听感 |
|---|---|
| hit_sword | 剑砍中身体：短而脆的「嚓」，0.12s |
| hit_blade | 刀砍中：更厚的「噗嚓」，0.15s |
| hit_fist | 拳掌打中：闷「砰」，0.12s |
| hit_crit | 暴击：命中声 + 一声清脆金属「叮」，0.25s |
| enemy_death | 小怪死亡：短促倒地 / 消散，≤0.3s |
| player_hurt | 玩家受伤：短促闷哼般的冲击，≤0.2s（不要人声尖叫） |
| armor_break / block_shield / vuln_break | 破甲「咔」/ 格挡金属「当」/ 破绽「啪」 |

## E. 系统与场景
| 文件名 | 听感 |
|---|---|
| level_up | 古筝拨弦上扬 + 一声清脆铃，≤0.8s |
| pickup_exp | 极短的玉石 / 水滴「叮」，0.1s，会高频连发，必须不刺耳 |
| dash_qg | 轻功冲刺：衣袂 + 气流「唰」，0.25s |
| burst_break / burst_ult | 真气爆发：低沉鼓 + 气浪；大招：锣 + 爆发，≤1s |
| realm_ying | 进入盈境：一声清亮的磬 / 钟，带轻微共鸣 |
| boss_warn | Boss 警告：沉重的鼓 / 号角，≤1s |
| boss_cleave | Boss 重击：巨大重击 + 低频 |
| enemy_ranged | 敌人放箭：弓弦释放 + 箭飞出 |

## F. 新增（现在没有的，请额外找）
`ui_click`（按钮点击）、`ui_confirm`（确认）、`ui_back`（返回）、`card_pick`（选择升级卡片）、`chest_open`（开箱 / 掉落）、`gear_upgrade`（装备强化成功，铁匠锤 + 叮）、`gear_fail`（装备强化失败）、`win_jingle`（通关短曲 ≤3s）、`lose_jingle`（失败短曲 ≤3s）、`footstep`（脚步，可选）。

## 交付
- 打包成文件夹（文件名按上表），再附一份 `sfx_sources.csv`：`文件名, 来源链接, 作者, 授权`。
- 放进共享云端硬盘，告诉我，我来做裁切、音量标准化和接入（`assets/sfx/<文件名>.wav`，游戏会优先加载这些文件；变体 `_1/_2/_3` 我来加随机轮换）。
- 如果某一类找不到满意的，请标出「待补」，不要用低质量的凑数。
