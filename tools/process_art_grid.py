#!/usr/bin/env python3
"""洋红底的「格子表」→ 游戏素材。支持四种：图标 / 场景物件 / NPC / 地面瓦片。

用法：
  python3 tools/process_art_grid.py icons  源图 --cols 3 --rows 3 --ids a,b,c,... --out assets/icons/skills --size 64
  python3 tools/process_art_grid.py props  源图 --cols 4 --rows 2 --ids tree,rock,... --out assets/maps/black_wind/props --scale 0.3
  python3 tools/process_art_grid.py npc    源图 --cols 3 --rows 2 --ids clerk,smith,... --out assets/town/npc --height 60
  python3 tools/process_art_grid.py enemy  源图 --cols 4 --ids bandit --out assets/enemies --height 42 --fps 8
  python3 tools/process_art_grid.py tiles  源图 --cols 4 --ids ground_0,ground_1,... --out assets/maps/black_wind --size 64

抠图：背景色取四周边缘的中位色，距离近的算背景。图标 / NPC 里的紫色（拳头图标、紫色心法）不会被误删；
场景物件下面的「紫色影子」会换成半透明的黑色柔影。边缘的洋红色晕边被削掉 2 像素。
"""
import argparse
import json
import pathlib
import sys

import numpy as np
from PIL import Image
from scipy import ndimage as ndi

ROOT = pathlib.Path(__file__).resolve().parent.parent


def load(path: str) -> np.ndarray:
    return np.asarray(Image.open(path).convert("RGB")).astype(np.int32)


def masks(rgb: np.ndarray, shadow: bool, smear: bool = False):
    border = np.concatenate([rgb[0], rgb[-1], rgb[:, 0], rgb[:, -1]])
    bg = np.median(border, axis=0)
    d = np.abs(rgb - bg).sum(axis=2)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    is_bg = d < 120
    sh = np.zeros_like(is_bg)
    if shadow:   # 紫色影子：不是背景、绿通道很低、红蓝都明显高于绿且接近
        sh = (~is_bg) & (np.minimum(r, b) - g > 70) & (g < 90) & (np.abs(r - b) < 90) & (np.minimum(r, b) > 70)
    fg = ~is_bg & ~sh
    if smear:   # AI 出图常见的洋红 / 紫色动态拖影：红蓝都明显高于绿且接近的，当作背景（皮肤、红头巾、蓝灰衣服都不满足）
        fg &= ~((r - g > 22) & (b - g > 22) & (np.abs(r - b) < 70))
    # 削掉洋红晕边
    fg = ndi.binary_erosion(fg, iterations=2)
    # 去掉小碎块（保留面积 >= 最大块 3% 的）
    lab, n = ndi.label(fg, structure=np.ones((3, 3)))
    if n:
        sizes = ndi.sum(fg, lab, range(1, n + 1))
        keep = np.isin(lab, [i + 1 for i, s in enumerate(sizes) if s >= max(30, 0.03 * sizes.max())])
        fg = keep
    if smear and fg.any():
        # 只保留和主体相连（或几乎相连）的部分：脱离身体飘在旁边的拖影块 / 碎片去掉；武器、披风、长矛都和身体连着，不受影响
        lab2, n2 = ndi.label(fg, structure=np.ones((3, 3)))
        sizes2 = ndi.sum(fg, lab2, range(1, n2 + 1))
        main = lab2 == (int(np.argmax(sizes2)) + 1)
        near = ndi.binary_dilation(main, iterations=5)
        keep2 = np.zeros_like(fg)
        for i in range(1, n2 + 1):
            comp = lab2 == i
            if (comp & near).any():
                keep2 |= comp
        fg = keep2
    sh = sh & ~ndi.binary_dilation(fg, iterations=0)
    return fg, sh


def cells_of(arr: np.ndarray, cols: int, rows: int):
    h, w, _ = arr.shape
    cw, ch = w // cols, h // rows
    for r in range(rows):
        for c in range(cols):
            yield r * cols + c, (c * cw, r * ch, (c + 1) * cw, (r + 1) * ch)


def rgba_of(rgb: np.ndarray, fg: np.ndarray, sh: np.ndarray) -> np.ndarray:
    a = np.zeros(rgb.shape[:2], dtype=np.uint8)
    a[fg] = 255
    out = np.dstack([np.clip(rgb, 0, 255).astype(np.uint8), a])
    if sh.any():    # 影子：半透明黑，边缘柔化
        soft = ndi.gaussian_filter(sh.astype(float), 1.5)
        shadow_a = (np.clip(soft * 1.2, 0, 1) * 95).astype(np.uint8)
        m = (~fg) & (shadow_a > 6)
        out[m] = np.dstack([np.zeros_like(a), np.zeros_like(a), np.zeros_like(a), shadow_a])[m]
    return out


def bbox(mask: np.ndarray):
    ys, xs = np.where(mask)
    return xs.min(), xs.max() + 1, ys.min(), ys.max() + 1


def run(a) -> None:
    arr = load(a.src)
    out_dir = ROOT / a.out if not pathlib.Path(a.out).is_absolute() else pathlib.Path(a.out)
    out_dir.mkdir(parents=True, exist_ok=True)
    ids = a.ids.split(",")
    if a.mode == "tiles":
        h, w, _ = arr.shape
        cw = w // a.cols
        fg_all, _ = masks(arr, False)
        for i, (idx, (x0, y0, x1, y1)) in enumerate(cells_of(arr, a.cols, 1)):
            cell = arr[:, x0:x1]
            border = np.median(np.concatenate([cell[0], cell[-1]]), axis=0)
            nonbg = np.abs(cell - np.median(np.concatenate([arr[0], arr[-1], arr[:, 0], arr[:, -1]]), axis=0)).sum(axis=2) > 120
            nonbg = ndi.binary_opening(nonbg, iterations=3)
            xs, xe, ys, ye = bbox(nonbg)
            inset = 4
            tile = cell[ys + inset:ye - inset, xs + inset:xe - inset]
            im = Image.fromarray(tile.astype(np.uint8)).resize((a.size, a.size), Image.BOX)
            im.save(out_dir / f"{ids[i]}.png")
            print("已写入", out_dir / f"{ids[i]}.png", tile.shape[:2], "→", a.size)
        return
    if a.mode == "enemy":
        # 一条横向的行走循环：每帧抠图；所有帧用同一个缩放（按最高的那帧到目标身高），脚底对齐格子底边，
        # 横向用「各帧重心的平均值」对齐，这样身体不会抖、挥动的武器也不会被裁掉
        frames = []
        keep_idx = [int(x) - 1 for x in a.use.split(",")] if a.use else list(range(a.cols))
        all_cells = list(cells_of(arr, a.cols, 1))
        for idx in keep_idx:
            _, (x0, y0, x1, y1) = all_cells[idx]
            cell = arr[y0:y1, x0:x1]
            fg, _ = masks(cell, False, smear=True)
            if not fg.any():
                sys.exit(f"第 {idx + 1} 帧是空的")
            frames.append((cell, fg))
        boxes = [bbox(fg) for _, fg in frames]
        scale = a.height / float(max(b[3] - b[2] for b in boxes))
        cxs = [float(np.where(fg)[1].mean()) for _, fg in frames]
        avg_cx = sum(cxs) / len(cxs)
        left = max(avg_cx - b[0] for b in boxes)
        right = max(b[1] - avg_cx for b in boxes)
        cw = int(round((max(left, right) * 2) * scale)) + 4
        ch = int(round(a.height)) + 2
        strip = Image.new("RGBA", (cw * len(frames), ch), (0, 0, 0, 0))
        for i, ((cell, fg), (x0, x1, y0, y1)) in enumerate(zip(frames, boxes)):
            rgba = rgba_of(cell, fg, np.zeros_like(fg))[y0:y1, x0:x1]
            im = Image.fromarray(rgba, "RGBA")
            nw, nh = max(1, round(im.width * scale)), max(1, round(im.height * scale))
            im = im.resize((nw, nh), Image.LANCZOS)
            ox = int(round(cw / 2 + (x0 - avg_cx) * scale))
            strip.alpha_composite(im, (i * cw + ox, ch - 1 - nh))
        strip.save(out_dir / f"{ids[0]}.png")
        mp = out_dir / "meta.json"
        meta = json.loads(mp.read_text(encoding="utf-8")) if mp.exists() else {}
        meta[ids[0]] = {"file": f"{ids[0]}.png", "frames": len(frames), "fps": a.fps, "w": cw, "h": ch}
        mp.write_text(json.dumps(meta, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
        print(f"已写入 {out_dir / (ids[0] + '.png')}：{len(frames)} 帧，每帧 {cw}×{ch}")
        return
    pieces = []
    for idx, (x0, y0, x1, y1) in cells_of(arr, a.cols, a.rows):
        cell = arr[y0:y1, x0:x1]
        fg, sh = masks(cell, a.mode == "props")
        if not fg.any():
            sys.exit(f"第 {idx + 1} 格是空的")
        pieces.append((cell, fg, sh))
    if a.mode == "icons":
        for i, (cell, fg, sh) in enumerate(pieces):
            x0, x1, y0, y1 = bbox(fg)
            rgba = rgba_of(cell, fg, sh)[y0:y1, x0:x1]
            im = Image.fromarray(rgba, "RGBA")
            s = (a.size - 4) / max(im.width, im.height)
            im = im.resize((max(1, round(im.width * s)), max(1, round(im.height * s))), Image.LANCZOS)
            canvas = Image.new("RGBA", (a.size, a.size), (0, 0, 0, 0))
            canvas.paste(im, ((a.size - im.width) // 2, (a.size - im.height) // 2))
            canvas.save(out_dir / f"{ids[i]}.png")
        print(f"已写入 {len(ids)} 个图标 → {out_dir}")
        return
    # props / npc：保持格子之间的相对大小；脚底（物件底部）对齐到图片底边
    boxes = [bbox(fg | sh) if a.mode == "props" else bbox(fg) for _, fg, sh in pieces]
    heights = [b[3] - b[2] for b in boxes]
    if a.mode == "npc":
        scale = a.height / float(np.median(heights))
    else:
        scale = a.scale
    meta = {}
    for i, ((cell, fg, sh), (x0, x1, y0, y1)) in enumerate(zip(pieces, boxes)):
        rgba = rgba_of(cell, fg, sh)[y0:y1, x0:x1]
        im = Image.fromarray(rgba, "RGBA")
        im = im.resize((max(1, round(im.width * scale)), max(1, round(im.height * scale))), Image.LANCZOS)
        im.save(out_dir / f"{ids[i]}.png")
        meta[ids[i]] = {"file": f"{ids[i]}.png", "w": im.width, "h": im.height}
    (out_dir / "meta.json").write_text(json.dumps(meta, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print(f"已写入 {len(ids)} 个 → {out_dir}（缩放 {scale:.3f}）", {k: (v['w'], v['h']) for k, v in meta.items()})


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("mode", choices=["icons", "props", "npc", "tiles", "enemy"])
    ap.add_argument("src")
    ap.add_argument("--cols", type=int, required=True)
    ap.add_argument("--rows", type=int, default=1)
    ap.add_argument("--ids", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--size", type=int, default=64)
    ap.add_argument("--scale", type=float, default=0.3)
    ap.add_argument("--height", type=float, default=60.0)
    ap.add_argument("--fps", type=float, default=8.0)
    ap.add_argument("--use", default="", help="怪物模式：只用并重排其中几帧，如 1,3,4,3（从 1 数起；某帧有重影 / 拖影时用）")
    run(ap.parse_args())


if __name__ == "__main__":
    main()
