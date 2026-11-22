#!/usr/bin/env python3
"""重置画面计划书 1：Gemini 的 RO 式 Q 版主角序列帧（256×256 格、纯洋红底）→ 游戏用精灵条带。

源图：assets/source/redraw_01_v2/<fist|sword|blade|spear>/<动作>.png
输出：assets/sprites/<player|sword|blade|spear>/<动作>.png（每格 CELL×CELL，透明底）+ anim.json

处理要点：
  - 洋红底按「洋红程度」做软透明，再按 obs = a*C + (1-a)*M 反推真实颜色（去洋红边）
  - 脚下的粉紫椭圆阴影、零散小碎点去掉
  - 预乘 alpha 后用 LANCZOS 缩小（256 → CELL），保持柔和手绘质感（不做调色板量化）
  - 动画时长保持和旧版一样（帧数变多，fps 相应提高），避免影响出招 / 大招的硬直时间
  - anim.json 新增 world（绘制时的世界尺寸）与 foot（脚底距格子底边，纹理像素）
用法：python3 tools/process_redraw_sprites.py
"""
import json
import pathlib

import numpy as np
from PIL import Image
from scipy import ndimage as ndi

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "assets/source/redraw_01_v2"
OUT = ROOT / "assets/sprites"
DIRS = {"fist": "player", "sword": "sword", "blade": "blade", "spear": "spear"}
SRC_CELL = 256
CELL = 156                 # 输出格：角色 120px × 156/256 ≈ 73px，正好等于「旧 56px × player_zoom 1.3」
WORLD = 120                # 绘制时的世界尺寸；player_zoom 1.3 → 156，和纹理 1:1，不再缩放
SRC_FOOT = 16              # 源图里脚底距格子底边
FOOT = round(SRC_FOOT * CELL / SRC_CELL)
EIGHT = np.ones((3, 3), dtype=bool)
MAG = np.array([255.0, 0.0, 255.0])


def key_alpha(rgb: np.ndarray) -> np.ndarray:
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    m = np.minimum(r - g, b - g)
    near = np.abs(r - b) < 90
    a = np.clip(1.0 - (m - 14.0) / (48.0 - 14.0), 0.0, 1.0)
    a = np.where(near, a, 1.0)
    return a


def process_cell(cell: np.ndarray) -> np.ndarray:
    rgb = cell.astype(float)
    a = key_alpha(rgb)
    # 反推真实颜色
    c = (rgb - (1.0 - a)[..., None] * MAG) / np.maximum(a, 1e-3)[..., None]
    c = np.clip(c, 0, 255)
    # 碎点：面积很小且离主体较远的连通块去掉
    mask = a > 0.5
    lab, n = ndi.label(ndi.binary_dilation(mask, iterations=2), structure=EIGHT)
    if n > 1:
        sizes = ndi.sum(mask, lab, index=range(1, n + 1))
        main = int(np.argmax(sizes)) + 1
        for i, s in enumerate(sizes, start=1):
            if i != main and s < 40:
                a[(lab == i)] = 0.0
    out = np.zeros(cell.shape[:2] + (4,), np.uint8)
    out[..., :3] = c.astype(np.uint8)
    out[..., 3] = (a * 255).astype(np.uint8)
    return out


def main() -> None:
    for sdir, odir in DIRS.items():
        path = OUT / odir / "anim.json"
        old = json.loads(path.read_text(encoding="utf-8"))
        old_anims = old["anims"]
        anims = {}
        for f in sorted((SRC / sdir).glob("*.png")):
            name = f.stem
            im = Image.open(f).convert("RGB")
            n = im.width // SRC_CELL
            arr = np.array(im)
            strip = Image.new("RGBA", (CELL * n, CELL), (0, 0, 0, 0))
            for i in range(n):
                cell = process_cell(arr[:, i * SRC_CELL:(i + 1) * SRC_CELL])
                pm = Image.fromarray(cell, "RGBA").convert("RGBa").resize((CELL, CELL), Image.LANCZOS).convert("RGBA")
                strip.paste(pm, (i * CELL, 0))
            strip.save(OUT / odir / f"{name}.png")
            o = old_anims.get(name)
            if o is not None:
                dur = float(o["frames"]) / float(o["fps"])
                fps = round(n / dur, 2)
                loop = bool(o.get("loop", True))
            else:
                fps, loop = 12.0, False
            anims[name] = {"file": f"{name}.png", "frames": n, "fps": fps, "loop": loop}
        # 旧动画里新版没有的，保留旧条目会导致尺寸不符，所以只保留新版有的
        data = {"cell": CELL, "world": WORLD, "foot": FOOT, "anims": anims}
        path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
        print(odir, "→", len(anims), "个动画：", ", ".join(f"{k}{v['frames']}" for k, v in anims.items()))


if __name__ == "__main__":
    main()
