class_name TestBot
extends RefCounted
## 测试用 bot：保持与最近敌人的交战距离（近战贴身、远程拉开）；被围时突围；
## 无敌人可打时去捡秘籍/经验；敌人贴身时轻功；内力满且敌多时放大招。


## engage：期望的交战距离。近战技能传 ~70，远程传 ~240。
static func drive(w: GameWorld, engage: float = 220.0) -> void:
	var nearest: Enemy = null
	var nd := INF
	var push := Vector2.ZERO
	var crowd := 0
	for e in w.enemies:
		var d := w.player_pos.distance_to(e.pos)
		if d < nd:
			nd = d
			nearest = e
		if d < 120.0:
			crowd += 1
			push += (w.player_pos - e.pos) / maxf(d, 1.0)

	# 秘籍 / 经验宝石
	var goal_dir := Vector2.ZERO
	var best := 450.0
	for g in w.gem_pos:
		var gd := w.player_pos.distance_to(g)
		if gd < best:
			best = gd
			goal_dir = (g - w.player_pos) / maxf(gd, 1.0)
	for c in w.chests:
		var cd := w.player_pos.distance_to(c)
		if cd < 900.0:
			goal_dir = (c - w.player_pos) / maxf(cd, 1.0)
			break

	var dir := Vector2.from_angle(w.time * 0.6)
	var strafe := Vector2.ZERO
	if nearest != null:
		var to := (nearest.pos - w.player_pos) / maxf(nd, 1.0)
		strafe = to.orthogonal()
		if crowd >= 8:
			dir = (push.normalized() * 1.5 + strafe * 0.5).normalized()   # 被围：突围
		elif goal_dir != Vector2.ZERO and nd > engage * 1.6:
			dir = goal_dir
		elif nd > engage * 1.15:
			dir = to
		elif nd < engage * 0.6:
			dir = (-to + strafe * 0.4).normalized()
		else:
			dir = strafe
	elif goal_dir != Vector2.ZERO:
		dir = goal_dir
	w.input_move = dir

	if crowd >= 3 and w.invuln <= 0.0:
		w.input_dash = true
	if crowd > 10 and w.neili >= w.st("max_neili"):
		w.input_ult = true


## 近战技能优先的 bot 使用的交战距离
static func engage_for(w: GameWorld) -> float:
	var melee := 0
	for s: SkillBase in w.skills.values():
		if s.tags().has("近战"):
			melee += 1
	return 75.0 if melee * 2 >= w.skills.size() else 240.0


## 处理所有待选项（升级 + 秘籍），随机挑选
static func resolve_choices(w: GameWorld, r: RandomNumberGenerator) -> bool:
	var ok := true
	while (w.pending_levels > 0 or w.pending_chests > 0) and not w.over:
		var ch: Array = w.roll_chest_choices() if w.pending_chests > 0 else w.roll_choices()
		if ch.is_empty():
			print("FAIL: 选项为空")
			ok = false
			break
		w.apply_choice(ch[r.randi() % ch.size()])
	return ok
