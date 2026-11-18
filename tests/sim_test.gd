extends Node
## 无渲染冒烟/性能测试：用 bot 跑完整局，输出每 30 秒的快照。
## 运行：godot --headless --path . res://tests/sim_test.tscn

const DT := 1.0 / 60.0


func _ready() -> void:
	var failures := 0
	for cfg in [
		{"name": "无敌 bot（压测 + Boss 流程）", "god": true, "seed": 1, "dur": 330.0},
		{"name": "普通 bot（难度参考）", "god": false, "seed": 2, "dur": 330.0},
		{"name": "普通 bot（难度参考，换种子）", "god": false, "seed": 3, "dur": 330.0},
	]:
		if not _run(cfg):
			failures += 1
	print("RESULT: %s" % ("FAIL" if failures > 0 else "OK"))
	get_tree().quit(1 if failures > 0 else 0)


func _run(cfg: Dictionary) -> bool:
	print("\n=== %s ===" % cfg["name"])
	var w := GameWorld.new()
	w.god = cfg["god"]
	w.rng_seed = cfg["seed"]
	add_child(w)
	var pick_rng := RandomNumberGenerator.new()
	pick_rng.seed = int(cfg["seed"]) * 7
	var steps := int(float(cfg["dur"]) / DT)
	var total_us := 0
	var worst_us := 0
	var peak_enemies := 0
	var next_report := 30.0
	var ok := true

	for i in steps:
		TestBot.drive(w)
		var t0 := Time.get_ticks_usec()
		w.step(DT)
		var us := Time.get_ticks_usec() - t0
		total_us += us
		worst_us = maxi(worst_us, us)
		peak_enemies = maxi(peak_enemies, w.enemies.size())
		while w.pending_levels > 0 and not w.over:
			var ch := w.roll_choices()
			if ch.is_empty():
				print("FAIL: roll_choices 返回空")
				ok = false
				break
			w.apply_choice(ch[pick_rng.randi() % ch.size()])
		if w.time >= next_report:
			next_report += 30.0
			print("t=%3ds lv=%2d hp=%3d neili=%3d enemies=%3d projs=%3d gems=%3d kills=%4d owned=%s" % [
				int(w.time), w.level, int(w.hp), int(w.neili), w.enemies.size(), w.projs.size(),
				w.gem_pos.size(), w.kills, str(w.owned)])
		if w.over:
			break

	var outcome := "胜利" if w.won else ("阵亡" if w.over else "存活到时限")
	print("结果：%s @ %.1fs  等级 %d  击杀 %d  Boss=%s" % [
		outcome, w.time, w.level, w.kills, "已刷出" if w.boss != null else "未刷出"])
	print("性能：平均 %.2f ms/step  最差 %.2f ms  敌人峰值 %d" % [
		total_us / 1000.0 / maxi(1, int(w.time / DT)), worst_us / 1000.0, peak_enemies])
	if cfg["god"] and w.time > 250.0 and w.boss == null:
		print("FAIL: 250s 后 Boss 未刷出")
		ok = false
	remove_child(w)
	w.free()
	return ok
