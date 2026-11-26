class_name SpearSkills
extends RefCounted
## 杨家将（长兵）的 9 个招式：枪路（灵动）4 个 + 棍路（刚猛）5 个。设计见 docs/design_spear.md。
## 流派机制在 GameWorld 里：枪势（靠移动）/ 棍势（近身命中、格挡）、枪尖、连击与枪影、格挡（初始 20%、上限 70%）、隐藏武功「无名枪法」的获得。


static func create(skill_id: String) -> SkillBase:
	match skill_id:
		"yangjia_spear": return Yangjia.new()
		"meihua_spear": return Meihua.new()
		"baima_spear": return Baima.new()
		"wuming_spear": return WuMing.new()
		"shaolin_staff": return Shaolin.new()
		"panlong_staff": return PanLong.new()
		"dagou_staff": return Dagou.new()
		"fengmo_staff": return Fengmo.new()
		"xiangmo_staff": return Xiangmo.new()
	push_error("未知杨家将招式: " + skill_id)
	return null


## 共用辅助：直线 / 扇形判定、枪势「游龙突」、棍势「横扫千军」
class Base extends SkillBase:
	## 沿一条线打击（枪）：按距离从近到远结算；枪尖（最远 35%）伤害 ×tip_mult 并露出破绽，近身（最近 35%）伤害 ×0.9
	func line_hit(origin: Vector2, dir: Vector2, length: float, width: float, dmg: float, knock: float, tip_mult: float = 1.45, force: bool = false) -> int:
		var cands: Array = []
		for e in w._query(origin + dir * length * 0.5, length * 0.5 + width + 40.0):
			if not e.alive:
				continue
			var rel := e.pos - origin
			var along := rel.dot(dir)
			if along < -e.radius or along > length + e.radius:
				continue
			if absf(rel.dot(dir.orthogonal())) > width * 0.5 + e.radius:
				continue
			cands.append([along, e])
		cands.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
		var n := 0
		for c in cands:
			var e: Enemy = c[1]
			var along: float = c[0]
			var tip := along >= length * (0.5 if w.st("ji_spear") > 0.0 else 0.65)
			var amt := dmg * ((tip_mult + w.st("tip_dmg")) if tip else (0.9 if along < length * 0.35 else 1.0))
			hit(e, amt, dir * knock, force)
			if tip:
				w.spear_tip_hit(e)
			n += 1
		return n

	func ray_fx(from: Vector2, to: Vector2, width: float, color: Color) -> void:
		w.add_fx("ray", from, 0.25, {"to": to, "width": width, "color": color})

	## 有素材就播特效条带（size = 世界里的边长，angle = 朝向）；没有素材返回 false，调用方画程序线条
	func vfx_at(id: String, pos: Vector2, size: float, angle: float = 0.0, life: float = 0.35) -> bool:
		if id == "" or not w.vfx.has(id):
			return false
		w.add_fx("ring", pos, life, {"r0": 10.0, "r1": 10.0, "color": Color.WHITE, "vfx": id, "size": size, "angle": angle})
		return true

	func beam_fx(id: String, from: Vector2, to: Vector2, width: float, color: Color, length_scale: float = 1.25) -> void:
		var d := to - from
		if not vfx_at(id, from + d * 0.5, d.length() * length_scale, d.angle(), 0.3):
			ray_fx(from, to, width, color)

	## 枪势满：下一枪变「游龙突」——原地向前刺出一道约 320 像素的枪龙（人不位移），贯穿一线所有敌人（×1.8、必暴击），0.45 秒无敌
	func breakthrough(dir: Vector2) -> bool:
		var wf := w.st("t_wanfa_gui") > 0.0                  # 万法归宗：任意枪 / 棍都能打出游龙突
		var free_qc := w.st("t_qiangchu") > 0.0 and w.spear_fire_n % 5 == 0 and str(def.get("route", "")) == "spear"      # 枪出如龙：每第 5 次枪路出手无需攒势
		if free_cast or (not wf and (str(def.get("route", "")) != "spear" or id == "wuming_spear")) or (w.spear_qs < 100.0 and not free_qc):
			return false
		if not free_qc:
			w.spear_qs = 50.0 if w.st("ji_spear") > 0.0 else 0.0
		w.huima_t = 3.0 if w.st("t_huima") > 0.0 else 0.0
		var dist := 320.0 * (1.0 + float(mods["range"])) * (1.0 + 0.15 * w.st("t_youlong"))
		w.invuln = maxf(w.invuln, 0.45)
		var start := w.player_pos
		line_hit(start, dir, dist, 64.0, p("damage") * 1.8, 120.0, 1.45, true)
		if not vfx_at("fx_youlong_dash", start + dir * dist * 0.5, dist * 1.35, dir.angle(), 0.45):
			ray_fx(start, start + dir * dist, 46.0, Color("#ffd878"))
		w.add_fx("text", w.player_pos + Vector2(0, -50), 0.9, {"text": "游龙突！", "size": 28, "color": Color("#ffd878")})
		w.shake = maxf(w.shake, 5.0)
		return true

	## 棍势满：下一击（棍或枪）变「横扫千军」——半径 ×2、伤害 ×2.5、必暴击、强击退，之后 0.5 秒格挡几率 +50%
	## 枪路也能打出：棍势靠近身命中 / 格挡 / 被近身攻击攒（不需要学棍法）
	func wide_sweep() -> bool:
		if free_cast or w.spear_gs < 100.0:
			return false
		w.spear_gs = (40.0 if w.st("ji_spear") > 0.0 else 0.0) + 15.0 * w.st("t_gunshi")            # 棍势满溢：横扫后再攒棍势
		if w.rng.randf() < 0.12 * w.st("t_liansao"):                                               # 连扫：保留一半棍势
			w.spear_gs = maxf(w.spear_gs, 50.0)
		var cap := w.st("t_hengsao_cap") > 0.0
		var r := (p("reach") if def.has("reach") else p("radius")) * 2.0 * (1.0 + w.st("sweep_r")) * (1.12 if cap else 1.0)
		w.spear_guard_t = 0.5
		w.cone_hit(self, w.player_pos, 0.0, PI, r, p("damage") * 2.5, p("knock") * 2.0 * (1.3 if cap else 1.0), true)
		for e in w._query(w.player_pos, r):
			if e.alive and e.pos.distance_to(w.player_pos) < r + e.radius:
				if w.st("t_pzg") > 0.0:                                                            # 破阵棍：降防
					e.def_down = maxf(e.def_down, 0.1 * w.st("t_pzg"))
					e.def_down_t = 3.0
				if cap and not e.is_boss:                                                          # 横扫天下：晕眩 0.8 秒
					e.stun = maxf(e.stun, 0.8)
		if w.st("t_hsyz") > 0.0:                                                                   # 横扫·余震：0.6 秒后再扫一次
			w.add_zone({"kind": "impact", "skill": self, "pos": w.player_pos, "r": r, "delay": 0.6, "t": 0.0, "dmg": p("damage") * (0.1 + 0.2 * w.st("t_hsyz")), "stun": 0.0, "crack": false, "elv": 0})
		if not vfx_at("fx_staff_wide", w.player_pos, r * 2.2, 0.0, 0.5):
			w.add_fx("ring", w.player_pos, 0.45, {"r0": 20.0, "r1": r, "color": Color("#ffd878")})
		w.add_fx("text", w.player_pos + Vector2(0, -50), 0.9, {"text": "横扫千军！", "size": 28, "color": Color("#ffd878")})
		w.shake = maxf(w.shake, 8.0)
		return true

	## 扇形结算（棍）：每个敌人单独命中，可附带定身 / 破绽
	func fan_hit(origin: Vector2, a: float, half_arc: float, reach: float, dmg: float, knock: float, stun_t: float = 0.0, vuln: float = 0.0, force: bool = false) -> int:
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
			hit(e, dmg, (to / d if d > 0.01 else Vector2.from_angle(a)) * knock, force)
			if stun_t > 0.0 and not e.is_boss:
				e.stun = maxf(e.stun, stun_t)
			if vuln > 0.0:
				w.apply_vuln(e, vuln)
			n += 1
		return n


## 杨家枪法（枪路起手）：超长直刺穿透，枪尖 +80%；出枪时原地不退（强化后才补一记回马枪）
class Yangjia extends Base:
	func fire() -> bool:
		var reach := p("reach")
		var t := w.nearest_enemy(reach + 40.0)
		if t == null:
			return false
		var dir := (t.pos - w.player_pos).normalized()
		if breakthrough(dir) or wide_sweep():
			return true
		var origin := w.player_pos
		beam_fx("fx_yangjia_thrust", origin, origin + dir * reach, 26.0, Color("#dfe8f5"))
		line_hit(origin, dir, reach, p("width"), p("damage"), p("knock"), float(def["tip"]), empowered)
		w.invuln = maxf(w.invuln, 0.2)
		if enhanced():                                       # 回马连环：对身后再补一枪
			line_hit(origin, -dir, reach * ev(0.5, 0.65, 0.8), p("width"), p("damage") * ev(0.6, 0.8, 1.0), p("knock"), 1.45, false)
			ray_fx(origin, origin - dir * reach * 0.6, 20.0, Color("#bfd0e8"))
		return true


## 梅花枪法：三（五）枪散开扇面，各自穿透
class Meihua extends Base:
	var _mh := 0

	func fire() -> bool:
		var reach := p("reach")
		var t := w.nearest_enemy(reach + 40.0)
		if t == null:
			return false
		var dir := (t.pos - w.player_pos).normalized()
		if breakthrough(dir) or wide_sweep():
			return true
		var n := int(p("count")) + (2 if enhanced() else 0)
		var dmg := p("damage") * (1.0 + (ev(0.1, 0.2, 0.3) if enhanced() else 0.0))
		vfx_at("fx_meihua_spear", t.pos, 190.0, 0.0, 0.35)
		_mh += 1
		var rain := int(w.st("t_meihuayu")) > 0 and _mh % 5 == 0             # 梅花雨：每第 5 次出枪变成环绕一圈（枪数 ×2）
		if rain:
			n *= 2
		for i in n:
			var d2 := dir.rotated((i - (n - 1) * 0.5) * float(def["spread"]))
			if rain:
				d2 = Vector2.from_angle(TAU * float(i) / float(n))
			ray_fx(w.player_pos, w.player_pos + d2 * reach, 14.0, Color("#f0c8c8"))
			line_hit(w.player_pos, d2, reach, p("width"), dmg, p("knock"), 1.45, empowered)
		return true


## 白马银枪：冲刺突刺，贯穿路径
class Baima extends Base:
	func fire() -> bool:
		var reach := p("reach") * (1.5 if empowered else 1.0)
		var t := w.nearest_enemy(reach + 120.0)
		if t == null:
			return false
		var dir := (t.pos - w.player_pos).normalized()
		if breakthrough(dir) or wide_sweep():
			return true
		var dist := clampf(w.player_pos.distance_to(t.pos) + 70.0, 120.0, reach)
		var start := w.player_pos
		w.invuln = maxf(w.invuln, 0.25)
		line_hit(start, dir, dist, p("width"), p("damage"), p("knock"), 1.2, false)
		w.player_pos += dir * dist
		beam_fx("fx_baima_dash", start, w.player_pos, 38.0, Color("#eaf2ff"), 1.4)
		if int(w.st("t_yiqi")) > 0:                            # 一骑绝尘：冲刺路径留下 2 秒枪痕
			for k in 4:
				w.add_zone({"kind": "crack", "skill": self, "pos": start + dir * dist * float(k) / 3.0, "r": 55.0, "t": 0.0, "life": 2.0, "tick": 0.0, "dmg": p("damage") * 0.25})
		if enhanced():                                       # 银龙探海：终点炸开一圈枪气
			var r := ev(110.0, 135.0, 160.0)
			w.area_hit(self, w.player_pos, r, p("damage") * ev(0.8, 1.0, 1.2), 200.0)
			w.add_fx("ring", w.player_pos, 0.35, {"r0": 12.0, "r1": r, "color": Color("#eaf2ff")})
		return true


## 无名枪法（隐藏武功）：单体破防——全游戏最高的单发伤害，无视 50% 防御并降低目标防御 30%，冷却固定 10 秒，每打出 10 下升一级（基础伤害 +20%/级）
class WuMing extends Base:
	var casts := 0
	var _last_reset := -99.0
	var _reset_cd := false

	func tick(dt: float) -> void:
		super.tick(dt)
		if _reset_cd:                      # 出手之后才会设置冷却，所以在这里把冷却清掉
			_reset_cd = false
			cd = 0.0
			cd_total = 0.0

	func lvl() -> int:
		return 1 + casts / 10

	func display_name() -> String:
		return "无名枪法%d" % lvl()

	func p(key: String) -> float:
		var v := super.p(key)
		if key == "damage":
			v *= 1.0 + 0.2 * float(lvl() - 1)
		return v

	func ignore_def() -> float:
		return clampf(0.5 + float(mods["pierce_def"]), 0.0, 0.9)

	## 目标优先级：Boss（大小 Boss）> 精英 > 其它；同级取最近
	func pick_target() -> Enemy:
		var reach := p("reach")
		var best: Enemy = null
		var best_score := -INF
		for e in w._query(w.player_pos, reach + 40.0):
			if not e.alive or e.is_prop:
				continue
			var d := e.pos.distance_to(w.player_pos)
			if d > reach + e.radius:
				continue
			var sc := (20000.0 if e.is_boss else (10000.0 if e.is_elite else 0.0)) - d
			if sc > best_score:
				best_score = sc
				best = e
		return best

	func fire() -> bool:
		var t := pick_target()
		if t == null:
			return false
		var dir := (t.pos - w.player_pos).normalized()
		beam_fx("fx_wuming_thrust", w.player_pos, t.pos, 30.0, Color("#ffd878"), 1.3)
		vfx_at("fx_wuming_hit", t.pos, 200.0, 0.0, 0.4)
		casts += 1
		t.def_down = 0.3
		t.def_down_t = 8.0 if w.st("t_fanpu") > 0.0 else 5.0                    # 返璞归真：防御削弱 8 秒
		var wmd := p("damage") * (1.0 + w.wm_boost) * (1.5 if (w.st("t_fanpu") > 0.0 and t.is_boss) else 1.0)       # 无名之名：击杀后下一发增伤；返璞归真：对 Boss ×1.5
		w.wm_boost = 0.0
		hit(t, wmd, dir * p("knock"), empowered)
		if float(mods["stun"]) > 0.0 and w.rng.randf() < float(mods["stun"]) and not t.is_boss:
			t.stun = maxf(t.stun, 1.0)
		if float(mods["vuln"]) > 0.0:
			w.apply_vuln(t, float(mods["vuln"]))
		if enhanced() and not t.alive and w.time - _last_reset >= ev(5.0, 4.0, 3.0):      # 无名之名：击杀重置自身冷却（5 / 4 / 3 秒内最多一次）
			_last_reset = w.time
			_reset_cd = true
			w.add_fx("text", w.player_pos + Vector2(0, -80), 0.9, {"text": "无名·冷却重置", "size": 22, "color": Color("#ffd878")})
		if casts % 10 == 0:
			w.add_fx("text", w.player_pos + Vector2(0, -60), 1.2, {"text": "无名枪法 %d 级" % lvl(), "size": 26, "color": Color("#ffd878")})
		w.shake = maxf(w.shake, 4.0)
		return true


## 少林棍法（棍路起手）：大扇形横扫，击退强、暴击率高；每第 3 下「力劈华山」
class Shaolin extends Base:
	var combo := 0

	func fire() -> bool:
		var reach := p("reach") * (1.4 if empowered else 1.0)
		var t := w.nearest_enemy(reach + 30.0)
		if t == null:
			return false
		var a := (t.pos - w.player_pos).angle()
		if wide_sweep():
			return true
		combo += 1
		var dakai := w.st("t_dakai") > 0.0                    # 大开大合·极：每第 2 下变 360° 横扫
		var third := combo % (2 if dakai else 3) == 0
		var full := third and (enhanced() or dakai)
		var arc := TAU if full else float(def["arc"])
		var dmg := p("damage") * (1.0 + ((ev(0.5, 0.7, 0.9) if enhanced() else 0.6) if third else 0.0))
		w.fx_slash(w.player_pos, a, reach, minf(arc, 3.4), third, fxid("slash"))
		fan_hit(w.player_pos, a, arc * 0.5, reach, dmg, p("knock") * (1.5 if third else 1.0), 0.0, 0.0, false)
		w.shake = maxf(w.shake, 3.0 if not third else 5.0)
		return true


## 蟠龙棍法：盘龙守势。守势期间格挡几率 +30%，每次成功格挡龙影自动反击
class PanLong extends Base:
	## 盘龙守势的光圈：缩成主角脚下一圈（压扁的椭圆、画在脚底），不再遮住主角
	func panlong_ring(life: float) -> bool:
		if not w.vfx.has("fx_panlong"):
			return false
		w.add_fx("ring", w.player_pos + Vector2(0, 14.0), life, {"r0": 10.0, "r1": 10.0, "color": Color.WHITE, "vfx": "fx_panlong", "size": 120.0, "yscale": 0.45})
		return true

	func fire() -> bool:
		if not w.any_enemy_within(w.player_pos, 300.0):
			return false
		w.panlong_t = p("stance") + (2.0 if empowered else 0.0)
		w.panlong_blocks = 0
		if not panlong_ring(0.5):
			w.add_fx("ring", w.player_pos, 0.5, {"r0": 20.0, "r1": 90.0, "color": Color("#9ab8c8")})
		w.add_fx("text", w.player_pos + Vector2(0, -50), 0.9, {"text": "盘龙守势", "size": 26, "color": Color("#9ab8c8")})
		return true

	## 守势中成功格挡：龙影对周围反击一击（范围伤害、击退、必暴击）
	func counter() -> void:
		var r := p("radius")
		w.area_hit_raw(w.player_pos, r, p("damage"), tags(), id, p("knock"), 0.0, false, true)
		w.add_fx("ring", w.player_pos, 0.35, {"r0": 15.0, "r1": r, "color": Color("#bfe0f0")})
		var ly := int(w.st("t_longying"))                        # 龙影追击：额外反击一次（60%/100%）
		if ly > 0:
			w.area_hit_raw(w.player_pos, r, p("damage") * (0.2 + 0.4 * float(ly)), tags(), id, p("knock"), 0.0, false, true)
		w.panlong_blocks += 1

	## 守势结束（龙腾九天）：格挡次数越多越重的一记重击
	func finale() -> void:
		if not enhanced() or w.panlong_blocks <= 0:
			return
		var r := p("radius") * 1.6 * (1.5 if w.st("t_longteng") > 0.0 else 1.0)
		var mult := 1.0 + float(w.panlong_blocks) * ev(0.25, 0.35, 0.45)
		w.area_hit_raw(w.player_pos, r, p("damage") * 1.5 * mult, tags(), id, 320.0, 0.0, false, true)
		w.add_fx("ring", w.player_pos, 0.5, {"r0": 20.0, "r1": r, "color": Color("#ffd878")})
		w.add_fx("text", w.player_pos + Vector2(0, -60), 1.0, {"text": "龙腾九天！", "size": 28, "color": Color("#ffd878")})
		w.shake = maxf(w.shake, 8.0)


## 翠竹巧拨棒：点地绊腿，扇形内敌人被绊倒（定身）并露出破绽
class Dagou extends Base:
	func fire() -> bool:
		var reach := p("reach")
		var t := w.nearest_enemy(reach + 30.0)
		if t == null:
			return false
		var a := (t.pos - w.player_pos).angle()
		if wide_sweep():
			return true
		var st := p("stun") * (ev(1.3, 1.5, 1.7) if enhanced() else 1.0) * (2.0 if empowered else 1.0)
		w.fx_slash(w.player_pos, a, reach, float(def["arc"]), false, fxid("slash"))
		fan_hit(w.player_pos, a, float(def["arc"]) * 0.5, reach, p("damage"), p("knock"), st, 0.2, false)
		if int(w.st("t_dagouzhen")) > 0:                       # 打狗阵：身周一圈再绊一次
			for e in w._query(w.player_pos, reach * 0.9):
				if e.alive and not e.is_boss and e.pos.distance_to(w.player_pos) < reach * 0.9 + e.radius:
					e.stun = maxf(e.stun, st * 0.7)
			w.add_fx("ring", w.player_pos, 0.35, {"r0": 15.0, "r1": reach * 0.9, "color": Color("#9ad8a0")})
		return true


## 怒涛狂澜杖：原地旋转，连续横扫并推开敌人
class Fengmo extends Base:
	var spin_left := 0.0
	var tick_t := 0.0

	func fire() -> bool:
		if not w.any_enemy_within(w.player_pos, p("radius") + 80.0):
			return false
		if wide_sweep():
			return true
		spin_left = p("spin") + (1.0 if empowered else 0.0)
		tick_t = 0.0
		return true

	func tick(dt: float) -> void:
		if spin_left > 0.0:
			spin_left -= dt
			tick_t -= dt
			if tick_t <= 0.0:
				tick_t = float(def["tick"])
				_spin_hit()
			if spin_left <= 0.0 and (enhanced() or int(w.st("t_moyin")) > 0):              # 魔音绕梁：旋转结束再震出一圈（魔音：+40%/80%）
				var r := p("radius") * (ev(1.4, 1.6, 1.8) if enhanced() else 1.4)
				w.area_hit_raw(w.player_pos, r, p("damage") * (ev(1.5, 2.0, 2.5) if enhanced() else 1.0) * (1.0 + 0.4 * w.st("t_moyin")), tags(), id, 260.0, 0.0, false, false)
				w.add_fx("ring", w.player_pos, 0.4, {"r0": 15.0, "r1": r, "color": Color("#ffd878")})
		super.tick(dt)

	func _spin_hit() -> void:
		var r := p("radius")
		if int(w.st("t_fengmo")) > 0:                        # 风魔·极：把近身敌人向中心吸拢
			for e0 in w._query(w.player_pos, r * 1.3):
				if e0.alive and not e0.is_boss and not e0.is_prop:
					var to0 := w.player_pos - e0.pos
					if to0.length() > 30.0:
						e0.pos += to0.normalized() * 36.0
		var near := 0
		for e in w._query(w.player_pos, r):
			if e.alive and e.pos.distance_to(w.player_pos) < r + e.radius:
				near += 1
		var mult := 1.0 + 0.05 * float(mini(near, 10))
		if not vfx_at("fx_fengmo", w.player_pos, r * 2.4, 0.0, 0.3):
			w.fx_slash(w.player_pos, w.time * 14.0, r, 3.0, false, "")
		w.area_hit_raw(w.player_pos, r, p("damage") * mult, tags(), id, p("knock"), 0.0, false, false)


## 定海铁杖：蓄力重击，落点大范围冲击并击晕；身边近身敌人越多越痛
class Xiangmo extends Base:
	var _cdr := 0.0

	func tick(dt: float) -> void:
		if _cdr > 0.0:
			cd = maxf(0.0, cd - _cdr)
			_cdr = 0.0
		super.tick(dt)

	func fire() -> bool:
		var t := w.nearest_enemy(p("reach"))
		if t == null:
			return false
		if wide_sweep():
			return true
		var near := 0
		for e in w._query(w.player_pos, 140.0):
			if e.alive and e.pos.distance_to(w.player_pos) < 140.0:
				near += 1
		var mult := 1.0 + 0.08 * float(mini(near, 10))
		var r := p("radius") * (1.5 if empowered else 1.0)
		var center := t.pos
		var rings: Array = [1.0]
		if enhanced():
			rings = [0.6, 1.0, 1.4]
		for i in rings.size():
			var rr: float = r * float(rings[i])
			var amt := p("damage") * mult * (ev(0.5, 0.6, 0.7) if enhanced() else 1.0)
			w.area_hit_raw(center, rr, amt, tags(), id, p("knock"), 0.0, false, empowered)
			if not vfx_at("fx_xiangmo", center, rr * 2.3, 0.0, 0.4 + 0.08 * i):
				w.add_fx("ring", center, 0.35 + 0.08 * i, {"r0": 12.0, "r1": rr, "color": Color("#ffd878")})
		var hit_n := 0
		for e in w._query(center, r):                           # 击晕
			if e.alive and not e.is_boss and e.pos.distance_to(center) < r + e.radius:
				e.stun = maxf(e.stun, p("stun") * (2.0 if empowered else 1.0))
			if e.alive and e.pos.distance_to(center) < r + e.radius:
				hit_n += 1
		if int(w.st("t_jingangz")) > 0:                         # 金刚震地·极：每命中一个敌人，下次冷却 −0.3 秒（最多 2 秒）
			_cdr = minf(2.0, 0.3 * float(hit_n))
		w.shake = maxf(w.shake, 9.0)
		return true
