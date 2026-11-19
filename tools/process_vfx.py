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
  - --trim：先裁掉所有帧共同的空白再缩放，让对称的爆发类特效填满格子（带方向的特效不要用，会丢掉原点）
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
    "proj_wave": ("裂岳掌：龙形掌风（弹体，朝右）", 96, 4, 12, True),
    "proj_palm": ("流云掌：掌印（弹体，朝右）", 64, 4, 12, True),
    "proj_bolt": ("八荒拳：拳气（弹体，朝右）", 48, 4, 14, True),
    "proj_finger": ("点穴指：指劲（弹体，朝右）", 48, 4, 14, True),
    "slash_fist": ("连环拳：拳风弧光（朝右）", 192, 5, 24, False),
    "slash_heavy": ("连环拳末拳 / 金刚拳：重击弧光（朝右）", 192, 6, 22, False),
    "burst_wind": ("回风掌：环身掌风", 256, 6, 22, False),
    "burst_quake": ("撼地拳：落点冲击", 256, 7, 20, False),
    "burst_gold": ("点穴连锁：金色爆炸", 256, 6, 20, False),
    "ring_taiji": ("太极劲：化解反击", 256, 6, 18, False),
    "ring_qinggong": ("轻功落点冲击", 256, 6, 22, False),
    "burst_ult": ("真气爆发（大招）", 256, 8, 16, False),
    "burst_break": ("破罡（Boss 罡气被打破）", 256, 7, 16, False),
    "halo_empower": ("催动光晕（出手时脚下闪一下）", 128, 4, 16, False),
    "zone_crack": ("撼地拳强化：裂地区域（循环）", 256, 4, 8, True),
    "zone_vortex": ("回风掌强化：旋涡区域（循环）", 256, 6, 12, True),
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


def process(src: str, fx_id: str, frames: int, cell: int, fps: float, loop: bool, trim: bool, floor: int, world_size: float = 0.0) -> None:
    img = Image.open(src).convert("RGB")
    arr = np.asarray(img).astype(np.uint8)
    h, w, _ = arr.shape
    fw = w // frames
    if fw < 8 or h < 8:
        sys.exit("源图太小")
    cells = [arr[:, i * fw:(i + 1) * fw] for i in range(frames)]
    # 去噪：整体最亮通道低于 floor 的像素清成纯黑
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
    process(a.src, a.id, a.frames or frames, a.cell or cell, a.fps or fps, loop, a.trim, a.floor, a.world_size)


if __name__ == "__main__":
    main()
