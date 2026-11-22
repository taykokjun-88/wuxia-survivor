#!/usr/bin/env python3
"""第 3 关·桃花岛地图素材：4 张地面瓦片 + 障碍 / 装饰物件 + 选关海报 + 4 位 Boss 头像。
源图在 assets/source/taohua_v1/。用法：python3 tools/make_taohua_assets.py"""
import json
import pathlib
import shutil
import subprocess
import sys
import tempfile

import numpy as np
from PIL import Image

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from make_guangming_assets import seamless  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parent.parent
M = ROOT / "assets/maps/taohua"
SRC1 = ROOT / "assets/source/taohua_v1"
SRC2 = ROOT / "assets/source/taohua_v2"          # 第二版（修改过的）优先


def src(name):
    return SRC2 / name if (SRC2 / name).exists() else SRC1 / name

WALLS = ["peach_tree", "taihu_rock", "bamboo", "stone_pillar", "rockery", "pavilion", "railing", "flag_base"]
PROPS = ["herb_bed", "stone_table", "stone_lantern", "petal_pile", "basket", "target", "guqin", "flute_stand"]
GROUND = ["grass", "path", "moss", "sand"]   # 0 草地（主）/ 1 青石小径 / 2 苔石 / 3 白沙


def main() -> None:
    M.mkdir(parents=True, exist_ok=True)
    for i, n in enumerate(GROUND):
        im = Image.open(src(f"stage3_ground_{n}.jpg")).convert("RGB")
        im = im.resize((128, 128), Image.LANCZOS)           # 源图本身无缝，直接缩小；再做一次边缘融合保险
        im = seamless(im).resize((64, 64), Image.LANCZOS)
        im.save(M / f"ground_{i}.png")
    tmp = pathlib.Path(tempfile.mkdtemp())
    (tmp / "w").mkdir()
    (tmp / "p").mkdir()
    g = str(ROOT / "tools/process_art_grid.py")
    subprocess.check_call([sys.executable, g, "props", str(src("stage3_walls_ruins.png")), "--cols", "4", "--rows", "2", "--ids", ",".join(WALLS), "--out", str(tmp / "w"), "--scale", "0.4"])
    subprocess.check_call([sys.executable, g, "props", str(src("stage3_props.png")), "--cols", "4", "--rows", "2", "--ids", ",".join(PROPS), "--out", str(tmp / "p"), "--scale", "0.3"])
    out = M / "props"
    shutil.rmtree(out, ignore_errors=True)
    out.mkdir(parents=True)
    meta = {}
    for d in ("w", "p"):
        m = json.loads((tmp / d / "meta.json").read_text(encoding="utf-8"))
        for k, v in m.items():
            shutil.copy(tmp / d / v["file"], out / v["file"])
            if k in WALLS:
                v["block"] = True
            meta[k] = v
    (out / "meta.json").write_text(json.dumps(meta, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    Image.open(src("stage_taohua_bg.jpg")).convert("RGB").resize((1376, 768), Image.LANCZOS).save(M / "stage_banner.jpg", quality=88)
    for k, pk in [("th_mini_1", "lu"), ("th_mini_2", "wu"), ("th_mini_3", "zhou"), ("th_boss", "huang")]:   # 头像：竖版立绘取上半身方形
        f = SRC2 / f"th_portrait_{pk}.jpg"
        im = Image.open(f if f.exists() else SRC1 / f"{k}_portrait.jpg").convert("RGB")
        im.crop((0, 0, im.width, im.width)).resize((384, 384), Image.LANCZOS).save(M / f"portrait_{k}.png")
    print("done")


if __name__ == "__main__":
    main()
