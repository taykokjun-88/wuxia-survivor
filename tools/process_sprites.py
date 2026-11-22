#!/usr/bin/env python3
"""AI 出的洋红底像素图 → 游戏用 sprite（透明底、统一缩放、固定调色板、脚底对齐）。

依赖：pip install pillow numpy scipy

用法：
  # 1) 先用所有素材建一个共用调色板（含特效用的奶白色等）
  python3 tools/process_sprites.py palette assets/sprites/source/*.jpg --colors 28

  # 2) 逐条处理动画（横向条带，N 帧）
  python3 tools/process_sprites.py strip assets/sprites/source/idle.jpg  idle  --frames 4 --use 1,3,4,3 --fps 4
  python3 tools/process_sprites.py strip assets/sprites/source/walk.jpg  walk  --frames 6 --fps 10
  python3 tools/process_sprites.py strip assets/sprites/source/punch.jpg punch --frames 4 --fps 16 --once
  python3 tools/process_sprites.py strip assets/sprites/source/dash.jpg  dash  --frames 3 --fps 14 --once \\
         --scale-mode image --align keep

输出到 assets/sprites/player/：<name>.png（横向条带，每格 cell×cell）、anim.json（游戏读取）、palette.json。

怎么处理 AI 出图的常见毛病：
  - 紫色/洋红的动态模糊拖影：按色相判断为背景，直接去掉
  - 帧交界处的细竖线、飘在外面的深色碎块：去掉；靠近角色的浅色特效（拳风、气劲弧、速度线）保留
  - 各条图的分辨率不同：scale-mode=frame 时按"参考帧（默认第 1 帧，站姿）"的身高缩放到 --height；
    没有站姿的动画（dash）用 scale-mode=image，按图高与基准动画的比例缩放
  - 缩放用最近邻（保持硬边），背景色先用最近前景色填充，避免边缘染上洋红；颜色吸附到固定调色板
  - 脚底：align=ground 每帧脚底落在同一条线；align=keep 保持帧间原有的高低（冲刺腾空）
  - 水平：每帧按"脚的中心"居中，播放时角色不会滑动
"""
import argparse
import json
import pathlib
import sys

import numpy as np
from PIL import Image
from scipy import ndimage as ndi

ROOT = pathlib.Path(__file__).resolve().parent.parent
DEFAULT_OUT = ROOT / "assets" / "sprites" / "player"
EIGHT = np.ones((3, 3), dtype=bool)


# ---------------------------------------------------------------- 去底
def key_mask(rgb: np.ndarray) -> np.ndarray:
    """前景遮罩：洋红底 + 紫色拖影都当背景。背景色取四周边缘的中位色。"""
    border = np.concatenate([rgb[0], rgb[-1], rgb[:, 0], rgb[:, -1]]).astype(int)
    bg = np.median(border, axis=0)
    a = rgb.astype(int)
    dist = np.abs(a - bg).sum(axis=2)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    # 洋红 / 紫色：红和蓝都明显高于绿，且红蓝接近。皮肤(b<g)、红围巾(b≈g)、青绿衣服(g 高)、深色轮廓都不满足
    purple = ((r - g) > 22) & ((b - g) > 22) & (np.abs(r - b) < 70)
    return (dist > 110) & ~purple


def luminance(rgb: np.ndarray) -> np.ndarray:
    return rgb.astype(float).mean(axis=2)


def clean_cell(mask: np.ndarray, rgb: np.ndarray) -> np.ndarray:
    """清理一格：去掉细线和碎块，保留主体和靠近主体的浅色特效。"""
    H, W = mask.shape
    thin = max(4, H // 100)
    # 1) 细线（贯穿整格的竖线 / 横线）
    lab, _ = ndi.label(mask, structure=EIGHT)
    out = mask.copy()
    for i, sl in enumerate(ndi.find_objects(lab), start=1):
        h, w = sl[0].stop - sl[0].start, sl[1].stop - sl[1].start
        if (w <= thin and h > 0.5 * H) or (h <= thin and w > 0.5 * W):
            out[lab == i] = False
    # 2) 膨胀后分簇：主簇 = 面积最大；其他簇只有"浅色 + 有一定大小 + 在主体附近"才保留（拳风、气劲弧、速度线）
    d = max(3, H // 60)
    clusters, n = ndi.label(ndi.binary_dilation(out, iterations=d), structure=EIGHT)
    if n == 0:
        return out
    idx = range(1, n + 1)
    areas = np.asarray(ndi.sum(out, clusters, index=idx))
    main = int(np.argmax(areas)) + 1
    ys, xs = np.where((clusters == main) & out)
    x0, y0, x1, y1 = xs.min(), ys.min(), xs.max(), ys.max()
    ph = y1 - y0
    lum = luminance(rgb)
    keep = (clusters == main) & out
    for k in idx:
        if k == main:
            continue
        sel = (clusters == k) & out
        if areas[k - 1] < 0.003 * areas[main - 1]:
            continue
        if lum[sel].mean() < 150:             # 深色碎块（飘着的靴子、头发）丢掉
            continue
        yk, xk = np.where(sel)
        cx, cy = xk.mean(), yk.mean()
        if x0 - 0.5 * ph <= cx <= x1 + 0.5 * ph and y0 - 0.4 * ph <= cy <= y1 + 0.4 * ph:
            keep |= sel
    return keep


def bbox(mask: np.ndarray):
    ys, xs = np.where(mask)
    if len(xs) == 0:
        return None
    return int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1


def fill_bg(rgb: np.ndarray, mask: np.ndarray) -> np.ndarray:
    """背景像素用最近的前景颜色填充，缩放时边缘不会染上洋红。"""
    idx = ndi.distance_transform_edt(~mask, return_distances=False, return_indices=True)
    return rgb[idx[0], idx[1]]


# ---------------------------------------------------------------- 调色板
def snap(arr: np.ndarray, palette) -> np.ndarray:
    pal = np.asarray(palette, dtype=int)
    flat = arr.reshape(-1, 1, 3).astype(int)
    idx = np.abs(flat - pal[None, :, :]).sum(axis=2).argmin(axis=1)
    return pal[idx].reshape(arr.shape).astype("uint8")


def cmd_palette(args):
    out_dir = pathlib.Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)
    samples = []
    rng = np.random.default_rng(1)
    for src in args.src:
        rgb = np.asarray(Image.open(src).convert("RGB"))
        m = key_mask(rgb)
        px = rgb[m]
        if len(px) > 150000:
            px = px[rng.choice(len(px), 150000, replace=False)]
        samples.append(px)
        print(f"{src}: 前景像素 {int(m.sum())}")
    allpx = np.concatenate(samples).reshape(-1, 1, 3).astype("uint8")
    q = Image.fromarray(allpx).quantize(colors=args.colors, method=Image.MEDIANCUT)
    pal = np.asarray(q.getpalette()[: args.colors * 3]).reshape(-1, 3)
    used = sorted({tuple(int(v) for v in pal[i]) for i in np.asarray(q).reshape(-1)})
    (out_dir / "palette.json").write_text(json.dumps([list(c) for c in used]))
    print(f"调色板 {len(used)} 色 → {out_dir / 'palette.json'}")


# ---------------------------------------------------------------- 条带
def cmd_strip(args):
    out_dir = pathlib.Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)
    pal_file = out_dir / "palette.json"
    if not pal_file.exists():
        sys.exit("还没有调色板：先运行 palette 子命令")
    palette = json.loads(pal_file.read_text())

    img = Image.open(args.src).convert("RGB")
    rgb = np.asarray(img)
    H, W = rgb.shape[:2]
    full_mask = key_mask(rgb)

    # 切格 → 清理 → 取包围盒
    frames = []
    for i in range(args.frames):
        x0, x1 = round(i * W / args.frames), round((i + 1) * W / args.frames)
        cell_rgb = rgb[:, x0:x1]
        m = clean_cell(full_mask[:, x0:x1], cell_rgb)
        b = bbox(m)
        if b is None:
            sys.exit(f"第 {i + 1} 帧是空的：请确认条带里确实有 {args.frames} 帧，且大致等距")
        frames.append({"rgb": cell_rgb, "mask": m, "bbox": b})

    use = [int(v) - 1 for v in args.use.split(",")] if args.use else list(range(args.frames))
    for u in use:
        if not 0 <= u < args.frames:
            sys.exit(f"--use 里的帧号 {u + 1} 超出范围 1~{args.frames}")

    # 缩放：frame 模式按参考帧身高；image 模式按图高与基准动画的比例
    scale_file = out_dir / "scale.json"
    ref = frames[args.ref_frame - 1]["bbox"]
    ref_h = ref[3] - ref[1]
    if args.scale > 0:
        scale = args.scale                       # 手动指定（各动作里人物本体大小不一致时，按本体高度换算）
    elif args.scale_mode == "image":
        if not scale_file.exists():
            sys.exit("scale-mode=image 需要先处理过一条 frame 模式的动画（scale.json）")
        k = json.loads(scale_file.read_text())["k"]
        scale = k / H
    else:
        scale = args.height / ref_h
        if not scale_file.exists():
            scale_file.write_text(json.dumps({"k": scale * H, "height": args.height}, indent=2))
            print(f"基准动画：缩放 {scale:.4f}，k={scale * H:.1f}")
    print(f"{args.src}: {W}×{H}，参考帧身高 {ref_h}px，缩放 {scale:.4f}（{args.scale_mode}）")

    # 逐帧：缩放 → 吸附调色板 → 脚底/脚中心定位
    cell = args.cell
    ref_bottom = frames[args.ref_frame - 1]["bbox"][3]
    tiles = []
    for u in use:
        f = frames[u]
        x0, y0, x1, y1 = f["bbox"]
        crop_rgb = fill_bg(f["rgb"], f["mask"])[y0:y1, x0:x1]
        crop_m = f["mask"][y0:y1, x0:x1]
        w, h = max(1, round((x1 - x0) * scale)), max(1, round((y1 - y0) * scale))
        rgb_s = snap(np.asarray(Image.fromarray(crop_rgb).resize((w, h), Image.NEAREST)), palette)
        # 轮廓用面积采样再阈值，比最近邻更稳（不会丢细小的特效像素）
        m_s = np.asarray(Image.fromarray((crop_m * 255).astype("uint8")).resize((w, h), Image.BOX)) > 90
        low = m_s[int(h * 0.65):]
        xs = np.where(low.any(axis=0))[0]
        foot_x = float(xs.mean()) if len(xs) else w / 2.0     # 脚的水平中心
        tiles.append((rgb_s, m_s, foot_x, y1))

    strip = Image.new("RGBA", (cell * len(tiles), cell), (0, 0, 0, 0))
    clipped = 0
    for i, (rgb_s, m_s, foot_x, y_bottom) in enumerate(tiles):
        h, w = m_s.shape
        ox = int(round(cell / 2 - foot_x))
        if args.align == "keep":
            oy = cell - 4 - h - int(round((ref_bottom - y_bottom) * scale))
        else:
            oy = cell - 4 - h
        tile = Image.fromarray(np.dstack([rgb_s, (m_s * 255).astype("uint8")]), "RGBA")
        sx, sy = max(0, -ox), max(0, -oy)
        ex, ey = min(w, cell - ox), min(h, cell - oy)
        if sx > 0 or sy > 0 or ex < w or ey < h:
            clipped += 1
        if ex > sx and ey > sy:
            strip.alpha_composite(tile.crop((sx, sy, ex, ey)), (i * cell + ox + sx, oy + sy))
    if clipped:
        print(f"警告：{clipped} 帧超出 {cell}px 格子被裁掉，建议加大 --cell")
    out_png = out_dir / f"{args.name}.png"
    strip.save(out_png)

    anim_file = out_dir / "anim.json"
    anim = json.loads(anim_file.read_text()) if anim_file.exists() else {"cell": cell, "anims": {}}
    if int(anim.get("cell", cell)) != cell:
        sys.exit(f"cell 必须和已有动画一致（{anim['cell']}）；要改请删除 anim.json 后全部重做")
    anim["cell"] = cell
    anim["anims"][args.name] = {"file": f"{args.name}.png", "frames": len(tiles), "fps": args.fps, "loop": not args.once}
    anim_file.write_text(json.dumps(anim, ensure_ascii=False, indent=2))
    print(f"已写入 {out_png.resolve().relative_to(ROOT)}：{len(tiles)} 帧 × {cell}px")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("palette", help="用所有素材建共用调色板")
    p.add_argument("src", nargs="+")
    p.add_argument("--colors", type=int, default=28)
    p.add_argument("--out", default=str(DEFAULT_OUT))
    p.set_defaults(fn=cmd_palette)

    s = sub.add_parser("strip", help="处理一条动画条带")
    s.add_argument("src")
    s.add_argument("name", help="动画名：idle / walk / punch / palm / dash / hurt / death / ult")
    s.add_argument("--frames", type=int, required=True, help="源图里的帧数")
    s.add_argument("--use", default="", help="只用并重排其中几帧，如 1,3,4,3（1 起）；默认全部按顺序")
    s.add_argument("--fps", type=float, default=8)
    s.add_argument("--once", action="store_true", help="只播放一次（出招、受击、倒下等）")
    s.add_argument("--ref-frame", type=int, default=1, help="缩放参考帧（站姿那一帧），默认第 1 帧")
    s.add_argument("--scale-mode", choices=["frame", "image"], default="frame")
    s.add_argument("--align", choices=["ground", "keep"], default="ground")
    s.add_argument("--height", type=int, default=56, help="参考帧的目标身高（像素）")
    s.add_argument("--scale", type=float, default=0.0, help="直接指定缩放倍数（覆盖 --height / --scale-mode）")
    s.add_argument("--cell", type=int, default=96)
    s.add_argument("--out", default=str(DEFAULT_OUT))
    s.set_defaults(fn=cmd_strip)
    a = ap.parse_args()
    a.fn(a)


if __name__ == "__main__":
    main()
