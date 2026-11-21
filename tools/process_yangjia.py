#!/usr/bin/env python3
"""把 Gemini 给的杨家将 / 四职业立绘等素材（assets/source/yangjiajiang/*.webp）处理成游戏用的文件。
用法：python3 tools/process_yangjia.py   （只处理「简单类」：立绘、选人全身像、胜败图、天赋背景、技能图标、武器图标）
精灵 / 特效 / 小镇精灵另有处理脚本。"""
import pathlib
import numpy as np
from PIL import Image, ImageFilter

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "assets" / "source" / "yangjiajiang"


def load(name):
    return Image.open(SRC / f"{name}.webp").convert("RGB")


def magenta_alpha(im, lo=115, hi=175):
    a = np.array(im).astype(float)
    dist = np.sqrt((255 - a[..., 0]) ** 2 + a[..., 1] ** 2 + (255 - a[..., 2]) ** 2)
    return np.clip((dist - lo) / (hi - lo), 0.0, 1.0)


def to_rgba(im):
    """去洋红底：软 alpha + 边缘去色溢（把边缘像素里混进来的洋红去掉），再把 alpha 收 1 像素"""
    al = magenta_alpha(im)
    a = np.array(im).astype(float)
    solid = (al > 0.5).astype(np.uint8) * 255
    core = np.array(Image.fromarray(solid).filter(ImageFilter.MinFilter(3))) > 0       # 内部（腐蚀 1 像素）
    edge = (al > 0.0) & ~core
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    spill = np.minimum(r, b) - g
    spill = np.where(edge & (spill > 0), spill, 0.0)
    a[..., 0] = np.clip(r - spill * 0.85, 0, 255)
    a[..., 2] = np.clip(b - spill * 0.85, 0, 255)
    alpha = np.where(core, 255.0, np.where(edge, al * 200.0, 0.0))
    out = np.dstack([a.astype(np.uint8), alpha.astype(np.uint8)])
    return Image.fromarray(out, "RGBA")


def segments(mask1d, min_len=20, gap=6):
    segs, start, miss = [], None, 0
    for i, v in enumerate(mask1d):
        if v:
            if start is None:
                start = i
            miss = 0
        elif start is not None:
            miss += 1
            if miss > gap:
                if i - miss - start >= min_len:
                    segs.append((start, i - miss))
                start, miss = None, 0
    if start is not None and len(mask1d) - start >= min_len:
        segs.append((start, len(mask1d) - 1))
    return segs


def cells(im, cols, rows):
    """按行 / 列投影切出网格里的每个图标，返回 [(x0,y0,x1,y1)]，按行优先"""
    al = magenta_alpha(im) > 0.5
    ys = segments(al.any(axis=1))
    out = []
    for (y0, y1) in ys[:rows]:
        xs = segments(al[y0:y1 + 1].any(axis=0))
        for (x0, x1) in xs[:cols]:
            out.append((x0, y0, x1 + 1, y1 + 1))
    return out


def icon64(im, box):
    c = im.crop(box)
    w, h = c.size
    s = max(w, h)
    sq = Image.new("RGB", (s, s), (255, 0, 255))
    sq.paste(c, ((s - w) // 2, (s - h) // 2))
    return to_rgba(sq).resize((64, 64), Image.LANCZOS)


def cover(im, w, h):
    sc = max(w / im.width, h / im.height)
    r = im.resize((round(im.width * sc), round(im.height * sc)), Image.LANCZOS)
    x, y = (r.width - w) // 2, (r.height - h) // 2
    return r.crop((x, y, x + w, y + h))


def main():
    # 创建角色立绘（高清，3:4）
    for sch in ["fist", "sword", "blade", "spear"]:
        load(f"portrait_{sch}").save(ROOT / "assets" / "portraits" / f"{sch}_hero.jpg", quality=92)
    # 选人全身像 512x640 透明底
    cut = to_rgba(load("charselect_spear_cutout"))
    bb = cut.getchannel("A").point(lambda v: 255 if v > 128 else 0).getbbox()
    cut = cut.crop(bb)
    sc = min(500 / cut.width, 590 / cut.height)
    cut = cut.resize((round(cut.width * sc), round(cut.height * sc)), Image.LANCZOS)
    canvas = Image.new("RGBA", (512, 640), (0, 0, 0, 0))
    canvas.paste(cut, ((512 - cut.width) // 2, 640 - cut.height - 20), cut)
    canvas.save(ROOT / "assets" / "char_select" / "spear.png")
    # 胜败图 1376x768
    for k in ["victory", "defeat"]:
        load(f"{k}_spear").resize((1376, 768), Image.LANCZOS).save(ROOT / "assets" / "ui" / "screens" / f"{k}_spear.jpg", quality=90)
    # 天赋背景 404x490
    for br in ["gang", "rou", "ling"]:
        cover(load(f"talentbg_spear_{br}"), 404, 490).save(ROOT / "assets" / "ui" / "talent_bg" / f"spear_{br}.jpg", quality=90)
    # 招式图标（3x3：杨家枪法 / 梅花 / 白马 / 无名 / 少林棍 / 蟠龙 / 打狗棒 / 疯魔杖 / 降魔杖）
    ids = ["yangjia_spear", "meihua_spear", "baima_spear", "wuming_spear", "shaolin_staff", "panlong_staff", "dagou_staff", "fengmo_staff", "xiangmo_staff"]
    im = load("icons_skills_3x3")
    bx = cells(im, 3, 3)
    assert len(bx) == 9, len(bx)
    for sid, box in zip(ids, bx):
        icon64(im, box).save(ROOT / "assets" / "icons" / "skills" / f"{sid}.png")
    # 武器图标（5x2，w1..w10）
    wim = load("icons_weapons_5x2")
    wb = cells(wim, 5, 2)
    assert len(wb) == 10, len(wb)
    d = ROOT / "assets" / "icons" / "spear_weapons"
    d.mkdir(parents=True, exist_ok=True)
    for i, box in enumerate(wb):
        icon64(wim, box).save(d / f"w{i + 1}.png")
    print("done")


if __name__ == "__main__":
    main()
