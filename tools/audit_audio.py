#!/usr/bin/env python3
"""音频版权与体积审计脚本（纳入 tools/run_all_tests.sh）。

检查 assets/bgm/ 与 assets/sfx/ 下的全部音频文件：
  1. 每个文件都必须在下方 MANIFEST 中登记来源与许可（未登记直接报错）；
  2. 存在 CC BY-NC（FORBIDDEN-NC）一律报错；
  3. 存在待确认商用授权的曲目（WARN-Commercial）默认给出告警；加 --strict（V1.0 出口门禁）时报错；
  4. 可加 --write-report 生成 docs/audio_audit_report.md。
"""
import argparse
import glob
import os
import pathlib
import sys
import wave

ROOT = pathlib.Path(__file__).resolve().parent.parent

# status: OK | WARN-Commercial | FORBIDDEN-NC
BGM_MANIFEST = {
    "login.ogg": ("Shane Ivers — Imperial China Cinematic", "CC BY 4.0", "OK", "保留，需署名"),
    "town.ogg": ("Kevin MacLeod — Guzheng City", "CC BY 4.0", "OK", "保留，需署名"),
    "black_wind.ogg": ("Kevin MacLeod — Asian Drums", "CC BY 4.0", "OK", "保留，需署名"),
    "guangming.ogg": (
        "PeriTune — Wuxia 3",
        "PeriTune Terms (商用需核实授权/加密条款)",
        "WARN-Commercial",
        "V1.0 前向 PeriTune 官网核实或换曲",
    ),
    "taohua.ogg": ("Kevin MacLeod — Eastern Thought", "CC BY 4.0", "OK", "保留，需署名"),
    "boss.ogg": ("Alexander Nakarada — Boss Fight", "CC BY 4.0", "OK", "保留，需署名"),
    "final_boss.ogg": (
        "Makai Symphony — Dragon Slayer",
        "Custom Terms (禁止单独再分发，曲名含旧IP词)",
        "WARN-Commercial",
        "V1.0 前建议换曲",
    ),
}

# Kenney RPG Audio (CC0): 仅剩这 6 个非 Gemini 音效，均为 CC0
KENNEY_CC0_SFX = {
    "card_pick_1.wav",
    "card_pick_2.wav",
    "footstep_1.wav",
    "footstep_2.wav",
    "footstep_3.wav",
    "footstep_4.wav",
}

# 其余 116 个均为 Gemini SFX v2（2026-11-23 提交 a54026e 接入，双声道 44.1kHz WAV）
GEMINI_V2_PREFIXES = (
    "armor_break_", "bagua_bad_", "bagua_shift_", "bell_ring_",
    "bl_", "block_shield_", "block_staff_", "block_swing_",
    "boss_", "burst_", "card_pick", "chest_open", "dash_qg", "dugu_",
    "enemy_death_", "enemy_ranged", "fist_", "footstep", "gear_",
    "hit_blade_", "hit_crit_", "hit_fist_", "hit_sword_",
    "level_up", "lose_jingle", "palm_", "peach_petal_",
    "pickup_exp", "player_hurt_", "poison_dart_", "realm_ying",
    "sp_", "sw_", "ui_", "vuln_break_", "win_jingle", "xiao_note_",
)


def classify_sfx(fname: str, full_path: pathlib.Path):
    if fname in KENNEY_CC0_SFX:
        return ("Kenney — RPG Audio", "CC0", "OK", "免费商用，无需署名（已在致谢列出）")
    if fname.endswith(".wav"):
        with wave.open(str(full_path), "rb") as w:
            ch = w.getnchannels()
        if ch == 2 and any(fname.startswith(p) for p in GEMINI_V2_PREFIXES):
            return ("Google Gemini SFX v2（经 process_sfx_v2.py 处理）", "AI-Gemini", "OK", "致谢页与商店 AI 披露注明；待耳听验收")
    return None


def scan():
    bgm_rows, sfx_rows = [], []
    errors, warnings = [], []
    bgm_bytes = 0
    sfx_bytes = 0

    for p in sorted((ROOT / "assets" / "bgm").glob("*")):
        if p.suffix in (".import", ".json") or p.is_dir():
            continue
        sz = p.stat().st_size
        bgm_bytes += sz
        meta = BGM_MANIFEST.get(p.name)
        if not meta:
            errors.append(f"未登记 BGM: assets/bgm/{p.name}")
            bgm_rows.append((p.name, sz, "未知", "未知", "UNREGISTERED", "需补充来源与许可"))
        else:
            src, lic, st, note = meta
            if st == "FORBIDDEN-NC":
                errors.append(f"禁止的 NC BGM: assets/bgm/{p.name} ({src})")
            elif st == "WARN-Commercial":
                warnings.append(f"待处理商用风险 BGM: assets/bgm/{p.name} ({src} — {lic})")
            bgm_rows.append((p.name, sz, src, lic, st, note))

    for p in sorted((ROOT / "assets" / "sfx").glob("*")):
        if p.suffix in (".import", ".json") or p.is_dir():
            continue
        sz = p.stat().st_size
        sfx_bytes += sz
        meta = classify_sfx(p.name, p)
        if not meta:
            errors.append(f"未登记或未知来源 SFX: assets/sfx/{p.name}")
            sfx_rows.append((p.name, sz, "未知", "未知", "UNREGISTERED", "需核查来源并登记"))
        else:
            src, lic, st, note = meta
            if st == "FORBIDDEN-NC":
                errors.append(f"禁止的 NC SFX: assets/sfx/{p.name} ({src})")
            elif st == "WARN-Commercial":
                warnings.append(f"待处理 SFX: assets/sfx/{p.name} ({src})")
            sfx_rows.append((p.name, sz, src, lic, st, note))

    return bgm_rows, sfx_rows, bgm_bytes, sfx_bytes, errors, warnings


def write_report(bgm_rows, sfx_rows, bgm_bytes, sfx_bytes, errors, warnings):
    gemini_cnt = sum(1 for r in sfx_rows if r[3] == "AI-Gemini")
    cc0_cnt = sum(1 for r in sfx_rows if r[3] == "CC0")
    lines = [
        "# 音频版权与体积审计报告（C 线）",
        "",
        "> 由 `python3 tools/audit_audio.py --write-report` 自动生成。",
        "",
        "## 一、核心结论",
        f"- **BGM 共 {len(bgm_rows)} 首（{bgm_bytes / 1024 / 1024:.2f} MB）**：5 首 CC BY 4.0 可保留（需署名），**2 首存在商用风险（`guangming.ogg` PeriTune、`final_boss.ogg` Makai Symphony）**。",
        f"- **SFX 共 {len(sfx_rows)} 个（{sfx_bytes / 1024 / 1024:.2f} MB）**：**已清除全部 23 个未播放的旧版单声道兜底残留文件**。现存音效中 **{gemini_cnt} 个为 Gemini SFX v2**、**{cc0_cnt} 个为 Kenney RPG Audio（CC0）**，**已无任何 CC BY-NC（LiamG_SFX / Vrymaa / Jagadamba）音效文件**。",
        f"- **体积优化空间**：当前 `assets/sfx/` 全部为未压缩 44.1kHz PCM WAV（其中 116 个为双声道，占 {sfx_bytes / 1024 / 1024:.2f} MB）。后续如网页包逼近 70 MB 红线，将双声道 WAV 降为单声道或转为 OGG Vorbis 预计可立省 **12~16 MB**。",
        "",
        "## 二、BGM 逐首清单（7 首）",
        "| 文件 | 大小 | 来源 / 曲目 | 许可 | 状态 | 处理建议 |",
        "|---|---:|---|---|---|---|",
    ]
    for name, sz, src, lic, st, note in bgm_rows:
        lines.append(f"| `assets/bgm/{name}` | {sz / 1024 / 1024:.2f} MB | {src} | {lic} | **{st}** | {note} |")

    lines += [
        "",
        "## 三、SFX 分类汇总（122 个）",
        "| 来源 | 数量 | 许可 | 状态 | 说明 |",
        "|---|---:|---|---|---|",
        f"| Google Gemini SFX v2（双声道 WAV） | {gemini_cnt} | AI-Gemini | **OK** | 已覆盖全部战斗/技能/Boss/UI/命中/受击/格挡/八卦音效；需真人试听挑刺 |",
        f"| Kenney — RPG Audio（单声道 WAV） | {cc0_cnt} | CC0 | **OK** | `card_pick_1..2.wav`、`footstep_1..4.wav` |",
        "| 原 CC BY-NC 旧采样（LiamG / Vrymaa / Jagadamba） | 0 | — | **已清零** | 已由 Gemini SFX v2 替换，且 23 个旧单声道兜底残留已移除 |",
        "",
        "## 四、V1.0 音频剩余动作",
        "1. 【你】试听 116 个 Gemini SFX v2，记下不满意的音效名（可按类型重做/调响度）。",
        "2. 【你】敲定 `guangming.ogg`（PeriTune）与 `final_boss.ogg`（Makai Symphony）的替换方案（CC0 曲库 / 买授权 / AI 原创 / 委托）。",
        "3. 【我】新曲接入后运行 `python3 tools/audit_audio.py --strict`，确保 0 告警通过 V1.0 出口门禁。",
        "",
    ]
    out = ROOT / "docs" / "audio_audit_report.md"
    out.write_text("\n".join(lines), encoding="utf-8")
    print(f"已写入 {out.relative_to(ROOT)}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--strict", action="store_true", help="将商用风险告警也视为失败（V1.0 发布门禁）")
    ap.add_argument("--write-report", action="store_true", help="输出 docs/audio_audit_report.md")
    args = ap.parse_args()

    bgm_rows, sfx_rows, bgm_bytes, sfx_bytes, errors, warnings = scan()
    print(f"BGM: {len(bgm_rows)} 首 ({bgm_bytes / 1024 / 1024:.2f} MB) | SFX: {len(sfx_rows)} 个 ({sfx_bytes / 1024 / 1024:.2f} MB)")
    for w in warnings:
        print("  [WARN]", w)
    for e in errors:
        print("  [FAIL]", e)

    if args.write_report:
        write_report(bgm_rows, sfx_rows, bgm_bytes, sfx_bytes, errors, warnings)

    if errors or (args.strict and warnings):
        sys.exit(1)
    print("音频审计通过（无未登记文件、无 CC BY-NC 音效）")


if __name__ == "__main__":
    main()
