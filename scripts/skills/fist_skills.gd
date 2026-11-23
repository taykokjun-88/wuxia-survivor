class_name FistSkills
extends RefCounted
## 武者流派的 9 个攻击技能。每个技能的"专属强化"在 enhanced() 分支里实现。


static func create(skill_id: String) -> SkillBase:
	match skill_id:
		"yue_palm": return YuePalm.new()
		"chain_fist": return ChainFist.new()
		"quake_fist": return QuakeFist.new()
		"whirl_palm": return WhirlPalm.new()
		"point_finger": return PointFinger.new()
		"vajra_fist": return VajraFist.new()
		"cloud_palm": return CloudPalm.new()
		"eight_waste": return EightWaste.new()
		"taiji": return Taiji.new()
	push_error("未知技能: " + skill_id)
	return null


## 撼岳惊涛掌：贯穿掌风。强化「龙战于野」：首次命中后分裂成两道小掌风。
class YuePalm extends SkillBase:
	var _n := 0

	func fire() -> bool:
		var t := w.nearest_enemy(p("speed") * p("life"))
		if t == null:
			return false
		var a := (t.pos - w.player_pos).angle()
		var o := {"split": int(ev(2, 3, 4)) if enhanced() else 0}
		if empowered:    # 催动：龙形掌风
			o["radius"] = p("radius") * 1.8
			o["pierce"] = p("pierce") + 3.0
		var hl := int(w.st("t_hanyue"))                  # 撼岳之势：每穿透一个敌人，伤害反而 +5% / +10%
		if hl > 0:
			o["falloff"] = 1.0 + 0.05 * float(hl)
		var jl := int(w.st("t_jingtao"))                 # 惊涛叠浪：飞到尽头炸成一圈浪
		_n += 1
		var offs: Array = [0.0]
		if int(w.st("t_jingtao_cap")) > 0 and _n % 5 == 0:   # 惊涛骇浪：每第 5 掌改为并排 3 道巨浪
			offs = [-45.0, 0.0, 45.0]
		var perp := Vector2.from_angle(a + PI * 0.5)
		for off in offs:
			var o2: Dictionary = o.duplicate()
			o2["pos"] = w.player_pos + Vector2.from_angle(a) * 18.0 + perp * float(off)
			var pr := w.spawn_proj(self, a, o2)
			if jl > 0:
				pr.end_burst_dmg = p("damage") * (0.1 + 0.2 * float(jl))
		return true


## 连山贯日拳：近身三连击。强化「横扫千军」：第三拳必暴击并释放冲击波。
class ChainFist extends SkillBase:
	var combo := 0
	var _marks: Dictionary = {}          # 天赋「连山不绝」：敌人 uid → [破绽层数, 上次命中时间]

	func hit_mult(e: Enemy) -> float:
		var lv := int(w.st("t_lianshan"))
		if lv <= 0:
			return 1.0
		var m: Array = _marks.get(e.uid, [0, 0.0])
		if w.time - float(m[1]) > 3.0:
			m[0] = 0
		var mult := 1.0 + 0.05 * float(m[0])
		m[0] = mini(int(m[0]) + 1, 2 + lv)
		m[1] = w.time
		_marks[e.uid] = m
		if _marks.size() > 300:
			_marks.clear()
		return mult

	func _third_talents(a: float, reach: float, knock: float, t: Enemy, gl: int) -> void:
		FistSkills._chain_third(self, a, reach, knock, t, gl)

	func fire() -> bool:
		var reach := p("reach")
		var t := w.nearest_enemy(reach + 30.0)
		if t == null:
			return false
		var a := (t.pos - w.player_pos).angle()
		combo += 1
		var third := combo % 3 == 0 or empowered
		var base := p("damage") * (2.2 if third else 1.0)
		var gl := int(w.st("t_guanri"))
		var knock := 320.0 * (1.0 + 0.2 * float(gl)) if third else 160.0
		w.fx_slash(w.player_pos, a, reach, p("arc"), third, fxid("slash"))
		w.cone_hit(self, w.player_pos, a, p("arc") * 0.5, reach, base, knock, third and enhanced())
		if empowered:    # 催动：末拳震晕前方敌人
			w.area_hit(self, w.player_pos + Vector2.from_angle(a) * reach * 0.6, 70.0, base * 0.4, 0.0, 0.8)
		if third:
			_third_talents(a, reach, knock, t, gl)
		if third and enhanced():
			var sr := ev(140.0, 170.0, 200.0)
			w.area_hit(self, w.player_pos, sr, p("damage") * ev(1.2, 1.6, 2.0), 300.0)
			w.add_fx("ring", w.player_pos, 0.35, {"r0": 20.0, "r1": sr, "color": GameWorld.GOLD})
		return true


## 连山贯日拳 · 第三拳的天赋：贯日之势（冲撞余波）/ 横扫余劲 / 贯日破天（贯穿直线）
static func _chain_third(s: ChainFist, a: float, reach: float, knock: float, t: Enemy, gl: int) -> void:
	var w := s.w
	if gl > 0:                                       # 贯日之势：被击飞方向上的敌人受到冲撞余波
		var at := t.pos + Vector2.from_angle(a) * 60.0
		w.area_hit(s, at, 75.0, s.p("damage") * 0.25 * float(gl), 0.0)
		w.add_fx("ring", at, 0.25, {"r0": 10.0, "r1": 75.0, "color": GameWorld.GOLD})
	var hl := int(w.st("t_hengsao"))
	if hl > 0 and s.enhanced():                      # 横扫余劲：追加一道更宽的余劲扇面
		w.fx_slash(w.player_pos, a, reach * 1.15, s.p("arc") * 1.3, true, s.fxid("slash"))
		w.cone_hit(s, w.player_pos, a, s.p("arc") * 0.65, reach * 1.15, s.p("damage") * (0.4 if hl == 1 else 0.7), knock * 0.5)
	if int(w.st("t_guanri_cap")) > 0 and s.combo % 3 == 0:   # 贯日破天：贯穿直线，伤害 200%，防御 −30%（3 秒）
		var dir := Vector2.from_angle(a)
		var len := reach * 2.4
		w.fx_slash(w.player_pos, a, len, 0.5, true, s.fxid("slash"))
		for e in w._query(w.player_pos, len + 40.0):
			if not e.alive:
				continue
			var rel := e.pos - w.player_pos
			var along := rel.dot(dir)
			if along > 0.0 and along < len and absf(rel.cross(dir)) < 38.0 + e.radius:
				e.def_down = 0.3
				e.def_down_t = 3.0
				w.hit_enemy(e, s.p("damage") * 2.0, s.tags(), dir * knock, s.id)


## 裂脉震拳：延迟落点的范围击晕。强化「裂脉暗劲」：落点留下 3 秒的裂痕。
class QuakeFist extends SkillBase:
	func fire() -> bool:
		var t := w.nearest_enemy(p("range"))
		if t == null:
			return false
		var z := {
			"kind": "impact", "skill": self, "pos": t.pos, "r": p("radius"),
			"delay": 0.35, "t": 0.0, "dmg": p("damage"), "stun": p("stun"), "crack": enhanced() or int(w.st("t_liemai_cap")) > 0, "elv": maxi(1, elv()),
		}
		w.add_zone(z)
		var ll := int(w.st("t_liemai"))                 # 裂脉连震：0.5 秒后再震一次（30% / 45% / 60%）
		if ll > 0:
			var z3 := z.duplicate()
			z3["delay"] = 0.85
			z3["dmg"] = float(z["dmg"]) * (0.15 + 0.15 * float(ll))
			z3["crack"] = false
			w.add_zone(z3)
		if empowered:    # 催动：落点追加一圈更大的冲击波
			var z2 := z.duplicate()
			z2["r"] = float(z["r"]) * 1.6
			z2["delay"] = 0.6
			z2["dmg"] = float(z["dmg"]) * 0.6
			z2["crack"] = false
			w.add_zone(z2)
		return true


## 乱花拂柳掌：环身掌风。强化「落英缤纷」：掌风过后身周旋涡收束，再轰一次（不再吸拢敌人）。
class WhirlPalm extends SkillBase:
	var _fuliu_t := -9.0

	func fire() -> bool:
		var r := p("radius") * (1.5 if empowered else 1.0)
		if not w.any_enemy_within(w.player_pos, r + 20.0):
			return false
		# 内力越满，连发的圈数越多（最多 3 圈，由小到大）；多圈时每圈伤害 ×0.6
		var frac := w.neili / maxf(1.0, w.st("max_neili"))
		var maxn := 3 + int(w.st("t_huakai"))               # 花开不败：圈数上限 +1/级（3 → 6）
		var n := clampi(1 + int(frac * float(maxn)), 1, maxn)
		var radii: Array = []
		if n <= 3:
			radii = {1: [1.0], 2: [0.7, 1.0], 3: [0.5, 0.75, 1.0]}[n]
		else:
			for i in n:
				radii.append(lerpf(0.4, 1.0, float(i) / float(n - 1)))
		for i in radii.size():
			var rr: float = r * float(radii[i])
			var last: bool = i == radii.size() - 1
			w.area_hit(self, w.player_pos, rr, p("damage") * (1.0 if n == 1 else 0.6), p("knock") * (2.0 if empowered else 1.0) if last else 0.0)
			w.add_fx("ring", w.player_pos, 0.3 + 0.08 * i, {"r0": 15.0, "r1": rr, "color": GameWorld.INK, "vfx": "fist_whirl_ring" if w.vfx.has("fist_whirl_ring") else (fxid("ring") if fxid("ring") != "" else "burst_wind"), "size": rr * 2.3})
		if enhanced():
			w.add_zone({"kind": "vortex", "skill": self, "dmg": p("damage") * ev(1.2, 1.6, 2.0), "r": r * ev(1.8, 2.1, 2.4),
				"t": 0.0, "life": 0.9})
		var fl := int(w.st("t_fuliu"))                      # 拂柳回气：一圈命中 ≥3 个敌人回内力（每秒最多一次）
		if fl > 0 and w.time - _fuliu_t >= 1.0:
			var cnt := 0
			for e in w._query(w.player_pos, r):
				if e.alive and e.pos.distance_to(w.player_pos) < r + e.radius:
					cnt += 1
			if cnt >= 3:
				w.add_neili(2.0 * float(fl))
				_fuliu_t = w.time
		if int(w.st("t_luanhua")) > 0 and n >= 3:           # 乱花漫天：三圈满时追加全屏一圈，并回复 5% 气血
			w.area_hit(self, w.player_pos, 700.0, p("damage") * 0.6, p("knock") * 2.0)
			w.add_fx("ring", w.player_pos, 0.5, {"r0": 30.0, "r1": 600.0, "color": GameWorld.INK, "vfx": "burst_wind", "size": 1100.0})
			w.hp = minf(w.st("max_hp"), w.hp + w.st("max_hp") * 0.05 * w.heal_mult())
		return true


## 凝霜点指：定身。强化「一阳连环」：被点穴的敌人死亡时爆炸并定身周围敌人。
class PointFinger extends SkillBase:
	func fire() -> bool:
		var reach := p("speed") * p("life")
		var targets := w.nearest_n(reach, int(p("count")))
		if targets.is_empty():
			return false
		var hl := int(w.st("t_hanshuang"))                  # 寒霜入骨：穿透衰减 −10%/级、定身几率 +5%/级
		var fall := minf(1.0, float(def.get("falloff", 1.0)) + 0.1 * float(hl))
		var sc := minf(1.0, float(def.get("stun_chance", 1.0)) + 0.05 * float(hl))
		var stun_t := (p("stun") + (1.0 if int(w.st("t_wanlai")) > 0 else 0.0)) * (2.0 if empowered else 1.0)   # 万籁俱寂：定身 +1 秒
		for t in targets:
			var a := (t.pos - w.player_pos).angle()
			w.spawn_proj(self, a, {"stun": stun_t, "chain": enhanced(), "falloff": fall, "stun_chance": sc})
		return true

	func hit_mult(e: Enemy) -> float:
		return 2.0 if int(w.st("t_wanlai")) > 0 and e.stun > 0.0 else 1.0       # 万籁俱寂：被定身的敌人受到凝霜点指伤害 ×2


## 沉岳铁拳：消耗内力的重击，内力越满越痛。强化「金刚不坏」：内力 ≥90% 时不耗内力并获得护盾。
class VajraFist extends SkillBase:
	func fire() -> bool:
		var reach := p("reach")
		var t := w.nearest_enemy(reach + 30.0)
		if t == null:
			return false
		var max_n := float(w.stats["max_neili"])
		var ratio := 1.0 if empowered else w.neili / max_n
		var mult := 0.8 + (1.2 + 0.1 * w.st("t_chenyue")) * ratio          # 沉岳蓄势：内力越满伤害越高的上限 +10%/级
		if enhanced() and ratio >= ev(0.9, 0.8, 0.7):
			w.add_shield(ev(25.0, 40.0, 55.0))
			mult *= 1.3
		else:
			w.neili = maxf(0.0, w.neili - p("cost"))
		var a := (t.pos - w.player_pos).angle()
		if fxid("bell") != "":
			w.add_fx("ring", w.player_pos + Vector2.from_angle(a) * reach * 0.55, 0.45, {"r0": reach * 0.4, "r1": reach * 0.95, "color": GameWorld.GOLD, "vfx": fxid("bell"), "size": reach * 2.2})
		else:
			w.fx_slash(w.player_pos, a, reach, p("arc"), true)
		var cap := int(w.st("t_chenyue_cap")) > 0 and ratio >= 0.9      # 沉岳崩山：内力 ≥90% 必暴击并震晕周围 1.2 秒
		w.cone_hit(self, w.player_pos, a, p("arc") * 0.5, reach, p("damage") * mult, p("knock"), cap)
		if cap:
			for e in w._query(w.player_pos, 150.0):
				if e.alive and e.pos.distance_to(w.player_pos) < 150.0 + e.radius:
					w.stun_enemy(e, 1.2)
		var jl := int(w.st("t_jingang"))                    # 金刚震地：命中后在目标处爆出冲击波
		if jl > 0:
			w.area_hit(self, t.pos, 70.0, p("damage") * (0.1 + 0.1 * float(jl)), 0.0)
			w.add_fx("ring", t.pos, 0.3, {"r0": 8.0, "r1": 70.0, "color": GameWorld.GOLD, "vfx": "burst_quake" if w.vfx.has("burst_quake") else ""})
		var bl := int(w.st("t_bupo"))                       # 不坏金身：出拳后 2 秒内受到伤害 −8% / −15%
		if bl > 0:
			w.tal_dr_t = 2.0
			w.tal_dr_v = 0.08 if bl == 1 else 0.15
		return true


## 朔雪融阳掌：追踪掌印。强化「六阳回环」：掌印飞出后折返，可再次命中。
class CloudPalm extends SkillBase:
	var _giant_t := 0.0

	func tick(dt: float) -> void:
		_giant_t = maxf(0.0, _giant_t - dt)
		super.tick(dt)

	func fire() -> bool:
		var t := w.nearest_enemy(520.0)
		if t == null:
			return false
		var n := int(p("count")) + (1 if empowered else 0)
		var base := (t.pos - w.player_pos).angle()
		var giant_i := -1
		if int(w.st("t_yangji")) > 0 and _giant_t <= 0.0 and n >= 3:     # 阳极生阴：掌印齐备（≥3）时每 5 秒融合成一枚巨掌印
			giant_i = (n - 1) / 2
			_giant_t = 5.0
		var yl := int(w.st("t_yanghui"))
		for i in n:
			var a := base + (i - (n - 1) * 0.5) * 0.5
			var o := {"homing": true, "turn": p("turn"), "boomerang": enhanced()}
			if i == 0 and yl > 0 and w.palm_stacks > 0:                  # 阳回雪归：击杀后下一枚掌印增伤（+30%/级/层）
				o["damage"] = p("damage") * (1.0 + 0.3 * float(yl) * float(w.palm_stacks))
				w.palm_stacks = 0
			if i == giant_i:
				o["radius"] = p("radius") * 2.0
				o["damage"] = float(o.get("damage", p("damage"))) * 2.0
				o["pierce"] = maxi(4, int(p("pierce")) * 2)
				o["splash"] = maxf(70.0, float(def.get("splash_radius", 0.0)) * 2.0)
				o["splash_frac"] = maxf(0.5, float(def.get("splash_frac", 0.0)))
			w.spawn_proj(self, a, o)
		return true


## 四野归元功：八方拳气（基础 8 个，催动 12 个）。强化「唯我独尊」：连发三轮，每轮偏转，形成旋转弹幕。
class EightWaste extends SkillBase:
	var bursts_left := 0
	var burst_t := 0.0
	var rot := 0.0
	var emp_burst := false
	var _conv_total := 0          # 归元一气：本轮发出的拳气数 / 已消失数 / 伤害总和
	var _conv_gone := 0
	var _conv_dmg := 0.0

	func conv_gone() -> void:
		_conv_gone += 1
		if _conv_gone >= _conv_total:
			var at := w.player_pos + w.facing * 60.0
			w.area_hit(self, at, 150.0, _conv_dmg * 0.5, 300.0)
			w.add_fx("ring", at, 0.45, {"r0": 20.0, "r1": 150.0, "color": GameWorld.GOLD, "vfx": fxid("muzzle"), "size": 320.0})
			w.shake = maxf(w.shake, 5.0)
			_conv_total = 0
			_conv_gone = 0
			_conv_dmg = 0.0

	func tick(dt: float) -> void:
		if bursts_left > 0:
			burst_t -= dt
			if burst_t <= 0.0:
				_burst()
				bursts_left -= 1
				burst_t = 0.13
			return
		super.tick(dt)

	func fire() -> bool:
		if w.nearest_enemy(450.0) == null:
			return false
		emp_burst = empowered
		_burst()
		if enhanced():
			bursts_left = int(ev(2, 3, 4))
			burst_t = 0.13
		return true

	func _burst() -> void:
		if fxid("muzzle") != "":
			w.add_fx("ring", w.player_pos, 0.4, {"r0": 30.0, "r1": 150.0, "color": GameWorld.GOLD, "vfx": fxid("muzzle"), "size": 240.0 * (1.0 + float(mods["range"]))})
		var n := int(p("count")) + (4 if emp_burst else 0)
		var gl := int(w.st("t_guiyuan"))
		var cap := int(w.st("t_guiyuan_cap")) > 0
		for i in n:
			var pr := w.spawn_proj(self, rot + TAU * i / n)
			if gl > 0:
				pr.neili_hit = 0.3 * float(gl)              # 归元返照：每道拳气首次命中回内力
			if cap:                                          # 归元一气：拳气消失后汇聚成大爆炸
				pr.conv = true
				_conv_total += 1
				_conv_dmg += pr.damage
		rot += 0.3 if enhanced() else 0.2


## 回澜卸力诀：受击时化解部分伤害并反击；平时周身有微弱劲气。强化「颠倒乾坤」：化解的伤害 ×4 转为反击。
class Taiji extends SkillBase:
	var _acc := 0.0               # 回澜归海：累计化解的伤害
	var guard_cd := 0.0
	var guard_total := 0.0
	var pulse_t := 2.0

	func tick(dt: float) -> void:
		guard_cd = maxf(0.0, guard_cd - dt)
		pulse_t -= dt
		if pulse_t <= 0.0:
			pulse_t = 3.0
			if w.any_enemy_within(w.player_pos, 100.0):
				w.area_hit(self, w.player_pos, 90.0, p("damage") * 0.4, 120.0)
				w.add_fx("ring", w.player_pos, 0.3, {"r0": 12.0, "r1": 90.0, "color": GameWorld.JADE})

	func cd_frac() -> float:
		return clampf(guard_cd / guard_total, 0.0, 1.0) if guard_total > 0.2 and guard_cd > 0.0 else 0.0

	func cd_secs() -> float:
		return guard_cd if guard_total > 0.2 else 0.0

	func on_hurt(amount: float) -> float:
		if guard_cd > 0.0:
			return amount
		var emp := w.can_empower(empower_cost())    # 催动：反击不进冷却，反击伤害大增
		if emp:
			w.pay_empower(empower_cost())
		else:
			guard_cd = p("cooldown") * w.cd_mult()
			guard_total = guard_cd
		var absorbed := amount * minf(0.9, p("absorb") + 0.05 * w.st("t_xieli"))      # 卸力归元：化解比例 +5%/级
		var r := p("radius") * (ev(1.5, 1.7, 1.9) if enhanced() else 1.0)
		var mult := ev(4.0, 6.0, 8.0) if enhanced() else 1.0
		if emp:
			mult = maxf(mult * 1.5, 3.0)
		var fz := int(w.st("t_fanzhen"))                    # 回澜反震：反击伤害 +20%/级，额外击退
		var dmg := (p("damage") + absorbed * mult) * (1.0 + 0.2 * float(fz))
		empowered = emp
		w.area_hit(self, w.player_pos, r, dmg, 400.0 + 120.0 * float(fz), 0.5)
		empowered = false
		var yl := int(w.st("t_yuanzhuan"))                  # 太极圆转：化解后 3 秒移速 +10%/20%，10%/20% 几率清零冷却
		if yl > 0:
			w.tal_spd_t = 3.0
			w.tal_spd_v = 0.1 * float(yl)
			if w.rng.randf() < 0.1 * float(yl):
				guard_cd = 0.0
		if int(w.st("t_huigui")) > 0:                       # 回澜归海：累计化解 100 点后范围反震
			_acc += absorbed
			if _acc >= 100.0:
				w.area_hit(self, w.player_pos, 220.0, _acc * 1.5, 320.0, 0.4)
				w.add_fx("ring", w.player_pos, 0.5, {"r0": 20.0, "r1": 220.0, "color": GameWorld.JADE, "vfx": "ring_taiji" if w.vfx.has("ring_taiji") else ""})
				_acc = 0.0
		w.add_fx("ring", w.player_pos, 0.45, {"r0": 15.0, "r1": r, "color": GameWorld.JADE, "vfx": fxid("ring") if fxid("ring") != "" else "ring_taiji"})
		return amount - absorbed
