class_name BladeSkills
extends RefCounted
## 刀客流派的 9 个刀法。每个招式的「专属强化」在 enhanced() / ev() 分支里实现。
## 流派机制在 GameWorld 里：刀魂（add_soul / blade_dmg / blade_range / 霸刀破岳）、撕裂（apply_bleed / bleed_burst）。
## 设计见 docs/design_blade.md。


static func create(skill_id: String) -> SkillBase:
	match skill_id:
		"wuhu_blade": return WuHu.new()
		"kuangfeng_blade": return KuangFeng.new()
		"hujia_blade": return HuJia.new()
		"ranmu_blade": return RanMu.new()
		"xuedao": return XueDao.new()
		"fanliangyi": return FanLiangYi.new()
		"xuanxu_blade": return XuanXu.new()
		"yuanyang_blade": return YuanYang.new()
		"tulong_art": return TuLong.new()
	push_error("未知刀客招式: " + skill_id)
	return null


## 刀客招式的共用辅助：扇形 / 圆形判定（逐个敌人结算，方便叠撕裂）
class Base extends SkillBase:
	func rmul() -> float:
		return w.blade_range()

	## 耗血刀法：出手时消耗一部分最大气血（不会把自己耗死，免费释放不耗）；自己耗掉的血同样涨刀魂，让霸刀破岳更容易触发
	func pay_hp() -> void:
		var frac := float(def.get("hp_cost", 0.0))
		if frac <= 0.0 or free_cast:
			return
		var max_hp := w.st("max_hp")
		var paid := minf(max_hp * frac * (0.5 if w.st("ji_blade") > 0.0 else 1.0), maxf(0.0, w.hp - 1.0))
		if paid <= 0.0:
			return
		if w.tb_t <= 0.0:                    # 真·霸刀破岳期间不真的扣血，刀魂照涨（按本该耗的血算）
			w.hp -= paid
		w.add_soul(minf(Data.T("blade_soul_hp_cap"), Data.T("blade_soul_hp") * paid / maxf(1.0, max_hp) * 100.0))
		if w.tb_t <= 0.0:
			w.add_fx("text", w.player_pos + Vector2(0, -34), 0.6, {"text": "-%d" % int(paid), "size": 16, "color": GameWorld.VERMILION})

	func _foe(e: Enemy, dmg: float, out: Vector2, stacks: int, force: bool) -> void:
		if bool(def.get("heavy", false)):
			w.bleed_burst(e)
		var amt := hit(e, dmg, out, force)
		if stacks > 0:
			w.apply_bleed(e, stacks, amt)

	func cone(origin: Vector2, a: float, half_arc: float, reach: float, dmg: float, knock: float, stacks: int = 0, force: bool = false) -> int:
		var n := 0
		for e in w._query(origin, reach):
			if not e.alive:
				continue
			var to := e.pos - origin
			var d := to.length()
			if d >= reach + e.radius:
				continue
			if d > 20.0 and absf(wrapf(to.angle() - a, -PI, PI)) > half_arc + 0.15:
				continue
			_foe(e, dmg, (to / d if d > 0.01 else Vector2.from_angle(a)) * knock, stacks, force)
			n += 1
		return n

	func ring_hit(center: Vector2, r: float, dmg: float, knock: float, stacks: int = 0) -> int:
		var n := 0
		for e in w._query(center, r):
			if not e.alive:
				continue
			var to := e.pos - center
			var d := to.length()
			if d >= r + e.radius:
				continue
			_foe(e, dmg, (to / d if d > 0.01 else Vector2.RIGHT) * knock, stacks, false)
			n += 1
		return n


## 五虎断门刀：宽扇重劈。强化「猛虎下山」：每第 3 刀变成 360° 横扫，对流血的敌人必定暴击。
class WuHu extends Base:
	var combo := 0

	func hit_crit(e: Enemy) -> bool:
		return enhanced() and e.bleed_stacks > 0

	func fire() -> bool:
		var reach := p("reach") * rmul() * (1.4 if empowered else 1.0)
		var t := w.nearest_enemy(reach + 30.0)
		if t == null:
			return false
		var a := (t.pos - w.player_pos).angle()
		combo += 1
		var sweep := enhanced() and combo % 3 == 0
		var arc := TAU if sweep else p("arc")
		var dmg := p("damage") * (1.0 + (ev(0.4, 0.8, 1.2) if sweep else 0.0))
		w.fx_slash(w.player_pos, a, reach, minf(arc, 3.4), true, fxid("slash"))
		cone(w.player_pos, a, arc * 0.5, reach, dmg, p("knock"), 1)
		if empowered:
			w.spawn_proj(self, a, {"speed": 480.0, "radius": 24.0, "life": 0.5, "pierce": 3, "knock": 80.0, "damage": p("damage") * 0.6, "bleed": 1.0})
		w.shake = maxf(w.shake, 3.0)
		return true


## 狂风刀法：近身快刀，一前一后两道刀弧。强化「风卷残云」：4 连斩，命中回内力。
class KuangFeng extends Base:
	func p(key: String) -> float:
		var v := super.p(key)
		if key == "cooldown":
			v /= 1.0 + 0.5 * maxf(0.0, w.st("speed_pct"))        # 跑得越快出刀越快
		return v

	func fire() -> bool:
		var reach := p("reach") * rmul() * (1.0 + (ev(0.25, 0.5, 0.75) if enhanced() else 0.0))
		var t := w.nearest_enemy(reach + 30.0)
		if t == null:
			return false
		var a := (t.pos - w.player_pos).angle()
		var angs := [a, a + PI, a + PI * 0.5, a - PI * 0.5]
		var n := 4 if enhanced() else 2
		var hits := 0
		for i in n:
			var ang: float = angs[i]
			w.fx_slash(w.player_pos, ang, reach, p("arc"), false, fxid("slash"))
			hits += cone(w.player_pos, ang, p("arc") * 0.5, reach, p("damage"), p("knock"))
		if enhanced() and hits > 0:
			w.add_neili(minf(6.0, float(hits)))
		if empowered:                                      # 刀卷残云：把周围的小怪向刀锋拉拢
			for e in w._query(w.player_pos, reach * 1.8):
				if e.alive and not e.is_boss and not e.is_prop:
					e.knock += (w.player_pos - e.pos).normalized() * 260.0
		return true


## 胡家刀法：弯月刀气，穿透多人；近处伤害更高并露出破绽。强化「八方藏刀式」：两侧分出次级刀气。
class HuJia extends Base:
	func hit_mult(e: Enemy) -> float:
		return 1.35 if e.pos.distance_to(w.player_pos) < 100.0 else 1.0

	func fire() -> bool:
		var reach := p("speed") * p("life") * rmul()
		var t := w.nearest_enemy(reach)
		if t == null:
			return false
		var a := (t.pos - w.player_pos).angle()
		var o := {"pierce": int(p("pierce")) + (3 if empowered else 0), "radius": p("radius") * (1.5 if empowered else 1.0), "vuln": 0.15}
		w.spawn_proj(self, a, o)
		if enhanced():
			var n := int(ev(2, 3, 4))
			for i in n:
				var off := (float(i) - (n - 1) * 0.5) * 0.5 + (0.25 if n % 2 == 0 else 0.0)
				w.spawn_proj(self, a + off, {"pierce": 2, "radius": p("radius") * 0.7, "damage": p("damage") * 0.5, "life": p("life") * 0.8})
		return true


## 燃木刀法：火焰刀浪 + 地面火海。强化「乾柴烈火」：被灼烧的敌人死亡时爆炸。
class RanMu extends Base:
	func fire() -> bool:
		var reach := p("reach") * rmul()
		var t := w.nearest_enemy(reach + 40.0)
		if t == null:
			return false
		var a := (t.pos - w.player_pos).angle()
		w.fx_slash(w.player_pos, a, reach, p("arc"), true, fxid("slash"))
		cone(w.player_pos, a, p("arc") * 0.5, reach, p("damage"), p("knock"))
		var r := p("zone_r") * (1.6 if empowered else 1.0)
		var z := {"kind": "fire", "skill": self, "pos": w.player_pos + Vector2.from_angle(a) * reach * 0.7, "r": r,
			"t": 0.0, "life": p("zone_life"), "tick": 0.0, "dmg": p("damage") * 0.35}
		if enhanced():
			z["burst"] = true
			z["burst_r"] = ev(70.0, 95.0, 120.0)
			z["burst_dmg"] = p("damage") * ev(1.5, 2.0, 2.5)
		w.add_zone(z)
		pay_hp()
		return true


## 血刀经：消耗气血斩出血刃，气血越低越痛；命中叠撕裂、回血。强化「血魔不死」：低血时冷却减半且不耗血。
class XueDao extends Base:
	func _low() -> bool:
		return enhanced() and w.hp < w.st("max_hp") * 0.4

	func p(key: String) -> float:
		var v := super.p(key)
		if key == "cooldown" and _low():
			v *= 0.5
		return v

	func fire() -> bool:
		var reach := p("reach") * rmul()
		var t := w.nearest_enemy(reach + 30.0)
		if t == null:
			return false
		var a := (t.pos - w.player_pos).angle()
		var max_hp := w.st("max_hp")
		var frac := clampf(w.hp / maxf(1.0, max_hp), 0.0, 1.0)
		var dmg := p("damage") * (1.0 + 0.9 * (1.0 - frac))
		if not _low():                                      # 耗血，但不会把自己耗死
			pay_hp()
		var dirs := [a, a + PI * 0.5, a + PI, a - PI * 0.5] if empowered else [a]
		var hits := 0
		for ang: float in dirs:
			w.fx_slash(w.player_pos, ang, reach, p("arc"), true, fxid("slash"))
			hits += cone(w.player_pos, ang, p("arc") * 0.5, reach, dmg, p("knock"), 1)
		var cap := ev(1.0, 1.5, 2.0) if enhanced() else 1.0
		var hm := w.heal_mult()
		var heal := minf(cap * (2.0 if empowered else 1.0) * hm, float(hits) * float(def.get("heal_hit", 0.002)) * dmg * (2.0 if empowered else 1.0) * hm)
		w.hp = minf(max_hp, w.hp + heal)
		return true


## 反两仪刀法：阴阳刀轮，抹弹幕、弹开敌人、叠撕裂。强化「混沌倒悬」：刀轮期间减伤并把所受伤害反弹。
class FanLiangYi extends Base:
	var wheel_t := 0.0
	var wheel_acc := 0.0
	var wheel_r := 0.0
	var wheel_emp := false

	func tick(dt: float) -> void:
		if wheel_t > 0.0:
			wheel_t -= dt
			wheel_acc -= dt
			if wheel_acc <= 0.0 and wheel_t > 0.0:
				wheel_acc = 0.3
				_pulse(false)
			if wheel_t <= 0.0 and wheel_emp:                # 两仪化四象：刀轮结束后射出 4 柄旋转飞刀
				wheel_emp = false
				var base := w.facing.angle()
				for i in 4:
					w.spawn_proj(self, base + i * PI * 0.5, {"speed": 460.0, "radius": 16.0, "life": 0.55, "pierce": 3, "knock": 60.0, "damage": p("damage") * 0.8, "pos": w.player_pos})
		super.tick(dt)

	func _clear_shots() -> void:
		for pr in w.projs:
			if pr.hostile and pr.pos.distance_to(w.player_pos) < wheel_r:
				pr.life = 0.0

	func _pulse(first: bool) -> void:
		_clear_shots()
		if first:
			ring_hit(w.player_pos, wheel_r, p("damage"), p("knock"), 2)
		else:
			ring_hit(w.player_pos, wheel_r, p("damage") * 0.35, p("knock") * 0.4, 0)
		w.add_fx("ring", w.player_pos, 0.35, {"r0": wheel_r * 0.6, "r1": wheel_r, "color": Color("#e8e0c8"), "vfx": fxid("ring"), "size": wheel_r * 2.2})

	func fire() -> bool:
		var r := p("radius") * rmul()
		var near_shot := false
		for pr in w.projs:
			if pr.hostile and pr.pos.distance_to(w.player_pos) < r + 60.0:
				near_shot = true
				break
		if not w.any_enemy_within(w.player_pos, r + 20.0) and not near_shot:
			return false
		wheel_r = r
		wheel_t = p("wheel_t")
		wheel_acc = 0.3
		wheel_emp = empowered
		_pulse(true)
		return true

	func on_hurt(amount: float) -> float:
		if wheel_t <= 0.0 or not enhanced():
			return amount
		var dmg := amount * (1.0 - ev(0.25, 0.35, 0.45))
		w.area_hit_raw(w.player_pos, wheel_r, dmg, [], id, 120.0)
		return dmg


## 玄虚刀法：震地裂痕，震晕路径上的敌人。强化「开山裂石」：对被震晕的敌人处决伤害。
class XuanXu extends Base:
	func hit_mult(e: Enemy) -> float:
		return ev(1.8, 2.2, 2.6) if (enhanced() and e.stun > 0.0) else 1.0

	func fire() -> bool:
		var reach := p("speed") * p("life") * rmul()
		var t := w.nearest_enemy(reach)
		if t == null:
			return false
		var a := (t.pos - w.player_pos).angle()
		var n := 5 if empowered else int(p("count"))
		for i in n:
			w.spawn_proj(self, a + (float(i) - (n - 1) * 0.5) * 0.3, {"stun": p("stun")})
		w.shake = maxf(w.shake, 4.0)
		pay_hp()
		return true


## 鸳鸯双刀：一长一短两柄飞刀回旋。长刀减速，短刀撕裂。强化「仁义无双」：被两刀都命中过的敌人必暴击并受更多伤害。
class YuanYang extends Base:
	func hit_crit(e: Enemy) -> bool:
		return enhanced() and e.slow_t > 0.0 and e.bleed_stacks > 0

	func hit_mult(e: Enemy) -> float:
		return ev(1.2, 1.4, 1.6) if (enhanced() and e.slow_t > 0.0 and e.bleed_stacks > 0) else 1.0

	func fire() -> bool:
		var reach := p("speed") * p("life") * rmul()
		var t := w.nearest_enemy(reach + 80.0)
		if t == null:
			return false
		var a := (t.pos - w.player_pos).angle()
		var pairs := int(p("count"))
		for k in pairs:
			var base := a + (float(k) - (pairs - 1) * 0.5) * 0.5
			w.spawn_proj(self, base + 0.9, {"boomerang": true, "slowv": 0.3})                  # 长刀：减速
			w.spawn_proj(self, base - 0.9, {"boomerang": true, "bleed": 1.0, "radius": p("radius") * 0.85})   # 短刀：撕裂
		w.add_fx("ring", w.player_pos, 0.5, {"r0": 40.0, "r1": 140.0, "color": Color("#f0c050"), "vfx": fxid("ring"), "size": 300.0})
		if empowered:                                       # 双宿双飞：两刀交汇时爆开刀花
			w.add_zone({"kind": "impact", "skill": self, "pos": w.player_pos, "r": 120.0, "delay": 0.65, "dmg": p("damage") * 1.2, "stun": 0.0, "crack": false, "elv": 0})
		return true


## 屠龙刀法：巨刀虚影砸落，击碎护盾、全场减速。强化「号令天下」：真气爆发 / 霸刀破岳时自动免费再来一次。
class TuLong extends Base:
	func shield_mult() -> float:
		return 3.0

	func _cast(mult: float, emp: bool) -> void:
		var r := p("radius") * rmul()
		var d := 0.45
		w.add_zone({"kind": "impact", "skill": self, "pos": w.player_pos, "r": r, "delay": d, "dmg": p("damage") * mult, "stun": 0.0, "crack": false, "elv": 0})
		if emp:                                             # 莫敢不从：刀龙环绕，再清一次场
			w.add_zone({"kind": "impact", "skill": self, "pos": w.player_pos, "r": r * 0.85, "delay": 1.1, "dmg": p("damage") * mult * 0.6, "stun": 0.0, "crack": false, "elv": 0})
		for e in w._query(w.player_pos, r):
			if e.alive and not e.is_prop:
				w.slow_enemy(e, float(def.get("slow", 0.7)), float(def.get("slow_t", 2.5)))
		w.shake = maxf(w.shake, 6.0)

	func fire() -> bool:
		if not w.any_enemy_within(w.player_pos, p("radius") * rmul() * 0.9):
			return false
		_cast(1.0, empowered)
		pay_hp()
		return true

	func _free() -> void:
		if not enhanced():
			return
		free_cast = true
		_cast(ev(1.0, 1.25, 1.5), false)
		free_cast = false

	func on_burst() -> void:
		_free()

	func on_baodao() -> void:
		_free()
