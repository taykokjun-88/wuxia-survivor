class_name BossAI
extends RefCounted
## Boss / 杂兵的技能系统：每个技能 = 预警（红线 / 红圈 / 红扇形）→ 施放 → 收招。参数在 data.boss_skills。
## 预警期间玩家有时间走位；施放瞬间才判定伤害。红线 / 红圈 / 扇形由 draw_telegraph 画（在 GameWorld._draw 里调用）。

const WARN_COL := Color("#ff3a2a")


static func _d(id: String) -> Dictionary:
	return Data.boss_skills.get(id, {})


## 某个 Boss 的专属特效 / 弹体覆盖（敌人定义里的 vfx_map / proj_kind_map）：同一个招式在不同 Boss 身上画不同的特效（桃花岛四人）
static func _vx(e: Enemy, id: String, d: Dictionary) -> String:
	var m: Dictionary = Data.enemies.get(e.type_id, {}).get("vfx_map", {})
	return str(m.get(id, d.get("vfx", "")))


static func _pk(e: Enemy, id: String, d: Dictionary) -> String:
	var m: Dictionary = Data.enemies.get(e.type_id, {}).get("proj_kind_map", {})
	return str(m.get(id, d.get("kind", "")))


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
		"blink", "backstab":
			return float(d["after"]) + 0.4
		"palm_seal", "sword_rain":
			return float(d["gap"]) * float(int(d["n"])) + 0.3
		"eagle_snake", "snow_palm":
			return float(d["dur"])
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
	e.cast_pos = w.player_pos - w.facing * 72.0 if (id == "blink" or id == "backstab") else w.player_pos     # 瞄准点在开始施放这一刻就锁定
	e.cast_dur = float(d["warn"]) + _exec_len(id, d)
	e.cast_list.clear()
	if str(d["shape"]) == "spots":                 # 多点落点：第一个落在玩家脚下，其余散在周围
		for k in int(d["n"]):
			var off := Vector2.ZERO if k == 0 else Vector2.from_angle(w.rng.randf() * TAU) * w.rng.randf_range(40.0, float(d["around"]))
			e.cast_list.append(w.player_pos + off)
	if e.is_boss and e.is_final or e.is_boss:
		w.add_fx("text", e.pos + Vector2(0, -e.radius - 34), 1.0, {"text": str(d["name"]), "size": 24, "color": Color("#ff6a4a")})


static func _end(e: Enemy, gap_lo: float = 2.0, gap_hi: float = 3.2) -> void:
	e.cast_id = ""
	var rage := 0.7 if (e.phase_hp > 0.0 and e.hp < e.max_hp * 0.5) or e.hp < e.max_hp * 0.3 else 1.0
	e.skill_gap = (gap_lo + (gap_hi - gap_lo) * float(e.uid % 7) / 6.0 + 0.0) * rage


static func _mult(e: Enemy) -> float:
	return maxf(0.5, e.damage / 18.0) * e.atk_mul()


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


static func _near_segment(p: Vector2, a: Vector2, b: Vector2, r: float) -> bool:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1.0), 0.0, 1.0)
	return p.distance_to(a + ab * t) <= r


## 大 Boss 进入第二阶段：震退玩家、大字、护盾、加攻 / 速 / 防，追加招式
static func enter_phase2(w: GameWorld, e: Enemy) -> void:
	e.phase2 = true
	var d: Dictionary = e.phase2_def
	e.shield_max = e.max_hp * float(d["shield"])
	e.shield = e.shield_max
	e.damage *= float(d["atk"])
	e.speed *= float(d["speed"])
	e.defense = float(d["defense"])
	for sk in d.get("add", []):
		e.skills.append(str(sk))
	e.cast_id = ""
	e.skill_gap = 1.2
	e.invuln_t = 0.0
	_knock(w, e.pos, float(d.get("knock", 600.0)))
	w.add_fx("text", e.pos + Vector2(0, -e.radius - 70), 3.0, {"text": str(d.get("text", "")), "size": 44, "color": Color("#bfe8ff")})
	w.add_fx("ring", e.pos, 0.8, {"r0": 20.0, "r1": 420.0, "color": Color("#bfe8ff"), "vfx": "boss_phase2_burst" if w.vfx.has("boss_phase2_burst") else "burst_break", "size": 560.0})
	w.shake = maxf(w.shake, 14.0)
	if w.tulong_equipped and e.is_final:                    # 彩蛋：屠龙宝刀对倚天剑
		w.tulong_on = true
		w.add_fx("text", w.player_pos + Vector2(0, -110), 3.0, {"text": "屠龙宝刀，天下至尊", "size": 40, "color": Color("#ffb030")})
	Sfx.play("boss_warn")


static func _knock(w: GameWorld, from: Vector2, power: float) -> void:
	var v := w.player_pos - from
	w.player_knock = (v.normalized() if v.length() > 0.01 else Vector2.RIGHT) * power


static func _shot(w: GameWorld, pos: Vector2, ang: float, spd: float, dmg: float, radius: float, kind: String, life: float = 3.5, cuttable: bool = false) -> void:
	var p := Projectile.new()
	p.hostile = true
	p.cuttable = cuttable
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
	if t < warn:                                   # 预警（施法）：方向 / 落点在 _start 时已锁定，之后不再跟随主角，留出走位时间
		return vel
	var u := t - warn                               # 施放后经过的时间
	match id:
		"charge", "rush", "eagle_snake", "snow_palm":
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
		"whip", "cleave", "dragon_claw", "snow_cleave":
			if e.cast_stage == 0:
				e.cast_stage = 1
				_slash_fx(w, e, d, e.cast_dir)
				if _in_fan(w, e.pos, e.cast_dir, float(d["reach"]), float(d["arc"])):
					_hurt(w, e, float(d["dmg"]))
					if d.has("slow"):
						w.player_slow_t = float(d["slow"])
				w.shake = maxf(w.shake, 5.0)
				Sfx.play("boss_cleave")
		"stomp", "shock", "bell_shock", "buddha_light":
			if e.cast_stage == 0:
				e.cast_stage = 1
				var r := float(d["r"])
				w.add_fx("ring", e.pos, 0.45, {"r0": 16.0, "r1": r, "color": Color("#ff6a4a"), "vfx": _vx(e, id, d), "size": r * 2.4})
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
					_shot(w, e.pos, e.cast_dir.angle() + (k - (n - 1) * 0.5) * float(d["spread"]), float(d["speed"]), float(d["dmg"]) * _mult(e), 10.0, _pk(e, id, d))
				Sfx.play("enemy_ranged")
		"palm":
			var i2 := int(u / float(d["gap"]))
			if e.cast_stage <= i2 and i2 < int(d["count"]):
				e.cast_stage = i2 + 1
				_shot(w, e.pos, (w.player_pos - e.pos).angle(), float(d["speed"]), float(d["dmg"]) * _mult(e), 14.0, str(d["kind"]), 3.0)
				Sfx.play("enemy_ranged")
		"blink", "backstab":
			if e.cast_stage == 0:
				e.cast_stage = 1
				w.add_fx("splat", e.pos, 0.5, {"r": e.radius * 1.6, "color": Color(0.05, 0.05, 0.08)})
				var bv := _vx(e, id, d)
				if bv != "" and w.vfx.has(bv):          # 桃花瓣：起跳点和落点各散一次
					w.add_fx("ring", e.pos, 0.5, {"r0": 10.0, "r1": 10.0, "color": Color.WHITE, "vfx": bv, "size": 190.0})
				e.pos = e.cast_pos
				w.add_fx("splat", e.pos, 0.5, {"r": e.radius * 1.6, "color": Color(0.05, 0.05, 0.08)})
				if bv != "" and w.vfx.has(bv):
					w.add_fx("ring", e.pos, 0.5, {"r0": 10.0, "r1": 10.0, "color": Color.WHITE, "vfx": bv, "size": 190.0})
				e.cast_dir = (w.player_pos - e.pos).normalized()
			elif e.cast_stage == 1 and u >= float(d["after"]):
				e.cast_stage = 2
				var cd := _d("whip") if id == "blink" else {"reach": 150.0, "arc": 2.2, "dmg": float(d["dmg2"]), "vfx": "boss_whip_arc"}
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
				w.add_fx("ring", e.pos, 0.5, {"r0": 16.0, "r1": r2, "color": Color("#ff6a4a"), "vfx": _vx(e, id, d), "size": r2 * 2.4})
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
		"fan_blade":
			if e.cast_stage == 0:
				e.cast_stage = 1
				var nb := int(d["count"])
				for kb in nb:
					_shot(w, e.pos, e.cast_dir.angle() + (kb - (nb - 1) * 0.5) * float(d["spread"]), float(d["speed"]), float(d["dmg"]) * _mult(e), 12.0, str(d["kind"]), 3.0)
				Sfx.play("enemy_ranged")
		"poison_mist":
			if e.cast_stage == 0:
				e.cast_stage = 1
				var zd: Dictionary = d["zone"]
				w.add_hzone({"kind": "mist", "shape": "circle", "pos": e.cast_pos, "r": float(d["r"]), "life": float(zd["life"]), "dps": float(zd["dps"]) * _mult(e), "slow": float(zd["slow"]), "vfx": str(d.get("vfx", ""))})
		"cross_blade", "yitian_cross":
			if e.cast_stage == 0:
				e.cast_stage = 1
				var nr := int(d["n"])
				var base := e.cast_dir.angle() + float(d["offset"])
				var hit := false
				for kr in nr:
					var ang := base + TAU * float(kr) / float(nr)
					var tip := e.pos + Vector2.from_angle(ang) * float(d["len"])
					w.add_fx("ray", e.pos, 0.35, {"to": tip, "width": float(d["width"]), "color": Color("#bfe8ff") if id == "yitian_cross" else Color("#ff6a4a")})
					if _near_segment(w.player_pos, e.pos, tip, float(d["width"]) * 0.5 + GameWorld.PLAYER_RADIUS):
						hit = true
				if hit:
					_hurt(w, e, float(d["dmg"]))
				w.shake = maxf(w.shake, 7.0)
				Sfx.play("boss_cleave")
		"frost_slash":
			if e.cast_stage == 0:
				e.cast_stage = 1
				var tip2 := e.pos + e.cast_dir * float(d["len"])
				w.add_fx("ray", e.pos, 0.4, {"to": tip2, "width": float(d["width"]), "color": Color("#9ad8ff")})
				if _near_segment(w.player_pos, e.pos, tip2, float(d["width"]) * 0.5 + GameWorld.PLAYER_RADIUS):
					_hurt(w, e, float(d["dmg"]))
				var iz: Dictionary = d["zone"]
				w.add_hzone({"kind": "ice", "shape": "line", "pos": e.pos, "end": tip2, "r": float(d["width"]), "life": float(iz["life"]), "dps": float(iz["dps"]) * _mult(e), "slow": float(iz["slow"]), "vfx": "decal_ice_zone"})
				Sfx.play("boss_cleave")
		"palm_seal", "sword_rain":
			var i4 := int(u / float(d["gap"]))
			while e.cast_stage <= i4 and e.cast_stage < e.cast_list.size():
				var sp: Vector2 = e.cast_list[e.cast_stage]
				e.cast_stage += 1
				var sr := float(d["r"])
				w.add_fx("ring", sp, 0.4, {"r0": 10.0, "r1": sr, "color": Color("#ffd070") if id == "palm_seal" else Color("#bfe8ff"), "vfx": _vx(e, id, d), "size": sr * 2.4})
				if id == "sword_rain":
					w.add_hzone({"kind": "scar", "shape": "circle", "pos": sp, "r": sr, "life": 4.0, "dps": 0.0, "slow": 0.0, "vfx": "decal_scorch"})
				if _in_circle(w, sp, sr):
					_hurt(w, e, float(d["dmg"]))
				w.shake = maxf(w.shake, 4.0)
				Sfx.play("boss_cleave")
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
		var follow := str(d.get("follow", ""))
		if follow != "" and _d(follow).size() > 0:
			_start(w, e, follow, e.cast_dir)
		else:
			_end(e)
	return vel


## 杂兵行为：弓手（保持距离、预警后放冷箭）/ 蛮兵（预警后直线冲锋）
static func minion(w: GameWorld, e: Enemy, dt: float, dir: Vector2, d: float) -> Vector2:
	if e.cast_id != "":
		e.cast_t += dt
		var sd := _d(e.cast_id)
		var warn := float(sd["warn"])
		if e.cast_t < warn:
			return Vector2.ZERO            # 施法中：方向已在开始时锁定，不再跟随
		var u := e.cast_t - warn
		var vel := Vector2.ZERO
		if e.cast_id == "minion_stomp":
			if e.cast_stage == 0:
				e.cast_stage = 1
				w.add_fx("ring", e.pos, 0.35, {"r0": 8.0, "r1": float(sd["r"]), "color": Color("#ffb070"), "vfx": "fx_minion_stomp", "size": float(sd["r"]) * 2.4})
				if _in_circle(w, e.pos, float(sd["r"])):
					w._hurt(float(sd["dmg"]) * maxf(1.0, e.damage / 12.0) * e.atk_mul())
					_knock(w, e.pos, float(sd["knock"]))
				w.shake = maxf(w.shake, 3.0)
			if u > 0.25:
				_end(e, 2.0, 3.0)
		elif e.cast_id == "arrow":
			if e.cast_stage == 0:
				e.cast_stage = 1
				_shot(w, e.pos, e.cast_dir.angle(), float(sd["speed"]), float(sd["dmg"]) * maxf(1.0, e.damage / 6.0) * e.atk_mul(), 7.0, "emei" if e.art_key == "emei" else "arrow", 2.5, true)
			if u > 0.25:
				_end(e, 1.8, 2.8)
		else:
			if e.cast_stage == 0 and e.cast_id == "thrust":
				e.cast_stage = 1
				w.add_fx("ring", e.pos, 0.3, {"r0": 8.0, "r1": 60.0, "color": Color("#bfe8ff"), "vfx": "fx_minion_thrust", "size": 150.0, "angle": e.cast_dir.angle()})
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
	if e.behavior == "stomper":
		if e.skill_gap <= 0.0 and d < 120.0:
			_start(w, e, "minion_stomp", dir)
		return dir * e.speed
	if e.behavior == "thruster" or e.behavior == "charger":
		if e.skill_gap <= 0.0 and d < 380.0 and d > 60.0:
			_start(w, e, e.mskill if e.mskill != "" else "rush", dir)
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
		"rays":
			var nr := int(d["n"])
			var base := e.cast_dir.angle() + float(d["offset"])
			for kr in nr:
				var ang := base + TAU * float(kr) / float(nr)
				var tip := e.pos + Vector2.from_angle(ang) * float(d["len"])
				var wd2 := float(d["width"])
				var nrm := Vector2.from_angle(ang).orthogonal() * wd2 * 0.5
				var quad := PackedVector2Array([e.pos + nrm, tip + nrm, tip - nrm, e.pos - nrm])
				w.draw_colored_polygon(quad, fill)
				var tipp := e.pos + Vector2.from_angle(ang) * float(d["len"]) * p
				w.draw_colored_polygon(PackedVector2Array([e.pos + nrm, tipp + nrm, tipp - nrm, e.pos - nrm]), inner)
				w.draw_polyline(PackedVector2Array([e.pos + nrm, tip + nrm, tip - nrm, e.pos - nrm, e.pos + nrm]), edge, 2.0)
		"spots":
			var sr := float(d["r"])
			for sp in e.cast_list:
				w.draw_circle(sp, sr, fill)
				w.draw_circle(sp, sr * p, inner)
				w.draw_arc(sp, sr, 0.0, TAU, 28, edge, 3.0)
		"circle":
			var c := e.pos
			if e.cast_id == "leap" or e.cast_id == "blink" or e.cast_id == "backstab":
				c = e.cast_pos
			elif d.get("at", "") == "player":
				c = e.cast_pos
			var r := float(d["r"])
			w.draw_circle(c, r, fill)
			w.draw_circle(c, r * p, inner)
			w.draw_arc(c, r, 0.0, TAU, 40, edge, 3.0)
