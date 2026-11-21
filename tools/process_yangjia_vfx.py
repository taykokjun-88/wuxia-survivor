#!/usr/bin/env python3
"""杨家将 + 招式差异化新特效：assets/source/yangjiajiang/vfx_*.webp → assets/vfx/<id>.png 并登记 vfx.json。
Gemini 的条带里每帧还带一块略深的洋红「方格」，先统一成纯洋红底再交给 process_vfx_alpha.py。
用法：python3 tools/process_yangjia_vfx.py"""
import pathlib
import subprocess
import sys
import tempfile

import numpy as np
from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "assets" / "source" / "yangjiajiang"

# (源文件, 特效 id, 帧数, fps, 循环, world_size, forward)
PLAN = [
    ("vfx_12hZ_spear_beam", "fx_yangjia_thrust", 4, 16, False, 400, 0.0),
    ("vfx_1Ltw_cyan_spear_burst", "fx_wuming_thrust", 4, 16, False, 300, 0.0),
    ("vfx_1oWa_armor_shatter", "fx_wuming_hit", 4, 14, False, 200, 0.0),
    ("vfx_1rXl_ice_star", "fx_meihua_spear", 4, 14, False, 220, 0.0),
    ("vfx_1m93_white_horse", "fx_baima_dash", 4, 14, False, 300, 0.0),
    ("vfx_1AM_gold_burst_ring", "fx_spear_tip", 4, 20, False, 120, 0.0),
    ("vfx_1HW7_gold_dragon_trail", "fx_youlong_dash", 4, 14, False, 420, 0.0),
    ("vfx_15li_gold_crescent", "fx_staff_sweep", 4, 16, False, 260, 0.2),
    ("vfx_1IH9_tan_rings", "fx_staff_wide", 4, 14, False, 560, 0.0),
    ("vfx_1Af9_gold_dragon_ring", "fx_panlong", 4, 10, True, 300, 0.0),
    ("vfx_1NW2_green_bamboo", "fx_dagou", 4, 14, False, 200, 0.0),
    ("vfx_1tl1_whirl_silver_cyan", "fx_fengmo", 4, 14, True, 260, 0.0),
    ("vfx_1XAX_ground_crack_red", "fx_xiangmo", 4, 12, False, 300, 0.0),
    ("vfx_1Z0s_crescent_spark", "fx_block_swing", 4, 18, False, 170, 0.0),
    ("vfx_15RN_white_ring", "fx_block_wave", 4, 14, False, 220, 0.0),
    ("vfx_1AO_brown_vortex", "aura_staff_charge", 4, 10, True, 180, 0.0),
    ("vfx_12q5_red_x_burst", "fx_blade_bleed_pop", 4, 20, False, 200, 0.0),
    ("vfx_1VcW_ink_ring", "fist_whirl_ring", 4, 16, False, 260, 0.0),
    ("vfx_1pfe_taiji_burst", "sw_taiji_reflect", 4, 14, False, 160, 0.0),
    ("vfx_1csT_taiji_orb", "proj_taiji_reflect", 4, 14, True, 90, 0.0),
    ("vfx_1uWS_pine_wave", "sw_qingsong_wave", 4, 20, False, 260, 0.2),
]


def clean(path):
    """洋红底（含每帧略深的方格 / 渐变）按色相判断：红蓝都明显高于绿且红蓝接近 = 背景，统一成纯洋红；
    半透明边缘里混进的洋红（去色溢）压低红 / 蓝，避免特效边缘一圈粉紫色"""
    a = np.array(Image.open(path).convert("RGB")).astype(float)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    m = np.minimum(r, b) - g
    bg = (m > 75) & (np.abs(r - b) < 90)
    soft = (m > 25) & ~bg
    k = np.where(soft, (m - 15) * 0.9, 0.0)
    a[..., 0] = np.clip(r - k, 0, 255)
    a[..., 2] = np.clip(b - k, 0, 255)
    a[bg] = (255, 0, 255)
    return Image.fromarray(a.astype(np.uint8))


def main():
    tmp = pathlib.Path(tempfile.mkdtemp())
    for src, fx, frames, fps, loop, ws, fwd in PLAN:
        p = tmp / f"{fx}.png"
        clean(SRC / f"{src}.webp").save(p)
        cmd = [sys.executable, str(ROOT / "tools" / "process_vfx_alpha.py"), str(p), fx, "--frames", str(frames), "--cell", "192", "--fps", str(fps), "--world-size", str(ws)]
        if loop:
            cmd.append("--loop")
        if fwd:
            cmd += ["--forward", str(fwd)]
        r = subprocess.run(cmd, capture_output=True, text=True)
        print(fx, (r.stdout.strip().splitlines() or r.stderr.strip().splitlines() or ["?"])[-1])


if __name__ == "__main__":
    main()
