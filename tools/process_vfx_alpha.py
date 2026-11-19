#!/usr/bin/env python3
"""洋红底的特效图 → 带真实透明度的特效条带（assets/vfx/<id>.png）+ 登记到 vfx.json。
和 process_vfx.py 的区别：那个按亮度转透明度（要求黑底发光图），深色特效（铁砂掌、玄铁刀光、爪痕）会被吃掉；
这个直接按「离洋红底有多远」抠出软透明度，保留原色。

用法：python3 tools/process_vfx_alpha.py 源图.jpg 特效id --frames 4 --cell 192 --fps 14 [--loop] [--world-size 160] [--forward 0.2] [--crop x0,y0,x1,y1]
"""
import argparse
import json
import pathlib
import sys

import numpy as np
from PIL import Image
from scipy import ndimage as ndi

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import process_vfx as pv  # noqa: E402


def to_rgba(img: Image.Image) -> np.ndarray:
    rgb = np.asarray(img.convert("RGB")).astype(np.float32)
    border = np.concatenate([rgb[0], rgb[-1], rgb[:, 0], rgb[:, -1]])
    bg = np.median(border, axis=0)
    dist = np.abs(rgb - bg).sum(axis=2)
    alpha = np.clip((dist - 60.0) / 170.0, 0.0, 1.0)
    solid = alpha > 0.9
    idx = ndi.distance_transform_edt(~solid, return_distances=False, return_indices=True)
    core = rgb[idx[0], idx[1]]
    col = np.where((alpha < 0.9)[..., None], core, rgb)
    return np.dstack([col, alpha * 255.0])


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("id")
    ap.add_argument("--frames", type=int, required=True)
    ap.add_argument("--cell", type=int, default=192)
    ap.add_argument("--fps", type=float, default=14)
    ap.add_argument("--loop", action="store_true")
    ap.add_argument("--world-size", type=float, default=0.0)
    ap.add_argument("--forward", type=float, default=None)
    ap.add_argument("--scale", type=float, default=None)
    ap.add_argument("--crop", default="")
    a = ap.parse_args()
    img = Image.open(a.src)
    if a.crop:
        img = img.crop(tuple(int(v) for v in a.crop.split(",")))
    arr = to_rgba(img)
    h, w, _ = arr.shape
    lit = arr[..., 3] > 40
    occ = lit.sum(axis=0)
    cuts, _ = pv._boundaries(occ, a.frames)
    ys = np.where(lit.any(axis=1))[0]
    cy = (ys.min() + ys.max()) / 2
    half_h = (ys.max() - ys.min()) / 2
    boxes = []
    for x0, x1 in zip(cuts[:-1], cuts[1:]):
        sub = lit[:, x0:x1]
        xs = np.where(sub.any(axis=0))[0]
        boxes.append((x0, x1, x0 + xs.min(), x0 + xs.max() + 1) if len(xs) else None)
    half_w = max((b[3] - b[2]) / 2 for b in boxes if b)
    side = int(max(half_h, half_w) * 2 * 1.06) + 2
    out = Image.new("RGBA", (a.cell * a.frames, a.cell), (0, 0, 0, 0))
    for i, b in enumerate(boxes):
        if b is None:
            continue
        x0, x1, c0, c1 = b
        cx = (c0 + c1) / 2
        ox, oy = int(round(cx - side / 2)), int(round(cy - side / 2))
        canvas = np.zeros((side, side, 4), dtype=np.float32)
        sx0, sy0 = max(ox, 0), max(oy, 0)
        sx1, sy1 = min(ox + side, w), min(oy + side, h)
        canvas[sy0 - oy:sy1 - oy, sx0 - ox:sx1 - ox] = arr[sy0:sy1, sx0:sx1]
        keep = np.zeros(side, dtype=bool)
        keep[max(0, x0 - ox):min(side, x1 - ox)] = True       # 只保留本帧范围内的内容
        canvas[:, ~keep, 3] = 0
        # 预乘后缩放（避免边缘染色），再还原
        pm = canvas.copy()
        pm[..., :3] *= pm[..., 3:4] / 255.0
        small = np.asarray(Image.fromarray(pm.astype(np.uint8), "RGBA").resize((a.cell, a.cell), Image.LANCZOS)).astype(np.float32)
        al = small[..., 3:4]
        rgb = np.where(al > 0, small[..., :3] * 255.0 / np.maximum(al, 1.0), 0.0)
        piece = np.dstack([np.clip(rgb, 0, 255), al]).astype(np.uint8)
        out.paste(Image.fromarray(piece, "RGBA"), (i * a.cell, 0))
    pv.OUT.mkdir(parents=True, exist_ok=True)
    out.save(pv.OUT / f"{a.id}.png")
    cfg = pv.load_cfg()
    entry = {"file": f"{a.id}.png", "frames": a.frames, "fps": a.fps, "cell": a.cell, "loop": a.loop}
    old = cfg["effects"].get(a.id, {})
    ws = a.world_size or float(old.get("world_size", 0.0))
    if ws > 0:
        entry["world_size"] = ws
    for k, v in (("scale", a.scale), ("forward", a.forward)):
        if v is not None:
            entry[k] = v
        elif k in old:
            entry[k] = old[k]
    cfg["effects"][a.id] = entry
    (pv.OUT / "vfx.json").write_text(json.dumps(cfg, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"已写入 assets/vfx/{a.id}.png：{a.frames} 帧 × {a.cell}px")


if __name__ == "__main__":
    main()
