#!/usr/bin/env python3
"""天赋穴位图标：洋红底的一排 4 个图标 → assets/ui/talent/node_{locked,open,ranked,maxed}.png（各 64×64，透明底）。

用法：python3 tools/process_icons.py 源图.jpg
源图：洋红（#ff00ff）底，横向 4 个图标，从左到右依次是 未打通 / 可点击 / 已有点数 / 已满。
图标请出成偏灰白的（游戏里会按所属经脉的颜色着色：刚=朱红，柔=青，灵=紫）。
"""
import pathlib
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from process_sprites import key_mask  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "ui" / "talent"
NAMES = ["locked", "open", "ranked", "maxed"]
SIZE = 64


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    img = Image.open(sys.argv[1]).convert("RGB")
    arr = np.asarray(img)
    h, w, _ = arr.shape
    cw = w // 4
    OUT.mkdir(parents=True, exist_ok=True)
    # 四个图标用同一个缩放比例（按最大的那个），保持相互之间的大小关系
    crops = []
    for i in range(4):
        cell = arr[:, i * cw:(i + 1) * cw]
        mask = key_mask(cell)
        ys, xs = np.where(mask)
        if len(xs) == 0:
            sys.exit(f"第 {i + 1} 个图标是空的")
        crops.append((cell, mask, xs.min(), xs.max() + 1, ys.min(), ys.max() + 1))
    side = max(max(c[3] - c[2], c[5] - c[4]) for c in crops)
    scale = (SIZE - 4) / side
    for name, (cell, mask, x0, x1, y0, y1) in zip(NAMES, crops):
        rgba = np.dstack([cell, (mask * 255).astype(np.uint8)])
        piece = Image.fromarray(rgba[y0:y1, x0:x1], "RGBA")
        nw, nh = max(1, round(piece.width * scale)), max(1, round(piece.height * scale))
        piece = piece.resize((nw, nh), Image.LANCZOS)
        canvas = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
        canvas.paste(piece, ((SIZE - nw) // 2, (SIZE - nh) // 2))
        canvas.save(OUT / f"node_{name}.png")
        print("已写入", OUT / f"node_{name}.png")


if __name__ == "__main__":
    main()
