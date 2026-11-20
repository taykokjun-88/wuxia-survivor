class_name Gear
extends RefCounted
## 装备：大 Boss 掉落，只会是本流派的。五个部位（武器 / 上衣 / 下半身 / 鞋子 / 配饰），五档稀有度。
## 一件装备只用一个编码 "部位.稀有度.种子" 表示，属性和词条由种子确定地生成（服务器只发编码、客户端展开），
## 所以服务器不需要懂装备属性，客户端也没法凭空造出更好的装备（服务器只认自己发过的编码）。
##
## 属性：基础属性（部位决定）+ 副属性（精品以上更多）+ 特殊词条（精品起）：强化某个攻击技能，或给某个心法 +级。


static func slot_ids() -> Array:
	var out := []
	for s in Data.gear["slots"]:
		out.append(s["id"])
	return out


static func slot_def(slot: String) -> Dictionary:
	for s in Data.gear["slots"]:
		if s["id"] == slot:
			return s
	return {}


static func rarity_def(r: int) -> Dictionary:
	return Data.gear["rarity"][clampi(r, 0, Data.gear["rarity"].size() - 1)]


## 编码 → {slot, rarity, seed}；格式不对返回空字典
static func parse(code: String) -> Dictionary:
	var p := code.split(".")
	if p.size() != 3 or not slot_ids().has(p[0]) or not p[1].is_valid_int() or not p[2].is_valid_int():
		return {}
	var r := int(p[1])
	if r < 0 or r >= Data.gear["rarity"].size():
		return {}
	return {"slot": p[0], "rarity": r, "seed": int(p[2])}


static func make_code(slot: String, rarity: int, seed_v: int) -> String:
	return "%s.%d.%d" % [slot, rarity, seed_v]


## 随机掉一件（部位平均，稀有度按权重；min_rarity 用于保底）
static func rarity_weight(i: int, comp: float) -> float:
	## 难度越高，高稀有度的权重越大：第 i 档 ×(1 + (综合难度−1) × rarity_skew × i)
	return float(Data.gear["rarity"][i]["weight"]) * (1.0 + (comp - 1.0) * float(Data.difficulty["rarity_skew"]) * float(i))


static func roll_code(rng: RandomNumberGenerator, min_rarity: int = 0, comp: float = 1.0) -> String:
	var slots := slot_ids()
	var slot: String = slots[rng.randi() % slots.size()]
	var total := 0.0
	for i in Data.gear["rarity"].size():
		total += rarity_weight(i, comp)
	var x := rng.randf() * total
	var rarity := 0
	for i in Data.gear["rarity"].size():
		x -= rarity_weight(i, comp)
		if x < 0.0:
			rarity = i
			break
	return make_code(slot, maxi(rarity, min_rarity), 1 + rng.randi() % 999999)


## 部位的装备清单（每个部位 10 件；武器按流派分「拳套类」「剑类」各 10 件，没有专属清单的流派用拳套类）
static func items_for(slot: String, school_id: String) -> Array:
	var sd := slot_def(slot)
	if sd.has("items_by_school"):
		var by: Dictionary = sd["items_by_school"]
		return by[school_id] if by.has(school_id) else by["fist"]
	return sd["items"]


## 本局掉落：每个被击败的小 Boss 固定 1 件；大 Boss（通关）1 件，另有 boss_extra_chance 的几率再 +1（共 1~2 件）
## 稀有度按 60 / 30 / 9 / 1 抽取，综合难度越高，特别 / 稀有 / 传说的权重按比例提高（见 rarity_weight）
static func run_drops(rng: RandomNumberGenerator, minis: int, won: bool, comp: float = 1.0) -> Array:
	var dd: Dictionary = Data.gear["drops"]
	var n := minis * int(dd["mini"])
	if won:
		n += int(dd["boss_min"]) + (1 if rng.randf() < float(dd["boss_extra_chance"]) else 0)
	var out := []
	for i in n:
		out.append(roll_code(rng, 0, comp))
	return out


## 展开：{code, slot, slot_name, rarity, rarity_name, color, name, stats{key: value}, affixes[{kind,id,dir,v,text}]}
static func make(code: String, school_id: String = "fist", enh_level: int = 0) -> Dictionary:
	var pc := parse(code)
	if pc.is_empty():
		return {}
	var rng := RandomNumberGenerator.new()
	rng.seed = int(pc["seed"]) * 7919 + int(pc["rarity"]) * 104729 + (hash(pc["slot"]) & 0xFFFF)
	var rd := rarity_def(int(pc["rarity"]))
	var sd := slot_def(str(pc["slot"]))
	var mult := float(rd["mult"])
	var stats := {}
	var defs := items_for(str(pc["slot"]), school_id)
	var idx := int(pc["seed"]) % defs.size()
	if sd.has("rarity_names") and (sd["rarity_names"] as Dictionary).has(school_id):     # 刀客的武器按稀有度选名（传说只出屠龙宝刀）
		var grp: Array = (sd["rarity_names"] as Dictionary)[school_id][clampi(int(pc["rarity"]), 0, 3)]
		idx = int(grp[int(pc["seed"]) % grp.size()])
	var idef: Dictionary = defs[idx]
	var base: Dictionary = idef["base"]
	for k in base:
		stats[k] = float(base[k]) * mult
	# 副属性：从池里不重复地挑
	var pool: Array = (Data.gear["subs"] as Dictionary).keys()
	for i in int(rd["subs"]):
		var k: String = pool[rng.randi() % pool.size()]
		pool.erase(k)
		stats[k] = float(stats.get(k, 0.0)) + float(Data.gear["subs"][k]) * mult * rng.randf_range(0.85, 1.15)
	# 特殊词条
	var affixes: Array = []
	var used := {}
	for i in int(rd["affixes"]):
		var a := _roll_affix(rng, school_id, mult, int(pc["rarity"]), used)
		if not a.is_empty():
			affixes.append(a)
	# 铁匠强化：基础 + 副属性每级 +8%（特殊词条不变）
	var lvl := clampi(enh_level, 0, enhance_max())
	if lvl > 0:
		for k in stats:
			stats[k] = float(stats[k]) * level_mult(lvl)
	return {
		"code": code, "slot": pc["slot"], "slot_name": sd["name"], "rarity": pc["rarity"], "rarity_name": rd["name"],
		"color": rd["color"], "name": str(idef["name"]) + (" +%d" % lvl if lvl > 0 else ""),
		"stats": stats, "affixes": affixes, "enh": lvl,
	}


# ---------------------------------------------------------------------
# 铁匠强化 / 银两（后端 Code.gs 里有同一份公式，测试用共用向量校验）
# ---------------------------------------------------------------------

static func enhance_max() -> int:
	return int(Data.gear["enhance"]["max"])


static func level_mult(lvl: int) -> float:
	return 1.0 + float(Data.gear["enhance"]["bonus"]) * lvl


## 把装备从 lvl 级强化到 lvl+1 级需要的银两
static func enhance_cost(rarity: int, lvl: int) -> int:
	var base: Array = Data.gear["enhance"]["cost_base"]
	return int(roundf(float(base[clampi(rarity, 0, base.size() - 1)]) * pow(float(lvl + 1), float(Data.gear["enhance"]["cost_exp"]))))


## 一局结算得到的银两（阵亡也有；通关额外 +win_bonus；综合难度越高越多）
static func run_silver(score: int, won: bool, comp: float) -> int:
	var s: Dictionary = Data.gear["silver"]
	var x := mini(int(s["cap"]), int(roundf(float(score) / float(s["per_score"]))))
	if won:
		x += int(s["win_bonus"])
	return int(roundf(float(x) * (1.0 + (comp - 1.0) * float(s["comp"]))))


## 丢弃（分解）一件装备换到的银两
static func discard_silver(rarity: int) -> int:
	var d: Array = Data.gear["silver"]["discard"]
	return int(d[clampi(rarity, 0, d.size() - 1)])


static func _roll_affix(rng: RandomNumberGenerator, school_id: String, mult: float, rarity: int, used: Dictionary) -> Dictionary:
	if rng.randf() < float(Data.gear["affix_xinfa_chance"]):
		var ids: Array = []
		for xid in Data.xinfa:                       # 只出能强化本流派招式的心法（同修里有本流派的招式）
			for sid2 in Data.xinfa[xid]["skills"]:
				if str(Data.skills[sid2]["school"]) == school_id:
					ids.append(xid)
					break
		if ids.is_empty():
			ids = Data.xinfa.keys()
		var id: String = ids[rng.randi() % ids.size()]
		if not used.has("x" + id):
			used["x" + id] = true
			var lv := 2 if rarity >= 4 else 1
			return {"kind": "xinfa", "id": id, "v": lv, "text": "%s +%d 份强度" % [Data.xinfa[id]["name"], lv]}
	var skills: Array = []
	for sid in Data.skills:
		if str(Data.skills[sid]["school"]) == school_id:
			skills.append(sid)
	for tries in 6:
		var sid: String = skills[rng.randi() % skills.size()]
		var dirs: Array = ["damage", "cooldown", "empower"]
		if not (Data.skills[sid]["map"]["range"] as Array).is_empty():
			dirs.append("range")
		var dir: String = dirs[rng.randi() % dirs.size()]
		if used.has(sid + dir):
			continue
		used[sid + dir] = true
		var v := roundf(float(Data.gear["affix_skill"][dir]) * mult * rng.randf_range(0.9, 1.1))
		var label: String = {"damage": "伤害 +%d%%", "cooldown": "冷却 −%d%%", "range": "范围 +%d%%", "empower": "催动消耗 −%d%%"}[dir]
		return {"kind": "skill", "id": sid, "dir": dir, "v": v, "text": "%s %s" % [Data.skills[sid]["name"], label % int(v)]}
	return {}


## 一件装备的说明文字（属性 + 词条）
static func describe(item: Dictionary) -> String:
	var parts: Array = []
	for k in item["stats"]:
		parts.append(stat_text(str(k), float(item["stats"][k])))
	for a in item["affixes"]:
		parts.append("★" + str(a["text"]))
	return "　".join(parts)


const STAT_NAMES := {
	"damage_pct": ["伤害", true], "max_hp": ["气血", false], "armor": ["防御", false], "neili_regen": ["内力回复", false],
	"crit_mult": ["暴击伤害", true], "empower_cut": ["催动消耗缩减", true], "kill_neili": ["击杀回内力", false], "hit_slow": ["命中减速", true],
	"hp_regen": ["气血回复", false], "block_chance": ["格挡", true], "dodge_chance": ["闪避", true], "thorns": ["反震", false],
	"pickup_heal": ["拾取回血", false], "med_regen": ["入定回气", false], "ying_dmg": ["盈境伤害", true],
	"speed_pct": ["移速", true], "qg_cd_reduce": ["轻功冷却缩减", true], "crit_chance": ["暴击", true], "max_neili": ["内力上限", false],
	"cd_reduce": ["冷却缩减", true], "luck": ["福缘", true], "exp_pct": ["经验", true],
	"armor_pierce": ["破防", true], "kill_hp": ["击杀回血", false], "qi_gain": ["蓄劲速度", true], "soul_gain": ["刀魂增长", true],
}


static func stat_text(key: String, v: float) -> String:
	var info: Array = STAT_NAMES.get(key, [key, false])
	if bool(info[1]):
		return "%s +%.1f%%" % [info[0], v * 100.0]
	return "%s +%.1f" % [info[0], v] if v < 10.0 else "%s +%d" % [info[0], int(round(v))]


## 已穿戴装备 → {stats: 属性加成, skill_mods: {技能: {方向: 百分数}}, xinfa: {心法: 额外等级}}
static func bonuses(items: Array) -> Dictionary:
	var stats := {}
	var skill_mods := {}
	var xinfa := {}
	for it in items:
		if it.is_empty():
			continue
		for k in it["stats"]:
			stats[k] = float(stats.get(k, 0.0)) + float(it["stats"][k])
		for a in it["affixes"]:
			if str(a["kind"]) == "skill":
				var m: Dictionary = skill_mods.get(a["id"], {})
				m[a["dir"]] = float(m.get(a["dir"], 0.0)) + float(a["v"])
				skill_mods[a["id"]] = m
			else:
				xinfa[a["id"]] = int(xinfa.get(a["id"], 0)) + int(a["v"])
	return {"stats": stats, "skill_mods": skill_mods, "xinfa": xinfa}


# ---------------------------------------------------------------------
# 装备分数：每件 = 品级基础分 × (1 + 强化加成)；总分 = 已穿戴各件之和（选关推荐线用）
# ---------------------------------------------------------------------

static func item_score(rarity: int, enh_level: int = 0) -> int:
	var base: Array = Data.gear["score"]["base"]
	return int(roundf(float(base[clampi(rarity, 0, base.size() - 1)]) * level_mult(clampi(enh_level, 0, enhance_max()))))


## equip：部位 → 编码；enh：编码 → 强化等级
static func total_score(equip: Dictionary, enh: Dictionary) -> int:
	var t := 0
	for slot in equip:
		var pc := parse(str(equip[slot]))
		if not pc.is_empty():
			t += item_score(int(pc["rarity"]), int(enh.get(str(equip[slot]), 0)))
	return t
