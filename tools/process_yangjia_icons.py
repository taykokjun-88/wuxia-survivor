#!/usr/bin/env python3
"""杨家将图标（第 4 版，256×256 透明底带边框）→ 64×64：招式图标 assets/icons/skills/<id>.png，武器 assets/icons/spear_weapons/w1..w10.png。
武器图标边缘有一圈洋红 / 紫色描边（抠图残留）：按色相去掉。用法：python3 tools/process_yangjia_icons.py"""
import pathlib

import numpy as np
from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "assets" / "source" / "yangjiajiang_v4" / "icons"
SKILLS = ["yangjia_spear", "meihua_spear", "baima_spear", "wuming_spear", "shaolin_staff", "panlong_staff", "dagou_staff", "fengmo_staff", "xiangmo_staff"]


def defringe(im):
    a = np.array(im.convert("RGBA")).astype(float)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    purple = ((r - g) > 35) & ((b - g) > 35) & (np.abs(r - b) < 110) & (b > 90)   # 洋红 / 紫：红蓝都高于绿
    a[purple, 3] = 0
    return Image.fromarray(a.astype(np.uint8))


def to64(im):
    bb = im.getchannel("A").point(lambda v: 255 if v > 40 else 0).getbbox()
    im = im.crop(bb)
    s = max(im.size)
    sq = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    sq.paste(im, ((s - im.width) // 2, (s - im.height) // 2))
    return sq.resize((64, 64), Image.LANCZOS)


def main():
    out_w = ROOT / "assets" / "icons" / "spear_weapons"
    out_w.mkdir(parents=True, exist_ok=True)
    for sid in SKILLS:
        to64(defringe(Image.open(SRC / f"{sid}.png"))).save(ROOT / "assets" / "icons" / "skills" / f"{sid}.png")
    for i in range(1, 11):
        to64(defringe(Image.open(SRC / f"w{i}.png"))).save(out_w / f"w{i}.png")
    print("done")


if __name__ == "__main__":
    main()
