extends Node
## 全局数据（Autoload: Data）：读取 data/game_data.json，注册输入映射，加载可选字体。

const STAT_NAMES := {
	"damage": "伤害", "cooldown": "冷却", "count": "数量", "pierce": "穿透",
	"radius": "范围", "reach": "距离", "stun": "定身", "absorb": "化解",
}

var player_base: Dictionary = {}
var tuning: Dictionary = {}
var starters: Array = []
var skills: Dictionary = {}
var xinfa: Dictionary = {}
var qinggong: Dictionary = {}
var enemies: Dictionary = {}


func _ready() -> void:
	var f := FileAccess.open("res://data/game_data.json", FileAccess.READ)
	assert(f != null, "找不到 data/game_data.json")
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	assert(parsed is Dictionary, "game_data.json 解析失败")
	var d: Dictionary = parsed
	player_base = d["player"]
	tuning = d["tuning"]
	starters = d["starters"]
	skills = d["skills"]
	xinfa = d["xinfa"]
	qinggong = d["qinggong"]
	enemies = d["enemies"]
	_setup_input()
	_load_font()


func T(key: String) -> float:
	return float(tuning[key])


## 取按等级分档的数值：数组按 (level-1) 取值，标量直接返回。
func lv(def: Dictionary, key: String, level: int) -> float:
	var v: Variant = def.get(key)
	if v is Array:
		var arr: Array = v
		return float(arr[clampi(level - 1, 0, arr.size() - 1)])
	if v == null:
		return 0.0
	return float(v)


## 技能升级提示（根据数值表自动生成）。
func skill_upgrade_text(id: String, new_level: int) -> String:
	var def: Dictionary = skills[id]
	var parts: PackedStringArray = []
	for key in STAT_NAMES:
		if def.get(key) is Array:
			var a := lv(def, key, new_level - 1)
			var b := lv(def, key, new_level)
			if not is_equal_approx(a, b):
				parts.append("%s %s→%s" % [STAT_NAMES[key], _fmt(a), _fmt(b)])
	return "，".join(parts)


func tags_text(id: String) -> String:
	var t: Array = skills[id]["tags"]
	var out: PackedStringArray = []
	for x in t:
		out.append(str(x))
	return " ".join(out)


func _fmt(x: float) -> String:
	return str(int(x)) if is_equal_approx(x, roundf(x)) else "%.1f" % x


func _add_action(action: String, keys: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


func _setup_input() -> void:
	_add_action("move_left", [KEY_A, KEY_LEFT])
	_add_action("move_right", [KEY_D, KEY_RIGHT])
	_add_action("move_up", [KEY_W, KEY_UP])
	_add_action("move_down", [KEY_S, KEY_DOWN])
	_add_action("dash", [KEY_SPACE, KEY_SHIFT])
	_add_action("ult", [KEY_E])


## 若 assets/fonts/main.ttf|otf 存在则作为全局字体（解决部分平台缺中文字体的问题）。
func _load_font() -> void:
	for path in ["res://assets/fonts/main.ttf", "res://assets/fonts/main.otf"]:
		if ResourceLoader.exists(path):
			var font: Font = load(path)
			ThemeDB.fallback_font = font
			return
