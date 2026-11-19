#!/usr/bin/env python3
"""洋红底的特效图 → 黑底发光图（process_vfx.py 要求黑底）。

用法：python3 tools/magenta_to_black.py 源图.jpg 输出.png [--crop x0,y0,x1,y1]
做法：离背景色（四周边缘的中位色）越远越不透明（软抠图）；边缘半透明像素的颜色用最近的「实心」前景色代替，
避免洋红光晕染进特效；最后按透明度压到黑底上（颜色 × alpha）。
"""
import argparse

import numpy as np
from PIL import Image
from scipy import ndimage as ndi


def convert(img: Image.Image) -> Image.Image:
    rgb = np.asarray(img.convert("RGB")).astype(np.float32)
    border = np.concatenate([rgb[0], rgb[-1], rgb[:, 0], rgb[:, -1]])
    bg = np.median(border, axis=0)
    dist = np.abs(rgb - bg).sum(axis=2)
    alpha = np.clip((dist - 70.0) / 190.0, 0.0, 1.0)            # 70 以内 = 背景；260 以上 = 实心
    solid = alpha > 0.95
    idx = ndi.distance_transform_edt(~solid, return_distances=False, return_indices=True)
    core = rgb[idx[0], idx[1]]                                  # 每个像素用最近的实心颜色
    out = np.where((alpha < 0.95)[..., None], core, rgb) * alpha[..., None]
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8))


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("dst")
    ap.add_argument("--crop", default="")
    a = ap.parse_args()
    im = Image.open(a.src)
    if a.crop:
        x0, y0, x1, y1 = (int(v) for v in a.crop.split(","))
        im = im.crop((x0, y0, x1, y1))
    convert(im).save(a.dst)
