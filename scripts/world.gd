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
const VACUUM_SPEED := 1100.0       # 吸星大法：道具飞向主角的速度
const MAX_EFFECTS := 160
const CELL := 64.0
const MAX_SKILLS := 4
const MAX_XINFA := 2
# 气海三境：盈（真气外放，伤害加成、可催动招式）/ 平 / 虚（回气加快）。数值见 data 的 tuning。
enum Realm { XU, PING, YING }

const INK := Color("#1d2a35")
const VERMILION := Color("#b33a2a")
const JADE := Color("#2a7f7a")
const GOLD := Color("#c9a227")

# ---- 输入（由 Main 或测试 bot 写入）----
var input_move := Vector2.ZERO
var input_dash := false
var input_ult := false
var burst_used := 0                # 本局已用的真气爆发次数
var atk_buff_t := 0.0              # 阴性爆发：攻速提升的剩余时间
var absorb_items: Array = []         # 「吸星大法」道具：[{pos, age}]（同时最多一个）
var vacuum_t := 0.0                 # 吸星大法生效的剩余时间：期间所有宝石 / 还丹飞向主角
var absorb_gap := 0.0               # 距离上次掉落吸星大法的时间
var pills: Array = []              # 掉落的还丹：[{pos, kind: small|large, age}]
var god := false
var rng_seed := 0
var rng := RandomNumberGenerator.new()

# ---- 装备 ----
var starter_id := "chain_fist"
var reward_comp := 1.0              # 综合难度（1.0 ~ 3.0），决定经验 / 修为 / 装备奖励
var difficulty := {"count": 1.0, "hp": 1.0, "speed": 1.0}   # 开局前选择的难度倍率（1.0 ~ 3.0）
var map_id := "black_wind"       # 当前地图（见 data 的 maps）
var shi: Dictionary = {}            # 独孤九剑：已领悟的「式」→ 层数（最多 4 种）
var dugu_combo_log: Array = []     # 统计：真·独孤九剑的连击段数（测试用）
var school_id := "fist"           # 创建角色时选定，决定可学的招式池
var qinggong_id := "tashue"
var qg: Dictionary = {}
var skills: Dictionary = {}       # id -> SkillBase（最多 4 个）
var xinfa: Dictionary = {}        # id -> 等级（最多 2 个）
var enhance_id := ""              # 本局唯一的专属强化所属技能
var enhance_level := 0            # 强化等级 1~3：首个小 Boss 选择强化，之后每个小 Boss 升一级
var deferred_upgrades := 0
var talent_stats: Dictionary = {} # 局外加成合计（属性点 + 天赋 + 装备基础属性），开局前由 main 设置
var talent_skill_mods: Dictionary = {} # 天赋对具体招式的强化：招式 → {项: 值}（targets 为个数）
var gear_skill_mods: Dictionary = {}   # 装备词条：技能 → {方向: 百分数}
var gear_xinfa: Dictionary = {}        # 装备词条：心法 → 额外等级（只对已学会的心法生效）

# ---- 玩家状态 ----
var stats: Dictionary = {}
var tag_bonus: Dictionary = {}    # 标签 -> 心法提供的伤害加成
var player_pos := Vector2.ZERO
var facing := Vector2.RIGHT
var hp := 100.0
var neili := 100.0
var still_t := 0.0                # 连续站立不动的时间（入定）
var realm_time := [0.0, 0.0, 0.0] # 虚 / 平 / 盈 各停留了多久（测试与平衡用）
var empower_count := 0
var _emp_ctx := -1                # 延迟命中（弹体 / 区域）的催动状态：-1 未设置，0 否，1 是
var enemy_art: EnemyArt            # 怪物立绘；没有素材的怪物画占位图形
var map_art: MapArt                 # 当前地图的像素美术（地面 + 物件）；没有素材时为 null
var vfx: Vfx                       # 招式特效素材（没有素材的特效继续用程序绘制）
var vfx_layer: VfxLayer
var synergies: Array = []          # 当前生效的阴阳组合 / 合璧：[{name, desc, harmony}]
var burn_t := 0.0
var break_count := 0              # 打破 Boss 罡气的次数（测试用）
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
var gem_age: Array[float] = []     # 宝石落地后的时间（目前只用于统计）
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
	enemy_art = EnemyArt.new()
	enemy_art.load_dir("res://assets/enemies")
	map_art = MapArt.new()
	if not map_art.load_dir("res://assets/maps/black_wind", {"tree": 2.0, "rock": 2.0, "banner": 0.8, "barrel": 1.0, "campfire": 0.4, "bones": 1.2, "spikes": 1.0, "tent": 0.6}):
		map_art = null
	vfx = Vfx.new()
	vfx.load_dir("res://assets/vfx")
	vfx_layer = VfxLayer.new()
	vfx_layer.world = self
	add_child(vfx_layer)
	sprite_anim = SpriteAnim.new()
	if not sprite_anim.load_dir("res://assets/sprites/player"):
		sprite_anim = null
	if rng_seed != 0:
		rng.seed = rng_seed
	else:
		rng.randomize()
	start_run()


func start_run(p_starter: String = "chain_fist", p_qinggong: String = "tashue", p_map: String = "black_wind", p_diff: Dictionary = {}) -> void:
	map_id = p_map
	set_difficulty(p_diff)
	starter_id = p_starter
	shi.clear()
	dugu_combo_log.clear()
	qinggong_id = p_qinggong
	qg = Data.qinggong[qinggong_id]
	skills.clear()
	xinfa.clear()
	enhance_id = ""
	enhance_level = 0
	deferred_upgrades = 0
	level = 1
	school_id = str(Data.skills[starter_id]["school"])
	_load_school_sprites()
	add_skill(starter_id)
	stats = {}
	recalc()
	hp = float(stats["max_hp"])
	neili = float(stats["max_neili"])
	still_t = 0.0
	realm_time = [0.0, 0.0, 0.0]
	empower_count = 0
	break_count = 0
	_emp_ctx = -1
	burst_used = 0
	atk_buff_t = 0.0
	pills.clear()
	absorb_items.clear()
	vacuum_t = 0.0
	absorb_gap = 0.0
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

var _sprite_cache: Dictionary = {}


## 每个流派有自己的角色动画（Data.schools[..].sprite_dir）；加载失败时回退占位图形
func _load_school_sprites() -> void:
	var dir := str(Data.schools.get(school_id, {}).get("sprite_dir", "res://assets/sprites/player"))
	if dir == "":
		dir = "res://assets/sprites/player"
	if not _sprite_cache.has(dir):
		var sa := SpriteAnim.new()
		_sprite_cache[dir] = sa if sa.load_dir(dir) else null
	sprite_anim = _sprite_cache[dir]


func add_skill(id: String) -> void:
	var s: SkillBase = SwordSkills.create(id) if str(Data.skills[id]["school"]) == "sword" else FistSkills.create(id)
	s.setup(self, id, Data.skills[id])
	s.mods["range"] = float(s.mods["range"]) + float(talent_stats.get("skill_range", 0.0))      # 剑客天赋：全部招式范围 / 闪现距离
	s.mods["debuff"] = float(s.mods["debuff"]) + float(talent_stats.get("skill_debuff", 0.0))  # 剑客天赋：破绽 / 中毒 / 定身效果
	var tm: Dictionary = talent_skill_mods.get(id, {})
	for k in tm:
		s.mods[k] = float(s.mods.get(k, 0.0)) + float(tm[k])
	var gm: Dictionary = gear_skill_mods.get(id, {})
	for dir in gm:
		s.mods[dir] = float(s.mods.get(dir, 0.0)) + float(gm[dir]) / 100.0
	skills[id] = s


func st(key: String) -> float:
	return float(stats.get(key, 0.0))


func recalc() -> void:
	stats = Data.player_base.duplicate()
	for id in xinfa:
		var def: Dictionary = Data.xinfa[id]
		var l: int = int(xinfa[id]) + int(gear_xinfa.get(id, 0))
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
	_apply_synergies()
	# 标签加成：心法每升 1 级，加成 ×(1 + 0.5 × (等级-1))
	tag_bonus.clear()
	for id in xinfa:
		var def2: Dictionary = Data.xinfa[id]
		var scale := 1.0 + 0.5 * (int(xinfa[id]) + int(gear_xinfa.get(id, 0)) - 1)
		var b: Dictionary = def2["bonus"]
		for tg in b:
			tag_bonus[tg] = float(tag_bonus.get(tg, 0.0)) + float(b[tg]) * scale
	hp = minf(hp, st("max_hp"))
	neili = minf(neili, st("max_neili"))


## 阴阳与合璧：只看当前学会的两个心法。先加数值，再做倍率。
func _apply_synergies() -> void:
	synergies.clear()
	var ids: Array = xinfa.keys()
	if ids.size() < 2:
		return
	var defs: Array = []
	var yy := Data.yinyang_of(ids[0], ids[1])
	if yy != "":
		var d: Dictionary = Data.yinyang[yy]
		defs.append(d)
		synergies.append({"name": d["name"], "desc": d["desc"], "harmony": false})
	var h := Data.harmony_of(ids[0], ids[1])
	if not h.is_empty():
		defs.append(h)
		synergies.append({"name": h["name"], "desc": h["desc"], "harmony": true})
	for d in defs:
		var sd: Dictionary = d.get("stats", {})
		for k in sd:
			stats[k] = st(k) + float(sd[k])
	for d in defs:
		var md: Dictionary = d.get("mul", {})
		for k in md:
			stats[k] = st(k) * float(md[k])


## 冰火同炉：被定身的敌人持续灼烧（每 0.5 秒结算一次）
func _burn_tick(dt: float) -> void:
	if st("burn") <= 0.0:
		return
	burn_t -= dt
	if burn_t > 0.0:
		return
	burn_t = 0.5
	var dmg := st("burn") * 0.5 * (1.0 + st("damage_pct"))
	for e in enemies:
		if e.alive and e.stun > 0.0:
			damage_enemy(e, dmg * (0.3 if e.is_boss else 1.0), Vector2.ZERO)
			if effects.size() < MAX_EFFECTS and e.weak_fx <= 0.0:
				add_fx("text", e.pos + Vector2(0, -e.radius - 6), 0.6, {"text": "灼", "size": 20, "color": VERMILION})


## 选心法卡片上的提示：和已学心法搭配会出现什么
func _synergy_hint(new_id: String) -> String:
	if xinfa.size() != 1:
		return ""
	var have: String = xinfa.keys()[0]
	var out := ""
	var yy := Data.yinyang_of(have, new_id)
	if yy != "":
		out += "\n▶ 与「%s」成「%s」：%s" % [Data.xinfa[have]["name"], Data.yinyang[yy]["name"], Data.yinyang[yy]["desc"]]
	var h := Data.harmony_of(have, new_id)
	if not h.is_empty():
		out += "\n★ 合璧「%s」：%s" % [h["name"], h["desc"]]
	return out


func _exp_for(l: int) -> int:
	return int(Data.T("exp_mult") * (6 + 4.0 * l + 0.5 * l * l))


func cd_mult() -> float:
	return maxf(0.4, 1.0 - st("cd_reduce") - (Data.T("burst_yin_cd") if atk_buff_t > 0.0 else 0.0))


## 内力充盈（≥50%）时全部伤害 +25%
func dmg_mult() -> float:
	return Data.T("ying_dmg") + st("ying_dmg") if realm() == Realm.YING else 1.0


## 盈境的门槛（九阳神功等心法可以调低）
func ying_at() -> float:
	return clampf(Data.T("ying_at") + st("ying_shift"), 0.5, 0.95)


func realm() -> int:
	var r := neili / maxf(1.0, st("max_neili"))
	if r >= ying_at():
		return Realm.YING
	if r < maxf(0.05, Data.T("xu_below") - st("ping_widen")):
		return Realm.XU
	return Realm.PING


## 入定：站立不动一小会儿，回气加快并减伤
func meditating() -> bool:
	return st("no_meditate") <= 0.0 and still_t >= Data.T("meditate_after")


## 催动：处于盈境且内力够用时，招式出手会消耗内力并打出灌注版
func can_empower(cost: float) -> bool:
	return realm() == Realm.YING and neili >= cost


func pay_empower(cost: float) -> void:
	neili = maxf(0.0, neili - cost)
	empower_count += 1
	add_fx("ring", player_pos, 0.25, {"r0": 10.0, "r1": 34.0, "color": Color("#4fe0d0"), "vfx": "halo_empower"})


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
	_update_pills(dt)
	_update_absorb(dt)
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

	if input_dash and not dash_sealed() and dash_t <= 0.0 and dash_charges > 0 and neili >= float(qg["cost"]):
		_start_dash(move, max_charges)
	input_dash = false

	if dash_t > 0.0:
		dash_t -= dt
		player_pos += dash_dir * float(qg["dash_speed"]) * dt
		add_fx("trail", player_pos, 0.25, {"vfx": "trail_dash", "size": 80.0, "angle": facing.angle()})
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
	if nature() == "yang" and st("burst_yang") > 0.0:
		regen *= Data.T("yang_regen_mult")
	var rl := realm()
	realm_time[rl] += dt
	_burn_tick(dt)
	if move.length() < 0.1 and dash_t <= 0.0:
		still_t += dt
	else:
		still_t = 0.0
	if rl == Realm.XU:
		regen *= Data.T("xu_regen")
	if meditating():
		regen *= Data.T("meditate_regen") + st("med_regen")
	if rl == Realm.YING:
		regen -= Data.T("ying_leak") * max_n      # 真气外放：盈境每秒外泄一点，防止囤着不用
	neili = clampf(neili + regen * dt, 0.0, max_n)
	var hr := st("hp_regen") + (st("full_hp_regen") if neili >= max_n - 0.01 else 0.0)
	hp = minf(st("max_hp"), hp + hr * dt)
	if since_hit > 2.0 and shield < st("shield_max"):
		shield = minf(st("shield_max"), shield + st("shield_regen") * dt)

	# 真气爆发：消耗全部内力，消耗越多威力越大；每局只能爆发有限次数（见 burst_max）
	if input_ult and can_burst():
		_burst()
	input_ult = false
	atk_buff_t = maxf(0.0, atk_buff_t - dt)
	# 阳性内力（天赋）：内力满时生成护盾
	if nature() == "yang" and st("burst_yang") > 0.0 and neili >= max_n * 0.97 and since_hit > 0.5:
		shield = minf(Data.T("yang_shield_frac") * st("max_hp"), shield + Data.T("yang_shield_rate") * st("max_hp") * dt)


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
			add_fx("ring", player_pos, 0.3, {"r0": 10.0, "r1": lr, "color": JADE, "vfx": "ring_qinggong"})
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


## 内力属性：由两个心法的阴阳决定（见 Data.yinyang_of）。不满两个心法时没有属性。
func nature() -> String:
	var ids: Array = xinfa.keys()
	if ids.size() < 2:
		return ""
	var yy := Data.yinyang_of(ids[0], ids[1])
	return {"harmony": "harmony", "double_yang": "yang", "double_yin": "yin"}.get(yy, "")


## 本局最多能爆发几次：基础 1 次；调和内力 + 天赋「调和归元」再 +1；另有 burst_extra（装备 / 其他来源）
func burst_max() -> int:
	var n := 1 + int(st("burst_extra"))
	if nature() == "harmony" and st("burst_harmony") > 0.0:
		n += 1
	return n


func burst_left() -> int:
	return maxi(0, burst_max() - burst_used)


func can_burst() -> bool:
	return burst_left() > 0 and neili >= maxf(1.0, st("max_neili") * Data.T("burst_min_frac"))


## 真气爆发的威力系数（0~1）：当前内力占上限的比例
func burst_power() -> float:
	return clampf(neili / maxf(1.0, st("max_neili")), 0.0, 1.0)


func _burst() -> void:
	var f := burst_power()
	burst_used += 1
	neili = 0.0                                   # 消耗全部内力
	play_anim("ult", 0.5)
	var radius := lerpf(Data.T("burst_radius_min"), Data.T("burst_radius_max"), f)
	var dmg := Data.T("burst_damage") * (0.4 + 4.6 * f)
	area_hit_raw(player_pos, radius, dmg, [], "ult", 300.0 + 500.0 * f, 1.5 if f >= 0.5 else 0.0)
	for p in projs:
		if p.hostile and p.pos.distance_to(player_pos) < radius:
			p.life = 0.0
	if f >= 0.3:
		invuln = maxf(invuln, 0.8)
	# 阴性内力（天赋）：额外回血 + 攻速提升
	if nature() == "yin" and st("burst_yin") > 0.0:
		var heal := st("max_hp") * Data.T("burst_yin_heal") * f
		hp = minf(st("max_hp"), hp + heal)
		atk_buff_t = Data.T("burst_yin_time")
		add_fx("text", player_pos + Vector2(0, -50), 1.2, {"text": "阴柔回春 +%d" % int(heal), "size": 22, "color": JADE})
	add_fx("ring", player_pos, 0.45, {"r0": 20.0, "r1": radius, "color": JADE, "vfx": "burst_ult"})
	add_fx("text", player_pos + Vector2(0, -70), 1.0, {"text": "真气爆发 %d%%" % int(f * 100.0), "size": 26, "color": GOLD})
	shake = 6.0 + 8.0 * f


func add_shield(v: float) -> void:
	shield = minf(maxf(st("shield_max"), 30.0), shield + v)


# =====================================================================
# 刷怪
# =====================================================================

## 难度调节：怪物数量 / 血量 / 移动速度，各 100% ~ 300%（传入的是倍率 1.0 ~ 3.0，越界会被夹住）
func set_difficulty(d: Dictionary) -> void:
	difficulty = {
		"count": clampf(float(d.get("count", 1.0)), 1.0, 3.0),
		"hp": clampf(float(d.get("hp", 1.0)), 1.0, 3.0),
		"speed": clampf(float(d.get("speed", 1.0)), 1.0, 3.0),
	}
	reward_comp = (float(difficulty["count"]) + float(difficulty["hp"]) + float(difficulty["speed"])) / 3.0
	# 怪多了，同屏上限也跟着放宽一些（最多 +50%），否则 300% 的数量会被上限卡住
	max_enemies = int(Data.T("max_enemies") * lerpf(1.0, 1.5, (float(difficulty["count"]) - 1.0) / 2.0))


func _spawn(dt: float) -> void:
	var rate := (Data.T("spawn_base") + time * Data.T("spawn_slope")) * float(difficulty["count"])
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
		var ring_n := int(round(24.0 * float(difficulty["count"])))
		for i in ring_n:
			if enemies.size() < max_enemies:
				_spawn_enemy("bandit", player_pos + Vector2.from_angle(TAU * i / float(ring_n)) * SPAWN_DIST)
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
	e.max_hp = float(def["hp"]) * (1.0 + time / Data.T("hp_scale_t")) * float(difficulty["hp"])
	e.hp = e.max_hp
	e.speed = float(def["speed"]) * (1.0 + minf(time / 900.0, 0.3)) * rng.randf_range(0.9, 1.1) * float(difficulty["speed"])
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
	e.max_hp = float(def["hp"]) * float(difficulty["hp"])   # Boss 不随时间缩放血量，保持固定的战斗时长（难度倍率照样生效）
	e.hp = e.max_hp
	e.speed = float(def["speed"]) * float(difficulty["speed"])
	e.damage = float(def["damage"])
	e.boss_bolts = int(def["bolts"])
	e.guard_max = e.max_hp * Data.T("boss_guard_pct")
	e.guard = e.guard_max
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
		e.weak_fx = maxf(0.0, e.weak_fx - dt)
		e.vuln_t = maxf(0.0, e.vuln_t - dt)
		if e.poison_t > 0.0:
			e.poison_t -= dt
			e.poison_acc += dt
			if e.poison_acc >= 0.5:
				var pd := e.poison_dps * e.poison_acc
				e.poison_acc = 0.0
				e.hp -= pd
				e.flash = 0.05
				skill_dmg["jinshe"] = float(skill_dmg.get("jinshe", 0.0)) + pd
				if effects.size() < MAX_EFFECTS / 2:
					add_fx("text", e.pos + Vector2(rng.randf_range(-8, 8), -e.radius), 0.7, {"text": str(int(pd)), "size": 17, "color": Color("#9be05a")})
				if e.hp <= 0.0:
					_kill(e)
					continue
			if e.poison_t <= 0.0:
				e.poison_dps = 0.0
		if e.is_boss:
			if e.weak_t > 0.0:
				e.weak_t -= dt
			elif e.guard <= 0.0:
				e.guard_regen -= dt
				if e.guard_regen <= 0.0:
					e.guard = e.guard_max
					add_fx("text", e.pos + Vector2(0, -e.radius - 26), 1.0, {"text": "罡气重聚", "size": 20, "color": Color("#4fe0d0")})
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
	# 闪避（凌波微步）与免伤（铁布衫）
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
	if meditating():
		dmg *= 1.0 - minf(0.6, Data.T("meditate_reduce") + st("med_reduce"))
	since_hit = 0.0
	invuln = 0.6
	if st("thorns") > 0.0:
		area_hit_raw(player_pos, 90.0, st("thorns"), [], "thorns", 150.0)
	if shield > 0.0 and nature() == "yang" and st("burst_yang") > 0.0:    # 阳性内力：护盾在时反弹所受伤害的 30%
		area_hit_raw(player_pos, 100.0, dmg * Data.T("yang_reflect"), [], "reflect", 180.0)
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
	if vfx.has("hit_impact") and effects.size() < MAX_EFFECTS / 2:
		var hid := "hit_crit" if crit and vfx.has("hit_crit") else "hit_impact"
		add_fx("hit", e.pos, 0.2, {"vfx": hid, "size": (46.0 if crit else 34.0) + e.radius, "angle": knock_vec.angle() if knock_vec != Vector2.ZERO else rng.randf() * TAU})
	if effects.size() < MAX_EFFECTS:
		var big := crit
		add_fx("text", e.pos + Vector2(rng.randf_range(-8, 8), -e.radius), 0.9 if big else 0.7,
			{"text": str(int(amount)), "size": 28 if big else 19, "color": Color("#ffd24a") if big else Color("#fff4d6")})
	if e.hp <= 0.0:
		_kill(e)


func _kill(e: Enemy) -> void:
	e.alive = false
	kills += 1
	neili = minf(st("max_neili"), neili + st("kill_neili"))
	_drop_gem(e.pos, e.exp_value)
	if not e.is_boss and not e.is_elite:
		_maybe_drop_absorb(e.pos)
	if vfx.has("death_puff") and effects.size() < MAX_EFFECTS:
		add_fx("splat", e.pos, 0.35, {"r": e.radius * 1.4, "color": e.color, "vfx": "death_puff", "size": e.radius * 4.0})
	else:
		add_fx("splat", e.pos, 0.6, {"r": e.radius * 1.4, "color": e.color})
	if e.poison_burst > 0.0 and e.poison_dps > 0.0:
		area_hit_raw(e.pos, e.poison_burst, e.poison_dps * 3.0, ["控制", "范围"], "jinshe")
		add_fx("ring", e.pos, 0.4, {"r0": 8.0, "r1": e.poison_burst, "color": Color("#5a8a2a")})
	if e.chain:
		_chain_explode(e)
	if e.is_elite:
		_drop_pill(e.pos, "small")
		if rng.randf() < Data.T("elite_large_pill_chance"):
			_drop_pill(e.pos + Vector2(18, 6), "large")
		add_fx("text", e.pos + Vector2(0, -30), 1.0, {"text": "精英已破", "size": 18, "color": GOLD})
	if e.is_boss:
		boss_log.append("%s %.0fs" % [e.boss_name, time - e.born])
	if e.is_boss and not e.is_final:
		chests.append(e.pos)
		_drop_pill(e.pos + Vector2(-26, 10), "large")
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
	add_fx("ring", e.pos, 0.3, {"r0": 10.0, "r1": er, "color": GOLD, "vfx": "burst_gold"})
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
	if e.vuln_t > 0.0:
		m *= 1.0 + e.vuln
	if sid == "dugu":
		var qi := int(shi.get("po_qi", 0))
		if qi > 0:
			if e.is_boss:
				m *= 1.0 + 0.1 * qi
			neili = minf(st("max_neili"), neili + 0.3 * qi)
	var crit_p := st("crit_chance") + (float(sk.mods["crit"]) if sk != null else 0.0)
	# 破绽联动：被定身 / 减速的敌人，特定标签的招式有额外效果
	var weak_hit := false
	if e.stun > 0.0:
		if tags.has("近战") or tags.has("蓄力"):
			crit_p += Data.T("weak_crit")
			weak_hit = true
		if tags.has("范围"):
			m *= Data.T("weak_aoe_mult")
			weak_hit = true
	if e.slow_t > 0.0 and (tags.has("追踪") or tags.has("贯穿")):
		m *= Data.T("weak_slow_mult")
		weak_hit = true
	if weak_hit and e.weak_fx <= 0.0 and effects.size() < MAX_EFFECTS:
		e.weak_fx = 0.8
		add_fx("text", e.pos + Vector2(0, -e.radius - 14), 0.85, {"text": "破绽", "size": 22, "color": JADE})
	var crit := force_crit or rng.randf() < crit_p
	if crit:
		m *= st("crit_mult")
	var emp := (_emp_ctx == 1) if _emp_ctx >= 0 else (sk != null and sk.empowered)
	if emp:
		m *= maxf(0.2, 1.0 + st("emp_power"))
	if crit and st("crit_neili") > 0.0:
		neili = minf(st("max_neili"), neili + st("crit_neili"))
	var amount := base * m
	var hs := st("hit_slow")
	if sk != null and float(sk.mods["debuff"]) > 0.0:
		hs = maxf(hs, float(sk.mods["debuff"]))
	if hs > 0.0:
		slow_enemy(e, 1.0 - minf(0.6, hs), 1.5)
	if sk != null and float(sk.mods["heal"]) > 0.0:
		hp = minf(st("max_hp"), hp + minf(3.0, amount * float(sk.mods["heal"])))
	skill_dmg[sid] = float(skill_dmg.get(sid, 0.0)) + amount
	if e.is_boss:
		amount = _boss_guard(e, amount, emp)
	damage_enemy(e, amount, knock_vec, crit)
	return amount


## Boss 护体罡气：罡气期间只受一半伤害，并消耗罡气（催动攻击消耗 ×3）；罡气被打破后虚弱一段时间，受伤加成。
func _boss_guard(e: Enemy, amount: float, emp: bool) -> float:
	if e.weak_t > 0.0:
		return amount * Data.T("break_dmg")
	if e.guard <= 0.0:
		return amount
	e.guard -= amount * (Data.T("guard_empower_mult") if emp else 1.0)
	if e.guard <= 0.0:
		e.guard = 0.0
		e.weak_t = Data.T("break_t")
		e.guard_regen = Data.T("guard_regen_t")
		break_count += 1
		shake = maxf(shake, 9.0)
		add_fx("text", e.pos + Vector2(0, -e.radius - 30), 1.4, {"text": "破罡！", "size": 30, "color": Color("#4fe0d0")})
		add_fx("ring", e.pos, 0.5, {"r0": 20.0, "r1": 130.0, "color": Color("#4fe0d0"), "vfx": "burst_break"})
	return amount * Data.T("guard_reduce")


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
	pr.splash = float(o.get("splash", s.def.get("splash_radius", 0.0)))
	pr.splash_frac = float(o.get("splash_frac", s.def.get("splash_frac", 0.0)))
	pr.falloff = float(o.get("falloff", s.def.get("falloff", 1.0)))
	pr.stun_chance = float(o.get("stun_chance", s.def.get("stun_chance", 1.0)))
	pr.bounce = int(o.get("bounce", 0))
	pr.bounce_dmg = float(o.get("bounce_dmg", 0.5))
	pr.pierce_reset = int(o.get("pierce_reset", maxi(1, pr.pierce)))
	pr.poison = float(o.get("poison", 0.0))
	pr.vuln = float(o.get("vuln", 0.0))
	pr.empowered = s.empowered
	projs.append(pr)
	return pr


func add_zone(z: Dictionary) -> void:
	if not z.has("pos"):
		z["pos"] = player_pos
	if z.has("skill") and not z.has("emp"):
		z["emp"] = (z["skill"] as SkillBase).empowered
	zones.append(z)


func fx_slash(at: Vector2, angle: float, reach: float, arc: float, heavy: bool) -> void:
	add_fx("slash", at, 0.2, {"angle": angle, "r": reach, "arc": arc, "heavy": heavy, "vfx": "slash_heavy" if heavy else "slash_fist"})


# =====================================================================
# 弹体 / 区域
# =====================================================================

## 破鞭式弹射：整个画面（不是整张地图）里离 pos 最近的敌人
func _nearest_on_screen(pos: Vector2, exclude: Dictionary) -> Enemy:
	var best: Enemy = null
	var bd := INF
	for e in enemies:
		if not e.alive or exclude.has(e.uid) or not _vis(e.pos, 0.0):
			continue
		var d2 := pos.distance_squared_to(e.pos)
		if d2 < bd:
			bd = d2
			best = e
	return best


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
						if p.vuln > 0.0:
							apply_vuln(e, p.vuln, true)
						_emp_ctx = 1 if p.empowered else 0
						hit_enemy(e, p.damage, p.tags, p.vel.normalized() * p.knock, p.skill_id)
						_emp_ctx = -1
						if p.stun > 0.0 and (p.stun_chance >= 1.0 or rng.randf() < p.stun_chance):
							stun_enemy(e, p.stun, p.chain)
						if p.poison > 0.0:
							poison_enemy(e, p.poison, p.skill_id)
						if p.splash > 0.0:
							_splash(e, p)
						p.damage *= p.falloff
						if p.split > 0:
							_split(p)
							p.split = 0
						p.pierce -= 1
						if p.pierce <= 0 and p.bounce > 0:
							var nt := _nearest_on_screen(p.pos, p.hit)
							if nt != null:
								p.bounce -= 1
								p.pierce = p.pierce_reset
								p.damage *= p.bounce_dmg
								p.vel = (nt.pos - p.pos).normalized() * p.speed
								p.angle = p.vel.angle()
								p.life = maxf(p.life, p.pos.distance_to(nt.pos) / maxf(p.speed, 1.0) + 0.4)
								add_fx("ring", p.pos, 0.2, {"r0": 4.0, "r1": 26.0, "color": Color("#8ab4d8")})
								break
							p.bounce = 0
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


## 小范围溅射：命中点周围的其他敌人受到一部分伤害（掌）
func _splash(center_e: Enemy, p: Projectile) -> void:
	for nb in _query(center_e.pos, p.splash):
		if nb == center_e or not nb.alive:
			continue
		if nb.pos.distance_to(center_e.pos) < p.splash + nb.radius:
			hit_enemy(nb, p.damage * p.splash_frac, p.tags, (nb.pos - center_e.pos).normalized() * p.knock * 0.5, p.skill_id)


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
		_emp_ctx = 1 if bool(z.get("emp", false)) else 0
		match str(z["kind"]):
			"impact":
				if z["t"] >= z["delay"]:
					var s: SkillBase = z["skill"]
					area_hit(s, zpos, zr, z["dmg"], 250.0, z["stun"])
					add_fx("ring", zpos, 0.3, {"r0": 10.0, "r1": zr, "color": VERMILION, "vfx": "burst_quake"})
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
	_emp_ctx = -1


# =====================================================================
# 经验 / 秘籍 / 升级
# =====================================================================

## 还丹：小还丹回 12% 气血，大还丹回 35%（精英必掉小还丹，有几率掉大还丹；小 Boss 必掉大还丹）
func _drop_pill(at: Vector2, kind: String) -> void:
	if pills.size() >= 30:
		pills.pop_front()
	pills.append({"pos": at, "kind": kind, "age": 0.0})


func _update_pills(dt: float) -> void:
	var i := 0
	while i < pills.size():
		var pl: Dictionary = pills[i]
		var d: float = (pl["pos"] as Vector2).distance_to(player_pos)
		pl["age"] = float(pl["age"]) + dt
		if d < 20.0:
			var frac := Data.T("pill_large") if pl["kind"] == "large" else Data.T("pill_small")
			var heal := st("max_hp") * frac
			hp = minf(st("max_hp"), hp + heal)
			add_fx("text", player_pos + Vector2(0, -34), 1.0, {"text": "%s +%d" % ["大还丹" if pl["kind"] == "large" else "小还丹", int(heal)], "size": 20, "color": VERMILION})
			pills.remove_at(i)
			continue
		if vacuum_t > 0.0:
			pl["pos"] = (pl["pos"] as Vector2) + (player_pos - (pl["pos"] as Vector2)).normalized() * VACUUM_SPEED * dt
		elif d < st("pickup_range") * 0.7:
			pl["pos"] = (pl["pos"] as Vector2) + (player_pos - (pl["pos"] as Vector2)).normalized() * 300.0 * dt
		i += 1


## 吸星大法：普通击杀 1% 几率掉落（同时只会有一个，且两次掉落至少隔 25 秒）。捡到后 3 秒内全场宝石 / 还丹飞向主角。
func _maybe_drop_absorb(at: Vector2) -> void:
	if not absorb_items.is_empty() or absorb_gap < Data.T("absorb_min_gap"):
		return
	if rng.randf() < Data.T("absorb_chance"):
		absorb_items.append({"pos": at, "age": 0.0})
		absorb_gap = 0.0
		add_fx("text", at + Vector2(0, -30), 1.6, {"text": "吸星大法现世！", "size": 24, "color": Color("#b98cff")})


func _update_absorb(dt: float) -> void:
	absorb_gap += dt
	vacuum_t = maxf(0.0, vacuum_t - dt)
	var i := 0
	while i < absorb_items.size():
		var it: Dictionary = absorb_items[i]
		it["age"] = float(it["age"]) + dt
		if (it["pos"] as Vector2).distance_to(player_pos) < 26.0:
			vacuum_t = Data.T("absorb_vacuum_time")
			absorb_items.remove_at(i)
			add_fx("text", player_pos + Vector2(0, -60), 1.6, {"text": "吸星大法！", "size": 30, "color": Color("#b98cff")})
			add_fx("ring", player_pos, 0.6, {"r0": 20.0, "r1": 420.0, "color": Color("#b98cff")})
			shake = maxf(shake, 5.0)
			continue
		i += 1


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
		if vacuum_t > 0.0:
			gem_pos[i] += (player_pos - gem_pos[i]).normalized() * VACUUM_SPEED * dt      # 吸星大法：全场飞来
		elif d < pull:
			gem_pos[i] += (player_pos - gem_pos[i]).normalized() * 420.0 * dt            # 只有走进拾取范围才会被吸过来
		i += 1


func _gain_exp(v: int) -> void:
	var gain := int(ceil(v * (1.0 + st("exp_pct")) * (1.0 + (reward_comp - 1.0) * float(Data.difficulty["exp_in_run"]))))
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
			if skills.has("dugu"):
				pending_chests += 1   # 独孤九剑：秘籍直接换成「+3 层」的式
			elif enhance_id == "":
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
	if skills.has("dugu"):
		var sc := shi_cards(3, int(Data.T("shi_chest_gain")), "chest")
		if not sc.is_empty():
			return sc
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
	var dugu_route := skills.has("dugu")
	var shi_pool: Array = shi_cards(2, int(Data.T("shi_card_gain")), "level") if dugu_route else []
	# 已有技能：每个技能给 2 张升级卡（不同方向，档位随机）
	for id in skills:
		var s: SkillBase = skills[id]
		if dugu_route or s.upgrades.size() >= Data.max_upgrades:
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
		if dugu_route or skills.has(id) or str(def["school"]) != school_id:
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
				"title": "修习：%s【%s】" % [def2["name"], "阳" if str(def2.get("yy", "")) == "yang" else "阴"],
				"desc": str(def2["desc"]) + _synergy_hint(id),
			})
	_shuffle(pool)
	var out: Array = shi_pool.duplicate()    # 独孤九剑：每次至少两张「式」
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
		"shi_new", "shi_up":
			add_shi(id, int(c["gain"]))
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
	for pl in pills:
		if _vis(pl["pos"]):
			_draw_pill(pl)
	for it in absorb_items:
		if _vis(it["pos"], 80.0):
			_draw_absorb(it)
	for c in chests:
		if _vis(c):
			var bob := sin(time * 4.0) * 3.0
			draw_rect(Rect2(c + Vector2(-11, -8 + bob), Vector2(22, 16)), Color("#8a5a1f"))
			draw_rect(Rect2(c + Vector2(-11, -8 + bob), Vector2(22, 16)), GOLD, false, 2.0)
			draw_arc(c + Vector2(0, bob), 20.0, 0.0, TAU, 20, Color(GOLD, 0.4 + 0.3 * sin(time * 5.0)), 2.0)
	# 角色、怪物、场景物件按「脚底的 y」从上到下排序再画：靠下的盖住靠上的，前后关系才对
	var ents: Array = []
	for e in enemies:
		if _vis(e.pos, 60.0):
			var key := _enemy_art_key(e)
			var fy := e.pos.y + (enemy_art.height_of(key) * 0.42 if enemy_art != null and enemy_art.has(key) else e.radius)
			ents.append([fy, 0, e])
	if map_art != null:
		for pr in map_art.visible_props(player_pos, Vector2(700.0, 420.0)):
			ents.append([(pr["pos"] as Vector2).y, 1, pr])
	ents.append([player_pos.y + 14.0, 2, null])
	ents.sort_custom(func(a, b): return a[0] < b[0])
	for it in ents:
		match int(it[1]):
			0: _draw_enemy(it[2])
			1: map_art.draw_prop(self, it[2])
			2: _draw_player()
	for p in projs:
		if _vis(p.pos):
			_draw_proj(p)
	_draw_effects()


## 吸星大法：旋转的紫青色星旋，比还丹大得多，远处也看得见
func _draw_absorb(it: Dictionary) -> void:
	var c: Vector2 = it["pos"]
	var t := time * 3.0
	draw_circle(c, 26.0 + 3.0 * sin(t * 1.3), Color("#b98cff", 0.16))
	for k in 3:
		var a0 := t + k * TAU / 3.0
		draw_arc(c, 18.0 - k * 3.0, a0, a0 + 2.4, 14, Color("#b98cff", 0.9), 3.0)
		draw_arc(c, 11.0 - k * 2.0, -a0 * 1.4, -a0 * 1.4 + 2.0, 10, Color("#4fe0d0", 0.9), 2.0)
	draw_circle(c, 4.0, Color("#fff6dc"))


## 还丹：像素风小葫芦丹——小的红褐色，大的金色带光晕
func _draw_pill(pl: Dictionary) -> void:
	var at: Vector2 = pl["pos"]
	var big: bool = pl["kind"] == "large"
	var bob := sin(time * 5.0 + at.x * 0.1) * 2.0
	var c := at + Vector2(0, bob)
	var u := 3.0 if big else 2.2                 # 一个像素块的边长
	var body := Color("#e0a82e") if big else Color("#c2452d")
	var dark := Color("#7a4a12") if big else Color("#6e1f12")
	var hi := Color("#fff2b0") if big else Color("#f08c70")
	if big:
		draw_circle(c, 14.0, Color(GOLD, 0.18 + 0.1 * sin(time * 6.0)))
	# 葫芦：上小下大，像素块拼出
	draw_rect(Rect2(c + Vector2(-1.0, -4.0) * u, Vector2(2.0, 1.0) * u), dark)                 # 瓶塞
	draw_rect(Rect2(c + Vector2(-1.5, -3.0) * u, Vector2(3.0, 2.0) * u), body)                 # 上腹
	draw_rect(Rect2(c + Vector2(-2.5, -1.0) * u, Vector2(5.0, 3.0) * u), body)                 # 下腹
	draw_rect(Rect2(c + Vector2(-1.5, 2.0) * u, Vector2(3.0, 1.0) * u), body)
	draw_rect(Rect2(c + Vector2(-2.5, -1.0) * u, Vector2(1.0, 3.0) * u), dark)                  # 左侧暗边
	draw_rect(Rect2(c + Vector2(1.0, -3.0) * u, Vector2(1.0, 1.0) * u), dark)
	draw_rect(Rect2(c + Vector2(0.5, -0.5) * u, Vector2(1.0, 1.0) * u), hi)                     # 高光


func _hash(cx: int, cy: int) -> int:
	return absi((cx * 73856093) ^ (cy * 19349663))


func _draw_background() -> void:
	if map_art != null:
		map_art.draw_ground(self, player_pos, Vector2(680.0, 400.0))
		return
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
				if vfx.has("zone_crack"):
					continue
				var a := 1.0 - float(z["t"]) / float(z["life"])
				draw_circle(zpos, zr, Color(0.1, 0.08, 0.06, 0.12 * a + 0.04))
				for k in 7:
					var ang := TAU * k / 7.0 + 0.4
					var mid := zpos + Vector2.from_angle(ang) * zr * 0.5 + Vector2.from_angle(ang + 1.2) * 8.0
					draw_line(zpos, mid, Color(0.1, 0.06, 0.04, 0.7 * a), 2.0)
					draw_line(mid, zpos + Vector2.from_angle(ang) * zr * 0.95, Color(0.1, 0.06, 0.04, 0.7 * a), 2.0)
			"vortex":
				if vfx.has("zone_vortex"):
					continue
				var a2 := 1.0 - float(z["t"]) / float(z["life"])
				for k in 3:
					var rot := float(z["t"]) * 6.0 + k * 2.1
					draw_arc(zpos, zr * (0.35 + 0.2 * k), rot, rot + 2.0, 16, Color(INK, 0.4 * a2), 3.0)


func _enemy_art_key(e: Enemy) -> String:
	if e.is_final:
		return "boss"
	if e.is_boss:
		return e.type_id        # 小 Boss：有对应素材才用（mini_boss_1 ...）
	if e.is_elite:
		return "elite"
	return e.type_id


func _draw_enemy(e: Enemy) -> void:
	var key := _enemy_art_key(e)
	if enemy_art != null and enemy_art.has(key):
		_draw_enemy_sprite(e, key)
		return
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
	if e.is_boss:
		if e.weak_t > 0.0:
			draw_arc(e.pos, r + 8.0, 0.0, TAU, 32, Color(GOLD, 0.5 + 0.5 * sin(time * 16.0)), 4.0)
		elif e.guard > 0.0:
			draw_arc(e.pos, r + 8.0, 0.0, TAU * e.guard / maxf(1.0, e.guard_max), 32, Color("#4fe0d0", 0.85), 4.0)
	if e.stun > 0.0:
		var ang := time * 8.0
		for k in 3:
			var sp := e.pos + Vector2(0, -r - 8.0) + Vector2.from_angle(ang + k * 2.09) * 9.0
			draw_circle(sp, 2.5, GOLD)
	if e.slow_t > 0.0:
		draw_arc(e.pos, r + 2.0, 0.0, TAU, 20, Color("#5aa7d8", 0.8), 2.0)


## 有立绘的怪物：脚底影子 + 立绘（朝向玩家）+ 受击 / 减速的着色 + 精英圈 / 罡气圈 / 眩晕星
func _draw_enemy_sprite(e: Enemy, key: String) -> void:
	var h := enemy_art.height_of(key)
	var feet := e.pos + Vector2(0, h * 0.42)
	var flip := player_pos.x < e.pos.x
	var walking := e.stun <= 0.0
	var ph := float(e.uid % 11)
	# 素材每帧几乎一样：用起伏 / 前倾 / 轻微挤压补出「走路」的体积感；被打中时被压扁一下
	var big := e.is_boss
	var bob := Depth.bob(time, (2.0 if big else 1.5 + h * 0.03), 5.0 if big else 9.0, ph) if walking else 0.0
	var lean := (-0.06 if flip else 0.06) if walking else 0.0
	var sq := 1.0 + 0.03 * sin(time * 17.0 + ph)
	if e.flash > 0.0:
		sq = 0.86
		lean = (0.12 if flip else -0.12)           # 挨打后仰
	Depth.shadow(self, feet + Vector2(0, -1), h * 0.7, bob)
	if e.is_boss and e.boss_state == "windup":
		draw_line(e.pos, e.pos + e.charge_dir * 260.0, Color(VERMILION, 0.3), e.radius * 1.6)
	var tint := Color.WHITE
	if e.flash > 0.0:
		tint = Color(1.6, 1.3, 1.3)
	elif e.slow_t > 0.0:
		tint = Color(0.72, 0.88, 1.0)
	elif e.stun > 0.0:
		tint = Color(0.85, 0.85, 0.85)
	enemy_art.draw(self, key, time + ph * 0.13, feet - Vector2(0, bob), flip, tint, lean, sq)
	var r := e.radius
	if e.is_elite:
		draw_arc(e.pos + Vector2(0, h * 0.1), h * 0.5, 0.0, TAU, 26, Color(GOLD, 0.8), 2.0)
	if e.is_boss:
		if e.weak_t > 0.0:
			draw_arc(e.pos, r + 8.0, 0.0, TAU, 32, Color(GOLD, 0.5 + 0.5 * sin(time * 16.0)), 4.0)
		elif e.guard > 0.0:
			draw_arc(e.pos, r + 8.0, 0.0, TAU * e.guard / maxf(1.0, e.guard_max), 32, Color("#4fe0d0", 0.85), 4.0)
	if e.stun > 0.0:
		var ang := time * 8.0
		for k in 3:
			var sp := e.pos + Vector2(0, -h * 0.55) + Vector2.from_angle(ang + k * 2.09) * 9.0
			draw_circle(sp, 2.5, GOLD)
	if e.slow_t > 0.0:
		draw_arc(e.pos + Vector2(0, h * 0.35), r + 2.0, 0.0, TAU, 20, Color("#5aa7d8", 0.8), 2.0)


func _draw_proj(p: Projectile) -> void:
	var dir := Vector2.from_angle(p.angle)
	if p.hostile:
		draw_circle(p.pos, p.radius, Color(VERMILION, 0.85))
		draw_arc(p.pos, p.radius, 0.0, TAU, 12, Color(0.1, 0.0, 0.0, 0.8), 2.0)
		return
	if vfx.has(str(VfxLayer.PROJ_IDS.get(p.kind, ""))):
		return    # 有特效素材：由 VfxLayer 绘制
	match p.kind:
		"wave":
			for k in 3:
				var off := p.pos - dir * (k * 14.0)
				draw_arc(off, p.radius, p.angle - 1.0, p.angle + 1.0, 18, Color(INK, 0.55 - k * 0.17), 6.0 - k * 1.5)
		"sword":
			draw_line(p.pos - dir * 30.0, p.pos, Color("#8ab4d8", 0.55), 3.0)
			draw_line(p.pos - dir * 12.0, p.pos + dir * 8.0, Color("#eaf4ff"), 2.5)
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
		"school": school_id, "map": map_id, "difficulty": {"count": int(round(float(difficulty["count"]) * 100.0)), "hp": int(round(float(difficulty["hp"]) * 100.0)), "speed": int(round(float(difficulty["speed"]) * 100.0))}, "starter": starter_id, "qinggong": qinggong_id,
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
	var st := _player_anim_state_base()
	if dugu_true():         # 真·独孤九剑：散发、持剑、周身气场的另一套动作
		match str(st[0]):
			"idle": st[0] = "true_idle"
			"walk": st[0] = "true_walk"
			"thrust", "slash", "palm", "punch": st[0] = "true_thrust"
	return st


func _player_anim_state_base() -> Array:
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


## 走路时每一步的上下起伏（站着 / 冲刺时为 0）
func _player_bob() -> float:
	if dash_t > 0.0 or input_move.length() <= 0.1:
		return 0.0
	return Depth.bob(time, 2.4, 12.0)


func _draw_player() -> void:
	var blink := invuln > 0.0 and dash_t <= 0.0 and int(time * 24.0) % 2 == 0
	if blink:
		return
	var alpha := 0.45 if stealth_t > 0.0 else 1.0
	var has_sprite := sprite_anim != null
	if has_sprite:
		# 脚下的接触影子（角色脚底在 player_pos 下方 14px）；走路起伏时影子随之变小
		Depth.shadow(self, player_pos + Vector2(0, 14), 30.0, _player_bob())
	else:
		draw_circle(player_pos + Vector2(0, 9), 10.0, Color(0, 0, 0, 0.12))
	if dugu_true() and vfx.has("awaken_aura"):
		vfx.draw(self, "awaken_aura", vfx.frame_loop("awaken_aura", time), player_pos + Vector2(0, 8), 120.0, 0.0, Color(1, 1, 1, 0.6))
	if realm() == Realm.YING:
		draw_arc(player_pos, 19.0, 0.0, TAU, 28, Color("#4fe0d0", 0.55 * alpha), 2.0)
	if meditating():
		var pulse := 0.5 + 0.5 * sin(time * 4.0)
		draw_arc(player_pos, 30.0 + 2.0 * pulse, 0.0, TAU, 36, Color(GOLD, 0.35 + 0.3 * pulse), 2.0)
	if shield > 0.0:
		draw_arc(player_pos, 24.0, 0.0, TAU, 28, Color("#7fc8e8", 0.8), 3.0)
	if has_sprite:
		var state := _player_anim_state()
		var tint := Color(1.0, 0.55, 0.55, alpha) if since_hit < 0.08 else Color(1.0, 1.0, 1.0, alpha)
		var lean := 0.0
		var sq := 1.0
		if dash_t > 0.0:
			lean = 0.2 * signf(dash_dir.x)        # 冲刺：身体前倾、拉长
			sq = 0.92
		elif input_move.length() > 0.1:
			lean = 0.07 * clampf(input_move.x, -1.0, 1.0)
			sq = 1.0 + 0.025 * sin(time * 26.0)
		if sprite_anim.draw(self, str(state[0]), float(state[1]), player_pos + Vector2(0, 14.0 - _player_bob()), facing.x < 0.0, tint, 1.0, lean, sq):
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
		if fx.has("vfx") and vfx.has(str(fx["vfx"])):
			continue
		match str(fx["kind"]):
			"text":
				# 飘字：游戏字体 + 深色描边（深色地面上也看得清）；出现时先「弹」一下变大，大半寿命保持不透明再淡出
				var col: Color = fx["color"]
				if col.get_luminance() < 0.45:
					col = col.lightened(0.4)
				var tfont: Font = Data.font_bold if Data.font_bold != null else font
				var pop := 1.0 + 0.35 * maxf(0.0, 1.0 - t / 0.12)
				var fs := int(float(fx["size"]) * pop)
				var ta := clampf(a * 2.2, 0.0, 1.0)
				var tw := 200.0
				var tp := at - Vector2(tw * 0.5, 0)
				draw_string_outline(tfont, tp, str(fx["text"]), HORIZONTAL_ALIGNMENT_CENTER, tw, fs, maxi(4, fs / 4), Color(0.05, 0.03, 0.02, ta))
				draw_string(tfont, tp, str(fx["text"]), HORIZONTAL_ALIGNMENT_CENTER, tw, fs, Color(col, ta))
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


# =====================================================================
# 剑客：破绽 / 中毒 / 独孤九剑「式」
# =====================================================================

## 破绽：受到的伤害额外 +v，持续 t 秒；spread 时顺带让附近一名敌人也露出破绽（万法皆破）
func apply_vuln(e: Enemy, v: float, spread: bool = false) -> void:
	var t := Data.T("dugu_vuln_t")
	if e.vuln_t <= 0.0 and e.weak_fx <= 0.0 and effects.size() < MAX_EFFECTS:
		e.weak_fx = 0.8
		add_fx("text", e.pos + Vector2(0, -e.radius - 14), 0.85, {"text": "破绽", "size": 22, "color": JADE})
	e.vuln = maxf(e.vuln if e.vuln_t > 0.0 else 0.0, v)
	e.vuln_t = t
	if spread:
		var nb := _nearest_from(e.pos, 170.0, {e.uid: true})
		if nb != null:
			nb.vuln = maxf(nb.vuln if nb.vuln_t > 0.0 else 0.0, v)
			nb.vuln_t = t


## 中毒：每次命中叠加 dps（最多 6 层，每层 = dps），重置持续时间
func poison_enemy(e: Enemy, dps: float, sid: String) -> void:
	var sk: SkillBase = skills.get(sid)
	var mult := 2.0 if (sk != null and sk.empowered) else 1.0
	e.poison_dps = minf(dps * 6.0 * mult, e.poison_dps + dps * mult)
	e.poison_t = 4.0
	if sk != null and sk.enhanced():
		e.poison_burst = sk.ev(80.0, 100.0, 120.0)


func shi_total() -> int:
	var t := 0
	for k in shi:
		t += int(shi[k])
	return t


## 独孤九剑形态：0 = 没走独孤路线；1 = 起手；2 = 万法皆破（总层 > 20）；3 = 真·独孤九剑（总层 > 30）
func dugu_stage() -> int:
	if not skills.has("dugu"):
		return 0
	var t := shi_total()
	if t > int(Data.T("shi_stage3")):
		return 3
	return 2 if t > int(Data.T("shi_stage2")) else 1


func dugu_true() -> bool:
	return dugu_stage() == 3


## 真·独孤九剑封印轻功
func dash_sealed() -> bool:
	return dugu_true()


func shi_name(id: String) -> String:
	for d in Data.shi:
		if str(d["id"]) == id:
			return str(d["name"])
	return id


## 领悟 / 提升一式；返回实际增加的层数
func add_shi(id: String, n: int) -> int:
	var cap := int(Data.T("shi_lv_max"))
	if not shi.has(id) and shi.size() >= int(Data.T("shi_kinds")):
		return 0
	var old_stage := dugu_stage()
	var old := int(shi.get(id, 0))
	shi[id] = mini(cap, old + n)
	var stage := dugu_stage()
	if stage > old_stage and stage >= 2:
		var txt := "万法皆破" if stage == 2 else "九剑真传"
		add_fx("text", player_pos + Vector2(0, -60), 2.4, {"text": txt, "size": 30, "color": VERMILION})
		add_fx("ring", player_pos, 0.9, {"r0": 10.0, "r1": 260.0, "color": GOLD})
		shake = maxf(shake, 8.0)
		if stage == 3:
			play_anim("awaken", 0.6)
	return int(shi[id]) - old


## 独孤九剑的「式」卡牌：已学的提升、新式（总共最多 4 种）。gain：本次领悟的层数
func shi_cards(n: int, gain: int, src: String) -> Array:
	var pool: Array = []
	var cap := int(Data.T("shi_lv_max"))
	for d in Data.shi:
		var id := str(d["id"])
		var lv := int(shi.get(id, 0))
		if lv > 0:
			if lv < cap:
				pool.append({"kind": "shi_up", "id": id, "gain": gain, "tag": "式", "src": src,
					"title": "%s Lv%d→%d" % [d["name"], lv, mini(cap, lv + gain)], "desc": str(d["desc"])})
		elif shi.size() < int(Data.T("shi_kinds")):
			pool.append({"kind": "shi_new", "id": id, "gain": gain, "tag": "新式", "src": src,
				"title": "领悟：%s" % d["name"], "desc": str(d["desc"])})
	_shuffle(pool)
	var out: Array = []
	while out.size() < n and not pool.is_empty():
		out.append(pool.pop_back())
	return out
