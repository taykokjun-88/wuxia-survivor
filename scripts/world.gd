class_name GameWorld
extends Node2D
## 游戏世界：模拟 + 绘制。
## 所有实体（敌人/弹体/经验）都是轻量数据，由本节点统一更新并在一次 _draw 中绘制。
## step(dt) 与渲染无关，可在 headless 下做自动化测试。
##
## 技能（scripts/skills/）通过本类提供的服务造成影响：
##   spawn_proj / area_hit / cone_hit / add_zone / stun_enemy / add_shield ...

signal player_died
signal victory

const PLAYER_RADIUS := 12.0
const SPAWN_DIST := 780.0
const RELOCATE_DIST := 1300.0
const MAX_GEMS := 400
const GEM_AUTO_PULL := 4.0
const MAX_EFFECTS := 160
const CELL := 64.0
const MAX_SKILLS := 4
const MAX_XINFA := 2
const NEILI_BONUS_THRESHOLD := 0.5
const NEILI_BONUS_MULT := 1.25
const ULT_RADIUS := 300.0
const ULT_DAMAGE := 90.0

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

# ---- 装备 ----
var starter_id := "chain_fist"
var school_id := "fist"           # 创建角色时选定，决定可学的招式池
var qinggong_id := "tashue"
var qg: Dictionary = {}
var skills: Dictionary = {}       # id -> SkillBase（最多 4 个）
var xinfa: Dictionary = {}        # id -> 等级（最多 2 个）
var enhance_id := ""              # 本局唯一的专属强化所属技能
var enhance_level := 0            # 强化等级 1~3：首个小 Boss 选择强化，之后每个小 Boss 升一级
var deferred_upgrades := 0
var talent_stats: Dictionary = {} # 天赋加成（局外成长，M5 接入）

# ---- 玩家状态 ----
var stats: Dictionary = {}
var tag_bonus: Dictionary = {}    # 标签 -> 心法提供的伤害加成
var player_pos := Vector2.ZERO
var facing := Vector2.RIGHT
var hp := 100.0
var neili := 100.0
var shield := 0.0
var level := 1
var exp_now := 0
var exp_next := 12
var pending_levels := 0
var pending_chests := 0
var invuln := 0.0
var since_hit := 99.0
var dash_t := 0.0
var dash_dir := Vector2.RIGHT
var dash_charges := 1
var dash_recharge := 0.0
var dash_hit := {}
var stealth_t := 0.0
var stealth_pos := Vector2.ZERO
var buff_t := 0.0
var shake := 0.0

# ---- 世界状态 ----
var time := 0.0
var kills := 0
var exp_total := 0          # 统计：本局累计获得的修为
var over := false
var won := false
var enemies: Array[Enemy] = []
var projs: Array[Projectile] = []
var zones: Array[Dictionary] = []
var gem_pos: Array[Vector2] = []
var gem_val: Array[int] = []
var gem_age: Array[float] = []     # 宝石落地后的时间：超过 GEM_AUTO_PULL 秒会自动飞向玩家
var chests: Array[Vector2] = []
var effects: Array[Dictionary] = []
var bosses: Array[Enemy] = []
var skill_dmg: Dictionary = {}    # 统计：技能 id -> 累计伤害
var boss_log: Array[String] = []   # 统计：Boss 击杀耗时
var grid: Dictionary = {}
var spawn_acc := 0.0
var next_burst := 45.0
var next_elite := 100.0
var mini_idx := 0
var boss_spawned := false
var next_uid := 1
var chain_depth := 0
var dash_count := 0
var sprite_anim: SpriteAnim = null   # 角色动画（没有素材时为 null，回退占位图形）
var anim_clock := 0.0
var anim_ovr := ""                   # 出招/大招等一次性动画
var anim_ovr_t := 0.0
var anim_ovr_len := 0.0
var death_t := 0.0
var max_enemies := 800


func _ready() -> void:
	sprite_anim = SpriteAnim.new()
	if not sprite_anim.load_dir("res://assets/sprites/player"):
		sprite_anim = null
	if rng_seed != 0:
		rng.seed = rng_seed
	else:
		rng.randomize()
	start_run()


func start_run(p_starter: String = "chain_fist", p_qinggong: String = "tashue") -> void:
	starter_id = p_starter
	qinggong_id = p_qinggong
	qg = Data.qinggong[qinggong_id]
	skills.clear()
	xinfa.clear()
	enhance_id = ""
	enhance_level = 0
	deferred_upgrades = 0
	level = 1
	school_id = str(Data.skills[starter_id]["school"])
	add_skill(starter_id)
	stats = {}
	recalc()
	hp = float(stats["max_hp"])
	neili = float(stats["max_neili"])
	shield = 0.0
	player_pos = Vector2.ZERO
	exp_now = 0
	exp_next = _exp_for(1)
	pending_levels = 0
	pending_chests = 0
	invuln = 0.0
	since_hit = 99.0
	dash_t = 0.0
	dash_charges = int(qg.get("charges", 1))
	dash_recharge = 0.0
	stealth_t = 0.0
	buff_t = 0.0
	time = 0.0
	kills = 0
	exp_total = 0
	over = false
	won = false
	enemies.clear()
	projs.clear()
	zones.clear()
	gem_pos.clear()
	gem_val.clear()
	gem_age.clear()
	chests.clear()
	effects.clear()
	bosses.clear()
	skill_dmg.clear()
	boss_log.clear()
	anim_clock = 0.0
	anim_ovr_t = 0.0
	death_t = 0.0
	dash_count = 0
	spawn_acc = 0.0
	next_burst = Data.T("burst_interval")
	next_elite = Data.T("elite_first")
	mini_idx = 0
	boss_spawned = false
	max_enemies = int(Data.T("max_enemies"))


# =====================================================================
# 装备 / 属性
# =====================================================================

func add_skill(id: String) -> void:
	var s := FistSkills.create(id)
	s.setup(self, id, Data.skills[id])
	skills[id] = s


func st(key: String) -> float:
	return float(stats.get(key, 0.0))


func recalc() -> void:
	stats = Data.player_base.duplicate()
	for id in xinfa:
		var def: Dictionary = Data.xinfa[id]
		var l: int = xinfa[id]
		var per: Dictionary = def["per_level"]
		for k in per:
			stats[k] = st(k) + float(per[k]) * l
	# 角色等级成长：每升 1 级，基础伤害 / 气血 / 防御小幅提升（见 data 的 level_growth）
	for k in Data.level_growth:
		stats[k] = st(k) + float(Data.level_growth[k]) * (level - 1)
	var qs: Dictionary = qg.get("stats", {})
	for k in qs:
		stats[k] = st(k) + float(qs[k])
	for k in talent_stats:
		stats[k] = st(k) + float(talent_stats[k])
	# 标签加成：心法每升 1 级，加成 ×(1 + 0.5 × (等级-1))
	tag_bonus.clear()
	for id in xinfa:
		var def2: Dictionary = Data.xinfa[id]
		var scale := 1.0 + 0.5 * (int(xinfa[id]) - 1)
		var b: Dictionary = def2["bonus"]
		for tg in b:
			tag_bonus[tg] = float(tag_bonus.get(tg, 0.0)) + float(b[tg]) * scale
	hp = minf(hp, st("max_hp"))
	neili = minf(neili, st("max_neili"))


func _exp_for(l: int) -> int:
	return int(Data.T("exp_mult") * (6 + 4.0 * l + 0.5 * l * l))


func cd_mult() -> float:
	return maxf(0.4, 1.0 - st("cd_reduce"))


## 内力充盈（≥50%）时全部伤害 +25%
func dmg_mult() -> float:
	return NEILI_BONUS_MULT if neili >= st("max_neili") * NEILI_BONUS_THRESHOLD else 1.0


# =====================================================================
# 主循环
# =====================================================================

func step(dt: float) -> void:
	anim_clock += dt
	anim_ovr_t = maxf(0.0, anim_ovr_t - dt)
	if over and not won:
		death_t += dt
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
	for s: SkillBase in skills.values():
		s.tick(dt)
	_update_projectiles(dt)
	_update_zones(dt)
	_update_gems(dt)
	_update_chests()
	_compact_enemies()
	_update_effects(dt)
	queue_redraw()


func _update_player(dt: float) -> void:
	invuln = maxf(0.0, invuln - dt)
	since_hit += dt
	stealth_t = maxf(0.0, stealth_t - dt)
	buff_t = maxf(0.0, buff_t - dt)

	# 轻功次数恢复
	var max_charges := int(qg.get("charges", 1))
	if dash_charges < max_charges:
		dash_recharge -= dt
		if dash_recharge <= 0.0:
			dash_charges += 1
			dash_recharge = float(qg["cd"]) * maxf(0.4, 1.0 - st("qg_cd_reduce"))

	var move := input_move
	if move.length() > 1.0:
		move = move.normalized()
	if move.length() > 0.1:
		facing = move.normalized()

	if input_dash and dash_t <= 0.0 and dash_charges > 0 and neili >= float(qg["cost"]):
		_start_dash(move, max_charges)
	input_dash = false

	if dash_t > 0.0:
		dash_t -= dt
		player_pos += dash_dir * float(qg["dash_speed"]) * dt
		add_fx("trail", player_pos, 0.25)
		var pd := float(qg.get("path_dmg", 0.0))
		if pd > 0.0:
			for e in _query(player_pos, 36.0):
				if e.alive and not dash_hit.has(e.uid) and e.pos.distance_to(player_pos) < 36.0 + e.radius:
					dash_hit[e.uid] = true
					hit_enemy(e, pd, [], dash_dir * float(qg["path_knock"]), "qinggong")
		if dash_t <= 0.0:
			_end_dash()
	else:
		var spd_pct := st("speed_pct") + (float(qg.get("buff_speed", 0.0)) if buff_t > 0.0 else 0.0)
		player_pos += move * st("move_speed") * (1.0 + spd_pct) * dt

	# 内力 / 气血 / 护盾
	var max_n := st("max_neili")
	var regen := st("neili_regen") * (1.0 + (float(qg.get("buff_regen", 0.0)) if buff_t > 0.0 else 0.0))
	neili = minf(max_n, neili + regen * dt)
	var hr := st("hp_regen") + (st("full_hp_regen") if neili >= max_n - 0.01 else 0.0)
	hp = minf(st("max_hp"), hp + hr * dt)
	if since_hit > 2.0 and shield < st("shield_max"):
		shield = minf(st("shield_max"), shield + st("shield_regen") * dt)

	# 真气爆发：消耗满内力的范围大招
	var ult_cost := minf(st("ult_cost"), max_n)
	if input_ult and neili >= ult_cost:
		neili -= ult_cost
		_ult()
	input_ult = false


func _start_dash(move: Vector2, max_charges: int) -> void:
	dash_count += 1
	neili -= float(qg["cost"])
	dash_charges -= 1
	if dash_charges == max_charges - 1:
		dash_recharge = float(qg["cd"]) * maxf(0.4, 1.0 - st("qg_cd_reduce"))
	var dir := move.normalized() if move.length() > 0.1 else facing
	dash_hit.clear()
	if qg.get("blink", false):
		var from := player_pos
		player_pos += dir * float(qg["blink_dist"])
		for i in 6:
			add_fx("trail", from.lerp(player_pos, i / 5.0), 0.3)
		invuln = maxf(invuln, 0.25)
		var ld := float(qg.get("land_dmg", 0.0))
		if ld > 0.0:
			var lr := float(qg["land_radius"])
			area_hit_raw(player_pos, lr, ld, [], "qinggong", 250.0)
			add_fx("ring", player_pos, 0.3, {"r0": 10.0, "r1": lr, "color": JADE})
		_end_dash()
	else:
		dash_t = float(qg["dash_time"])
		dash_dir = dir
		invuln = maxf(invuln, dash_t + 0.08)


func _end_dash() -> void:
	if qg.has("stealth"):
		stealth_t = float(qg["stealth"])
		stealth_pos = player_pos
	if qg.has("buff_time"):
		buff_t = float(qg["buff_time"])


func _ult() -> void:
	play_anim("ult", 0.5)
	area_hit_raw(player_pos, ULT_RADIUS, ULT_DAMAGE, [], "ult", 600.0)
	for p in projs:
		if p.hostile and p.pos.distance_to(player_pos) < ULT_RADIUS:
			p.life = 0.0
	add_fx("ring", player_pos, 0.45, {"r0": 20.0, "r1": ULT_RADIUS, "color": JADE})
	shake = 10.0


func add_shield(v: float) -> void:
	shield = minf(maxf(st("shield_max"), 30.0), shield + v)


# =====================================================================
# 刷怪
# =====================================================================

func _spawn(dt: float) -> void:
	var rate := Data.T("spawn_base") + time * Data.T("spawn_slope")
	if _boss_alive():
		rate *= 0.5
	spawn_acc += rate * dt
	while spawn_acc >= 1.0:
		spawn_acc -= 1.0
		if enemies.size() < max_enemies:
			_spawn_enemy(_pick_type(), _ring_pos())
	# 合围：定时在四周刷出一圈敌人
	if time >= next_burst:
		next_burst += Data.T("burst_interval")
		for i in 24:
			if enemies.size() < max_enemies:
				_spawn_enemy("bandit", player_pos + Vector2.from_angle(TAU * i / 24.0) * SPAWN_DIST)
	if time >= next_elite:
		next_elite += Data.T("elite_interval")
		_spawn_elite()
	var mini_times: Array = Data.tuning["mini_boss_times"]
	if mini_idx < mini_times.size() and time >= float(mini_times[mini_idx]):
		mini_idx += 1
		_spawn_boss("mini_boss_%d" % mini_idx, false)
	if not boss_spawned and time >= Data.T("boss_time"):
		boss_spawned = true
		_spawn_boss("boss", true)


func _boss_alive() -> bool:
	for b in bosses:
		if b.alive:
			return true
	return false


func _ring_pos() -> Vector2:
	return player_pos + Vector2.from_angle(rng.randf() * TAU) * (SPAWN_DIST + rng.randf() * 60.0)


func _pick_type() -> String:
	var w_blade := clampf((time - 30.0) / 180.0, 0.0, 0.8)
	var w_soldier := clampf((time - 90.0) / 240.0, 0.0, 0.7)
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
	e.born = time
	e.type_id = type
	e.pos = at
	e.max_hp = float(def["hp"]) * (1.0 + time / Data.T("hp_scale_t"))
	e.hp = e.max_hp
	e.speed = float(def["speed"]) * (1.0 + minf(time / 900.0, 0.3)) * rng.randf_range(0.9, 1.1)
	e.damage = float(def["damage"]) * (1.0 + time / Data.T("dmg_scale_t"))
	e.radius = float(def["radius"])
	e.exp_value = int(def["exp"])
	e.color = Color(str(def["color"]))
	enemies.append(e)
	return e


func _spawn_elite() -> void:
	var e := _spawn_enemy("soldier" if rng.randf() < 0.6 else "blade", _ring_pos())
	e.is_elite = true
	e.max_hp *= Data.T("elite_hp")
	e.hp = e.max_hp
	e.radius *= Data.T("elite_radius")
	e.speed *= Data.T("elite_speed")
	e.damage *= Data.T("elite_dmg")
	e.exp_value = int(Data.T("elite_exp"))
	add_fx("text", player_pos + Vector2(0, -80), 1.6, {"text": "精英现身！", "size": 26, "color": GOLD})


func _spawn_boss(id: String, final: bool) -> void:
	var def: Dictionary = Data.enemies[id]
	var e := _spawn_enemy(id, _ring_pos())
	e.is_boss = true
	e.is_final = final
	e.boss_name = str(def["name"])
	e.max_hp = float(def["hp"])   # Boss 不随时间缩放血量，保持固定的战斗时长
	e.hp = e.max_hp
	e.speed = float(def["speed"])
	e.damage = float(def["damage"])
	e.boss_bolts = int(def["bolts"])
	bosses.append(e)
	add_fx("text", player_pos + Vector2(0, -80), 2.0, {"text": "%s 现身！" % e.boss_name, "size": 28, "color": VERMILION})


# =====================================================================
# 空间查询
# =====================================================================

func _rebuild_grid() -> void:
	grid.clear()
	for e in enemies:
		var k := _key(e.pos)
		if grid.has(k):
			var cell: Array[Enemy] = grid[k]
			cell.append(e)
		else:
			var cell2: Array[Enemy] = [e]
			grid[k] = cell2


func _key(p: Vector2) -> int:
	return int(floorf(p.x / CELL)) * 100003 + int(floorf(p.y / CELL))


func _query(center: Vector2, r: float) -> Array[Enemy]:
	var out: Array[Enemy] = []
	var rr := r + 66.0  # 留出最大敌人半径（Boss/精英）的余量
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


## 自动瞄准：Boss / 精英在射程内时优先（有效距离 ×0.35），否则打最近的
func _target_weight(e: Enemy) -> float:
	if e.is_boss:
		return 0.12
	if e.is_elite:
		return 0.4
	return 1.0


func nearest_enemy(max_dist: float) -> Enemy:
	var best: Enemy = null
	var lim := max_dist * max_dist
	var bd := INF
	for e in enemies:
		if not e.alive:
			continue
		var d2 := player_pos.distance_squared_to(e.pos)
		if d2 >= lim:
			continue
		var score := d2 * _target_weight(e)
		if score < bd:
			bd = score
			best = e
	return best


## 最近的 n 个敌人（按距离升序）
func nearest_n(max_dist: float, n: int) -> Array[Enemy]:
	var best: Array[Enemy] = []
	var dists: Array[float] = []
	var lim := max_dist * max_dist
	for e in enemies:
		if not e.alive:
			continue
		var d2 := player_pos.distance_squared_to(e.pos)
		if d2 >= lim:
			continue
		d2 *= _target_weight(e)
		if best.size() < n or d2 < dists[best.size() - 1]:
			var i := best.size()
			while i > 0 and dists[i - 1] > d2:
				i -= 1
			best.insert(i, e)
			dists.insert(i, d2)
			if best.size() > n:
				best.pop_back()
				dists.pop_back()
	return best


func any_enemy_within(center: Vector2, r: float) -> bool:
	for e in _query(center, r):
		if e.alive and e.pos.distance_to(center) < r + e.radius:
			return true
	return false


# =====================================================================
# 敌人
# =====================================================================

func _update_enemies(dt: float) -> void:
	for e in enemies:
		if not e.alive:
			continue
		e.flash = maxf(0.0, e.flash - dt)
		e.slow_t = maxf(0.0, e.slow_t - dt)
		var to := player_pos - e.pos
		var d := to.length()
		if d > RELOCATE_DIST and not e.is_boss:
			e.pos = _ring_pos()
			continue
		var dir := to / d if d > 0.001 else Vector2.ZERO
		var vel := Vector2.ZERO
		if e.stun > 0.0:
			e.stun -= dt
		elif e.is_boss:
			vel = _boss_ai(e, dt, dir)
		else:
			var spd := e.speed * (e.slow_mult if e.slow_t > 0.0 else 1.0)
			if stealth_t > 0.0:
				# 轻功隐匿：敌人只会慢慢走向玩家消失的位置
				var tp := stealth_pos - e.pos
				vel = tp.normalized() * spd * 0.35 if tp.length() > 8.0 else Vector2.ZERO
			else:
				vel = dir * spd
			vel += _separation(e) * 90.0
		e.pos += (vel + e.knock) * dt
		e.knock *= maxf(0.0, 1.0 - 7.0 * dt)
		if e.stun <= 0.0 and d < e.radius + PLAYER_RADIUS and invuln <= 0.0:
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
				_boss_radial(e, int(e.boss_bolts * (1.5 if rage else 1.0)))
			if e.boss_timer >= 6.0:
				e.boss_state = "windup"
				e.boss_timer = 0.0
			return dir * e.speed * (e.slow_mult if e.slow_t > 0.0 else 1.0)
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
	# 闪避（灵蛇步）与免伤（铁骨诀）
	if st("dodge_chance") > 0.0 and neili >= float(qg.get("dodge_cost", 0.0)) and rng.randf() < st("dodge_chance"):
		neili -= float(qg.get("dodge_cost", 0.0))
		invuln = 0.3
		add_fx("text", player_pos + Vector2(0, -24), 0.6, {"text": "闪", "size": 24, "color": JADE})
		return
	if rng.randf() < st("block_chance"):
		invuln = 0.3
		add_fx("text", player_pos + Vector2(0, -24), 0.6, {"text": "挡", "size": 24, "color": JADE})
		return
	var dmg := amount
	for s: SkillBase in skills.values():
		dmg = s.on_hurt(dmg)
	dmg = maxf(maxf(1.0, dmg * 0.25), dmg - st("armor"))
	since_hit = 0.0
	invuln = 0.6
	if st("thorns") > 0.0:
		area_hit_raw(player_pos, 90.0, st("thorns"), [], "thorns", 150.0)
	if shield > 0.0:
		var absorbed := minf(shield, dmg)
		shield -= absorbed
		dmg -= absorbed
	if dmg <= 0.0:
		return
	hp -= dmg
	shake = 8.0
	add_fx("text", player_pos + Vector2(0, -24), 0.7, {"text": "-%d" % int(dmg), "size": 22, "color": VERMILION})
	if hp <= 0.0 and not over:
		hp = 0.0
		over = true
		won = false
		player_died.emit()


func damage_enemy(e: Enemy, amount: float, knock_vec: Vector2, crit: bool = false) -> void:
	if not e.alive:
		return
	e.hp -= amount
	e.flash = 0.08
	e.knock += knock_vec * (0.1 if e.is_boss else (0.4 if e.is_elite else 1.0))
	if effects.size() < MAX_EFFECTS:
		var big := crit
		add_fx("text", e.pos + Vector2(rng.randf_range(-8, 8), -e.radius), 0.55 if big else 0.45,
			{"text": str(int(amount)), "size": 20 if big else 14, "color": GOLD if big else INK})
	if e.hp <= 0.0:
		_kill(e)


func _kill(e: Enemy) -> void:
	e.alive = false
	kills += 1
	neili = minf(st("max_neili"), neili + st("kill_neili"))
	_drop_gem(e.pos, e.exp_value)
	add_fx("splat", e.pos, 0.6, {"r": e.radius * 1.4, "color": e.color})
	if e.chain:
		_chain_explode(e)
	if e.is_elite:
		hp = minf(st("max_hp"), hp + st("max_hp") * 0.15)
		add_fx("text", e.pos + Vector2(0, -30), 1.0, {"text": "精英已破：气血回复", "size": 18, "color": GOLD})
	if e.is_boss:
		boss_log.append("%s %.0fs" % [e.boss_name, time - e.born])
	if e.is_boss and not e.is_final:
		chests.append(e.pos)
	if e.is_final:
		over = true
		won = true
		shake = 14.0
		victory.emit()


func _chain_explode(e: Enemy) -> void:
	var s: SkillBase = skills.get("point_finger")
	if s == null or chain_depth >= 6:
		return
	chain_depth += 1
	var lv := clampi(enhance_level, 1, 3) - 1
	var er: float = [85.0, 110.0, 140.0][lv]
	area_hit(s, e.pos, er, s.p("damage") * [1.2, 1.6, 2.0][lv], 100.0, [0.8, 1.0, 1.2][lv], true)
	add_fx("ring", e.pos, 0.3, {"r0": 10.0, "r1": er, "color": GOLD})
	chain_depth -= 1


func _compact_enemies() -> void:
	var j := 0
	for e in enemies:
		if e.alive:
			enemies[j] = e
			j += 1
	enemies.resize(j)


func stun_enemy(e: Enemy, t: float, chain: bool = false) -> void:
	var f := 0.2 if e.is_boss else (0.4 if e.is_elite else 1.0)
	e.stun = maxf(e.stun, t * f)
	if chain:
		e.chain = true


func slow_enemy(e: Enemy, mult: float, t: float) -> void:
	e.slow_mult = mult
	e.slow_t = maxf(e.slow_t, t)


# =====================================================================
# 技能服务
# =====================================================================

## 统一结算一次命中：标签加成 × 内力加成 × 暴击。返回最终伤害。
func hit_enemy(e: Enemy, base: float, tags: Array, knock_vec: Vector2, sid: String, force_crit: bool = false) -> float:
	var m := 1.0
	for tg in tags:
		m += float(tag_bonus.get(tg, 0.0))
	m *= dmg_mult() * (1.0 + st("damage_pct"))
	var sk: SkillBase = skills.get(sid)
	var crit_p := st("crit_chance") + (float(sk.mods["crit"]) if sk != null else 0.0)
	var crit := force_crit or rng.randf() < crit_p
	if crit:
		m *= st("crit_mult")
	var amount := base * m
	var hs := st("hit_slow")
	if sk != null and float(sk.mods["debuff"]) > 0.0:
		hs = maxf(hs, float(sk.mods["debuff"]))
	if hs > 0.0:
		slow_enemy(e, 1.0 - minf(0.6, hs), 1.5)
	if sk != null and float(sk.mods["heal"]) > 0.0:
		hp = minf(st("max_hp"), hp + minf(3.0, amount * float(sk.mods["heal"])))
	skill_dmg[sid] = float(skill_dmg.get(sid, 0.0)) + amount
	damage_enemy(e, amount, knock_vec, crit)
	return amount


func area_hit_raw(center: Vector2, radius: float, base: float, tags: Array, sid: String,
		knock: float = 0.0, stun: float = 0.0, chain: bool = false, force_crit: bool = false) -> void:
	for e in _query(center, radius):
		if not e.alive:
			continue
		var d := e.pos.distance_to(center)
		if d < radius + e.radius:
			var out := (e.pos - center) / d if d > 0.01 else Vector2.from_angle(rng.randf() * TAU)
			hit_enemy(e, base, tags, out * knock, sid, force_crit)
			if stun > 0.0:
				stun_enemy(e, stun, chain)


func area_hit(s: SkillBase, center: Vector2, radius: float, base: float,
		knock: float = 0.0, stun: float = 0.0, chain: bool = false) -> void:
	area_hit_raw(center, radius, base, s.tags(), s.id, knock, stun, chain)


## 扇形近战判定
func cone_hit(s: SkillBase, origin: Vector2, angle: float, half_arc: float, reach: float,
		base: float, knock: float, force_crit: bool = false) -> void:
	for e in _query(origin, reach):
		if not e.alive:
			continue
		var to := e.pos - origin
		var d := to.length()
		if d >= reach + e.radius:
			continue
		if d > 20.0 and absf(wrapf(to.angle() - angle, -PI, PI)) > half_arc + 0.15:
			continue
		var out := to / d if d > 0.01 else Vector2.from_angle(angle)
		hit_enemy(e, base, s.tags(), out * knock, s.id, force_crit)


func spawn_proj(s: SkillBase, angle: float, o: Dictionary = {}) -> Projectile:
	var pr := Projectile.new()
	var dir := Vector2.from_angle(angle)
	pr.kind = str(s.def.get("proj_kind", "bolt"))
	pr.skill_id = s.id
	pr.tags = s.tags()
	pr.angle = angle
	pr.pos = o.get("pos", player_pos + dir * 18.0)
	pr.speed = float(o.get("speed", s.p("speed")))
	pr.vel = dir * pr.speed
	pr.radius = float(o.get("radius", s.p("radius")))
	pr.damage = float(o.get("damage", s.p("damage")))
	pr.pierce = int(o.get("pierce", s.p("pierce")))
	pr.life = float(o.get("life", s.p("life")))
	pr.knock = float(o.get("knock", s.p("knock")))
	pr.homing = bool(o.get("homing", false))
	pr.turn = float(o.get("turn", 0.0))
	pr.split = int(o.get("split", 0))
	pr.boomerang = bool(o.get("boomerang", false))
	pr.stun = float(o.get("stun", 0.0))
	pr.chain = bool(o.get("chain", false))
	projs.append(pr)
	return pr


func add_zone(z: Dictionary) -> void:
	if not z.has("pos"):
		z["pos"] = player_pos
	zones.append(z)


func fx_slash(at: Vector2, angle: float, reach: float, arc: float, heavy: bool) -> void:
	add_fx("slash", at, 0.2, {"angle": angle, "r": reach, "arc": arc, "heavy": heavy})


# =====================================================================
# 弹体 / 区域
# =====================================================================

func _nearest_from(pos: Vector2, max_dist: float, exclude: Dictionary) -> Enemy:
	var best: Enemy = null
	var bd := max_dist * max_dist
	for e in enemies:
		if not e.alive or exclude.has(e.uid):
			continue
		var d2 := pos.distance_squared_to(e.pos)
		if d2 < bd:
			bd = d2
			best = e
	return best


func _update_projectiles(dt: float) -> void:
	var j := 0
	for p in projs:
		p.life -= dt
		if p.life <= 0.0 and p.boomerang and not p.returning:
			p.returning = true
			p.homing = false
			p.life = 3.0
			p.hit.clear()
			p.pierce = maxi(p.pierce, 2 + enhance_level)
			p.damage *= 1.6 + 0.3 * (enhance_level - 1)
		if p.returning:
			var back := player_pos - p.pos
			if back.length() < 22.0:
				p.life = 0.0
			else:
				p.vel = back.normalized() * p.speed * 1.3
				p.angle = p.vel.angle()
		elif p.homing:
			if p.target == null or not p.target.alive or p.hit.has(p.target.uid):
				p.target = _nearest_from(p.pos, 420.0, p.hit)
			if p.target != null:
				var diff := wrapf((p.target.pos - p.pos).angle() - p.vel.angle(), -PI, PI)
				var rot := clampf(diff, -p.turn * dt, p.turn * dt)
				p.vel = p.vel.rotated(rot)
				p.angle = p.vel.angle()
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
						hit_enemy(e, p.damage, p.tags, p.vel.normalized() * p.knock, p.skill_id)
						if p.stun > 0.0:
							stun_enemy(e, p.stun, p.chain)
						if p.split > 0:
							_split(p)
							p.split = 0
						p.pierce -= 1
						if p.pierce <= 0:
							if p.boomerang and not p.returning:
								p.life = 0.0   # 回旋：穿透耗尽时不消失，转为折返
							else:
								keep = false
							break
		if keep:
			projs[j] = p
			j += 1
	projs.resize(j)


func _split(p: Projectile) -> void:
	var s: SkillBase = skills.get(p.skill_id)
	if s == null:
		return
	var n := p.split
	for i in n:
		var child := spawn_proj(s, p.angle + (i - (n - 1) * 0.5) * 0.5, {
			"pos": p.pos, "damage": p.damage * (0.7 + 0.1 * enhance_level), "radius": p.radius * 0.7,
			"pierce": 3, "life": 0.65, "speed": p.speed * 0.9, "knock": p.knock * 0.5})
		child.hit = p.hit.duplicate()


func _update_zones(dt: float) -> void:
	var j := 0
	for z in zones:
		var keep := true
		z["t"] = float(z["t"]) + dt
		var zpos: Vector2 = z["pos"]
		var zr: float = z["r"]
		match str(z["kind"]):
			"impact":
				if z["t"] >= z["delay"]:
					var s: SkillBase = z["skill"]
					area_hit(s, zpos, zr, z["dmg"], 250.0, z["stun"])
					add_fx("ring", zpos, 0.3, {"r0": 10.0, "r1": zr, "color": VERMILION})
					shake = maxf(shake, 5.0)
					if z["crack"]:
						var cl: int = z["elv"]
						add_zone({"kind": "crack", "skill": s, "pos": zpos, "r": zr * (0.8 + 0.15 * (cl - 1)),
							"t": 0.0, "life": 3.0 + (cl - 1), "tick": 0.0, "dmg": float(z["dmg"]) * (0.5 + 0.2 * (cl - 1))})
					keep = false
			"crack":
				if z["t"] >= z["life"]:
					keep = false
				else:
					z["tick"] = float(z["tick"]) - dt
					if z["tick"] <= 0.0:
						z["tick"] = 0.5
						var s2: SkillBase = z["skill"]
						area_hit(s2, zpos, zr, z["dmg"])
						for e in _query(zpos, zr):
							if e.alive and e.pos.distance_to(zpos) < zr + e.radius:
								slow_enemy(e, 0.6, 0.7)
			"vortex":
				z["pos"] = player_pos
				zpos = player_pos
				if z["t"] >= z["life"]:
					keep = false
					# 旋涡收束：把聚拢的敌人再轰一次
					if z.has("skill"):
						area_hit(z["skill"], zpos, zr * 0.6, z["dmg"], 200.0)
						add_fx("ring", zpos, 0.3, {"r0": 10.0, "r1": zr * 0.6, "color": INK})
				else:
					for e in _query(zpos, zr):
						if not e.alive or e.is_boss:
							continue
						var to := zpos - e.pos
						var d := to.length()
						if d > 24.0 and d < zr:
							e.pos += to / d * float(z["pull"]) * dt
		if keep:
			zones[j] = z
			j += 1
	zones.resize(j)


# =====================================================================
# 经验 / 秘籍 / 升级
# =====================================================================

func _drop_gem(at: Vector2, value: int) -> void:
	if gem_pos.size() >= MAX_GEMS:
		var i := rng.randi() % gem_pos.size()
		gem_val[i] += value
		return
	gem_pos.append(at)
	gem_val.append(value)
	gem_age.append(0.0)


func _update_gems(dt: float) -> void:
	var pull := st("pickup_range")
	var i := 0
	while i < gem_pos.size():
		var d := gem_pos[i].distance_to(player_pos)
		if d < 14.0:
			_gain_exp(gem_val[i])
			hp = minf(st("max_hp"), hp + st("pickup_heal"))
			var last := gem_pos.size() - 1
			gem_pos[i] = gem_pos[last]
			gem_val[i] = gem_val[last]
			gem_age[i] = gem_age[last]
			gem_pos.pop_back()
			gem_val.pop_back()
			gem_age.pop_back()
			continue
		gem_age[i] += dt
		if d < pull:
			gem_pos[i] += (player_pos - gem_pos[i]).normalized() * 420.0 * dt
		elif gem_age[i] > GEM_AUTO_PULL:
			# 落地一段时间后自动飞向玩家：升级节奏只取决于击杀，不取决于敢不敢冲进怪堆里捡
			gem_pos[i] += (player_pos - gem_pos[i]).normalized() * 320.0 * dt
		i += 1


func _gain_exp(v: int) -> void:
	var gain := int(ceil(v * (1.0 + st("exp_pct"))))
	exp_now += gain
	exp_total += gain
	var leveled := false
	while exp_now >= exp_next:
		exp_now -= exp_next
		level += 1
		exp_next = _exp_for(level)
		pending_levels += 1
		leveled = true
	if leveled:
		var old_max := st("max_hp")
		recalc()
		hp += maxf(0.0, st("max_hp") - old_max)


## 小 Boss 掉落「秘籍」：首次拾取三选一专属强化；之后每次拾取把该强化升一级（最高 3 级），满级后改为回复奖励。
func _update_chests() -> void:
	var i := 0
	while i < chests.size():
		if chests[i].distance_to(player_pos) < 30.0:
			var at := chests[i]
			chests.remove_at(i)
			if enhance_id == "":
				if pending_chests == 0:
					pending_chests += 1
				else:
					deferred_upgrades += 1   # 还没来得及选强化又拾到第二本：选完后直接升级
			elif enhance_level < 3:
				enhance_level += 1
				_enhance_upgraded(at)
			else:
				hp = minf(st("max_hp"), hp + st("max_hp") * 0.3)
				exp_now += int(exp_next * 0.4)
				add_fx("text", at + Vector2(0, -30), 1.2, {"text": "强化已圆满：气血回复、修为精进", "size": 20, "color": GOLD})
			continue
		i += 1


func _enhance_upgraded(at: Vector2) -> void:
	var def: Dictionary = Data.skills[enhance_id]
	var en: Dictionary = def["enhance"]
	add_fx("ring", player_pos, 0.8, {"r0": 10.0, "r1": 240.0, "color": GOLD})
	add_fx("text", at + Vector2(0, -40), 2.0, {
		"text": "「%s」升华至 Lv%d" % [en["name"], enhance_level], "size": 26, "color": GOLD})
	shake = maxf(shake, 6.0)


func roll_chest_choices() -> Array:
	var ids: Array = skills.keys()
	_shuffle(ids)
	var out: Array = []
	for id in ids:
		if out.size() >= 3:
			break
		var def: Dictionary = Data.skills[id]
		var en: Dictionary = def["enhance"]
		out.append({
			"kind": "enhance", "id": id, "tag": "秘籍", "src": "chest",
			"title": "%s · %s" % [def["name"], en["name"]], "desc": en["desc"],
		})
	return out


## 升级三选一：已有技能/心法的升级，以及槽位未满时的新技能/新心法。
func roll_choices(n: int = 3) -> Array:
	var pool: Array = []
	# 已有技能：每个技能给 2 张升级卡（不同方向，档位随机）
	for id in skills:
		var s: SkillBase = skills[id]
		if s.upgrades.size() >= Data.max_upgrades:
			continue
		var dirs := s.available_dirs()
		_shuffle(dirs)
		for i in mini(2, dirs.size()):
			var tier := Data.roll_tier(rng, st("luck"))
			pool.append({
				"kind": "up_skill", "id": id, "dir": dirs[i], "tier": tier, "src": "level",
				"tag": str(Data.tiers[tier]["name"]), "color": str(Data.tiers[tier]["color"]),
				"title": "%s · %s" % [s.def["name"], Data.directions[dirs[i]]["name"]],
				"desc": "%s　（已升级 %d/%d）" % [s.upgrade_text(dirs[i], tier), s.upgrades.size(), Data.max_upgrades],
			})
	for id in Data.skills:
		var def: Dictionary = Data.skills[id]
		if skills.has(id) or str(def["school"]) != school_id:
			continue
		if skills.size() < MAX_SKILLS:
			pool.append({
				"kind": "new_skill", "id": id, "tag": "招式", "src": "level",
				"title": "领悟：%s" % def["name"],
				"desc": "%s　【%s】" % [def["desc"], Data.tags_text(id)],
			})
	for id in Data.xinfa:
		var def2: Dictionary = Data.xinfa[id]
		if xinfa.has(id):
			if xinfa[id] < int(def2["max_level"]):
				pool.append({
					"kind": "up_xinfa", "id": id, "tag": "心法", "src": "level",
					"title": "%s Lv%d→%d" % [def2["name"], xinfa[id], xinfa[id] + 1],
					"desc": "标签加成与被动效果提升",
				})
		elif xinfa.size() < MAX_XINFA:
			pool.append({
				"kind": "new_xinfa", "id": id, "tag": "心法", "src": "level",
				"title": "修习：%s" % def2["name"], "desc": def2["desc"],
			})
	_shuffle(pool)
	var out: Array = []
	while out.size() < n and not pool.is_empty():
		out.append(pool.pop_back())
	if out.is_empty():
		out.append({"kind": "heal", "id": "", "tag": "调息", "src": "level", "title": "运功疗伤", "desc": "回复 40% 气血"})
		out.append({"kind": "elixir", "id": "", "tag": "调息", "src": "level", "title": "凝神静气", "desc": "获得相当于当前升级所需 60% 的修为"})
	return out


func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var t: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = t


func apply_choice(c: Dictionary) -> void:
	var old_max := st("max_hp")
	var id: String = c["id"]
	match str(c["kind"]):
		"new_skill":
			add_skill(id)
		"up_skill":
			var s: SkillBase = skills[id]
			s.add_upgrade(str(c["dir"]), int(c["tier"]))
		"new_xinfa":
			xinfa[id] = 1
		"up_xinfa":
			xinfa[id] = int(xinfa[id]) + 1
		"enhance":
			enhance_id = id
			enhance_level = mini(3, 1 + deferred_upgrades)
			deferred_upgrades = 0
			add_fx("ring", player_pos, 0.8, {"r0": 10.0, "r1": 220.0, "color": GOLD})
		"heal":
			hp = minf(st("max_hp"), hp + st("max_hp") * 0.4)
		"elixir":
			exp_now += int(exp_next * 0.6)
	recalc()
	hp += maxf(0.0, st("max_hp") - old_max)
	if str(c["src"]) == "chest":
		pending_chests = maxi(0, pending_chests - 1)
	else:
		pending_levels = maxi(0, pending_levels - 1)
	# 额外的修为可能再触发升级
	if exp_now >= exp_next:
		_gain_exp(0)


# =====================================================================
# 特效 & 绘制
# =====================================================================

func add_fx(kind: String, at: Vector2, life: float, extra: Dictionary = {}) -> void:
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
	_draw_zones()
	for i in gem_pos.size():
		var g := gem_pos[i]
		if _vis(g):
			draw_colored_polygon(PackedVector2Array([
				g + Vector2(0, -6), g + Vector2(5, 0), g + Vector2(0, 6), g + Vector2(-5, 0)]), GOLD)
	for c in chests:
		if _vis(c):
			var bob := sin(time * 4.0) * 3.0
			draw_rect(Rect2(c + Vector2(-11, -8 + bob), Vector2(22, 16)), Color("#8a5a1f"))
			draw_rect(Rect2(c + Vector2(-11, -8 + bob), Vector2(22, 16)), GOLD, false, 2.0)
			draw_arc(c + Vector2(0, bob), 20.0, 0.0, TAU, 20, Color(GOLD, 0.4 + 0.3 * sin(time * 5.0)), 2.0)
	for e in enemies:
		if _vis(e.pos, 60.0):
			_draw_enemy(e)
	for p in projs:
		if _vis(p.pos):
			_draw_proj(p)
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


func _draw_zones() -> void:
	for z in zones:
		var zpos: Vector2 = z["pos"]
		var zr: float = z["r"]
		match str(z["kind"]):
			"impact":
				var f := clampf(float(z["t"]) / float(z["delay"]), 0.0, 1.0)
				draw_circle(zpos, zr, Color(VERMILION, 0.10))
				draw_circle(zpos, zr * f, Color(VERMILION, 0.18))
				draw_arc(zpos, zr, 0.0, TAU, 32, Color(VERMILION, 0.6), 2.0)
			"crack":
				var a := 1.0 - float(z["t"]) / float(z["life"])
				draw_circle(zpos, zr, Color(0.1, 0.08, 0.06, 0.12 * a + 0.04))
				for k in 7:
					var ang := TAU * k / 7.0 + 0.4
					var mid := zpos + Vector2.from_angle(ang) * zr * 0.5 + Vector2.from_angle(ang + 1.2) * 8.0
					draw_line(zpos, mid, Color(0.1, 0.06, 0.04, 0.7 * a), 2.0)
					draw_line(mid, zpos + Vector2.from_angle(ang) * zr * 0.95, Color(0.1, 0.06, 0.04, 0.7 * a), 2.0)
			"vortex":
				var a2 := 1.0 - float(z["t"]) / float(z["life"])
				for k in 3:
					var rot := float(z["t"]) * 6.0 + k * 2.1
					draw_arc(zpos, zr * (0.35 + 0.2 * k), rot, rot + 2.0, 16, Color(INK, 0.4 * a2), 3.0)


func _draw_enemy(e: Enemy) -> void:
	var c := Color.WHITE if e.flash > 0.0 else e.color
	var r := e.radius
	draw_circle(e.pos + Vector2(0, r * 0.8), r * 0.8, Color(0, 0, 0, 0.10))
	if e.is_boss and e.boss_state == "windup":
		draw_line(e.pos, e.pos + e.charge_dir * 260.0, Color(VERMILION, 0.3), r * 1.6)
	draw_circle(e.pos, r, c)
	draw_arc(e.pos, r, 0.0, TAU, 22, Color(0.04, 0.04, 0.05, 0.9), 2.0)
	if e.is_boss:
		draw_arc(e.pos, r + 8.0, 0.0, TAU, 32, Color(VERMILION, 0.6), 3.0)
		draw_line(e.pos + Vector2(r * 0.4, 0), e.pos + Vector2(r * 1.9, -r * 0.9), Color("#e8e8e8"), 5.0)
	else:
		match e.type_id:
			"bandit":
				draw_line(e.pos + Vector2(-r * 0.85, -r * 0.35), e.pos + Vector2(r * 0.85, -r * 0.35), VERMILION, 3.0)
			"blade":
				draw_line(e.pos + Vector2(r * 0.6, -r * 0.1), e.pos + Vector2(r * 1.7, -r * 1.2), Color("#d8d8d8"), 3.0)
			"soldier":
				draw_colored_polygon(PackedVector2Array([
					e.pos + Vector2(-r * 0.8, -r * 0.3), e.pos + Vector2(0, -r * 1.3), e.pos + Vector2(r * 0.8, -r * 0.3)]),
					Color("#9aa7b4"))
	if e.is_elite:
		draw_arc(e.pos, r + 5.0, 0.0, TAU, 26, GOLD, 3.0)
	if e.stun > 0.0:
		var ang := time * 8.0
		for k in 3:
			var sp := e.pos + Vector2(0, -r - 8.0) + Vector2.from_angle(ang + k * 2.09) * 9.0
			draw_circle(sp, 2.5, GOLD)
	if e.slow_t > 0.0:
		draw_arc(e.pos, r + 2.0, 0.0, TAU, 20, Color("#5aa7d8", 0.8), 2.0)


func _draw_proj(p: Projectile) -> void:
	var dir := Vector2.from_angle(p.angle)
	if p.hostile:
		draw_circle(p.pos, p.radius, Color(VERMILION, 0.85))
		draw_arc(p.pos, p.radius, 0.0, TAU, 12, Color(0.1, 0.0, 0.0, 0.8), 2.0)
		return
	match p.kind:
		"wave":
			for k in 3:
				var off := p.pos - dir * (k * 14.0)
				draw_arc(off, p.radius, p.angle - 1.0, p.angle + 1.0, 18, Color(INK, 0.55 - k * 0.17), 6.0 - k * 1.5)
		"finger":
			draw_line(p.pos - dir * 26.0, p.pos, Color(GOLD, 0.6), 3.0)
			draw_circle(p.pos, p.radius * 0.7, GOLD)
		"palm":
			draw_circle(p.pos, p.radius, Color(JADE, 0.35))
			draw_arc(p.pos, p.radius, 0.0, TAU, 14, JADE, 2.5)
			draw_line(p.pos - dir * 16.0, p.pos, Color(JADE, 0.4), 4.0)
		_:
			draw_line(p.pos - dir * 18.0, p.pos, Color(INK, 0.5), 3.0)
			draw_circle(p.pos, p.radius * 0.6, INK)


## 本局成绩摘要（提交排行榜用；字段与 backend/Code.gs 的 submit 对应）
func run_summary() -> Dictionary:
	var bosses_killed := 0
	for b in bosses:
		if not b.alive:
			bosses_killed += 1
	var build: Array = []
	for s: SkillBase in skills.values():
		build.append({"id": s.id, "lv": s.level})
	return {
		"won": won, "seconds": int(time), "level": level, "kills": kills, "bosses": bosses_killed,
		"school": school_id, "starter": starter_id, "qinggong": qinggong_id,
		"enhance": "%s:%d" % [enhance_id, enhance_level] if enhance_id != "" else "",
		"build": build, "version": str(ProjectSettings.get_setting("application/config/version", "0")),
	}


## 播放一次性动画（出招、大招）。受击、倒下、冲刺由状态自动决定。
func play_anim(name: String, dur: float) -> void:
	anim_ovr = name
	anim_ovr_len = dur
	anim_ovr_t = dur


## 当前应播放的角色动画：[名称, 该动画内的时间]
func _player_anim_state() -> Array:
	if over and not won:
		return ["death", death_t]
	if anim_ovr_t > 0.0:
		return [anim_ovr, anim_ovr_len - anim_ovr_t]
	if since_hit < 0.25:
		return ["hurt", since_hit]
	if dash_t > 0.0:
		return ["dash", float(qg["dash_time"]) - dash_t]
	if input_move.length() > 0.1:
		return ["walk", anim_clock]
	return ["idle", anim_clock]


func _draw_player() -> void:
	var blink := invuln > 0.0 and dash_t <= 0.0 and int(time * 24.0) % 2 == 0
	if blink:
		return
	var alpha := 0.45 if stealth_t > 0.0 else 1.0
	var has_sprite := sprite_anim != null
	if has_sprite:
		# 脚下的扁椭圆影子（角色脚底在 player_pos 下方 14px）
		draw_set_transform(player_pos + Vector2(0, 13), 0.0, Vector2(1.0, 0.35))
		draw_circle(Vector2.ZERO, 15.0, Color(0, 0, 0, 0.18))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		draw_circle(player_pos + Vector2(0, 9), 10.0, Color(0, 0, 0, 0.12))
	if neili >= st("max_neili") * NEILI_BONUS_THRESHOLD:
		draw_arc(player_pos, 19.0, 0.0, TAU, 28, Color(JADE, 0.45 * alpha), 2.0)
	if shield > 0.0:
		draw_arc(player_pos, 24.0, 0.0, TAU, 28, Color("#7fc8e8", 0.8), 3.0)
	if has_sprite:
		var state := _player_anim_state()
		var tint := Color(1.0, 0.55, 0.55, alpha) if since_hit < 0.08 else Color(1.0, 1.0, 1.0, alpha)
		if sprite_anim.draw(self, str(state[0]), float(state[1]), player_pos + Vector2(0, 14), facing.x < 0.0, tint):
			return
	draw_circle(player_pos, PLAYER_RADIUS, Color(JADE, alpha))
	draw_arc(player_pos, PLAYER_RADIUS, 0.0, TAU, 20, Color(0.03, 0.08, 0.08, alpha), 2.0)
	draw_circle(player_pos + Vector2(0, -9), 6.0, Color(0.11, 0.11, 0.11, alpha))
	# 双拳
	var perp := facing.orthogonal()
	draw_circle(player_pos + facing * 16.0 + perp * 7.0, 4.5, Color("#e8c9a0", alpha))
	draw_circle(player_pos + facing * 16.0 - perp * 7.0, 4.5, Color("#e8c9a0", alpha))


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
				draw_string(font, at - Vector2(60, 0), str(fx["text"]), HORIZONTAL_ALIGNMENT_CENTER, 120.0,
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
			"slash":
				var ang: float = fx["angle"]
				var arc: float = fx["arc"]
				var rr: float = fx["r"]
				var wdt := (16.0 if fx["heavy"] else 10.0) * a + 2.0
				draw_arc(at, rr * 0.7, ang - arc * 0.5, ang + arc * 0.5, 16, Color(INK, a * 0.7), wdt)
				draw_arc(at, rr * 0.9, ang - arc * 0.4, ang + arc * 0.4, 16, Color(1, 1, 1, a * 0.6), wdt * 0.4)
