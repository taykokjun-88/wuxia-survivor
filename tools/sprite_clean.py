"""精灵切格后的清理：避免「切碎、分散」。
  1. 只保留和主体相连（膨胀 gap 像素后连通）的部分；漂在外面的碎块（飞出去的刀尖、半截弧光、残影点）整块去掉——这些效果由特效层负责，不该画在精灵里
  2. 主体上延伸到格子左右边缘的部分（效果被格子边界硬切）：在边缘 ramp 像素内渐隐，不留硬切边
cell：RGBA uint8 数组 (H, W, 4)；返回清理后的副本和被去掉的像素数。
"""
import numpy as np
from scipy import ndimage as ndi

EIGHT = np.ones((3, 3), dtype=bool)


def defragment(cell: np.ndarray, gap: int = 7, ramp: int = 10, thr: int = 24):
    out = cell.copy()
    a = out[..., 3]
    mask = a > thr
    if not mask.any():
        return out, 0
    lab, n = ndi.label(ndi.binary_dilation(mask, structure=EIGHT, iterations=gap), structure=EIGHT)
    sizes = ndi.sum(mask, lab, index=range(1, n + 1))
    main = int(np.argmax(sizes)) + 1
    keep = (lab == main)
    removed = int((mask & ~keep).sum())
    out[~keep, 3] = 0
    h, w = a.shape
    if ramp > 0:
        # 硬切边检测：内容最左 / 最右一列的不透明像素很多（>= 18）说明那里是被硬切断的，不是自然的轮廓；在那一侧向内渐隐 ramp 像素
        cols = (out[..., 3] > thr).sum(axis=0)
        xs = np.where(cols > 0)[0]
        if len(xs):
            x0, x1 = int(xs.min()), int(xs.max())
            if cols[x1] >= 18 or x1 >= w - 3:
                for i in range(ramp):
                    xx = x1 - i
                    if xx < 0:
                        break
                    f = (i + 1) / float(ramp + 1)
                    out[:, xx, 3] = (out[:, xx, 3] * f).astype(np.uint8)
            if cols[x0] >= 18 or x0 <= 2:
                for i in range(ramp):
                    xx = x0 + i
                    if xx >= w:
                        break
                    f = (i + 1) / float(ramp + 1)
                    out[:, xx, 3] = (out[:, xx, 3] * f).astype(np.uint8)
    return out, removed


def fig_height(cells) -> float:
    """一组格子（RGBA 数组列表）里人物的中位高度（不透明像素的纵向范围）"""
    hs = []
    for c in cells:
        ys = np.where((c[..., 3] > 40).any(axis=1))[0]
        if len(ys):
            hs.append(int(ys.max() - ys.min()))
    return float(np.median(hs)) if hs else 0.0


def rescale_to(cell: np.ndarray, k: float, foot_x: float = 128.0, foot_y: float = 240.0) -> np.ndarray:
    """把一格内容按 k 缩放（k<1 缩小），以脚底 (foot_x, foot_y) 为支点，保持格子大小。用于把画得偏大的新条带对齐到现有角色的高度"""
    from PIL import Image
    h, w = cell.shape[:2]
    if abs(k - 1.0) < 0.02:
        return cell
    im = Image.fromarray(cell, "RGBA").convert("RGBa")
    nw, nh = max(1, round(w * k)), max(1, round(h * k))
    im = im.resize((nw, nh), Image.LANCZOS).convert("RGBA")
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    out.alpha_composite(im, (round(foot_x - foot_x * k), round(foot_y - foot_y * k)))
    return np.array(out)
