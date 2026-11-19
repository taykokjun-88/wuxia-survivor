class_name BossAI
extends RefCounted
## Boss / 杂兵的技能系统：每个技能 = 预警（红线 / 红圈 / 红扇形）→ 施放 → 收招。参数在 data.boss_skills。
## 预警期间玩家有时间走位；施放瞬间才判定伤害。红线 / 红圈 / 扇形由 draw_telegraph 画（在 GameWorld._draw 里调用）。

const WARN_COL := Color("#ff3a2a")


static func _d(id: String) -> Dictionary:
	return Data.boss_skills.get(id, {})


## Boss 每帧的 AI：返回这一帧的移动速度向量
static func think(w: GameWorld, e: Enemy, dt: float, dir: Vector2) -> Vector2:
	e.boss_timer += dt
	e.rage_t = maxf(0.0, e.rage_t - dt)
	e.summon_cd = maxf(0.0, e.summon_cd - dt)
	if e.type_id == "mini_boss_3":                    # 聚气罡盾：定期重新开盾（需催动 / 大招打破）
		e.shield_t -= dt
		if e.shield_t <= 0.0:
			e.shield_t = float(Data.enemies[e.type_id].get("shield_every", 16.0))
			if e.guard < e.guard_max * 0.5 and e.weak_t <= 0.0:
				e.guard = e.guard_max
				w.add_fx("text", e.pos + Vector2(0, -e.radius - 26), 1.2, {"text": "聚气罡盾", "size": 22, "color": Color("#4fe0d0")})
	if e.cast_id != "":
		return _cast(w, e, dt, dir)
	var spd := e.speed * (1.3 if e.rage_t > 0.0 else 1.0) * (e.slow_mult if e.slow_t > 0.0 else 1.0)
	e.skill_gap -= dt
	if e.skill_gap <= 0.0 and not e.skills.is_empty():
		_begin(w, e, dir)
	return dir * spd


static func _available(w: GameWorld, e: Enemy, id: String) -> bool:
	var d := _d(id)
	var dist := e.pos.distance_to(w.player_pos)
	if d.has("max_dist") and dist > float(d["max_dist"]):
		return false
	if id == "summon":
		return e.summon_cd <= 0.0
	return true


static func _begin(w: GameWorld, e: Enemy, dir: Vector2) -> void:
	var list: Array = e.skills.duplicate()
	if e.phase_hp > 0.0 and e.hp < e.max_hp * e.phase_hp:
		list.append_array(e.skills2)
	for i in list.size():
		var id := str(list[(e.skill_idx + i) % list.size()])
		if _available(w, e, id):
			e.skill_idx = (e.skill_idx + i + 1) % list.size()
			_start(w, e, id, dir)
			return
	e.skill_gap = 0.6


static func _exec_len(id: String, d: Dictionary) -> float:
	match id:
		"charge", "rush":
			return float(d["dur"])
		"claw":
			return float(d["gap"]) * float(int(d["hits"]) - 1) + 0.25
		"palm":
			return float(d["gap"]) * float(int(d["count"]) - 1) + 0.25
		"whirl":
			return float(d["gap"]) * float(int(d["rounds"])) + 0.2
		"blink":
			return float(d["after"]) + 0.4
		"leap":
			return float(d["fly"]) + 0.3
	return 0.35


static func _start(w: GameWorld, e: Enemy, id: String, dir: Vector2) -> void:
	var d := _d(id)
	e.cast_id = id
	e.cast_t = 0.0
	e.cast_stage = 0
	e.cast_dir = dir
	e.cast_start = e.pos
	e.cast_pos = w.player_pos
	e.cast_dur = float(d["warn"]) + _exec_len(id, d)
	if e.is_boss and e.is_final or e.is_boss:
		w.add_fx("text", e.pos + Vector2(0, -e.radius - 34), 1.0, {"text": str(d["name"]), "size": 24, "color": Color("#ff6a4a")})


static func _end(e: Enemy, gap_lo: float = 2.0, gap_hi: float = 3.2) -> void:
	e.cast_id = ""
	var rage := 0.7 if (e.phase_hp > 0.0 and e.hp < e.max_hp * 0.5) or e.hp < e.max_hp * 0.3 else 1.0
	e.skill_gap = (gap_lo + (gap_hi - gap_lo) * float(e.uid % 7) / 6.0 + 0.0) * rage


static func _mult(e: Enemy) -> float:
	return maxf(0.5, e.damage / 18.0)


static func _in_fan(w: GameWorld, origin: Vector2, dir: Vector2, reach: float, arc: float) -> bool:
	var to := w.player_pos - origin
	var dist := to.length()
	if dist > reach + GameWorld.PLAYER_RADIUS:
		return false
	if dist < 24.0:
		return true
	return absf(wrapf(to.angle() - dir.angle(), -PI, PI)) <= arc * 0.5


static func _in_circle(w: GameWorld, c: Vector2, r: float) -> bool:
	return w.player_pos.distance_to(c) <= r + GameWorld.PLAYER_RADIUS


static func _hurt(w: GameWorld, e: Enemy, dmg: float) -> void:
	if w.invuln <= 0.0:
		w._hurt(dmg * _mult(e))


static func _knock(w: GameWorld, from: Vector2, power: float) -> void:
	var v := w.player_pos - from
	w.player_knock = (v.normalized() if v.length() > 0.01 else Vector2.RIGHT) * power


static func _shot(w: GameWorld, pos: Vector2, ang: float, spd: float, dmg: float, radius: float, kind: String, life: float = 3.5) -> void:
	var p := Projectile.new()
	p.hostile = true
	p.kind = kind
	p.pos = pos
	p.vel = Vector2.from_angle(ang) * spd
	p.angle = ang
	p.radius = radius
	p.damage = dmg
	p.pierce = 1
	p.life = life
	w.projs.append(p)


static func _slash_fx(w: GameWorld, e: Enemy, d: Dictionary, dir: Vector2) -> void:
	w.add_fx("slash", e.pos, 0.3, {"angle": dir.angle(), "arc": float(d.get("arc", 2.0)), "r": float(d.get("reach", 120.0)), "heavy": true, "color": Color("#ff6a4a"),
		"vfx": str(d.get("vfx", "")), "size": float(d.get("reach", 120.0)) * 2.2})


static func _cast(w: GameWorld, e: Enemy, dt: float, dir: Vector2) -> Vector2:
	e.cast_t += dt
	var id := e.cast_id
	var d := _d(id)
	var warn := float(d["warn"])
	var t := e.cast_t
	var vel := Vector2.ZERO
	if t < warn:                                   # 预警：线 / 扇形跟着玩家转，最后 0.25 秒锁定
		if t < warn - 0.25:
			e.cast_dir = dir
			e.cast_pos = w.player_pos
		if id == "blink":
			e.cast_pos = w.player_pos - w.facing * 72.0
		return vel
	var u := t - warn                               # 施放后经过的时间
	match id:
		"charge", "rush":
			if u < float(d["dur"]):
				vel = e.cast_dir * float(d["speed"])
		"claw":
			var i := int(u / float(d["gap"]))
			if e.cast_stage <= i and i < int(d["hits"]):
				e.cast_stage = i + 1
				_slash_fx(w, e, d, e.cast_dir)
				if _in_fan(w, e.pos, e.cast_dir, float(d["reach"]), float(d["arc"])):
					_hurt(w, e, float(d["dmg"]))
				Sfx.play("boss_cleave")
		"whip", "cleave":
			if e.cast_stage == 0:
				e.cast_stage = 1
				_slash_fx(w, e, d, e.cast_dir)
				if _in_fan(w, e.pos, e.cast_dir, float(d["reach"]), float(d["arc"])):
					_hurt(w, e, float(d["dmg"]))
					if d.has("slow"):
						w.player_slow_t = float(d["slow"])
				w.shake = maxf(w.shake, 5.0)
				Sfx.play("boss_cleave")
		"stomp", "shock":
			if e.cast_stage == 0:
				e.cast_stage = 1
				var r := float(d["r"])
				w.add_fx("ring", e.pos, 0.45, {"r0": 16.0, "r1": r, "color": Color("#ff6a4a"), "vfx": str(d.get("vfx", "")), "size": r * 2.4})
				if _in_circle(w, e.pos, r):
					_hurt(w, e, float(d["dmg"]))
					_knock(w, e.pos, float(d["knock"]))
				w.shake = maxf(w.shake, 8.0)
				Sfx.play("boss_cleave")
		"claw_proj":
			if e.cast_stage == 0:
				e.cast_stage = 1
				var n := int(d["count"])
				for k in n:
					_shot(w, e.pos, e.cast_dir.angle() + (k - (n - 1) * 0.5) * float(d["spread"]), float(d["speed"]), float(d["dmg"]) * _mult(e), 10.0, str(d["kind"]))
				Sfx.play("enemy_ranged")
		"palm":
			var i2 := int(u / float(d["gap"]))
			if e.cast_stage <= i2 and i2 < int(d["count"]):
				e.cast_stage = i2 + 1
				_shot(w, e.pos, (w.player_pos - e.pos).angle(), float(d["speed"]), float(d["dmg"]) * _mult(e), 14.0, str(d["kind"]), 3.0)
				Sfx.play("enemy_ranged")
		"blink":
			if e.cast_stage == 0:
				e.cast_stage = 1
				w.add_fx("splat", e.pos, 0.5, {"r": e.radius * 1.6, "color": Color(0.05, 0.05, 0.08)})
				e.pos = e.cast_pos
				w.add_fx("splat", e.pos, 0.5, {"r": e.radius * 1.6, "color": Color(0.05, 0.05, 0.08)})
				e.cast_dir = (w.player_pos - e.pos).normalized()
			elif e.cast_stage == 1 and u >= float(d["after"]):
				e.cast_stage = 2
				var cd := _d("whip")
				_slash_fx(w, e, cd, e.cast_dir)
				if _in_fan(w, e.pos, e.cast_dir, float(cd["reach"]), float(cd["arc"])):
					_hurt(w, e, float(cd["dmg"]))
		"leap":
			var fly := float(d["fly"])
			if u < fly:
				e.pos = e.cast_start.lerp(e.cast_pos, clampf(u / fly, 0.0, 1.0))
			elif e.cast_stage == 0:
				e.cast_stage = 1
				e.pos = e.cast_pos
				var r2 := float(d["r"])
				w.add_fx("ring", e.pos, 0.5, {"r0": 16.0, "r1": r2, "color": Color("#ff6a4a"), "vfx": str(d.get("vfx", "")), "size": r2 * 2.4})
				if _in_circle(w, e.pos, r2):
					_hurt(w, e, float(d["dmg"]))
					_knock(w, e.pos, float(d["knock"]))
				w.shake = maxf(w.shake, 11.0)
				Sfx.play("boss_cleave")
		"whirl":
			var i3 := int(u / float(d["gap"]))
			if e.cast_stage <= i3 and i3 < int(d["rounds"]):
				e.cast_stage = i3 + 1
				var n2 := int(d["count"])
				var off := float(i3) * 0.31 + w.time
				for k2 in n2:
					_shot(w, e.pos, off + TAU * k2 / n2, float(d["speed"]), float(d["dmg"]) * _mult(e), 12.0, str(d["kind"]), 4.0)
				Sfx.play("enemy_ranged")
		"summon":
			if e.cast_stage == 0:
				e.cast_stage = 1
				e.summon_cd = float(d["cd"])
				e.rage_t = float(d["rage"])
				for k3 in int(d["n"]):
					var s := w._spawn_enemy(str(d["type"]), e.pos + Vector2.from_angle(TAU * k3 / float(d["n"]) + 0.4) * 100.0)
					s.speed *= 1.1
				w.add_fx("text", e.pos + Vector2(0, -e.radius - 50), 1.4, {"text": "狂暴！", "size": 30, "color": Color("#ff3a2a")})
				w.shake = maxf(w.shake, 6.0)
	if e.cast_t >= e.cast_dur:
		_end(e)
	return vel


## 杂兵行为：弓手（保持距离、预警后放冷箭）/ 蛮兵（预警后直线冲锋）
static func minion(w: GameWorld, e: Enemy, dt: float, dir: Vector2, d: float) -> Vector2:
	if e.cast_id != "":
		e.cast_t += dt
		var sd := _d(e.cast_id)
		var warn := float(sd["warn"])
		if e.cast_t < warn:
			if e.cast_t < warn - 0.2:
				e.cast_dir = dir
			return Vector2.ZERO
		var u := e.cast_t - warn
		var vel := Vector2.ZERO
		if e.cast_id == "arrow":
			if e.cast_stage == 0:
				e.cast_stage = 1
				_shot(w, e.pos, e.cast_dir.angle(), float(sd["speed"]), float(sd["dmg"]) * maxf(1.0, e.damage / 6.0), 7.0, "arrow", 2.5)
			if u > 0.25:
				_end(e, 1.8, 2.8)
		else:
			if u < float(sd["dur"]):
				vel = e.cast_dir * float(sd["speed"])
			else:
				_end(e, 2.6, 3.6)
		return vel
	e.skill_gap -= dt
	if e.behavior == "archer":
		if e.skill_gap <= 0.0 and d < 420.0:
			_start(w, e, "arrow", dir)
		if d < 220.0:
			return -dir * e.speed
		if d > 330.0:
			return dir * e.speed
		return dir.orthogonal() * e.speed * 0.5
	if e.skill_gap <= 0.0 and d < 380.0 and d > 90.0:
		_start(w, e, "rush", dir)
	return dir * e.speed


## 预警：红线 / 红圈 / 红扇形（越接近施放越红越实）；Boss 和杂兵共用
static func draw_telegraph(w: GameWorld, e: Enemy) -> void:
	var d := _d(e.cast_id)
	var warn := float(d["warn"])
	if e.cast_t >= warn:
		return
	var p := clampf(e.cast_t / warn, 0.0, 1.0)
	var pulse := 0.5 + 0.5 * sin(w.time * 18.0)
	var edge := Color(WARN_COL, 0.55 + 0.35 * pulse)
	var fill := Color(WARN_COL, 0.10 + 0.14 * p)
	var inner := Color(WARN_COL, 0.2 + 0.3 * p)
	match str(d["shape"]):
		"line":
			var ln := float(d["len"])
			var wd := float(d["width"])
			var a := e.cast_dir.angle()
			w.draw_set_transform(e.pos, a, Vector2.ONE)
			w.draw_rect(Rect2(0.0, -wd * 0.5, ln, wd), fill)
			w.draw_rect(Rect2(0.0, -wd * 0.5, ln * p, wd), inner)
			w.draw_rect(Rect2(0.0, -wd * 0.5, ln, wd), edge, false, 2.0)
			w.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		"fan":
			var reach := float(d["reach"])
			var arc := float(d["arc"])
			var a2 := e.cast_dir.angle()
			var pts := PackedVector2Array([e.pos])
			var pts2 := PackedVector2Array([e.pos])
			for i in 17:
				var ang := a2 - arc * 0.5 + arc * float(i) / 16.0
				pts.append(e.pos + Vector2.from_angle(ang) * reach)
				pts2.append(e.pos + Vector2.from_angle(ang) * reach * p)
			w.draw_colored_polygon(pts, fill)
			w.draw_colored_polygon(pts2, inner)
			w.draw_polyline(pts, edge, 2.0)
			w.draw_line(pts[pts.size() - 1], e.pos, edge, 2.0)
		"circle":
			var c := e.pos
			if e.cast_id == "leap" or e.cast_id == "blink":
				c = e.cast_pos
			var r := float(d["r"])
			w.draw_circle(c, r, fill)
			w.draw_circle(c, r * p, inner)
			w.draw_arc(c, r, 0.0, TAU, 40, edge, 3.0)
