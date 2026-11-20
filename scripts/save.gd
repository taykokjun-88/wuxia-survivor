extends Node
## 存档（Autoload: Save）：保存在 user://save.json。
## 目前只有角色流派；后续的天赋点、装备背包也放这里。

const DEFAULT_PATH := "user://save.json"

var path := DEFAULT_PATH
var data: Dictionary = {"school": "", "session": {}, "meta": {"exp": 0, "alloc": {}, "won": false, "talents": {}, "items": [], "equip": {}, "silver": 0, "enh": {}, "cleared": {}}}


func _ready() -> void:
	load_data()


func load_data() -> void:
	data = {"school": "", "session": {}, "meta": {"exp": 0, "alloc": {}, "won": false, "talents": {}, "items": [], "equip": {}, "silver": 0, "enh": {}, "cleared": {}}}
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var json := JSON.new()
	if json.parse(f.get_as_text()) == OK and json.data is Dictionary:   # 损坏的存档视为空，不打印错误
		data.merge(json.data, true)
	# 流派必须是有效且已开放的，否则视为没有角色
	var s := str(data["school"])
	if s != "" and (not Data.schools.has(s) or not bool(Data.schools[s]["enabled"])):
		data["school"] = ""


func save_data() -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("无法写入存档: " + path)
		return
	f.store_string(JSON.stringify(data, "\t"))


func has_character() -> bool:
	return str(data["school"]) != ""


func school() -> String:
	return str(data["school"])


func create_character(school_id: String) -> void:
	data["school"] = school_id
	save_data()


## 登录会话（昵称 + 令牌）。令牌只是登录凭证，不含 PIN。
func session() -> Dictionary:
	var s: Variant = data.get("session", {})
	if s is Dictionary and str(s.get("nick", "")) != "" and str(s.get("token", "")) != "":
		return s
	return {}


func has_session() -> bool:
	return not session().is_empty()


func set_session(nick: String, token: String) -> void:
	data["session"] = {"nick": nick, "token": token}
	save_data()


func clear_session() -> void:
	data["session"] = {}
	save_data()


func reset_character() -> void:
	data["school"] = ""
	save_data()


# ---------------------------------------------------------------------
# 局外成长（修为 + 属性点分配）。登录时以服务器为准，本地只是缓存 / 单机存档。
# ---------------------------------------------------------------------

func _meta() -> Dictionary:
	var m: Variant = data.get("meta", {})
	if not m is Dictionary:
		m = {}
		data["meta"] = m
	return m


func meta_exp() -> int:
	return maxi(0, int(_meta().get("exp", 0)))


func meta_alloc() -> Dictionary:
	return Meta.clean_alloc(_meta().get("alloc", {}))


func meta_won() -> bool:
	return bool(_meta().get("won", false))


func store_meta(exp: int, alloc: Dictionary) -> void:
	var m := _meta()
	m["exp"] = maxi(0, exp)
	m["alloc"] = Meta.clean_alloc(alloc)
	save_data()


func set_meta_alloc(alloc: Dictionary) -> void:
	_meta()["alloc"] = Meta.clean_alloc(alloc)
	save_data()


## 单机结算：加修为，返回 {gained, exp, level, levelUp}
func add_run_exp(summary: Dictionary) -> Dictionary:
	var first := bool(summary.get("won", false)) and not meta_won()
	var gained := Meta.run_exp(Score.compute(summary), bool(summary.get("won", false)), first, Meta.comp_of(summary.get("difficulty", {})))
	var old_level := Meta.level_of(meta_exp())
	var m := _meta()
	m["exp"] = meta_exp() + gained
	if bool(summary.get("won", false)):
		m["won"] = true
		var cl := cleared()
		cl[str(summary.get("map", "black_wind"))] = true
		m["cleared"] = cl
	var sg := Gear.run_silver(Score.compute(summary), bool(summary.get("won", false)), Meta.comp_of(summary.get("difficulty", {})))
	m["silver"] = mini(int(Data.gear["silver"]["max"]), silver() + sg)
	save_data()
	var lv := Meta.level_of(meta_exp())
	return {"gained": gained, "exp": meta_exp(), "level": lv, "levelUp": lv > old_level, "silverGained": sg, "silver": silver()}


# ---------------------------------------------------------------------
# 天赋 / 装备（登录时以服务器为准，本地缓存 + 单机存档）
# ---------------------------------------------------------------------

func meta_talents() -> Dictionary:
	return Talents.repair(_meta().get("talents", {}), Meta.level_of(meta_exp()))


func set_meta_talents(t: Dictionary) -> void:
	_meta()["talents"] = Talents.clean(t)
	save_data()


func items() -> Array:
	var out := []
	var v: Variant = _meta().get("items", [])
	if v is Array:
		for c in v:
			if not Gear.parse(str(c)).is_empty():
				out.append(str(c))
	return out


## 已穿戴：部位 → 编码（编码必须在背包里）
func equip() -> Dictionary:
	var out := {}
	var inv := items()
	var e: Variant = _meta().get("equip", {})
	if e is Dictionary:
		for slot in e:
			var c := str(e[slot])
			if inv.has(c) and str(Gear.parse(c).get("slot", "")) == str(slot):
				out[str(slot)] = c
	return out


func set_gear(p_items: Array, p_equip: Dictionary) -> void:
	var m := _meta()
	m["items"] = p_items.duplicate()
	m["equip"] = p_equip.duplicate()
	save_data()


## 单机：直接加入背包（超过上限时丢掉最低稀有度、最早的未穿戴装备）
func add_items(codes: Array) -> void:
	var inv := items()
	var eq := equip()
	for c in codes:
		inv.append(str(c))
	while inv.size() > int(Data.gear["inventory_max"]):
		var worst := -1
		var worst_r := 99
		for i in inv.size():
			if eq.values().has(inv[i]):
				continue
			var r := int(Gear.parse(inv[i])["rarity"])
			if r < worst_r:
				worst_r = r
				worst = i
		if worst < 0:
			break
		inv.remove_at(worst)
	set_gear(inv, eq)


# ---------------------------------------------------------------------
# 银两 / 强化（登录时以服务器为准，本地缓存 + 单机存档）
# ---------------------------------------------------------------------

func silver() -> int:
	return maxi(0, int(_meta().get("silver", 0)))


## 强化等级：编码 → 级数（只保留背包里有的装备）
func enh() -> Dictionary:
	var out := {}
	var e: Variant = _meta().get("enh", {})
	var inv := items()
	if e is Dictionary:
		for c in e:
			if inv.has(str(c)) and int(e[c]) > 0:
				out[str(c)] = clampi(int(e[c]), 0, Gear.enhance_max())
	return out


func enh_level(code: String) -> int:
	return int(enh().get(code, 0))


func store_silver_enh(p_silver: int, p_enh: Dictionary) -> void:
	var m := _meta()
	m["silver"] = maxi(0, p_silver)
	m["enh"] = p_enh.duplicate()
	save_data()


## 单机：强化一件装备（扣银两）。返回 {ok, msg, silver, level, cost}
func enhance_local(code: String) -> Dictionary:
	var pc := Gear.parse(code)
	if pc.is_empty() or not items().has(code):
		return {"ok": false, "msg": "背包里没有这件装备"}
	var lv := enh_level(code)
	if lv >= Gear.enhance_max():
		return {"ok": false, "msg": "已经强化到顶了"}
	var cost := Gear.enhance_cost(int(pc["rarity"]), lv)
	if silver() < cost:
		return {"ok": false, "msg": "银两不够（需要 %d，现有 %d）" % [cost, silver()]}
	var e := enh()
	e[code] = lv + 1
	store_silver_enh(silver() - cost, e)
	return {"ok": true, "silver": silver(), "level": lv + 1, "cost": cost}


## 单机：丢弃（分解）装备换银两，并清掉强化记录
func discard_local(codes: Array) -> void:
	var e := enh()
	var gain := 0
	for c in codes:
		var pc := Gear.parse(str(c))
		if not pc.is_empty():
			gain += Gear.discard_silver(int(pc["rarity"]))
		e.erase(str(c))
	store_silver_enh(silver() + gain, e)


# ---------------------------------------------------------------------
# 通关记录（解锁新地图）与选关推荐条件
# ---------------------------------------------------------------------

func cleared() -> Dictionary:
	var c: Variant = _meta().get("cleared", {})
	return c if c is Dictionary else {}


func is_cleared(map_id: String) -> bool:
	return bool(cleared().get(map_id, false))


func set_cleared(c: Dictionary) -> void:
	_meta()["cleared"] = c.duplicate()
	save_data()


func gear_score() -> int:
	return Gear.total_score(equip(), enh())


## 地图是否已解锁：需要先通关 requires_clear 指定的地图
func map_unlocked(map_id: String) -> bool:
	var req := str(Data.maps[map_id].get("requires_clear", ""))
	return req == "" or is_cleared(req)


## 推荐条件（天赋点已投入 / 装备分数）→ [{label, ok}]
func recommend_status(map_id: String) -> Array:
	var rec: Dictionary = Data.maps[map_id].get("recommend", {})
	var out: Array = []
	if rec.has("talent_points"):
		var sp := Talents.spent(meta_talents())
		out.append({"label": "天赋点 %d / %d" % [sp, int(rec["talent_points"])], "ok": sp >= int(rec["talent_points"])})
	if rec.has("gear_score"):
		var gs := gear_score()
		out.append({"label": "装备分数 %d / %d" % [gs, int(rec["gear_score"])], "ok": gs >= int(rec["gear_score"])})
	return out
