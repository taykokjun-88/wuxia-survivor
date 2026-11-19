#!/usr/bin/env python3
"""带边框的图标网格（洋红底）→ 64×64 图标。格子内部的洋红底会被填成深蓝灰，格子外的洋红变透明。

用法：python3 tools/process_framed_icons.py 源图.jpg --cols 5 --rows 2 --ids a,b,c,... --out assets/icons/shi
（id 为 skills/xxx 时会写到 assets/icons/skills；这里用 --out 指定目录，--map id=目录 可单独覆盖）
"""
import argparse
import pathlib

import numpy as np
from PIL import Image
from scipy import ndimage as ndi

ROOT = pathlib.Path(__file__).resolve().parent.parent
MAGENTA = np.array([255, 0, 255])
FILL = np.array([38, 46, 60])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("--cols", type=int, required=True)
    ap.add_argument("--rows", type=int, default=1)
    ap.add_argument("--ids", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--map", default="", help="id=目录 覆盖输出目录，逗号分隔")
    ap.add_argument("--size", type=int, default=64)
    a = ap.parse_args()
    ids = a.ids.split(",")
    over = dict(kv.split("=") for kv in a.map.split(",") if kv)
    rgb = np.asarray(Image.open(a.src).convert("RGB")).astype(int)
    H, W, _ = rgb.shape
    cw, ch = W // a.cols, H // a.rows
    for n, iid in enumerate(ids):
        r, c = divmod(n, a.cols)
        cell = rgb[r * ch:(r + 1) * ch, c * cw:(c + 1) * cw]
        bg = np.abs(cell - MAGENTA).sum(axis=2) < 110              # 纯洋红底（含 JPEG 噪点）
        fg = ~bg
        fg = ndi.binary_opening(fg, iterations=2)
        lab, k = ndi.label(fg)
        sizes = ndi.sum(fg, lab, range(1, k + 1))
        main = lab == (int(np.argmax(sizes)) + 1)                    # 边框 + 内容连成的主体
        filled = ndi.binary_fill_holes(main)
        ys, xs = np.where(filled)
        y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
        out = cell.copy()
        inner = filled & bg
        out[inner] = FILL
        alpha = (filled * 255).astype(np.uint8)
        piece = Image.fromarray(np.dstack([out, alpha]).astype(np.uint8), "RGBA").crop((x0, y0, x1, y1))
        piece = piece.resize((a.size, a.size), Image.LANCZOS)
        d = pathlib.Path(over.get(iid, a.out))
        d = d if d.is_absolute() else ROOT / d
        d.mkdir(parents=True, exist_ok=True)
        piece.save(d / f"{iid}.png")
        print("已写入", d / f"{iid}.png")


if __name__ == "__main__":
    main()
