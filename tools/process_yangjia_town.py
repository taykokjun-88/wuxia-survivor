#!/usr/bin/env python3
"""杨家将小镇精灵（正 / 背 / 侧，各 4 帧）：从 assets/source/yangjiajiang/town_*.webp 生成 assets/town/hero_spear/。"""
import json
import pathlib
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from process_yangjia import to_rgba, load  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "town" / "hero_spear"
TARGET_H = 62


def frames_of(name, n=4):
    im = to_rgba(load(name))
    W, H = im.size
    out = []
    for i in range(n):
        c = im.crop((round(i * W / n), 0, round((i + 1) * W / n), H))
        bb = c.getchannel("A").point(lambda v: 255 if v > 100 else 0).getbbox()
        out.append((c.crop(bb), bb))
    return out


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    meta = {}
    sets = {k: frames_of(f"town_{k}") for k in ["down", "up", "side"]}
    for key, frs in sets.items():
        # 三张源图是分别生成的，比例不一致：每一组按自己的中位帧高度缩放到 TARGET_H（含枪尖，所以身体约 52 像素）
        hs = sorted(f.height for f, _ in frs)
        k = TARGET_H / hs[len(hs) // 2]
        tiles = []
        for f, _ in frs:
            tiles.append(f.resize((max(1, round(f.width * k)), max(1, round(f.height * k))), Image.LANCZOS))
        w = max(t.width for t in tiles)
        h = max(t.height for t in tiles)
        strip = Image.new("RGBA", (w * len(tiles), h), (0, 0, 0, 0))
        for i, t in enumerate(tiles):
            strip.alpha_composite(t, (i * w + (w - t.width) // 2, h - t.height))
        strip.save(OUT / f"hero_{key}.png")
        meta[f"hero_{key}"] = {"file": f"hero_{key}.png", "frames": len(tiles), "fps": 8.0, "w": w, "h": h}
    (OUT / "meta.json").write_text(json.dumps(meta, ensure_ascii=False, indent=2))
    print(meta)


if __name__ == "__main__":
    main()
