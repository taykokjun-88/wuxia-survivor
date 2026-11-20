class_name SwordSkills
extends RefCounted
## 剑侠流派的 9 个攻击技能 + 独孤九剑。每个技能的"专属强化"在 enhanced() 分支里实现。
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
	push_error("未知剑侠招式: " + skill_id)
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
		w.fx_slash(w.player_pos, a, reach, p("arc"), false, fxid("slash"))
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
		w.fx_slash(w.player_pos, a, reach, arc * (1.0 if fxid("slash") == "" else 1.0), wave, fxid("slash"))
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
		w.fx_slash(w.player_pos, a, reach, p("arc"), true, fxid("slash"))
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
		w.add_fx("ring", w.player_pos, 0.35, {"r0": 15.0, "r1": r, "color": GameWorld.JADE, "vfx": fxid("ring") if fxid("ring") != "" else "ring_taiji"})
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
		if fxid("muzzle") != "":
			w.add_fx("trail", w.player_pos + Vector2.from_angle(base) * 40.0, 0.4, {"vfx": fxid("muzzle"), "size": 220.0, "angle": base})
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
		w.add_fx("ring", w.player_pos, 0.35, {"r0": 15.0, "r1": r, "color": Color("#e8e0c8"), "vfx": fxid("ring")})
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
		if fxid("arrive") != "":
			w.add_fx("trail", w.player_pos + Vector2.from_angle(a) * 20.0, 0.3, {"vfx": fxid("arrive"), "size": p("reach") * 2.6, "angle": a})
		else:
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
		w.fx_slash(w.player_pos, a, reach, p("arc"), true, fxid("slash"))
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
	var wb_hits: Dictionary = {}     # 破兵微步：本次出手已命中的敌人
	var wb_cd := 0.0
	var wb_count := 0                # 统计：破兵微步触发次数（测试用）
	var combo_left := 0
	var combo_t := 0.0
	var combo_idx := 0
	var combo_total := 0
	var sb_left := 0                 # 剑破天下：剩余闪现次数
	var sb_t := 0.0
	var sb_idx := 0
	var sb_mult := 1.0
	var sb_strikes := 0              # 统计：累计闪现次数（测试用）
	var sb_seen: Dictionary = {}
	var _base_dmg := -1.0
	var _base_crit := 0.0
	var _base_debuff := 0.0

	func flash_range() -> float:
		return Data.T("dugu_flash_range") * (1.0 + float(mods["range"]))

	func vuln_scale() -> float:
		return 1.0 + (_base_debuff if _base_dmg >= 0.0 else float(mods["debuff"]))    # 只算天赋 / 装备带来的，不含破索式自带的减速

	func L(sid: String) -> int:
		return w.shi_lv(sid)

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

	## 破兵微步（总层 ≥ 9）：一次出手命中 ≥ 2 名敌人，返还 1 点内力并缩短本招当前剩余冷却 10%（每秒最多一次）
	func note_hit(e: Enemy) -> void:
		if not w.dugu_micro() or wb_cd > 0.0:
			return
		wb_hits[e.uid] = true
		if wb_hits.size() >= 2:
			wb_hits.clear()
			wb_cd = Data.T("dugu_wb_gap")
			wb_count += 1
			w.add_neili(Data.T("dugu_wb_neili") + w.st("dugu_wb"))
			cd = maxf(0.0, cd * (1.0 - Data.T("dugu_wb_cut") - 0.05 * w.st("dugu_wb")))
			w.add_fx("text", w.player_pos + Vector2(0, -44), 0.6, {"text": "破兵微步", "size": 16, "color": Color("#bfe8ff")})

	## 破箭式 / 万法皆破：近战斩击把范围内的敌方普通投射物全部斩落
	func _cut_in(center: Vector2, radius: float) -> void:
		if w.dugu_can_cut():
			w.cut_hostile_projs(center, radius)

	func tick(dt: float) -> void:
		refresh()
		wb_cd = maxf(0.0, wb_cd - dt)
		if w.dugu_true():
			if sb_left > 0:                     # 剑破天下：九连闪现，每一次是一个「式」
				w.invuln = maxf(w.invuln, 0.25)
				sb_t -= dt
				if sb_t <= 0.0:
					_sb_step()
				return
			if combo_left > 0:                  # 连击：近身范围斩连续出手
				combo_t -= dt
				if combo_t <= 0.0:
					combo_left -= 1
					combo_idx += 1
					combo_t = 0.09
					_pulse(_shi_label(), 1.0)
				return
			cd -= dt
			if cd <= 0.0:
				if _begin_true():
					cd = Data.T("dugu_true_cd") * w.cd_mult() * maxf(0.35, 1.0 - float(mods["cooldown"]))
					cd_total = cd
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
		wb_hits.clear()
		var n := 1 + L("po_jian") / 3
		var base := (t.pos - w.player_pos).angle()
		var o := _opts(1.0)
		for i in n:
			w.spawn_proj(self, base + (i - (n - 1) * 0.5) * 0.16, o)
		return true

	# ---------------- 真·独孤九剑 ----------------

	func pulse_radius() -> float:
		return (Data.T("dugu_pulse_radius") + 6.0 * L("po_dao")) * (1.0 + float(mods["range"])) * (1.0 + 0.03 * L("po_qiang"))

	## 觉醒 / 真气爆发时触发：「真·独孤九剑·剑破天下」——连续闪现九次，每一次是一个「式」
	func start_sword_break(delay: float = 0.0, mult: float = 1.0) -> void:
		sb_left = 9
		sb_idx = 0
		sb_t = delay
		sb_mult = mult
		sb_seen.clear()
		combo_left = 0
		w.sword_break_count += 1
		w.invuln = maxf(w.invuln, delay + 1.4)
		w.add_fx("text", w.player_pos + Vector2(0, -96), 1.6, {"text": "真·独孤九剑 · 剑破天下", "size": 30, "color": GameWorld.VERMILION})
		w.shake = maxf(w.shake, 6.0)

	func _sb_step() -> void:
		var t := w._nearest_on_screen(w.player_pos, sb_seen)
		if t == null:
			sb_seen.clear()                     # 九个都打过了一轮（敌人少）：再从头找
			t = w._nearest_on_screen(w.player_pos, {})
		if t == null:
			sb_left = 0                         # 画面里没有敌人了
			return
		sb_seen[t.uid] = true
		_flash_strike(t, TRUE_NAMES[sb_idx], 1.6 * sb_mult)
		sb_idx += 1
		sb_left -= 1
		sb_strikes += 1
		sb_t = Data.T("dugu_sb_gap")
		if sb_left == 0:
			w.play_anim("finish", 0.45)

	## 一次闪现刺击：闪到敌人身旁，必破绽、必暴击，各式同时生效
	func _flash_strike(t: Enemy, label: String, mult: float) -> void:
		var dir := (t.pos - w.player_pos).normalized()
		var from := w.player_pos
		w.player_pos = t.pos - dir * (t.radius + 26.0)
		w.facing = dir
		var dist := from.distance_to(w.player_pos)
		if w.vfx.has("flash_streak"):
			w.add_fx("trail", (from + w.player_pos) * 0.5, 0.25, {"vfx": "flash_streak", "size": maxf(90.0, dist * 1.25), "angle": dir.angle()})
			w.add_fx("trail", from, 0.4, {"vfx": "afterimage", "size": 110.0, "tint": Color(1, 1, 1, 0.75)})
		else:
			w.add_fx("ring", from, 0.3, {"r0": 30.0, "r1": 4.0, "color": SwordSkills.SWORD_BLUE})
			for i in 5:
				w.add_fx("trail", from.lerp(w.player_pos, i / 5.0), 0.3)
		w.play_anim("true_thrust", 0.2)
		Sfx.play_skill("dugu", 1 + sb_idx)
		var a := dir.angle()
		var reach := 96.0 * (1.0 + 0.04 * L("po_qiang"))
		_cut_in(w.player_pos, reach + 60.0)
		w.fx_slash(w.player_pos, a, reach, 1.0, true)
		var dmg := p("damage") * 2.4 * Data.T("dugu_true_mult") * mult
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
			w.hit_enemy(e, dmg, tags(), to.normalized() * 220.0, id, true)
			if L("po_suo") > 0 and w.rng.randf() < (0.08 + 0.02 * L("po_suo")) * vuln_scale():
				w.stun_enemy(e, 0.8)
			if first == null:
				first = e
		if first == null:
			first = t
		w.add_fx("text", first.pos + Vector2(0, -first.radius - 34), 0.9, {"text": label, "size": 26, "color": GameWorld.VERMILION})
		_chain_effects(first, dmg, vuln)

	## 破鞭式（剑势转向画面里另一名敌人）和破掌式（落点爆开），闪现与范围斩共用
	func _chain_effects(first: Enemy, dmg: float, vuln: float) -> void:
		if L("po_bian") > 0:
			var seen := {first.uid: true}
			var src := first.pos
			for i in ceili(L("po_bian") / 3.0):
				var nb := w._nearest_on_screen(src, seen)
				if nb == null:
					break
				seen[nb.uid] = true
				w.apply_vuln(nb, vuln, false)
				w.hit_enemy(nb, dmg * (0.4 + 0.03 * L("po_bian")), tags(), Vector2.ZERO, id, true)
				w.add_fx("ring", nb.pos, 0.2, {"r0": 4.0, "r1": 28.0, "color": SwordSkills.SWORD_BLUE})
				src = nb.pos
		if L("po_zhang") > 0:
			var sr := 50.0 + 4.0 * L("po_zhang")
			w.area_hit_raw(first.pos, sr, dmg * (0.35 + 0.03 * L("po_zhang")), tags(), id, 80.0, 0.0, false, true)

	## 平时的真·独孤九剑：近身范围群攻（一圈剑气斩）。必破绽、必暴击；攻速快、有几率 2 / 4 / 9 连击
	func _begin_true() -> bool:
		if not w.any_enemy_within(w.player_pos, pulse_radius() + 20.0):
			return false
		# 连击几率各自独立判定，从高到低：先 9 连（9%），没中再判 4 连（20%），再判 2 连（50%）；中了高的，低的就不会触发
		var cm := 1.25 if w.st("ji_sword") > 0.0 else 1.0           # 极·万剑归宗：连击几率 ×1.25
		if w.rng.randf() < Data.T("dugu_combo9") * cm:
			combo_total = 9
		elif w.rng.randf() < Data.T("dugu_combo4") * cm:
			combo_total = 4
		elif w.rng.randf() < Data.T("dugu_combo2") * cm:
			combo_total = 2
		else:
			combo_total = 1
		combo_idx = 0
		combo_left = combo_total - 1
		combo_t = 0.09
		wb_hits.clear()
		w.dugu_combo_log.append(combo_total)
		_combo_banner()
		_pulse(_shi_label(), 1.0)
		return true

	## 连击的醒目大字：二连击 / 四连击 / 九连击，越多越大越红，一眼就能看出
	func _combo_banner() -> void:
		if combo_total < 2:
			return
		var txt := {2: "二连击", 4: "四连击！", 9: "九连击！！！"}[combo_total] as String
		var size := {2: 36, 4: 46, 9: 62}[combo_total] as int
		var col: Color = {2: Color("#ffb347"), 4: Color("#ff6a3d"), 9: Color("#ff2d55")}[combo_total]
		w.add_fx("text", w.player_pos + Vector2(0, -78 - (combo_total / 3) * 8), 1.1, {"text": txt, "size": size, "color": col})
		if combo_total >= 4:
			w.shake = maxf(w.shake, 3.0 if combo_total == 4 else 8.0)
			w.add_fx("ring", w.player_pos, 0.5, {"r0": 10.0, "r1": pulse_radius() * 1.4, "color": col})

	func _shi_label() -> String:
		if combo_total == 9:
			return TRUE_NAMES[combo_idx % 9]
		var learned: Array = w.shi.keys()
		if learned.is_empty():
			return "破剑式"
		var pick := str(learned[w.rng.randi() % learned.size()])
		return w.shi_name(pick) if pick != "zong" else "总诀式"

	func _pulse(label: String, mult: float) -> void:
		var R := pulse_radius()
		var dmg := p("damage") * 1.7 * Data.T("dugu_true_mult") * mult * (1.0 + 0.03 * L("po_qiang"))
		var vuln := Data.T("dugu_vuln3") * vuln_scale()
		w.play_anim("true_thrust", 0.2)
		Sfx.play_skill("dugu", 1 + combo_idx)
		_cut_in(w.player_pos, R * 1.25 + Data.T("dugu_cut_lv") * L("po_arrow"))
		w.add_fx("ring", w.player_pos, 0.3, {"r0": 20.0, "r1": R, "color": SwordSkills.SWORD_BLUE, "vfx": "burst_wind"})
		w.fx_slash(w.player_pos, w.facing.angle(), R * 0.8, TAU * 0.9, true)
		var first: Enemy = null
		for e in w._query(w.player_pos, R + 30.0):
			if not e.alive or e.pos.distance_to(w.player_pos) >= R + e.radius:
				continue
			w.apply_vuln(e, vuln, false)
			var to := e.pos - w.player_pos
			w.hit_enemy(e, dmg, tags(), (to.normalized() if to.length() > 0.01 else Vector2.RIGHT) * 260.0, id, true)
			if L("po_suo") > 0 and w.rng.randf() < (0.08 + 0.02 * L("po_suo")) * vuln_scale():
				w.stun_enemy(e, 0.8)
			if first == null or to.length() < (first.pos - w.player_pos).length():
				first = e
		# 破剑式：每 3 层多一圈余波（更大一圈，60% 伤害）
		for i in mini(3, L("po_jian") / 3):
			var Ri := R * (1.0 + 0.16 * (i + 1))
			w.area_hit_raw(w.player_pos, Ri, dmg * 0.6, tags(), id, 160.0, 0.0, false, true)
			w.add_fx("ring", w.player_pos, 0.35 + 0.05 * i, {"r0": R * 0.6, "r1": Ri, "color": SwordSkills.SWORD_BLUE})
		if first != null:
			w.add_fx("text", first.pos + Vector2(0, -first.radius - 34), 0.9, {"text": label, "size": 26, "color": GameWorld.VERMILION})
			_chain_effects(first, dmg, vuln)
