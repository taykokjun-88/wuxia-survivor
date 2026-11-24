extends Node
## 把客户端认为「合法」的随机加点方案打印成 JSON（每行一个），交给 backend/test/talent_cross.js 用后端校验——两边规则必须一致。
## 运行：godot --headless --path . res://tests/talent_dump.tscn
func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	for sc in ["fist", "sword", "blade", "spear"]:
		var ids: Array = Talents.nodes(sc).keys()
		for level in [5, 15, 30, 50]:
			for trial in 6:
				var t := {}
				var guard := 0
				while guard < 3000 and Talents.spent(t, sc) < Talents.total_points(level):
					guard += 1
					var id: String = ids[rng.randi() % ids.size()]
					if Talents.can_add(t, id, level):
						t[id] = int(t.get(id, 0)) + 1
				print("TALENT_CASE ", JSON.stringify({"school": sc, "level": level, "t": t}))
	# 深度方案：按层从上到下把各系依次点满（会点到终极 / 巅峰 / 极意）
	for sc in ["fist", "sword", "blade", "spear"]:
		var all := Talents.nodes(sc)
		var ids2: Array = all.keys()
		ids2.sort_custom(func(a, b): return int(all[a]["row"]) < int(all[b]["row"]))
		for perm in [["gang", "rou", "ling"], ["ling", "gang", "rou"], ["rou", "ling", "gang"]]:
			for level in [30, 50]:
				var t2 := {}
				for br in perm:
					for id in ids2:
						if str(all[id]["branch"]) != br:
							continue
						while Talents.can_add(t2, id, level):
							t2[id] = int(t2.get(id, 0)) + 1
				for id in ids2:
					while Talents.can_add(t2, id, level):
						t2[id] = int(t2.get(id, 0)) + 1
				print("TALENT_CASE ", JSON.stringify({"school": sc, "level": level, "t": t2}))
	get_tree().quit()
