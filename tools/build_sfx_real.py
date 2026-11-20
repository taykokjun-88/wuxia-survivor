#!/usr/bin/env python3
"""把真实采样（CC0 / CC-BY，见 docs/credits.md）裁切、变调、叠加、统一音量，输出到 assets/sfx/<id>.wav。
用法：python3 tools/build_sfx_real.py <原始采样目录>
原始文件名见 SRC 表（目录里按这些名字放）。变体输出为 <id>_1.wav / _2 / _3，游戏里随机轮换。
"""
import pathlib, subprocess, sys
import numpy as np
from scipy import signal

SR = 44100
RAW = pathlib.Path(sys.argv[1])
OUT = pathlib.Path(__file__).resolve().parent.parent / "assets" / "sfx"


def load(name):
    p = subprocess.run(["ffmpeg", "-v", "error", "-i", str(RAW / name), "-f", "f32le", "-ac", "1", "-ar", str(SR), "-"], capture_output=True, check=True)
    x = np.frombuffer(p.stdout, dtype=np.float32).copy()
    return x


def lead_trim(x, db=-42.0):
    th = max(float(np.max(np.abs(x))) * 10 ** (db / 20.0), 1e-4)
    idx = np.nonzero(np.abs(x) > th)[0]
    return x[max(0, idx[0] - int(0.002 * SR)):] if len(idx) else x


def src(name, dur=None, semis=0.0, lp=None, hp=None, start=0.0):
    x = lead_trim(load(name))
    if start:
        x = x[int(start * SR):]
    if semis:
        r = 2 ** (semis / 12.0)
        n = int(len(x) / r)
        x = np.interp(np.linspace(0, len(x) - 1, n), np.arange(len(x)), x)
    if dur:
        x = x[:int(dur * SR)]
    if lp:
        b, a = signal.butter(2, lp / (SR / 2), "low"); x = signal.lfilter(b, a, x)
    if hp:
        b, a = signal.butter(2, hp / (SR / 2), "high"); x = signal.lfilter(b, a, x)
    return x.astype(np.float32)


def fade(x, out=0.04):
    n = min(len(x), int(out * SR))
    if n > 0:
        x = x.copy(); x[-n:] *= np.linspace(1, 0, n) ** 1.5
    return x


def mix(*parts):
    """parts: (signal, gain, delay_seconds)"""
    n = max(int(d * SR) + len(s) for s, g, d in parts)
    y = np.zeros(n, np.float32)
    for s, g, d in parts:
        o = int(d * SR); y[o:o + len(s)] += s * g
    return y


LOUD = {"pickup_exp": -27, "footstep": -27, "card_pick": -22, "ui_click": -23, "ui_confirm": -23, "ui_back": -23, "chest_open": -22, "enemy_ranged": -21,
        "level_up": -20, "realm_ying": -20, "win_jingle": -19, "lose_jingle": -19, "hit_sword": -21, "enemy_death": -22,
        "boss_warn": -15, "boss_cleave": -15, "burst_break": -16, "burst_ult": -15, "bl_dragon": -15, "bl_quake": -16,
        "palm_dragon": -15, "fist_quake": -17, "sw_yitian": -17, "dugu_awaken": -17}


def save(name, x, peak=0.9, tail=0.04):
    """按响度（RMS dB）统一音量：同类音效听感一样响，峰值不超过 0.9"""
    import wave
    x = fade(x, tail)
    base = name.rsplit("_", 1)[0] if name[-2:] in ("_1", "_2", "_3") else name
    target = LOUD.get(base, -19)
    rms = float(np.sqrt(np.mean(x ** 2))) or 1e-6
    g = 10 ** (target / 20.0) / rms
    g = min(g, peak / (float(np.max(np.abs(x))) or 1.0))
    pcm = (np.clip(x * g, -1, 1) * 32767).astype(np.int16)
    with wave.open(str(OUT / f"{name}.wav"), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(pcm.tobytes())


S = src
J = {}

# ---- 剑：细、亮、带金属「铮」 ----
J["sw_slash"] = lambda: mix((S("w_60004_fastsword.flac", .3), 1, 0), (S("k_tin_000.ogg", hp=1500), .35, .12))
J["sw_thrust"] = lambda: S("w_60005_sharp18.flac", .3, hp=500)
J["sw_proj"] = lambda: S("whoosh1.wav", .35, semis=2)
J["sw_ring"] = lambda: S("w_60025_double2.flac", .55)
J["sw_multi"] = lambda: S("w_60021_triple.flac", .8)
J["sw_heavy"] = lambda: mix((S("w_60003_loud16.flac", .45, semis=-3), 1, 0), (S("q_punchyboom.wav", .3, lp=900), .5, .05))
J["sw_blink"] = lambda: S("w_60023_windy36.flac", .32, hp=600, semis=2)
J["sw_snake"] = lambda: mix((S("w_60006_metalrod.flac", .4), 1, 0), (S("k_tin_001.ogg", hp=1800), .4, .1))
J["sw_yitian"] = lambda: mix((S("unsheathe.wav", 1.0), 1, 0), (S("q_lowgong.wav", 1.0, lp=1200), .4, .3))
J["dugu_flash"] = lambda: mix((S("clang.wav", .22, semis=3), 1, 0), (S("w_59988_swosh01.flac", .2, hp=1500), .5, 0))
J["dugu_awaken"] = lambda: mix((S("unsheathe.wav", 1.0, semis=2), 1, 0), (S("q_lowgong.wav", 1.2, lp=1000), .5, .25))
# ---- 刀：宽、重 ----
J["bl_slash"] = lambda: S("slice.wav", .32)
J["bl_heavy"] = lambda: mix((S("w_59992_swordswing.flac", .45, semis=-5), 1, 0), (S("k_punch_heavy_000.ogg", .3), .6, .08))
J["bl_spin"] = lambda: S("w_60028_double.flac", .65, semis=-3)
J["bl_wheel"] = lambda: S("w_60021_triple.flac", .75, semis=-3)
J["bl_proj"] = lambda: S("w_60018_windswing31.flac", .5, semis=-3)
J["bl_blood"] = lambda: S("slashattack.flac", .42)
J["bl_fire"] = lambda: mix((S("w_60007_swipe.flac", .5, semis=-5), 1, 0), (S("k_wood_000.ogg"), .3, .12), (S("k_wood_002.ogg"), .25, .22))
J["bl_quake"] = lambda: mix((S("rock.wav", .75), 1, 0), (S("q_deepsub.wav", .75, lp=500), .6, 0))
J["bl_dragon"] = lambda: mix((S("q_cinboom.wav", 1.1), 1, 0), (S("q_lowgong.wav", 1.1, lp=900), .5, .1))
# ---- 拳掌：闷、低频 ----
J["fist_punch"] = lambda: S("p_16.wav", .27)
J["fist_finger"] = lambda: mix((S("w_59988_swosh01.flac", .16, semis=4), 1, 0), (S("k_tin_001.ogg"), .3, .08))
J["fist_vajra"] = lambda: mix((S("k_metal_001.ogg"), .7, 0), (S("k_punch_heavy_002.ogg", semis=-2), 1, 0))
J["fist_quake"] = lambda: mix((S("rock.wav", .6), 1, .02), (S("k_punch_heavy_000.ogg", semis=-3), 1, 0))
J["palm_soft"] = lambda: S("w_60027_slow40.flac", .38, lp=4500)
J["palm_wave"] = lambda: mix((S("w_60026_swoosh.flac", .45, semis=-2), 1, 0), (S("q_punchyboom.wav", .3, lp=700), .4, .04))
J["palm_multi"] = lambda: S("w_60019_quad.flac", .85)
J["palm_dragon"] = lambda: mix((S("q_cinboom.wav", .95), 1, 0), (S("w_60028_double.flac", .6, semis=-4), .6, 0))
# ---- 系统 ----
J["level_up"] = lambda: mix((S("q_levelbells.wav", .9), 1, 0), (S("guzheng.wav", .7), .7, 0))
J["pickup_exp"] = lambda: S("chime.wav", .12, semis=5)
J["dash_qg"] = lambda: S("w_60030_aircut.flac", .28)
J["burst_break"] = lambda: mix((S("q_punchyboom.wav", .6), 1, 0), (S("q_deepsub.wav", .6, lp=400), .5, 0))
J["burst_ult"] = lambda: mix((S("gong.wav", 1.0), 1, 0), (S("q_cinboom.wav", 1.0), .6, 0))
J["realm_ying"] = lambda: S("chime.wav", .75, semis=-3)
J["boss_warn"] = lambda: S("q_lowgong.wav", 1.0)
J["boss_cleave"] = lambda: mix((S("q_trailerhit.wav", .6), 1, 0), (S("q_deepsub.wav", .6, lp=300), .5, 0))
J["enemy_ranged"] = lambda: S("arrow.wav", .6)
J["ui_click"] = lambda: S("ui_click1.wav", .1)
J["ui_confirm"] = lambda: S("ui_click2.wav", .12, semis=3)
J["ui_back"] = lambda: S("ui_click2.wav", .12, semis=-4)
J["chest_open"] = lambda: S("chest.mp3", 1.3)
J["gear_upgrade"] = lambda: mix((S("anvil.wav", .5), 1, 0), (S("q_chime.wav", .8), .6, .15))
J["gear_fail"] = lambda: mix((S("k_soft_000.ogg"), 1, 0), (S("q_deepsub.wav", .45, lp=350, semis=-2), .6, 0))
J["win_jingle"] = lambda: S("q_win.wav", 3.0, hp=80)
J["lose_jingle"] = lambda: mix((S("q_lowgong.wav", 2.2, semis=-4, lp=1500), 1, 0), (S("q_deepsub.wav", 2.2, lp=300), .5, 0))

# ---- 变体（_1/_2/_3，随机轮换）：命中 / 受击 ----
V = {}
V["hit_sword"] = [lambda: S("k_tin_000.ogg", .14, hp=1000), lambda: S("k_tin_001.ogg", .14, hp=1000), lambda: S("k_tin_002.ogg", .14, hp=1000)]
V["hit_blade"] = [lambda: S("slice.wav", .16, semis=-2),
                  lambda: mix((S("k_metal_000.ogg", .15), 1, 0), (S("k_punch_med_000.ogg", .15), .7, 0)),
                  lambda: mix((S("k_metal_002.ogg", .15), 1, 0), (S("k_soft_000.ogg", .15), .8, 0))]
V["hit_fist"] = [lambda: S("p_05.wav", .2), lambda: S("p_07.wav", .2), lambda: S("k_punch_med_001.ogg", .18)]
V["hit_crit"] = [lambda: mix((S("k_metal_003.ogg"), 1, 0), (S("chime.wav", .25, semis=7), .5, .01)),
                 lambda: mix((S("k_metal_001.ogg"), 1, 0), (S("chime.wav", .25, semis=9), .5, .01)),
                 lambda: mix((S("swordclash.wav", .3), 1, 0), (S("k_punch_heavy_001.ogg", .2), .6, 0))]
V["enemy_death"] = [lambda: S("fallbody.mp3", .3), lambda: S("bodythud.wav", .3, lp=3000), lambda: S("k_soft_001.ogg", .3)]
V["player_hurt"] = [lambda: mix((S("k_soft_000.ogg", .2), 1, 0), (S("q_punchyboom.wav", .2, lp=500), .6, 0)),
                    lambda: S("p_07.wav", .2, semis=-4), lambda: S("k_soft_002.ogg", .2, semis=-2)]
V["armor_break"] = [lambda: S("k_metal_001.ogg"), lambda: S("k_metal_003.ogg", semis=-3), lambda: mix((S("k_metal_004.ogg"), 1, 0), (S("k_wood_001.ogg"), .6, .02))]
V["block_shield"] = [lambda: S("swordclash.wav", .3), lambda: S("clang.wav", .3), lambda: mix((S("k_metal_000.ogg"), 1, 0), (S("k_tin_000.ogg", semis=-4), .6, 0))]
V["footstep"] = [lambda: S("foot0.ogg"), lambda: S("foot1.ogg"), lambda: S("foot2.ogg"), lambda: S("foot3.ogg")]
V["card_pick"] = [lambda: S("flip2.ogg"), lambda: S("flip3.ogg")]
V["vuln_break"] = [lambda: S("k_wood_000.ogg", .2, semis=2), lambda: S("k_wood_001.ogg", .2, semis=2), lambda: S("k_wood_002.ogg", .2, semis=2)]

if __name__ == "__main__":
    for k, f in J.items():
        save(k, f())
    for k, fs in V.items():
        for i, f in enumerate(fs, 1):
            save(f"{k}_{i}", f())
        # 无编号版本留作兜底（第一个变体）
        save(k, fs[0]())
    print("ok", len(J), "+", sum(len(v) for v in V.values()))
