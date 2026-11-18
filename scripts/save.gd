extends Node
## 存档（Autoload: Save）：保存在 user://save.json。
## 目前只有角色流派；后续的天赋点、装备背包也放这里。

const DEFAULT_PATH := "user://save.json"

var path := DEFAULT_PATH
var data: Dictionary = {"school": "", "session": {}}


func _ready() -> void:
	load_data()


func load_data() -> void:
	data = {"school": "", "session": {}}
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
