#!/usr/bin/env python3
"""生成 B 线美术走查对照图，输出到 docs/redraw/audit/（导出 Web 时 docs/* 已排除，不占包体）。

输出：
  - sprite_sword.png / sprite_blade.png / sprite_spear.png：逐帧战斗精灵 + 小镇三方向（供逐帧核对发型/配色/断帧）
  - assets_xinfa_qinggong_shi.png：心法 10 / 轻功 6 / 无迹九变剑 9 式 名称↔图标对照表
  - assets_enemies_bosses.png：三关全部杂兵 / 精英 / Boss 名称↔精灵首帧↔Boss 立绘对照表
"""
import json
import os
import pathlib
from PIL import Image, ImageDraw, ImageFont

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "docs" / "redraw" / "audit"
OUT.mkdir(parents=True, exist_ok=True)

FONT_PATH = str(ROOT / "assets" / "fonts" / "main.ttf")
FONT_BOLD = str(ROOT / "assets" / "fonts" / "main_bold.ttf")


def font(size: int, bold: bool = False):
    return ImageFont.truetype(FONT_BOLD if bold else FONT_PATH, size)


def checker_bg(w: int, h: int, sq: int = 12) -> Image.Image:
    im = Image.new("RGBA", (w, h), (38, 36, 33, 255))
    dr = ImageDraw.Draw(im)
    for y in range(0, h, sq):
        for x in range(0, w, sq):
            if ((x // sq) + (y // sq)) % 2 == 0:
                dr.rectangle([x, y, x + sq - 1, y + sq - 1], fill=(48, 45, 41, 255))
    return im


def fit_paste(canvas: Image.Image, src: Image.Image, box: tuple[int, int, int, int]):
    x0, y0, bw, bh = box
    im = src.convert("RGBA")
    ratio = min(bw / max(1, im.width), bh / max(1, im.height))
    nw, nh = max(1, int(im.width * ratio)), max(1, int(im.height * ratio))
    im = im.resize((nw, nh), Image.Resampling.LANCZOS)
    canvas.alpha_composite(im, (x0 + (bw - nw) // 2, y0 + (bh - nh) // 2))


def build_sprite_sheet(school_id: str, title: str, sprite_dir: str, town_dir: str, out_name: str):
    sdir = ROOT / sprite_dir
    tdir = ROOT / town_dir
    anim = json.loads((sdir / "anim.json").read_text(encoding="utf-8"))
    cell = int(anim.get("cell", 156))
    rows = []
    for aname, cfg in sorted(anim["anims"].items()):
        fpath = sdir / cfg["file"]
        if not fpath.exists():
            continue
        strip = Image.open(fpath).convert("RGBA")
        nf = int(cfg["frames"])
        fw = strip.width // max(1, nf)
        frames = [strip.crop((i * fw, 0, (i + 1) * fw, strip.height)) for i in range(nf)]
        rows.append((f"局内 · {aname} ({nf}帧)", frames))

    for dname, label in [("hero_down.png", "小镇 · 朝下"), ("hero_side.png", "小镇 · 朝侧"), ("hero_up.png", "小镇 · 朝上")]:
        fpath = tdir / dname
        if not fpath.exists():
            continue
        strip = Image.open(fpath).convert("RGBA")
        nf = max(1, round(strip.width / max(1, strip.height)))
        fw = strip.width // nf
        frames = [strip.crop((i * fw, 0, (i + 1) * fw, strip.height)) for i in range(nf)]
        rows.append((f"{label} ({nf}帧)", frames))

    max_cols = max((len(r[1]) for r in rows), default=4)
    tile = 136
    pad = 10
    label_w = 190
    header_h = 54
    row_h = tile + 26
    w = label_w + max_cols * (tile + pad) + 20
    h = header_h + len(rows) * row_h + 16
    img = Image.new("RGBA", (w, h), (24, 22, 20, 255))
    dr = ImageDraw.Draw(img)
    dr.text((16, 12), f"{title}（{school_id}）逐帧美术走查对照图 — 核对发型 / 配色 / 残影 / 小镇一致性", fill=(240, 210, 120, 255), font=font(22, True))

    for ri, (rlabel, frames) in enumerate(rows):
        ry = header_h + ri * row_h
        dr.line([(12, ry - 4), (w - 12, ry - 4)], fill=(58, 52, 46, 255), width=1)
        dr.text((16, ry + tile // 2 - 10), rlabel, fill=(235, 226, 205, 255), font=font(16))
        for ci, fr in enumerate(frames):
            cx = label_w + ci * (tile + pad)
            cy = ry + 18
            bg = checker_bg(tile, tile)
            img.alpha_composite(bg, (cx, cy))
            fit_paste(img, fr, (cx + 2, cy + 2, tile - 4, tile - 4))
            dr.rectangle([cx, cy, cx + tile - 1, cy + tile - 1], outline=(95, 86, 70, 255), width=1)
            dr.text((cx + 4, ry + 1), f"第 {ci + 1} 帧", fill=(180, 172, 152, 255), font=font(13))

    out_p = OUT / out_name
    img.convert("RGB").save(out_p, quality=92, optimize=True)
    print(f"生成 {out_p.relative_to(ROOT)} ({w}x{h})")


def build_icons_sheet(gd: dict):
    sections = []
    # 心法 10
    xinfa_items = []
    for iid, info in gd["xinfa"].items():
        p = ROOT / "assets" / "icons" / "xinfa" / f"{iid}.png"
        xinfa_items.append((info["name"], iid, p))
    sections.append(("心法图标（10 个）", xinfa_items))

    # 轻功 6
    qg_items = []
    for iid, info in gd["qinggong"].items():
        p = ROOT / "assets" / "icons" / "qinggong" / f"{iid}.png"
        qg_items.append((info["name"], iid, p))
    sections.append(("轻功图标（6 个）", qg_items))

    # 式 9
    shi_items = []
    for info in gd["shi"]:
        iid = info["id"]
        p = ROOT / "assets" / "icons" / "shi" / f"{iid}.png"
        shi_items.append((info["name"], iid, p))
    sections.append(("无迹九变剑 · 九式图标（9 个）", shi_items))

    cols = 5
    cell_w, cell_h = 200, 138
    margin = 20
    sec_title_h = 40
    total_h = 62
    for _, items in sections:
        nrows = (len(items) + cols - 1) // cols
        total_h += sec_title_h + nrows * cell_h + 16
    w = margin * 2 + cols * cell_w
    img = Image.new("RGBA", (w, total_h), (24, 22, 20, 255))
    dr = ImageDraw.Draw(img)
    dr.text((margin, 14), "心法 / 轻功 / 九式 名称 ↔ 图标对照表（B1 美术走查）", fill=(240, 210, 120, 255), font=font(22, True))

    y = 62
    for stitle, items in sections:
        dr.text((margin, y + 6), stitle, fill=(154, 216, 255, 255), font=font(18, True))
        y += sec_title_h
        for idx, (cname, iid, p) in enumerate(items):
            r, c = divmod(idx, cols)
            x = margin + c * cell_w
            cy = y + r * cell_h
            dr.rectangle([x + 4, cy + 4, x + cell_w - 8, cy + cell_h - 8], fill=(36, 33, 29, 255), outline=(85, 76, 62, 255))
            if p.exists():
                fit_paste(img, Image.open(p), (x + 56, cy + 12, 84, 84))
            else:
                dr.text((x + 68, cy + 42), "缺失", fill=(240, 90, 80, 255), font=font(16))
            dr.text((x + 12, cy + 99), f"{cname}", fill=(243, 234, 210, 255), font=font(15, True))
            dr.text((x + 12, cy + 117), f"{iid}", fill=(150, 142, 124, 255), font=font(12))
        nrows = (len(items) + cols - 1) // cols
        y += nrows * cell_h + 16

    out_p = OUT / "assets_xinfa_qinggong_shi.png"
    img.convert("RGB").save(out_p, quality=92, optimize=True)
    print(f"生成 {out_p.relative_to(ROOT)} ({w}x{total_h})")


def build_enemies_sheet(gd: dict):
    emeta = json.loads((ROOT / "assets" / "enemies" / "meta.json").read_text(encoding="utf-8"))
    groups = [
        ("第一关 · 黑风寨", ["bandit", "blade", "soldier", "archer", "charger", "elite", "mini_boss_1", "mini_boss_2", "mini_boss_3", "boss"], "black_wind"),
        ("第二关 · 赤焰巅", ["huashan", "kunlun", "kongtong", "shaolin", "emei", "s2_mini_1", "s2_mini_2", "s2_mini_3", "s2_boss"], "guangming"),
        ("第三关 · 海棠屿", ["th_yapu", "th_jiading", "th_yaotong", "th_dushe", "th_jiguan", "th_mini_1", "th_mini_2", "th_mini_3", "th_boss"], "taohua"),
    ]
    cols = 5
    cell_w, cell_h = 246, 154
    margin = 20
    sec_h = 40
    total_h = 62
    for _, ids, _ in groups:
        nrows = (len(ids) + cols - 1) // cols
        total_h += sec_h + nrows * cell_h + 16
    w = margin * 2 + cols * cell_w
    img = Image.new("RGBA", (w, total_h), (24, 22, 20, 255))
    dr = ImageDraw.Draw(img)
    dr.text((margin, 14), "三关怪物 / Boss 名称 ↔ 精灵首帧 ↔ 立绘对照表（B1 美术走查）", fill=(240, 210, 120, 255), font=font(22, True))

    y = 62
    for gtitle, ids, mid in groups:
        dr.text((margin, y + 6), gtitle, fill=(240, 180, 90, 255), font=font(18, True))
        y += sec_h
        for idx, eid in enumerate(ids):
            r, c = divmod(idx, cols)
            x = margin + c * cell_w
            cy = y + r * cell_h
            info = gd["enemies"].get(eid, {})
            cname = info.get("name", eid)
            dr.rectangle([x + 4, cy + 4, x + cell_w - 8, cy + cell_h - 8], fill=(36, 33, 29, 255), outline=(85, 76, 62, 255))
            # Sprite first frame
            mc = emeta.get(eid)
            sp_box = (x + 12, cy + 12, 102, 102)
            bg = checker_bg(102, 102, 10)
            img.alpha_composite(bg, (sp_box[0], sp_box[1]))
            if mc and (ROOT / "assets" / "enemies" / mc["file"]).exists():
                st = Image.open(ROOT / "assets" / "enemies" / mc["file"]).convert("RGBA")
                nf = max(1, int(mc.get("frames", 1)))
                fw = st.width // nf
                fit_paste(img, st.crop((0, 0, fw, st.height)), sp_box)
            else:
                dr.text((x + 30, cy + 52), "无精灵", fill=(240, 90, 80, 255), font=font(14))
            # Optional boss portrait
            ppath = ROOT / "assets" / "maps" / mid / f"portrait_{eid}.png"
            if ppath.exists():
                fit_paste(img, Image.open(ppath), (x + 122, cy + 12, 102, 102))
                dr.rectangle([x + 122, cy + 12, x + 223, cy + 113], outline=(201, 162, 39, 255))
            else:
                dr.text((x + 132, cy + 54), "（无立绘）", fill=(115, 110, 98, 255), font=font(13))
            dr.text((x + 12, cy + 118), f"{cname}", fill=(243, 234, 210, 255), font=font(15, True))
            dr.text((x + 12, cy + 136), f"{eid}", fill=(150, 142, 124, 255), font=font(12))
        nrows = (len(ids) + cols - 1) // cols
        y += nrows * cell_h + 16

    out_p = OUT / "assets_enemies_bosses.png"
    img.convert("RGB").save(out_p, quality=92, optimize=True)
    print(f"生成 {out_p.relative_to(ROOT)} ({w}x{total_h})")


def build_gear_weapons_sheet(gd: dict):
    ibs = gd["gear"]["slots"][0]["items_by_school"]
    sname = {k: v["name"] for k, v in gd["schools"].items()}
    cols = 10
    cell_w, cell_h = 124, 128
    margin = 16
    sec_h = 34
    # 4 weapon rows (10 each) + 1 gear row (20 icons = 2 rows of 10)
    total_h = 60 + 4 * (sec_h + cell_h + 10) + sec_h + 2 * cell_h + 24
    w = margin * 2 + cols * cell_w
    img = Image.new("RGBA", (w, total_h), (24, 22, 20, 255))
    dr = ImageDraw.Draw(img)
    dr.text((margin, 14), "4 职业武器图标（40 件）与部位图标对照表（B1 美术走查）", fill=(240, 210, 120, 255), font=font(22, True))

    y = 58
    for sc in ["fist", "sword", "blade", "spear"]:
        dr.text((margin, y + 6), f"{sname[sc]} 武器（assets/icons/{sc}_weapons/w1~w10）", fill=(154, 216, 255, 255), font=font(17, True))
        y += sec_h
        items = ibs[sc]
        for idx, it in enumerate(items):
            x = margin + idx * cell_w
            dr.rectangle([x + 3, y + 3, x + cell_w - 5, y + cell_h - 5], fill=(36, 33, 29, 255), outline=(85, 76, 62, 255))
            # Prefer wired icon, else inspect w{idx+1}.png directly
            wired = it.get("icon") or ""
            p = ROOT / "assets" / "icons" / f"{sc}_weapons" / f"w{idx + 1}.png"
            if p.exists():
                fit_paste(img, Image.open(p), (x + 24, y + 8, 74, 74))
            dr.text((x + 8, y + 86), f"w{idx+1} {it['name'][:5]}", fill=(243, 234, 210, 255), font=font(13, True))
            tag = "已接入" if wired.startswith(f"{sc}_weapons/") else ("旧图" if wired else "未接入")
            tcol = (140, 220, 140, 255) if tag == "已接入" else (240, 170, 90, 255)
            dr.text((x + 8, y + 105), f"{tag}", fill=tcol, font=font(12))
        y += cell_h + 10

    dr.text((margin, y + 6), "分流派装备部位图标（assets/icons/gear/）", fill=(240, 180, 90, 255), font=font(17, True))
    y += sec_h
    gear_files = [
        ("通用武器", "weapon.png"), ("通用上衣", "coat.png"), ("通用下身", "pants.png"), ("通用鞋子", "boots.png"), ("通用配饰", "charm.png"),
        ("武者上衣", "fist_coat.png"), ("武者下身", "fist_pants.png"), ("武者鞋子", "fist_boots.png"), ("武者配饰", "fist_charm.png"), ("剑客上衣", "sword_coat.png"),
        ("剑客下身", "sword_pants.png"), ("剑客鞋子", "sword_boots.png"), ("剑客配饰", "sword_charm.png"), ("刀客上衣", "blade_coat.png"), ("刀客下身", "blade_pants.png"),
        ("刀客鞋子", "blade_boots.png"), ("刀客配饰", "blade_charm.png"), ("杨家上衣", "spear_coat.png"), ("杨家下身", "spear_pants.png"), ("杨家鞋子", "spear_boots.png"),
    ]
    for idx, (lbl, fn) in enumerate(gear_files):
        r, c = divmod(idx, cols)
        x = margin + c * cell_w
        cy = y + r * cell_h
        dr.rectangle([x + 3, cy + 3, x + cell_w - 5, cy + cell_h - 5], fill=(36, 33, 29, 255), outline=(85, 76, 62, 255))
        p = ROOT / "assets" / "icons" / "gear" / fn
        if p.exists():
            fit_paste(img, Image.open(p), (x + 24, cy + 10, 74, 74))
        dr.text((x + 8, cy + 92), lbl, fill=(243, 234, 210, 255), font=font(13, True))

    out_p = OUT / "assets_gear_weapons.png"
    img.convert("RGB").save(out_p, quality=92, optimize=True)
    print(f"生成 {out_p.relative_to(ROOT)} ({w}x{total_h})")


def build_portraits_ui_sheet():
    groups = [
        ("职业立绘 & 选人全身像", [
            ("武者立绘", "assets/portraits/fist_hero.jpg"),
            ("剑客立绘", "assets/portraits/sword_hero.jpg"),
            ("刀客立绘", "assets/portraits/blade_hero.jpg"),
            ("杨家将立绘", "assets/portraits/spear_hero.jpg"),
            ("选人 · 武者", "assets/char_select/fist.png"),
            ("选人 · 剑客", "assets/char_select/sword.png"),
            ("选人 · 刀客", "assets/char_select/blade.png"),
            ("选人 · 杨家将", "assets/char_select/spear.png"),
        ]),
        ("登录封面 / 选关横幅 / 标题字（IP 文字核查）", [
            ("登录封面", "assets/ui/screens/title_cover.jpg"),
            ("登录 Logo", "assets/ui/login/logo.png"),
            ("黑风寨横幅", "assets/maps/black_wind/stage_banner.jpg"),
            ("赤焰巅横幅", "assets/maps/guangming/stage_banner.jpg"),
            ("赤焰巅标题字", "assets/maps/guangming/title_logo.png"),
            ("海棠屿横幅", "assets/maps/taohua/stage_banner.jpg"),
        ]),
        ("胜负结算插画", [
            ("武者胜", "assets/ui/screens/victory_fist.jpg"),
            ("剑客胜", "assets/ui/screens/victory_sword.jpg"),
            ("刀客胜", "assets/ui/screens/victory_blade.jpg"),
            ("杨家将胜", "assets/ui/screens/victory_spear.jpg"),
            ("赤焰巅胜", "assets/ui/screens/victory_guangming.jpg"),
            ("武者败", "assets/ui/screens/defeat_fist.jpg"),
            ("剑客败", "assets/ui/screens/defeat_sword.jpg"),
            ("刀客败", "assets/ui/screens/defeat_blade.jpg"),
            ("杨家将败", "assets/ui/screens/defeat_spear.jpg"),
            ("赤焰巅败", "assets/ui/screens/defeat_guangming.jpg"),
        ]),
    ]
    cols = 4
    cell_w, cell_h = 310, 210
    margin = 18
    sec_h = 38
    total_h = 62
    for _, items in groups:
        nrows = (len(items) + cols - 1) // cols
        total_h += sec_h + nrows * cell_h + 14
    w = margin * 2 + cols * cell_w
    img = Image.new("RGBA", (w, total_h), (24, 22, 20, 255))
    dr = ImageDraw.Draw(img)
    dr.text((margin, 14), "立绘 / 选人 / 封面 / 横幅 / 结算插画总览（B1 / B5 画面与 IP 文字走查）", fill=(240, 210, 120, 255), font=font(22, True))

    y = 60
    for gtitle, items in groups:
        dr.text((margin, y + 6), gtitle, fill=(154, 216, 255, 255), font=font(18, True))
        y += sec_h
        for idx, (lbl, rel) in enumerate(items):
            r, c = divmod(idx, cols)
            x = margin + c * cell_w
            cy = y + r * cell_h
            dr.rectangle([x + 4, cy + 4, x + cell_w - 8, cy + cell_h - 8], fill=(36, 33, 29, 255), outline=(85, 76, 62, 255))
            p = ROOT / rel
            if p.exists():
                fit_paste(img, Image.open(p), (x + 10, cy + 10, cell_w - 24, cell_h - 46))
            dr.text((x + 12, cy + cell_h - 30), lbl, fill=(243, 234, 210, 255), font=font(15, True))
        nrows = (len(items) + cols - 1) // cols
        y += nrows * cell_h + 14

    out_p = OUT / "assets_portraits_ui.png"
    img.convert("RGB").save(out_p, quality=90, optimize=True)
    print(f"生成 {out_p.relative_to(ROOT)} ({w}x{total_h})")


def main():
    gd = json.loads((ROOT / "data" / "game_data.json").read_text(encoding="utf-8"))
    build_sprite_sheet("sword", "剑客", "assets/sprites/sword", "assets/town/hero_sword", "sprite_sword.png")
    build_sprite_sheet("blade", "刀客", "assets/sprites/blade", "assets/town/hero_blade", "sprite_blade.png")
    build_sprite_sheet("spear", "杨家将", "assets/sprites/spear", "assets/town/hero_spear", "sprite_spear.png")
    build_icons_sheet(gd)
    build_enemies_sheet(gd)
    build_gear_weapons_sheet(gd)
    build_portraits_ui_sheet()


if __name__ == "__main__":
    main()
