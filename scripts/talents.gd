class_name Talents
extends RefCounted
## 天赋树（刚 / 柔 / 灵）。三系同时存在、自由加点；总点数 = 局外等级（含创建角色时的 1 点）。
## 每一层需要「本系已投入点数 ≥ 层号 × row_gate」才能解锁；三系各 7 层 × 5 点 = 35 点，总共只有 50 点，必须取舍。
## 校验逻辑在后端 Code.gs 里有同一份（节点表由 tools/sync_talents.py 生成）。


static func branches() -> Array:
	return ["gang", "rou", "ling"]


static func gate() -> int:
	return int(Data.talents["row_gate"])


## 全部节点：id → {id, name, max, stat, desc, branch, row}
## school_id：节点可以按流派覆盖名称 / 说明 / 属性（节点 id 和上限不变，所以后端校验不受影响）
static func nodes(school_id: String = "") -> Dictionary:
	var out := {}
	var br: Dictionary = Data.talents["branches"]
	for b in br:
		var rows: Array = br[b]["rows"]
		for r in rows.size():
			for n in rows[r]:
				var d: Dictionary = (n as Dictionary).duplicate()
				d["branch"] = b
				d["row"] = r
				var sch: Variant = d.get("schools", {})
				if school_id != "" and sch is Dictionary and (sch as Dictionary).has(school_id):
					var o: Dictionary = (sch as Dictionary)[school_id]
					for k in o:
						d[k] = o[k]
				out[d["id"]] = d
	return out


static func total_points(meta_level: int) -> int:
	return meta_level


static func clean(t: Variant) -> Dictionary:
	var out := {}
	if not t is Dictionary:
		return out
	var all := nodes()
	for id in t:
		if all.has(id):
			var r := clampi(int(t[id]), 0, int(all[id]["max"]))
			if r > 0:
				out[str(id)] = r
	return out


static func spent(t: Dictionary) -> int:
	var s := 0
	for id in t:
		s += int(t[id])
	return s


static func branch_spent(t: Dictionary, branch: String) -> int:
	var all := nodes()
	var s := 0
	for id in t:
		if all.has(id) and all[id]["branch"] == branch:
			s += int(t[id])
	return s


## 整套加点是否合法：每个有点数的节点所在层都已解锁，且总点数不超过可用点数
static func valid(t: Dictionary, meta_level: int) -> bool:
	var all := nodes()
	for id in t:
		if not all.has(id) or int(t[id]) < 0 or int(t[id]) > int(all[id]["max"]):
			return false
	if spent(t) > total_points(meta_level):
		return false
	for id in t:
		if int(t[id]) > 0:
			var n: Dictionary = all[id]
			# 解锁条件：本系「更低层」的投入合计 ≥ 层号 × row_gate
			var lower := 0
			for id2 in t:
				if all.has(id2) and all[id2]["branch"] == n["branch"] and int(all[id2]["row"]) < int(n["row"]):
					lower += int(t[id2])
			if lower < int(n["row"]) * gate():
				return false
	return true


static func can_add(t: Dictionary, id: String, meta_level: int) -> bool:
	var all := nodes()
	if not all.has(id) or int(t.get(id, 0)) >= int(all[id]["max"]):
		return false
	var t2 := t.duplicate()
	t2[id] = int(t.get(id, 0)) + 1
	return valid(t2, meta_level)


static func can_remove(t: Dictionary, id: String, meta_level: int) -> bool:
	if int(t.get(id, 0)) <= 0:
		return false
	var t2 := t.duplicate()
	t2[id] = int(t[id]) - 1
	if int(t2[id]) == 0:
		t2.erase(id)
	return valid(t2, meta_level)


## 天赋 → 局内属性加成
static func stats_for(t: Dictionary, school_id: String = "") -> Dictionary:
	var out := {}
	var all := nodes(school_id)
	for id in t:
		if not all.has(id):
			continue
		var st: Dictionary = all[id]["stat"]
		for k in st:
			out[k] = float(out.get(k, 0.0)) + float(st[k]) * int(t[id])
	return out


## 天赋里「针对具体招式」的强化用 "skill:<招式>:<项>" 作键，开局时并入该招式的 mods（targets 是个数，其余是小数比例）
static func split_skill_mods(stats: Dictionary) -> Array:
	var plain := {}
	var skill_mods := {}
	for k in stats:
		var key := str(k)
		if key.begins_with("skill:"):
			var parts := key.split(":")
			if parts.size() == 3:
				var m: Dictionary = skill_mods.get(parts[1], {})
				m[parts[2]] = float(m.get(parts[2], 0.0)) + float(stats[k])
				skill_mods[parts[1]] = m
		else:
			plain[key] = stats[k]
	return [plain, skill_mods]
