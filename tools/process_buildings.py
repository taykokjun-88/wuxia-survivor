#!/usr/bin/env python3
"""小镇建筑图（洋红底）→ assets/town/buildings/<id>.png（透明底，裁到内容）+ meta.json（含招牌位置）。

用法：python3 tools/process_buildings.py
源图在 assets/town/buildings/source/town_<名>.jpg；显示宽度和招牌（空白木牌）的位置在下面的表里。
招牌位置 = 源图里木牌中心 (x, y) 与宽度，脚本会换算到输出图的坐标，游戏里在木牌上画店名。
"""
import json
import pathlib

import numpy as np
from PIL import Image
from scipy import ndimage as ndi

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "assets" / "town" / "buildings" / "source"
OUT = ROOT / "assets" / "town" / "buildings"

# id: (源文件, 输出宽度, 木牌中心 x, y, 木牌宽（源图像素）, 木牌是否倾斜)
TABLE = {
    "clerk": ("town_post.jpg", 290, 612, 505, 130),
    "smith": ("town_smith.jpg", 310, 715, 447, 125),
    "herbalist": ("town_herbalist.jpg", 300, 470, 340, 250),
    "master": ("town_dojo.jpg", 340, 632, 420, 210),
    "innkeeper": ("town_inn.jpg", 310, 480, 432, 210),
    "sage": ("town_sage.jpg", 200, 510, 320, 290),
}


def main():
    meta = {}
    for bid, (fn, out_w, sx, sy, sw) in TABLE.items():
        rgb = np.asarray(Image.open(SRC / fn).convert("RGB")).astype(int)
        bg = np.abs(rgb - np.array([255, 0, 255])).sum(axis=2) < 110
        fg = ndi.binary_opening(~bg, iterations=2)
        lab, k = ndi.label(fg)
        sizes = ndi.sum(fg, lab, range(1, k + 1))
        keep = np.isin(lab, [i + 1 for i, s in enumerate(sizes) if s > 0.02 * sizes.max()])   # 去掉零碎噪点，保留主体和马 / 手推车等
        ys, xs = np.where(keep)
        x0, y0, x1, y1 = xs.min(), ys.min(), xs.max() + 1, ys.max() + 1
        # 边缘的洋红染色：用最近的前景色替换
        idx = ndi.distance_transform_edt(~keep, return_distances=False, return_indices=True)
        col = rgb[idx[0], idx[1]]
        alpha = (keep * 255).astype(np.uint8)
        im = Image.fromarray(np.dstack([col, alpha]).astype(np.uint8), "RGBA").crop((x0, y0, x1, y1))
        s = out_w / im.width
        im = im.resize((out_w, max(1, round(im.height * s))), Image.LANCZOS)
        im.save(OUT / f"{bid}.png")
        meta[bid] = {"file": f"{bid}.png", "w": im.width, "h": im.height,
                     "sign": [round((sx - x0) * s), round((sy - y0) * s), round(sw * s)]}
        print(bid, im.size, meta[bid]["sign"])
    (OUT / "meta.json").write_text(json.dumps(meta, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
