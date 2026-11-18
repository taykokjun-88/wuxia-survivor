#!/usr/bin/env python3
"""AI 出的洋红底像素图 → 游戏用 sprite（透明底、统一像素大小、固定调色板、按脚底对齐）。

用法（需要 pillow、numpy）：
  # 1) 先处理"基础姿势"（1 帧），它决定整套角色的缩放比例和调色板
  python3 tools/process_sprites.py assets/sprites/source/player_base_pose.jpg idle --frames 1 --fps 1

  # 2) 其余动画（横向条带，N 帧）沿用同一缩放和调色板
  python3 tools/process_sprites.py assets/sprites/source/walk.png walk --frames 6 --fps 10
  python3 tools/process_sprites.py assets/sprites/source/punch.png punch --frames 4 --fps 16 --once

输出到 assets/sprites/player/：
  <name>.png     横向条带，每格 cell×cell（默认 64×64），透明底
  anim.json      各动画的帧数 / fps / 是否循环（游戏读取）
  scale.json     缩放比例（首次处理时写入，之后所有动画共用）
  palette.json   固定调色板（首次处理时写入）

怎么做到统一：
  - 洋红底键控 → 估计 AI 图的"原生像素块"大小 → 按块取样还原成真正的像素画
  - 所有动画使用同一个缩放比例（由基础姿势的身高决定），角色不会忽大忽小
  - 所有像素都吸附到同一个调色板，去掉 JPEG 噪点和渐变
  - 每帧按"脚底线"对齐、按身体中心水平对齐，播放时不抖
"""
import argparse
import json
import pathlib
import sys

import numpy as np
from PIL import Image, ImageFilter

ROOT = pathlib.Path(__file__).resolve().parent.parent
DEFAULT_OUT = ROOT / "assets" / "sprites" / "player"


# ---------------------------------------------------------------- 去底
def key_mask(rgb: np.ndarray) -> np.ndarray:
    """洋红底 → 前景遮罩。取四周边缘的中位色作为背景色。"""
    border = np.concatenate([rgb[0], rgb[-1], rgb[:, 0], rgb[:, -1]]).astype(int)
    bg = np.median(border, axis=0)
    dist = np.abs(rgb.astype(int) - bg).sum(axis=2)
    r, g, b = rgb[..., 0].astype(int), rgb[..., 1].astype(int), rgb[..., 2].astype(int)
    magenta_like = (r > 150) & (b > 150) & (g < 120)          # 去掉洋红边缘的残留
    mask = (dist > 110) & ~magenta_like
    m = Image.fromarray((mask * 255).astype("uint8")).filter(ImageFilter.MedianFilter(5))
    return np.asarray(m) > 127


def bbox(mask: np.ndarray):
    ys, xs = np.where(mask)
    if len(xs) == 0:
        return None
    return xs.min(), ys.min(), xs.max() + 1, ys.max() + 1


# ---------------------------------------------------------------- 原生像素网格
def estimate_block(rgb: np.ndarray, mask: np.ndarray) -> int:
    """AI 图里一个"像素"大约占多少真实像素：用颜色突变位置的自相关估计。"""
    a = rgb.astype(int)
    prof = (np.abs(np.diff(a, axis=1)).sum(axis=2) > 60)[:, :]
    prof = prof[mask[:, :-1]].reshape(-1) if False else prof.sum(axis=0)
    c = prof - prof.mean()
    ac = np.correlate(c, c, "full")[len(c) - 1:]
    lo, hi = 4, max(8, rgb.shape[1] // 40)
    cand = range(lo, hi)
    best = max(cand, key=lambda k: ac[k] / (1 + 0.02 * k))
    return int(best)


def to_native(img: Image.Image, mask: np.ndarray, block: int):
    """按块取样还原成原生像素画（NEAREST 取块中心，不混色）。"""
    b = bbox(mask)
    x0, y0, x1, y1 = b
    crop = img.crop((x0, y0, x1, y1))
    m = Image.fromarray((mask[y0:y1, x0:x1] * 255).astype("uint8"))
    nw, nh = max(1, round(crop.width / block)), max(1, round(crop.height / block))
    return crop.resize((nw, nh), Image.NEAREST), m.resize((nw, nh), Image.NEAREST)


# ---------------------------------------------------------------- 调色板
def build_palette(native_rgb: Image.Image, native_mask: Image.Image, colors: int) -> list:
    arr = np.asarray(native_rgb)
    m = np.asarray(native_mask) > 127
    px = arr[m].reshape(-1, 1, 3)
    q = Image.fromarray(px.astype("uint8")).quantize(colors=colors, method=Image.MEDIANCUT)
    pal = np.asarray(q.getpalette()[: colors * 3]).reshape(-1, 3)
    used = sorted({tuple(int(v) for v in pal[i]) for i in np.asarray(q).reshape(-1)})
    return [list(c) for c in used]


def snap(arr: np.ndarray, palette: list) -> np.ndarray:
    pal = np.asarray(palette, dtype=int)
    flat = arr.reshape(-1, 1, 3).astype(int)
    idx = np.abs(flat - pal[None, :, :]).sum(axis=2).argmin(axis=1)
    return pal[idx].reshape(arr.shape).astype("uint8")


# ---------------------------------------------------------------- 主流程
def process(src, name, frames, fps, once, out_dir, height, cell, colors, smooth=False):
    out_dir.mkdir(parents=True, exist_ok=True)
    img = Image.open(src).convert("RGB")
    rgb = np.asarray(img)
    mask = key_mask(rgb)
    if bbox(mask) is None:
        sys.exit("没有找到前景（背景色不是纯色？）")
    block = estimate_block(rgb, mask)
    print(f"{src}: {img.size}，估计像素块 ≈ {block}px")

    # 把整张图按帧切开（要求帧间有空隙，且大致等宽）
    W = img.width
    cells = []
    for i in range(frames):
        x0, x1 = round(i * W / frames), round((i + 1) * W / frames)
        sub_mask = np.zeros_like(mask)
        sub_mask[:, x0:x1] = mask[:, x0:x1]
        if bbox(sub_mask) is None:
            sys.exit(f"第 {i + 1} 帧是空的：请确认条带里确实有 {frames} 帧，且大致等距")
        cells.append(to_native(img, sub_mask, block))

    # 缩放比例：首次由基础姿势的身高决定，之后所有动画共用
    scale_file = out_dir / "scale.json"
    if scale_file.exists():
        scale = json.loads(scale_file.read_text())["scale"]
    else:
        scale = height / max(c[0].height for c in cells)
        scale_file.write_text(json.dumps({"scale": scale, "target_height": height, "block": block}, indent=2))
        print(f"首次处理：缩放比例 {scale:.4f}（角色高 {height}px）")

    # 调色板：首次由基础姿势生成，之后共用
    pal_file = out_dir / "palette.json"
    if pal_file.exists():
        palette = json.loads(pal_file.read_text())
    else:
        palette = build_palette(cells[0][0], cells[0][1], colors)
        pal_file.write_text(json.dumps(palette))
        print(f"首次处理：调色板 {len(palette)} 色")

    # 每帧：缩放 → 吸附调色板 → 硬 alpha → 按脚底/身体中心摆进格子
    centers = []
    scaled = []
    for rgb_n, m_n in cells:
        w, h = max(1, round(rgb_n.width * scale)), max(1, round(rgb_n.height * scale))
        if smooth:
            # 面积平均（只按前景像素加权，背景不参与）：更柔和，但会产生中间色杂点
            m_f = np.asarray(m_n, dtype=np.float32) / 255.0
            rgb_f = np.asarray(rgb_n, dtype=np.float32)
            mm = np.asarray(Image.fromarray(m_f, "F").resize((w, h), Image.BOX))
            chans = [np.asarray(Image.fromarray(rgb_f[..., c] * m_f, "F").resize((w, h), Image.BOX))
                     for c in range(3)]
            rgb_s = np.stack([ch / np.maximum(mm, 1e-3) for ch in chans], axis=2).clip(0, 255).astype("uint8")
            m_s = mm > 0.5
        else:
            # 默认：最近邻取样。保住原来的硬边和轮廓，最像真正的像素画
            rgb_s = np.asarray(rgb_n.resize((w, h), Image.NEAREST))
            m_s = np.asarray(m_n.resize((w, h), Image.NEAREST)) > 127
        rgb_s = snap(rgb_s, palette)
        scaled.append((rgb_s, m_s))
        b = bbox(m_s)
        centers.append((b[0] + b[2]) / 2.0)
    anchor_x = float(np.median(centers))

    strip = Image.new("RGBA", (cell * frames, cell), (0, 0, 0, 0))
    for i, (rgb_s, m_s) in enumerate(scaled):
        b = bbox(m_s)
        rgba = np.dstack([rgb_s, (m_s * 255).astype("uint8")])
        tile = Image.fromarray(rgba, "RGBA")
        ox = int(round(cell / 2 - anchor_x))              # 格内的水平偏移
        oy = cell - 4 - b[3]                              # 脚底线：距格子底部 4px
        left = max(0, -ox)                                # 超出格子左/右边界的部分裁掉
        right = min(tile.width, cell - ox)
        if right > left:
            strip.alpha_composite(tile.crop((left, 0, right, tile.height)), (i * cell + ox + left, max(0, oy)))
    out_png = out_dir / f"{name}.png"
    strip.save(out_png)

    anim_file = out_dir / "anim.json"
    anim = json.loads(anim_file.read_text()) if anim_file.exists() else {"cell": cell, "anims": {}}
    anim["cell"] = cell
    anim["anims"][name] = {"file": f"{name}.png", "frames": frames, "fps": fps, "loop": not once}
    anim_file.write_text(json.dumps(anim, ensure_ascii=False, indent=2))
    print(f"已写入 {out_png.relative_to(ROOT)}：{frames} 帧 × {cell}px，调色板 {len(palette)} 色")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("src")
    ap.add_argument("name", help="动画名：idle / walk / punch / palm / dash / hurt / death / ult")
    ap.add_argument("--frames", type=int, default=1)
    ap.add_argument("--fps", type=float, default=8)
    ap.add_argument("--once", action="store_true", help="只播放一次（出招、受击、倒下等）")
    ap.add_argument("--out", default=str(DEFAULT_OUT))
    ap.add_argument("--height", type=int, default=56, help="角色目标身高（像素），仅首次处理时生效")
    ap.add_argument("--cell", type=int, default=64)
    ap.add_argument("--colors", type=int, default=24)
    ap.add_argument("--smooth", action="store_true", help="用面积平均缩放（默认最近邻，更像像素画）")
    a = ap.parse_args()
    process(a.src, a.name, a.frames, a.fps, a.once, pathlib.Path(a.out), a.height, a.cell, a.colors, a.smooth)


if __name__ == "__main__":
    main()
