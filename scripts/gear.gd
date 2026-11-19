class_name Gear
extends RefCounted
## 装备：大 Boss 掉落，只会是本流派的。五个部位（武器 / 上衣 / 裤子 / 鞋子 / 饰品），五档稀有度。
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


## 本次掉落：胜利必掉 drops_per_win 件，另有「额外掉落」：期望 extra_drop_chance + (综合难度−1) × drop_bonus 件
## （整数部分必掉，小数部分按几率）
static func drop_count(rng: RandomNumberGenerator, comp: float) -> int:
	var bonus := float(Data.gear["extra_drop_chance"]) + (comp - 1.0) * float(Data.difficulty["drop_bonus"])
	return int(Data.gear["drops_per_win"]) + int(floorf(bonus)) + (1 if rng.randf() < bonus - floorf(bonus) else 0)


static func roll_drops(rng: RandomNumberGenerator, comp: float = 1.0) -> Array:
	var out := []
	for i in drop_count(rng, comp):
		out.append(roll_code(rng, 0, comp))
	return out


## 展开：{code, slot, slot_name, rarity, rarity_name, color, name, stats{key: value}, affixes[{kind,id,dir,v,text}]}
static func make(code: String, school_id: String = "fist") -> Dictionary:
	var pc := parse(code)
	if pc.is_empty():
		return {}
	var rng := RandomNumberGenerator.new()
	rng.seed = int(pc["seed"]) * 7919 + int(pc["rarity"]) * 104729 + (hash(pc["slot"]) & 0xFFFF)
	var rd := rarity_def(int(pc["rarity"]))
	var sd := slot_def(str(pc["slot"]))
	var mult := float(rd["mult"])
	var stats := {}
	var base: Dictionary = sd["base"]
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
	var names: Array = sd["names"]
	if school_id == "sword" and sd.has("sword_names"):
		names = sd["sword_names"]
	return {
		"code": code, "slot": pc["slot"], "slot_name": sd["name"], "rarity": pc["rarity"], "rarity_name": rd["name"],
		"color": rd["color"], "name": names[int(pc["seed"]) % names.size()], "stats": stats, "affixes": affixes,
	}


static func _roll_affix(rng: RandomNumberGenerator, school_id: String, mult: float, rarity: int, used: Dictionary) -> Dictionary:
	if rng.randf() < float(Data.gear["affix_xinfa_chance"]):
		var ids: Array = Data.xinfa.keys()
		var id: String = ids[rng.randi() % ids.size()]
		if not used.has("x" + id):
			used["x" + id] = true
			var lv := 2 if rarity >= 4 else 1
			return {"kind": "xinfa", "id": id, "v": lv, "text": "%s +%d 级" % [Data.xinfa[id]["name"], lv]}
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
	"speed_pct": ["移速", true], "qg_cd_reduce": ["轻功冷却缩减", true], "crit_chance": ["暴击", true], "max_neili": ["内力上限", false],
	"cd_reduce": ["冷却缩减", true], "luck": ["福缘", true], "exp_pct": ["经验", true],
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
