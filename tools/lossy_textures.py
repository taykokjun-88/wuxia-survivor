"""把 assets 下贴图的导入模式改为有损 WebP（压缩 pck 体积）。
用法: python3 tools/lossy_textures.py [质量0-1=0.85]   （改完需 godot --headless --import）"""
import glob, re, sys
q = sys.argv[1] if len(sys.argv) > 1 else "0.85"
SKIP = ("assets/fonts/", "assets/source/", "assets/ui/")  # 文字/界面图保持无损
n = 0
for f in glob.glob("assets/**/*.import", recursive=True):
    if any(s in f for s in SKIP): continue
    t = open(f).read()
    if 'importer="texture"' not in t: continue
    t2 = re.sub(r"compress/mode=\d", "compress/mode=1", t)
    t2 = re.sub(r"compress/lossy_quality=[\d.]+", "compress/lossy_quality=" + q, t2)
    if t2 != t: open(f, "w").write(t2); n += 1
print("改了", n, "个")
