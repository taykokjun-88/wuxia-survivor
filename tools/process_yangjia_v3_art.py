#!/usr/bin/env python3
"""第三版立绘类素材（二次元）：创建立绘 / 选人全身像 / 胜负海报 → 游戏用图。
用法：python3 tools/process_yangjia_v3_art.py"""
import pathlib

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
V3 = ROOT / "assets" / "source" / "yangjiajiang_v3"
V8 = ROOT / "assets" / "source" / "yangjiajiang_v8"     # 第八版：武者成年二次元重画（有就优先）


V10 = ROOT / "assets" / "source" / "proportions_v10"    # 第十版：武者 / 杨家将腿长修正
V9 = ROOT / "assets" / "source" / "charselect_v9"        # 第九版：四职业选人全身像（与封面同画风）


def pick(name):
    for d in (V10, V9, V8):
        if (d / name).exists():
            return d / name
    return V3 / name


def main():
    for k in ["fist", "sword", "blade", "spear"]:               # 创建角色立绘 1200×1600，原样使用
        Image.open(pick(f"{k}_hero.jpg")).convert("RGB").save(ROOT / "assets" / "portraits" / f"{k}_hero.jpg", quality=93)
    for k in ["fist", "sword", "blade", "spear"]:               # 选人全身像：透明底，裁边后放进 512×640
        cut = Image.open(pick(f"charselect_{k}.png")).convert("RGBA")
        bb = cut.getchannel("A").point(lambda v: 255 if v > 128 else 0).getbbox()
        cut = cut.crop(bb)
        sc = min(500 / cut.width, 590 / cut.height)
        cut = cut.resize((round(cut.width * sc), round(cut.height * sc)), Image.LANCZOS)
        canvas = Image.new("RGBA", (512, 640), (0, 0, 0, 0))
        canvas.paste(cut, ((512 - cut.width) // 2, 640 - cut.height - 20), cut)
        canvas.save(ROOT / "assets" / "char_select" / f"{k}.png")
    for k in ["victory", "defeat"]:                             # 胜负海报
        Image.open(V3 / f"{k}_spear.jpg").convert("RGB").resize((1376, 768), Image.LANCZOS).save(ROOT / "assets" / "ui" / "screens" / f"{k}_spear.jpg", quality=90)
    print("done")


if __name__ == "__main__":
    main()
