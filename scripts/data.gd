extends Node
## 全局数据（Autoload: Data）：读取 data/game_data.json，注册输入映射，加载可选字体。

var player_base: Dictionary = {}
var tuning: Dictionary = {}
var schools: Dictionary = {}      # 流派（创建角色时选择）：名称 / 是否可选 / 起手招式
var level_growth: Dictionary = {} # 角色每升 1 级的基础属性成长
var skills: Dictionary = {}
var xinfa: Dictionary = {}
var qinggong: Dictionary = {}
var directions: Dictionary = {}   # 升级方向
var tiers: Array = []             # 升级档位：小成 / 中成 / 大成 / 灵机一动
var max_upgrades := 11             # 技能最多升级次数（起始 1 层 → 最高 12 层）
var enemies: Dictionary = {}
var talents: Dictionary = {}      # 天赋树：{row_gate, branches}
var yinyang: Dictionary = {}      # 阴阳组合（调和 / 烈火 / 寒潭）
var harmony: Array = []           # 合璧：两个特定心法同时修习的额外效果
var town: Dictionary = {}         # 小镇：边界 / NPC / 建筑
var guide: Dictionary = {}        # 百晓生的玩法说明
var maps: Dictionary = {}         # 地图（黑风寨 / 华山…）
var difficulty: Dictionary = {}   # 综合难度带来的奖励系数
var shi: Array = []                # 独孤九剑的九「式」
var gear: Dictionary = {}         # 装备：部位 / 稀有度 / 词条池
var font_bold: Font               # 楷体粗体（"极"等需要突出的字）


func _ready() -> void:
	var f := FileAccess.open("res://data/game_data.json", FileAccess.READ)
	assert(f != null, "找不到 data/game_data.json")
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	assert(parsed is Dictionary, "game_data.json 解析失败")
	var d: Dictionary = parsed
	player_base = d["player"]
	tuning = d["tuning"]
	schools = d["schools"]
	level_growth = d["level_growth"]
	skills = d["skills"]
	xinfa = d["xinfa"]
	qinggong = d["qinggong"]
	directions = d["directions"]
	tiers = d["tiers"]
	max_upgrades = int(d["max_upgrades"])
	enemies = d["enemies"]
	talents = d["talents"]
	gear = d["gear"]
	shi = d.get("shi", [])
	town = d["town"]
	difficulty = d["difficulty"]
	maps = d["maps"]
	guide = d["guide"]
	yinyang = d["yinyang"]
	harmony = d["harmony"]
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


## 按权重抽取升级档位，返回档位下标（0 小成 … 3 灵机一动）
## luck：福缘带来的高档位（大成 / 灵机一动）权重加成，0.48 即这两档的权重 ×1.48
func roll_tier(rng: RandomNumberGenerator, luck: float = 0.0) -> int:
	var total := 0.0
	for i in tiers.size():
		total += _tier_weight(i, luck)
	var r := rng.randf() * total
	for i in tiers.size():
		r -= _tier_weight(i, luck)
		if r < 0.0:
			return i
	return 0


func _tier_weight(i: int, luck: float) -> float:
	return float(tiers[i]["weight"]) * (1.0 + luck if i >= 2 else 1.0)


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
## 自带的楷体字库（霞鹜文楷 LXGW WenKai，OFL 协议）。
## 浏览器里没有系统字体可回退，所以必须打包；UI 控件的默认字体在 project.godot 的 gui/theme/custom_font 里设置。
func _load_font() -> void:
	font_bold = ThemeDB.fallback_font
	if ResourceLoader.exists("res://assets/fonts/main.ttf"):
		ThemeDB.fallback_font = load("res://assets/fonts/main.ttf")
		font_bold = ThemeDB.fallback_font
	if ResourceLoader.exists("res://assets/fonts/main_bold.ttf"):
		font_bold = load("res://assets/fonts/main_bold.ttf")


## 两个心法能不能合璧：返回合璧定义，没有则返回空字典
func harmony_of(a: String, b: String) -> Dictionary:
	for h in harmony:
		var pr: Array = h["pair"]
		if (pr[0] == a and pr[1] == b) or (pr[0] == b and pr[1] == a):
			return h
	return {}


## 两个心法的阴阳组合：yinyang 里的键；不满两个或没有组合返回 ""
func yinyang_of(a: String, b: String) -> String:
	var ya := str(xinfa[a].get("yy", ""))
	var yb := str(xinfa[b].get("yy", ""))
	if ya == "" or yb == "":
		return ""
	if ya == yb:
		return "double_" + ya
	return "harmony"


var _icons: Dictionary = {}

## 技能 / 心法图标（assets/icons/<kind>/<id>.png）；没有则返回 null，调用方画占位
func icon(kind: String, id: String) -> Texture2D:
	var key := kind + "/" + id
	if not _icons.has(key):
		var path := "res://assets/icons/%s.png" % key
		_icons[key] = load(path) if ResourceLoader.exists(path) else null
	return _icons[key]
