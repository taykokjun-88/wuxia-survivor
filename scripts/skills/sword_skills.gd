class_name SwordSkills
extends RefCounted
## 剑客流派的 9 个攻击技能 + 独孤九剑。每个技能的"专属强化"在 enhanced() 分支里实现。
## 独孤九剑是特殊路线：不学其他招式，只领悟「式」（见 GameWorld.shi），多个式的效果同时生效。

const SWORD_BLUE := Color("#8ab4d8")


static func create(skill_id: String) -> SkillBase:
	match skill_id:
		"kuang_feng": return KuangFeng.new()
		"qingsong": return QingSong.new()
		"zhongjian": return ZhongJian.new()
		"taiji_sword": return TaijiSword.new()
		"wanjian": return WanJian.new()
		"yunv": return YuNv.new()
		"pixie": return PiXie.new()
		"jinshe": return JinShe.new()
		"yitian": return YiTian.new()
		"dugu": return Dugu.new()
	push_error("未知剑客招式: " + skill_id)
	return null


## 狂风快剑：近身快剑。强化「风卷残云」：每第四剑的风刃贯穿并回血。
class KuangFeng extends SkillBase:
	var combo := 0

	func fire() -> bool:
		var reach := p("reach")
		var t := w.nearest_enemy(reach + 30.0)
		if t == null:
			return false
		var a := (t.pos - w.player_pos).angle()
		combo += 1
		w.fx_slash(w.player_pos, a, reach, p("arc"), false)
		w.cone_hit(self, w.player_pos, a, p("arc") * 0.5, reach, p("damage"), 90.0, false)
		if empowered:
			w.cone_hit(self, w.player_pos, a, p("arc") * 0.5, reach, p("damage") * 0.8, 60.0, false)
		if combo % 4 == 0:
			var o := {"speed": 460.0, "radius": 22.0, "life": 0.55, "knock": 140.0,
				"pierce": int(ev(3, 4, 5)) if enhanced() else 1, "damage": p("damage") * (1.6 + 0.2 * elv())}
			w.spawn_proj(self, a, o)
			if enhanced():
				w.hp = minf(w.st("max_hp"), w.hp + ev(1.0, 1.5, 2.0))
		return true


## 青松剑法：稳健的连刺。每第三剑「松涛」更宽更重。强化「松涛阵阵」：松涛同时射出扇形剑气。
class QingSong extends SkillBase:
	var combo := 0

	func fire() -> bool:
		var reach := p("reach")
		var t := w.nearest_enemy(reach + 30.0)
		if t == null:
			return false
		var a := (t.pos - w.player_pos).angle()
		combo += 1
		var wave := combo % 3 == 0 or empowered
		var arc := p("arc") * (2.2 if wave else 1.0)
		w.fx_slash(w.player_pos, a, reach, arc, wave)
		w.cone_hit(self, w.player_pos, a, arc * 0.5, reach, p("damage") * (1.7 if wave else 1.0), p("knock") * (1.6 if wave else 1.0), false)
		if wave and enhanced():
			var n := int(ev(3, 4, 5))
			for i in n:
				w.spawn_proj(self, a + (i - (n - 1) * 0.5) * 0.2, {"speed": 520.0, "radius": 10.0, "life": 0.6, "pierce": 2,
					"knock": 60.0, "damage": p("damage") * ev(0.6, 0.8, 1.0)})
		return true


## 玄铁重剑：缓慢而沉重。强化「无锋大巧」：落地冲击波并击晕。
class ZhongJian extends SkillBase:
	func fire() -> bool:
		var reach := p("reach")
		var t := w.nearest_enemy(reach + 30.0)
		if t == null:
			return false
		var a := (t.pos - w.player_pos).angle()
		w.fx_slash(w.player_pos, a, reach, p("arc"), true)
		w.cone_hit(self, w.player_pos, a, p("arc") * 0.5, reach, p("damage"), p("knock"), empowered)
		w.shake = maxf(w.shake, 4.0)
		if enhanced():
			var sr := ev(110.0, 140.0, 170.0)
			w.area_hit(self, w.player_pos + Vector2.from_angle(a) * reach * 0.6, sr, p("damage") * ev(0.6, 0.8, 1.0), 260.0, 0.8)
			w.add_fx("ring", w.player_pos + Vector2.from_angle(a) * reach * 0.6, 0.35, {"r0": 15.0, "r1": sr, "color": GameWorld.INK})
		return true


## 太极剑：周身圆弧，抹去敌方弹幕。强化「四两拨千斤」：每抹去一枚弹幕，这一剑伤害提高。
class TaijiSword extends SkillBase:
	func _hostile_near(r: float) -> Array[Projectile]:
		var out: Array[Projectile] = []
		for pr in w.projs:
			if pr.hostile and pr.pos.distance_to(w.player_pos) < r:
				out.append(pr)
		return out

	func fire() -> bool:
		var r := p("radius") * (1.4 if empowered else 1.0)
		var hostile := _hostile_near(r)
		if not w.any_enemy_within(w.player_pos, r + 20.0) and hostile.is_empty():
			return false
		for pr in hostile:
			pr.life = 0.0
		var mult := 1.0 + (minf(1.5, hostile.size() * ev(0.1, 0.15, 0.2)) if enhanced() else 0.0)
		w.area_hit(self, w.player_pos, r, p("damage") * mult, p("knock"))
		w.add_fx("ring", w.player_pos, 0.35, {"r0": 15.0, "r1": r, "color": GameWorld.JADE, "vfx": "ring_taiji"})
		return true


## 万剑归宗：扇形飞剑齐发。强化「剑雨」：命中后分裂成两柄小剑。
class WanJian extends SkillBase:
	func fire() -> bool:
		var reach := p("speed") * p("life")
		var t := w.nearest_enemy(reach)
		if t == null:
			return false
		var n := int(p("count")) + (3 if empowered else 0)
		var base := (t.pos - w.player_pos).angle()
		for i in n:
			var o := {}
			if enhanced():
				o["split"] = 2
			w.spawn_proj(self, base + (i - (n - 1) * 0.5) * 0.22, o)
		return true


## 玉女素心剑：回身一圈剑光，命中回血。强化「双剑合璧」：追加更大的第二圈。
class YuNv extends SkillBase:
	func _ring(r: float, dmg: float) -> int:
		var n := 0
		for e in w._query(w.player_pos, r):
			if e.alive and e.pos.distance_to(w.player_pos) < r + e.radius:
				n += 1
		w.area_hit(self, w.player_pos, r, dmg, p("knock"))
		w.add_fx("ring", w.player_pos, 0.3, {"r0": 15.0, "r1": r, "color": Color("#e8e0c8")})
		return n

	func fire() -> bool:
		var r := p("radius")
		if not w.any_enemy_within(w.player_pos, r + 20.0):
			return false
		var n := _ring(r, p("damage"))
		if enhanced():
			n += _ring(r * ev(1.3, 1.45, 1.6), p("damage") * 0.8)
		var heal := minf(10.0, n * float(def.get("heal_hit", 1.0)) * (2.0 if empowered else 1.0))
		w.hp = minf(w.st("max_hp"), w.hp + heal)
		return true


## 辟邪剑法：闪现到最近的敌人身边刺击，出手无敌。强化「欲练神功」：落地后再补一圈。
class PiXie extends SkillBase:
	func fire() -> bool:
		var rng_tp := float(def.get("range_tp", 340.0)) * (1.0 + float(mods["range"]))
		var t := w.nearest_enemy(rng_tp)
		if t == null:
			return false
		var dir := (t.pos - w.player_pos).normalized()
		var from := w.player_pos
		w.player_pos = t.pos - dir * (t.radius + 28.0)
		w.facing = dir
		w.invuln = maxf(w.invuln, 0.3)
		w.add_fx("ring", from, 0.3, {"r0": 26.0, "r1": 6.0, "color": GameWorld.VERMILION})
		var a := dir.angle()
		w.fx_slash(w.player_pos, a, p("reach"), p("arc"), true)
		w.cone_hit(self, w.player_pos, a, p("arc") * 0.5, p("reach") + 14.0, p("damage"), 200.0, empowered)
		if enhanced():
			var sr := ev(90.0, 120.0, 150.0)
			w.area_hit(self, w.player_pos, sr, p("damage") * 0.8, 200.0)
			w.add_fx("ring", w.player_pos, 0.3, {"r0": 10.0, "r1": sr, "color": GameWorld.VERMILION})
		return true


## 金蛇剑法：金蛇锥，命中叠毒。强化「蛇毒入髓」：中毒者死亡时毒雾爆开。
class JinShe extends SkillBase:
	func fire() -> bool:
		var reach := p("speed") * p("life")
		var n := int(p("count"))
		var ts := w.nearest_n(reach, n)
		if ts.is_empty():
			return false
		for t in ts:
			w.spawn_proj(self, (t.pos - w.player_pos).angle(), {"poison": float(def.get("poison", 8.0)) * (1.0 + float(mods["debuff"]))})
		return true


## 倚天剑法：前方极宽的巨大剑光。强化「屠龙之势」：额外射出贯穿剑气。
class YiTian extends SkillBase:
	func fire() -> bool:
		var reach := p("reach") * (1.5 if empowered else 1.0)
		var t := w.nearest_enemy(reach + 30.0)
		if t == null:
			return false
		var a := (t.pos - w.player_pos).angle()
		w.fx_slash(w.player_pos, a, reach, p("arc"), true)
		w.cone_hit(self, w.player_pos, a, p("arc") * 0.5, reach, p("damage"), p("knock"), false)
		if enhanced():
			w.spawn_proj(self, a, {"speed": 540.0, "radius": 30.0, "life": ev(0.6, 0.75, 0.9), "pierce": 5, "knock": 160.0,
				"damage": p("damage") * ev(1.0, 1.3, 1.6)})
		return true


## 独孤九剑：起手很弱；「式」的效果全部同时生效。
## 总层 > 20：万法皆破（破绽 + 蔓延）；总层 > 30：真·独孤九剑（闪现连刺、必破绽必暴击、几率 2/4/9 连击，封印轻功）。
class Dugu extends SkillBase:
	const ORDER := ["zong", "po_jian", "po_dao", "po_qiang", "po_bian", "po_suo", "po_zhang", "po_arrow", "po_qi"]
	const TRUE_NAMES := ["破剑式", "破刀式", "破枪式", "破鞭式", "破索式", "破掌式", "破箭式", "破气式", "总诀式"]
	var arrow_t := 2.0
	var combo_left := 0
	var combo_t := 0.0
	var combo_idx := 0
	var combo_total := 0
	var _base_dmg := -1.0
	var _base_crit := 0.0
	var _base_debuff := 0.0

	func flash_range() -> float:
		return Data.T("dugu_flash_range") * (1.0 + float(mods["range"]))

	func vuln_scale() -> float:
		return 1.0 + (_base_debuff if _base_dmg >= 0.0 else float(mods["debuff"]))    # 只算天赋 / 装备带来的，不含破索式自带的减速

	func L(sid: String) -> int:
		return int(w.shi.get(sid, 0))

	func refresh() -> void:
		if _base_dmg < 0.0:
			_base_dmg = float(mods["damage"])
			_base_crit = float(mods["crit"])
			_base_debuff = float(mods["debuff"])
		mods["damage"] = _base_dmg + 0.08 * L("zong") + 0.03 * w.shi_total()    # 每领悟一层，全部式的威力都略有提升
		mods["crit"] = _base_crit + 0.02 * L("zong")
		mods["debuff"] = _base_debuff + (0.1 + 0.02 * L("po_suo") if L("po_suo") > 0 else 0.0)

	func empower_cost() -> float:
		return super.empower_cost() * maxf(0.4, 1.0 - 0.05 * L("po_qi"))

	func tick(dt: float) -> void:
		refresh()
		if L("po_arrow") > 0:
			arrow_t -= dt
			if arrow_t <= 0.0:
				arrow_t = maxf(0.8, 3.0 - 0.15 * L("po_arrow"))
				var t := w.nearest_enemy(520.0)
				if t != null:
					w.spawn_proj(self, (t.pos - w.player_pos).angle(), _opts(0.6, true))
		if w.dugu_true():
			if combo_left > 0:
				combo_t -= dt
				if combo_t <= 0.0:
					combo_left -= 1
					combo_idx += 1
					combo_t = 0.07
					_strike()
				return
			cd -= dt
			if cd <= 0.0:
				if _begin_true():
					cd = Data.T("dugu_true_cd") * w.cd_mult()
					cd_total = cd
					if def.has("anim"):
						w.play_anim(str(def["anim"]), 0.2)
				else:
					cd = 0.1
					cd_total = 0.0
			return
		super.tick(dt)

	## 起手形态：剑气（各式同时生效）
	func _opts(dmg_mult: float, homing: bool = false) -> Dictionary:
		var o := {}
		var lv_dao := L("po_dao")
		var lv_qiang := L("po_qiang")
		o["pierce"] = int(p("pierce")) + lv_dao / 2
		o["pierce_reset"] = o["pierce"]
		o["radius"] = p("radius") * (1.0 + 0.05 * lv_dao)
		o["speed"] = p("speed") * (1.0 + 0.04 * L("po_jian") + 0.05 * lv_qiang)
		o["life"] = p("life") * (1.0 + 0.05 * lv_qiang)
		o["damage"] = p("damage") * dmg_mult * (1.0 + 0.03 * lv_qiang)
		if L("po_bian") > 0:
			o["bounce"] = ceili(L("po_bian") / 3.0)
			o["bounce_dmg"] = 0.4 + 0.03 * L("po_bian")
		if L("po_suo") > 0:
			o["stun"] = 0.8
			o["stun_chance"] = (0.08 + 0.02 * L("po_suo")) * vuln_scale()
		if L("po_zhang") > 0:
			o["splash"] = 50.0 + 4.0 * L("po_zhang")
			o["splash_frac"] = 0.35 + 0.03 * L("po_zhang")
		if w.dugu_stage() >= 2:
			o["vuln"] = Data.T("dugu_vuln2") * vuln_scale()
		if homing:
			o["homing"] = true
			o["turn"] = 6.0
		return o

	func fire() -> bool:
		var reach := p("speed") * p("life") * (1.0 + 0.05 * L("po_qiang"))
		var t := w.nearest_enemy(reach)
		if t == null:
			return false
		var n := 1 + L("po_jian") / 3
		var base := (t.pos - w.player_pos).angle()
		var o := _opts(1.0)
		for i in n:
			w.spawn_proj(self, base + (i - (n - 1) * 0.5) * 0.16, o)
		return true

	# ---------------- 真·独孤九剑 ----------------

	func _begin_true() -> bool:
		var t := w.nearest_enemy(flash_range())
		if t == null:
			return false
		var r := w.rng.randf()
		var c9 := Data.T("dugu_combo9")
		var c4 := Data.T("dugu_combo4")
		var c2 := Data.T("dugu_combo2")
		if r < c9:
			combo_total = 9
		elif r < c9 + c4:
			combo_total = 4
		elif r < c9 + c4 + c2:
			combo_total = 2
		else:
			combo_total = 1
		combo_idx = 0
		combo_left = combo_total - 1
		combo_t = 0.07
		w.dugu_combo_log.append(combo_total)
		_strike()
		return true

	func _shi_label() -> String:
		if combo_total == 9:
			return TRUE_NAMES[combo_idx % 9]
		var learned: Array = w.shi.keys()
		if learned.is_empty():
			return "破剑式"
		var pick := str(learned[w.rng.randi() % learned.size()])
		return w.shi_name(pick) if pick != "zong" else "总诀式"

	## 一次闪现刺击：闪到最近的敌人身旁，必破绽、必暴击，各式同时生效
	func _strike() -> void:
		var t := w.nearest_enemy(flash_range())
		if t == null:
			combo_left = 0
			return
		var dir := (t.pos - w.player_pos).normalized()
		var from := w.player_pos
		w.player_pos = t.pos - dir * (t.radius + 26.0)
		w.facing = dir
		w.invuln = maxf(w.invuln, 0.25)
		var dist := from.distance_to(w.player_pos)
		if w.vfx.has("flash_streak"):
			w.add_fx("trail", (from + w.player_pos) * 0.5, 0.25, {"vfx": "flash_streak", "size": maxf(90.0, dist * 1.25), "angle": dir.angle()})
			w.add_fx("trail", from, 0.4, {"vfx": "afterimage", "size": 110.0, "tint": Color(1, 1, 1, 0.75)})
		else:
			w.add_fx("ring", from, 0.3, {"r0": 30.0, "r1": 4.0, "color": SwordSkills.SWORD_BLUE})
			for i in 5:
				w.add_fx("trail", from.lerp(w.player_pos, i / 5.0), 0.3)
		w.play_anim("true_thrust", 0.2)
		var a := dir.angle()
		var reach := 96.0 * (1.0 + 0.04 * L("po_qiang"))
		w.fx_slash(w.player_pos, a, reach, 1.0, true)
		var dmg := p("damage") * 2.4 * Data.T("dugu_true_mult")
		var hits := 0
		var vuln := Data.T("dugu_vuln3") * vuln_scale()
		var first: Enemy = null
		for e in w._query(w.player_pos, reach + 40.0):
			if not e.alive:
				continue
			var to := e.pos - w.player_pos
			if to.length() >= reach + e.radius:
				continue
			if to.length() > 20.0 and absf(wrapf(to.angle() - a, -PI, PI)) > 0.65:
				continue
			w.apply_vuln(e, vuln, false)
			var tgt := e
			w.hit_enemy(tgt, dmg, tags(), to.normalized() * 220.0, id, true)
			if L("po_suo") > 0 and w.rng.randf() < (0.08 + 0.02 * L("po_suo")) * vuln_scale():
				w.stun_enemy(tgt, 0.8)
			if first == null:
				first = tgt
			hits += 1
		if first == null:
			first = t
		w.add_fx("text", first.pos + Vector2(0, -first.radius - 34), 0.9, {"text": _shi_label(), "size": 26, "color": GameWorld.VERMILION})
		# 破鞭式：剑势转向另一名敌人
		if L("po_bian") > 0:
			var seen := {first.uid: true}
			var src := first.pos
			for i in ceili(L("po_bian") / 3.0):
				var nb := w._nearest_from(src, 300.0, seen)
				if nb == null:
					break
				seen[nb.uid] = true
				w.apply_vuln(nb, vuln, false)
				w.hit_enemy(nb, dmg * (0.4 + 0.03 * L("po_bian")), tags(), Vector2.ZERO, id, true)
				w.add_fx("ring", nb.pos, 0.2, {"r0": 4.0, "r1": 28.0, "color": SwordSkills.SWORD_BLUE})
				src = nb.pos
		# 破掌式：落点爆开
		if L("po_zhang") > 0:
			var sr := 50.0 + 4.0 * L("po_zhang")
			w.area_hit_raw(first.pos, sr, dmg * (0.35 + 0.03 * L("po_zhang")), tags(), id, 80.0, 0.0, false, true)
		if combo_total == 9 and combo_left == 0:      # 九连击打完：收势
			w.play_anim("finish", 0.45)
