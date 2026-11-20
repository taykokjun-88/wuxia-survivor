#!/usr/bin/env python3
"""光明顶地图素材：4 张地面（1024² → 64² 无缝瓦片）+ 障碍 / 装饰物件（合并 meta，障碍标 block）+ 选关海报。
源图在 assets/maps/guangming/source/。用法：python3 tools/make_guangming_assets.py
"""
import json
import pathlib
import shutil
import subprocess
import sys
import tempfile

import numpy as np
from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
M = ROOT / "assets/maps/guangming"
SRC = M / "source"
BLOCK = {"wall_seg", "wall_corner", "column_fallen", "pillar_broken", "rock_pile", "chevaux", "cauldron", "lion_gate"}
GROUND = ["ground_stone", "ground_snow", "ground_scorched", "ground_cracked"]   # 0 基底 / 1 雪斑 / 2 焦土 / 3 裂纹石板


def seamless(img: Image.Image) -> Image.Image:
    a = np.asarray(img).astype(np.float32)
    n = a.shape[0]
    h = n // 2
    rolled = np.roll(np.roll(a, h, 0), h, 1)
    t = np.abs(np.linspace(-1, 1, n))                      # 中心 0，边缘 1
    w = np.clip(1.0 - np.minimum(t[:, None], t[None, :]) * 0 - np.maximum(t[:, None], t[None, :]), 0, 1)
    # w 在中心为 1、边缘为 0：中心用原图，边缘用错位图（错位图的边缘是原图的中心，天然连续）
    out = a * w[..., None] + rolled * (1 - w[..., None])
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8))


def main() -> None:
    for i, n in enumerate(GROUND):
        im = Image.open(SRC / f"{n}.jpg").convert("RGB")
        c = int(im.width * 0.08)
        im = im.crop((c, c, im.width - c, im.height - c)).resize((128, 128), Image.LANCZOS)
        im = seamless(im).resize((64, 64), Image.LANCZOS)
        im.save(M / f"ground_{i}.png")
    tmp = pathlib.Path(tempfile.mkdtemp())
    (tmp / "w").mkdir()
    (tmp / "p").mkdir()
    g = str(ROOT / "tools/process_art_grid.py")
    subprocess.check_call([sys.executable, g, "props", str(SRC / "walls_ruins.jpg"), "--cols", "4", "--rows", "2", "--ids",
                           "wall_seg,wall_corner,column_fallen,pillar_broken,rock_pile,chevaux,cauldron,lion_gate", "--out", str(tmp / "w"), "--scale", "0.4"])
    subprocess.check_call([sys.executable, g, "props", str(SRC / "props_destructibles.jpg"), "--cols", "4", "--rows", "2", "--ids",
                           "brazier,weapon_rack,crate,war_banner,pine,stele,censer,lantern", "--out", str(tmp / "p"), "--scale", "0.3"])
    out = M / "props"
    shutil.rmtree(out, ignore_errors=True)
    out.mkdir(parents=True)
    meta = {}
    for d in ("w", "p"):
        m = json.loads((tmp / d / "meta.json").read_text(encoding="utf-8"))
        for k, v in m.items():
            shutil.copy(tmp / d / v["file"], out / v["file"])
            if k in BLOCK:
                v["block"] = True
            meta[k] = v
    (out / "meta.json").write_text(json.dumps(meta, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    Image.open(SRC / "poster.jpg").convert("RGB").save(M / "stage_banner.jpg", quality=88)
    print("done")


if __name__ == "__main__":
    main()
