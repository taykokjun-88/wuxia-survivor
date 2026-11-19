#!/usr/bin/env python3
"""AI 出的黑底发光特效图 → 游戏用特效条带（assets/vfx/<id>.png）+ 登记到 assets/vfx/vfx.json。

依赖：pip install pillow numpy

用法：
  python3 tools/process_vfx.py strip 源图.jpg proj_wave --frames 4 --cell 96 --fps 12 --loop
  python3 tools/process_vfx.py strip 源图.jpg slash_fist --frames 5 --cell 192 --fps 24
  python3 tools/process_vfx.py strip 源图.jpg burst_quake --frames 7 --cell 256 --fps 20 --trim
  python3 tools/process_vfx.py list           # 看已登记的特效 / 还缺哪些

源图要求：纯黑底（#000000）的横向条带，N 帧等宽排开，特效在每格正中。处理方式：
  - 每格按等宽切开，整体等比缩放进 cell×cell（所有帧用同一个比例，保持帧与帧之间的大小关系）
  - 接近黑色的杂点清成纯黑（AI 出图的 JPEG 噪点），黑色同时变透明：alpha = 最亮通道（越亮越不透明），颜色还原成不预乘
  - 缩放用 LANCZOS（发光效果需要平滑）；游戏里用普通 alpha 混合绘制（背景是浅色宣纸，叠加混合会冲成白色），所以特效要用高饱和的颜色
  - --trim：先裁掉所有帧共同的空白再缩放，让对称的爆发类特效填满格子（以画面中心为原点对称地裁，不会丢掉原点）
  - --auto-split：按内容分帧。AI 出的条带每帧宽度 / 间距往往不一样，等分会切坏；这个模式把分界线放在最暗的谷底，
    各帧以自己的横向中心对齐、共用同一条垂直中线（所以特效的原点变成「内容中心」，刀光类可以再用 --forward 往前挪）
特效的约定（画在游戏里时）：格子正中心是原点；带方向的（弹体 / 刀光 / 冲刺拖尾）朝右。
"""
import argparse
import json
import pathlib
import sys

import numpy as np
from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = pathlib.Path(__import__("os").environ.get("VFX_OUT", ROOT / "assets" / "vfx"))   # VFX_OUT：测试时指向临时目录

# 需要的全部特效：id → (说明, 格子, 帧数, fps, 是否循环)
CATALOG = {
    "proj_wave": ("降龙十八掌：龙形掌风（弹体，朝右）", 96, 4, 12, True),
    "proj_palm": ("天山六阳掌：掌印（弹体，朝右）", 64, 4, 12, True),
    "proj_bolt": ("八荒六合功：拳气（弹体，朝右）", 48, 4, 14, True),
    "proj_finger": ("一阳指：指劲（弹体，朝右）", 48, 4, 14, True),
    "slash_fist": ("太祖长拳：拳风弧光（朝右）", 192, 5, 24, False),
    "slash_heavy": ("太祖长拳末拳 / 大金刚拳：重击弧光（朝右）", 192, 6, 22, False),
    "burst_wind": ("落英神剑掌：环身掌风", 256, 6, 22, False),
    "burst_quake": ("七伤拳：落点冲击", 256, 7, 20, False),
    "burst_gold": ("点穴连锁：金色爆炸", 256, 6, 20, False),
    "ring_taiji": ("乾坤大挪移：化解反击", 256, 6, 18, False),
    "ring_qinggong": ("轻功落点冲击", 256, 6, 22, False),
    "burst_ult": ("真气爆发（大招）", 256, 8, 16, False),
    "burst_break": ("破罡（Boss 罡气被打破）", 256, 7, 16, False),
    "halo_empower": ("催动光晕（出手时脚下闪一下）", 128, 4, 16, False),
    "zone_crack": ("七伤拳强化：裂地区域（循环）", 256, 4, 8, True),
    "zone_vortex": ("落英神剑掌强化：旋涡区域（循环）", 256, 6, 12, True),
    "hit_impact": ("普通命中火花", 64, 4, 20, False),
    "hit_crit": ("暴击命中火花", 96, 5, 20, False),
    "trail_dash": ("轻功冲刺拖尾（朝右）", 96, 4, 16, False),
    "death_puff": ("敌人倒下的烟尘", 96, 5, 14, False),
}


def load_cfg() -> dict:
    p = OUT / "vfx.json"
    if p.exists():
        return json.loads(p.read_text(encoding="utf-8"))
    return {"cell_note": "由 tools/process_vfx.py 生成", "effects": {}}


def _boundaries(occ: np.ndarray, n: int) -> tuple:
    """把横向分成 n 段：每条分界线取在「理想等分位置附近最暗的谷底」。返回 (分界线列表, 代价)。"""
    w = len(occ)
    fw = w / n
    sm = np.convolve(occ.astype(float), np.ones(5) / 5.0, mode="same")
    cuts, cost = [0], 0.0
    for i in range(1, n):
        c = int(round(i * fw))
        lo, hi = max(cuts[-1] + 4, int(c - 0.38 * fw)), min(w - 4, int(c + 0.38 * fw))
        if hi <= lo:
            cuts.append(c)
            continue
        seg = sm[lo:hi]
        m = seg.min()
        cand = np.where(seg <= m + 1e-9)[0] + lo
        j = int(cand[np.argmin(np.abs(cand - c))])      # 并列最暗时取最靠近等分位置的
        cuts.append(j)
        cost += m
    cuts.append(w)
    return cuts, cost


def auto_split(arr: np.ndarray, floor: int, n: int, pad_frac: float) -> list:
    """按内容分帧：AI 出的条带每帧宽度、间距往往不一样，等分会切坏、按间隙切又会把贴在一起的帧合并。
    做法：n 帧 → 每条分界线放在附近最暗的谷底 → 每帧以自己内容的横向中心对齐，所有帧共用同一条垂直中线
    （地面类爆发的底边因此保持一致）。完全空白的帧会丢掉。返回等大的方形帧列表。"""
    h, w, _ = arr.shape
    lit = arr.max(axis=2) > max(floor, 22)
    occ = lit.sum(axis=0)
    if occ.sum() == 0:
        sys.exit("源图里没有找到特效")
    cuts, _ = _boundaries(occ, n)
    ys = np.where(lit.any(axis=1))[0]
    cy = (ys.min() + ys.max()) / 2
    half_h = (ys.max() - ys.min()) / 2
    boxes = []
    for a, b in zip(cuts[:-1], cuts[1:]):
        sub = lit[:, a:b]
        if sub.sum() < 25:
            continue
        xs = np.where(sub.any(axis=0))[0]
        boxes.append((a, b, a + xs.min(), a + xs.max() + 1))
    half_w = max((x1 - x0) / 2 for _, _, x0, x1 in boxes)
    side = int(max(half_h, half_w) * 2 * (1 + pad_frac)) + 2
    out = []
    for a, b, x0c, x1c in boxes:
        cx = (x0c + x1c) / 2
        x0, y0 = int(round(cx - side / 2)), int(round(cy - side / 2))
        canvas = np.zeros((side, side, 3), dtype=np.uint8)
        sx0, sy0 = max(x0, 0), max(y0, 0)
        sx1, sy1 = min(x0 + side, w), min(y0 + side, h)
        canvas[sy0 - y0:sy1 - y0, sx0 - x0:sx1 - x0] = arr[sy0:sy1, sx0:sx1]
        keep = np.zeros(side, dtype=bool)                   # 只保留本帧范围内的内容，相邻帧漏进来的部分清掉
        keep[max(0, a - x0):min(side, b - x0)] = True
        canvas[:, ~keep] = 0
        out.append(canvas)
    return out


def process(src: str, fx_id: str, frames: int, cell: int, fps: float, loop: bool, trim: bool, floor: int, world_size: float = 0.0,
            auto: bool = False, frames_given: bool = False, extra: dict = None) -> None:
    img = Image.open(src).convert("RGB")
    arr = np.asarray(img).astype(np.uint8)
    h, w, _ = arr.shape
    if auto:
        cells = auto_split(arr, floor, frames, 0.06)
        frames = len(cells)
        h, fw = cells[0].shape[:2]
        trim = False
    else:
        fw = w // frames
        if fw < 8 or h < 8:
            sys.exit("源图太小")
        cells = [arr[:, i * fw:(i + 1) * fw] for i in range(frames)]
    # 去噪：整体最亮通道低于 floor 的像素清成纯黑
    cells = [np.ascontiguousarray(c) for c in cells]
    for c in cells:
        c[c.max(axis=2) < floor] = 0
    if trim:
        union = np.zeros((h, fw), dtype=bool)
        for c in cells:
            union |= c.max(axis=2) > 0
        ys, xs = np.where(union)
        if len(xs):
            x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
            # 以画面中心为原点对称地裁，保持特效居中
            cx, cy = fw / 2, h / 2
            rx = max(cx - x0, x1 - cx)
            ry = max(cy - y0, y1 - cy)
            r = int(max(rx, ry) + 2)
            x0, x1, y0, y1 = int(cx - r), int(cx + r), int(cy - r), int(cy + r)
            cells = [np.pad(c, ((r, r), (r, r), (0, 0)))[y0 + r:y1 + r, x0 + r:x1 + r] for c in cells]
            h, fw = cells[0].shape[:2]
    side = max(h, fw)
    out = Image.new("RGBA", (cell * frames, cell), (0, 0, 0, 0))
    for i, c in enumerate(cells):
        sq = np.zeros((side, side, 3), dtype=np.uint8)
        oy, ox = (side - c.shape[0]) // 2, (side - c.shape[1]) // 2
        sq[oy:oy + c.shape[0], ox:ox + c.shape[1]] = c
        small = np.asarray(Image.fromarray(sq).resize((cell, cell), Image.LANCZOS)).astype(np.float32)
        a = small.max(axis=2)
        a = np.where(a < floor * 0.6, 0.0, a)
        safe = np.maximum(a, 1.0)[..., None]
        rgb = np.clip(small * 255.0 / safe, 0, 255)          # 颜色还原成不预乘
        rgba = np.dstack([rgb, a]).astype(np.uint8)
        out.paste(Image.fromarray(rgba, "RGBA"), (i * cell, 0))
    OUT.mkdir(parents=True, exist_ok=True)
    out.save(OUT / f"{fx_id}.png")
    cfg = load_cfg()
    entry = {"file": f"{fx_id}.png", "frames": frames, "fps": fps, "cell": cell, "loop": loop}
    old = cfg["effects"].get(fx_id, {})
    ws = world_size or float(old.get("world_size", 0.0))
    if ws > 0:
        entry["world_size"] = ws
    for k, v in (extra or {}).items():
        if v is not None:
            entry[k] = v
    for k in ("scale", "forward"):      # 重新处理时保留手工调过的值
        if k not in entry and k in old:
            entry[k] = old[k]
    cfg["effects"][fx_id] = entry
    (OUT / "vfx.json").write_text(json.dumps(cfg, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"已写入 assets/vfx/{fx_id}.png：{frames} 帧 × {cell}px，{fps} fps，{'循环' if loop else '一次性'}")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("strip")
    s.add_argument("src")
    s.add_argument("id", help="特效 id，见 list")
    s.add_argument("--frames", type=int)
    s.add_argument("--cell", type=int)
    s.add_argument("--fps", type=float)
    s.add_argument("--loop", action="store_true", default=None)
    s.add_argument("--once", action="store_true", help="一次性（默认按目录里的建议值）")
    s.add_argument("--trim", action="store_true")
    s.add_argument("--floor", type=int, default=18, help="低于这个亮度的像素当作黑底（默认 18）")
    s.add_argument("--auto-split", action="store_true", help="按内容分帧（条带每帧宽度 / 间距不均匀时用）。帧数请用 --frames N 指定（条带里数一数有几个，末尾几乎看不见的淡帧也算）")
    s.add_argument("--scale", type=float, default=None, help="游戏里的额外缩放倍数（相对于代码算出的尺寸）")
    s.add_argument("--forward", type=float, default=None, help="沿朝向向前偏移（占特效边长的比例；刀光 / 弧光用）")
    s.add_argument("--world-size", type=float, default=0.0, help="整张格子在游戏里的边长（像素）；不填则沿用已登记的值，仍没有就按招式半径")
    sub.add_parser("list")
    a = ap.parse_args()
    if a.cmd == "list":
        have = load_cfg()["effects"]
        for k, (desc, cell, frames, fps, loop) in CATALOG.items():
            print(f"{'✔' if k in have else '·'} {k:14s} {cell:3d}px × {frames} 帧  {fps:>4.0f}fps  {'循环' if loop else '一次'}  {desc}")
        print(f"\n已完成 {sum(1 for k in CATALOG if k in have)} / {len(CATALOG)}")
        return
    desc, cell, frames, fps, loop = CATALOG.get(a.id, ("", 128, 4, 16, False))
    loop = True if a.loop else (False if a.once else loop)
    process(a.src, a.id, a.frames or frames, a.cell or cell, a.fps or fps, loop, a.trim, a.floor, a.world_size, a.auto_split, a.frames is not None, {"scale": a.scale, "forward": a.forward})


if __name__ == "__main__":
    main()
