#!/usr/bin/env python3
"""把霞鹜文楷（LXGW WenKai，OFL）裁剪成游戏用的小字库。

浏览器里没有系统字体可回退，必须自带中文字体；完整字体 19MB，裁剪后约 2MB。
保留：仓库里出现过的所有字符 + GB2312 一级常用字(3755) + ASCII + 常用标点，
所以以后改文案基本不用重新裁剪。

用法：
  pip install fonttools
  python3 tools/subset_font.py LXGWWenKai-Regular.ttf assets/fonts/main.ttf
  python3 tools/subset_font.py LXGWWenKai-Bold.ttf    assets/fonts/main_bold.ttf
"""
import sys
import pathlib


ROOT = pathlib.Path(__file__).resolve().parent.parent
EXTRA = "，。、：；！？“”‘’（）【】《》—…·×→←↑↓％＋－＝★●■▲　 ·"


def repo_chars() -> set:
    chars = set()
    for pat in ("scripts/**/*.gd", "data/*.json", "backend/*.gs", "docs/*.md", "README.md", "tests/*.gd"):
        for p in ROOT.glob(pat):
            chars.update(p.read_text(encoding="utf-8", errors="ignore"))
    return {c for c in chars if not c.isspace() or c == " "}


def gb2312_level1() -> set:
    out = set()
    for row in range(0xB0, 0xD8):          # 一级字库：16~55 区
        for col in range(0xA1, 0xFF):
            try:
                out.add(bytes([row, col]).decode("gb2312"))
            except UnicodeDecodeError:
                pass
    return out


def main(src: str, dst: str) -> None:
    import uharfbuzz as hb

    chars = repo_chars() | gb2312_level1() | set(EXTRA) | {chr(c) for c in range(0x20, 0x7F)}
    blob = hb.Blob.from_file_path(src)
    face = hb.Face(blob)
    inp = hb.SubsetInput()
    inp.unicode_set.update(ord(c) for c in chars)
    inp.flags = hb.SubsetFlags.NO_HINTING
    out = hb.subset(face, inp)
    data = out.blob.data
    pathlib.Path(dst).write_bytes(data)
    print(f"{dst}: {len(chars)} 个字符，{len(data) / 1024:.0f} KB")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
