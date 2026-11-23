#!/usr/bin/env python3
"""重置画面计划书 10：Gemini 的小镇 / 地图 / 拾取物（RGBA）→ 游戏目录。

输入（解压后的目录，参数传入）：
  <root>/a/pickups/*.png  <root>/a/town/{hero,hero_blade,hero_sword,hero_spear}/hero_{down,side,up}.png（4 帧 1024×256）
  <root>/a/town/npc/*.png  <root>/a/town/buildings/*.png
  <root>/b/maps/<black_wind|guangming>/{ground_*.png, props/*.png}  <root>/c/maps/taohua/...
处理：
  - 静态图：裁到不透明范围，贴图保留高分辨率（长边 ≤ cap），meta 里的 w/h 是「世界尺寸」，沿用旧素材的高度（怪物 / 道具大小不变）
  - 地面瓦片：缩到 128×128（TILE=128）
  - 小镇主角条带：每格去碎块、缩到 192，meta 里 w/h=格，scale=世界缩放，foot=脚底距格底，fh=世界身高 60
  - 建筑：世界宽度沿用旧值，高度按新图比例；没有牌匾的建筑 plaque=true（运行时画一块木牌托住店名）
"""
import json
import pathlib
import sys

import numpy as np
from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
from sprite_clean import defragment

AS = ROOT / "assets"


def trim(im: Image.Image, pad: int = 2) -> Image.Image:
    a = np.array(im.convert("RGBA"))[..., 3]
    ys, xs = np.where(a > 12)
    if len(xs) == 0:
        return im
    return im.crop((max(0, xs.min() - pad), max(0, ys.min() - pad), min(im.width, xs.max() + 1 + pad), min(im.height, ys.max() + 1 + pad)))


def save_hi(im: Image.Image, out: pathlib.Path, cap: int) -> Image.Image:
    im = im.convert("RGBA")
    k = min(1.0, cap / max(im.size))
    if k < 1.0:
        im = im.convert("RGBa").resize((max(1, round(im.width * k)), max(1, round(im.height * k))), Image.LANCZOS).convert("RGBA")
    im.save(out)
    return im


def static_set(src: pathlib.Path, dst: pathlib.Path, meta_path: pathlib.Path, cap: int, keep_height: bool = True) -> None:
    meta = json.loads(meta_path.read_text(encoding="utf-8"))
    for f in sorted(src.glob("*.png")):
        id_ = f.stem
        if id_ not in meta:
            print("  跳过（旧 meta 里没有）：", id_)
            continue
        im = trim(Image.open(f))
        old = meta[id_]
        ow, oh = float(old["w"]), float(old["h"])
        asp = im.width / im.height
        if keep_height:
            h = oh
            w = round(h * asp)
        else:
            w = ow
            h = round(w / asp)
        save_hi(im, dst / f"{id_}.png", cap)
        old["w"], old["h"] = int(w), int(h)
        meta[id_] = old
        print(f"  {id_}: 世界 {int(w)}×{int(h)}，贴图 {im.size}")
    meta_path.write_text(json.dumps(meta, ensure_ascii=False, indent=1), encoding="utf-8")


def ground(src: pathlib.Path, dst: pathlib.Path) -> None:
    for f in sorted(src.glob("ground_*.png")):
        im = Image.open(f).convert("RGB").resize((128, 128), Image.LANCZOS)
        im.save(dst / f.name)
    print("  地面瓦片", len(list(src.glob("ground_*.png"))), "张 → 128×128")


def hero_strips(src: pathlib.Path, dst: pathlib.Path) -> None:
    meta_p = dst / "meta.json"
    meta = json.loads(meta_p.read_text(encoding="utf-8"))
    for f in sorted(src.glob("hero_*.png")):
        id_ = f.stem
        im = np.array(Image.open(f).convert("RGBA"))
        n = im.shape[1] // 256
        cell = 192
        k = cell / 256.0
        figs = []
        strip = Image.new("RGBA", (cell * n, cell), (0, 0, 0, 0))
        for i in range(n):
            c, _ = defragment(im[:, i * 256:(i + 1) * 256].copy(), gap=5, ramp=0)
            ys = np.where((c[..., 3] > 40).any(axis=1))[0]
            if len(ys):
                figs.append(int(ys.max() - ys.min()))
            pm = Image.fromarray(c, "RGBA").convert("RGBa").resize((cell, cell), Image.LANCZOS).convert("RGBA")
            strip.paste(pm, (i * cell, 0))
        strip.save(dst / f"{id_}.png")
        fig = float(np.median(figs)) * k if figs else cell * 0.47
        fh = 60.0
        old = meta.get(id_, {"fps": 8.0})
        meta[id_] = {"file": f"{id_}.png", "frames": n, "fps": float(old.get("fps", 8.0)), "w": cell, "h": cell, "scale": round(fh / fig, 4), "foot": round(16 * k), "fh": fh}
    meta_p.write_text(json.dumps(meta, ensure_ascii=False, indent=1), encoding="utf-8")
    print("  主角条带", dst.name)


# 店名位置（占建筑世界宽高的比例：x, y, 宽度占比）和是否需要运行时画木牌（素材里没有现成的牌匾时 plaque=True）
SIGNS = {
    "clerk": (0.46, 0.20, 0.30, True),
    "herbalist": (0.41, 0.27, 0.22, False),
    "innkeeper": (0.50, 0.46, 0.28, True),
    "master": (0.38, 0.38, 0.24, False),
    "sage": (0.74, 0.30, 0.24, True),
    "smith": (0.44, 0.43, 0.30, True),
}


def place_signs() -> None:
    p = AS / "town/buildings/meta.json"
    meta = json.loads(p.read_text(encoding="utf-8"))
    for id_, (fx, fy, fw, pl) in SIGNS.items():
        if id_ in meta:
            w, h = float(meta[id_]["w"]), float(meta[id_]["h"])
            meta[id_]["sign"] = [round(w * fx), round(h * fy), round(w * fw)]
            meta[id_]["plaque"] = pl
    p.write_text(json.dumps(meta, ensure_ascii=False, indent=1), encoding="utf-8")


def phase11(root: pathlib.Path) -> None:
    """计划书 11：无缝地面瓦片（三张地图 + 小镇）与小镇装饰（树 / 灯笼柱 / 水井）。源：assets/source/redraw_11/"""
    for m in ("black_wind", "guangming", "taohua"):
        d = root / "maps" / m
        if d.exists():
            ground(d, AS / "maps" / m)
    t = root / "town"
    if not t.exists():
        return
    town_dir = AS / "maps" / "town"
    town_dir.mkdir(parents=True, exist_ok=True)
    for i in range(4):
        f = t / f"town_ground_{i}.png"
        if f.exists():
            Image.open(f).convert("RGB").resize((128, 128), Image.LANCZOS).save(town_dir / f"ground_{i}.png")
    deco = AS / "town" / "deco"
    deco.mkdir(parents=True, exist_ok=True)
    meta = {}
    for id_, wh in (("tree_a", 104), ("tree_b", 104), ("tree_c", 104), ("lamp", 78), ("well", 104)):      # 世界高度（树 / 灯笼柱：脚底在 y 原点）
        f = t / f"{id_}.png"
        if not f.exists():
            continue
        im = trim(Image.open(f))
        save_hi(im, deco / f"{id_}.png", 256)
        meta[id_] = {"file": f"{id_}.png", "w": round(wh * im.width / im.height), "h": wh}
        print(f"  {id_}: 世界 {meta[id_]['w']}×{wh}")
    (deco / "meta.json").write_text(json.dumps(meta, ensure_ascii=False, indent=1), encoding="utf-8")


def main(root: str) -> None:
    r = pathlib.Path(root)
    print("拾取物")
    static_set(r / "a/pickups", AS / "pickups", AS / "pickups/meta.json", 160)
    print("小镇 NPC")
    static_set(r / "a/town/npc", AS / "town/npc", AS / "town/npc/meta.json", 192)
    print("建筑")
    static_set(r / "a/town/buildings", AS / "town/buildings", AS / "town/buildings/meta.json", 512, keep_height=False)
    place_signs()
    for d in ("hero", "hero_blade", "hero_sword", "hero_spear"):
        print("小镇主角", d)
        hero_strips(r / "a/town" / d, AS / "town" / d)
    for grp, maps in (("b", ("black_wind", "guangming")), ("c", ("taohua",))):
        for m in maps:
            print("地图", m)
            ground(r / grp / "maps" / m, AS / "maps" / m)
            static_set(r / grp / "maps" / m / "props", AS / "maps" / m / "props", AS / "maps" / m / "props/meta.json", 256)


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "phase11":
        phase11(ROOT / "assets/source/redraw_11")
    else:
        main(sys.argv[1] if len(sys.argv) > 1 else "/tmp/claude-0/z")
