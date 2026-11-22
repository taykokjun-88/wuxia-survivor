#!/usr/bin/env python3
"""把 tools/web_head.html 压成一行写进 export_presets.cfg 的 html/head_include（网页导出时注入 <head>）。
改了 web_head.html 之后运行：python3 tools/sync_web_head.py"""
import pathlib, re
ROOT = pathlib.Path(__file__).resolve().parent.parent
src = (ROOT / "tools/web_head.html").read_text(encoding="utf-8")
one = "".join(line.strip() for line in src.splitlines())
esc = one.replace("\\", "\\\\").replace('"', '\\"')
cfg = ROOT / "export_presets.cfg"
text = cfg.read_text(encoding="utf-8")
new, n = re.subn(r'^html/head_include=.*$', lambda m: 'html/head_include="' + esc + '"', text, flags=re.M)
assert n == 1, n
cfg.write_text(new, encoding="utf-8")
print("已更新 head_include，长度", len(esc))
