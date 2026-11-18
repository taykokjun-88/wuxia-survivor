extends Node
## 存档（Autoload: Save）：保存在 user://save.json。
## 目前只有角色流派；后续的天赋点、装备背包也放这里。

const DEFAULT_PATH := "user://save.json"

var path := DEFAULT_PATH
var data: Dictionary = {"school": "", "session": {}, "meta": {"exp": 0, "alloc": {}, "won": false}}


func _ready() -> void:
	load_data()


func load_data() -> void:
	data = {"school": "", "session": {}, "meta": {"exp": 0, "alloc": {}, "won": false}}
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
	var gained := Meta.run_exp(Score.compute(summary), bool(summary.get("won", false)), first)
	var old_level := Meta.level_of(meta_exp())
	var m := _meta()
	m["exp"] = meta_exp() + gained
	if bool(summary.get("won", false)):
		m["won"] = true
	save_data()
	var lv := Meta.level_of(meta_exp())
	return {"gained": gained, "exp": meta_exp(), "level": lv, "levelUp": lv > old_level}
