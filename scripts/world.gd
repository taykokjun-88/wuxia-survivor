class_name GameWorld
extends Node2D
## 游戏世界：模拟 + 绘制。
## 所有实体（敌人/弹体/经验）都是轻量数据，由本节点统一更新并在一次 _draw 中绘制。
## step(dt) 与渲染无关，可在 headless 下做自动化测试。

signal player_died
signal victory

const PLAYER_RADIUS := 12.0
const DASH_TIME := 0.18
const DASH_SPEED := 1200.0
const SPAWN_DIST := 780.0
const RELOCATE_DIST := 1300.0
const MAX_ENEMIES := 700
const MAX_GEMS := 400
const MAX_EFFECTS := 160
const BOSS_TIME := 240.0
const BURST_INTERVAL := 40.0
const ULT_RADIUS := 300.0
const ULT_DAMAGE := 90.0
const CELL := 64.0
const NEILI_BONUS_THRESHOLD := 0.5
const NEILI_BONUS_MULT := 1.25

const INK := Color("#1d2a35")
const VERMILION := Color("#b33a2a")
const JADE := Color("#2a7f7a")
const GOLD := Color("#c9a227")

# ---- 输入（由 Main 或测试 bot 写入）----
var input_move := Vector2.ZERO
var input_dash := false
var input_ult := false
var god := false
var rng_seed := 0
var rng := RandomNumberGenerator.new()

# ---- 玩家状态 ----
var stats: Dictionary = {}
var owned: Dictionary = {}      # 武学/心法 id -> 等级
var skill_cd: Dictionary = {}
var hp_penalty := 1.0
var neili_bonus := 0.0
var player_pos := Vector2.ZERO
var facing := Vector2.RIGHT
var hp := 100.0
var neili := 100.0
var level := 1
var exp_now := 0
var exp_next := 12
var pending_levels := 0
var invuln := 0.0
var dash_t := 0.0
var dash_cd_t := 0.0
var dash_dir := Vector2.RIGHT
var shake := 0.0

# ---- 世界状态 ----
var time := 0.0
var kills := 0
var over := false
var won := false
var enemies: Array[Enemy] = []
var projs: Array[Projectile] = []
var gem_pos: Array[Vector2] = []
var gem_val: Array[int] = []
var effects: Array[Dictionary] = []
var orbit_blades: Array[Vector2] = []
var orbit_blade_r := 16.0
var orbit_angle := 0.0
var boss: Enemy = null
var grid: Dictionary = {}
var spawn_acc := 0.0
var next_burst := BURST_INTERVAL
var next_uid := 1


func _ready() -> void:
	if rng_seed != 0:
		rng.seed = rng_seed
	else:
		rng.randomize()
	start_run()


func start_run() -> void:
	owned = {"liyue_palm": 1}
	skill_cd = {"liyue_palm": 0.3}
	hp_penalty = 1.0
	neili_bonus = 0.0
	recalc()
	hp = stats["max_hp"]
	neili = stats["max_neili"]
	player_pos = Vector2.ZERO
	level = 1
	exp_now = 0
	exp_next = _exp_for(1)
	pending_levels = 0
	time = 0.0
	kills = 0
	over = false
	won = false
	enemies.clear()
	projs.clear()
	gem_pos.clear()
	gem_val.clear()
	effects.clear()
	boss = null
	next_burst = BURST_INTERVAL


# =====================================================================
# 属性
# =====================================================================

func recalc() -> void:
	stats = Data.player_base.duplicate()
	for id in owned:
		var def: Dictionary = Data.skills[id]
		if def.get("kind") == "passive":
			var l: int = owned[id]
			var per: Dictionary = def["per_level"]
			for k in per:
				stats[k] = float(stats.get(k, 0.0)) + float(per[k]) * l
	stats["max_hp"] = float(stats["max_hp"]) * hp_penalty
	stats["max_neili"] = float(stats["max_neili"]) + neili_bonus
	stats["dash_cost"] = maxf(8.0, float(stats["dash_cost"]))
	stats["dash_cd"] = maxf(0.25, float(stats["dash_cd"]))
	hp = minf(hp, stats["max_hp"])
	neili = minf(neili, stats["max_neili"])


func _exp_for(l: int) -> int:
	return int(4 + l * 4 + l * l * 0.5)


## 内力充盈（≥50%）时全部伤害 +25%
func dmg_mult() -> float:
	return NEILI_BONUS_MULT if neili >= float(stats["max_neili"]) * NEILI_BONUS_THRESHOLD else 1.0


# =====================================================================
# 主循环
# =====================================================================

func step(dt: float) -> void:
	if over:
		_update_effects(dt)
		queue_redraw()
		return
	time += dt
	shake = maxf(0.0, shake - 30.0 * dt)
	_update_player(dt)
	_spawn(dt)
	_rebuild_grid()
	_update_enemies(dt)
	_update_skills(dt)
	_update_projectiles(dt)
	_update_gems(dt)
	_compact_enemies()
	_update_effects(dt)
	queue_redraw()


func _update_player(dt: float) -> void:
	invuln = maxf(0.0, invuln - dt)
	dash_cd_t = maxf(0.0, dash_cd_t - dt)

	var move := input_move
	if move.length() > 1.0:
		move = move.normalized()
	if move.length() > 0.1:
		facing = move.normalized()

	# 轻功：短距离无敌冲刺，消耗内力
	if input_dash and dash_t <= 0.0 and dash_cd_t <= 0.0 and neili >= float(stats["dash_cost"]):
		dash_t = DASH_TIME
		dash_dir = move.normalized() if move.length() > 0.1 else facing
		neili -= float(stats["dash_cost"])
		dash_cd_t = float(stats["dash_cd"])
		invuln = maxf(invuln, DASH_TIME + 0.08)
	input_dash = false

	if dash_t > 0.0:
		dash_t -= dt
		player_pos += dash_dir * DASH_SPEED * dt
		_add_fx("trail", player_pos, 0.25)
	else:
		player_pos += move * float(stats["move_speed"]) * dt

	neili = minf(stats["max_neili"], neili + float(stats["neili_regen"]) * dt)
	hp = minf(stats["max_hp"], hp + float(stats["hp_regen"]) * dt)

	# 真气爆发：消耗满内力的范围大招
	var ult_cost := minf(float(stats["ult_cost"]), float(stats["max_neili"]))
	if input_ult and neili >= ult_cost:
		neili -= ult_cost
		_ult()
	input_ult = false


func _ult() -> void:
	var dmg := ULT_DAMAGE * dmg_mult()
	for e in _query(player_pos, ULT_RADIUS):
		if e.alive and e.pos.distance_to(player_pos) < ULT_RADIUS + e.radius:
			var out := (e.pos - player_pos).normalized()
			damage_enemy(e, dmg, out * 600.0)
	for p in projs:
		if p.hostile and p.pos.distance_to(player_pos) < ULT_RADIUS:
			p.life = 0.0
	_add_fx("ring", player_pos, 0.45, {"r0": 20.0, "r1": ULT_RADIUS, "color": JADE})
	shake = 10.0


# =====================================================================
# 敌人
# =====================================================================

func _spawn(dt: float) -> void:
	var rate := 1.3 + time * 0.04
	if time >= BOSS_TIME:
		rate *= 0.5
	spawn_acc += rate * dt
	while spawn_acc >= 1.0:
		spawn_acc -= 1.0
		if enemies.size() < MAX_ENEMIES:
			_spawn_enemy(_pick_type(), _ring_pos())
	# 合围：定时在四周刷出一圈敌人
	if time >= next_burst:
		next_burst += BURST_INTERVAL
		for i in 24:
			if enemies.size() < MAX_ENEMIES:
				var a := TAU * i / 24.0
				_spawn_enemy("bandit", player_pos + Vector2.from_angle(a) * SPAWN_DIST)
	if time >= BOSS_TIME and boss == null:
		_spawn_boss()


func _ring_pos() -> Vector2:
	return player_pos + Vector2.from_angle(rng.randf() * TAU) * (SPAWN_DIST + rng.randf() * 60.0)


func _pick_type() -> String:
	var w_blade := clampf((time - 30.0) / 120.0, 0.0, 0.8)
	var w_soldier := clampf((time - 70.0) / 150.0, 0.0, 0.6)
	var r := rng.randf() * (1.0 + w_blade + w_soldier)
	if r < 1.0:
		return "bandit"
	if r < 1.0 + w_blade:
		return "blade"
	return "soldier"


func _spawn_enemy(type: String, at: Vector2) -> Enemy:
	var def: Dictionary = Data.enemies[type]
	var e := Enemy.new()
	e.uid = next_uid
	next_uid += 1
	e.type_id = type
	e.pos = at
	var scale := 1.0 + time / 150.0
	e.max_hp = float(def["hp"]) * scale
	e.hp = e.max_hp
	e.speed = float(def["speed"]) * (1.0 + minf(time / 600.0, 0.3)) * rng.randf_range(0.9, 1.1)
	e.damage = float(def["damage"]) * (1.0 + time / 400.0)
	e.radius = float(def["radius"])
	e.exp_value = int(def["exp"])
	e.color = Color(str(def["color"]))
	enemies.append(e)
	return e


func _spawn_boss() -> void:
	boss = _spawn_enemy("boss", _ring_pos())
	boss.is_boss = true
	# Boss 不随时间缩放血量，保持固定的战斗时长
	boss.max_hp = float(Data.enemies["boss"]["hp"])
	boss.hp = boss.max_hp
	boss.damage = float(Data.enemies["boss"]["damage"])
	_add_fx("text", player_pos + Vector2(0, -80), 2.0, {"text": "海岛剑尊 现身！", "size": 28, "color": VERMILION})


func _rebuild_grid() -> void:
	grid.clear()
	for e in enemies:
		var k := _key(e.pos)
		if grid.has(k):
			var cell: Array[Enemy] = grid[k]
			cell.append(e)
		else:
			var cell: Array[Enemy] = [e]
			grid[k] = cell


func _key(p: Vector2) -> int:
	return int(floorf(p.x / CELL)) * 100003 + int(floorf(p.y / CELL))


func _query(center: Vector2, r: float) -> Array[Enemy]:
	var out: Array[Enemy] = []
	var rr := r + 44.0  # 留出最大敌人半径（Boss）的余量
	var x0 := int(floorf((center.x - rr) / CELL))
	var x1 := int(floorf((center.x + rr) / CELL))
	var y0 := int(floorf((center.y - rr) / CELL))
	var y1 := int(floorf((center.y + rr) / CELL))
	for cx in range(x0, x1 + 1):
		for cy in range(y0, y1 + 1):
			var k := cx * 100003 + cy
			if grid.has(k):
				out.append_array(grid[k])
	return out


func _nearest(max_dist: float) -> Enemy:
	var best: Enemy = null
	var bd := max_dist * max_dist
	for e in enemies:
		if not e.alive:
			continue
		var d2 := player_pos.distance_squared_to(e.pos)
		if d2 < bd:
			bd = d2
			best = e
	return best


func _update_enemies(dt: float) -> void:
	for e in enemies:
		if not e.alive:
			continue
		e.orbit_cd -= dt
		e.flash = maxf(0.0, e.flash - dt)
		var to := player_pos - e.pos
		var d := to.length()
		if d > RELOCATE_DIST and not e.is_boss:
			e.pos = _ring_pos()
			continue
		var dir := to / d if d > 0.001 else Vector2.ZERO
		var vel := dir * e.speed
		if e.is_boss:
			vel = _boss_ai(e, dt, dir)
		else:
			vel += _separation(e) * 90.0
		e.pos += (vel + e.knock) * dt
		e.knock *= maxf(0.0, 1.0 - 7.0 * dt)
		if d < e.radius + PLAYER_RADIUS and invuln <= 0.0:
			_hurt(e.damage)


## 简易分离：只看自己所在格的少量邻居，避免敌人叠成一团。
func _separation(e: Enemy) -> Vector2:
	var k := _key(e.pos)
	if not grid.has(k):
		return Vector2.ZERO
	var push := Vector2.ZERO
	var cnt := 0
	var cell: Array[Enemy] = grid[k]
	for o in cell:
		if o == e or not o.alive:
			continue
		var delta := e.pos - o.pos
		var min_d := e.radius + o.radius
		var d2 := delta.length_squared()
		if d2 < min_d * min_d:
			if d2 < 0.01:
				push += Vector2.from_angle(rng.randf() * TAU)
			else:
				push += delta / sqrt(d2)
		cnt += 1
		if cnt >= 8:
			break
	return push


func _boss_ai(e: Enemy, dt: float, dir: Vector2) -> Vector2:
	e.boss_timer += dt
	e.bolt_timer -= dt
	match e.boss_state:
		"chase":
			if e.bolt_timer <= 0.0:
				var rage := e.hp < e.max_hp * 0.5
				e.bolt_timer = 2.2 if rage else 3.0
				_boss_radial(e, 22 if rage else 14)
			if e.boss_timer >= 6.0:
				e.boss_state = "windup"
				e.boss_timer = 0.0
			return dir * e.speed
		"windup":
			e.charge_dir = dir
			if e.boss_timer >= 0.9:
				e.boss_state = "charge"
				e.boss_timer = 0.0
			return Vector2.ZERO
		"charge":
			if e.boss_timer >= 0.5:
				e.boss_state = "chase"
				e.boss_timer = 0.0
			return e.charge_dir * 520.0
	return Vector2.ZERO


func _boss_radial(e: Enemy, n: int) -> void:
	var offset := time * 0.7
	for i in n:
		var a := offset + TAU * i / n
		var p := Projectile.new()
		p.hostile = true
		p.kind = "bolt"
		p.pos = e.pos
		p.vel = Vector2.from_angle(a) * 240.0
		p.angle = a
		p.radius = 9.0
		p.damage = 14.0
		p.pierce = 1
		p.life = 4.0
		projs.append(p)


func _hurt(amount: float) -> void:
	if god:
		return
	var dmg := maxf(1.0, amount - float(stats["armor"]))
	hp -= dmg
	invuln = 0.6
	shake = 8.0
	_add_fx("text", player_pos + Vector2(0, -24), 0.7, {"text": "-%d" % int(dmg), "size": 22, "color": VERMILION})
	if hp <= 0.0 and not over:
		hp = 0.0
		over = true
		won = false
		player_died.emit()


func damage_enemy(e: Enemy, amount: float, knock_vec: Vector2) -> void:
	if not e.alive:
		return
	e.hp -= amount
	e.flash = 0.08
	if not e.is_boss:
		e.knock += knock_vec
	else:
		e.knock += knock_vec * 0.1
	if effects.size() < MAX_EFFECTS:
		_add_fx("text", e.pos + Vector2(rng.randf_range(-8, 8), -e.radius), 0.5,
			{"text": str(int(amount)), "size": 14, "color": INK})
	if e.hp <= 0.0:
		_kill(e)


func _kill(e: Enemy) -> void:
	e.alive = false
	kills += 1
	_drop_gem(e.pos, e.exp_value)
	_add_fx("splat", e.pos, 0.6, {"r": e.radius * 1.4, "color": e.color})
	if e.is_boss:
		over = true
		won = true
		shake = 14.0
		victory.emit()


func _compact_enemies() -> void:
	var j := 0
	for e in enemies:
		if e.alive:
			enemies[j] = e
			j += 1
	enemies.resize(j)


# =====================================================================
# 武学
# =====================================================================

func _update_skills(dt: float) -> void:
	orbit_blades.clear()
	for id in owned:
		var def: Dictionary = Data.skills[id]
		var l: int = owned[id]
		match str(def["type"]):
			"wave", "bolt":
				skill_cd[id] = float(skill_cd.get(id, 0.0)) - dt
				if skill_cd[id] <= 0.0:
					if _fire(def, l):
						skill_cd[id] = Data.lv(def, "cooldown", l)
					else:
						skill_cd[id] = 0.15
			"orbit":
				_update_orbit(def, l, dt)


func _fire(def: Dictionary, l: int) -> bool:
	# 瞄准距离 = 弹体实际射程，避免"打出去够不着"
	var reach := Data.lv(def, "speed", l) * Data.lv(def, "life", l)
	var target := _nearest(reach)
	if target == null:
		return false
	var base := (target.pos - player_pos).angle()
	var dmg := Data.lv(def, "damage", l) * dmg_mult()
	if str(def["type"]) == "wave":
		_spawn_proj("wave", base, def, l, dmg)
		if def.get("both_sides", false):
			_spawn_proj("wave", base + PI, def, l, dmg)
	else:
		var n := int(Data.lv(def, "count", l))
		var spread := Data.lv(def, "spread", l)
		for i in n:
			var a := base
			if str(def.get("pattern", "spread")) == "radial":
				a = base + TAU * i / n
			else:
				a = base + (i - (n - 1) * 0.5) * spread
			_spawn_proj("bolt", a, def, l, dmg)
	return true


func _spawn_proj(kind: String, angle: float, def: Dictionary, l: int, dmg: float) -> void:
	var p := Projectile.new()
	var dir := Vector2.from_angle(angle)
	p.kind = kind
	p.angle = angle
	p.pos = player_pos + dir * 18.0
	p.vel = dir * Data.lv(def, "speed", l)
	p.radius = Data.lv(def, "radius", l)
	p.damage = dmg
	p.pierce = int(Data.lv(def, "pierce", l))
	p.life = Data.lv(def, "life", l)
	p.knock = Data.lv(def, "knock", l)
	projs.append(p)


func _update_orbit(def: Dictionary, l: int, dt: float) -> void:
	orbit_angle += Data.lv(def, "speed", l) * dt
	var n := int(Data.lv(def, "count", l))
	var orbit_r := Data.lv(def, "orbit_radius", l)
	orbit_blade_r = Data.lv(def, "radius", l)
	var dmg := Data.lv(def, "damage", l) * dmg_mult()
	for i in n:
		var a := orbit_angle + TAU * i / n
		var bp := player_pos + Vector2.from_angle(a) * orbit_r
		orbit_blades.append(bp)
		for e in _query(bp, orbit_blade_r):
			if e.alive and e.orbit_cd <= 0.0 and bp.distance_to(e.pos) < orbit_blade_r + e.radius:
				e.orbit_cd = 0.4
				damage_enemy(e, dmg, (e.pos - player_pos).normalized() * 120.0)


func _update_projectiles(dt: float) -> void:
	var j := 0
	for p in projs:
		p.life -= dt
		p.pos += p.vel * dt
		var keep := p.life > 0.0
		if keep:
			if p.hostile:
				if invuln <= 0.0 and p.pos.distance_to(player_pos) < p.radius + PLAYER_RADIUS:
					_hurt(p.damage)
					keep = false
			else:
				for e in _query(p.pos, p.radius):
					if not e.alive or p.hit.has(e.uid):
						continue
					if p.pos.distance_to(e.pos) < p.radius + e.radius:
						p.hit[e.uid] = true
						damage_enemy(e, p.damage, p.vel.normalized() * p.knock)
						p.pierce -= 1
						if p.pierce <= 0:
							keep = false
							break
		if keep:
			projs[j] = p
			j += 1
	projs.resize(j)


# =====================================================================
# 经验 / 升级
# =====================================================================

func _drop_gem(at: Vector2, value: int) -> void:
	if gem_pos.size() >= MAX_GEMS:
		var i := rng.randi() % gem_pos.size()
		gem_val[i] += value
		return
	gem_pos.append(at)
	gem_val.append(value)


func _update_gems(dt: float) -> void:
	var pull := float(stats["pickup_range"])
	var i := 0
	while i < gem_pos.size():
		var d := gem_pos[i].distance_to(player_pos)
		if d < 14.0:
			_gain_exp(gem_val[i])
			var last := gem_pos.size() - 1
			gem_pos[i] = gem_pos[last]
			gem_val[i] = gem_val[last]
			gem_pos.pop_back()
			gem_val.pop_back()
			continue
		if d < pull:
			gem_pos[i] += (player_pos - gem_pos[i]).normalized() * 420.0 * dt
		i += 1


func _gain_exp(v: int) -> void:
	exp_now += v
	while exp_now >= exp_next:
		exp_now -= exp_next
		level += 1
		exp_next = _exp_for(level)
		pending_levels += 1


## 生成升级三选一：进化优先，其次随机的新武学/升级，小概率混入奇遇。
func roll_choices(n: int = 3) -> Array:
	var out: Array = []
	for evo in Data.evolutions:
		var from_id: String = evo["from"]
		var to_id: String = evo["to"]
		var from_def: Dictionary = Data.skills[from_id]
		if owned.has(from_id) and owned[from_id] >= int(from_def["max_level"]) and owned.has(evo["requires"]):
			var to_def: Dictionary = Data.skills[to_id]
			out.append({
				"kind": "evolve", "id": to_id, "from": from_id, "tag": "进化",
				"title": "%s → %s" % [from_def["name"], to_def["name"]], "desc": to_def["desc"],
			})

	var pool: Array = []
	for id in Data.skills:
		var def: Dictionary = Data.skills[id]
		if def.get("evolved", false):
			continue
		var tag := "心法" if def["kind"] == "passive" else "招式"
		if owned.has(id):
			if owned[id] < int(def["max_level"]):
				var nl: int = owned[id] + 1
				pool.append({
					"kind": "upgrade", "id": id, "tag": tag,
					"title": "%s Lv%d→%d" % [def["name"], owned[id], nl], "desc": Data.upgrade_text(id, nl),
				})
		else:
			pool.append({
				"kind": "new", "id": id, "tag": tag,
				"title": "领悟：%s" % def["name"], "desc": def["desc"],
			})
	_shuffle(pool)

	if rng.randf() < 0.2:
		var adv := _roll_adventure()
		if not adv.is_empty():
			pool.append(adv)  # 末尾，优先被取出
	while out.size() < n and not pool.is_empty():
		out.append(pool.pop_back())
	if out.is_empty():
		out.append({"kind": "heal", "id": "", "tag": "调息", "title": "运功疗伤", "desc": "回复 30% 气血"})
	return out


func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var t: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = t


func _roll_adventure() -> Dictionary:
	var ids: Array = Data.adventures.keys()
	var id: String = ids[rng.randi() % ids.size()]
	if id == "cliff" and _cliff_candidates().is_empty():
		id = "master"
	var def: Dictionary = Data.adventures[id]
	return {"kind": "adventure", "id": id, "tag": "奇遇", "title": def["name"], "desc": def["desc"]}


func _cliff_candidates() -> Array:
	var c: Array = []
	for id in owned:
		var def: Dictionary = Data.skills[id]
		if not def.get("evolved", false) and owned[id] < int(def["max_level"]):
			c.append(id)
	return c


func apply_choice(c: Dictionary) -> void:
	var old_max := float(stats["max_hp"])
	var id: String = c["id"]
	match str(c["kind"]):
		"new":
			owned[id] = 1
			skill_cd[id] = 0.2
		"upgrade":
			owned[id] = int(owned[id]) + 1
		"evolve":
			var from_id: String = c["from"]
			owned.erase(from_id)
			skill_cd.erase(from_id)
			owned[id] = 1
			skill_cd[id] = 0.2
			_add_fx("ring", player_pos, 0.8, {"r0": 10.0, "r1": 220.0, "color": GOLD})
		"adventure":
			_apply_adventure(id)
		"heal":
			hp = minf(float(stats["max_hp"]), hp + float(stats["max_hp"]) * 0.3)
	recalc()
	hp += maxf(0.0, float(stats["max_hp"]) - old_max)
	pending_levels = maxi(0, pending_levels - 1)


func _apply_adventure(id: String) -> void:
	match id:
		"cliff":
			var c := _cliff_candidates()
			if not c.is_empty():
				var pick: String = c[rng.randi() % c.size()]
				owned[pick] = int(owned[pick]) + 1
				hp_penalty *= 0.85
		"master":
			neili_bonus += 30.0
			recalc()
			neili = float(stats["max_neili"])


# =====================================================================
# 特效 & 绘制
# =====================================================================

func _add_fx(kind: String, at: Vector2, life: float, extra: Dictionary = {}) -> void:
	var fx := {"kind": kind, "pos": at, "t": 0.0, "life": life}
	fx.merge(extra)
	effects.append(fx)


func _update_effects(dt: float) -> void:
	var j := 0
	for fx in effects:
		fx["t"] = float(fx["t"]) + dt
		if fx["t"] < fx["life"]:
			if fx["kind"] == "text":
				fx["pos"] = Vector2(fx["pos"]) + Vector2(0, -40) * dt
			effects[j] = fx
			j += 1
	effects.resize(j)


func _vis(p: Vector2, margin: float = 40.0) -> bool:
	return absf(p.x - player_pos.x) < 640.0 + margin and absf(p.y - player_pos.y) < 360.0 + margin


func _draw() -> void:
	_draw_background()
	for i in gem_pos.size():
		var g := gem_pos[i]
		if _vis(g):
			draw_colored_polygon(PackedVector2Array([
				g + Vector2(0, -6), g + Vector2(5, 0), g + Vector2(0, 6), g + Vector2(-5, 0)]), GOLD)
	for e in enemies:
		if _vis(e.pos, 60.0):
			_draw_enemy(e)
	for p in projs:
		if _vis(p.pos):
			_draw_proj(p)
	for bp in orbit_blades:
		draw_circle(bp, orbit_blade_r, Color(INK, 0.25))
		draw_arc(bp, orbit_blade_r, 0.0, TAU, 14, INK, 3.0)
		draw_line(bp - facing * 0.0 - Vector2(0, orbit_blade_r), bp + Vector2(0, orbit_blade_r), Color("#e8e8e8"), 2.0)
	_draw_player()
	_draw_effects()


func _hash(cx: int, cy: int) -> int:
	return absi((cx * 73856093) ^ (cy * 19349663))


func _draw_background() -> void:
	# 水墨风占位：淡墨山石 + 草丛笔触，按格子哈希稳定生成
	var cs := 180
	var x0 := int(floorf((player_pos.x - 720.0) / cs))
	var x1 := int(floorf((player_pos.x + 720.0) / cs))
	var y0 := int(floorf((player_pos.y - 440.0) / cs))
	var y1 := int(floorf((player_pos.y + 440.0) / cs))
	for cx in range(x0, x1 + 1):
		for cy in range(y0, y1 + 1):
			var h := _hash(cx, cy)
			var c := Vector2(cx * cs + (h % 140), cy * cs + ((h / 7) % 140))
			match h % 5:
				0:
					var r := 22.0 + (h % 38)
					for k in 3:
						draw_circle(c + Vector2(k * 7, -k * 5), r * (1.0 - 0.28 * k), Color(0.15, 0.17, 0.2, 0.05))
				1:
					for k in 3:
						var b := c + Vector2(k * 5, 0)
						draw_line(b, b + Vector2(-4 + k * 3, -13), Color(0.12, 0.3, 0.2, 0.28), 2.0)


func _draw_enemy(e: Enemy) -> void:
	var c := Color.WHITE if e.flash > 0.0 else e.color
	var r := e.radius
	draw_circle(e.pos + Vector2(0, r * 0.8), r * 0.8, Color(0, 0, 0, 0.10))
	if e.is_boss and e.boss_state == "windup":
		# 冲锋预警线
		var end := e.pos + e.charge_dir * 260.0
		draw_line(e.pos, end, Color(VERMILION, 0.3), r * 1.6)
	draw_circle(e.pos, r, c)
	draw_arc(e.pos, r, 0.0, TAU, 22, Color(0.04, 0.04, 0.05, 0.9), 2.0)
	match e.type_id:
		"bandit":
			draw_line(e.pos + Vector2(-r * 0.85, -r * 0.35), e.pos + Vector2(r * 0.85, -r * 0.35), VERMILION, 3.0)
		"blade":
			draw_line(e.pos + Vector2(r * 0.6, -r * 0.1), e.pos + Vector2(r * 1.7, -r * 1.2), Color("#d8d8d8"), 3.0)
		"soldier":
			draw_colored_polygon(PackedVector2Array([
				e.pos + Vector2(-r * 0.8, -r * 0.3), e.pos + Vector2(0, -r * 1.3), e.pos + Vector2(r * 0.8, -r * 0.3)]),
				Color("#9aa7b4"))
		"boss":
			draw_arc(e.pos, r + 8.0, 0.0, TAU, 32, Color(VERMILION, 0.6), 3.0)
			draw_line(e.pos + Vector2(r * 0.4, 0), e.pos + Vector2(r * 1.9, -r * 0.9), Color("#e8e8e8"), 5.0)


func _draw_proj(p: Projectile) -> void:
	var dir := Vector2.from_angle(p.angle)
	if p.hostile:
		draw_circle(p.pos, p.radius, Color(VERMILION, 0.85))
		draw_arc(p.pos, p.radius, 0.0, TAU, 12, Color(0.1, 0.0, 0.0, 0.8), 2.0)
	elif p.kind == "wave":
		# 墨色新月形掌风，带三层拖尾
		for k in 3:
			var off := p.pos - dir * (k * 14.0)
			draw_arc(off, p.radius, p.angle - 1.0, p.angle + 1.0, 18, Color(INK, 0.55 - k * 0.17), 6.0 - k * 1.5)
	else:
		draw_line(p.pos - dir * 18.0, p.pos, Color(INK, 0.5), 3.0)
		draw_circle(p.pos, p.radius * 0.6, INK)


func _draw_player() -> void:
	var blink := invuln > 0.0 and dash_t <= 0.0 and int(time * 24.0) % 2 == 0
	if blink:
		return
	draw_circle(player_pos + Vector2(0, 9), 10.0, Color(0, 0, 0, 0.12))
	if neili >= float(stats["max_neili"]) * NEILI_BONUS_THRESHOLD:
		draw_arc(player_pos, 19.0, 0.0, TAU, 28, Color(JADE, 0.45), 2.0)
	draw_circle(player_pos, PLAYER_RADIUS, JADE)
	draw_arc(player_pos, PLAYER_RADIUS, 0.0, TAU, 20, Color(0.03, 0.08, 0.08), 2.0)
	draw_circle(player_pos + Vector2(0, -9), 6.0, Color("#1c1c1c"))
	draw_line(player_pos, player_pos + facing * 28.0, Color("#eeeeee"), 3.0)


func _draw_effects() -> void:
	var font := ThemeDB.fallback_font
	for fx in effects:
		var t: float = fx["t"]
		var life: float = fx["life"]
		var a := 1.0 - t / life
		var at: Vector2 = fx["pos"]
		match str(fx["kind"]):
			"text":
				var col: Color = fx["color"]
				draw_string(font, at - Vector2(40, 0), str(fx["text"]), HORIZONTAL_ALIGNMENT_CENTER, 80.0,
					int(fx["size"]), Color(col, a))
			"ring":
				var r := lerpf(float(fx["r0"]), float(fx["r1"]), t / life)
				var col2: Color = fx["color"]
				draw_arc(at, r, 0.0, TAU, 48, Color(col2, a * 0.8), 5.0)
			"splat":
				var col3: Color = fx["color"]
				draw_circle(at, float(fx["r"]) * (1.0 + t), Color(col3, a * 0.35))
			"trail":
				draw_circle(at, PLAYER_RADIUS * a, Color(JADE, a * 0.4))
