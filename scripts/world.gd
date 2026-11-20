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
const LITE_ENEMIES := 140          # 画面里怪物超过这个数：普通怪用快速画法（没有倾斜 / 挤压）
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
var shi: Dictionary = {}            # 独孤九剑：已领悟的「式」→ 层数（最多 4 种；计入 9 / 18 / 27 层门槛）
var shi_bonus: Dictionary = {}      # 每一式的品质加成（只加威力，不计入门槛）
var _sh_tex: Texture2D = Depth.shadow_texture()
var _lite := false                  # 本帧画面里怪太多：普通怪走快速绘制
var props_enabled := true          # 场景里随机出现可打碎的木箱 / 酒坛 / 火盆
var prop_t := 3.0
var pickup_art: Dictionary = {}    # 掉落物素材（assets/pickups）：id → {tex, w, h}
var hzones: Array = []                # Boss 留下的地面区域：毒雾 / 冰封带（持续伤害 / 减速）
var player_knock := Vector2.ZERO       # Boss 技能击退
var player_slow_t := 0.0           # 银鞭减速
var boss_deadline := -1.0          # 大 Boss 现身后的限时（秒，游戏内时间）；超时 = 寨主逃遁，判负
var timeout_fail := false
var sword_break_count := 0           # 统计：「剑破天下」触发次数（测试用）
var dugu_combo_log: Array = []     # 统计：真·独孤九剑的连击段数（测试用）
var soul := 0.0                    # 刀魂（刀客，0~100）
var soul_idle := 0.0
var tulong_equipped := false         # 装备了传说「屠龙宝刀」（光明顶彩蛋）
var tulong_on := false               # 彩蛋已触发：无视 50% 防御、护盾双倍伤害、破盾后易伤
var fist_ult_t := 0.0              # 武者「拳掌无敌」剩余时间
var fist_ult_count := 0
var cut_count := 0                 # 本局斩落的敌方投射物数量（独孤九剑）
var fist_qi := 0.0                 # 武者蓄劲（0~100）
var fist_qi_crit_t := 0.0
var cunjin_count := 0              # 本局寸劲震爆次数
var meta_level := 1                # 局外等级（由 main 在开局前设置；决定「另觅机缘」次数）
var rerolls_left := 0              # 另觅机缘：本局剩余次数
var rerolls_used := 0
var ji_haste_until := -1.0          # 极·万剑归宗：冲刺后的加速窗口
var tb_count := 0                  # 本局真·霸刀破岳触发次数
var tb_t := 0.0                    # 真·霸刀破岳：剩余持续时间（>0 = 生效中）
var tb_cd := 0.0                   # 真·霸刀破岳：冷却（状态结束后才开始倒计时）
var baodao := false                # 本次出手是「霸刀破岳」
var baodao_ctx := false            # 弹体 / 区域命中结算时的破岳标记
var dash_end_t := -99.0
var school_id := "fist"           # 创建角色时选定，决定可学的招式池
var qinggong_id := "tashue"
var qg: Dictionary = {}
var skills: Dictionary = {}       # id -> SkillBase（最多 4 个）
var xinfa: Dictionary = {}        # id -> 等级（最多 2 个；修习 = Lv1，之后每次强化 +1，最高 Lv4）
var xinfa_q: Dictionary = {}      # id -> 每次强化的品质（0 普通 … 3 传说）
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
var map_art_dir := ""
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
var next_wave := 120.0
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
	vfx = Vfx.new()
	vfx.load_dir("res://assets/vfx")
	_load_pickups()
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


func _load_map_art() -> void:
	var cfg: Dictionary = Data.maps[map_id].get("art", {})
	var dir := str(cfg.get("dir", "res://assets/maps/black_wind"))
	if map_art != null and map_art_dir == dir:
		return
	map_art_dir = dir
	map_art = MapArt.new()
	if not map_art.load_dir(dir, cfg.get("weights", {})):
		map_art = null


func start_run(p_starter: String = "chain_fist", p_qinggong: String = "tashue", p_map: String = "black_wind", p_diff: Dictionary = {}) -> void:
	map_id = p_map
	_load_map_art()
	set_difficulty(p_diff)
	starter_id = p_starter
	shi.clear()
	shi_bonus.clear()
	dugu_combo_log.clear()
	boss_deadline = -1.0
	timeout_fail = false
	hzones.clear()
	sword_break_count = 0
	qinggong_id = p_qinggong
	qg = Data.qinggong[qinggong_id]
	skills.clear()
	xinfa.clear()
	xinfa_q.clear()
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
	soul = 0.0
	soul_idle = 0.0
	tulong_on = false
	baodao = false
	baodao_ctx = false
	fist_qi = 0.0
	fist_qi_crit_t = 0.0
	cunjin_count = 0
	cut_count = 0
	fist_ult_t = 0.0
	fist_ult_count = 0
	tb_t = 0.0
	tb_cd = 0.0
	tb_count = 0
	ji_haste_until = -1.0
	rerolls_left = rerolls_for_level(meta_level)
	rerolls_used = 0
	dash_end_t = -99.0
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
	next_wave = Data.T("wave_first")
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
	var sch := str(Data.skills[id]["school"])
	var s: SkillBase = SwordSkills.create(id) if sch == "sword" else (BladeSkills.create(id) if sch == "blade" else FistSkills.create(id))
	s.setup(self, id, Data.skills[id])
	s.mods["range"] = float(s.mods["range"]) + float(talent_stats.get("skill_range", 0.0))      # 剑侠天赋：全部招式范围 / 闪现距离
	s.mods["debuff"] = float(s.mods["debuff"]) + float(talent_stats.get("skill_debuff", 0.0))  # 剑侠天赋：破绽 / 中毒 / 定身效果
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
		var per: Dictionary = def["per_level"]
		var pw := xinfa_power(id)
		for k in per:
			stats[k] = st(k) + float(per[k]) * pw
	# 角色等级成长：每升 1 级，基础伤害 / 气血 / 防御小幅提升（见 data 的 level_growth）
	for k in Data.level_growth:
		stats[k] = st(k) + float(Data.level_growth[k]) * (level - 1)
	var qs: Dictionary = qg.get("stats", {})
	for k in qs:
		stats[k] = st(k) + float(qs[k])
	for k in talent_stats:
		stats[k] = st(k) + float(talent_stats[k])
	var sp: Dictionary = Data.schools.get(school_id, {}).get("passive", {})       # 流派特色（剑侠：身法 / 武者：内力 / 刀客：气血）
	for k in sp:
		stats[k] = st(k) + float(sp[k])
	_apply_synergies()
	# 标签加成：心法每升 1 级，加成 ×(1 + 0.5 × (等级-1))
	tag_bonus.clear()
	for id in xinfa:
		var def2: Dictionary = Data.xinfa[id]
		var scale := xinfa_scale(id)
		var b: Dictionary = def2["bonus"]
		for tg in b:
			tag_bonus[tg] = float(tag_bonus.get(tg, 0.0)) + float(b[tg]) * scale
	_apply_xinfa_links()
	hp = minf(hp, st("max_hp"))
	neili = minf(neili, st("max_neili"))


## 心法强度：修习 = 1 份；每次强化再加（品质 + 1）份（普通 1 / 特别 2 / 优秀 3 / 传说 4）；装备词条每级 +1 份
func xinfa_power(id: String) -> float:
	if not xinfa.has(id):
		return 0.0
	var pw := 1.0 + float(gear_xinfa.get(id, 0))
	for q in xinfa_q.get(id, []):
		pw += float(int(q) + 1)
	return pw


## 标签加成 / 同修联动的强度倍率：1 份 = ×1.0，每多 1 份 +12%
func xinfa_scale(id: String) -> float:
	return 1.0 + 0.12 * (xinfa_power(id) - 1.0)


## 心法「同修」：学会的心法点名 3 个招式（可以跨流派、起手招式除外），每个招式有各自的加成 / 特殊效果；强度随心法的份数提高
func _apply_xinfa_links() -> void:
	var per_skill: Dictionary = {}       # 技能 id -> {mods: {}, flags: {}}
	for id in xinfa:
		var def: Dictionary = Data.xinfa[id]
		var sc := xinfa_scale(id)
		var lk_all: Dictionary = def.get("link", {})
		for sid in lk_all:
			if not skills.has(sid):
				continue
			if not per_skill.has(sid):
				per_skill[sid] = {"mods": {}, "flags": {}}
			var lk: Dictionary = lk_all[sid]
			for k in lk:
				var v := float(lk[k]) * sc
				if ["ying", "neili_hit", "vuln", "bleed"].has(k):
					per_skill[sid]["flags"][k] = float(per_skill[sid]["flags"].get(k, 0.0)) + v
				else:
					per_skill[sid]["mods"][k] = float(per_skill[sid]["mods"].get(k, 0.0)) + v
	for sid in skills:
		var sk: SkillBase = skills[sid]
		if per_skill.has(sid):
			sk.apply_link(per_skill[sid]["mods"], per_skill[sid]["flags"])
		else:
			sk.apply_link({}, {})


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


## 选心法卡片上的提示：这个心法点名的招式里，你现在已有 / 可以领悟到的
func _link_hint(id: String) -> String:
	var have: Array = []
	for sid in Data.xinfa[id].get("skills", []):
		if skills.has(sid):
			have.append(str(Data.skills[sid]["name"]))
	return "\n◆ 你已有的同修招式：%s" % "、".join(have) if not have.is_empty() else ""


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
	# 剑侠：移速越高攻速越快（speed_cd × 移速加成）
	var sc := st("speed_cd") * maxf(0.0, st("speed_pct"))
	var jc := 0.0
	if st("ji_sword") > 0.0:                      # 极·万剑归宗：冷却 −20%，冲刺 / 闪现后 3 秒再 −40%
		jc = 0.2 + (0.4 if time < ji_haste_until else 0.0)
	return maxf(0.3 if jc > 0.0 else 0.4, 1.0 - st("cd_reduce") - sc - jc - (Data.T("burst_yin_cd") if atk_buff_t > 0.0 else 0.0))


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
	if boss_deadline > 0.0 and time >= boss_deadline and not over:     # 大 Boss 限时：超时寨主逃遁，判负
		timeout_fail = true
		over = true
		won = false
		add_fx("text", player_pos + Vector2(0, -90), 2.0, {"text": "寨主逃遁了……", "size": 34, "color": VERMILION})
		player_died.emit()
		return
	shake = maxf(0.0, shake - 30.0 * dt)
	_update_player(dt)
	_spawn(dt)
	_update_props(dt)
	_rebuild_grid()
	_update_enemies(dt)
	for s: SkillBase in skills.values():
		s.tick(dt)
	_update_projectiles(dt)
	_update_zones(dt)
	_update_hzones(dt)
	_update_gems(dt)
	_update_pills(dt)
	_update_absorb(dt)
	_update_chests()
	_compact_enemies()
	_update_effects(dt)
	queue_redraw()


func _update_player(dt: float) -> void:
	invuln = maxf(0.0, invuln - dt)
	player_slow_t = maxf(0.0, player_slow_t - dt)
	if player_knock.length() > 8.0:
		player_pos += player_knock * dt
		player_knock *= maxf(0.0, 1.0 - 8.0 * dt)
	since_hit += dt
	stealth_t = maxf(0.0, stealth_t - dt)
	buff_t = maxf(0.0, buff_t - dt)
	if school_id == "fist":                        # 蓄劲：盈境下自然蓄劲
		if fist_ult_t > 0.0:                      # 拳掌无敌：无敌，内力清零且不恢复
			fist_ult_t = maxf(0.0, fist_ult_t - dt)
			if fist_ult_t > 0.0:
				invuln = maxf(invuln, 0.1)
				neili = 0.0
			elif st("ji_fist") > 0.0:                 # 极·天人合一：结束时回复 40% 内力
				neili = st("max_neili") * 0.4
		fist_qi_crit_t = maxf(0.0, fist_qi_crit_t - dt)
		if realm() == Realm.YING:
			fist_qi = minf(100.0, fist_qi + Data.T("fist_qi_ying") * dt * (1.0 + st("qi_gain") + (1.0 if st("ji_fist") > 0.0 else 0.0)))
	if school_id == "blade":
		_tick_true_blade(dt)
		soul_idle += dt
		if soul_idle > Data.T("blade_soul_delay"):
			soul = maxf(0.0, soul - Data.T("blade_soul_decay") * dt)

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
		var spd_pct := st("speed_pct") + (float(qg.get("buff_speed", 0.0)) if buff_t > 0.0 else 0.0) + (0.25 if st("ji_sword") > 0.0 and time < ji_haste_until else 0.0)
		player_pos += move * st("move_speed") * (1.0 + spd_pct) * (0.55 if player_slow_t > 0.0 else 1.0) * dt
	if map_art != null and map_art.has_blockers:        # 残墙 / 石柱挡人（含冲刺、击退）
		player_pos = map_art.push_out(player_pos, PLAYER_RADIUS)

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
	neili = clampf(neili + regen * dt, 0.0, max_n) if fist_ult_t <= 0.0 else 0.0     # 拳掌无敌期间不恢复内力
	var hr := (st("hp_regen") + (st("full_hp_regen") if neili >= max_n - 0.01 else 0.0)) * heal_mult()
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
	Sfx.play("dash_qg")
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
	dash_end_t = time
	if st("ji_sword") > 0.0:
		ji_haste_until = time + 3.0
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
	if school_id == "fist":                       # 武者：初始 2 次，局内每 10 级 +1 次
		n += 1 + int(level / 10) + (1 if st("ji_fist") > 0.0 else 0)
	if nature() == "harmony" and st("burst_harmony") > 0.0:
		n += 1
	return n


func burst_left() -> int:
	return maxi(0, burst_max() - burst_used)


## 所有「加内力」的来源都走这里（拳掌无敌期间一律无效）
func add_neili(n: float) -> void:
	if fist_ult_t > 0.0 or n <= 0.0:
		return
	neili = minf(st("max_neili"), neili + n)


func can_burst() -> bool:
	return fist_ult_t <= 0.0 and burst_left() > 0 and neili >= maxf(1.0, st("max_neili") * Data.T("burst_min_frac"))


## 真气爆发的威力系数（0~1）：当前内力占上限的比例
func burst_power() -> float:
	return clampf(neili / maxf(1.0, st("max_neili")), 0.0, 1.0)


## 真·独孤九剑：觉醒、或按「真气爆发」时触发「剑破天下」（九连闪现）
func _trigger_sword_break(delay: float, mult: float) -> void:
	var s: SkillBase = skills.get("dugu")
	if s != null and s.has_method("start_sword_break"):
		s.call("start_sword_break", delay, mult)


func _burst() -> void:
	for sk_b: SkillBase in skills.values():
		sk_b.on_burst()
	var f := burst_power()
	Sfx.play("burst_ult")
	burst_used += 1
	neili = 0.0                                   # 消耗全部内力
	if dugu_true():
		_trigger_sword_break(0.15, 0.7 + 0.8 * f)
		return
	play_anim("ult", 0.5)
	var radius := lerpf(Data.T("burst_radius_min"), Data.T("burst_radius_max"), f)
	var dmg := Data.T("burst_damage") * (0.4 + 4.6 * f)
	if school_id == "fist":                       # 武者：真气爆发 = 10 秒「拳掌无敌」
		fist_ult_t = Data.T("fist_ult_dur") + (5.0 if st("ji_fist") > 0.0 else 0.0)
		fist_ult_count += 1
		invuln = maxf(invuln, 0.3)
		for p in projs:
			if p.hostile and p.pos.distance_to(player_pos) < radius:
				p.life = 0.0
		add_fx("text", player_pos + Vector2(0, -90), 1.6, {"text": "拳掌无敌！", "size": 34, "color": Color("#5fe8d0")})
	else:
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
	if boss_spawned:
		rate = 0.0                          # 大 Boss 现身后不再刷小怪（只有 Boss 自己召唤的）
	elif _boss_alive():
		rate *= 0.5
	spawn_acc += rate * dt
	while spawn_acc >= 1.0:
		spawn_acc -= 1.0
		if enemies.size() < max_enemies:
			_spawn_enemy(_pick_type(), _ring_pos())
	# 合围：定时在四周刷出一圈敌人
	if time >= next_burst and not boss_spawned:
		next_burst += Data.T("burst_interval")
		var ring_n := int(round(24.0 * float(difficulty["count"])))
		for i in ring_n:
			if enemies.size() < max_enemies:
				_spawn_enemy("bandit", player_pos + Vector2.from_angle(TAU * i / float(ring_n)) * SPAWN_DIST)
	if time >= next_elite and not boss_spawned:
		next_elite += Data.T("elite_interval")
		for i in 1 + int(time / 420.0):          # 越到后面精英越多：每 7 分钟多一只
			_spawn_elite()
	if time >= next_wave and not boss_spawned:                       # 怪潮：从一个方向压过来的一大群
		next_wave += Data.T("wave_interval")
		_spawn_wave()
	var tl := _timeline()
	var minis: Array = tl["minis"]
	if mini_idx < minis.size() and time >= float(minis[mini_idx]["t"]) and not boss_spawned:
		_spawn_boss(str(minis[mini_idx]["id"]), false)
		mini_idx += 1
	var fin: Dictionary = tl["final"]
	if not boss_spawned and time >= float(fin["t"]):
		boss_spawned = true
		_clear_for_final()
		_spawn_boss(str(fin["id"]), true)


## 当前地图的时间轴（小 Boss 时间 / 大 Boss 现身时间与限时 / 血量倍数）
func _timeline() -> Dictionary:
	return Data.maps[map_id]["timeline"]


## 大 Boss 现身：场上所有还没击杀的小 Boss 和小怪立刻消失（不掉经验 / 装备）；没击杀的小 Boss 也不计入击杀
func _clear_for_final() -> void:
	for e in enemies:
		if e.alive and not e.is_prop:
			e.alive = false
	var keep: Array[Enemy] = []
	for b in bosses:
		if not b.alive and b.hp <= 0.0:
			keep.append(b)          # 已击杀的小 Boss 保留（统计用）
	bosses = keep
	projs = projs.filter(func(p): return not p.hostile)
	zones.clear()
	hzones.clear()
	add_fx("text", player_pos + Vector2(0, -130), 2.2, {"text": "大敌当前，杂兵尽退！", "size": 30, "color": VERMILION})


func _boss_alive() -> bool:
	for b in bosses:
		if b.alive:
			return true
	return false


func _ring_pos() -> Vector2:
	return player_pos + Vector2.from_angle(rng.randf() * TAU) * (SPAWN_DIST + rng.randf() * 60.0)


func _pick_type() -> String:
	var tbl: Array = Data.maps[map_id].get("spawn_table", [])
	if not tbl.is_empty():                                # 按门派时间表刷怪：当前阶段的权重 1，已过的阶段留一点（0.3）
		var tot := 0.0
		var ws: Array[float] = []
		for row in tbl:
			var wt := 0.0
			if time >= float(row["t0"]):
				wt = 1.0 if time < float(row["t1"]) else 0.25
			ws.append(wt)
			tot += wt
		var rr := rng.randf() * tot
		for i in tbl.size():
			rr -= ws[i]
			if rr < 0.0:
				return str(tbl[i]["id"])
		return str(tbl[0]["id"])
	var w_blade := clampf((time - 30.0) / 180.0, 0.0, 0.8)
	var w_soldier := clampf((time - 90.0) / 240.0, 0.0, 0.7)
	var w_archer := clampf((time - 140.0) / 220.0, 0.0, 0.45)      # 弓手：保持距离放冷箭（有红线预警）
	var w_charger := clampf((time - 220.0) / 260.0, 0.0, 0.35)     # 蛮兵：预警后直线冲锋
	var r := rng.randf() * (1.0 + w_blade + w_soldier + w_archer + w_charger)
	if r < 1.0:
		return "bandit"
	r -= 1.0
	if r < w_blade:
		return "blade"
	r -= w_blade
	if r < w_soldier:
		return "soldier"
	r -= w_soldier
	if r < w_archer:
		return "archer"
	return "charger"


func _spawn_enemy(type: String, at: Vector2) -> Enemy:
	var def: Dictionary = Data.enemies[type]
	var e := Enemy.new()
	e.uid = next_uid
	next_uid += 1
	e.born = time
	e.type_id = type
	e.pos = at
	e.max_hp = float(def["hp"]) * (1.0 + time / Data.T("hp_scale_t")) * float(difficulty["hp"]) * Data.T("enemy_hp_mult")
	e.hp = e.max_hp
	e.speed = float(def["speed"]) * (1.0 + minf(time / 900.0, 0.3)) * rng.randf_range(0.9, 1.1) * float(difficulty["speed"]) * Data.T("enemy_speed_mult")
	e.damage = float(def["damage"]) * (1.0 + time / Data.T("dmg_scale_t"))
	e.radius = float(def["radius"])
	e.exp_value = int(def["exp"])
	e.color = Color(str(def["color"]))
	e.behavior = str(def.get("behavior", ""))
	e.mskill = str(def.get("mskill", ""))
	e.skill_gap = rng.randf_range(0.5, 2.0)
	e.touch_slow = float(def.get("touch_slow", 0.0))
	e.defense = float(def.get("defense", 0.0))
	e.art_key = str(def.get("art", ""))
	if def.has("tint"):
		e.tint = Color(str(def["tint"]))
	if bool(def.get("prop", false)):      # 场景物件：固定血量，不随时间 / 难度变强，不动
		e.is_prop = true
		e.max_hp = float(def["hp"])
		e.hp = e.max_hp
		e.speed = 0.0
		e.damage = 0.0
	enemies.append(e)
	return e


## 怪潮：从随机一个方向压过来的一大群（数量随难度 / 时间增加），提前飘字预警
func _spawn_wave() -> void:
	if _boss_alive():
		return
	var a := rng.randf() * TAU
	var n := int(round(Data.T("wave_size") * float(difficulty["count"]) * (1.0 + time / 480.0)))
	for i in n:
		if enemies.size() >= max_enemies:
			break
		var dir := Vector2.from_angle(a + rng.randf_range(-0.55, 0.55))
		var e := _spawn_enemy(_pick_type(), player_pos + dir * (SPAWN_DIST + rng.randf() * 140.0))
		e.speed *= 1.15
	add_fx("text", player_pos + Vector2.from_angle(a) * 230.0, 2.0, {"text": "怪潮来袭！", "size": 34, "color": VERMILION})
	Sfx.play("boss_warn")


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
	var hpm: Dictionary = _timeline().get("hp_mult", {})
	e.max_hp = float(def["hp"]) * float(hpm.get("final" if final else "mini", 1.0)) * float(difficulty["hp"]) * Data.T("enemy_hp_mult")   # Boss 不随时间缩放血量，保持固定的战斗时长（难度倍率照样生效）
	e.hp = e.max_hp
	e.speed = float(def["speed"]) * float(difficulty["speed"]) * Data.T("enemy_speed_mult")
	e.damage = float(def["damage"])
	e.boss_bolts = int(def["bolts"])
	e.skills = (def.get("skills", []) as Array).duplicate()
	e.skills2 = (def.get("skills2", []) as Array).duplicate()
	e.phase_hp = float(def.get("phase_hp", 0.0))
	e.phase2_def = (def.get("phase2", {}) as Dictionary).duplicate()
	e.skill_gap = 2.0
	e.guard_max = e.max_hp * Data.T("boss_guard_pct")
	e.guard = e.guard_max
	bosses.append(e)
	if final:
		boss_deadline = time + float((_timeline()["final"] as Dictionary)["limit"])
	Sfx.play("boss_warn")
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
		if not e.alive or e.is_prop:
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
		if not e.alive or e.is_prop:
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
		if e.alive and not e.is_prop and e.pos.distance_to(center) < r + e.radius:
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
		if e.is_prop:
			continue
		e.slow_t = maxf(0.0, e.slow_t - dt)
		e.weak_fx = maxf(0.0, e.weak_fx - dt)
		e.vuln_t = maxf(0.0, e.vuln_t - dt)
		e.atk_down_t = maxf(0.0, e.atk_down_t - dt)
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
		if e.bleed_t > 0.0:                            # 撕裂（刀客）：每 0.5 秒结算一次流血
			e.bleed_t -= dt
			e.bleed_acc += dt
			if e.bleed_acc >= 0.5:
				var bdm := e.bleed_dps * e.bleed_acc
				e.bleed_acc = 0.0
				e.hp -= bdm
				e.flash = 0.05
				skill_dmg["bleed"] = float(skill_dmg.get("bleed", 0.0)) + bdm
				if effects.size() < MAX_EFFECTS / 2:
					add_fx("text", e.pos + Vector2(rng.randf_range(-8, 8), -e.radius), 0.7, {"text": str(int(bdm)), "size": 17, "color": Color("#d84a3a")})
				if e.hp <= 0.0:
					_kill(e)
					continue
			if e.bleed_t <= 0.0:
				e.bleed_dps = 0.0
				e.bleed_stacks = 0
		if e.burn_t > 0.0:
			e.burn_t -= dt
		if e.is_boss and not e.phase2 and not e.phase2_def.is_empty() and e.hp <= e.max_hp * float(e.phase2_def["hp"]):
			BossAI.enter_phase2(self, e)
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
		var staggered := e.stagger_t > 0.0 and not e.is_boss
		if e.stagger_t > 0.0:
			e.stagger_t -= dt
		if e.stun > 0.0:
			e.stun -= dt
		elif e.is_boss:
			vel = _boss_ai(e, dt, dir)
		elif e.behavior != "":
			vel = BossAI.minion(self, e, dt, dir, d) * (e.slow_mult if e.slow_t > 0.0 else 1.0)
			vel += _separation(e) * 60.0
		else:
			var spd := e.speed * (e.slow_mult if e.slow_t > 0.0 else 1.0)
			if stealth_t > 0.0:
				# 轻功隐匿：敌人只会慢慢走向玩家消失的位置
				var tp := stealth_pos - e.pos
				vel = tp.normalized() * spd * 0.35 if tp.length() > 8.0 else Vector2.ZERO
			else:
				vel = dir * spd
			vel += _separation(e) * 90.0
		if staggered:                               # 受击硬直：这一瞬间站住不动（击退照常）
			vel = Vector2.ZERO
		e.pos += (vel + e.knock) * dt
		if map_art != null and map_art.has_blockers and d < 900.0:
			e.pos = map_art.push_out(e.pos, e.radius * 0.8)
		e.knock *= maxf(0.0, 1.0 - 7.0 * dt)
		if e.stun <= 0.0 and d < e.radius + PLAYER_RADIUS and invuln <= 0.0:
			_hurt(e.damage * e.atk_mul())
			if e.touch_slow > 0.0:
				player_slow_t = maxf(player_slow_t, e.touch_slow)
				add_fx("ring", player_pos, 0.35, {"r0": 6.0, "r1": 20.0, "color": Color("#9ad8ff"), "vfx": "fx_minion_frost", "size": 64.0})


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
	return BossAI.think(self, e, dt, dir)


func _boss_radial(e: Enemy, n: int) -> void:
	Sfx.play("enemy_ranged")
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
		p.damage = 14.0 * e.atk_mul()
		p.cuttable = true          # 杂兵的弓箭 / 剑气：独孤九剑可以斩落
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
		Sfx.play("block_shield")
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
	if school_id == "blade":                       # 刀客：挨打更凶，每损失 1% 气血涨刀魂（单次有上限）
		add_soul(minf(Data.T("blade_soul_hp_cap"), Data.T("blade_soul_hp") * dmg / maxf(1.0, st("max_hp")) * 100.0))
	hp -= dmg
	shake = 8.0
	Sfx.play("player_hurt")
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
	if e.hp > 0.0 and not e.is_boss and not e.is_elite and not e.is_prop and time - e.stagger_last >= Data.T("stagger_gap"):
		e.stagger_t = Data.T("stagger_crit") if crit else Data.T("stagger_hit")      # 普通敌人受击硬直：0.05 秒（暴击 0.1 秒），0.25 秒内不重复触发
		e.stagger_last = time
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
	Sfx.play("enemy_death")
	e.alive = false
	if e.is_prop:
		_break_prop(e)
		return
	kills += 1
	add_neili(st("kill_neili"))
	if st("kill_hp") > 0.0:
		hp = minf(st("max_hp"), hp + st("kill_hp") * heal_mult())
	_drop_gem(e.pos, e.exp_value)
	if not e.is_boss and not e.is_elite:
		_maybe_drop_absorb(e.pos)
	if vfx.has("death_puff") and effects.size() < MAX_EFFECTS:
		add_fx("splat", e.pos, 0.35, {"r": e.radius * 1.4, "color": e.color, "vfx": "death_puff", "size": e.radius * 4.0})
	else:
		add_fx("splat", e.pos, 0.6, {"r": e.radius * 1.4, "color": e.color})
	if e.burn_burst > 0.0 and e.burn_t > 0.0:        # 燃木刀法强化：灼烧中的敌人死亡时火焰爆炸
		area_hit_raw(e.pos, e.burn_burst, e.burn_dmg, ["范围"], "ranmu_blade", 140.0)
		add_fx("ring", e.pos, 0.35, {"r0": 10.0, "r1": e.burn_burst, "color": Color("#ff8a30")})
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
		boss_deadline = -1.0
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
	var bd := baodao or baodao_ctx
	if school_id == "blade":
		m *= blade_dmg()
		var lh := st("lowhp_dmg")
		if lh > 0.0:
			m *= 1.0 + lh * floorf((1.0 - hp / maxf(1.0, st("max_hp"))) * 10.0)
		if time - dash_end_t < 2.0 and st("dash_dmg") > 0.0:
			m *= 1.0 + st("dash_dmg")
		if (e.shield > 0.0 or e.defense > 0.0) and st("armor_dmg") > 0.0:
			m *= 1.0 + st("armor_dmg")
		if bd:
			m *= Data.T("blade_break_mult")
	if sk != null:
		m *= sk.hit_mult(e)
		if realm() == Realm.YING and float(sk.link_flags.get("ying", 0.0)) > 0.0:     # 九阳神功同修：盈境下额外增伤
			m *= 1.0 + float(sk.link_flags["ying"])
	if e.vuln_t > 0.0:
		m *= 1.0 + e.vuln
	if sid == "dugu":
		var qi := shi_lv("po_qi")
		if qi > 0:
			if e.is_boss:
				m *= 1.0 + 0.1 * qi
			add_neili(0.3 * qi)
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
		Sfx.play("vuln_break")
		add_fx("text", e.pos + Vector2(0, -e.radius - 14), 0.85, {"text": "破绽", "size": 22, "color": JADE})
	var crit := force_crit or bd or (sk != null and sk.hit_crit(e)) or rng.randf() < crit_p
	if crit:
		m *= st("crit_mult")
	var emp := (_emp_ctx == 1) if _emp_ctx >= 0 else (sk != null and sk.empowered)
	if emp:
		m *= maxf(0.2, 1.0 + st("emp_power"))
	if crit and st("crit_neili") > 0.0:
		add_neili(st("crit_neili"))
	var amount := base * m
	if fist_ult_t > 0.0 and school_id == "fist" and sk != null:          # 拳掌无敌：额外造成伤害量 30% 的真伤（无视防御 / 罡气 / 护盾）
		var tdmg := amount * Data.T("fist_ult_true")
		e.hp -= tdmg
		add_fx("text", e.pos + Vector2(rng.randf_range(-10, 10), -e.radius - 12), 0.7, {"text": str(int(tdmg)), "size": 17, "color": Color("#5fe8d0")})
		if e.hp <= 0.0 and e.alive:
			_kill(e)
			return amount
	var hs := st("hit_slow")
	if sk != null and float(sk.mods["debuff"]) > 0.0:
		hs = maxf(hs, float(sk.mods["debuff"]))
	if hs > 0.0:
		slow_enemy(e, 1.0 - minf(0.6, hs), 1.5)
	if sk != null and float(sk.mods["heal"]) > 0.0:
		hp = minf(st("max_hp"), hp + minf(0.6 * heal_mult(), amount * float(sk.mods["heal"]) * heal_mult()))       # 吸血要克制：每次命中最多回 0.6
	skill_dmg[sid] = float(skill_dmg.get(sid, 0.0)) + amount
	if sid == "dugu" and sk is SwordSkills.Dugu:
		(sk as SwordSkills.Dugu).note_hit(e)
	if crit and school_id == "fist" and sk != null and not sk.free_cast and fist_qi_crit_t <= 0.0:       # 暴击多攒一点（每 0.3 秒最多一次）
		fist_qi = minf(100.0, fist_qi + Data.T("fist_qi_crit") - Data.T("fist_qi_cast"))
		fist_qi_crit_t = 0.3
	if school_id == "blade" and sk != null and not sk.free_cast:
		add_soul(Data.T("blade_soul_crit") if crit else Data.T("blade_soul_hit"))
	if sk != null and not sk.link_flags.is_empty():              # 心法同修的特殊效果
		var lfl: Dictionary = sk.link_flags
		if float(lfl.get("neili_hit", 0.0)) > 0.0:
			add_neili(float(lfl["neili_hit"]))
		if float(lfl.get("vuln", 0.0)) > 0.0 and not e.is_prop:
			apply_vuln(e, float(lfl["vuln"]))
		if float(lfl.get("bleed", 0.0)) > 0.0 and not e.is_prop:
			var bv := float(lfl["bleed"])
			var bn := int(bv) + (1 if rng.randf() < bv - floorf(bv) else 0)
			if bn > 0:
				apply_bleed(e, bn, amount)
	if bd:
		apply_bleed(e, int(Data.T("blade_break_stacks")), amount)
	if e.defense > 0.0:
		var dfn := e.defense
		if e.bleed_stacks > 0:                          # 撕裂：每层降低目标防御
			dfn = maxf(0.0, dfn - Data.T("bleed_armor") * e.bleed_stacks * (1.0 + st("bleed_pow")))
		amount *= 1.0 - dfn * (1.0 - clampf(st("armor_pierce") + (0.5 if tulong_on else 0.0), 0.0, 1.0))
	if e.is_boss:
		amount = _boss_guard(e, amount, emp)
		if e.shield > 0.0:                               # 护盾：先吃伤害；Boss 破防（虚弱）时以双倍伤害打掉
			var shm := (Data.T("blade_break_shield") if bd else 1.0) * (sk.shield_mult() if sk != null else 1.0) * (2.0 if tulong_on else 1.0)
			var sd := amount * shm * (2.0 if e.weak_t > 0.0 else 1.0)
			if sd < e.shield:
				e.shield -= sd
				e.flash = 0.08
				add_fx("text", e.pos + Vector2(rng.randf_range(-8, 8), -e.radius), 0.6, {"text": str(int(sd)), "size": 17, "color": Color("#9ae8ff")})
				return amount
			amount = (sd - e.shield) / (shm * (2.0 if e.weak_t > 0.0 else 1.0))
			e.shield = 0.0
			add_fx("text", e.pos + Vector2(0, -e.radius - 30), 1.2, {"text": "护盾破碎！", "size": 28, "color": Color("#9ae8ff")})
			if tulong_on:                                  # 屠龙宝刀破盾：兵刃震脱，3 秒易伤
				e.vuln = maxf(e.vuln if e.vuln_t > 0.0 else 0.0, 0.35)
				e.vuln_t = 3.0
				add_fx("ring", e.pos, 0.5, {"r0": 20.0, "r1": 200.0, "color": Color("#ffb030"), "vfx": "fx_tulong_break", "size": 340.0})
				add_fx("text", e.pos + Vector2(0, -e.radius - 62), 1.6, {"text": "兵刃震脱！", "size": 26, "color": Color("#ffb030")})
			add_fx("ring", e.pos, 0.5, {"r0": 20.0, "r1": 140.0, "color": Color("#9ae8ff"), "vfx": "boss_shield_break" if vfx.has("boss_shield_break") else "burst_break", "size": maxf(e.radius * 4.0, 150.0)})
			shake = maxf(shake, 7.0)
	damage_enemy(e, amount, knock_vec, crit)
	Sfx.play("hit_crit" if crit else ("hit_blade" if school_id == "blade" else ("hit_sword" if school_id == "sword" else "hit_fist")))
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
		Sfx.play("armor_break")
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
	pr.vfx_id = s.fxid("proj")
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
	pr.baodao = baodao
	pr.bleed = float(o.get("bleed", 0.0))
	pr.slowv = float(o.get("slowv", 0.0))
	projs.append(pr)
	return pr


func add_zone(z: Dictionary) -> void:
	if not z.has("pos"):
		z["pos"] = player_pos
	if z.has("skill") and not z.has("emp"):
		z["emp"] = (z["skill"] as SkillBase).empowered
	z["bd"] = baodao
	if not z.has("t"):
		z["t"] = 0.0
	zones.append(z)


func fx_slash(at: Vector2, angle: float, reach: float, arc: float, heavy: bool, vid: String = "") -> void:
	add_fx("slash", at, 0.2, {"angle": angle, "r": reach, "arc": arc, "heavy": heavy, "vfx": vid if vid != "" else ("slash_heavy" if heavy else "slash_fist")})


# =====================================================================
# 弹体 / 区域
# =====================================================================

## 破鞭式弹射：整个画面（不是整张地图）里离 pos 最近的敌人
func _nearest_on_screen(pos: Vector2, exclude: Dictionary) -> Enemy:
	var best: Enemy = null
	var bd := INF
	for e in enemies:
		if not e.alive or e.is_prop or exclude.has(e.uid) or not _vis(e.pos, 0.0):
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
		if not e.alive or e.is_prop or exclude.has(e.uid):
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
		if not p.hostile and p.skill_id == "dugu" and dugu_can_cut():
			cut_hostile_projs(p.pos, p.radius + Data.T("dugu_cut_base") + Data.T("dugu_cut_lv") * float(shi.get("po_arrow", 0)))
		var keep := p.life > 0.0
		if keep and map_art != null and map_art.has_blockers and map_art.blocked(p.pos, p.radius * 0.5):
			keep = false                                # 弹体撞上残墙 / 石柱消失
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
						baodao_ctx = p.baodao
						hit_enemy(e, p.damage, p.tags, p.vel.normalized() * p.knock, p.skill_id)
						baodao_ctx = false
						_emp_ctx = -1
						if p.bleed > 0.0:
							apply_bleed(e, int(p.bleed), p.damage)
						if p.slowv > 0.0:
							slow_enemy(e, 1.0 - p.slowv, 1.5)
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
		baodao_ctx = bool(z.get("bd", false))
		match str(z["kind"]):
			"impact":
				if z["t"] >= z["delay"]:
					var s: SkillBase = z["skill"]
					area_hit(s, zpos, zr, z["dmg"], 250.0, z["stun"])
					add_fx("ring", zpos, 0.3, {"r0": 10.0, "r1": zr, "color": VERMILION, "vfx": s.fxid("impact") if s.fxid("impact") != "" else "burst_quake"})
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
			"fire":                                        # 燃木刀法的火海：持续灼烧 + 减速
				if z["t"] >= z["life"]:
					keep = false
				else:
					z["tick"] = float(z["tick"]) - dt
					if z["tick"] <= 0.0:
						z["tick"] = 0.5
						var s3: SkillBase = z["skill"]
						area_hit(s3, zpos, zr, z["dmg"])
						for e in _query(zpos, zr):
							if e.alive and e.pos.distance_to(zpos) < zr + e.radius:
								slow_enemy(e, 0.8, 0.7)
								e.burn_t = 0.8
								if bool(z.get("burst", false)):
									e.burn_burst = float(z["burst_r"])
									e.burn_dmg = float(z["burst_dmg"])
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
			Sfx.play_exp()
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
		Sfx.play("level_up")
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
## 另觅机缘：局外等级每满 5 级，局内多 3 次重抽升级卡
static func rerolls_for_level(lv: int) -> int:
	return int(lv / 5) * 3


func can_reroll() -> bool:
	return rerolls_left > 0


## 消耗一次「另觅机缘」，重新抽 3 张升级卡（尽量避开刚才展示的）；不消耗升级机会
func use_reroll(prev: Array) -> Array:
	if rerolls_left <= 0:
		return prev
	rerolls_left -= 1
	rerolls_used += 1
	var avoid: Array = []
	for c: Dictionary in prev:
		avoid.append(_choice_key(c))
	return roll_choices(3, avoid)


func _choice_key(c: Dictionary) -> String:
	return "%s|%s|%s|%s" % [c.get("kind", ""), c.get("id", ""), c.get("dir", ""), c.get("tier", "")]


func roll_choices(n: int = 3, avoid: Array = []) -> Array:
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
		if dugu_route or skills.has(id) or str(def["school"]) != school_id or Data.is_starter(id):      # 起手招式（含独孤九剑）只能在出发前选，升级时不会出现
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
				var xt := Data.roll_tier(rng, st("luck"))
				pool.append({
					"kind": "up_xinfa", "id": id, "tier": xt, "src": "level",
					"tag": str(Data.tiers[xt]["name"]), "color": str(Data.tiers[xt]["color"]),
					"title": "%s · 强化（Lv%d→%d）" % [def2["name"], xinfa[id], xinfa[id] + 1],
					"desc": "同修招式与被动属性 +%d 份强度（累计 %.0f → %.0f 份）　（已强化 %d/%d）" % [
						xt + 1, xinfa_power(id), xinfa_power(id) + xt + 1, int(xinfa[id]) - 1, int(def2["max_level"]) - 1],
				})
		elif xinfa.size() < MAX_XINFA:
			pool.append({
				"kind": "new_xinfa", "id": id, "tag": "心法", "src": "level",
				"title": "修习：%s【%s】" % [def2["name"], "阳" if str(def2.get("yy", "")) == "yang" else "阴"],
				"desc": str(def2["desc"]) + _link_hint(id) + _synergy_hint(id),
			})
	_shuffle(pool)
	if not avoid.is_empty() and pool.size() > n:      # 重抽：刚展示过的卡放到最后面（抽不到别的时才会再出现）
		var seen: Array = []
		var fresh: Array = []
		for c: Dictionary in pool:
			(seen if avoid.has(_choice_key(c)) else fresh).append(c)
		pool = seen + fresh
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
			shi_bonus[id] = float(shi_bonus.get(id, 0.0)) + float(c.get("bonus", 0.0))
		"new_xinfa":
			xinfa[id] = 1
			xinfa_q[id] = []
		"up_xinfa":
			xinfa[id] = int(xinfa[id]) + 1
			var qa: Array = xinfa_q.get(id, [])
			qa.append(int(c.get("tier", 0)))
			xinfa_q[id] = qa
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
	_draw_hzones()
	for i in gem_pos.size():
		var g := gem_pos[i]
		if _vis(g):
			_draw_gem(g, gem_val[i], gem_age[i])
	for pl in pills:
		if _vis(pl["pos"]):
			_draw_pill(pl)
	for it in absorb_items:
		if _vis(it["pos"], 80.0):
			_draw_absorb(it)
	for c in chests:
		if _vis(c) and pickup_art.has("chest"):
			var bob2 := sin(time * 4.0) * 3.0
			draw_circle(c + Vector2(0, 14), 16.0, Color(0, 0, 0, 0.18))
			draw_circle(c + Vector2(0, bob2), 30.0, Color(GOLD, 0.12 + 0.08 * sin(time * 5.0)))
			_draw_pickup("chest", c + Vector2(0, bob2), 44.0)
		elif _vis(c):
			var bob := sin(time * 4.0) * 3.0
			draw_rect(Rect2(c + Vector2(-11, -8 + bob), Vector2(22, 16)), Color("#8a5a1f"))
			draw_rect(Rect2(c + Vector2(-11, -8 + bob), Vector2(22, 16)), GOLD, false, 2.0)
			draw_arc(c + Vector2(0, bob), 20.0, 0.0, TAU, 20, Color(GOLD, 0.4 + 0.3 * sin(time * 5.0)), 2.0)
	for e in enemies:
		if e.cast_id != "" and e.alive and _vis(e.pos, 300.0):
			BossAI.draw_telegraph(self, e)
	# 角色、怪物、场景物件按「脚底的 y」从上到下排序再画：靠下的盖住靠上的，前后关系才对
	var ents: Array = []
	var uniq := 0.0
	for e in enemies:
		if _vis(e.pos, 60.0):
			var key := _enemy_art_key(e)
			var fy := e.pos.y + (enemy_art.height_of(key) * 0.42 if enemy_art != null and enemy_art.has(key) else e.radius)
			uniq += 1e-6
			ents.append([fy + uniq, 0, e])         # 加一点点序号让第一项互不相同：用原生排序，比 sort_custom 快得多
	_lite = ents.size() > LITE_ENEMIES
	if map_art != null:
		for pr in map_art.visible_props(player_pos, Vector2(700.0, 420.0)):
			uniq += 1e-6
			ents.append([(pr["pos"] as Vector2).y + uniq, 1, pr])
	ents.append([player_pos.y + 14.0 + 0.5, 2, null])
	ents.sort()
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
	if pickup_art.has("absorb"):
		draw_circle(c, 30.0 + 3.0 * sin(t * 1.3), Color("#b98cff", 0.14))
		_draw_pickup("absorb", c, 44.0, time * 1.5)
		return
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
	if pickup_art.has("gourd"):
		if big:
			draw_circle(c, 18.0, Color(GOLD, 0.2 + 0.1 * sin(time * 6.0)))
		_draw_pickup("gourd", c, 34.0 if big else 24.0)
		return
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
				pass       # 玩家自己的招式不画预警圈（红色预警只属于敌人，避免混淆）；落地时才有特效
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
			"fire":
				if vfx.has("fx_blade_fire"):
					continue
				var a3 := 1.0 - float(z["t"]) / float(z["life"])
				draw_circle(zpos, zr, Color(1.0, 0.45, 0.1, 0.12 * a3 + 0.04))
				draw_arc(zpos, zr, 0.0, TAU, 32, Color(1.0, 0.6, 0.2, 0.6 * a3), 2.0)
			"vortex":
				if vfx.has("zone_vortex"):
					continue
				var a2 := 1.0 - float(z["t"]) / float(z["life"])
				for k in 3:
					var rot := float(z["t"]) * 6.0 + k * 2.1
					draw_arc(zpos, zr * (0.35 + 0.2 * k), rot, rot + 2.0, 16, Color(INK, 0.4 * a2), 3.0)


## 弓手：行走用第 1~2 帧，预警 / 放箭时用拉弓的第 3~4 帧
func _fr0(e: Enemy, key: String) -> int:
	return 2 if (key == "archer" and e.cast_id != "") else 0


func _fr1(e: Enemy, key: String) -> int:
	if key == "archer":
		return 3 if e.cast_id != "" else 1
	return -1


func _enemy_art_key(e: Enemy) -> String:
	if e.art_key != "":
		return e.art_key           # 复用别的怪的素材（弓手 / 蛮兵）
	if e.is_final:
		return "boss"
	if e.is_boss:
		return e.type_id        # 小 Boss：有对应素材才用（mini_boss_1 ...）
	if e.is_elite:
		return "elite"
	return e.type_id


func _draw_enemy(e: Enemy) -> void:
	if e.is_prop:
		_draw_prop(e)
		return
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
	if _lite and not e.is_boss and not e.is_elite:      # 同屏很多怪：快速画法（影子贴图 + 翻转好的图集，一次绘制）
		var tf := e.tint
		if e.flash > 0.0:
			tf = Color(1.6, 1.3, 1.3)
		elif e.slow_t > 0.0:
			tf = Color(0.72, 0.88, 1.0)
		elif e.stun > 0.0:
			tf = Color(0.85, 0.85, 0.85)
		var rw := h * 0.46
		draw_texture_rect(_sh_tex, Rect2(feet.x - rw, feet.y - 1.0 - rw * 0.3, rw * 2.0, rw * 0.6), false)
		enemy_art.draw_fast(self, key, time + float(e.uid % 11) * 0.13, feet, flip, tf, _fr0(e, key), _fr1(e, key))
		return
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
	var tint := e.tint
	if e.flash > 0.0:
		tint = Color(1.6, 1.3, 1.3)
	elif e.slow_t > 0.0:
		tint = Color(0.72, 0.88, 1.0)
	elif e.stun > 0.0:
		tint = Color(0.85, 0.85, 0.85)
	enemy_art.draw(self, key, time + ph * 0.13, feet - Vector2(0, bob), flip, tint, lean, sq, _fr0(e, key), _fr1(e, key))
	var r := e.radius
	if e.is_elite:
		draw_arc(e.pos + Vector2(0, h * 0.1), h * 0.5, 0.0, TAU, 26, Color(GOLD, 0.8), 2.0)
	if e.is_boss:
		if e.weak_t > 0.0:
			draw_arc(e.pos, r + 8.0, 0.0, TAU, 32, Color(GOLD, 0.5 + 0.5 * sin(time * 16.0)), 4.0)
		elif e.guard > 0.0:
			draw_arc(e.pos, r + 8.0, 0.0, TAU * e.guard / maxf(1.0, e.guard_max), 32, Color("#4fe0d0", 0.85), 4.0)
	if e.shield > 0.0:                                 # 护盾光罩
		if vfx.has("boss_shield"):
			vfx.draw(self, "boss_shield", vfx.frame_loop("boss_shield", time), e.pos + Vector2(0, -h * 0.1), h * 1.5, 0.0, Color(1, 1, 1, 0.8))
		else:
			draw_circle(e.pos + Vector2(0, -h * 0.1), h * 0.62, Color("#9ae8ff", 0.14))
			draw_arc(e.pos + Vector2(0, -h * 0.1), h * 0.62, 0.0, TAU, 36, Color("#bfe8ff", 0.7 + 0.2 * sin(time * 8.0)), 3.0)
	if e.phase2:                                       # 二阶段气场
		if vfx.has("boss_aura_phase2"):
			vfx.draw(self, "boss_aura_phase2", vfx.frame_loop("boss_aura_phase2", time), e.pos + Vector2(0, h * 0.25), h * 1.3, 0.0, Color(1, 1, 1, 0.7))
		else:
			for kk in 3:
				var aa := time * 2.5 + kk * 2.09
				draw_arc(e.pos, h * 0.55, aa, aa + 1.2, 12, Color("#bfe8ff", 0.8), 3.0)
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
		if vfx.has(str(VfxLayer.HOSTILE_IDS.get(p.kind, ""))):
			return      # 有特效素材：由 VfxLayer 绘制
		match p.kind:
			"claw":        # 白骨爪气：幽蓝三道爪痕
				for k in 3:
					var o := dir.orthogonal() * (float(k) - 1.0) * 5.0
					draw_line(p.pos + o - dir * 22.0, p.pos + o + dir * 6.0, Color("#6ab8ff", 0.9), 3.0)
			"palm":        # 铁砂掌印：暗红
				draw_circle(p.pos, p.radius, Color("#7a1f2a", 0.9))
				draw_arc(p.pos, p.radius, 0.0, TAU, 14, Color("#ff6a4a"), 2.5)
				draw_line(p.pos - dir * 16.0, p.pos, Color("#7a1f2a", 0.5), 6.0)
			"blade":       # 旋转刀气：猩红月牙
				var ra := time * 14.0
				draw_arc(p.pos, p.radius + 3.0, ra, ra + 2.6, 10, Color("#ff5a2a"), 5.0)
				draw_arc(p.pos, p.radius - 2.0, ra + 0.4, ra + 2.2, 8, Color("#ffd08a"), 2.0)
			"arrow":
				draw_line(p.pos - dir * 20.0, p.pos, Color("#c9a56a"), 2.5)
				draw_circle(p.pos + dir * 2.0, 3.0, Color("#e8d8b0"))
			_:
				draw_circle(p.pos, p.radius, Color(VERMILION, 0.85))
				draw_arc(p.pos, p.radius, 0.0, TAU, 12, Color(0.1, 0.0, 0.0, 0.8), 2.0)
		return
	if p.vfx_id != "" or vfx.has(str(VfxLayer.PROJ_IDS.get(p.kind, ""))):
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
		"rerolls": rerolls_used, "cunjin": cunjin_count, "true_blade": tb_count, "fist_ult": fist_ult_count, "build": build, "version": str(ProjectSettings.get_setting("application/config/version", "0")),
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
	var blink := invuln > 0.0 and fist_ult_t <= 0.0 and dash_t <= 0.0 and int(time * 24.0) % 2 == 0
	if blink:
		return
	var alpha := 0.45 if stealth_t > 0.0 else 1.0
	var has_sprite := sprite_anim != null
	if has_sprite:
		# 脚下的接触影子（角色脚底在 player_pos 下方 14px）；走路起伏时影子随之变小
		Depth.shadow(self, player_pos + Vector2(0, 14), 30.0, _player_bob())
	else:
		draw_circle(player_pos + Vector2(0, 9), 10.0, Color(0, 0, 0, 0.12))
	if school_id == "blade" and soul >= 100.0 and vfx.has("fx_blade_soul_aura"):      # 刀魂满：脚下一圈火环
		vfx.draw(self, "fx_blade_soul_aura", vfx.frame_loop("fx_blade_soul_aura", time), player_pos + Vector2(0, 10), 130.0, 0.0, Color(1, 1, 1, 0.75))
	if school_id == "fist" and fist_ult_t > 0.0:      # 拳掌无敌：金青脉动光环
		var fu := 0.5 + 0.5 * sin(time * 8.0)
		draw_circle(player_pos + Vector2(0, 8), 34.0 + 6.0 * fu, Color(0.2, 0.9, 0.8, 0.14))
		draw_arc(player_pos + Vector2(0, 8), 30.0 + 7.0 * fu, 0.0, TAU, 32, Color("#5fe8d0", 0.8), 3.0)
		draw_arc(player_pos + Vector2(0, 8), 42.0 + 9.0 * fu, 0.0, TAU, 32, Color("#ffd24a", 0.55), 2.0)
	if school_id == "blade" and tb_t > 0.0:          # 真·霸刀破岳：赤红 + 耀金脉动光环
		var pu := 0.5 + 0.5 * sin(time * 9.0)
		draw_circle(player_pos + Vector2(0, 8), 34.0 + 6.0 * pu, Color(1.0, 0.25, 0.1, 0.16))
		draw_arc(player_pos + Vector2(0, 8), 28.0 + 8.0 * pu, 0.0, TAU, 32, Color("#ff5a28", 0.75), 3.0)
		draw_arc(player_pos + Vector2(0, 8), 40.0 + 10.0 * pu, 0.0, TAU, 32, Color("#ffd24a", 0.55), 2.0)
		for k in 6:
			var an := time * 2.2 + float(k) * TAU / 6.0
			draw_circle(player_pos + Vector2(0, 8) + Vector2(cos(an), sin(an)) * (46.0 + 4.0 * pu), 2.4, Color("#ffd24a", 0.8))
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
		if sprite_anim.draw(self, str(state[0]), float(state[1]), player_pos + Vector2(0, 14.0 - _player_bob()), facing.x < 0.0, tint, Data.T("player_zoom"), lean, sq):   # 三个流派的角色高度都是 56px，统一放大
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
				var tw := maxf(200.0, float(fs) * float(str(fx["text"]).length()) + 24.0)
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
			"ray":
				var rc: Color = fx["color"]
				var rto: Vector2 = fx["to"]
				draw_line(at, rto, Color(rc, a * 0.35), float(fx["width"]))
				draw_line(at, rto, Color(1, 1, 1, a * 0.9), 4.0)
			"slash":
				var ang: float = fx["angle"]
				var arc: float = fx["arc"]
				var rr: float = fx["r"]
				var wdt := (16.0 if fx["heavy"] else 10.0) * a + 2.0
				var sc: Color = fx.get("color", INK)
				draw_arc(at, rr * 0.7, ang - arc * 0.5, ang + arc * 0.5, 16, Color(sc, a * 0.85), wdt)
				draw_arc(at, rr * 0.9, ang - arc * 0.4, ang + arc * 0.4, 16, Color(1, 1, 1, a * 0.6), wdt * 0.4)


# =====================================================================
# 剑侠：破绽 / 中毒 / 独孤九剑「式」
# =====================================================================

## 破绽：受到的伤害额外 +v，持续 t 秒；spread 时顺带让附近一名敌人也露出破绽（万法皆破）
func apply_vuln(e: Enemy, v: float, spread: bool = false) -> void:
	if skills.has("dugu"):                        # 天赋「万法」：独孤九剑的破绽更痛
		v *= 1.0 + st("dugu_vuln")
	if e.is_boss:                                 # Boss 只吃破绽效果的一半（承伤加成、攻击削弱都减半）
		v *= Data.T("boss_vuln_mult")
	var t := Data.T("dugu_vuln_t")
	if e.vuln_t <= 0.0 and e.weak_fx <= 0.0 and effects.size() < MAX_EFFECTS:
		e.weak_fx = 0.8
		add_fx("text", e.pos + Vector2(0, -e.radius - 14), 0.85, {"text": "破绽", "size": 22, "color": JADE})
	e.vuln = maxf(e.vuln if e.vuln_t > 0.0 else 0.0, v)
	e.vuln_t = t
	if dugu_stage() >= 2:                         # 万法皆破：破绽同时削弱敌人的攻击
		e.atk_down = Data.T("dugu_atk_down") * (Data.T("boss_vuln_mult") if e.is_boss else 1.0)
		e.atk_down_t = t
	if spread:
		var nb := _nearest_from(e.pos, 170.0, {e.uid: true})
		if nb != null:
			nb.vuln = maxf(nb.vuln if nb.vuln_t > 0.0 else 0.0, v)
			nb.vuln_t = t


## 中毒：每次命中叠加 dps（最多 6 层，每层 = dps），重置持续时间
## 刀魂：+n（上限 100）；刀魂越多，刀法的伤害和范围越大
func add_soul(n: float) -> void:
	if school_id != "blade" or n <= 0.0:
		return
	soul = minf(100.0, soul + n * (1.0 + st("soul_gain") + (0.5 if st("ji_blade") > 0.0 else 0.0)))
	soul_idle = 0.0


## 真·霸刀破岳：气血 ≤ 20% 时触发，持续 10 秒（刀招不耗血、回复翻倍）；冷却 30 秒从状态结束后才开始算；每帧检查
func _tick_true_blade(dt: float) -> void:
	if tb_t > 0.0:
		tb_t -= dt
		if tb_t <= 0.0:
			tb_t = 0.0
			tb_cd = Data.T("true_blade_cd") * (0.5 if st("ji_blade") > 0.0 else 1.0)
			add_fx("text", player_pos + Vector2(0, -52), 0.9, {"text": "破岳之势已尽", "size": 22, "color": Color("#c9a227")})
	elif tb_cd > 0.0:
		tb_cd = maxf(0.0, tb_cd - dt)
	elif hp > 0.0 and not over and hp <= st("max_hp") * Data.T("true_blade_hp_pct"):
		tb_t = Data.T("true_blade_dur") + (5.0 if st("ji_blade") > 0.0 else 0.0)
		tb_count += 1
		invuln = maxf(invuln, Data.T("true_blade_invuln"))
		add_fx("text", player_pos + Vector2(0, -60), 1.6, {"text": "真·霸刀破岳！", "size": 34, "color": Color("#ff6030")})
		add_fx("ring", player_pos, 0.8, {"r0": 10.0, "r1": 240.0, "color": Color("#ff6030")})
		shake = maxf(shake, 9.0)
		Sfx.play("burst_break")


## 回复倍率（真·霸刀破岳期间：吸血 / 击杀回血 / 自然回复都翻倍）
func heal_mult() -> float:
	return Data.T("true_blade_heal_mult") if tb_t > 0.0 else 1.0


## 蓄劲：每次出手（不管打中几只）攒劲；满 100 后下一次出手打出「寸劲震爆」
func fist_after_cast(s: SkillBase) -> void:
	if school_id != "fist" or s.free_cast or str(s.def.get("school", "")) != "fist":
		return
	if fist_ult_t > 0.0:                          # 拳掌无敌：每一下出手都触发寸劲（不耗劲力）
		_cunjin(s, true)
	elif fist_qi >= 100.0:
		_cunjin(s)
	else:
		fist_qi = minf(100.0, fist_qi + Data.T("fist_qi_cast") * (1.0 + st("qi_gain") + (1.0 if st("ji_fist") > 0.0 else 0.0)))


func _cunjin(s: SkillBase, free: bool = false) -> void:
	var t := nearest_enemy(420.0)
	var center := t.pos if t != null else player_pos + facing_dir() * 90.0
	var r := Data.T("fist_qi_radius")
	var base := s.p("damage") * Data.T("fist_qi_mult")
	for e in _query(center, r):
		if not e.alive:
			continue
		var d := e.pos.distance_to(center)
		if d >= r + e.radius:
			continue
		var out := (e.pos - center) / d if d > 0.01 else Vector2.from_angle(rng.randf() * TAU)
		hit_enemy(e, base, s.tags(), out * Data.T("fist_qi_knock"), s.id)
		if e.alive and not e.is_prop:
			apply_vuln(e, Data.T("fist_qi_vuln"))
	if not free:
		fist_qi = 0.0
	cunjin_count += 1
	add_fx("ring", center, 0.5, {"r0": 14.0, "r1": r, "color": Color("#5fe8d0"), "vfx": "burst_gold", "size": r * 2.2})
	add_fx("ring", center, 0.3, {"r0": 6.0, "r1": r * 0.6, "color": GOLD})
	if not free or cunjin_count % 4 == 0:             # 无敌期间连发，飘字不刷屏
		add_fx("text", player_pos + Vector2(0, -52), 1.0, {"text": "寸劲震爆！", "size": 30, "color": Color("#5fe8d0")})
	shake = maxf(shake, 8.0)
	Sfx.play("fist_quake", 0.04, 0.0)
	Sfx.play("armor_break", 0.04, -3.0)


func facing_dir() -> Vector2:
	return facing.normalized() if facing.length() > 0.1 else Vector2.RIGHT


func blade_dmg() -> float:
	return 1.0 + Data.T("blade_soul_dmg") * floorf(soul / 10.0)


func blade_range() -> float:
	return 1.0 + Data.T("blade_soul_range") * floorf(soul / 10.0) if school_id == "blade" else 1.0


## 刀魂满时，这一次出手是「霸刀破岳」：返回 true 表示已「上膛」
func baodao_try(s: SkillBase) -> bool:
	if school_id == "blade" and soul >= 100.0 and not s.free_cast and str(s.def.get("school", "")) == "blade":
		baodao = true
		return true
	return false


func baodao_done() -> void:
	for sk_f: SkillBase in skills.values():
		sk_f.on_baodao()
	soul = 0.0
	soul_idle = 0.0
	var heal := (st("max_hp") - hp) * Data.T("blade_break_heal") * (2.0 if st("ji_blade") > 0.0 else 1.0)
	hp = minf(st("max_hp"), hp + heal)
	add_fx("text", player_pos + Vector2(0, -52), 1.0, {"text": "霸刀！" if rng.randf() < 0.5 else "破岳！", "size": 30, "color": Color("#ffb030")})
	shake = maxf(shake, 7.0)
	Sfx.play("burst_break")


## 撕裂：每层每秒造成「触发这一击」伤害的一定比例，持续数秒；层数上限 5
func apply_bleed(e: Enemy, stacks: int, hit_dmg: float) -> void:
	if e.is_prop or not e.alive or stacks <= 0:
		return
	var per := hit_dmg * Data.T("bleed_pct") * (1.0 + st("bleed_pow"))
	var cap := int(Data.T("bleed_max"))
	var add := mini(stacks, cap - e.bleed_stacks)
	if add > 0:
		e.bleed_stacks += add
		e.bleed_dps += per * add
	e.bleed_t = Data.T("bleed_dur") + 0.0
	if e.bleed_stacks >= cap and e.bleed_dps > 0.0:
		e.bleed_dps = maxf(e.bleed_dps, per * cap)


## 断脉爆血：撕裂叠满时被重劈命中，立即结算剩余流血的 150% 并溅射周围
func bleed_burst(e: Enemy) -> void:
	if e.bleed_stacks < int(Data.T("bleed_max")) or e.bleed_dps <= 0.0:
		return
	var dmg := e.bleed_dps * maxf(0.5, e.bleed_t) * Data.T("bleed_burst")
	e.bleed_stacks = 0
	e.bleed_dps = 0.0
	e.bleed_t = 0.0
	area_hit_raw(e.pos, Data.T("bleed_burst_r"), dmg, [], "bleed", 60.0)
	add_fx("ring", e.pos, 0.4, {"r0": 10.0, "r1": Data.T("bleed_burst_r"), "color": Color("#d84a3a")})
	add_fx("text", e.pos + Vector2(0, -e.radius - 22), 0.9, {"text": "断脉爆血", "size": 24, "color": Color("#ff5a40")})
	Sfx.play("hit_crit")


func poison_enemy(e: Enemy, dps: float, sid: String) -> void:
	var sk: SkillBase = skills.get(sid)
	var mult := 2.0 if (sk != null and sk.empowered) else 1.0
	e.poison_dps = minf(dps * 6.0 * mult, e.poison_dps + dps * mult)
	e.poison_t = 4.0
	if sk != null and sk.enhanced():
		e.poison_burst = sk.ev(80.0, 100.0, 120.0)


## 某一式实际生效的层数 = 层数 + 品质加成（取整）；门槛只看 shi_total()，不含品质加成
func shi_lv(id: String) -> int:
	return int(shi.get(id, 0)) + int(float(shi_bonus.get(id, 0.0)))


func shi_total() -> int:
	var t := 0
	for k in shi:
		t += int(shi[k])
	return t


## 独孤九剑形态：0 = 没走独孤路线；1 = 起手（≥9 另有「破兵微步」）；2 = 万法皆破（总层 ≥ 18）；3 = 真·独孤九剑（总层 ≥ 27）
func dugu_stage() -> int:
	if not skills.has("dugu"):
		return 0
	var t := shi_total()
	if t >= int(Data.T("shi_stage3")):
		return 3
	return 2 if t >= int(Data.T("shi_stage2")) else 1


## 总层 ≥ 9：「破兵微步」
func dugu_micro() -> bool:
	return skills.has("dugu") and shi_total() >= int(Data.T("shi_stage1"))


## 能否斩落敌方普通投射物（万法皆破起；或学了破箭式）
func dugu_can_cut() -> bool:
	return skills.has("dugu") and (dugu_stage() >= 2 or int(shi.get("po_arrow", 0)) > 0)


## 斩落 center 周围 radius 内的敌方普通投射物（Boss 大招除外），返回斩落数量
func cut_hostile_projs(center: Vector2, radius: float) -> int:
	var n := 0
	for h in projs:
		if h.hostile and h.cuttable and h.life > 0.0 and h.pos.distance_to(center) < radius + h.radius:
			h.life = 0.0
			n += 1
			if effects.size() < MAX_EFFECTS:
				add_fx("ring", h.pos, 0.2, {"r0": 3.0, "r1": 18.0, "color": Color("#bfe8ff")})
	if n > 0:
		cut_count += n
		Sfx.play("hit_crit", 0.06, -6.0)
	return n


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
	var old_micro := dugu_micro()
	var old := int(shi.get(id, 0))
	shi[id] = mini(cap, old + n)
	var stage := dugu_stage()
	if dugu_micro() and not old_micro:
		add_fx("text", player_pos + Vector2(0, -60), 1.8, {"text": "破兵微步", "size": 26, "color": Color("#bfe8ff")})
	if stage > old_stage and stage >= 2:
		var txt := "万法皆破" if stage == 2 else "九剑真传"
		add_fx("text", player_pos + Vector2(0, -60), 2.4, {"text": txt, "size": 30, "color": VERMILION})
		add_fx("ring", player_pos, 0.9, {"r0": 10.0, "r1": 260.0, "color": GOLD})
		shake = maxf(shake, 8.0)
		if stage == 3:
			Sfx.play("dugu_awaken")
			play_anim("awaken", 0.6)
			_trigger_sword_break(0.6, 1.0)
	return int(shi[id]) - old


## 「式」的说明：普通形态（飞剑）+ 觉醒后（≥27 层，近战）的效果
func _shi_desc(d: Dictionary) -> String:
	return "普通：%s\n觉醒：%s" % [d["desc"], d.get("awaken", "同样生效")]


## 独孤九剑的「式」卡牌：已学的提升、新式（总共最多 4 种）。gain：本次领悟的层数
func shi_cards(n: int, gain: int, src: String) -> Array:
	var pool: Array = []
	var cap := int(Data.T("shi_lv_max"))
	var chest := src == "chest"
	for d in Data.shi:
		var id := str(d["id"])
		var lv := int(shi.get(id, 0))
		# 品质：升级卡按概率抽（福缘提高高档）；秘籍至少紫色
		var tier := Data.roll_tier(rng, st("luck"))
		if chest:
			tier = maxi(tier, 2)
		var bonus := float(tier) * Data.T("shi_q_step")
		var qn := str(Data.tiers[tier]["name"])
		var col := str(Data.tiers[tier]["color"])
		if lv > 0:
			if lv < cap or chest:
				var g := 0 if chest else gain
				pool.append({"kind": "shi_up", "id": id, "gain": g, "tier": tier, "bonus": bonus, "tag": qn, "color": col, "src": src,
					"title": ("%s Lv%d→%d" % [d["name"], lv, mini(cap, lv + g)]) if g > 0 else ("%s 品质加成" % d["name"]),
					"desc": _shi_card_text(d, g, bonus)})
		elif shi.size() < int(Data.T("shi_kinds")):
			var g2 := maxi(1, gain)
			pool.append({"kind": "shi_new", "id": id, "gain": g2, "tier": tier, "bonus": bonus, "tag": qn, "color": col, "src": src,
				"title": "领悟：%s" % d["name"], "desc": _shi_card_text(d, g2, bonus)})
	_shuffle(pool)
	var out: Array = []
	while out.size() < n and not pool.is_empty():
		out.append(pool.pop_back())
	return out


## 「式」卡片说明：层数（计入门槛）+ 品质加成（只加威力）+ 普通 / 觉醒效果
func _shi_card_text(d: Dictionary, gain: int, bonus: float) -> String:
	var head := ""
	if gain > 0:
		head = "层数 +%d（计入 9 / 18 / 27 层门槛）" % gain
	if bonus > 0.0:
		head += ("　" if head != "" else "") + "品质加成 +%s 层威力（不计入门槛）" % String.num(bonus, 1)
	return head + "\n" + _shi_desc(d)


# =====================================================================
# 掉落物素材 / 可打碎的场景物件
# =====================================================================

func _load_pickups() -> void:
	var path := "res://assets/pickups/meta.json"
	if not FileAccess.file_exists(path):
		return
	var js: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not js is Dictionary:
		return
	for id in js:
		var d: Dictionary = js[id]
		var f := "res://assets/pickups/%s" % str(d["file"])
		if ResourceLoader.exists(f):
			pickup_art[str(id)] = {"tex": load(f), "w": int(d["w"]), "h": int(d["h"])}


## 掉落物：以 at 为中心，画成高度 h（世界像素）；rot：旋转（吸星珠）
func _draw_pickup(id: String, at: Vector2, h: float, rot: float = 0.0, tint: Color = Color.WHITE) -> void:
	var a: Dictionary = pickup_art[id]
	var w := h * float(a["w"]) / float(a["h"])
	draw_set_transform(at, rot, Vector2.ONE)
	draw_texture_rect(a["tex"], Rect2(-w * 0.5, -h * 0.5, w, h), false, tint)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 修为珠分品阶：绿（小）→ 绿（大）→ 金 → 金（大）
func _draw_gem(at: Vector2, value: int, age: float) -> void:
	if not pickup_art.has("gem_low"):
		draw_colored_polygon(PackedVector2Array([at + Vector2(0, -6), at + Vector2(5, 0), at + Vector2(0, 6), at + Vector2(-5, 0)]), GOLD)
		return
	var high := value >= 8
	var h := 17.0 if value < 3 else (24.0 if value < 8 else (26.0 if value < 20 else 34.0))
	var bob := sin(time * 4.0 + at.x * 0.07) * 1.5
	_draw_pickup("gem_high" if high else "gem_low", at + Vector2(0, bob), h)


func _update_props(dt: float) -> void:
	if not props_enabled:
		return
	prop_t -= dt
	var n := 0
	for e in enemies:
		if e.alive and e.is_prop:
			if e.pos.distance_to(player_pos) > RELOCATE_DIST + 200.0:
				e.alive = false          # 离得太远：悄悄消失，不掉东西
			else:
				n += 1
	if prop_t > 0.0 or n >= int(Data.T("prop_max")):
		return
	prop_t = Data.T("prop_interval") * rng.randf_range(0.7, 1.3)
	var r := rng.randf()
	var kind := "prop_crate" if r < 0.5 else ("prop_jar" if r < 0.85 else "prop_brazier")
	var dist := rng.randf_range(Data.T("prop_min_dist"), Data.T("prop_max_dist"))
	_spawn_enemy(kind, player_pos + Vector2.from_angle(rng.randf() * TAU) * dist)


func _break_prop(e: Enemy) -> void:
	add_fx("splat", e.pos, 0.4, {"r": e.radius * 1.2, "color": e.color})
	match e.type_id:
		"prop_crate":                         # 木箱：掉几颗修为珠
			for i in 3:
				_drop_gem(e.pos + Vector2(rng.randf_range(-14, 14), rng.randf_range(-10, 10)), int(Data.T("prop_gem_value")))
		"prop_jar":                           # 酒坛：多半掉一颗回血葫芦，否则掉修为珠
			if rng.randf() < Data.T("prop_jar_pill"):
				_drop_pill(e.pos, "small")
			else:
				for i in 2:
					_drop_gem(e.pos + Vector2(rng.randf_range(-12, 12), rng.randf_range(-8, 8)), int(Data.T("prop_gem_value")) + 1)
			add_fx("text", e.pos + Vector2(0, -e.radius - 8), 0.8, {"text": "酒香四溢", "size": 18, "color": Color("#ffb070")})
		"prop_brazier":                       # 火盆：打翻后火星四溅，灼伤周围的敌人
			var R := Data.T("prop_fire_radius")
			area_hit_raw(e.pos, R, Data.T("prop_fire_damage") * (1.0 + time / 240.0), [], "brazier", 220.0)
			add_fx("ring", e.pos, 0.4, {"r0": 10.0, "r1": R, "color": Color("#ff8a30")})
			add_fx("text", e.pos + Vector2(0, -e.radius - 8), 0.8, {"text": "火星四溅", "size": 18, "color": Color("#ffb070")})
			shake = maxf(shake, 4.0)


func _draw_prop(e: Enemy) -> void:
	var id := e.type_id.trim_prefix("prop_")
	var h: float = float({"crate": 40.0, "jar": 38.0, "brazier": 48.0}.get(id, 40.0))
	var at := e.pos + Vector2(0, -h * 0.35)
	draw_circle(e.pos + Vector2(0, 8), e.radius * 0.9, Color(0, 0, 0, 0.2))
	if pickup_art.has(id):
		_draw_pickup(id, at, h, 0.0, Color(1.6, 1.6, 1.6) if e.flash > 0.0 else Color.WHITE)
	else:
		draw_circle(e.pos, e.radius, Color.WHITE if e.flash > 0.0 else e.color)


# =====================================================================
# Boss 留下的地面区域（毒雾 / 冰封带）
# =====================================================================

func add_hzone(z: Dictionary) -> void:
	z["t"] = 0.0
	z["tick"] = 0.0
	hzones.append(z)


func _hz_contains(z: Dictionary, p: Vector2) -> bool:
	if str(z["shape"]) == "circle":
		return p.distance_to(z["pos"]) <= float(z["r"]) + PLAYER_RADIUS
	var a: Vector2 = z["pos"]
	var b: Vector2 = z["end"]
	var ab := b - a
	var tt := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1.0), 0.0, 1.0)
	return p.distance_to(a + ab * tt) <= float(z["r"]) * 0.5 + PLAYER_RADIUS


func _update_hzones(dt: float) -> void:
	var j := 0
	for z in hzones:
		z["t"] = float(z["t"]) + dt
		if float(z["t"]) < float(z["life"]):
			if _hz_contains(z, player_pos):
				if float(z["slow"]) > 0.0:
					player_slow_t = maxf(player_slow_t, 0.25)
				z["tick"] = float(z["tick"]) + dt
				if float(z["tick"]) >= 0.5:
					z["tick"] = 0.0
					hurt_dot(float(z["dps"]) * 0.5)
			hzones[j] = z
			j += 1
	hzones.resize(j)


## 持续伤害（毒 / 冰）：不触发受击无敌，护盾和内力减伤不生效，但仍会死
func hurt_dot(amount: float) -> void:
	if god or over or invuln > 0.3:
		return
	hp -= maxf(0.5, amount - st("armor") * 0.25)
	add_fx("text", player_pos + Vector2(rng.randf_range(-10, 10), -24), 0.5, {"text": "-%d" % int(amount), "size": 16, "color": Color("#a0e060")})
	add_fx("ring", player_pos + Vector2(0, -8), 0.45, {"r0": 6.0, "r1": 20.0, "color": Color("#a0e060"), "vfx": "fx_poison_hit", "size": 60.0})
	if hp <= 0.0 and not over:
		hp = 0.0
		over = true
		won = false
		player_died.emit()


func _draw_hzones() -> void:
	for z in hzones:
		var a := clampf(minf(float(z["t"]) * 3.0, (float(z["life"]) - float(z["t"])) * 1.5), 0.0, 1.0)
		var col: Color = Color("#7ac040") if str(z["kind"]) == "mist" else Color("#8ad0ff")
		if vfx.has(str(z.get("vfx", ""))) and str(z["shape"]) == "circle":
			var zf := vfx.frame_loop(str(z["vfx"]), time)
			if str(z["kind"]) == "scar":
				zf = int(absf((z["pos"] as Vector2).x)) % int(vfx.effects[str(z["vfx"])]["frames"])
			vfx.draw(self, str(z["vfx"]), zf, z["pos"], float(z["r"]) * 2.2, 0.0, Color(1, 1, 1, a))
		elif str(z["shape"]) == "circle":
			draw_circle(z["pos"], float(z["r"]), Color(col, 0.22 * a))
			draw_arc(z["pos"], float(z["r"]), 0.0, TAU, 36, Color(col, 0.7 * a), 3.0)
		elif str(z["shape"]) == "line" and vfx.has(str(z.get("vfx", ""))):
			var zp: Vector2 = z["pos"]
			var ze: Vector2 = z["end"]
			var zl := zp.distance_to(ze)
			vfx.draw(self, str(z["vfx"]), vfx.frame_loop(str(z["vfx"]), time), (zp + ze) * 0.5, zl, (ze - zp).angle(), Color(1, 1, 1, a * 0.9))
		else:
			draw_line(z["pos"], z["end"], Color(col, 0.28 * a), float(z["r"]))
			draw_line(z["pos"], z["end"], Color(col, 0.6 * a), 3.0)
