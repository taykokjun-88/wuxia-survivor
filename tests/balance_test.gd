extends Node
## 平衡矩阵：会选卡、不无敌的 bot，按「局外等级 / 属性点打法 / 装备分 / 天赋」配置跑多局，输出通关与否。
## 环境变量：SCHOOL(fist|sword|blade)、MAP、LV(局外等级)、ALLOC(none|pow|vit|bal|agi|luk)、GEAR(0|20|50)、TAL(none|gang|rou|ling)、SEEDS(每个起手招式跑几局)
## 运行：godot --headless --path . res://tests/balance_test.tscn

const DT := 1.0 / 60.0
const ALLOCS := {
	"none": {}, "pow": {"pow": 27}, "vit": {"vit": 27}, "agi": {"agi": 27}, "luk": {"luk": 27},
	"bal": {"pow": 9, "vit": 9, "int": 9},
}


func _ready() -> void:
	var school := OS.get_environment("SCHOOL")
	var map_id := OS.get_environment("MAP") if OS.get_environment("MAP") != "" else "black_wind"
	var lv := int(OS.get_environment("LV")) if OS.get_environment("LV") != "" else 1
	var alloc_name := OS.get_environment("ALLOC") if OS.get_environment("ALLOC") != "" else "none"
	var gear_score := int(OS.get_environment("GEAR")) if OS.get_environment("GEAR") != "" else 0
	var tal := OS.get_environment("TAL") if OS.get_environment("TAL") != "" else "none"
	var seeds := int(OS.get_environment("SEEDS")) if OS.get_environment("SEEDS") != "" else 2
	var alloc: Dictionary = ALLOCS[alloc_name]
	if lv < 10:
		alloc = {}
	else:
		var pts := Meta.points_total(lv)
		if alloc_name != "none" and pts != 27:      # 按等级缩放点数
			var scaled := {}
			for k in alloc:
				scaled[k] = int(round(float(alloc[k]) * float(pts) / 27.0))
			alloc = scaled
	var talents := _talents(school, tal, lv)
	var equip := _equip(gear_score)
	var starters: Array = Data.schools[school]["starters"]
	for st in starters:
		for k in seeds:
			var sd := 100 + k * 7 + starters.find(st)
			var w := GameWorld.new()
			w.rng_seed = sd
			add_child(w)
			Build.apply_to(w, alloc, talents, equip, school)
			w.meta_level = lv
			w.start_run(str(st), ["tashue", "feiyan", "yufeng", "lingshe"][sd % 4], map_id)
			var pick_rng := RandomNumberGenerator.new()
			pick_rng.seed = sd
			for i in int(1000.0 / DT):
				TestBot.drive(w, TestBot.engage_for(w))
				w.step(DT)
				TestBot.resolve_choices(w, pick_rng, true)
				if w.over:
					break
			var cause := ""
			if not w.won:
				cause = "超时未击败 Boss" if w.timeout_fail else "阵亡"
			print("RES|%s|%s|%s|lv%d|%s|gear%d|%s|seed%d|%s|%d|Lv%d|kills%d|%s" % [school, st, map_id, lv, alloc_name, gear_score, tal, sd, "WIN" if w.won else "LOSE", int(w.time), w.level, w.kills, cause])
			w.queue_free()
	get_tree().quit()


## 天赋：按偏好顺序把点数花完（刚 / 柔 / 灵 三系，哪个在前先点哪个）
func _talents(school: String, plan: String, lv: int) -> Dictionary:
	if plan == "none" or lv < 2:
		return {}
	var order: Array = {"gang": ["gang", "rou", "ling"], "rou": ["rou", "gang", "ling"], "ling": ["ling", "gang", "rou"]}[plan]
	var nodes := Talents.nodes(school)
	var t := {}
	var left := Talents.total_points(lv)
	var progressed := true
	while left > 0 and progressed:
		progressed = false
		for b in order:
			var ids: Array = []
			for id in nodes:
				if str(nodes[id]["branch"]) == b:
					ids.append(id)
			ids.sort_custom(func(x, y): return int(nodes[x]["row"]) < int(nodes[y]["row"]))
			for id in ids:
				if Talents.can_add(t, str(id), lv):
					t[str(id)] = int(t.get(str(id), 0)) + 1
					left -= 1
					progressed = true
					break
			if progressed:
				break
	return t


## 装备分：普通 5 / 特别 10 / 稀有 20 / 传说 40；20 分 = 两件特别（武器 + 上衣），50 分 = 五件特别
func _equip(score: int) -> Dictionary:
	if score >= 50:
		return {"weapon": "weapon.1.111", "coat": "coat.1.222", "pants": "pants.1.333", "boots": "boots.1.444", "charm": "charm.1.555"}
	if score >= 20:
		return {"weapon": "weapon.1.111", "coat": "coat.1.222"}
	return {}
