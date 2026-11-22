#!/usr/bin/env python3
"""装备图标（第 6 版，256×256 透明底带边框）→ 64×64：
武器 assets/icons/<fist|sword|spear>_weapons/w1..w10.png；防具 / 配饰 assets/icons/gear/<职业>_<coat|pants|boots|charm>.png。
用法：python3 tools/process_gear_icons.py"""
import pathlib

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "assets" / "source" / "gear_v6"
ICONS = ROOT / "assets" / "icons"


def to64(path):
    im = Image.open(path).convert("RGBA")
    bb = im.getchannel("A").point(lambda v: 255 if v > 40 else 0).getbbox()
    im = im.crop(bb)
    s = max(im.size)
    sq = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    sq.paste(im, ((s - im.width) // 2, (s - im.height) // 2))
    return sq.resize((64, 64), Image.LANCZOS)


def main():
    for sch in ("fist", "sword"):
        d = ICONS / f"{sch}_weapons"
        d.mkdir(parents=True, exist_ok=True)
        for i in range(1, 11):
            to64(SRC / f"{sch}_w{i}.png").save(d / f"w{i}.png")
    to64(SRC / "spear_w10.png").save(ICONS / "spear_weapons" / "w10.png")
    for sch in ("fist", "sword", "blade", "spear"):
        for slot in ("coat", "pants", "boots", "charm"):
            to64(SRC / f"{sch}_{slot}.png").save(ICONS / "gear" / f"{sch}_{slot}.png")
    print("done")


if __name__ == "__main__":
    main()
