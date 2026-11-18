#!/usr/bin/env python3
"""把 data/game_data.json 里的天赋树与装备参数同步到 backend/Code.gs（服务器要做同样的校验）。
改了天赋树 / 装备数据后运行一次：python3 tools/sync_talents.py
backend 测试会检查两边是否一致（node backend/test/backend.test.js）。"""
import json, pathlib, re

ROOT = pathlib.Path(__file__).resolve().parent.parent
BEGIN, END = "// BEGIN GENERATED (tools/sync_talents.py)", "// END GENERATED"


def block() -> str:
    d = json.loads((ROOT / "data" / "game_data.json").read_text(encoding="utf-8"))
    nodes = {}
    for b, bd in d["talents"]["branches"].items():
        for r, row in enumerate(bd["rows"]):
            for n in row:
                nodes[n["id"]] = [b, r, n["max"]]
    g = d["gear"]
    gear = {"slots": [s["id"] for s in g["slots"]], "weights": [r["weight"] for r in g["rarity"]],
            "invMax": g["inventory_max"], "drops": g["drops_per_win"], "extra": g["extra_drop_chance"]}
    return (f"{BEGIN}\nvar TALENT_GATE = {d['talents']['row_gate']};\n"
            f"var TALENTS = {json.dumps(nodes, ensure_ascii=False, separators=(',', ':'))};\n"
            f"var GEAR = {json.dumps(gear, ensure_ascii=False, separators=(',', ':'))};\n{END}")


def main() -> None:
    p = ROOT / "backend" / "Code.gs"
    s = p.read_text(encoding="utf-8")
    if BEGIN in s:
        s = re.sub(re.escape(BEGIN) + r".*?" + re.escape(END), lambda m: block(), s, flags=re.S)
    else:
        marker = "// ---------------------------------------------------------------- 局外成长"
        assert marker in s
        s = s.replace(marker, block() + "\n\n" + marker, 1)
    p.write_text(s, encoding="utf-8")
    print("已同步到 backend/Code.gs")


if __name__ == "__main__":
    main()
