#!/usr/bin/env python3
"""合成一套国风战斗音效（assets/sfx/<id>.wav，16-bit 单声道 44.1kHz）。游戏里 Sfx 会优先加载这些文件。
设计思路（贴合国风配乐 + 招式质感）：
  - 剑：高频、细、带「铮」的金属泛音；刀：更宽更重，低频体感 + 金属；拳：闷、低频冲击；掌：气流 + 内劲低鸣。
  - 拨弦（Karplus-Strong，像古筝）用于拾取 / 升级；锣 / 鼓用于 Boss、爆发、境界。
用法：python3 tools/make_sfx.py
"""
import pathlib
import wave

import numpy as np
from scipy import signal

SR = 44100
OUT = pathlib.Path(__file__).resolve().parent.parent / "assets" / "sfx"
RNG = np.random.default_rng(20261120)


def t_(d):
    return np.arange(int(d * SR)) / SR


def env(n, a=0.002, d=0.1, curve=3.0):
    """起音 a 秒，随后指数衰减（d 为衰减时长）。"""
    t = np.arange(n) / SR
    e = np.where(t < a, t / max(a, 1e-6), np.exp(-(t - a) / max(d, 1e-4) * curve))
    return e


def noise(d):
    return RNG.standard_normal(int(d * SR))


def bp(x, lo, hi, order=2):
    lo = max(lo, 20.0); hi = min(hi, SR / 2 - 100)
    sos = signal.butter(order, [lo, hi], btype="band", fs=SR, output="sos")
    return signal.sosfilt(sos, x)


def lp(x, f, order=2):
    return signal.sosfilt(signal.butter(order, min(f, SR / 2 - 100), btype="low", fs=SR, output="sos"), x)


def hp(x, f, order=2):
    return signal.sosfilt(signal.butter(order, f, btype="high", fs=SR, output="sos"), x)


def sweep_noise(d, f0, f1, q=0.45, curve=None):
    """中心频率随时间滑动的带通噪声（风声 / 挥刀声）。"""
    n = int(d * SR)
    x = noise(d)
    out = np.zeros(n)
    chunk = 256
    zi = None
    for i in range(0, n, chunk):
        u = i / n
        fc = f0 + (f1 - f0) * (curve(u) if curve else u)
        lo, hi = fc * (1 - q), fc * (1 + q)
        sos = signal.butter(2, [max(lo, 30), min(hi, SR / 2 - 200)], btype="band", fs=SR, output="sos")
        if zi is None:
            zi = np.zeros((sos.shape[0], 2))
        seg, zi = signal.sosfilt(sos, x[i:i + chunk], zi=zi)
        out[i:i + chunk] = seg[: n - i]
    return out / (np.max(np.abs(out)) + 1e-9)


def tone(d, f0, f1=None, partials=((1, 1.0),), dec=0.15, a=0.002, curve=3.0):
    t = t_(d)
    f1 = f0 if f1 is None else f1
    f = f0 + (f1 - f0) * np.clip(t / d, 0, 1) ** 0.6
    ph = 2 * np.pi * np.cumsum(f) / SR
    y = np.zeros_like(t)
    for k, g in partials:
        y += g * np.sin(k * ph)
    return y * env(len(t), a, dec, curve)


def metal(d, f, dec=0.25, partials=(1, 2.76, 5.4, 8.9), gains=(1, 0.6, 0.4, 0.25)):
    """金属「铮」：非谐泛音。"""
    t = t_(d)
    y = np.zeros_like(t)
    for r, g in zip(partials, gains):
        y += g * np.sin(2 * np.pi * f * r * t) * np.exp(-t / (dec / (1 + 0.5 * r)) * 3.0)
    return y


def pluck(f, d=0.6, damp=0.996, bright=0.5):
    """Karplus-Strong 拨弦（古筝 / 琵琶味）。"""
    n = int(d * SR)
    p = int(SR / f)
    buf = RNG.uniform(-1, 1, p) * bright + lp(RNG.uniform(-1, 1, p), 3000) * (1 - bright)
    out = np.zeros(n)
    for i in range(n):
        out[i] = buf[i % p]
        buf[i % p] = damp * 0.5 * (buf[i % p] + buf[(i + 1) % p])
    return out


def gong(d, f, dec=1.2):
    t = t_(d)
    ratios = [1.0, 1.47, 2.09, 2.57, 3.02, 3.9]
    gains = [1.0, 0.7, 0.55, 0.45, 0.3, 0.2]
    y = np.zeros_like(t)
    for r, g in zip(ratios, gains):
        y += g * np.sin(2 * np.pi * f * r * t + RNG.uniform(0, 6.28)) * np.exp(-t / (dec / (0.6 + 0.4 * r)) * 2.5)
    return y * (1 - np.exp(-t / 0.004))


def drum(d, f0=140, f1=48, click=0.35, dec=0.18):
    y = tone(d, f0, f1, dec=dec, a=0.001, curve=3.5)
    y += click * lp(noise(d), 2500) * env(int(d * SR), 0.0005, 0.02)
    return y


def reverb(x, amt=0.25, delays=(0.011, 0.023, 0.037, 0.053), decay=0.5):
    out = np.copy(x)
    pad = int(max(delays) * SR) + 1
    out = np.concatenate([out, np.zeros(pad)])
    for i, dl in enumerate(delays):
        k = int(dl * SR)
        out[k:k + len(x)] += x * amt * (decay ** (i + 1))
    return out


def fit(x, peak=0.8, fade=0.004):
    x = x - np.mean(x)
    x = x / (np.max(np.abs(x)) + 1e-9) * peak
    n = int(fade * SR)
    if len(x) > 2 * n:
        x[-n:] *= np.linspace(1, 0, n)
        x[:8] *= np.linspace(0, 1, 8)
    return x


def mix(*parts, delay=None):
    n = max(len(p) + int((delay[i] if delay else 0) * SR) for i, p in enumerate(parts))
    y = np.zeros(n)
    for i, p in enumerate(parts):
        o = int((delay[i] if delay else 0) * SR)
        y[o:o + len(p)] += p
    return y


def save(name, x, peak=0.8):
    x = fit(x, peak)
    pcm = (np.clip(x, -1, 1) * 32767).astype("<i2")
    OUT.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUT / f"{name}.wav"), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(pcm.tobytes())


S = {}   # name -> (array, peak)


def add(name, x, peak=0.8):
    S[name] = (x, peak)


# ---------------------------------------------------------------- 剑：细、亮、带「铮」
d = 0.20
add("sw_slash", mix(sweep_noise(d, 2600, 7200, 0.5) * env(int(d * SR), 0.006, 0.10, 3.0) * 0.9,
                    metal(0.35, 3100, 0.30, (1, 2.4, 4.1), (0.35, 0.25, 0.15))), 0.55)
d = 0.12
add("sw_thrust", mix(sweep_noise(d, 3500, 9000, 0.4) * env(int(d * SR), 0.003, 0.05, 3.0),
                     metal(0.30, 4200, 0.25, (1, 2.4), (0.4, 0.2)), tone(0.05, 900, 400, dec=0.03) * 0.3), 0.55)
d = 0.28
add("sw_proj", mix(sweep_noise(d, 1800, 5200, 0.35) * env(int(d * SR), 0.01, 0.16, 2.5) * 0.8,
                   tone(d, 1500, 3800, partials=((1, 1.0), (2, 0.25)), dec=0.18) * 0.35), 0.5)
d = 0.50
add("sw_heavy", mix(lp(sweep_noise(0.30, 500, 2400, 0.6), 4000) * env(int(0.30 * SR), 0.01, 0.2, 2.5),
                    drum(0.35, 110, 40, 0.5, 0.2) * 1.1,
                    metal(0.55, 1500, 0.5, (1, 2.76, 5.4), (0.5, 0.35, 0.2)) * 0.5, delay=[0, 0.05, 0.04]), 0.8)
add("sw_ring", mix(metal(0.7, 880, 0.7, (1, 2.0, 3.0, 4.2), (0.7, 0.45, 0.3, 0.2)),
                   sweep_noise(0.25, 1500, 3000, 0.5) * env(int(0.25 * SR), 0.02, 0.15) * 0.4), 0.55)
add("sw_multi", mix(*[mix(sweep_noise(0.14, 2400 + 500 * k, 6500, 0.5) * env(int(0.14 * SR), 0.004, 0.07, 3.0),
                          metal(0.2, 3600 + 300 * k, 0.2, (1, 2.4), (0.3, 0.2))) for k in range(4)],
                    delay=[0, 0.04, 0.08, 0.12]), 0.6)
add("sw_blink", mix(sweep_noise(0.16, 700, 5000, 0.5) * env(int(0.16 * SR), 0.003, 0.08, 3.0),
                    tone(0.10, 220, 70, dec=0.07, a=0.001) * 0.7,
                    metal(0.25, 3800, 0.2, (1, 2.4), (0.45, 0.25)), delay=[0, 0.09, 0.1]), 0.65)
add("sw_snake", mix(hp(sweep_noise(0.32, 5000, 7500, 0.25), 3500) * env(int(0.32 * SR), 0.04, 0.18) * 0.7,
                    tone(0.25, 2200, 1500, dec=0.15) * 0.18), 0.4)
add("sw_yitian", mix(drum(0.5, 90, 35, 0.4, 0.3), metal(1.0, 660, 1.0, (1, 2.0, 3.0, 5.0), (0.8, 0.55, 0.4, 0.25)) * 0.6,
                     sweep_noise(0.35, 800, 4000, 0.6) * env(int(0.35 * SR), 0.01, 0.2) * 0.6), 0.85)
add("dugu_flash", mix(sweep_noise(0.09, 4000, 10000, 0.4) * env(int(0.09 * SR), 0.002, 0.04, 3.0),
                      metal(0.16, 5200, 0.12, (1, 2.4), (0.35, 0.2))), 0.45)
add("dugu_awaken", mix(gong(1.4, 220, 1.4) * 0.8, metal(1.2, 1100, 1.0, (1, 2.0, 3.0, 4.0), (0.6, 0.4, 0.3, 0.2)) * 0.5,
                       sweep_noise(0.6, 300, 6000, 0.6) * env(int(0.6 * SR), 0.2, 0.3) * 0.5), 0.85)

# ---------------------------------------------------------------- 刀：宽、重、有分量
add("bl_slash", mix(lp(sweep_noise(0.22, 900, 4200, 0.55), 6000) * env(int(0.22 * SR), 0.008, 0.12, 2.8),
                    tone(0.12, 160, 70, dec=0.08, a=0.001) * 0.7,
                    metal(0.3, 2000, 0.25, (1, 2.76, 5.4), (0.3, 0.2, 0.12)), delay=[0, 0.04, 0.03]), 0.6)
add("bl_heavy", mix(lp(sweep_noise(0.30, 400, 2000, 0.65), 4500) * env(int(0.30 * SR), 0.01, 0.2, 2.5) * 1.1,
                    drum(0.4, 100, 36, 0.6, 0.25) * 1.2,
                    metal(0.5, 1200, 0.45, (1, 2.76, 5.4), (0.5, 0.35, 0.2)) * 0.45, delay=[0, 0.08, 0.06]), 0.85)
add("bl_proj", mix(sweep_noise(0.30, 1200, 3800, 0.45) * env(int(0.30 * SR), 0.012, 0.18, 2.6) * 0.85,
                   tone(0.28, 700, 1600, partials=((1, 1.0), (2, 0.3)), dec=0.2) * 0.3), 0.55)
add("bl_fire", mix(lp(sweep_noise(0.45, 600, 2200, 0.7), 5000) * env(int(0.45 * SR), 0.02, 0.3, 2.2),
                   hp(noise(0.5), 2500) * np.where(RNG.random(int(0.5 * SR)) > 0.985, 1.0, 0.0) * 0.8 * env(int(0.5 * SR), 0.02, 0.35),
                   drum(0.25, 80, 40, 0.3, 0.15) * 0.8), 0.7)
add("bl_blood", mix(lp(sweep_noise(0.2, 800, 3200, 0.55), 4500) * env(int(0.2 * SR), 0.006, 0.1, 3.0),
                    tone(0.16, 130, 55, dec=0.1, a=0.001) * 0.9,
                    bp(noise(0.12), 300, 1200) * env(int(0.12 * SR), 0.002, 0.06) * 0.5, delay=[0, 0.03, 0.05]), 0.65)
add("bl_wheel", mix(sweep_noise(0.5, 1000, 2600, 0.4, curve=lambda u: 0.5 + 0.5 * np.sin(u * 14)) * env(int(0.5 * SR), 0.02, 0.35, 2.0) * 0.8,
                    metal(0.6, 1760, 0.5, (1, 2.0, 3.0), (0.4, 0.3, 0.2)) * 0.5), 0.6)
add("bl_quake", mix(drum(0.5, 70, 28, 0.5, 0.35) * 1.3, lp(noise(0.6), 800) * env(int(0.6 * SR), 0.01, 0.4) * 0.8,
                    metal(0.4, 400, 0.3, (1, 2.3), (0.4, 0.2)) * 0.4), 0.9)
add("bl_spin", mix(sweep_noise(0.55, 1500, 3200, 0.45, curve=lambda u: 0.5 + 0.5 * np.sin(u * 22)) * env(int(0.55 * SR), 0.03, 0.4, 2.0) * 0.8,
                   metal(0.3, 2600, 0.2, (1, 2.4), (0.35, 0.2)), delay=[0, 0.15]), 0.55)
add("bl_dragon", mix(gong(1.6, 110, 1.6) * 1.0, drum(0.6, 85, 30, 0.7, 0.4) * 1.3,
                     sweep_noise(0.9, 200, 3500, 0.7, curve=lambda u: u ** 0.5) * env(int(0.9 * SR), 0.05, 0.6, 2.0) * 0.7,
                     metal(1.2, 700, 1.0, (1, 2.0, 3.0), (0.5, 0.35, 0.2)) * 0.4), 0.95)

# ---------------------------------------------------------------- 拳 / 掌：闷、低、气浪
add("fist_punch", mix(drum(0.16, 150, 52, 0.55, 0.09) * 1.2, lp(noise(0.06), 1800) * env(int(0.06 * SR), 0.001, 0.03) * 0.6), 0.75)
add("fist_finger", mix(pluck(1320, 0.25, 0.992) * 0.8, tone(0.04, 3000, 1800, dec=0.02, a=0.0005) * 0.5,
                       sweep_noise(0.1, 3000, 6000, 0.4) * env(int(0.1 * SR), 0.003, 0.05) * 0.4), 0.6)
add("fist_quake", mix(drum(0.5, 80, 30, 0.7, 0.3) * 1.4, lp(noise(0.4), 600) * env(int(0.4 * SR), 0.005, 0.25) * 0.7), 0.9)
add("fist_vajra", mix(gong(1.0, 150, 1.0) * 0.8, drum(0.4, 100, 38, 0.6, 0.25) * 1.2), 0.9)
add("palm_wave", mix(lp(sweep_noise(0.32, 300, 1500, 0.7), 3000) * env(int(0.32 * SR), 0.03, 0.22, 2.2) * 0.9,
                     tone(0.22, 120, 70, dec=0.15, a=0.005) * 0.6), 0.6)
add("palm_multi", mix(*[mix(lp(sweep_noise(0.2, 350, 1400, 0.7), 3000) * env(int(0.2 * SR), 0.01, 0.12, 2.6) * 0.8,
                            tone(0.1, 130, 80, dec=0.06) * 0.5) for _ in range(3)], delay=[0, 0.05, 0.1]), 0.6)
add("palm_dragon", mix(lp(sweep_noise(0.5, 150, 1100, 0.8), 2500) * env(int(0.5 * SR), 0.04, 0.35, 2.0),
                       tone(0.45, 90, 55, partials=((1, 1.0), (2, 0.4), (3, 0.2)), dec=0.3, a=0.01),
                       drum(0.3, 100, 40, 0.4, 0.2) * 0.8, delay=[0, 0, 0.1]), 0.85)
add("palm_soft", mix(gong(0.9, 330, 0.9) * 0.6, lp(sweep_noise(0.3, 500, 1800, 0.6), 3500) * env(int(0.3 * SR), 0.03, 0.2) * 0.5), 0.55)

# ---------------------------------------------------------------- 命中 / 受击 / 通用
add("hit_fist", mix(drum(0.12, 170, 55, 0.5, 0.07) * 1.1, lp(noise(0.05), 2200) * env(int(0.05 * SR), 0.001, 0.025) * 0.6), 0.55)
add("hit_sword", mix(hp(noise(0.06), 1800) * env(int(0.06 * SR), 0.0008, 0.025) * 0.8, metal(0.2, 2700, 0.15, (1, 2.4, 4.1), (0.4, 0.25, 0.15)),
                     tone(0.05, 300, 120, dec=0.03) * 0.5), 0.5)
add("hit_blade", mix(hp(noise(0.07), 1200) * env(int(0.07 * SR), 0.001, 0.03) * 0.8, drum(0.1, 190, 70, 0.3, 0.05) * 0.9,
                     metal(0.22, 1900, 0.18, (1, 2.76, 5.4), (0.4, 0.25, 0.15))), 0.55)
add("hit_crit", mix(drum(0.2, 150, 50, 0.6, 0.1) * 1.1, metal(0.5, 2200, 0.4, (1, 2.4, 4.1, 6.0), (0.6, 0.4, 0.3, 0.2)),
                    hp(noise(0.08), 1500) * env(int(0.08 * SR), 0.001, 0.03) * 0.8), 0.75)
add("vuln_break", mix(metal(0.45, 1500, 0.4, (1, 2.0, 3.0), (0.6, 0.4, 0.3)), tone(0.08, 500, 250, dec=0.05) * 0.6), 0.6)
add("block_shield", mix(metal(0.5, 900, 0.45, (1, 2.76, 5.4, 8.9), (0.8, 0.5, 0.35, 0.2)), drum(0.1, 220, 100, 0.5, 0.05) * 0.6), 0.7)
add("player_hurt", mix(drum(0.3, 110, 40, 0.5, 0.15) * 1.2, lp(noise(0.25), 700) * env(int(0.25 * SR), 0.003, 0.15) * 0.7,
                       tone(0.18, 200, 110, partials=((1, 1.0), (1.5, 0.3)), dec=0.1) * 0.3), 0.8)
add("enemy_death", mix(drum(0.22, 100, 38, 0.4, 0.12) * 0.9, lp(noise(0.2), 900) * env(int(0.2 * SR), 0.002, 0.1) * 0.6), 0.5)
add("dash_qg", mix(sweep_noise(0.22, 400, 3500, 0.7, curve=lambda u: u ** 0.6) * env(int(0.22 * SR), 0.02, 0.14, 2.4) * 0.9,
                   tone(0.1, 500, 200, dec=0.06) * 0.2), 0.6)
add("enemy_ranged", mix(sweep_noise(0.2, 1800, 4200, 0.4) * env(int(0.2 * SR), 0.005, 0.1) * 0.8,
                        pluck(660, 0.25, 0.99) * 0.5), 0.5)

# ---------------------------------------------------------------- 拨弦 / 锣 / 鼓：拾取、升级、境界、爆发、Boss
pent = [523.25, 587.33, 659.25, 783.99, 880.0, 1046.5]   # 宫商角徵羽
add("pickup_exp", mix(pluck(1568, 0.22, 0.993) * 0.9, tone(0.05, 3200, 3200, dec=0.03) * 0.15), 0.4)
add("level_up", mix(*[pluck(f, 0.9, 0.9965) for f in (523.25, 659.25, 783.99, 1046.5)], delay=[0, 0.09, 0.18, 0.27]) , 0.7)
add("realm_ying", mix(gong(1.2, 262, 1.2) * 0.7, pluck(523.25, 1.0, 0.997) * 0.8, pluck(784, 1.0, 0.997) * 0.6, delay=[0, 0.05, 0.12]), 0.7)
add("burst_ult", mix(gong(1.6, 130, 1.6), drum(0.6, 90, 32, 0.7, 0.4) * 1.3,
                     sweep_noise(0.7, 200, 5000, 0.7, curve=lambda u: u ** 0.5) * env(int(0.7 * SR), 0.1, 0.4, 2.0) * 0.7), 0.95)
add("burst_break", mix(gong(1.0, 196, 1.0) * 0.9, metal(0.8, 1300, 0.7, (1, 2.76, 5.4), (0.6, 0.4, 0.25)) * 0.7,
                       drum(0.3, 120, 45, 0.6, 0.15) * 1.1), 0.9)
add("boss_warn", mix(drum(0.5, 75, 30, 0.6, 0.35) * 1.4, gong(1.4, 98, 1.4) * 0.8, drum(0.5, 75, 30, 0.6, 0.35) * 1.4,
                     delay=[0, 0, 0.45]), 0.95)
add("armor_break", mix(metal(0.7, 800, 0.6, (1, 2.76, 5.4, 8.9), (0.8, 0.55, 0.4, 0.25)),
                       hp(noise(0.12), 1000) * env(int(0.12 * SR), 0.001, 0.05) * 0.8, drum(0.2, 140, 50, 0.5, 0.1)), 0.85)
add("boss_cleave", mix(drum(0.5, 85, 32, 0.6, 0.3) * 1.3, lp(sweep_noise(0.35, 300, 2200, 0.7), 4500) * env(int(0.35 * SR), 0.01, 0.22, 2.2),
                       metal(0.5, 1100, 0.4, (1, 2.76, 5.4), (0.4, 0.3, 0.2)) * 0.5, delay=[0.04, 0, 0.04]), 0.9)

for name, (arr, peak) in S.items():
    save(name, reverb(arr, 0.18) if name in ("burst_ult", "bl_dragon", "dugu_awaken", "boss_warn", "level_up", "realm_ying", "sw_yitian") else arr, peak)
print(f"已写入 {len(S)} 个音效 → {OUT}")
