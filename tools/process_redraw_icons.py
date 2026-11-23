"""重置画面计划书 17：Gemini 的 1024 招式图标 → 裁到底板外框、补成正方形、缩到 64×64，覆盖 assets/icons/skills/。
用法: python3 tools/process_redraw_icons.py [源目录=assets/source/redraw_17]"""
import sys, glob, os
from PIL import Image
import numpy as np
src = sys.argv[1] if len(sys.argv) > 1 else "assets/source/redraw_17"
for f in sorted(glob.glob(src + "/*.png")):
    im = Image.open(f).convert("RGBA")
    a = np.array(im)[..., 3]
    ys, xs = np.where(a > 40)
    x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
    c = im.crop((x0, y0, x1, y1))
    s = max(c.size); sq = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    sq.paste(c, ((s - c.width) // 2, (s - c.height) // 2))
    sq.resize((64, 64), Image.LANCZOS).save("assets/icons/skills/" + os.path.basename(f))
    print(os.path.basename(f), c.size)
