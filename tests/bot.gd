class_name TestBot
extends RefCounted

## bot：远离敌群质心 + 绕圈漂移；敌人贴身时轻功；内力满且敌多时放大招。
static func drive(w: GameWorld) -> void:
	var push := Vector2.ZERO
	var near := 0
	for e in w.enemies:
		var d := w.player_pos.distance_to(e.pos)
		if d < 220.0:
			near += 1
			push += (w.player_pos - e.pos) / maxf(d, 1.0)
	var drift := Vector2.from_angle(w.time * 0.6)
	# 无近敌时去捡最近的经验宝石
	var gem_dir := Vector2.ZERO
	var best := 450.0
	for g in w.gem_pos:
		var gd := w.player_pos.distance_to(g)
		if gd < best:
			best = gd
			gem_dir = (g - w.player_pos) / maxf(gd, 1.0)
	var dir := drift
	if near > 0:
		dir = (push.normalized() * 1.5 + drift * 0.5 + gem_dir * 0.5).normalized()
	elif gem_dir != Vector2.ZERO:
		dir = gem_dir
	w.input_move = dir
	if near > 0 and w.invuln <= 0.0:
		for e in w.enemies:
			if w.player_pos.distance_to(e.pos) < 40.0:
				w.input_dash = true
				break
	if near > 10 and w.neili >= float(w.stats["max_neili"]):
		w.input_ult = true
