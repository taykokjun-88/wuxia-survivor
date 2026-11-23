#!/usr/bin/env python3
"""把 data/game_data.json 里的天赋树与装备参数同步到 backend/Code.gs（服务器要做同样的校验）。
改了天赋树 / 装备数据后运行一次：python3 tools/sync_talents.py
backend 测试会检查两边是否一致（node backend/test/backend.test.js）。"""
import json, pathlib, re

ROOT = pathlib.Path(__file__).resolve().parent.parent
BEGIN, END = "// BEGIN GENERATED (tools/sync_talents.py)", "// END GENERATED"


def block() -> str:
    d = json.loads((ROOT / "data" / "game_data.json").read_text(encoding="utf-8"))
    # 节点表：id → [系, 层/行, 上限, 组, 层门槛, 前置[[id, "one"|"full"]], 终极?, 巅峰?]；组 legacy = 旧树（剑/刀/枪），其余 = 按流派的新树
    nodes = {}
    for b, bd in d["talents"]["branches"].items():
        for r, row in enumerate(bd["rows"]):
            for n in row:
                nodes[n["id"]] = [b, r, n["max"], "legacy", 0, [], 0, 0]
    nodes[d["talents"]["ji"]["id"]] = ["ji", 7, d["talents"]["ji"]["max"], "legacy", 0, [], 0, 0]
    trees = json.loads((ROOT / "data" / "talent_trees.json").read_text(encoding="utf-8"))
    for grp, tr in trees.items():
        for b, bd in tr["branches"].items():
            for n in bd["nodes"]:
                nodes[n["id"]] = [b, n["row"], n["max"], grp, tr["gates"][n["tier"] - 1], n["req"], int(n["cap"]), int(n["peak"])]
        nodes[tr["ji"]["id"]] = ["ji", 10, tr["ji"]["max"], grp, 0, [], 0, 0]
    g = d["gear"]
    gear = {"slots": [s["id"] for s in g["slots"]], "weights": [r["weight"] for r in g["rarity"]],
            "invMax": g["inventory_max"], "mini": g["drops"]["mini"], "bossMin": g["drops"]["boss_min"], "bossExtra": g["drops"]["boss_extra_chance"],
            "enh": {"max": g["enhance"]["max"], "bonus": g["enhance"]["bonus"], "costBase": g["enhance"]["cost_base"], "costExp": g["enhance"]["cost_exp"]},
            "silver": {"perScore": g["silver"]["per_score"], "cap": g["silver"]["cap"], "winBonus": g["silver"]["win_bonus"], "comp": g["silver"]["comp"], "discard": g["silver"]["discard"], "max": g["silver"]["max"]}}
    maps = {k: {"minTimes": [m["t"] for m in v["timeline"]["minis"]], "finalT": v["timeline"]["final"]["t"], "minWin": v["timeline"]["min_win"], "requires": v.get("requires_clear", ""), "expMult": v.get("exp", {}).get("mult", 1.0), "runCap": v.get("exp", {}).get("run_cap", 400), "capLevel": v.get("exp", {}).get("cap_level", 0), "dropWeights": v.get("drop_weights", [])} for k, v in d["maps"].items() if "timeline" in v}
    df = d["difficulty"]
    diff = {"expMeta": df["exp_meta"], "dropBonus": df["drop_bonus"], "raritySkew": df["rarity_skew"]}
    schools = [k for k, v in d["schools"].items() if v.get("enabled")]
    return (f"{BEGIN}\nvar SCHOOLS = {json.dumps(schools)};\nvar TALENT_GATE = {d['talents']['row_gate']};\n"
            f"var TALENT_PER_LEVEL = {d['talents']['per_level']};\n"
            f"var TALENT_JI_NEED = {d['talents']['ji']['need']};\n"
            f"var TALENTS = {json.dumps(nodes, ensure_ascii=False, separators=(',', ':'))};\n"
            f"var GEAR = {json.dumps(gear, ensure_ascii=False, separators=(',', ':'))};\n"
            f"var MAPS = {json.dumps(maps, ensure_ascii=False, separators=(',', ':'))};\n"
            f"var DIFF = {json.dumps(diff, ensure_ascii=False, separators=(',', ':'))};\n{END}")


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
