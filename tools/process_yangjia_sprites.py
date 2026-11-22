#!/usr/bin/env python3
"""杨家将局内精灵：把 assets/source/yangjiajiang/sprite_*.webp 整理成 4 帧条带，再交给 tools/process_sprites.py 处理。
用法：python3 tools/process_yangjia_sprites.py"""
import json
import pathlib
import subprocess
import sys

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "assets" / "source" / "yangjiajiang_v3"   # 第三版：像素 Q 版，每个动作 1 行 4 帧
OUT = ROOT / "assets" / "sprites" / "spear"
WORK = OUT / "source"
MAGENTA = (255, 0, 255)


def strip_from(name, top_row_only=False):
    im = Image.open(SRC / f"spear_{name}.png").convert("RGB")
    if top_row_only:                              # 8 帧（两行）→ 取上面一行 4 帧，放进和其它条带一样高的洋红画布里（保持缩放一致）
        row = im.crop((0, 0, im.width, im.height // 2))
        canvas = Image.new("RGB", im.size, MAGENTA)
        canvas.paste(row, (0, (im.height - row.height) // 2))
        im = canvas
    return im


def run(*args):
    r = subprocess.run([sys.executable, str(ROOT / "tools" / "process_sprites.py"), *map(str, args)], capture_output=True, text=True)
    print(r.stdout.strip() or r.stderr.strip())


# 第三版各动作图里人物大小不一（Gemini 没做到同比例）：量出「发髻顶 → 脚底」的本体像素高度，统一缩放到 BODY_PX
BODY = {"idle": 427, "walk": 330, "thrust": 293, "slash": 317, "block": 300, "dash": 280, "ult": 375, "hurt": 376, "death": 313}
BODY_PX = 54


def main():
    WORK.mkdir(parents=True, exist_ok=True)
    plan = [  # 动画名, 源图, 是否只取上面一行, fps, 是否只播一次
        ("idle", "idle", False, 4, False),
        ("walk", "walk", False, 9, False),
        ("thrust", "thrust", False, 14, True),
        ("slash", "slash", False, 14, True),
        ("block", "block", False, 12, True),
        ("dash", "dash", False, 14, True),
        ("ult", "ult", False, 8, True),
        ("hurt", "hurt", False, 10, True),
        ("death", "death", False, 6, True),
    ]
    for name, src, top, fps, once in plan:
        strip_from(src, top).save(WORK / f"{name}.jpg", quality=95)
    for f in ["palette.json", "anim.json", "scale.json"]:
        (OUT / f).unlink(missing_ok=True)
    run("palette", *[WORK / f"{p[0]}.jpg" for p in plan], "--colors", 28, "--out", OUT)
    for i, (name, src, top, fps, once) in enumerate(plan):
        args = ["strip", WORK / f"{name}.jpg", name, "--frames", 4, "--fps", fps, "--cell", 128, "--scale", BODY_PX / BODY[name], "--out", OUT]
        if once:
            args.append("--once")
        if name == "dash":
            args += ["--align", "keep"]
        run(*args)


if __name__ == "__main__":
    main()
