#!/usr/bin/env python3
"""重置画面计划书 7~9：Gemini 的怪物 / Boss 精灵条带（RGBA、每格 256×256、脚底距格底 16px）→ assets/enemies/ + meta.json。

源图：assets/source/redraw_07|08|09/<id>.png（循环）、<id>_attack / _windup / _hurt / _death.png（动作）
处理：
  - 去掉脚下的粉紫色块与细横线（elite 系列有地面线）
  - 同一个怪物的所有条带用同一个输出格大小和缩放，保证比例一致
  - 输出格 = 人物高度的 ~1.5 倍（上限 256）；预乘 alpha 后 LANCZOS 缩小
  - meta.json 里：w/h = 输出格，scale = 世界缩放，foot = 脚底距格底（输出像素），fh = 人物在世界里的高度（沿用旧素材的 h，保持怪物大小不变）
用法：python3 tools/process_redraw_enemies.py
"""
import json
import pathlib

import sys

import numpy as np
from PIL import Image
from scipy import ndimage as ndi

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
from sprite_clean import defragment
SRC = ROOT / "assets/source"
OUT = ROOT / "assets/enemies"
STAGES = ["redraw_07", "redraw_08", "redraw_09"]
SRC_CELL = 256
SRC_FOOT = 16
SUFFIX = ("_attack", "_windup", "_hurt", "_death")
EIGHT = np.ones((3, 3), dtype=bool)


def base_id(name: str) -> str:
    for s in SUFFIX:
        if name.endswith(s):
            return name[: -len(s)]
    return name


def clean(cell: np.ndarray) -> np.ndarray:
    """cell: RGBA uint8。去掉粉紫色块和贯穿的细横线。"""
    a = cell[..., 3].astype(float)
    r, g, b = cell[..., 0].astype(int), cell[..., 1].astype(int), cell[..., 2].astype(int)
    pink = (r > 170) & (b > 170) & (g < 140) & ((r - g) > 60) & ((b - g) > 60) & (np.abs(r - b) < 70) & (a > 20)
    out = cell.copy()
    out[pink, 3] = 0
    mask = out[..., 3] > 20
    lab, n = ndi.label(mask, structure=EIGHT)
    for i, sl in enumerate(ndi.find_objects(lab), start=1):
        h = sl[0].stop - sl[0].start
        w = sl[1].stop - sl[1].start
        if h <= 4 and w >= 30 and sl[0].start > 200:      # 脚下的细线
            out[lab == i, 3] = 0
    return out


def figure_height(arr: np.ndarray, n: int) -> int:
    hs = []
    for i in range(n):
        al = arr[:, i * SRC_CELL:(i + 1) * SRC_CELL, 3] > 40
        ys = np.where(al.any(axis=1))[0]
        if len(ys):
            hs.append(int(ys.max() - ys.min()))
    return int(np.median(hs)) if hs else SRC_CELL // 2


def main() -> None:
    meta = json.loads((OUT / "meta.json").read_text(encoding="utf-8"))
    files = {}
    for st in STAGES:
        for f in sorted((SRC / st).glob("*.png")):
            files[f.stem] = f
    ids = sorted({base_id(n) for n in files if base_id(n) in meta})
    for eid in ids:
        old = meta[eid]
        fh_world = float(old.get("fh", float(old["h"]) * float(old.get("scale", 1.0))))
        loop = files.get(eid)
        if loop is None:
            continue
        loop_arr = np.array(Image.open(loop).convert("RGBA"))
        fig = figure_height(loop_arr, loop_arr.shape[1] // SRC_CELL)
        cell = int(max(96, min(256, round(fig * 1.5 / 8.0) * 8)))
        k = cell / SRC_CELL
        fig_out = fig * k
        scale = fh_world / fig_out
        foot = round(SRC_FOOT * k)
        entry = dict(old)
        for name, f in files.items():
            if base_id(name) != eid:
                continue
            im = np.array(Image.open(f).convert("RGBA"))
            n = im.shape[1] // SRC_CELL
            strip = Image.new("RGBA", (cell * n, cell), (0, 0, 0, 0))
            for i in range(n):
                c = clean(im[:, i * SRC_CELL:(i + 1) * SRC_CELL])
                c, _rm = defragment(c, gap=4, ramp=26)                  # 去掉漂在外面的碎块；被格子边界切断的边缘渐隐
                pm = Image.fromarray(c, "RGBA").convert("RGBa").resize((cell, cell), Image.LANCZOS).convert("RGBA")
                strip.paste(pm, (i * cell, 0))
            strip.save(OUT / f"{name}.png")
            if name == eid:
                entry.update({"file": f"{eid}.png", "frames": n, "fps": float(old["fps"]), "w": cell, "h": cell, "scale": round(scale, 4), "foot": foot, "fh": round(fh_world, 2)})
            else:
                meta[name] = {"file": f"{name}.png", "frames": n, "fps": float(old["fps"]), "w": cell, "h": cell, "scale": round(scale, 4), "foot": foot, "fh": round(fh_world, 2)}
        meta[eid] = entry
        print(f"{eid}: 格 {cell}px，人物 {fig}px→世界 {fh_world:.0f}px，缩放 {scale:.3f}")
    (OUT / "meta.json").write_text(json.dumps(meta, ensure_ascii=False, indent=1), encoding="utf-8")


if __name__ == "__main__":
    main()
