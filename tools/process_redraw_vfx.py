#!/usr/bin/env python3
"""重置画面计划书 2~6：Gemini 的高清特效条带（RGBA、4 帧、每帧 256×256）→ assets/vfx/<名字>.png + 更新 vfx.json。

源图：assets/source/redraw_NN/<名字>.png（已经是透明底，不用再抠背景）
处理：按 world_size 选择输出格大小（约 world_size×1.5，最大 256，最小 96），预乘 alpha 后 LANCZOS 缩小，避免边缘发黑；
      vfx.json 里 cell / frames 更新为新值；一次性特效的 fps 重新计算，保持原来的总时长不变。
用法：python3 tools/process_redraw_vfx.py [redraw_02 ...]   （默认处理 assets/source/redraw_0* 下所有）
"""
import json
import pathlib
import sys

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC_ROOT = ROOT / "assets/source"
VFX = ROOT / "assets/vfx"
SRC_CELL = 256


def pick_cell(world_size: float) -> int:
    if world_size <= 0:
        return 192
    c = int(round(world_size * 1.5 / 8.0)) * 8
    return max(96, min(256, c))


def main(dirs: list) -> None:
    meta_path = VFX / "vfx.json"
    meta = json.loads(meta_path.read_text(encoding="utf-8"))
    effects = meta["effects"]
    for d in dirs:
        for f in sorted((SRC_ROOT / d).glob("*.png")):
            name = f.stem
            if name not in effects:
                print("跳过（vfx.json 里没有）：", name)
                continue
            e = effects[name]
            im = Image.open(f).convert("RGBA")
            n = im.width // SRC_CELL
            cell = pick_cell(float(e.get("world_size", 0.0)))
            strip = Image.new("RGBA", (cell * n, cell), (0, 0, 0, 0))
            for i in range(n):
                piece = im.crop((i * SRC_CELL, 0, (i + 1) * SRC_CELL, SRC_CELL)).convert("RGBa")
                strip.paste(piece.resize((cell, cell), Image.LANCZOS).convert("RGBA"), (i * cell, 0))
            strip.save(VFX / e["file"])
            old_frames = int(e["frames"])
            if not bool(e.get("loop", False)):
                e["fps"] = round(n * float(e["fps"]) / old_frames, 2)   # 保持总时长
            e["frames"] = n
            e["cell"] = cell
            print(f"{name}: {n} 帧 × {cell}px")
    meta_path.write_text(json.dumps(meta, ensure_ascii=False, indent=1), encoding="utf-8")


if __name__ == "__main__":
    dirs = sys.argv[1:] or sorted(p.name for p in SRC_ROOT.glob("redraw_0*") if p.name != "redraw_01_v2" and p.name != "redraw_01")
    main(dirs)
