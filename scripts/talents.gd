class_name Talents
extends RefCounted
## 天赋树。两种：
##   旧树（刚 / 柔 / 灵 三系 × 7 层 × 每层 2 穴，剑 / 刀 / 杨家将暂时仍用，组名 legacy）；
##   新树（data/talent_trees.json，按流派，RO 式：每系 50 点、4 列、前置连线 + 层门槛；目前只有武者 fist）。
## 每个「组」（legacy / fist / …）各有一份预算：总点数 = 局外等级 × 每级点数（2）；点满 99 点后出现第 100 点「极意」。
## 存档里是一份 id → 点数 的大字典（各组的 id 互不重复），校验按组分别进行。后端 Code.gs 有同一份（节点表由 tools/sync_talents.py 生成）。


## 新树的前置类型：one = 前置节点 ≥1 点；full = 前置节点点满
static func has_tree(school_id: String) -> bool:
	return Data.talent_trees.has(school_id)


static func group_of(school_id: String) -> String:
	return school_id if has_tree(school_id) else "legacy"


static func tree(school_id: String) -> Dictionary:
	return Data.talent_trees.get(school_id, {})


static func tree_gates(school_id: String) -> Array:
	return tree(school_id).get("gates", [])


static func groups() -> Array:
	var out: Array = ["legacy"]
	for k in Data.talent_trees:
		out.append(str(k))
	return out


## 某组的全部节点：id → {id, name, max, stat, desc, branch, row, group, ...}；legacy 组可按流派覆盖名称 / 说明 / 属性
static func group_nodes(group: String, school_id: String = "") -> Dictionary:
	var out := {}
	if group == "legacy":
		var br: Dictionary = Data.talents["branches"]
		for b in br:
			var rows: Array = br[b]["rows"]
			for r in rows.size():
				for n in rows[r]:
					var d: Dictionary = (n as Dictionary).duplicate()
					d["branch"] = b
					d["row"] = r
					d["group"] = "legacy"
					var sch: Variant = d.get("schools", {})
					if school_id != "" and sch is Dictionary and (sch as Dictionary).has(school_id):
						var o: Dictionary = (sch as Dictionary)[school_id]
						for k in o:
							d[k] = o[k]
					out[d["id"]] = d
		var ji: Dictionary = (Data.talents["ji"] as Dictionary).duplicate()          # 「极意」：三系点满后出现的第 100 点
		ji["branch"] = "ji"
		ji["row"] = 7
		ji["group"] = "legacy"
		if school_id != "" and (ji["schools"] as Dictionary).has(school_id):
			var jo: Dictionary = ji["schools"][school_id]
			for k in jo:
				ji[k] = jo[k]
		out[ji["id"]] = ji
	else:
		var tr: Dictionary = tree(group)
		var gates: Array = tr.get("gates", [])
		for b in tr["branches"]:
			for n in tr["branches"][b]["nodes"]:
				var d2: Dictionary = (n as Dictionary).duplicate()
				d2["branch"] = b
				d2["group"] = group
				d2["gate"] = int(gates[int(d2["tier"]) - 1])
				out[d2["id"]] = d2
		var j2: Dictionary = (tr["ji"] as Dictionary).duplicate()
		j2["branch"] = "ji"
		j2["row"] = 10
		j2["group"] = group
		out[j2["id"]] = j2
	return out


## 当前流派用的那一组节点
static func nodes(school_id: String = "") -> Dictionary:
	return group_nodes(group_of(school_id), school_id)


## 所有组的节点合并（清理存档用，不含流派覆盖）
static var _all_cache: Dictionary = {}


static func all_nodes() -> Dictionary:
	if _all_cache.is_empty():                          # 数据启动后不会变；缓存起来（界面每帧都要判断节点状态）
		for g in groups():
			_all_cache.merge(group_nodes(g))
	return _all_cache


## —— 旧树（legacy）的辅助 ——
static func branches() -> Array:
	return ["gang", "rou", "ling"]


static func gate() -> int:
	return int(Data.talents["row_gate"])


static func ji_id() -> String:
	return str(Data.talents["ji"]["id"])


## 三系点满所需的点数（极意 穴位出现的条件）。新旧树都是 99
static func ji_need() -> int:
	return int(Data.talents["ji"]["need"])


## 旧树某一系的点数上限
static func branch_cap(branch: String) -> int:
	var s := 0
	for row in Data.talents["branches"][branch]["rows"]:
		for n in row:
			s += int(n["max"])
	return s


static func total_points(meta_level: int) -> int:
	return meta_level * int(Data.talents.get("per_level", 1))


static func clean(t: Variant) -> Dictionary:
	var out := {}
	if not t is Dictionary:
		return out
	var all := all_nodes()
	for id in t:
		if all.has(id):
			var r := clampi(int(t[id]), 0, int(all[id]["max"]))
			if r > 0:
				out[str(id)] = r
	return out


## 某一组（流派）的子集 / 点数
static func subset(t: Dictionary, group: String) -> Dictionary:
	var all := all_nodes()
	var out := {}
	for id in t:
		if all.has(id) and all[id]["group"] == group:
			out[id] = t[id]
	return out


## 已投入点数：school_id 为空 = 全部；否则只算该流派那一组
static func spent(t: Dictionary, school_id: String = "") -> int:
	var src := t if school_id == "" else subset(t, group_of(school_id))
	var s := 0
	for id in src:
		s += int(src[id])
	return s


## 同一「系」（branch）已投入的点数（旧树：school_id 为空；新树：传流派）
static func branch_spent(t: Dictionary, branch: String, school_id: String = "") -> int:
	var all := nodes(school_id)
	var s := 0
	for id in t:
		if all.has(id) and all[id]["branch"] == branch:
			s += int(t[id])
	return s


## 整套加点是否合法（每一组各自检查）
static func valid(t: Dictionary, meta_level: int) -> bool:
	var all := all_nodes()
	for id in t:
		if not all.has(id) or int(t[id]) < 0 or int(t[id]) > int(all[id]["max"]):
			return false
	for g in groups():
		if not _valid_group(subset(t, g), meta_level, g, all):
			return false
	return true


static func _valid_group(t: Dictionary, meta_level: int, group: String, all: Dictionary) -> bool:
	var total := 0
	for id in t:
		total += int(t[id])
	if total > total_points(meta_level):
		return false
	for id in t:
		if int(t[id]) <= 0:
			continue
		var n: Dictionary = all[id]
		if n["branch"] == "ji":                       # 极意：本组其余节点共 99 点之后才出现
			if total - int(t[id]) < ji_need():
				return false
			continue
		if group == "legacy":
			# 旧树：本系「更低层」的投入合计 ≥ 层号 × row_gate
			var lower := 0
			for id2 in t:
				if all[id2]["branch"] == n["branch"] and int(all[id2]["row"]) < int(n["row"]):
					lower += int(t[id2])
			if lower < int(n["row"]) * gate():
				return false
		else:
			# 新树：本系其余节点已投入 ≥ 层门槛；前置节点（≥1 点 / 点满）；巅峰需要本系至少一个终极
			var bsum := 0
			var has_cap := false
			for id2 in t:
				if all[id2]["branch"] == n["branch"]:
					if id2 != id:
						bsum += int(t[id2])
					if bool(all[id2].get("cap", false)) and int(t[id2]) > 0:
						has_cap = true
			if bsum < int(n["gate"]):
				return false
			for rq in n.get("req", []):
				var have := int(t.get(rq[0], 0))
				if have < (int(all[rq[0]]["max"]) if rq[1] == "full" else 1):
					return false
			if bool(n.get("peak", false)) and not has_cap:
				return false
	return true


## 把不合法的加点修成合法：从最靠后的节点往下减点，直到每一组都合法
static func repair(t: Dictionary, meta_level: int) -> Dictionary:
	var out := clean(t)
	var all := all_nodes()
	var guard := 0
	while not valid(out, meta_level) and guard < 800:
		guard += 1
		var worst := ""
		var worst_row := -1
		for id in out:
			var r := int(all[id]["row"])
			if r > worst_row:
				worst_row = r
				worst = str(id)
		if worst == "":
			break
		out[worst] = int(out[worst]) - 1
		if int(out[worst]) <= 0:
			out.erase(worst)
	return out


static func can_add(t: Dictionary, id: String, meta_level: int) -> bool:
	var all := all_nodes()
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


## 天赋 → 局内属性加成（只算当前流派那一组）
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
