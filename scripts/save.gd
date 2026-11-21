extends Node
## 存档（Autoload: Save）：保存在 user://save.json。多个角色（最多 5 个），每个角色有自己的流派、局外成长、天赋、装备。

const DEFAULT_PATH := "user://save.json"
const MAX_CHARS := 5            # 每个账号 / 每台设备最多 5 个角色

var path := DEFAULT_PATH
## data：session（登录）、ui（界面偏好）、chars（单机角色列表）、cur（当前单机角色 id）。
## 每个角色 = {id, name, school, meta{exp, alloc, won, talents, items, equip, silver, enh, cleared}}；局外等级 / 天赋 / 装备都按角色存。
var data: Dictionary = {"session": {}, "chars": [], "cur": ""}
var _cur: Dictionary = {}        # 当前角色（单机：指向 chars 里的某一项；在线：服务器角色的本地缓存）


static func new_meta() -> Dictionary:
	return {"exp": 0, "alloc": {}, "won": false, "talents": {}, "items": [], "equip": {}, "silver": 0, "enh": {}, "cleared": {}}


static func new_char(p_id: String, p_name: String, p_school: String) -> Dictionary:
	return {"id": p_id, "name": p_name, "school": p_school, "meta": new_meta()}


func _ready() -> void:
	load_data()


func load_data() -> void:
	data = {"session": {}, "chars": [], "cur": ""}
	_cur = {}
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f != null:
			var json := JSON.new()
			if json.parse(f.get_as_text()) == OK and json.data is Dictionary:   # 损坏的存档视为空，不打印错误
				data.merge(json.data, true)
	# 旧版存档（只有一个角色）：流派 / 局外成长挪进第一个角色
	if data.has("school") or data.has("meta"):
		var old_school := str(data.get("school", ""))
		if old_school != "" and (data["chars"] as Array).is_empty():
			var oc := new_char("c1", "侠客", old_school)
			if data.get("meta", {}) is Dictionary:
				oc["meta"].merge(data.get("meta", {}), true)
			data["chars"] = [oc]
			data["cur"] = "c1"
		elif old_school == "" and data.get("meta", {}) is Dictionary and not (data.get("meta", {}) as Dictionary).is_empty():
			data["scratch"] = {"id": "", "name": "", "school": "", "meta": data.get("meta", {})}
		data.erase("school")
		data.erase("meta")
	if not data["chars"] is Array:
		data["chars"] = []
	# 流派必须是有效且已开放的，否则这个角色丢弃
	var kept: Array = []
	for c in data["chars"]:
		if c is Dictionary and Data.schools.has(str(c.get("school", ""))) and bool(Data.schools[str(c["school"])]["enabled"]):
			if not c.get("meta", null) is Dictionary:
				c["meta"] = new_meta()
			c["meta"] = _merged_meta(c["meta"])
			kept.append(c)
	data["chars"] = kept
	if str(data.get("cur", "")) != "":
		select_char(str(data["cur"]))
	if _cur.is_empty() and data.get("scratch", null) is Dictionary:
		_cur = data["scratch"]
		_cur["id"] = ""
		_cur["meta"] = _merged_meta(_cur.get("meta", {}) if _cur.get("meta", {}) is Dictionary else {})
	if _cur.is_empty():
		_cur = new_char("", "", "")        # 还没有角色：一个空的草稿角色


static func _merged_meta(m: Dictionary) -> Dictionary:
	var out := new_meta()
	out.merge(m, true)
	return out


func save_data() -> void:
	if str(_cur.get("id", "")) == "":
		data["scratch"] = _cur.duplicate(true)       # 还没有角色时的草稿进度（兼容：先攒修为后建角色）
	else:
		data.erase("scratch")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("无法写入存档: " + path)
		return
	f.store_string(JSON.stringify(data, "\t"))


# ---------------------------------------------------------------------
# 角色（单机存档里的多角色；在线时角色在服务器上，这里只缓存当前这个）
# ---------------------------------------------------------------------

## 没能上传的成绩（断网 / 服务器忙）：[{nick, char, summary}]，之后自动补传
func pending_runs() -> Array:
	var p: Variant = data.get("pending", [])
	return p if p is Array else []


func add_pending(nick: String, char_id_v: String, summary: Dictionary) -> void:
	var p := pending_runs()
	p.append({"nick": nick, "char": char_id_v, "summary": summary})
	data["pending"] = p
	save_data()


func remove_pending(entry: Dictionary) -> void:
	var p := pending_runs()
	p.erase(entry)
	data["pending"] = p
	save_data()


func has_character() -> bool:
	return str(_cur.get("school", "")) != ""


func school() -> String:
	return str(_cur.get("school", ""))


func char_id() -> String:
	return str(_cur.get("id", ""))


func char_name() -> String:
	return str(_cur.get("name", ""))


## 单机角色列表（摘要）：[{id, name, school, level, exp}]
func chars() -> Array:
	var out: Array = []
	for c in data["chars"]:
		var xp := maxi(0, int((c["meta"] as Dictionary).get("exp", 0)))
		out.append({"id": str(c["id"]), "name": str(c["name"]), "school": str(c["school"]), "level": Meta.level_of(xp), "exp": xp})
	return out


## 新建一个单机角色（最多 5 个），返回它的 id；失败返回 ""
func add_char(p_name: String, p_school: String) -> String:
	if (data["chars"] as Array).size() >= MAX_CHARS or not Data.schools.has(p_school):
		return ""
	var id := "c%d" % (Time.get_ticks_usec() % 100000000)
	while _char_by_id(id) != null:
		id += "x"
	(data["chars"] as Array).append(new_char(id, p_name, p_school))
	save_data()
	return id


func delete_char(id: String) -> void:
	var list: Array = data["chars"]
	for i in list.size():
		if str(list[i]["id"]) == id:
			if _cur.get("id", "") == id:
				_cur = new_char("", "", "")
				data["cur"] = ""
			list.remove_at(i)
			break
	save_data()


func _char_by_id(id: String) -> Variant:
	for c in data["chars"]:
		if str(c["id"]) == id:
			return c
	return null


## 选中一个单机角色
func select_char(id: String) -> bool:
	var c: Variant = _char_by_id(id)
	if c == null:
		return false
	_cur = c
	data["cur"] = id
	save_data()
	return true


## 在线：切换到服务器上的某个角色（进度由调用方随后用 store_meta / set_* 灌进来）
func use_online_char(id: String, p_name: String, p_school: String) -> void:
	_cur = new_char("online:" + id, p_name, p_school)


## 兼容旧调用：给「当前角色」设流派；还没有角色就新建一个（名字「侠客」）
func create_character(school_id: String, p_name: String = "侠客") -> void:
	if str(_cur.get("id", "")) == "" and not _cur.is_empty():
		var id := add_char(p_name, school_id)
		if id != "":
			select_char(id)
			return
		_cur["school"] = school_id
		return
	_cur["school"] = school_id
	save_data()


## 清掉当前角色（测试清理用）
func reset_character() -> void:
	if str(_cur.get("id", "")) != "" and not str(_cur["id"]).begins_with("online:"):
		delete_char(str(_cur["id"]))
	_cur = new_char("", "", "")
	data["cur"] = ""
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


# ---------------------------------------------------------------------
# 局外成长（修为 + 属性点分配）。登录时以服务器为准，本地只是缓存 / 单机存档。
# ---------------------------------------------------------------------

func _meta() -> Dictionary:
	var m: Variant = _cur.get("meta", null)
	if not m is Dictionary:
		m = new_meta()
		_cur["meta"] = m
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
	var mx: Dictionary = Data.maps.get(str(summary.get("map", "black_wind")), {}).get("exp", {})
	var gained0 := Meta.run_exp(Score.compute(summary), bool(summary.get("won", false)), first, Meta.comp_of(summary.get("difficulty", {})), mx)
	var gained := Meta.capped(gained0, meta_exp(), int(mx.get("cap_level", 0)))
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
	return {"gained": gained, "capped": gained < gained0, "exp": meta_exp(), "level": lv, "levelUp": lv > old_level, "silverGained": sg, "silver": silver()}


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
	return Gear.total_score(equip(), enh(), school() if school() != "" else "fist", last_starter())


## 本角色上次出发选的起手招式（装备分的「适配度」按它算）
func last_starter() -> String:
	var ui: Variant = data.get("ui", {})
	if ui is Dictionary and (ui as Dictionary).get("last_starter", {}) is Dictionary:
		return str(((ui as Dictionary)["last_starter"] as Dictionary).get(char_id(), ""))
	return ""


func set_last_starter(starter_id: String) -> void:
	var ui: Variant = data.get("ui", {})
	if not ui is Dictionary:
		ui = {}
	var ls: Variant = (ui as Dictionary).get("last_starter", {})
	if not ls is Dictionary:
		ls = {}
	(ls as Dictionary)[char_id()] = starter_id
	(ui as Dictionary)["last_starter"] = ls
	data["ui"] = ui
	save_data()


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
