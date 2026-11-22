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
DOWN_FIX = 1.07      # 实测：按身体高度缩放后正面仍比背面 / 侧面矮约 7%（站姿帧比走路帧矮），再放大一点


V3 = ROOT / "assets" / "source" / "yangjiajiang_v3"
V4 = ROOT / "assets" / "source" / "yangjiajiang_v4"


def body_height(frame):
    """去掉枪杆 / 棍这类细长物后的「身体高度」：对不透明区域做开运算，只保留粗的部分，再量包围盒"""
    from scipy import ndimage as ndi
    a = np.array(frame.getchannel("A")) > 100
    r = max(2, a.shape[0] // 22)
    o = ndi.binary_opening(a, structure=np.ones((r, r), bool))
    ys = np.where(o.any(axis=1))[0]
    return float(ys.max() - ys.min() + 1) if len(ys) else float(a.shape[0])


def frames_of(name, n=4):
    f4 = V4 / f"spear_{name}.png"                 # 第四版有的用第四版（侧面还是第三版）
    im = to_rgba(Image.open(f4 if f4.exists() else V3 / f"spear_{name}.png").convert("RGB"))
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
    # 正面那张的枪尖高过头顶，按整体高度缩放会让身体比背面 / 侧面小一号：
    # 正面改按「身体高度」缩放，目标 = 背面和侧面（仍按整体高度缩放）缩放后的平均身体高度
    ref = []
    for key in ("up", "side"):
        hs = sorted(f.height for f, _ in sets[key])
        k0 = TARGET_H / hs[len(hs) // 2]
        ref.append(k0 * sorted(body_height(f) for f, _ in sets[key])[len(sets[key]) // 2])
    body_target = sum(ref) / len(ref)
    for key, frs in sets.items():
        # 三张源图是分别生成的，比例不一致：每一组按自己的中位帧高度缩放到 TARGET_H（含枪尖，所以身体约 52 像素）
        hs = sorted(f.height for f, _ in frs)
        k = TARGET_H / hs[len(hs) // 2]
        if key == "down":
            k = body_target / sorted(body_height(f) for f, _ in frs)[len(frs) // 2] * DOWN_FIX
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
