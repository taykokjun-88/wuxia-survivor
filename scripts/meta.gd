class_name Meta
extends RefCounted
## 局外成长：修为 → 局外等级（上限 50）→ 属性点；五种属性 → 局内加成。
## 公式在后端 Code.gs 里有同一份，测试用 backend/test/meta_vectors.json 对照。

const MAX_LEVEL := 50
const POINTS_PER_LEVEL := 3
const ATTR_CAP := 99
const EXP_CAP_PER_RUN := 400
const WIN_BONUS := 40
const FIRST_WIN_BONUS := 100

## id、名称、一句话作用
const ATTRS := [
	{"id": "pow", "name": "力道", "desc": "招式伤害 +%.1f%%"},
	{"id": "agi", "name": "身法", "desc": "移速 +%.1f%%　轻功冷却 −%.1f%%"},
	{"id": "vit", "name": "根骨", "desc": "气血 +%.0f　防御 +%.1f"},
	{"id": "int", "name": "内息", "desc": "内力上限 +%.0f　回复 +%.1f/秒"},
	{"id": "luk", "name": "福缘", "desc": "暴击率 +%.1f%%　高档位升级概率 +%.0f%%"},
]


## Lv L → L+1 所需修为
static func need(l: int) -> int:
	return 40 + 6 * l


## 到达某等级累计需要的修为（Lv1 为 0）
static func exp_to_reach(level: int) -> int:
	var t := 0
	for l in range(1, level):
		t += need(l)
	return t


static func level_of(exp: int) -> int:
	var l := 1
	var t := 0
	while l < MAX_LEVEL and t + need(l) <= exp:
		t += need(l)
		l += 1
	return l


## 当前等级内的进度：{level, into, need}；满级时 need = 0
static func progress(exp: int) -> Dictionary:
	var l := level_of(exp)
	if l >= MAX_LEVEL:
		return {"level": l, "into": 0, "need": 0}
	return {"level": l, "into": exp - exp_to_reach(l), "need": need(l)}


static func run_exp(score: int, won: bool, first_win: bool) -> int:
	var x := mini(EXP_CAP_PER_RUN, int(round(float(score) / 80.0)))
	if won:
		x += WIN_BONUS
		if first_win:
			x += FIRST_WIN_BONUS
	return x


static func points_total(level: int) -> int:
	return POINTS_PER_LEVEL * (level - 1)


static func points_used(alloc: Dictionary) -> int:
	var t := 0
	for a in ATTRS:
		t += int(alloc.get(a["id"], 0))
	return t


## 规范化：每项 0~99 的整数，只保留五种属性
static func clean_alloc(alloc: Variant) -> Dictionary:
	var out := {}
	for a in ATTRS:
		var v := 0
		if alloc is Dictionary:
			v = clampi(int((alloc as Dictionary).get(a["id"], 0)), 0, ATTR_CAP)
		out[a["id"]] = v
	return out


## 软上限：前 30 点每点 1，31~60 每点 0.6，61~99 每点 0.3
static func effective(points: int) -> float:
	var p := clampi(points, 0, ATTR_CAP)
	var e := float(mini(p, 30))
	if p > 30:
		e += 0.6 * float(mini(p, 60) - 30)
	if p > 60:
		e += 0.3 * float(p - 60)
	return e


## 属性点 → 局内属性加成（并入 GameWorld.talent_stats）
static func stats_for(alloc: Dictionary) -> Dictionary:
	var a := clean_alloc(alloc)
	var pw := effective(a["pow"])
	var ag := effective(a["agi"])
	var vi := effective(a["vit"])
	var ne := effective(a["int"])
	var lu := effective(a["luk"])
	return {
		"damage_pct": 0.005 * pw,
		"speed_pct": 0.003 * ag,
		"qg_cd_reduce": 0.004 * ag,
		"max_hp": 1.5 * vi,
		"armor": 0.04 * vi,
		"max_neili": 0.7 * ne,
		"neili_regen": 0.06 * ne,
		"crit_chance": 0.0015 * lu,
		"luck": 0.008 * lu,
	}


## 某项属性在给定点数下的效果文字
static func effect_text(attr_id: String, points: int) -> String:
	var e := effective(points)
	for a in ATTRS:
		if a["id"] != attr_id:
			continue
		match attr_id:
			"pow": return str(a["desc"]) % (0.5 * e)
			"agi": return str(a["desc"]) % [0.3 * e, 0.4 * e]
			"vit": return str(a["desc"]) % [1.5 * e, 0.04 * e]
			"int": return str(a["desc"]) % [0.7 * e, 0.06 * e]
			"luk": return str(a["desc"]) % [0.15 * e, 0.8 * e]
	return ""
