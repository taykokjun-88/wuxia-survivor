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


## 降龙十八掌：贯穿掌风。强化「龙战于野」：首次命中后分裂成两道小掌风。
class YuePalm extends SkillBase:
	func fire() -> bool:
		var t := w.nearest_enemy(p("speed") * p("life"))
		if t == null:
			return false
		var a := (t.pos - w.player_pos).angle()
		var o := {"split": int(ev(2, 3, 4)) if enhanced() else 0}
		if empowered:    # 催动：龙形掌风
			o["radius"] = p("radius") * 1.8
			o["pierce"] = p("pierce") + 3.0
		w.spawn_proj(self, a, o)
		return true


## 太祖长拳：近身三连击。强化「横扫千军」：第三拳必暴击并释放冲击波。
class ChainFist extends SkillBase:
	var combo := 0

	func fire() -> bool:
		var reach := p("reach")
		var t := w.nearest_enemy(reach + 30.0)
		if t == null:
			return false
		var a := (t.pos - w.player_pos).angle()
		combo += 1
		var third := combo % 3 == 0 or empowered
		var base := p("damage") * (2.2 if third else 1.0)
		var knock := 320.0 if third else 160.0
		w.fx_slash(w.player_pos, a, reach, p("arc"), third, fxid("slash"))
		w.cone_hit(self, w.player_pos, a, p("arc") * 0.5, reach, base, knock, third and enhanced())
		if empowered:    # 催动：末拳震晕前方敌人
			w.area_hit(self, w.player_pos + Vector2.from_angle(a) * reach * 0.6, 70.0, base * 0.4, 0.0, 0.8)
		if third and enhanced():
			var sr := ev(140.0, 170.0, 200.0)
			w.area_hit(self, w.player_pos, sr, p("damage") * ev(1.2, 1.6, 2.0), 300.0)
			w.add_fx("ring", w.player_pos, 0.35, {"r0": 20.0, "r1": sr, "color": GameWorld.GOLD})
		return true


## 七伤拳：延迟落点的范围击晕。强化「七伤暗劲」：落点留下 3 秒的裂痕。
class QuakeFist extends SkillBase:
	func fire() -> bool:
		var t := w.nearest_enemy(p("range"))
		if t == null:
			return false
		var z := {
			"kind": "impact", "skill": self, "pos": t.pos, "r": p("radius"),
			"delay": 0.35, "t": 0.0, "dmg": p("damage"), "stun": p("stun"), "crack": enhanced(), "elv": elv(),
		}
		w.add_zone(z)
		if empowered:    # 催动：落点追加一圈更大的冲击波
			var z2 := z.duplicate()
			z2["r"] = float(z["r"]) * 1.6
			z2["delay"] = 0.6
			z2["dmg"] = float(z["dmg"]) * 0.6
			z2["crack"] = false
			w.add_zone(z2)
		return true


## 落英神剑掌：环身掌风。强化「落英缤纷」：掌风过后身周旋涡收束，再轰一次（不再吸拢敌人）。
class WhirlPalm extends SkillBase:
	func fire() -> bool:
		var r := p("radius") * (1.5 if empowered else 1.0)
		if not w.any_enemy_within(w.player_pos, r + 20.0):
			return false
		# 内力越满，连发的圈数越多（最多 3 圈，由小到大）；多圈时每圈伤害 ×0.6
		var frac := w.neili / maxf(1.0, w.st("max_neili"))
		var n := clampi(1 + int(frac * 3.0), 1, 3)
		var radii: Array = {1: [1.0], 2: [0.7, 1.0], 3: [0.5, 0.75, 1.0]}[n]
		for i in radii.size():
			var rr: float = r * float(radii[i])
			var last: bool = i == radii.size() - 1
			w.area_hit(self, w.player_pos, rr, p("damage") * (1.0 if n == 1 else 0.6), p("knock") * (2.0 if empowered else 1.0) if last else 0.0)
			w.add_fx("ring", w.player_pos, 0.3 + 0.08 * i, {"r0": 15.0, "r1": rr, "color": GameWorld.INK, "vfx": fxid("ring") if fxid("ring") != "" else "burst_wind"})
		if enhanced():
			w.add_zone({"kind": "vortex", "skill": self, "dmg": p("damage") * ev(1.2, 1.6, 2.0), "r": r * ev(1.8, 2.1, 2.4),
				"t": 0.0, "life": 0.9})
		return true


## 一阳指：定身。强化「一阳连环」：被点穴的敌人死亡时爆炸并定身周围敌人。
class PointFinger extends SkillBase:
	func fire() -> bool:
		var reach := p("speed") * p("life")
		var targets := w.nearest_n(reach, int(p("count")))
		if targets.is_empty():
			return false
		for t in targets:
			var a := (t.pos - w.player_pos).angle()
			w.spawn_proj(self, a, {"stun": p("stun") * (2.0 if empowered else 1.0), "chain": enhanced()})
		return true


## 大金刚拳：消耗内力的重击，内力越满越痛。强化「金刚不坏」：内力 ≥90% 时不耗内力并获得护盾。
class VajraFist extends SkillBase:
	func fire() -> bool:
		var reach := p("reach")
		var t := w.nearest_enemy(reach + 30.0)
		if t == null:
			return false
		var max_n := float(w.stats["max_neili"])
		var ratio := 1.0 if empowered else w.neili / max_n
		var mult := 0.8 + 1.2 * ratio
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
		w.cone_hit(self, w.player_pos, a, p("arc") * 0.5, reach, p("damage") * mult, p("knock"), false)
		return true


## 天山六阳掌：追踪掌印。强化「六阳回环」：掌印飞出后折返，可再次命中。
class CloudPalm extends SkillBase:
	func fire() -> bool:
		var t := w.nearest_enemy(520.0)
		if t == null:
			return false
		var n := int(p("count")) + (1 if empowered else 0)
		var base := (t.pos - w.player_pos).angle()
		for i in n:
			var a := base + (i - (n - 1) * 0.5) * 0.5
			w.spawn_proj(self, a, {"homing": true, "turn": p("turn"), "boomerang": enhanced()})
		return true


## 八荒六合功：八方拳气（基础 8 个，催动 12 个）。强化「唯我独尊」：连发三轮，每轮偏转，形成旋转弹幕。
class EightWaste extends SkillBase:
	var bursts_left := 0
	var burst_t := 0.0
	var rot := 0.0
	var emp_burst := false

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
			w.add_fx("ring", w.player_pos, 0.4, {"r0": 30.0, "r1": 150.0, "color": GameWorld.GOLD, "vfx": fxid("muzzle"), "size": 240.0})
		var n := int(p("count")) + (4 if emp_burst else 0)
		for i in n:
			w.spawn_proj(self, rot + TAU * i / n)
		rot += 0.3 if enhanced() else 0.2


## 乾坤大挪移：受击时化解部分伤害并反击；平时周身有微弱劲气。强化「颠倒乾坤」：化解的伤害 ×4 转为反击。
class Taiji extends SkillBase:
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
		var absorbed := amount * p("absorb")
		var r := p("radius") * (ev(1.5, 1.7, 1.9) if enhanced() else 1.0)
		var mult := ev(4.0, 6.0, 8.0) if enhanced() else 1.0
		if emp:
			mult = maxf(mult * 1.5, 3.0)
		var dmg := p("damage") + absorbed * mult
		empowered = emp
		w.area_hit(self, w.player_pos, r, dmg, 400.0, 0.5)
		empowered = false
		w.add_fx("ring", w.player_pos, 0.45, {"r0": 15.0, "r1": r, "color": GameWorld.JADE, "vfx": fxid("ring") if fxid("ring") != "" else "ring_taiji"})
		return amount - absorbed
