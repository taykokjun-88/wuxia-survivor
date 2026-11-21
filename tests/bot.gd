class_name TestBot
extends RefCounted
## 测试用 bot：保持与最近敌人的交战距离（近战贴身、远程拉开）；被围时突围；
## 无敌人可打时去捡秘籍/经验；敌人贴身时轻功；内力满且敌多时放大招。


## 躲预警圈 / 来袭弹体（模拟「会看红圈的玩家」）。平衡测试里打开；其它测试保持原样
static var dodge := false
const DODGE_MARGIN := 34.0


## 预警区域里需要离开的方向（零向量 = 安全）。urgent：这一刻施法就要结算（该用轻功了）
static func danger_escape(w: GameWorld) -> Array:
	var pp := w.player_pos
	var esc := Vector2.ZERO
	var urgent := false
	for e in w.enemies:
		if not e.alive or e.cast_id == "":
			continue
		var sd: Dictionary = Data.boss_skills.get(e.cast_id, {})
		if sd.is_empty():
			continue
		var warn := float(sd["warn"])
		var left := warn - e.cast_t
		var shape := str(sd["shape"])
		var active := left > -0.05
		if shape == "line" and (e.cast_id in ["charge", "rush", "eagle_snake", "snow_palm", "thrust"]):
			active = e.cast_t < float(e.cast_dur)           # 冲锋期间也危险
		if not active:
			continue
		var fire_soon := left < 0.3
		match shape:
			"circle":
				var c := e.pos
				if e.cast_id in ["leap", "blink", "backstab"] or str(sd.get("at", "")) == "player":
					c = e.cast_pos
				var r := float(sd["r"]) + DODGE_MARGIN
				if pp.distance_to(c) < r:
					esc += (pp - c).normalized() * (r - pp.distance_to(c) + 40.0)
					urgent = urgent or fire_soon
			"fan":
				var reach := float(sd["reach"]) + DODGE_MARGIN
				var to := pp - e.pos
				if to.length() < reach and absf(wrapf(to.angle() - e.cast_dir.angle(), -PI, PI)) <= float(sd["arc"]) * 0.5 + 0.35:
					var side := signf(e.cast_dir.cross(to))
					esc += e.cast_dir.orthogonal() * (side if side != 0.0 else 1.0) * 100.0
					urgent = urgent or fire_soon
			"line":
				var ln := float(sd["len"])
				var wd := float(sd["width"]) * 0.5 + DODGE_MARGIN
				var rel := pp - e.pos
				var along := rel.dot(e.cast_dir)
				var off := rel.dot(e.cast_dir.orthogonal())
				if along > -20.0 and along < ln + 20.0 and absf(off) < wd:
					esc += e.cast_dir.orthogonal() * (signf(off) if off != 0.0 else 1.0) * 100.0
					urgent = urgent or fire_soon
			"rays":
				var base := e.cast_dir.angle() + float(sd["offset"])
				var nr := int(sd["n"])
				for k in nr:
					var ang := base + TAU * float(k) / float(nr)
					var dv := Vector2.from_angle(ang)
					var rel2 := pp - e.pos
					var al := rel2.dot(dv)
					var of := rel2.dot(dv.orthogonal())
					if al > -20.0 and al < float(sd["len"]) + 20.0 and absf(of) < float(sd["width"]) * 0.5 + DODGE_MARGIN:
						esc += dv.orthogonal() * (signf(of) if of != 0.0 else 1.0) * 100.0
						urgent = urgent or fire_soon
			"spots":
				for sp in e.cast_list:
					var rr := float(sd["r"]) + DODGE_MARGIN
					if pp.distance_to(sp) < rr:
						esc += (pp - sp).normalized() * 100.0
						urgent = urgent or fire_soon
	# 来袭弹体：预测 0.7 秒内会擦到就侧移
	for pr in w.projs:
		if not pr.hostile:
			continue
		var rel3: Vector2 = pp - pr.pos
		var vl: float = pr.vel.length()
		if vl < 1.0:
			continue
		var vd: Vector2 = pr.vel / vl
		var al2: float = rel3.dot(vd)
		if al2 < 0.0 or al2 > vl * 0.7:
			continue
		var of2: float = rel3.dot(vd.orthogonal())
		if absf(of2) < pr.radius + GameWorld.PLAYER_RADIUS + 22.0:
			esc += vd.orthogonal() * (signf(of2) if of2 != 0.0 else 1.0) * 60.0
	return [esc.normalized() if esc.length() > 0.01 else Vector2.ZERO, urgent]


## engage：期望的交战距离。近战技能传 ~70，远程传 ~240。
static func drive(w: GameWorld, engage: float = 220.0) -> void:
	var nearest: Enemy = null
	var nd := INF
	var push := Vector2.ZERO
	# 无敌模式（流程压测）：不逃跑，优先追打活着的 Boss，保证 Boss/秘籍/强化流程被覆盖
	var fearless := w.god
	var boss: Enemy = null
	if fearless:
		for b in w.bosses:
			if b.alive:
				boss = b
				break
	var crowd := 0
	for e in w.enemies:
		if e.is_prop or not e.alive:
			continue
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

	if boss != null:
		nearest = boss
		nd = w.player_pos.distance_to(boss.pos)
		crowd = 0
	var dir := Vector2.from_angle(w.time * 0.6)
	var strafe := Vector2.ZERO
	if nearest != null:
		var to := (nearest.pos - w.player_pos) / maxf(nd, 1.0)
		strafe = to.orthogonal()
		if crowd >= 8 and not fearless:
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
	if dodge and not w.god:
		var ds := danger_escape(w)
		if ds[0] != Vector2.ZERO:
			dir = ds[0]
			if bool(ds[1]) and w.invuln <= 0.0:
				w.input_dash = true
	w.input_move = dir

	if crowd >= 3 and w.invuln <= 0.0:
		w.input_dash = true
	if crowd > 10 and w.neili >= w.st("max_neili") * 0.7 and w.can_burst():
		w.input_ult = true


## 近战技能优先的 bot 使用的交战距离
static func engage_for(w: GameWorld) -> float:
	var melee := 0
	for s: SkillBase in w.skills.values():
		if s.tags().has("近战"):
			melee += 1
	return 75.0 if melee * 2 >= w.skills.size() else 240.0


const DIR_SCORE := {
	"damage": 8.0, "cooldown": 7.0, "hits": 6.0, "targets": 6.0, "range": 5.0,
	"crit": 4.0, "duration": 3.0, "debuff": 3.0, "heal": 2.0, "buff": 2.0,
}


## 「合格玩家」的选卡打分：优先输出向的新技能和伤害/冷却类升级，避开防御型的乾坤大挪移
static func score_card(w: GameWorld, c: Dictionary) -> float:
	match str(c["kind"]):
		"new_skill":
			return 4.0 if str(c["id"]) == "taiji" else 12.0
		"up_skill":
			var sc: float = DIR_SCORE.get(str(c["dir"]), 2.0) + float(c["tier"]) * 2.0
			if str(c["id"]) == "taiji":
				sc -= 5.0
			return sc
		"new_xinfa":
			return 7.0
		"up_xinfa":
			return 6.0
		"enhance":
			return 10.0
		"shi_new":
			return 12.0
		"shi_up":
			return 9.0 + float(c["gain"])
	return 1.0


## 处理所有待选项（升级 + 秘籍）。smart=false：纯随机（新手下限）；smart=true：按打分选（合格玩家）
static func resolve_choices(w: GameWorld, r: RandomNumberGenerator, smart: bool = false) -> bool:
	var ok := true
	while (w.pending_levels > 0 or w.pending_chests > 0) and not w.over:
		var ch: Array = w.roll_chest_choices() if w.pending_chests > 0 else w.roll_choices()
		if ch.is_empty():
			print("FAIL: 选项为空")
			ok = false
			break
		var pick: Dictionary = ch[r.randi() % ch.size()]
		if smart:
			var best := -INF
			for c in ch:
				var sc := score_card(w, c) + r.randf()
				if sc > best:
					best = sc
					pick = c
		w.apply_choice(pick)
	return ok
