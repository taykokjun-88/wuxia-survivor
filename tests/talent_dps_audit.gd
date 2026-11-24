extends Node
## A2 新天赋树专项 DPS 审计（Godot 无头）：
##   1. 测量每个职业 0 点白板 vs 满 99 点（主修刚 / 主修柔 / 主修灵）的 45 秒木桩总 DPS，核对「最强 / 最弱 ≤ 1.6×」；
##   2. 逐个测量每个「终极（cap）」与「极意（ji）」节点的边际 DPS 增幅，核对「任意单个终极 ≤ +25% 总 DPS」；
##   3. 专项核查剑客无迹九变剑（dugu）27 层觉醒构筑的 99 点灵系 DPS。
## 运行：godot --headless --path . res://tests/talent_dps_audit.tscn

const DT := 1.0 / 60.0
const SIM_SEC := 45.0

const LOADOUTS := {
	"fist": {"skills": ["chain_fist", "quake_fist", "yue_palm", "eight_waste"], "xinfa": ["chunyang", "tiegu"]},
	"sword": {"skills": ["kuang_feng", "qingsong", "wanjian", "yitian"], "xinfa": ["lingxi", "hanshuang"]},
	"blade": {"skills": ["wuhu_blade", "kuangfeng_blade", "ranmu_blade", "xuedao"], "xinfa": ["puti", "gangqi"]},
	"spear": {"skills": ["yangjia_spear", "meihua_spear", "shaolin_staff", "panlong_staff"], "xinfa": ["chunyang", "gangqi"]},
}


func _ready() -> void:
	for sc in ["fist", "sword", "blade", "spear"]:
		var d0 := _measure(sc, {}, LOADOUTS[sc])
		var t_g := _build_99(sc, ["gang", "rou", "ling"])
		var t_r := _build_99(sc, ["rou", "gang", "ling"])
		var t_l := _build_99(sc, ["ling", "gang", "rou"])
		var dg := _measure(sc, t_g, LOADOUTS[sc])
		var dr := _measure(sc, t_r, LOADOUTS[sc])
		var dl := _measure(sc, t_l, LOADOUTS[sc])
		var mx := maxf(dg, maxf(dr, dl))
		var mn := maxf(1.0, minf(dg, minf(dr, dl)))
		print("BUILD|%s|blank=%.1f|gang99=%.1f|rou99=%.1f|ling99=%.1f|ratio=%.2f" % [sc, d0, dg, dr, dl, mx / mn])
		# 极意（+1 点第 100 点）边际增益（基于刚 99 构筑）
		var nodes := Talents.nodes(sc)
		var ji_id := str(Talents.tree(sc).get("ji", {}).get("id", ""))
		if ji_id != "":
			var t_ji := t_g.duplicate()
			t_ji[ji_id] = 1
			var d_ji := _measure(sc, t_ji, LOADOUTS[sc])
			print("ULT|%s|%s|%s|base=%.1f|with=%.1f|pct=%.1f" % [sc, ji_id, str(nodes[ji_id]["name"]), dg, d_ji, (d_ji / maxf(1.0, dg) - 1.0) * 100.0])
		# 各系终极（cap）边际增益：从该系主修 99 点中去掉该终极，对比增幅
		var by_branch := {"gang": t_g, "rou": t_r, "ling": t_l}
		var cap_ids: Array = []
		for id in nodes:
			if bool(nodes[id].get("cap", false)):
				cap_ids.append(str(id))
		cap_ids.sort()
		for cid in cap_ids:
			var b := str(nodes[cid]["branch"])
			var full_t: Dictionary = by_branch[b].duplicate()
			if int(full_t.get(cid, 0)) <= 0:
				continue
			var without_t := full_t.duplicate()
			without_t.erase(cid)
			# 若巅峰依赖该终极，也先去掉巅峰以免影响归因
			for id2 in nodes:
				if str(nodes[id2]["branch"]) == b and bool(nodes[id2].get("peak", false)):
					without_t.erase(id2)
					full_t.erase(id2)
			var base_d := _measure(sc, without_t, LOADOUTS[sc])
			var with_d := _measure(sc, full_t, LOADOUTS[sc])
			print("ULT|%s|%s|%s|base=%.1f|with=%.1f|pct=%.1f" % [sc, cid, str(nodes[cid]["name"]), base_d, with_d, (with_d / maxf(1.0, base_d) - 1.0) * 100.0])
	# 剑客无迹九变剑（dugu）27 层觉醒专项
	var dugu_cfg := {"skills": ["dugu"], "xinfa": ["lingxi", "hanshuang"], "dugu27": true}
	var dd0 := _measure("sword", {}, dugu_cfg)
	var d_tl := _build_99("sword", ["ling", "gang", "rou"])
	var ddl := _measure("sword", d_tl, dugu_cfg)
	print("DUGU|blank=%.1f|ling99=%.1f|mult=%.2f" % [dd0, ddl, ddl / maxf(1.0, dd0)])
	get_tree().quit(0)


func _build_99(school: String, order: Array) -> Dictionary:
	var nodes := Talents.nodes(school)
	var t := {}
	var left := 99
	var progressed := true
	while left > 0 and progressed:
		progressed = false
		for b in order:
			var ids: Array = []
			for id in nodes:
				if str(nodes[id]["branch"]) == b:
					ids.append(id)
			ids.sort_custom(func(x, y): return int(nodes[x]["row"]) < int(nodes[y]["row"]))
			for id in ids:
				if Talents.can_add(t, str(id), 50):
					t[str(id)] = int(t.get(str(id), 0)) + 1
					left -= 1
					progressed = true
					break
			if progressed:
				break
	return t


func _measure(school: String, talents: Dictionary, cfg: Dictionary) -> float:
	var w := GameWorld.new()
	w.god = true
	w.props_enabled = false
	w.rng_seed = 2026
	add_child(w)
	Build.apply_to(w, {"pow": 30, "agi": 30, "vit": 30, "int": 30, "luk": 27}, talents, {}, school)
	w.meta_level = 50
	var sks: Array = cfg["skills"]
	w.start_run(str(sks[0]), "tashue", "black_wind")
	for i in range(1, sks.size()):
		w.add_skill(str(sks[i]))
	for xf in cfg.get("xinfa", []):
		w.xinfa[str(xf)] = 2
	if bool(cfg.get("dugu27", false)):
		w.shi = {"zong": 7, "po_jian": 7, "po_dao": 7, "po_qiang": 6}
	w.recalc()
	w.hp = w.st("max_hp") * 0.6      # 留出回血 / 低血增伤测试空间
	w.neili = w.st("max_neili")
	# 10 个高血木桩围圈 + 1 个 Boss 木桩
	var dummies: Array[Enemy] = []
	for k in 10:
		var ang := float(k) * TAU / 10.0
		var e: Enemy = w._spawn_enemy("bandit", Vector2.from_angle(ang) * 110.0)
		e.max_hp = 1.0e8
		e.hp = 1.0e8
		e.speed = 0.0
		dummies.append(e)
	var b: Enemy = w._spawn_enemy("mini_boss_1", Vector2(95.0, 0.0))
	b.max_hp = 1.0e8
	b.hp = 1.0e8
	b.speed = 0.0
	b.is_boss = true
	dummies.append(b)
	w._rebuild_grid()

	var steps := int(SIM_SEC / DT)
	for i in steps:
		var ang := float(i) * DT * 2.0
		w.input_move = Vector2.from_angle(ang) * 0.6     # 小幅走位以便触发枪势 / 移动类天赋
		w.input_dash = (i % 240 == 60)
		w.input_ult = (i % 600 == 120)
		w.step(DT)
		# 让木桩一直围在玩家附近，并防止超时/刷怪干扰
		w.spawn_acc = 0.0
		for k in 10:
			dummies[k].pos = w.player_pos + Vector2.from_angle(float(k) * TAU / 10.0) * 110.0
		b.pos = w.player_pos + Vector2(95.0, 0.0)
	var total := 0.0
	for e in dummies:
		total += (1.0e8 - e.hp)
	remove_child(w)
	w.free()
	return total / SIM_SEC
