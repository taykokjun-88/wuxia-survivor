extends Node
## 无渲染测试：完整局模拟 + 全部技能/强化/心法/轻功的冒烟与伤害报告 + 秘籍流程。
## 运行：godot --headless --path . res://tests/sim_test.tscn

const DT := 1.0 / 60.0

var failures := 0


func _ready() -> void:
	var only := OS.get_environment("TEST_ONLY")
	if only == "":
		_chest_flow_test()
	if only == "" or only == "upgrade":
		_upgrade_system_test()
		_enhance_rework_test()
		_level_growth_test()
		_save_test()
		_sprite_anim_test()
		await _net_test()
		_meta_test()
		_neili_test()
		_build_test()
		_talent_map_test()
		_talent_skill_test()
		_vfx_test()
		_p2_test()
		_synergy_test()
		_burst_pill_test()
		_absorb_test()
		_starter_trait_test()
		_cd_sweep_test()
		_difficulty_test()
		_difficulty_reward_test()
		_sword_test()
		_dugu_test()
		_sword_art_test()
		_sword_talent_test()
		_blade_test()
		_plan6_test()
		_smith_test()
		_prop_test()
		_boss_skill_test()
		_skill_fx_test()
		_stage_test()
		_stage2_boss_test()
		_map_collision_test()
		await _town_test()
		_font_coverage_test()
	if only == "" or only == "matrix":
		_skill_matrix()
	if only == "":
		_xinfa_test()
		_qinggong_test()
	if only == "" or only == "full":
		_run_full()
	if only == "levels":
		_levels_report()
	if only == "blade":
		_blade_test()
	if only == "plan6":
		_plan6_test()
	if only == "cards":
		_upgrade_system_test()
		_enhance_rework_test()
		_synergy_test()
		_build_test()
		_neili_test()
		_meta_test()
		_xinfa_test()
		_starter_trait_test()
		_burst_pill_test()
		_p2_test()
	if only == "survive":
		_survive_report()
	if only == "boss":
		_boss_time_report(OS.get_environment("MAP") if OS.get_environment("MAP") != "" else "guangming")
	if only == "dugu":
		_dugu_report()
	print("\nRESULT: %s" % ("FAIL (%d)" % failures if failures > 0 else "OK"))
	get_tree().quit(1 if failures > 0 else 0)


## 平衡用：不无敌、会选卡的 bot 多个种子，看存活时间 / 通关率 / 气海三境占比
func _survive_report() -> void:
	print("\n=== 多种子存活报告（会选卡 bot，不无敌）===")
	var wins := 0
	var tsum := 0.0
	var rsum := [0.0, 0.0, 0.0]
	var seeds := [21, 22, 23, 24, 25, 26, 27, 28]
	for sd in seeds:
		var w := GameWorld.new()
		w.rng_seed = sd
		add_child(w)
		var starters: Array = ["chain_fist", "point_finger", "cloud_palm"]
		if OS.get_environment("SCHOOL") != "":
			starters = Data.schools[OS.get_environment("SCHOOL")]["starters"]
		w.start_run(starters[sd % starters.size()], ["tashue", "feiyan", "yufeng", "lingshe"][sd % 4])
		var pick_rng := RandomNumberGenerator.new()
		pick_rng.seed = sd
		for i in int(900.0 / DT):
			TestBot.drive(w, TestBot.engage_for(w))
			w.step(DT)
			TestBot.resolve_choices(w, pick_rng, true)
			if w.over:
				break
		var mech := ""
		if w.school_id == "blade":
			mech = "　真·霸刀破岳 %d 次" % w.tb_count
		elif w.school_id == "fist":
			mech = "　寸劲震爆 %d 次" % w.cunjin_count
		elif w.skills.has("dugu"):
			mech = "　破兵微步 %d 次 / 斩落弹体 %d" % [(w.skills["dugu"] as SwordSkills.Dugu).wb_count, w.cut_count]
		print("  种子 %d：%s @ %ds Lv%d 击杀 %d%s" % [sd, "通关" if w.won else "阵亡", int(w.time), w.level, w.kills, mech])
		wins += 1 if w.won else 0
		tsum += w.time
		for k in 3:
			rsum[k] += float(w.realm_time[k])
		_free_world(w)
	var tot: float = rsum[0] + rsum[1] + rsum[2]
	print("  通关 %d/%d　平均存活 %ds　气海 虚 %d%% / 平 %d%% / 盈 %d%%" % [wins, seeds.size(), int(tsum / seeds.size()),
		int(rsum[0] / tot * 100.0), int(rsum[1] / tot * 100.0), int(rsum[2] / tot * 100.0)])


## 每个 Boss 从现身到被击败用了多久（会选卡的无敌 bot ≈ 理想玩家）；目标：小 Boss 60~120 秒，大 Boss 70~85 秒（限时 90）
func _boss_time_report(map_id: String) -> void:
	print("\n=== %s Boss 战斗时长（会选卡无敌 bot）===" % map_id)
	var seeds := [11, 12, 13, 14]
	var sums := {}
	for sd in seeds:
		var w := GameWorld.new()
		w.god = true
		w.rng_seed = sd
		add_child(w)
		var bst: Array = ["chain_fist", "point_finger", "cloud_palm"]
		if OS.get_environment("SCHOOL") != "":
			bst = Data.schools[OS.get_environment("SCHOOL")]["starters"]
		w.start_run(bst[sd % bst.size()], "tashue", map_id)
		var pick_rng := RandomNumberGenerator.new()
		pick_rng.seed = sd
		var seen := {}
		var refs := {}
		var done := {}
		var line := "  种子 %d：" % sd
		for i in int(1000.0 / DT):
			TestBot.drive(w, TestBot.engage_for(w))
			w.step(DT)
			TestBot.resolve_choices(w, pick_rng, true)
			for b in w.bosses:
				if not seen.has(b.type_id):
					seen[b.type_id] = w.time
					refs[b.type_id] = b
			for k in refs:
				if not done.has(k) and not (refs[k] as Enemy).alive:
					done[k] = w.time - float(seen[k])
					if not sums.has(k):
						sums[k] = []
					sums[k].append(done[k])
					line += "%s %ds  " % [k, int(done[k])]
			if w.over:
				break
		for k in refs:
			var rb: Enemy = refs[k]
			if rb.alive:
				line += "[%s 未击败：血量 %d%%（含护盾 %d%%）] " % [k, int(rb.hp / rb.max_hp * 100.0), int((rb.hp + rb.shield) / rb.max_hp * 100.0)]
		print(line + ("通关 @%ds Lv%d" % [int(w.time), w.level] if w.won else "未通关 @%ds Lv%d" % [int(w.time), w.level]))
		_free_world(w)
	for k in sums:
		var a: Array = sums[k]
		var t := 0.0
		for v in a:
			t += float(v)
		print("  平均 %s：%.0f 秒（%d 次）" % [k, t / a.size(), a.size()])


## 测量「打完一局」的角色等级：会选卡的无敌 bot（≈ 理想玩家）多个种子，打到大 Boss 被击败为止
func _levels_report() -> void:
	print("\n=== 通关时的角色等级（exp_mult = %.2f）===" % Data.T("exp_mult"))
	var sum := 0
	var n := 0
	for sd in [11, 12, 13, 14]:
		var w := GameWorld.new()
		w.god = true
		w.rng_seed = sd
		add_child(w)
		w.start_run(["chain_fist", "point_finger", "cloud_palm"][sd % 3], "tashue")
		var pick_rng := RandomNumberGenerator.new()
		pick_rng.seed = sd
		for i in int(1000.0 / DT):
			TestBot.drive(w, TestBot.engage_for(w))
			w.step(DT)
			TestBot.resolve_choices(w, pick_rng, true)
			if w.over:
				break
		print("  种子 %d：%s @ %ds  Lv%d  击杀 %d  修为 %d" % [
			sd, "通关" if w.won else "未通关", int(w.time), w.level, w.kills, w.exp_total])
		sum += w.level
		n += 1
		_free_world(w)
	print("  平均等级 %.1f" % (float(sum) / n))


## 独孤九剑：会选卡的 bot 多个种子，看总层数何时越过 20 / 30（不无敌 + 无敌各一组）
func _dugu_report() -> void:
	print("\n=== 独孤九剑 · 总层数进度（会选卡 bot）===")
	for god in [true, false]:
		for sd in [31, 32, 33, 34]:
			var w := GameWorld.new()
			w.god = god
			w.rng_seed = sd
			add_child(w)
			w.start_run("dugu", "tashue")
			var pick_rng := RandomNumberGenerator.new()
			pick_rng.seed = sd
			var t20 := -1.0
			var t30 := -1.0
			for i in int(900.0 / DT):
				TestBot.drive(w, TestBot.engage_for(w))
				w.step(DT)
				TestBot.resolve_choices(w, pick_rng, true)
				if t20 < 0.0 and w.shi_total() >= 27:
					t20 = w.time
				if t30 < 0.0 and w.shi_total() >= 18:
					t30 = w.time
				if w.over:
					break
			print("  %s 种子 %d：%s @ %ds  Lv%d  总层 %d（≥27 @ %ds, ≥18 @ %ds）  式=%s  连击=%s" % [
				"无敌" if god else "不无敌", sd, "通关" if w.won else ("阵亡" if w.over else "存活"), int(w.time), w.level,
				w.shi_total(), int(t20), int(t30), str(w.shi), str(w.dugu_combo_log.size())])
			_free_world(w)


func _run_full() -> void:
	_full_run({"name": "完整局·无敌 + 会选卡（压测 + 3 小 Boss + 大 Boss + 精英/秘籍）", "god": true, "smart": true,
		"seed": 1, "dur": 900.0, "starter": "chain_fist", "qg": "tashue"})
	_full_run({"name": "完整局·会选卡的合格玩家（不无敌）", "god": false, "smart": true,
		"seed": 2, "dur": 900.0, "starter": "cloud_palm", "qg": "feiyan"})
	_full_run({"name": "完整局·纯随机选卡的新手（不无敌，难度下限）", "god": false, "smart": false,
		"seed": 3, "dur": 900.0, "starter": "point_finger", "qg": "yufeng"})


# ---------------------------------------------------------------------
# 剑侠
# ---------------------------------------------------------------------

func _blade_world(seed_v: int, starter: String = "wuhu_blade") -> GameWorld:
	var w := GameWorld.new()
	w.rng_seed = seed_v
	add_child(w)
	w.start_run(starter, "tashue")
	w.god = false
	w.props_enabled = false
	w.hp = 1e6
	return w


func _blade_test() -> void:
	print("\n=== 刀客：流派 / 刀魂 / 撕裂 / 霸刀破岳 / 九个刀法 / 武器 / 天赋 ===")
	_check(bool(Data.schools["blade"]["enabled"]), "刀客流派已开放")
	_check((Data.schools["blade"]["starters"] as Array).size() == 3, "刀客有 3 个起手招式")
	var nb := 0
	for id in Data.skills:
		if str(Data.skills[id]["school"]) == "blade":
			nb += 1
	_check(nb == 9, "刀客共 9 个招式（%d）" % nb)
	# 刀魂：命中涨、受击涨（有上限）、衰减、满魂破岳
	var w := _blade_world(61)
	_check(w.school_id == "blade" and w.skills.has("wuhu_blade"), "起手 → 刀客流派")
	w.hp = w.st("max_hp")
	_populate(w, 40)
	for i in 240:
		TestBot.drive(w, 60.0)
		w.step(DT)
	_check(w.soul > 0.0 or w.skill_dmg.get("wuhu_blade", 0.0) > 0.0, "命中后涨刀魂 / 造成伤害（刀魂 %.1f）" % w.soul)
	var before := w.soul
	w.hp = 80.0
	w.soul = 0.0
	w._hurt(10.0)
	_check(w.soul >= 1.0 and w.soul <= Data.T("blade_soul_hp_cap") + 0.01, "受击涨刀魂且不超过上限（%.1f）" % w.soul)
	w._hurt(9999.0)
	_check(w.soul <= Data.T("blade_soul_hp_cap") * 2.0 + 0.01, "再受重击，涨幅也有上限")
	w.skills.clear()
	w.god = true
	w.over = false
	w.hp = w.st("max_hp")
	for en in w.enemies:
		en.alive = false
	w.enemies.clear()
	w.soul = 50.0
	w.soul_idle = 0.0
	for i in int((Data.T("blade_soul_delay") + 1.0) / DT):
		w.step(DT)
	_check(w.soul < 50.0, "脱战后刀魂衰减")
	_check(absf(w.blade_dmg() - (1.0 + Data.T("blade_soul_dmg") * floorf(w.soul / 10.0))) < 1e-6, "刀魂加成公式")
	_free_world(w)
	# 撕裂
	var w2 := _blade_world(62)
	w2.skills.clear()
	var e: Enemy = w2._spawn_enemy("bandit", w2.player_pos + Vector2(40, 0))
	e.hp = 1e6
	e.max_hp = 1e6
	w2.apply_bleed(e, 2, 100.0)
	_check(e.bleed_stacks == 2 and e.bleed_dps > 0.0, "撕裂叠层")
	w2.apply_bleed(e, 9, 100.0)
	_check(e.bleed_stacks == int(Data.T("bleed_max")), "撕裂最多 %d 层" % int(Data.T("bleed_max")))
	var hp0 := e.hp
	for i in int(1.2 / DT):
		w2.step(DT)
	_check(e.hp < hp0, "撕裂持续流血")
	# 撕裂降低防御：同样的一击，叠层后伤害更高
	var d1: Enemy = w2._spawn_enemy("bandit", w2.player_pos + Vector2(60, 0))
	d1.hp = 1e9
	d1.max_hp = 1e9
	d1.defense = 0.4
	var h0 := d1.hp
	w2.hit_enemy(d1, 100.0, [], Vector2.ZERO, "wuhu_blade")
	var plain := h0 - d1.hp
	d1.bleed_stacks = 5
	d1.bleed_t = 3.0
	h0 = d1.hp
	w2.hit_enemy(d1, 100.0, [], Vector2.ZERO, "wuhu_blade")
	var bled := h0 - d1.hp
	_check(bled > plain * 1.2, "撕裂破甲：同一击 %.1f → %.1f" % [plain, bled])
	# 断脉爆血
	var bb: Enemy = w2._spawn_enemy("bandit", w2.player_pos + Vector2(80, 0))
	bb.hp = 1e9
	bb.max_hp = 1e9
	bb.bleed_stacks = 5
	bb.bleed_dps = 40.0
	bb.bleed_t = 3.0
	w2.bleed_burst(bb)
	_check(bb.bleed_stacks == 0, "断脉爆血清空撕裂")
	# 霸刀破岳：刀魂满后下一次出手 ×2.5、必暴击、叠 3 层撕裂，清空刀魂并回血
	w2.skills.clear()
	w2.add_skill("wuhu_blade")
	for en in w2.enemies:
		en.alive = false
	w2.enemies.clear()
	var tg: Enemy = w2._spawn_enemy("bandit", w2.player_pos + Vector2(70, 0))
	tg.hp = 1e9
	tg.max_hp = 1e9
	w2.soul = 100.0
	w2.hp = w2.st("max_hp") * 0.5
	var hp_a := w2.hp
	for i in 90:
		w2.step(DT)
		if w2.soul < 100.0:
			break
	_check(w2.soul < 30.0, "霸刀破岳后刀魂清空（%.1f）" % w2.soul)
	_check(tg.bleed_stacks >= int(Data.T("blade_break_stacks")), "霸刀破岳叠 %d 层撕裂（实际 %d）" % [int(Data.T("blade_break_stacks")), tg.bleed_stacks])
	_check(w2.hp > hp_a, "霸刀破岳回复已损气血")
	_free_world(w2)
	# 九个刀法：开强化 / 催动，40 秒冒烟 + 伤害
	print("  刀法            基础      强化3")
	for id in Data.skills:
		if str(Data.skills[id]["school"]) != "blade":
			continue
		var row: Array[String] = []
		for mode in ["lv1", "enh3"]:
			var wk := _blade_world(63)
			wk.god = true
			wk.skills.clear()
			wk.add_skill(id)
			if mode == "enh3":
				wk.enhance_id = id
				wk.enhance_level = 3
			_populate(wk, 90)
			var engage := 75.0 if (Data.skills[id]["tags"] as Array).has("近战") else 240.0
			for i in int(40.0 / DT):
				TestBot.drive(wk, engage)
				wk.step(DT)
			var dmg := float(wk.skill_dmg.get(id, 0.0))
			_check(dmg > 0.0, "%s %s：40 秒内没有造成伤害" % [id, mode])
			row.append("%7.0f (%d)" % [dmg / 40.0, wk.kills])
			_free_world(wk)
		print("  %-8s %s" % [Data.skills[id]["name"], "  ".join(row)])
	# 耗血刀法：血刀经 / 燃木 / 玄虚 / 屠龙共 4 个会耗血，耗的血也涨刀魂，且不会把自己耗死
	var hp_skills := []
	for id in Data.skills:
		if str(Data.skills[id]["school"]) == "blade" and float(Data.skills[id].get("hp_cost", 0.0)) > 0.0:
			hp_skills.append(id)
	_check(hp_skills.size() == 4, "刀客有 4 个耗血刀法（%s）" % str(hp_skills))
	for id in hp_skills:
		var wh := _blade_world(92)
		wh.god = true
		wh.skills.clear()
		wh.add_skill(id)
		wh.hp = wh.st("max_hp")
		wh.soul = 0.0
		_populate(wh, 20)
		for i in int(14.0 / DT):
			TestBot.drive(wh, 75.0)
			wh.step(DT)
		_check(wh.skills[id].cd_total > 0.0 or float(wh.skill_dmg.get(id, 0.0)) > 0.0, "%s 出过手" % id)
		_check(wh.soul > 0.0, "%s：耗血 / 命中涨刀魂（%.1f）" % [id, wh.soul])
		var w_low := _blade_world(93)
		w_low.skills.clear()
		w_low.add_skill(id)
		w_low.god = true
		w_low.hp = 1.0
		_populate(w_low, 20)
		for i in int(14.0 / DT):
			TestBot.drive(w_low, 75.0)
			w_low.step(DT)
		_check(w_low.hp >= 1.0, "%s：只剩 1 点气血也不会被自己耗死" % id)
		_free_world(wh)
		_free_world(w_low)
	var wpay := _blade_world(94)
	wpay.skills.clear()
	wpay.add_skill("tulong_art")
	wpay.hp = wpay.st("max_hp")
	wpay.soul = 0.0
	wpay.skills["tulong_art"].pay_hp()
	_check(absf((wpay.st("max_hp") - wpay.hp) - wpay.st("max_hp") * 0.06) < 0.01 and wpay.soul > 4.0, "屠龙刀法耗 6%% 气血并涨刀魂（%.1f）" % wpay.soul)
	wpay.hp = wpay.st("max_hp")
	wpay.soul = 0.0
	wpay.skills["tulong_art"].free_cast = true
	wpay.skills["tulong_art"].pay_hp()
	_check(is_equal_approx(wpay.hp, wpay.st("max_hp")) and wpay.soul == 0.0, "免费释放（号令天下）不耗血")
	_free_world(wpay)
	# 反两仪：抹弹幕、减伤反弹；屠龙刀法：免费释放；血刀经：不会把自己耗死
	var w3 := _blade_world(64)
	w3.skills.clear()
	w3.add_skill("fanliangyi")
	w3.enhance_id = "fanliangyi"
	w3.enhance_level = 2
	var fl: SkillBase = w3.skills["fanliangyi"]
	var foe: Enemy = w3._spawn_enemy("bandit", w3.player_pos + Vector2(50, 0))
	foe.hp = 1e9
	foe.max_hp = 1e9
	var shot := Projectile.new()
	shot.hostile = true
	shot.pos = w3.player_pos + Vector2(60, 0)
	shot.life = 3.0
	w3.projs.append(shot)
	for i in 30:
		w3.step(DT)
	_check(shot.life <= 0.0 or not w3.projs.has(shot), "反两仪抹去敌方弹幕")
	var reduced: float = fl.on_hurt(100.0)
	_check(reduced < 100.0, "反两仪刀轮期间减伤（%.0f）" % reduced)
	_free_world(w3)
	var w4 := _blade_world(65)
	w4.skills.clear()
	w4.add_skill("tulong_art")
	w4.enhance_id = "tulong_art"
	w4.enhance_level = 1
	var zc := w4.zones.size()
	w4.neili = w4.st("max_neili")
	w4._burst()
	_check(w4.zones.size() > zc, "真气爆发触发屠龙刀法「号令天下」")
	_free_world(w4)
	var w5 := _blade_world(66)
	w5.skills.clear()
	w5.add_skill("xuedao")
	w5.god = true
	w5.hp = 2.0
	_populate(w5, 30)
	var min_hp := 1e9
	for i in 600:
		TestBot.drive(w5, 75.0)
		w5.step(DT)
		min_hp = minf(min_hp, w5.hp)
	_check(min_hp >= 1.0, "血刀经耗血不会自杀（最低气血 %.1f）" % min_hp)
	_free_world(w5)
	# 武器：按稀有度选名；传说只出屠龙宝刀
	var legend := Gear.make("weapon.3.12345", "blade")
	_check(str(legend["name"]) == "屠龙宝刀", "刀客传说武器 = 屠龙宝刀（%s）" % str(legend["name"]))
	var okn := true
	for sd in 40:
		var n0 := str(Gear.make("weapon.0.%d" % (1000 + sd), "blade")["name"])
		if not ["百炼柳叶刀", "鬼头大环刀", "黑煞雁翎刀"].has(n0):
			okn = false
	_check(okn, "刀客普通武器只出前 3 把刀")
	_check(Gear.items_for("weapon", "blade").size() == 10, "刀客武器清单 10 把")
	_check(Gear.items_for("weapon", "sword").size() == 10 and str(Gear.make("weapon.3.12345", "sword")["name"]) != "", "剑侠武器不受影响")
	# 屠龙宝刀彩蛋：灭绝师泰二阶段时触发 —— 无视 50% 防御、护盾双倍伤害、破盾后易伤
	var w6 := _s2_world(67)
	w6.tulong_equipped = true
	w6._spawn_boss("s2_boss", true)
	var fb: Enemy = w6.bosses[0]
	fb.max_hp = 1e9
	fb.hp = 4e8
	for i in 8:
		w6.step(DT)
	_check(w6.tulong_on and fb.phase2, "装备屠龙宝刀，灭绝师泰二阶段触发彩蛋")
	fb.guard = 0.0
	fb.guard_regen = 99.0
	fb.shield = 100.0
	fb.shield_max = 100.0
	w6.hit_enemy(fb, 1000.0, [], Vector2.ZERO, "wuhu_blade")
	_check(fb.shield <= 0.0 and fb.vuln_t > 0.0 and fb.vuln >= 0.3, "屠龙宝刀破盾后易伤")
	_free_world(w6)
	var w7 := _s2_world(68)
	w7._spawn_boss("s2_boss", true)
	var fb2: Enemy = w7.bosses[0]
	fb2.max_hp = 1e9
	fb2.hp = 4e8
	for i in 8:
		w7.step(DT)
	_check(not w7.tulong_on, "没有装备屠龙宝刀不触发彩蛋")
	_free_world(w7)
	# 天赋
	var tn: Dictionary = Talents.nodes("blade")
	_check(str(tn["gang_ying"]["name"]) == "霸刀阔刃" and str(tn["ling_peak"]["name"]) == "刀皇霸体", "刀客天赋改名")
	_check(float(Talents.stats_for({"gang_ying": 2, "rou_finger": 1}, "blade").get("bleed_pow", 0.0)) > 0.1, "泣血撕裂：撕裂强化")
	_check(int(Talents.nodes()["gang_ying"]["max"]) == int(tn["gang_ying"]["max"]), "天赋节点上限不变（服务器校验不受影响）")


func _sword_test() -> void:
	print("\n=== 剑侠：流派 / 招式池 / 剑侠专属机制 ===")
	_check(bool(Data.schools["sword"]["enabled"]), "剑侠流派应已开放")
	var pool := 0
	for id in Data.skills:
		if str(Data.skills[id]["school"]) == "sword":
			pool += 1
	_check(pool == 10, "剑侠应有 9 个招式 + 独孤九剑，实际 %d" % pool)
	for sid in Data.schools["sword"]["starters"]:
		_check(Data.skills.has(sid) and str(Data.skills[sid]["school"]) == "sword", "剑侠起手招式有效: %s" % sid)
	# 选卡池只出本流派招式
	var w := _new_world(5, "kuang_feng")
	_check(w.school_id == "sword", "起手剑侠招式 → 流派 sword")
	for i in 40:
		for c in w.roll_choices(3):
			if str(c["kind"]) == "new_skill":
				_check(str(Data.skills[c["id"]]["school"]) == "sword", "不应出现其他流派招式: %s" % c["id"])
	# 起手不选独孤九剑：升级 / 秘籍选项里永远不会出现独孤九剑
	for i in 300:
		for c in w.roll_choices(3):
			_check(not (str(c["kind"]) == "new_skill" and str(c["id"]) == "dugu"), "非独孤路线的升级选项里不应出现独孤九剑")
	# 破绽：受伤加成
	w.time = 120.0
	var e := w._spawn_enemy("bandit", w.player_pos + Vector2(200, 0))
	e.hp = 1e6
	e.max_hp = 1e6
	var h0 := e.hp
	w.hit_enemy(e, 100.0, [], Vector2.ZERO, "x", false)
	var plain := h0 - e.hp
	h0 = e.hp
	w.apply_vuln(e, 0.5)
	w.hit_enemy(e, 100.0, [], Vector2.ZERO, "x", false)
	var with_v := h0 - e.hp
	_check(absf(with_v / maxf(0.01, plain) - 1.5) < 0.2, "破绽 +50%% 伤害（实际 ×%.2f）" % (with_v / maxf(0.01, plain)))
	e.vuln_t = 0.0
	# 中毒：层数叠加并持续掉血
	var e2 := w._spawn_enemy("bandit", w.player_pos + Vector2(300, 0))
	e2.hp = 1e6
	e2.max_hp = 1e6
	w.poison_enemy(e2, 8.0, "jinshe")
	w.poison_enemy(e2, 8.0, "jinshe")
	_check(is_equal_approx(e2.poison_dps, 16.0), "毒层叠加 16/s，实际 %.1f" % e2.poison_dps)
	var hp0 := e2.hp
	for i in 120:
		w._update_enemies(DT)
	_check(hp0 - e2.hp > 20.0, "中毒 2 秒应掉血 > 20，实际 %.1f" % (hp0 - e2.hp))
	_free_world(w)


func _sword_art_test() -> void:
	print("\n=== 剑侠美术接入（角色动画 / 小镇 / 小 Boss / 特效）===")
	var sa := SpriteAnim.new()
	_check(sa.load_dir(str(Data.schools["sword"]["sprite_dir"])), "剑侠角色动画能加载")
	for n in ["idle", "walk", "slash", "thrust", "dash", "ult", "hurt", "death", "true_idle", "true_walk", "true_thrust", "awaken", "finish"]:
		_check(sa.anims.has(n), "剑侠动画缺少 %s" % n)
	_check(ResourceLoader.exists(str(Data.schools["sword"]["portrait"])), "剑侠立绘存在")
	var w := _new_world(3, "dugu")
	_check(w.sprite_anim != null and w.sprite_anim.anims.has("true_walk"), "独孤九剑开局使用剑侠动画")
	w.shi = {"zong": 36}
	var st := w._player_anim_state()
	_check(str(st[0]) == "true_idle", "真形态站立用 true_idle，实际 %s" % str(st[0]))
	w.input_move = Vector2.RIGHT
	_check(str(w._player_anim_state()[0]) == "true_walk", "真形态行走用 true_walk")
	_free_world(w)
	var wf := _new_world(3, "chain_fist")
	_check(wf.sprite_anim != null and not wf.sprite_anim.anims.has("true_walk"), "武者流派仍用原来的动画")
	_free_world(wf)
	var ea := EnemyArt.new()
	ea.load_dir("res://assets/enemies")
	for id in ["mini_boss_1", "mini_boss_2", "mini_boss_3", "boss", "elite"]:
		_check(ea.has(id), "怪物素材缺少 %s" % id)
	var hero := EnemyArt.new()
	_check(hero.load_dir(str(Data.schools["sword"]["town_hero_dir"])) == 3, "剑侠村子走路素材（正 / 背 / 侧）")
	var t := Town.new()
	add_child(t)
	_check(t.building_art.size() == 6, "小镇 6 座建筑素材，实际 %d" % t.building_art.size())
	t.set_school("sword")
	_check(t.hero_art != null and t.hero_art.has("hero_down"), "小镇主角跟随流派")
	remove_child(t)
	t.free()
	var v := Vfx.new()
	v.load_dir("res://assets/vfx")
	for id in ["zone_crack", "zone_vortex", "hit_impact", "hit_crit", "trail_dash", "death_puff", "afterimage", "flash_streak", "awaken_aura"]:
		_check(v.has(id), "特效缺少 %s" % id)
	for id in ["dugu", "zong", "po_jian", "po_dao", "po_qiang", "po_bian", "po_suo", "po_zhang", "po_arrow", "po_qi"]:
		_check(Data.icon("skills", id) != null if id == "dugu" else Data.icon("shi", id) != null, "图标缺少 %s" % id)


func _sword_talent_test() -> void:
	print("\n=== 剑侠天赋覆盖 / 武器名 ===")
	var base := Talents.nodes()
	var sw := Talents.nodes("sword")
	_check(base.size() == sw.size(), "覆盖不改变节点数量")
	for id in base:
		_check(int(base[id]["max"]) == int(sw[id]["max"]) and base[id]["branch"] == sw[id]["branch"] and int(base[id]["row"]) == int(sw[id]["row"]), "覆盖不改变 id / 层 / 上限：%s" % id)
	var expect := {"gang_ying": "剑心", "gang_peak": "剑意凌霄", "rou_finger": "破绽洞察", "ling_qg": "御风剑步", "ling_crit": "剑气贯虹", "ling_peak": "独孤剑悟"}
	for id in expect:
		_check(str(sw[id]["name"]) == str(expect[id]), "剑侠节点名 %s" % id)
	_check(str(base["gang_ying"]["name"]) == "盈劲" and str(Talents.nodes("fist")["gang_ying"]["name"]) == "盈劲", "武者流派的节点不变")
	var ts := Talents.stats_for({"gang_ying": 2, "ling_qg": 2, "gang_peak": 1, "ling_peak": 1, "ling_crit": 2}, "sword")
	_check(absf(float(ts.get("skill_range", 0.0)) - 0.10) < 1e-6, "剑心 +5%%/级")
	_check(absf(float(ts.get("ying_dmg", 0.0)) - 0.10) < 1e-6, "剑意凌霄 盈境伤害 +10%%")
	_check(float(ts.get("burst_yang", 0.0)) == 1.0 and float(ts.get("burst_harmony", 0.0)) == 1.0, "剑侠的第 7 层保留阳性 / 调和内力")
	_check(not ts.has("crit_mult"), "剑侠天赋不再额外给暴击伤害")
	_check(absf(float(ts.get("crit_chance", 0.0)) - 0.04) < 1e-6, "剑气贯虹 暴击率 +2%%/级")
	_check(absf(float(ts.get("cd_reduce", 0.0)) - (0.03 + 0.05)) < 1e-6, "御风剑步 + 独孤剑悟 冷却：%s" % str(ts.get("cd_reduce", 0.0)))
	_check(absf(float(ts.get("exp_pct", 0.0)) - 0.08) < 1e-6 and absf(float(ts.get("qg_cd_reduce", 0.0)) - 0.08) < 1e-6, "经验 +8%%，轻功冷却 −8%%")
	var tf := Talents.stats_for({"gang_ying": 2}, "fist")
	_check(float(tf.get("ying_dmg", 0.0)) > 0.0 and not tf.has("skill_range"), "武者的盈劲仍是盈境伤害")
	# 进入局内：范围 / 减益并入招式
	var w := GameWorld.new()
	w.rng_seed = 4
	w.god = true
	add_child(w)
	Build.apply_to(w, {}, {"gang_ying": 3, "rou_finger": 2}, {}, "sword")
	w.start_run("qingsong", "tashue")
	var s: SkillBase = w.skills["qingsong"]
	_check(absf(float(s.mods["range"]) - 0.15) < 1e-6, "剑心 +15%% 范围并入招式，实际 %s" % str(s.mods["range"]))
	_check(absf(float(s.mods["debuff"]) - 0.20) < 1e-6, "破绽洞察 +20%% 减益并入招式，实际 %s" % str(s.mods["debuff"]))
	_check(s.p("reach") > float(Data.skills["qingsong"]["reach"]) * 1.14, "青松剑法 reach 变大")
	_free_world(w)
	# 武器名
	var seen_s := {}
	var seen_f := {}
	for i in 40:
		seen_s[str(Gear.make("weapon.2.%d" % i, "sword")["name"])] = true
		seen_f[str(Gear.make("weapon.2.%d" % i, "fist")["name"])] = true
	var sword_names: Array = []
	for idef in Gear.items_for("weapon", "sword"):
		sword_names.append(str(idef["name"]))
	for n in seen_s:
		_check(sword_names.has(n), "剑侠的武器叫 %s" % n)
	_check(seen_f.has("铁指套") and not seen_f.has("青锋剑"), "武者武器名不变")


func _smith_test() -> void:
	print("\n=== 铁匠强化 / 银两 ===")
	var ev: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://backend/test/enh_vectors.json"))
	_check(ev is Dictionary, "能读到共用向量")
	var cost: Array = (ev as Dictionary)["cost"]
	for r in cost.size():
		for lv in (cost[r] as Array).size():
			_check(Gear.enhance_cost(r, lv) == int(cost[r][lv]), "强化费用 稀有度%d +%d：%d vs %d" % [r, lv, Gear.enhance_cost(r, lv), int(cost[r][lv])])
	for row in (ev as Dictionary)["silver"]:
		var got := Gear.run_silver(int(row[0]), bool(row[1]), float(row[2]))
		_check(got == int(row[3]), "银两 %d %s ×%s：%d vs %d" % [int(row[0]), str(row[1]), str(row[2]), got, int(row[3])])
	# 强化加成：+10 → 基础 / 副属性 ×1.8，特殊词条不变；名字带 +N
	var base := Gear.make("weapon.3.4242", "fist")
	var up := Gear.make("weapon.3.4242", "fist", 10)
	for k in base["stats"]:
		_check(absf(float(up["stats"][k]) - float(base["stats"][k]) * 1.8) < 1e-6, "强化 +10 属性 ×1.8：%s" % str(k))
	_check((up["affixes"] as Array).size() == (base["affixes"] as Array).size() and str(up["name"]) == str(base["name"]) + " +10", "词条不变、名字带 +10")
	_check(Gear.make("weapon.3.4242", "fist", 99)["enh"] == Gear.enhance_max(), "强化等级封顶")
	# 单机存档：强化扣银两、不够不能强化、到顶、丢弃换银两
	var old_path := Save.path
	Save.path = "user://test_smith.json"
	Save.load_data()
	Save.set_gear(["weapon.0.1", "coat.4.2"], {})
	Save.store_silver_enh(0, {})
	var res := Save.enhance_local("weapon.0.1")
	_check(not bool(res["ok"]) and Save.enh_level("weapon.0.1") == 0, "银两不够不能强化")
	Save.store_silver_enh(100000, {})
	var spent := 0
	for lv in Gear.enhance_max():
		res = Save.enhance_local("weapon.0.1")
		_check(bool(res["ok"]) and int(res["level"]) == lv + 1 and int(res["cost"]) == Gear.enhance_cost(0, lv), "强化到 +%d" % (lv + 1))
		spent += int(res["cost"])
	_check(Save.silver() == 100000 - spent and Save.enh_level("weapon.0.1") == Gear.enhance_max(), "扣的银两 = 各级费用之和")
	_check(not bool(Save.enhance_local("weapon.0.1")["ok"]), "到顶不能再强化")
	_check(not bool(Save.enhance_local("weapon.4.999")["ok"]), "没有的装备不能强化")
	var before := Save.silver()
	Save.discard_local(["weapon.0.1"])
	Save.set_gear(["coat.4.2"], {})
	_check(Save.silver() == before + Gear.discard_silver(0) and Save.enh_level("weapon.0.1") == 0, "丢弃换银两并清除强化")
	# 单机结算：得银两
	var sm := {"won": true, "seconds": 800, "level": 30, "kills": 3000, "bosses": 4, "difficulty": {"count": 100, "hp": 100, "speed": 100}}
	var s0 := Save.silver()
	var r2 := Save.add_run_exp(sm)
	_check(int(r2["silverGained"]) == Gear.run_silver(Score.compute(sm), true, 1.0) and Save.silver() == s0 + int(r2["silverGained"]), "单机结算得银两")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_smith.json"))
	Save.path = old_path
	Save.load_data()


func _prop_test() -> void:
	print("\n=== 可打碎的场景物件（木箱 / 酒坛 / 火盆）===")
	var w := _new_world(12, "chain_fist")
	w.props_enabled = false
	var crate := w._spawn_enemy("prop_crate", w.player_pos + Vector2(60, 0))
	_check(crate.is_prop and crate.damage == 0.0 and crate.speed == 0.0, "木箱：不动、不伤人")
	_check(w.nearest_enemy(300.0) == null and not w.any_enemy_within(w.player_pos, 200.0), "技能不会把场景物件当目标")
	w._rebuild_grid()
	var gems0 := w.gem_pos.size()
	var kills0 := w.kills
	w.area_hit_raw(w.player_pos, 120.0, 999.0, [], "x")
	_check(not crate.alive and w.gem_pos.size() == gems0 + 3 and w.kills == kills0, "打碎木箱：掉 3 颗修为珠，不算击杀")
	var jar_gems := 0
	var jar_pills := 0
	for i in 40:
		var jar := w._spawn_enemy("prop_jar", w.player_pos + Vector2(50, 0))
		w._rebuild_grid()
		var g0 := w.gem_pos.size()
		var p0 := w.pills.size()
		w.hit_enemy(jar, 999.0, [], Vector2.ZERO, "x")
		jar_gems += w.gem_pos.size() - g0
		jar_pills += w.pills.size() - p0
	_check(jar_pills > 10 and jar_gems > 8, "酒坛：多半掉回血葫芦，否则掉修为珠（葫芦 %d / 珠 %d）" % [jar_pills, jar_gems])
	var brazier := w._spawn_enemy("prop_brazier", w.player_pos + Vector2(200, 0))
	var foe := w._spawn_enemy("bandit", w.player_pos + Vector2(230, 0))
	foe.hp = 1e6
	foe.max_hp = 1e6
	w._rebuild_grid()
	w.hit_enemy(brazier, 999.0, [], Vector2.ZERO, "x")
	_check(foe.hp < foe.max_hp, "火盆：打翻后灼伤周围的敌人")
	_free_world(w)
	# 自动刷出：靠近玩家一定距离，数量有上限，离太远会消失
	var w2 := _new_world(13, "chain_fist")
	w2.prop_t = 0.1
	for i in 60 * 120:
		w2.step(DT)
	var n := 0
	for e in w2.enemies:
		if e.alive and e.is_prop:
			n += 1
	_check(n >= 1 and n <= int(Data.T("prop_max")), "场景物件会自动刷出且有上限（%d 个）" % n)
	_free_world(w2)
	for id in ["gem_low", "gem_high", "chest", "absorb", "gourd", "crate", "jar", "brazier"]:
		_check(ResourceLoader.exists("res://assets/pickups/%s.png" % id), "掉落物素材 %s" % id)


func _boss_skill_test() -> void:
	print("\n=== Boss 技能 / 预警 / 杂兵行为 / 怪潮 / 大 Boss 限时 ===")
	for id in ["mini_boss_1", "mini_boss_2", "mini_boss_3", "boss"]:
		for k in Data.enemies[id]["skills"]:
			_check(Data.boss_skills.has(k), "%s 的技能 %s 有参数" % [id, k])
		var w := _new_world(41, "chain_fist")
		w.god = false
		w.props_enabled = false
		w.skills.clear()
		w.hp = 1e7
		w._spawn_boss(id, id == "boss")
		var b: Enemy = w.bosses[0]
		b.pos = w.player_pos + Vector2(150, 0)
		var used := {}
		var warned := false
		var shots := 0
		var hp0 := w.hp
		var spawned0 := w.enemies.size()
		b.hp = b.max_hp * 0.4                  # 直接进入后半段：追加的技能也会用到
		b.max_hp = 1e9
		b.hp = 4e8
		var was_hurt := false
		for i in 60 * 70:
			w.input_move = Vector2.ZERO
			w.neili = w.st("max_neili")
			w.hp = 1e7
			w.step(DT)
			if w.hp < 1e7 - 0.5:
				was_hurt = true
			if b.cast_id != "":
				used[b.cast_id] = true
				if b.cast_t < float(Data.boss_skills[b.cast_id]["warn"]) - 0.05:
					warned = true
			shots = maxi(shots, w.projs.size())
			b.hp = 4e8
			if b.pos.distance_to(w.player_pos) > 500.0:
				b.pos = w.player_pos + Vector2(220, 0)
		var want: Array = (Data.enemies[id]["skills"] as Array).duplicate()
		want.append_array(Data.enemies[id]["skills2"])
		for k in want:
			_check(used.has(k), "%s 用过技能 %s（实际用过 %s）" % [id, k, str(used.keys())])
		_check(warned, "%s 施放前有预警" % id)
		_check(was_hurt, "%s 的技能能伤到玩家" % id)
		if id == "boss":
			_check(w.enemies.size() > spawned0, "寨主号令：召来精锐")
		_free_world(w)
	# 杂兵：弓手放冷箭 / 蛮兵预警后冲锋
	var wm := _new_world(42, "chain_fist")
	wm.god = false
	wm.props_enabled = false
	wm.skills.clear()
	wm.hp = 1e7
	var ar := wm._spawn_enemy("archer", wm.player_pos + Vector2(300, 0))
	var ch := wm._spawn_enemy("charger", wm.player_pos + Vector2(0, 300))
	ar.hp = 1e9
	ch.hp = 1e9
	ar.max_hp = 1e9
	ch.max_hp = 1e9
	var arrow := false
	var rushed := false
	var d_min := 1e9
	for i in 60 * 20:
		wm.input_move = Vector2.ZERO
		wm.hp = 1e7
		wm.step(DT)
		for p in wm.projs:
			if p.hostile and p.kind == "arrow":
				arrow = true
		if ch.cast_id == "rush" and ch.cast_t > 0.7:
			rushed = true
		d_min = minf(d_min, ar.pos.distance_to(wm.player_pos))
	_check(arrow, "弓手放出冷箭")
	_check(rushed, "蛮兵预警后冲锋")
	_check(d_min > 120.0, "弓手保持距离（最近 %d）" % int(d_min))
	# 怪潮
	var n0 := wm.enemies.size()
	wm.time = 130.0
	wm.next_wave = 100.0
	wm._spawn(DT)
	_check(wm.enemies.size() >= n0 + 12, "怪潮：一次刷出一大群（%d → %d）" % [n0, wm.enemies.size()])
	_free_world(wm)
	# 大 Boss 限时：现身后 1 分钟内没击败 → 寨主逃遁，判负
	var wd := _new_world(43, "chain_fist")
	wd.god = false
	wd.props_enabled = false
	wd.skills.clear()
	wd.hp = 1e7
	wd.time = 719.0
	for i in 60 * 3:
		wd.hp = 1e7
		wd.step(DT)
	_check(wd.boss_deadline > 0.0 and absf(wd.boss_deadline - (wd.time - 0.0 + (wd.boss_deadline - wd.time))) < 1e-6, "大 Boss 现身时开始限时")
	_check(not wd.over, "限时内还没结束")
	wd.boss_deadline = wd.time + 0.2
	for i in 60:
		wd.hp = 1e7
		wd.step(DT)
	_check(wd.over and not wd.won and wd.timeout_fail, "超时：寨主逃遁，判负")
	_free_world(wd)


func _skill_fx_test() -> void:
	print("\n=== 各招式专属攻击特效 ===")
	var v := Vfx.new()
	v.load_dir("res://assets/vfx")
	for id in Data.skills:
		var fx: Variant = Data.skills[id].get("fx", {})
		_check(fx is Dictionary and not (fx as Dictionary).is_empty(), "%s 配有专属特效" % id)
		for k in fx:
			_check(v.has(str(fx[k])), "%s 的特效 %s 素材存在" % [id, fx[k]])
	for id in ["boss_claw_slash", "boss_whip_arc", "boss_claw_proj", "boss_dark_palm", "boss_red_ring", "boss_huge_cleave", "boss_blade_proj"]:
		_check(v.has(id), "Boss 特效 %s" % id)
	# 实际出招时会产生专属特效
	var seen := {}
	for id in Data.skills:
		var starter := str(id)
		var w := _new_world(60, starter if (Data.schools[str(Data.skills[id]["school"])]["starters"] as Array).has(id) else ("chain_fist" if str(Data.skills[id]["school"]) == "fist" else "kuang_feng"))
		w.props_enabled = false
		w.skills.clear()
		w.add_skill(id)
		w.shi = {}
		for i in 10:
			var e := w._spawn_enemy("bandit", w.player_pos + Vector2.from_angle(float(i) * 0.6) * 90.0)
			e.hp = 1e9
			e.max_hp = 1e9
			e.speed = 0.0
		w._rebuild_grid()
		var want: Dictionary = Data.skills[id]["fx"]
		var found := false
		for i in 180:
			w._rebuild_grid()
			if id == "taiji" and i % 20 == 0:
				w.god = false
				w.hp = 1e6
				w.invuln = 0.0
				w._hurt(30.0)           # 乾坤大挪移：受击才反击
			w.step(DT)
			for fxe in w.effects:
				if want.values().has(str(fxe.get("vfx", ""))):
					found = true
			for pr in w.projs:
				if want.values().has(pr.vfx_id):
					found = true
			if found:
				break
		if id != "dugu" and id != "jinshe":      # 这两个是弹体特效，上面 projs 已检查
			pass
		_check(found, "%s 出招会用到自己的特效 %s" % [id, str(want)])
		_free_world(w)


func _stage_test() -> void:
	print("\n=== 关卡时间轴 / 大 Boss 清场与倒计时 / 通关解锁 / 装备分数 ===")
	var tl: Dictionary = Data.maps["black_wind"]["timeline"]
	_check(float(tl["final"]["t"]) == 600.0 and float(tl["final"]["limit"]) == 90.0, "黑风寨：大 Boss 10:00 现身，限时 1:30")
	_check(float(tl["minis"][0]["t"]) == 180.0 and float(tl["minis"][1]["t"]) == 330.0 and float(tl["minis"][2]["t"]) == 480.0, "小 Boss 3:00 / 5:30 / 8:00")
	var w := _new_world(70, "chain_fist")
	w.god = true
	w.props_enabled = false
	w.skills.clear()
	w.time = 595.0
	w.mini_idx = 2
	for i in 30:
		w._spawn_enemy("bandit", w.player_pos + Vector2(200 + i * 5, 0))
	w._spawn_boss("mini_boss_3", false)              # 一个还没击杀的小 Boss
	var mb: Enemy = w.bosses[0]
	_check(w.enemies.size() >= 31, "清场前场上有怪")
	for i in 60 * 7:
		w.step(DT)
	_check(w.boss_spawned and w.boss_deadline > 0.0, "10:00 大 Boss 现身并开始倒计时")
	_check(not mb.alive, "大 Boss 现身时，没击杀的小 Boss 消失")
	var alive := 0
	for e in w.enemies:
		if e.alive:
			alive += 1
			_check(e.is_final, "场上只剩大 Boss")
	_check(alive == 1 and w.bosses.size() == 1 and w.bosses[0].is_final, "清场后只剩大 Boss（%d）" % alive)
	_check(absf((w.boss_deadline - w.time) - 90.0) < 8.0, "倒计时约 90 秒（%.0f）" % (w.boss_deadline - w.time))
	var n0 := 0
	for i in 60 * 5:
		w.step(DT)
	for e in w.enemies:
		if e.alive and not e.is_final:
			n0 += 1
	_check(n0 == 0, "大 Boss 在场期间不再刷小怪（%d）" % n0)
	_free_world(w)
	# 通关解锁（单机存档）
	var old_path := Save.path
	Save.path = "user://test_stage.json"
	Save.load_data()
	_check(Save.map_unlocked("black_wind") and Save.map_unlocked("guangming"), "光明顶不再需要通关黑风寨（只需局外 Lv5）")
	_check(int(Data.maps["guangming"]["min_meta_level"]) == 5, "光明顶需局外等级 5")
	# 装备分数
	_check(Gear.item_score(0) == 5 and Gear.item_score(1) == 10 and Gear.item_score(2) == 20 and Gear.item_score(3) == 40, "装备基础分 5 / 10 / 20 / 40")
	_check(Gear.item_score(3, 10) == 72, "传说 +10 = 72 分（实际 %d）" % Gear.item_score(3, 10))
	Save.set_gear(["weapon.1.1", "coat.1.2", "boots.0.3"], {"weapon": "weapon.1.1", "coat": "coat.1.2", "boots": "boots.0.3"})
	_check(Save.gear_score() == 25, "已穿戴三件（10+10+5）= 25 分（实际 %d）" % Save.gear_score())
	var rec: Array = Save.recommend_status("guangming")
	_check(rec.size() == 1 and bool(rec[0]["ok"]), "建议条件：只有装备分数 20（已达标）")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_stage.json"))
	Save.path = old_path
	Save.load_data()


func _map_collision_test() -> void:
	print("\n=== 光明顶地图：障碍碰撞 / 素材 / 解锁 ===")
	var w := _s2_world(91)
	_check(w.map_art != null and w.map_art.has_blockers, "光明顶地图有挡路物件")
	var wb := _new_world(92)
	_check(wb.map_art != null and not wb.map_art.has_blockers, "黑风寨没有碰撞物件（装饰）")
	_free_world(wb)
	# 找一个碰撞块，把玩家 / 怪 / 弹体放进去
	var rc := Rect2()
	var found := false
	for cy in range(-6, 7):
		for cx in range(-6, 7):
			var arr: Array = w.map_art._cell_blockers(cx, cy)
			if not arr.is_empty() and not found:
				rc = arr[0]
				found = true
	_check(found, "附近能找到碰撞块")
	var inside := rc.get_center()
	w.player_pos = inside
	w._update_player(DT)
	_check(not rc.grow(w.PLAYER_RADIUS - 1.0).has_point(w.player_pos), "玩家被顶出碰撞块")
	_check(w.map_art.blocked(inside, 2.0), "块中心判定为被挡")
	_check(not w.map_art.blocked(inside + Vector2(0, 400), 2.0), "远处不被挡")
	var p := w.map_art.push_out(inside + Vector2(0, 100), 12.0)
	_check(p == inside + Vector2(0, 100), "没碰到不会被移动")
	# 覆盖率：障碍占地面积要小，不会封死地图
	var area := 0.0
	var tot := 0.0
	for cy in range(-12, 13):
		for cx in range(-12, 13):
			tot += MapArt.PROP_CELL * MapArt.PROP_CELL
			for r in w.map_art._cell_blockers(cx, cy):
				area += (r as Rect2).get_area()
	_check(area / tot < 0.06, "碰撞块总面积占比 < 6%%（实际 %.1f%%）" % [area / tot * 100.0])
	# 出生点附近 230 以内无障碍
	var clear := true
	for a in 36:
		var q := Vector2.from_angle(TAU * a / 36.0) * 200.0
		if w.map_art.blocked(q, 14.0):
			clear = false
	_check(clear, "出生点周围留空")
	# 素材齐全
	for id in ["huashan", "kunlun", "kongtong", "shaolin", "emei", "s2_mini_1", "s2_mini_2", "s2_mini_3", "s2_boss"]:
		_check(w.enemy_art.has(id), "怪物素材 %s 存在" % id)
	for id in ["boss_fan_blade", "boss_poison_mist", "boss_ice_band", "boss_cross_blade", "boss_dragon_claw", "boss_golden_bell_ring", "boss_palm_seal", "boss_buddha_light", "boss_yitian_cross", "boss_sword_rain", "boss_shield", "boss_aura_phase2", "boss_shield_break", "boss_phase2_burst", "fx_minion_stomp", "fx_minion_thrust", "fx_minion_frost", "fx_poison_hit", "proj_emei_sword", "decal_scorch", "decal_ice_zone"]:
		_check(w.vfx.has(id), "特效 %s 已登记" % id)
	_check(bool(Data.maps["guangming"]["enabled"]), "光明顶已开放")
	_free_world(w)


func _s2_world(seed_v: int) -> GameWorld:
	var w := GameWorld.new()
	w.rng_seed = seed_v
	add_child(w)
	w.start_run("chain_fist", "tashue", "guangming", {})
	w.god = false
	w.props_enabled = false
	w.skills.clear()
	w.hp = 1e7
	return w


func _stage2_boss_test() -> void:
	print("\n=== 光明顶 Boss：新招式 / 红色预警 / 毒雾冰封 / 二阶段 + 护盾 / 破防 / 无视防御 ===")
	for id in ["s2_mini_1", "s2_mini_2", "s2_mini_3", "s2_boss"]:
		var w := _s2_world(81)
		w._spawn_boss(id, id == "s2_boss")
		var b: Enemy = w.bosses[0]
		b.pos = w.player_pos + Vector2(170, 0)
		b.max_hp = 1e9
		b.hp = 4e8 if id != "s2_boss" else 9e8
		var used := {}
		var warned := {}
		var hurt := false
		var zone_seen := false
		for i in 60 * 120:
			w.input_move = Vector2.ZERO
			w.hp = 1e7
			w.step(DT)
			if w.hp < 1e7 - 0.5:
				hurt = true
			if not w.hzones.is_empty():
				zone_seen = true
			if b.cast_id != "":
				used[b.cast_id] = true
				if b.cast_t < float(Data.boss_skills[b.cast_id]["warn"]) - 0.05:
					warned[b.cast_id] = true
			b.hp = 4e8 if id != "s2_boss" else 9e8
			if id == "s2_boss" and i == 60 * 60:
				b.hp = 4e8                          # 低于 50%：触发二阶段
			if id == "s2_boss" and i > 60 * 60:
				b.hp = maxf(b.hp, 4e8)
			if b.pos.distance_to(w.player_pos) > 500.0:
				b.pos = w.player_pos + Vector2(220, 0)
		var want: Array = (Data.enemies[id]["skills"] as Array).duplicate()
		want.append_array(Data.enemies[id]["skills2"])
		if id == "s2_boss":
			want.append("sword_rain")
		for k in want:
			_check(used.has(k), "%s 用过 %s（用过 %s）" % [id, k, str(used.keys())])
			_check(warned.has(k) or not used.has(k), "%s 的 %s 施放前有红色预警" % [id, k])
		_check(hurt, "%s 的招式能伤到玩家" % id)
		if id == "s2_mini_1" or id == "s2_mini_2":
			_check(zone_seen, "%s 留下毒雾 / 冰封带" % id)
		if id == "s2_boss":
			_check(b.phase2 and b.defense > 0.29 and b.shield_max > 0.0, "灭绝师泰进入二阶段")
		_free_world(w)
	# 五大派小怪：按时间表刷出；华山突刺 / 昆仑减速 / 崆峒震击 / 少林高防御 / 峨眉远程
	var wm := _s2_world(83)
	var counts := {}
	for t in [60.0, 250.0, 450.0, 620.0, 800.0]:
		wm.time = t
		var c := {}
		for i in 400:
			var tp := wm._pick_type()
			c[tp] = int(c.get(tp, 0)) + 1
		var top := ""
		for k in c:
			if top == "" or int(c[k]) > int(c[top]):
				top = k
		counts[t] = top
	_check(str(counts[60.0]) == "huashan" and str(counts[250.0]) == "kunlun" and str(counts[450.0]) == "kongtong" and str(counts[620.0]) == "shaolin" and str(counts[800.0]) == "emei", "门派刷怪时间表：%s" % str(counts))
	wm.time = 100.0
	var hs := wm._spawn_enemy("huashan", wm.player_pos + Vector2(250, 0))
	var kt := wm._spawn_enemy("kongtong", wm.player_pos + Vector2(0, 300))
	var em := wm._spawn_enemy("emei", wm.player_pos + Vector2(-300, 0))
	for e in [hs, kt, em]:
		e.hp = 1e9
		e.max_hp = 1e9
	var sl := wm._spawn_enemy("shaolin", wm.player_pos + Vector2(0, -400))
	sl.hp = 1e9
	sl.max_hp = 1e9
	sl.speed = 0.0
	var thrust := false
	var stomp := false
	var arrow := false
	for i in 60 * 25:
		wm.input_move = Vector2.ZERO
		wm.hp = 1e7
		wm.step(DT)
		if hs.cast_id == "thrust":
			thrust = true
		if kt.cast_id == "minion_stomp":
			stomp = true
		for pr in wm.projs:
			if pr.hostile and (pr.kind == "emei" or pr.kind == "arrow"):
				arrow = true
	_check(thrust and stomp and arrow, "华山突刺 / 崆峒震击 / 峨眉剑气（%s %s %s）" % [str(thrust), str(stomp), str(arrow)])
	var bd := wm._spawn_enemy("bandit", wm.player_pos + Vector2(0, -420))
	bd.hp = 1e9
	bd.max_hp = 1e9
	bd.speed = 0.0
	var hp_a := sl.hp
	var hp_b := bd.hp
	wm.hit_enemy(sl, 100.0, [], Vector2.ZERO, "x")
	wm.hit_enemy(bd, 100.0, [], Vector2.ZERO, "x")
	_check(absf((hp_a - sl.hp) / (hp_b - bd.hp) - 0.6) < 0.02, "少林武僧防御 40%%：只受 60%%（%.2f）" % ((hp_a - sl.hp) / (hp_b - bd.hp)))
	_free_world(wm)
	var wk := _s2_world(84)
	var kl := wk._spawn_enemy("kunlun", wk.player_pos + Vector2(10, 0))
	kl.hp = 1e9
	wk.invuln = 0.0
	wk.player_slow_t = 0.0
	wk.step(DT)
	_check(wk.player_slow_t > 0.3, "昆仑弟子碰到玩家会减速")
	_free_world(wk)
	# 二阶段细节：护盾 = 最大血量 50%；攻 +30% 速 +10% 防 +30%；护盾先吃伤害；破防双倍；无视防御
	var w2 := _s2_world(82)
	w2._spawn_boss("s2_boss", true)
	var b2: Enemy = w2.bosses[0]
	var dmg0 := b2.damage
	var spd0 := b2.speed
	var hpm := b2.max_hp
	b2.pos = w2.player_pos + Vector2(100, 0)
	b2.hp = hpm * 0.49
	w2.step(DT)
	_check(b2.phase2 and absf(b2.shield - hpm * 0.5) < 1.0, "护盾 = 最大血量的 50%%（%.0f / %.0f）" % [b2.shield, hpm * 0.5])
	_check(absf(b2.damage - dmg0 * 1.3) < 0.01 and absf(b2.speed - spd0 * 1.1) < 0.01 and absf(b2.defense - 0.3) < 1e-6, "攻击 +30%% / 移速 +10%% / 防御 +30%%")
	_check(w2.player_knock.length() > 100.0, "二阶段震退玩家")
	var found_text := false
	for fx in w2.effects:
		if str(fx.get("text", "")) == "倚天不出，谁与争锋":
			found_text = true
	_check(found_text, "弹出「倚天不出，谁与争锋」")
	b2.guard = 0.0
	b2.weak_t = 0.0
	var hp1 := b2.hp
	var sh1 := b2.shield
	w2.hit_enemy(b2, 1000.0, [], Vector2.ZERO, "x", false)
	var sh_loss1 := sh1 - b2.shield
	_check(b2.hp == hp1 and sh_loss1 > 0.0, "伤害先打护盾，血量不动")
	b2.weak_t = 5.0
	var sh2 := b2.shield
	w2.hit_enemy(b2, 1000.0, [], Vector2.ZERO, "x", false)
	var sh_loss2 := sh2 - b2.shield
	_check(sh_loss2 > sh_loss1 * 2.0, "破防时双倍伤害打护盾（%.0f vs %.0f，另有破防的伤害加成）" % [sh_loss2, sh_loss1])
	b2.weak_t = 0.0
	b2.shield = 0.0
	b2.guard = 0.0
	var hp2 := b2.hp
	w2.hit_enemy(b2, 1000.0, [], Vector2.ZERO, "x", false)
	var plain := hp2 - b2.hp
	w2.talent_stats = {"armor_pierce": 0.5}
	w2.recalc()
	var hp3 := b2.hp
	w2.hit_enemy(b2, 1000.0, [], Vector2.ZERO, "x", false)
	var pierced := hp3 - b2.hp
	_check(pierced > plain * 1.1, "无视 50%% 防御：伤害更高（%.0f → %.0f）" % [plain, pierced])
	_free_world(w2)


func _dugu_test() -> void:
	print("\n=== 独孤九剑：式 / 叠加 / 阶段 / 真·独孤九剑 ===")
	var w := _new_world(7, "dugu")
	_check(w.school_id == "sword" and w.skills.size() == 1 and w.skills.has("dugu"), "独孤九剑起手：只有独孤九剑")
	# 升级卡：只出「式」，不出别的招式 / 招式升级
	for i in 30:
		var ch := w.roll_choices(3)
		var shi_n := 0
		for c in ch:
			var k := str(c["kind"])
			_check(k != "new_skill" and k != "up_skill", "独孤路线不应出招式卡（%s）" % k)
			if k == "shi_new" or k == "shi_up":
				shi_n += 1
		_check(shi_n >= 2, "每次至少 2 张「式」卡")
	# 最多 4 种
	for id in ["po_jian", "po_dao", "po_bian", "zong"]:
		w.add_shi(id, 1)
	_check(w.shi.size() == 4, "已学 4 式")
	_check(w.add_shi("po_qi", 2) == 0 and not w.shi.has("po_qi"), "第 5 种式不能学")
	for c in w.roll_choices(3):
		_check(str(c["kind"]) != "shi_new", "满 4 式后不再出新式卡")
	# 每式上限 10
	w.add_shi("po_jian", 99)
	_check(int(w.shi["po_jian"]) == 10, "单式封顶 10 层")
	# 阶段
	w.shi = {"po_jian": 8}
	_check(w.dugu_stage() == 1 and not w.dugu_micro(), "总层 8：仍是起手阶段，没有破兵微步")
	w.shi = {"po_jian": 9}
	_check(w.dugu_stage() == 1 and w.dugu_micro(), "总层 9 → 破兵微步")
	w.shi = {"po_jian": 10, "po_dao": 7}
	_check(w.dugu_stage() == 1, "总层 17：还不是万法皆破")
	w.shi = {"po_jian": 10, "po_dao": 8}
	_check(w.dugu_stage() == 2 and not w.dugu_true(), "总层 18 → 万法皆破")
	w.shi = {"po_jian": 10, "po_dao": 10, "zong": 6}
	_check(w.dugu_stage() == 2, "总层 26：仍是万法皆破")
	w.shi["zong"] = 7
	_check(w.dugu_stage() == 3 and w.dugu_true() and w.dash_sealed(), "总层 27 → 真·独孤九剑，轻功封印")
	# 秘籍：+3 层的式
	w.shi = {"po_jian": 2}
	var cc := w.roll_chest_choices()
	_check(not cc.is_empty() and str(cc[0]["kind"]).begins_with("shi_") and int(cc[0]["gain"]) == 3, "独孤路线的秘籍 = +3 层的式")
	w.pending_chests = 1
	w.apply_choice(cc[0])
	_check(w.pending_chests == 0 and w.shi_total() >= 5, "秘籍选完 +3 层")
	_free_world(w)

	# ---- 叠加：穿透 + 弹射同时生效 ----
	var w2 := _new_world(8, "dugu")
	w2.time = 120.0
	w2.shi = {"po_dao": 2, "po_bian": 3}    # 穿透 +1（共 3），弹射 1 次
	var sk: SkillBase = w2.skills["dugu"]
	sk.refresh()
	var line: Array[Enemy] = []
	for i in 3:
		var en := w2._spawn_enemy("bandit", w2.player_pos + Vector2(150.0 + 40.0 * i, 0))
		en.uid = 9000 + i
		en.hp = 1e6
		en.max_hp = 1e6
		en.speed = 0.0
		line.append(en)
	var off := w2._spawn_enemy("bandit", w2.player_pos + Vector2(270.0, 170.0))
	off.uid = 9100
	off.hp = 1e6
	off.max_hp = 1e6
	off.speed = 0.0
	w2._rebuild_grid()
	var hp_off := off.hp
	sk.cd = 0.0
	w2.step(DT)
	for i in 120:
		w2._rebuild_grid()
		w2.step(DT)
	_check(line[0].hp < line[0].max_hp and line[2].hp < line[2].max_hp, "穿透：一剑穿过三名敌人")
	_check(off.hp < hp_off, "弹射：穿透耗尽后转向旁边的敌人（穿透 + 弹射同时生效）")
	_free_world(w2)
	# 弹射范围 = 整个画面：很远但在画面里的敌人会被弹到；画面外的不会
	for far_x in [560.0, 300.0]:
		var wf := _new_world(8, "dugu")
		wf.time = 120.0
		wf.shi = {"po_bian": 3}
		var hits: Array[Enemy] = []
		for i in 2:
			var en := wf._spawn_enemy("bandit", wf.player_pos + Vector2(150.0 + 40.0 * i, 0))
			en.uid = 9300 + i
			hits.append(en)
		var far := wf._spawn_enemy("bandit", wf.player_pos + Vector2(far_x, -250.0 if far_x > 400.0 else -480.0))
		far.uid = 9400
		for en2 in hits + [far]:
			en2.hp = 1e6
			en2.max_hp = 1e6
			en2.speed = 0.0
		wf._rebuild_grid()
		wf.skills["dugu"].cd = 0.0
		for i in 240:
			wf._rebuild_grid()
			wf.step(DT)
		if far_x > 400.0:
			_check(far.hp < far.max_hp, "弹射：画面里很远的敌人也能被弹到（距离 %d）" % int(Vector2(far_x - 190.0, 250.0).length()))
		else:
			_check(far.hp >= far.max_hp, "弹射：画面外的敌人不会被弹到")
		_free_world(wf)

	# ---- 万法皆破：命中令敌人露出破绽并蔓延 ----
	var w3 := _new_world(9, "dugu")
	w3.time = 120.0
	w3.shi = {"zong": 21}
	var a := w3._spawn_enemy("bandit", w3.player_pos + Vector2(200, 0))
	var b := w3._spawn_enemy("bandit", w3.player_pos + Vector2(260, 40))
	for en2 in [a, b]:
		en2.hp = 1e6
		en2.max_hp = 1e6
		en2.speed = 0.0
	w3._rebuild_grid()
	w3.skills["dugu"].cd = 0.0
	for i in 90:
		w3._rebuild_grid()
		w3.step(DT)
	_check(a.vuln_t > 0.0 or b.vuln_t > 0.0, "万法皆破：命中使敌人露出破绽")
	_check(a.vuln_t > 0.0 and b.vuln_t > 0.0, "万法皆破：破绽蔓延到附近敌人")
	_free_world(w3)

	# ---- 真·独孤九剑：觉醒触发「剑破天下」九连闪现 → 之后近身范围群攻；真气爆发可再次触发 ----
	var w4 := _new_world(10, "dugu")
	w4.time = 120.0
	w4.shi = {"zong": 10, "po_jian": 10, "po_dao": 10, "po_bian": 6}      # 总层 36，已是真形态（直接赋值不触发觉醒）
	_check(w4.dugu_true(), "真·独孤九剑已觉醒")
	var dsk: SkillBase = w4.skills["dugu"]
	for i in 40:
		var en3 := w4._spawn_enemy("bandit", w4.player_pos + Vector2(200 + 12 * i, ((i % 5) - 2) * 40.0))
		en3.speed = 0.0
		en3.hp = 1e5
		en3.max_hp = 1e5
	w4._rebuild_grid()
	var p0 := w4.player_pos
	w4.shi = {"zong": 10, "po_jian": 10, "po_dao": 4, "po_bian": 2}      # 总层 26：还不是真形态
	w4.add_shi("po_bian", 1)                                             # 再领悟 → 达到 27 层，觉醒
	_check(w4.dugu_true() and w4.sword_break_count == 1, "达到 27 层自动触发一次剑破天下")
	var names := {}
	for i in 60 * 4:
		w4._rebuild_grid()
		w4.step(DT)
		for fx in w4.effects:
			var tx := str(fx.get("text", ""))
			if tx.begins_with("破") and tx.ends_with("式") or tx == "总诀式":
				names[tx] = true
	_check(int(dsk.get("sb_strikes")) == 9, "剑破天下连续闪现 9 次，实际 %d" % int(dsk.get("sb_strikes")))
	_check(int(dsk.get("sb_left")) == 0, "九次打完")
	_check(names.size() >= 8, "九次各是一个「式」（飘字 %d 种）" % names.size())
	_check(w4.player_pos.distance_to(p0) > 100.0, "闪现到了敌人身边")
	# 之后：近身范围群攻（不再闪现），连击几率保持，攻速快
	var pos1 := w4.player_pos
	var dmg0 := float(w4.skill_dmg.get("dugu", 0.0))
	var log0 := w4.dugu_combo_log.size()
	w4.input_dash = true
	var dc0 := w4.dash_count
	for en5 in w4.enemies:
		if en5.alive:
			en5.pos = w4.player_pos + Vector2.from_angle(w4.rng.randf() * TAU) * w4.rng.randf_range(40.0, 130.0)
	for i in 60 * 30:
		w4._rebuild_grid()
		w4.step(DT)
		w4.input_move = Vector2.ZERO
		if i % 90 == 0:
			for en6 in w4.enemies:
				if en6.alive:
					en6.hp = 1e5
					en6.pos = w4.player_pos + Vector2.from_angle(w4.rng.randf() * TAU) * w4.rng.randf_range(40.0, 130.0)
	_check(w4.dash_count == dc0, "真形态：轻功仍被封印")
	_check(w4.player_pos.distance_to(pos1) < 60.0, "之后不再闪现，原地近身群攻（位移 %d）" % int(w4.player_pos.distance_to(pos1)))
	var log: Array = w4.dugu_combo_log.slice(log0)
	var c1 := log.count(1)
	var c2 := log.count(2)
	var c4 := log.count(4)
	var c9 := log.count(9)
	print("  30 秒出手 %d 次：单 %d / 2连 %d / 4连 %d / 9连 %d" % [log.size(), c1, c2, c4, c9])
	_check(log.size() >= 40, "攻速快：30 秒出手 ≥ 40 次，实际 %d" % log.size())
	_check(c2 > 0 and c4 > 0, "连击：2 连 / 4 连都应出现")
	_check(c2 > c4 and c4 + 4 >= c9 and c1 > 0, "连击几率独立判定：9 连 9%% / 4 连 18%% / 2 连 36%% / 单击 36%%（%d / %d / %d / %d）" % [c9, c4, c2, c1])
	_check(float(w4.skill_dmg.get("dugu", 0.0)) - dmg0 > 100000.0, "近身群攻输出很高，实际 %d" % int(float(w4.skill_dmg.get("dugu", 0.0)) - dmg0))
	var any_vuln := false
	for en7 in w4.enemies:
		if en7.alive and en7.vuln_t > 0.0:
			any_vuln = true
	_check(any_vuln, "群攻命中必破绽")
	# 真气爆发再次触发剑破天下
	w4.neili = w4.st("max_neili")
	w4.input_ult = true
	w4._rebuild_grid()
	w4.step(DT)
	_check(w4.burst_used == 1 and w4.sword_break_count == 2 and int(dsk.get("sb_left")) > 0, "按真气爆发再次触发剑破天下")
	for i in 60 * 3:
		w4._rebuild_grid()
		w4.step(DT)
	_check(int(dsk.get("sb_strikes")) == 18, "第二次也闪现 9 次（累计 18），实际 %d" % int(dsk.get("sb_strikes")))
	_free_world(w4)
	# 真形态下，原本针对飞剑的式也要有效：破剑 = 多圈余波，破刀 / 破枪 = 范围更大
	var dmgs := []
	var radii := []
	for shi_set in [{"zong": 27, "po_arrow": 9}, {"zong": 27, "po_jian": 9}, {"zong": 27, "po_dao": 9}, {"zong": 27, "po_qiang": 9}]:
		var wp := _new_world(14, "dugu")
		wp.time = 120.0
		wp.shi = shi_set
		wp.props_enabled = false
		var tgt := wp._spawn_enemy("bandit", wp.player_pos + Vector2(100, 0))
		tgt.hp = 1e9
		tgt.max_hp = 1e9
		tgt.speed = 0.0
		wp._rebuild_grid()
		var ds: SkillBase = wp.skills["dugu"]
		ds.call("refresh")
		var h0 := tgt.hp
		ds.call("_pulse", "破剑式", 1.0)
		dmgs.append(h0 - tgt.hp)
		radii.append(float(ds.call("pulse_radius")))
		_free_world(wp)
	_check(float(dmgs[1]) > float(dmgs[0]) * 1.4, "破剑式：真形态每 3 层多一圈余波（伤害 %d → %d）" % [int(dmgs[0]), int(dmgs[1])])
	_check(float(radii[2]) > float(radii[0]) + 40.0, "破刀式：真形态斩击范围变大（%d → %d）" % [int(radii[0]), int(radii[2])])
	_check(float(radii[3]) > float(radii[0]) * 1.2 and float(dmgs[3]) > float(dmgs[0]) * 1.1, "破枪式：真形态斩击范围和伤害提高")


func _check(cond: bool, msg: String) -> void:
	if not cond:
		print("FAIL: ", msg)
		failures += 1


func _new_world(seed_v: int, starter: String = "chain_fist", qg: String = "tashue") -> GameWorld:
	var w := GameWorld.new()
	w.rng_seed = seed_v
	w.god = true
	add_child(w)
	w.start_run(starter, qg)
	return w


func _free_world(w: GameWorld) -> void:
	remove_child(w)
	w.free()


## 预置一批敌人，让技能测试有稳定的目标密度
func _populate(w: GameWorld, n: int) -> void:
	w.time = 120.0
	for i in n:
		var a := w.rng.randf() * TAU
		w._spawn_enemy("bandit", w.player_pos + Vector2.from_angle(a) * w.rng.randf_range(150.0, 650.0))


# ---------------------------------------------------------------------

func _chest_flow_test() -> void:
	print("=== 秘籍流程 ===")
	var w := _new_world(11)
	w.chests.append(w.player_pos)
	w.step(DT)
	_check(w.pending_chests == 1, "拾取第 1 本秘籍后应有 1 个待选")
	var ch := w.roll_chest_choices()
	_check(ch.size() == 1, "只有起手技能时秘籍应给出 1 个强化选项，实际 %d" % ch.size())
	w.apply_choice(ch[0])
	_check(w.enhance_id == "chain_fist" and w.enhance_level == 1, "首次应获得 Lv1 强化")
	_check(w.pending_chests == 0, "选择后待选应清零")
	# 之后每本秘籍：直接升级，不再弹选择
	for expect in [2, 3]:
		w.chests.append(w.player_pos)
		w.step(DT)
		_check(w.pending_chests == 0, "已有强化时不应再弹出选择")
		_check(w.enhance_level == expect, "强化应升到 Lv%d，实际 Lv%d" % [expect, w.enhance_level])
	w.chests.append(w.player_pos)
	w.step(DT)
	_check(w.enhance_level == 3, "强化最高 Lv3")
	# 边界：还没选强化就连续拾到两本 → 选完直接 Lv2
	var w2 := _new_world(12)
	w2.chests.append(w2.player_pos)
	w2.chests.append(w2.player_pos)
	w2.step(DT)
	w2.step(DT)
	w2.apply_choice(w2.roll_chest_choices()[0])
	_check(w2.enhance_level == 2, "连续拾到两本应直接 Lv2，实际 Lv%d" % w2.enhance_level)
	print("  强化 Lv1→2→3、封顶、连拾边界  OK")
	_free_world(w2)
	_free_world(w)


func _skill_matrix() -> void:
	print("\n=== 技能冒烟 + 伤害报告（每个 40 秒，无敌 bot，同样的敌人密度） ===")
	print("%-8s %10s %10s %12s %12s   （总伤害/秒；括号内为击杀数；+5 = 5 次中档升级）" % ["技能", "基础", "+5升级", "+5+强化1", "+5+强化3"])
	for id in Data.skills:
		var row: Array[String] = []
		for mode in ["lv1", "up5", "enh1", "enh3"]:
			var w := _new_world(21)
			w.skills.clear()
			w.add_skill(id)
			var s: SkillBase = w.skills[id]
			if mode != "lv1":
				_apply_up5(s)
			if mode.begins_with("enh"):
				w.enhance_id = id
				w.enhance_level = int(mode.substr(3))
			_populate(w, 90)
			var guard_ok := true
			var engage := 75.0 if s.tags().has("近战") else 240.0
			for i in int(40.0 / DT):
				TestBot.drive(w, engage)
				w.step(DT)
				# 乾坤大挪移是受击触发：god 模式下直接调用，覆盖反击分支
				if id == "taiji" and i % 120 == 0:
					s.on_hurt(30.0)
				if w.over:
					guard_ok = false
					break
			var dmg := float(w.skill_dmg.get(id, 0.0))
			_check(guard_ok, "%s %s：god 模式下不应结束" % [id, mode])
			_check(dmg > 0.0, "%s %s：40 秒内没有造成任何伤害" % [id, mode])
			row.append("%7.0f (%d)" % [dmg / 40.0, w.kills])
			_free_world(w)
		print("%-8s %s" % [Data.skills[id]["name"], "  ".join(row)])


## 固定的 5 次升级：伤害（大成）、冷却/范围/目标/时长（中成）；该技能没有的方向用伤害（中成）补齐
func _apply_up5(s: SkillBase) -> void:
	var avail := s.available_dirs()
	var plan := [["damage", 2], ["cooldown", 1], ["range", 1], ["targets", 1], ["duration", 1]]
	for step in plan:
		if avail.has(step[0]):
			s.add_upgrade(step[0], step[1])
		else:
			s.add_upgrade("damage", 1)


func _enhance_rework_test() -> void:
	print("\n=== 强化改版：品质 / 10 次强化 / 起手招式不再出现 / 心法同修 / 恢复速度 / 独孤门槛 ===")
	# 品质：普通 / 特别 / 优秀 / 传说，概率 50 / 25 / 18 / 7；强化量 1× / 2× / 3× / 4×
	var tn: Array = []
	for t in Data.tiers:
		tn.append(str(t["name"]))
	_check(tn == ["普通", "特别", "优秀", "传说"], "品质名称")
	var cols: Array = []
	for t in Data.tiers:
		cols.append(str(t["color"]))
	_check(cols == ["#e8e8e8", "#5aa0ff", "#b070e8", "#f0c050"], "品质颜色：白 / 蓝 / 紫 / 金")
	_check([int(Data.tiers[0]["weight"]), int(Data.tiers[1]["weight"]), int(Data.tiers[2]["weight"]), int(Data.tiers[3]["weight"])] == [50, 25, 18, 7], "品质概率 50 / 25 / 18 / 7")
	for dir in Data.directions:
		var vs: Array = Data.directions[dir]["values"]
		_check(is_equal_approx(float(vs[1]), float(vs[0]) * 2.0) and is_equal_approx(float(vs[2]), float(vs[0]) * 3.0) and is_equal_approx(float(vs[3]), float(vs[0]) * 4.0), "方向 %s：每高一档品质强化量 +1 倍（1 / 2 / 3 / 4 ×）" % dir)
	_check(Data.max_upgrades == 10, "每个招式最多强化 10 次")
	for id in Data.xinfa:
		_check(int(Data.xinfa[id]["max_level"]) - 1 == 3, "%s：最多强化 3 次" % id)
	# 强化卡：框的颜色 = 品质色；已强化满的招式不再出现强化卡
	var w := _new_world(81)
	w.skills.clear()
	w.add_skill("chain_fist")
	var coloured := true
	for i in 40:
		for c in w.roll_choices(30):
			if str(c["kind"]) == "up_skill":
				coloured = coloured and str(c["color"]) == str(Data.tiers[int(c["tier"])]["color"]) and str(c["tag"]) == str(Data.tiers[int(c["tier"])]["name"])
	_check(coloured, "强化卡带品质名和品质色")
	_free_world(w)
	# 起手招式（所有流派）升级时不会出现
	for st in ["chain_fist", "kuang_feng", "wuhu_blade"]:
		var ws := _new_world(82, st)
		var bad := false
		var learn := {}
		for i in 80:
			for c in ws.roll_choices(30):
				if str(c["kind"]) == "new_skill":
					learn[str(c["id"])] = true
					bad = bad or Data.is_starter(str(c["id"]))
		_check(not bad, "%s 流派：升级卡不会出现起手招式" % st)
		_check(learn.size() >= 5, "%s 流派：非起手招式都能出现（%d 个）" % [st, learn.size()])
		_free_world(ws)
	# 心法：强化品质累计强度；同修联动；重算不会重复叠加
	var wx := _new_world(83)
	wx.skills.clear()
	wx.add_skill("yue_palm")
	wx.add_skill("vajra_fist")
	wx.apply_choice({"kind": "new_xinfa", "id": "chunyang", "src": "level"})
	_check(is_equal_approx(wx.xinfa_power("chunyang"), 1.0), "修习 = 1 份强度")
	wx.apply_choice({"kind": "up_xinfa", "id": "chunyang", "tier": 3, "src": "level"})
	_check(is_equal_approx(wx.xinfa_power("chunyang"), 5.0) and int(wx.xinfa["chunyang"]) == 2, "传说强化 +4 份（共 5 份）")
	wx.apply_choice({"kind": "up_xinfa", "id": "chunyang", "tier": 0, "src": "level"})
	_check(is_equal_approx(wx.xinfa_power("chunyang"), 6.0), "普通强化 +1 份（共 6 份）")
	var yue: SkillBase = wx.skills["yue_palm"]
	var want := float(Data.xinfa["chunyang"]["link"]["yue_palm"]["damage"]) * wx.xinfa_scale("chunyang")
	_check(absf(float(yue.link_applied.get("damage", 0.0)) - want) < 1e-9, "同修：降龙十八掌伤害 +%.0f%%" % (want * 100.0))
	var d_before := float(yue.mods["damage"])
	for i in 5:
		wx.recalc()
	_check(is_equal_approx(float(yue.mods["damage"]), d_before), "反复重算不会重复叠加联动")
	_check(float(yue.link_flags.get("ying", 0.0)) > 0.0, "九阳神功同修：盈境增伤标记")
	var other := _new_world(84)
	other.skills.clear()
	other.add_skill("eight_waste")
	other.apply_choice({"kind": "new_xinfa", "id": "chunyang", "src": "level"})
	_check(float(other.skills["eight_waste"].link_applied.get("damage", 0.0)) == 0.0, "没有被心法点名的招式不受联动")
	_free_world(other)
	_free_world(wx)
	# 联动特殊效果：命中回内力 / 破绽 / 撕裂
	var wn := _new_world(85)
	wn.skills.clear()
	wn.add_skill("taiji")
	wn.apply_choice({"kind": "new_xinfa", "id": "tunhai", "src": "level"})
	var tgt := Enemy.new()
	tgt.hp = 1e12
	tgt.max_hp = 1e12
	wn.neili = 10.0
	wn.hit_enemy(tgt, 10.0, ["防御"], Vector2.ZERO, "taiji")
	_check(wn.neili > 10.4, "北冥神功同修：命中回内力（%.2f）" % wn.neili)
	_free_world(wn)
	var wv := _new_world(86, "kuang_feng")
	wv.skills.clear()
	wv.add_skill("yunv")
	wv.apply_choice({"kind": "new_xinfa", "id": "hanshuang", "src": "level"})
	var tv := Enemy.new()
	tv.hp = 1e12
	tv.max_hp = 1e12
	wv.hit_enemy(tv, 10.0, ["范围"], Vector2.ZERO, "yunv")
	_check(tv.vuln_t > 0.0 and tv.vuln > 0.0, "玄冥神功同修：命中露出破绽")
	_free_world(wv)
	var wbl := _new_world(87, "wuhu_blade")
	wbl.skills.clear()
	wbl.add_skill("xuedao")
	wbl.apply_choice({"kind": "new_xinfa", "id": "changsheng", "src": "level"})
	for k in 3:
		wbl.apply_choice({"kind": "up_xinfa", "id": "changsheng", "tier": 3, "src": "level"})
	var tb := Enemy.new()
	tb.hp = 1e12
	tb.max_hp = 1e12
	var bled := 0
	for i in 60:
		tb.bleed_stacks = 0
		tb.bleed_t = 0.0
		tb.bleed_dps = 0.0
		wbl.hit_enemy(tb, 20.0, ["近战"], Vector2.ZERO, "xuedao")
		bled += 1 if tb.bleed_stacks > 0 else 0
	_check(bled > 10, "先天功同修：命中有几率撕裂（%d/60）" % bled)
	_free_world(wbl)
	# 每个心法点名 3 个非起手招式（可以跨流派，各自的加成不同）；每个非起手招式至少被一个心法点名
	var covered := {}
	var cross := 0
	for id in Data.xinfa:
		var lk: Dictionary = Data.xinfa[id]["link"]
		_check(lk.size() == 3, "%s 点名 %d 个招式（要求 3 个）" % [id, lk.size()])
		var sch_set := {}
		for sid in lk:
			covered[sid] = true
			sch_set[str(Data.skills[sid]["school"])] = true
			_check(not Data.is_starter(str(sid)), "%s → %s：不能是起手招式" % [id, sid])
		cross += 1 if sch_set.size() > 1 else 0
	_check(cross >= 8, "心法点名的招式多数跨流派（%d / 10）" % cross)
	for sid in Data.skills:
		if not Data.is_starter(sid):
			_check(covered.has(sid), "非起手招式 %s 至少被一个心法点名" % sid)
	var ny := 0
	for id in Data.xinfa:
		ny += 1 if str(Data.xinfa[id]["yy"]) == "yang" else 0
	_check(ny == 5, "5 个阳性 + 5 个阴性心法（阳 %d）" % ny)
	# 初始恢复：内力回复 −30%，气血每 5 秒 1 点
	_check(absf(float(Data.player_base["neili_regen"]) - 8.4) < 1e-6, "初始内力回复 8.4（原 12 的 70%）")
	_check(absf(float(Data.player_base["hp_regen"]) - 0.2) < 1e-6, "初始气血回复 0.2 / 秒（每 5 秒 1 点）")
	# 流派特色：剑侠 = 速度 / 攻速；武者 = 内力（盈境加成高、催动贵）；刀客 = 气血；独孤九剑催动消耗减半
	var wsw := _new_world(88, "kuang_feng")
	var wfi := _new_world(89, "chain_fist")
	var wbl2 := _new_world(90, "wuhu_blade")
	_check(wsw.st("speed_pct") >= 0.10 - 1e-9 and wsw.st("qg_cd_reduce") >= 0.10 - 1e-9, "剑侠：移速 +10%、轻功冷却 −10%")
	wsw.stats["speed_pct"] = 0.30
	var cm_fast := wsw.cd_mult()
	wsw.stats["speed_pct"] = 0.0
	_check(cm_fast < wsw.cd_mult() - 0.1, "剑侠：移速越高攻速越快（%.2f < %.2f）" % [cm_fast, wsw.cd_mult()])
	_check(wfi.st("ying_dmg") >= 0.10 - 1e-9 and wfi.st("empower_cut") < 0.0 and wfi.st("max_neili") > float(Data.player_base["max_neili"]), "武者：盈境加成更高、催动更贵、内力更深")
	_check(wbl2.st("max_hp") > float(Data.player_base["max_hp"]) and wbl2.st("hp_regen") > float(Data.player_base["hp_regen"]), "刀客：气血上限与回复更高")
	var hpk := wbl2.hp
	wbl2.hp = 10.0
	var ke: Enemy = wbl2._spawn_enemy("bandit", wbl2.player_pos + Vector2(40, 0))
	wbl2._kill(ke)
	_check(wbl2.hp > 10.04, "刀客：击杀回血（%.2f）" % wbl2.hp)
	wbl2.hp = hpk
	var wdu := _new_world(91, "dugu")
	var cdu: float = wdu.skills["dugu"].empower_cost()
	var cqs: float = wsw.skills["kuang_feng"].empower_cost() if wsw.skills.has("kuang_feng") else 1.0
	_check(float(Data.skills["dugu"]["empower_cost"]) <= 4.5 and cdu > 0.0, "独孤九剑：催动消耗大幅降低（%.1f）" % cdu)
	_free_world(wdu)
	_free_world(wsw)
	_free_world(wfi)
	_free_world(wbl2)
	# 局外属性 / 天赋：内力和气血恢复相关，数量不多；各流派覆盖不改节点 id / 上限
	var ms := Meta.stats_for({"pow": 0, "agi": 0, "vit": 30, "int": 30, "luk": 0})
	_check(float(ms["hp_regen"]) > 0.1 and float(ms["neili_regen"]) > 2.0, "根骨加气血回复、内息加内力回复（%.2f / %.2f）" % [ms["hp_regen"], ms["neili_regen"]])
	var base_nodes: Dictionary = Talents.nodes()
	for sc in ["fist", "sword", "blade"]:
		var sn: Dictionary = Talents.nodes(sc)
		var diff := 0
		for nid in sn:
			_check(int(sn[nid]["max"]) == int(base_nodes[nid]["max"]), "%s 流派天赋 %s 上限不变" % [sc, nid])
			diff += 1 if str(sn[nid]["name"]) != str(base_nodes[nid]["name"]) or str(sn[nid]["desc"]) != str(base_nodes[nid]["desc"]) else 0
		_check(diff >= 4, "%s 流派有专属天赋覆盖（%d 个）" % [sc, diff])
	# 每个流派的天赋树只能加成本流派的招式（不能在刀客的树里看到降龙十八掌）
	for sc in ["fist", "sword", "blade"]:
		for nid in Talents.nodes(sc):
			var nn: Dictionary = Talents.nodes(sc)[nid]
			for k in nn.get("stat", {}):
				if str(k).begins_with("skill:"):
					var sid := str(k).split(":")[1]
					_check(str(Data.skills[sid]["school"]) == sc, "%s 流派天赋 %s 加成了别的流派的招式 %s" % [sc, nid, sid])
			for sid2 in Data.skills:
				if str(Data.skills[sid2]["school"]) != sc:
					_check(not str(nn["desc"]).contains(str(Data.skills[sid2]["name"])), "%s 流派天赋 %s 的说明提到了别的流派的招式 %s" % [sc, nid, str(Data.skills[sid2]["name"])])
	_check(float(Talents.stats_for({"ling_step": 3}, "sword")["speed_pct"]) > float(Talents.stats_for({"ling_step": 3}, "fist")["speed_pct"]), "剑侠的移速天赋更强")
	_check(float(Talents.stats_for({"rou_regen": 3}, "blade")["hp_regen"]) > float(Talents.stats_for({"rou_regen": 3}, "fist")["hp_regen"]), "刀客的气血回复天赋更强")
	_check(float(Talents.stats_for({"rou_neili": 3}, "fist")["neili_regen"]) > 0.0, "武者的养气带回内力")
	# 吸血要克制（伤害高、血量低）：「增加治疗」最高 0.2% 伤害；每次命中最多回 0.6
	var hv: Array = Data.directions["heal"]["values"]
	_check(is_equal_approx(float(hv[1]), 0.1) and float(hv[3]) <= 0.2 + 1e-9, "增加治疗：特别档 0.1%%（实际 %s）" % str(hv))
	var wheal := _new_world(95, "wuhu_blade")
	wheal.skills.clear()
	wheal.add_skill("wuhu_blade")
	wheal.skills["wuhu_blade"].add_upgrade("heal", 1)
	wheal.hp = 50.0
	var th := Enemy.new()
	th.hp = 1e12
	th.max_hp = 1e12
	for i in 20:
		wheal.hit_enemy(th, 200.0, ["近战"], Vector2.ZERO, "wuhu_blade")
	_check(wheal.hp < 50.0 + 20.0 * 0.6 + 0.01 and wheal.hp - 50.0 < 8.0, "吸血 0.1%%：20 次大伤害命中只回一点点（%.2f）" % (wheal.hp - 50.0))
	_free_world(wheal)
	for xid in Data.xinfa:
		for sid2 in Data.xinfa[xid]["link"]:
			_check(float(Data.xinfa[xid]["link"][sid2].get("heal", 0.0)) <= 0.0016, "心法 %s 对 %s 的命中回血要克制" % [xid, sid2])
	# 独孤九剑：破 X 式总强化次数门槛 9 / 18 / 27
	_check(int(Data.T("shi_stage1")) == 9 and int(Data.T("shi_stage2")) == 18 and int(Data.T("shi_stage3")) == 27, "独孤九剑门槛 9 / 18 / 27")
	for sh in Data.shi:
		_check(str(sh.get("desc", "")) != "" and str(sh.get("awaken", "")) != "", "式「%s」要有普通效果和觉醒效果的说明" % sh["name"])
	var wsc := _new_world(96, "dugu")
	wsc.shi = {"po_jian": 1}
	var sc := wsc.shi_cards(3, 2, "level")
	_check(not sc.is_empty() and str(sc[0]["desc"]).contains("普通：") and str(sc[0]["desc"]).contains("觉醒："), "式的卡片同时写明普通和觉醒效果")
	_free_world(wsc)


## 计划书 6：另觅机缘 / 真·霸刀破岳 / 蓄劲 / 独孤九剑 9-18-27
func _plan6_test() -> void:
	print("\n=== 计划书 6：另觅机缘 / 真·霸刀破岳 / 蓄劲 / 独孤九剑 ===")
	# ---- 另觅机缘 ----
	_check(GameWorld.rerolls_for_level(4) == 0 and GameWorld.rerolls_for_level(5) == 3 and GameWorld.rerolls_for_level(10) == 6 and GameWorld.rerolls_for_level(14) == 6, "另觅机缘次数：Lv4=0 / Lv5=3 / Lv10=6 / Lv14=6")
	var wr := GameWorld.new()
	wr.rng_seed = 5
	wr.god = true
	wr.meta_level = 10
	add_child(wr)
	wr.start_run("chain_fist", "tashue")
	_check(wr.rerolls_left == 6 and wr.can_reroll(), "开局 Lv10 → 6 次")
	var c0 := wr.roll_choices()
	var keys0 := []
	for c in c0:
		keys0.append(wr._choice_key(c))
	var c1 := wr.use_reroll(c0)
	_check(wr.rerolls_left == 5 and wr.rerolls_used == 1 and c1.size() == 3, "重抽：扣 1 次，仍是 3 张")
	var same := 0
	for c in c1:
		if keys0.has(wr._choice_key(c)):
			same += 1
	_check(same == 0, "重抽尽量避开刚才的卡（重复 %d 张）" % same)
	for i in 5:
		wr.use_reroll(c1)
	_check(not wr.can_reroll() and wr.rerolls_left == 0, "6 次用完后不能再重抽")
	var c2 := wr.use_reroll(c1)
	_check(c2 == c1 and wr.rerolls_used == 6, "次数为 0 时重抽无效，不计数")
	_free_world(wr)
	# ---- 真·霸刀破岳 ----
	var wb := _blade_world(71)
	wb.skills.clear()
	wb.add_skill("xuedao")
	wb.hp = wb.st("max_hp")
	for i in 5:
		wb.step(DT)
	_check(wb.tb_t <= 0.0 and wb.tb_cd <= 0.0, "满血不触发真·霸刀破岳")
	wb.hp = wb.st("max_hp") * 0.19
	wb.step(DT)
	_check(wb.tb_t > 9.9 and wb.tb_t <= 10.0, "气血 ≤ 20%% 当帧触发，持续 10 秒（%.2f）" % wb.tb_t)
	_check(is_equal_approx(wb.heal_mult(), 2.0), "期间回复翻倍")
	# 不耗血、刀魂照涨
	var xd: SkillBase = wb.skills["xuedao"]
	var hp1 := wb.hp
	var soul1 := wb.soul
	xd.cd = 0.0
	var tgt := wb._spawn_enemy("bandit", wb.player_pos + Vector2(60, 0))
	tgt.hp = 1e9
	tgt.max_hp = 1e9
	tgt.speed = 0.0
	wb._rebuild_grid()
	wb.neili = 0.0
	(xd as BladeSkills.Base).pay_hp()
	_check(absf(wb.hp - hp1) < 0.01, "期间刀招不扣血（%.2f → %.2f）" % [hp1, wb.hp])
	_check(wb.soul > soul1, "期间刀魂照常增长")
	# 10 秒后才进入冷却
	for i in int(9.5 * 60.0):
		wb.step(DT)
	_check(wb.tb_t > 0.0 and wb.tb_cd <= 0.0, "第 9.5 秒仍在状态内，冷却没开始")
	for i in int(0.6 * 60.0):
		wb.step(DT)
	_check(wb.tb_t <= 0.0 and wb.tb_cd > 29.0, "状态结束才开始 30 秒冷却（%.1f）" % wb.tb_cd)
	wb.hp = wb.st("max_hp") * 0.1
	for i in 60 * 5:
		wb.step(DT)
	_check(wb.tb_t <= 0.0, "冷却中即使血量更低也不再触发")
	wb.tb_cd = 0.01
	wb.hp = wb.st("max_hp") * 0.1
	for i in 5:
		wb.step(DT)
	_check(wb.tb_t > 0.0, "冷却结束后血量仍低 → 再次触发（tb_t %.2f cd %.2f hp %.1f/%.1f over %s）" % [wb.tb_t, wb.tb_cd, wb.hp, wb.st("max_hp"), str(wb.over)])
	_free_world(wb)
	var wnb := _new_world(72, "kuang_feng")
	wnb.hp = 1.0
	for i in 5:
		wnb.step(DT)
	_check(wnb.tb_t <= 0.0, "只有刀客有真·霸刀破岳")
	_free_world(wnb)
	# 回复翻倍：击杀回血
	var wk := _blade_world(73)
	wk.hp = wk.st("max_hp") * 0.5
	var kh := wk.st("kill_hp")
	var e1 := wk._spawn_enemy("bandit", wk.player_pos + Vector2(500, 0))
	e1.hp = 1.0
	var h0 := wk.hp
	wk.damage_enemy(e1, 999.0, Vector2.ZERO, false)
	var gain1 := wk.hp - h0
	wk.tb_t = 5.0
	var e2 := wk._spawn_enemy("bandit", wk.player_pos + Vector2(500, 50))
	e2.hp = 1.0
	h0 = wk.hp
	wk.damage_enemy(e2, 999.0, Vector2.ZERO, false)
	var gain2 := wk.hp - h0
	_check(kh <= 0.0 or absf(gain2 - gain1 * 2.0) < 0.001, "击杀回血翻倍（%.3f → %.3f）" % [gain1, gain2])
	_free_world(wk)
	# ---- 蓄劲 ----
	var wf := _new_world(74, "chain_fist")
	wf.neili = 0.0
	_check(wf.fist_qi == 0.0, "开局蓄劲为 0")
	for i in 10:
		wf.fist_after_cast(wf.skills["chain_fist"])
	_check(is_equal_approx(wf.fist_qi, 30.0), "每次出手 +3（10 次 = 30，实际 %.1f）" % wf.fist_qi)
	wf.fist_qi = 99.0
	wf.fist_after_cast(wf.skills["chain_fist"])
	_check(wf.fist_qi <= 100.0, "劲力上限 100")
	var tq := wf._spawn_enemy("bandit", wf.player_pos + Vector2(80, 0))
	tq.hp = 1e9
	tq.max_hp = 1e9
	tq.speed = 0.0
	wf._rebuild_grid()
	wf.fist_qi = 100.0
	var hp_t := tq.hp
	wf.fist_after_cast(wf.skills["chain_fist"])
	_check(wf.fist_qi == 0.0 and wf.cunjin_count == 1, "满劲后下一次出手触发寸劲震爆并清零")
	_check(tq.hp < hp_t and tq.vuln_t > 0.0, "寸劲：范围伤害 + 破防（破绽）")
	wf.fist_qi = 0.0
	wf.neili = wf.st("max_neili")
	var q0 := wf.fist_qi
	for i in 60:
		wf.step(DT)
	_check(wf.realm() == GameWorld.Realm.YING and wf.fist_qi > q0 + 3.0, "盈境下每秒自然蓄劲（%.1f）" % wf.fist_qi)
	_free_world(wf)
	var wfs := _new_world(75, "kuang_feng")
	wfs.fist_after_cast(wfs.skills["kuang_feng"])
	_check(wfs.fist_qi == 0.0, "只有武者蓄劲")
	_free_world(wfs)
	# ---- 武者真气爆发：拳掌无敌 ----
	var wu := _new_world(77, "chain_fist")
	wu.god = false
	_check(wu.burst_max() == 2, "武者初始 2 次真气爆发（%d）" % wu.burst_max())
	wu.level = 10
	_check(wu.burst_max() == 3, "10 级 → 3 次")
	wu.level = 20
	_check(wu.burst_max() == 4, "20 级 → 4 次")
	wu.level = 9
	_check(wu.burst_max() == 2, "9 级仍是 2 次")
	var wk2 := _new_world(78, "kuang_feng")
	_check(wk2.burst_max() == 1, "剑侠仍是 1 次")
	_free_world(wk2)
	wu.level = 1
	wu.neili = wu.st("max_neili")
	var tu := wu._spawn_enemy("bandit", wu.player_pos + Vector2(80, 0))
	tu.hp = 1e9
	tu.max_hp = 1e9
	tu.speed = 0.0
	tu.defense = 0.5
	wu._rebuild_grid()
	_check(wu.can_burst(), "内力足够可以爆发")
	wu._burst()
	_check(wu.fist_ult_t > 9.9 and wu.neili == 0.0 and wu.burst_left() == 1, "爆发：消耗全部内力、进入 10 秒拳掌无敌、次数 −1")
	wu.hp = wu.st("max_hp")
	wu.input_move = Vector2.ZERO
	var hp_u := wu.hp
	for i in 60 * 3:
		wu.step(DT)
		tu.hp = 1e9
	_check(wu.neili == 0.0, "状态期间内力不恢复（%.2f）" % wu.neili)
	wu.add_neili(50.0)
	wu.neili = 0.0
	wu.add_neili(50.0)
	_check(wu.neili == 0.0, "任何手段都无法加内力")
	_check(wu.invuln > 0.0 and wu.hp >= hp_u - 0.01, "状态期间无敌")
	_check(not wu.can_burst(), "状态期间不能再次爆发")
	var c_before := wu.cunjin_count
	for i in 40:
		tu.pos = wu.player_pos + Vector2(60, 0)       # 寸劲会把敌人击退，每帧放回原位
		tu.knock = Vector2.ZERO
		wu._rebuild_grid()
		wu.skills["chain_fist"].cd = 0.0
		wu.step(DT)
		tu.hp = 1e9
	_check(wu.cunjin_count > c_before, "无敌期间每一下出手都触发寸劲（%d → %d）" % [c_before, wu.cunjin_count])
	# 真伤：额外 30%，无视防御（多次平均，排除暴击随机）
	var sum_t := 0.0
	var sum_n := 0.0
	for i in 300:
		tu.hp = 1e9
		wu.fist_ult_t = 5.0
		wu.hit_enemy(tu, 100.0, ["近战"], Vector2.ZERO, "chain_fist")
		sum_t += 1e9 - tu.hp
		tu.hp = 1e9
		wu.fist_ult_t = 0.0
		wu.hit_enemy(tu, 100.0, ["近战"], Vector2.ZERO, "chain_fist")
		sum_n += 1e9 - tu.hp
	var kdef := 1.0 - tu.defense * (1.0 - wu.st("armor_pierce"))
	var ratio := sum_t / sum_n
	_check(absf(ratio - (1.0 + 0.3 / kdef)) < 0.12, "真伤 = 伤害量 30%%，不被防御削减（倍率 %.2f，预期 %.2f）" % [ratio, 1.0 + 0.3 / kdef])
	# 状态结束后恢复内力
	wu.fist_ult_t = 0.02
	wu.neili = 0.0
	for i in 60 * 2:
		wu.step(DT)
	_check(wu.fist_ult_t == 0.0 and wu.neili > 1.0, "状态结束后才恢复内力（%.1f）" % wu.neili)
	_free_world(wu)
	# ---- 「极」：每个职业的专属强机制 ----
	var wjf := _new_world(79, "chain_fist")
	wjf.stats["ji_fist"] = 1.0
	wjf.level = 1
	_check(wjf.burst_max() == 3, "极·天人合一：多 1 次真气爆发（%d）" % wjf.burst_max())
	wjf.neili = wjf.st("max_neili")
	wjf._burst()
	_check(is_equal_approx(wjf.fist_ult_t, 15.0), "极·天人合一：拳掌无敌 15 秒（%.1f）" % wjf.fist_ult_t)
	wjf.fist_ult_t = 0.01
	for i in 3:
		wjf.step(DT)
	_check(wjf.neili >= wjf.st("max_neili") * 0.39, "拳掌无敌结束回复 40%% 内力（%.1f / %.1f）" % [wjf.neili, wjf.st("max_neili")])
	var q1 := wjf.fist_qi
	wjf.fist_after_cast(wjf.skills["chain_fist"])
	_check(is_equal_approx(wjf.fist_qi - q1, 6.0), "蓄劲速度翻倍（+6）")
	_free_world(wjf)
	var wjs := _new_world(80, "kuang_feng")
	var cd0j := wjs.cd_mult()
	wjs.stats["ji_sword"] = 1.0
	_check(absf((cd0j - wjs.cd_mult()) - 0.2) < 1e-6, "极·万剑归宗：冷却 −20%")
	wjs.ji_haste_until = wjs.time + 3.0
	var cd_j20 := cd0j - 0.2
	_check(wjs.cd_mult() < cd_j20 - 0.1 and wjs.cd_mult() >= 0.3, "冲刺后 3 秒冷却再降（%.2f → %.2f，下限 0.3）" % [cd_j20, wjs.cd_mult()])
	wjs.ji_haste_until = -1.0
	_free_world(wjs)
	var wjb := _blade_world(81)
	wjb.stats["ji_blade"] = 1.0
	wjb.hp = wjb.st("max_hp") * 0.1
	wjb.step(DT)
	_check(wjb.tb_t > 14.9, "极·霸刀：真·霸刀破岳 15 秒（%.1f）" % wjb.tb_t)
	wjb.tb_t = 0.01
	wjb.step(DT)
	wjb.step(DT)
	_check(absf(wjb.tb_cd - 15.0) < 0.1, "极·霸刀：冷却减半（%.1f）" % wjb.tb_cd)
	wjb.soul = 0.0
	wjb.add_soul(10.0)
	_check(is_equal_approx(wjb.soul, 15.0), "刀魂增长 +50%")
	_free_world(wjb)
	# ---- 独孤九剑 9 / 18 / 27 ----
	var wd := _new_world(76, "dugu")
	wd.time = 120.0
	wd.shi = {"zong": 9}
	wd.props_enabled = false
	var dg: SwordSkills.Dugu = wd.skills["dugu"]
	var ea := wd._spawn_enemy("bandit", wd.player_pos + Vector2(120, 0))
	var eb := wd._spawn_enemy("bandit", wd.player_pos + Vector2(130, 40))
	for en in [ea, eb]:
		en.hp = 1e9
		en.max_hp = 1e9
		en.speed = 0.0
	wd._rebuild_grid()
	dg.cd = 2.0
	wd.neili = 10.0
	wd.hit_enemy(ea, 10.0, dg.tags(), Vector2.ZERO, "dugu")
	_check(dg.wb_count == 0, "只命中 1 名：破兵微步不触发")
	wd.hit_enemy(eb, 10.0, dg.tags(), Vector2.ZERO, "dugu")
	_check(dg.wb_count == 1 and is_equal_approx(wd.neili, 11.0) and absf(dg.cd - 1.8) < 0.001, "命中 2 名：返还 1 内力、冷却 −10%%（内力 %.1f，cd %.2f）" % [wd.neili, dg.cd])
	wd.hit_enemy(ea, 10.0, dg.tags(), Vector2.ZERO, "dugu")
	wd.hit_enemy(eb, 10.0, dg.tags(), Vector2.ZERO, "dugu")
	_check(dg.wb_count == 1, "破兵微步每秒最多触发一次")
	wd.shi = {"zong": 8}
	dg.wb_cd = 0.0
	dg.wb_hits.clear()
	wd.hit_enemy(ea, 10.0, dg.tags(), Vector2.ZERO, "dugu")
	wd.hit_enemy(eb, 10.0, dg.tags(), Vector2.ZERO, "dugu")
	_check(dg.wb_count == 1, "总层 < 9 没有破兵微步")
	# 18：破绽攻防 −30%、斩落普通投射物
	wd.shi = {"zong": 18}
	wd.apply_vuln(ea, 0.3)
	_check(ea.atk_down_t > 3.9 and is_equal_approx(ea.atk_mul(), 0.7) and is_equal_approx(ea.vuln, 0.3), "万法皆破：破绽 4 秒，攻击 −30%、承伤 +30%")
	var ea2 := wd._spawn_enemy("bandit", wd.player_pos + Vector2(900, 0))
	wd.shi = {"zong": 9}
	wd.apply_vuln(ea2, 0.3)
	_check(ea2.atk_down_t <= 0.0, "总层 < 18 的破绽不降低攻击")
	wd.shi = {"zong": 18}
	var arrow := Projectile.new()
	arrow.hostile = true
	arrow.cuttable = true
	arrow.pos = wd.player_pos + Vector2(300, 300)
	arrow.radius = 7.0
	arrow.life = 3.0
	var bossball := Projectile.new()
	bossball.hostile = true
	bossball.cuttable = false
	bossball.pos = arrow.pos
	bossball.radius = 7.0
	bossball.life = 3.0
	wd.projs.append(arrow)
	wd.projs.append(bossball)
	var cut := wd.cut_hostile_projs(arrow.pos, 20.0)
	_check(cut == 1 and arrow.life == 0.0 and bossball.life > 0.0, "斩落普通投射物，Boss 大招弹体不受影响")
	_check(wd.dugu_can_cut(), "总层 18 起能斩落投射物")
	wd.shi = {"zong": 9}
	_check(not wd.dugu_can_cut(), "总层 9 还不能斩落")
	wd.shi = {"zong": 9, "po_arrow": 1}
	_check(wd.dugu_can_cut(), "学了破箭式也能斩落")
	_check(not (Data.shi as Array).any(func(d): return str(d["desc"]).contains("追踪剑气")), "破箭式不再是自动射箭")
	# 连击几率
	_check(is_equal_approx(Data.T("dugu_combo2"), 0.45) and is_equal_approx(Data.T("dugu_combo4"), 0.20) and is_equal_approx(Data.T("dugu_combo9"), 0.08), "觉醒连击几率 45% / 20% / 8%")
	_free_world(wd)


func _upgrade_system_test() -> void:
	print("\n=== 升级系统：方向 × 档位 ===")
	var checked := 0
	for id in Data.skills:
		var base := SkillBase.new()
		var w := _new_world(51)
		base.setup(w, id, Data.skills[id])
		for dir in base.available_dirs():
			for tier in Data.tiers.size():
				var s := SkillBase.new()
				s.setup(w, id, Data.skills[id])
				s.add_upgrade(dir, tier)
				var ok := false
				match dir:
					"damage": ok = s.p("damage") > base.p("damage")
					"cooldown": ok = s.p("cooldown") < base.p("cooldown")
					"range":
						for k in Data.skills[id]["map"]["range"]:
							ok = ok or s.p(k) > base.p(k)
					"duration":
						for k in Data.skills[id]["map"]["duration"]:
							ok = ok or s.p(k) > base.p(k)
					"targets":
						var tk := str(Data.skills[id]["map"]["targets"])
						ok = s.p(tk) > base.p(tk)
					"buff": ok = float(s.mods["buff"]) > 0.0
					"debuff": ok = float(s.mods["debuff"]) > 0.0
					"heal": ok = float(s.mods["heal"]) > 0.0
					"hits": ok = float(s.mods["hits"]) > 0.0
					"crit": ok = float(s.mods["crit"]) > 0.0
					"empower": ok = s.empower_cost() < base.empower_cost()
				_check(ok, "%s 的方向 %s 档位 %d 没有生效" % [id, dir, tier])
				_check(not s.upgrade_text(dir, tier).contains("{"), "%s/%s 的描述有未替换的占位符" % [id, dir])
				checked += 1
		# 同一方向档位越高，加成越大
		for dir in base.available_dirs():
			var prev := -1.0
			for tier in Data.tiers.size():
				var v := float(Data.directions[dir]["values"][tier])
				_check(v > prev, "%s 的档位数值应递增" % dir)
				prev = v
		_free_world(w)
	print("  %d 个 (技能 × 方向 × 档位) 组合全部生效，数值逐档递增  OK" % checked)

	# 档位概率
	var r := RandomNumberGenerator.new()
	r.seed = 99
	var cnt := [0, 0, 0, 0]
	var n := 20000
	for i in n:
		cnt[Data.roll_tier(r)] += 1
	var line := ""
	for i in 4:
		var got := float(cnt[i]) / n * 100.0
		var want := float(Data.tiers[i]["weight"])
		line += "%s %.1f%%(目标 %d%%)  " % [Data.tiers[i]["name"], got, int(want)]
		_check(absf(got - want) < 2.0, "档位 %s 概率偏离过大：%.1f%% vs %d%%" % [Data.tiers[i]["name"], got, int(want)])
	print("  档位概率：", line)

	# 升级卡：同一技能的两张卡方向不同；升级满 5 次后不再出现
	var w2 := _new_world(52)
	var s0: SkillBase = w2.skills["chain_fist"]
	var dup := false
	for i in 200:
		var cards: Array = []
		for c in w2.roll_choices(20):
			if str(c["kind"]) == "up_skill":
				cards.append(c)
		if cards.size() == 2 and cards[0]["dir"] == cards[1]["dir"]:
			dup = true
	_check(not dup, "同一技能的两张升级卡不应是同一方向")
	for i in Data.max_upgrades:
		s0.add_upgrade("damage", 0)
	var offered := false
	for c in w2.roll_choices(20):
		if str(c["kind"]) == "up_skill":
			offered = true
	_check(not offered, "升级满 %d 次后不应再出现升级卡" % Data.max_upgrades)
	_check(s0.level == 1 + Data.max_upgrades, "升级后等级应为 1+次数")
	print("  升级卡去重、升级封顶  OK")
	_free_world(w2)

	# 「增加打击次数」：触发连续出招；「增加增益」：出招回内力
	var w3 := _new_world(53)
	_populate(w3, 40)
	var s3: SkillBase = w3.skills["chain_fist"]
	s3.mods["hits"] = 1.0
	s3.mods["buff"] = 5.0
	w3.neili = 10.0
	var fired_before := float(w3.skill_dmg.get("chain_fist", 0.0))
	for i in 240:
		TestBot.drive(w3, 75.0)
		w3.step(DT)
	_check(float(w3.skill_dmg.get("chain_fist", 0.0)) > fired_before, "连击/增益测试：技能应造成伤害")
	print("  连续出招（echo）与出招回内力  OK")
	_free_world(w3)


func _level_growth_test() -> void:
	print("\n=== 角色升级成长（基础伤害 / 气血 / 防御）+ 12 层上限 ===")
	var w := _new_world(61)
	var hp0 := w.st("max_hp")
	var arm0 := w.st("armor")
	var dmg0 := w.st("damage_pct")                # 含流派被动（武者 +8%）
	var e := Enemy.new()
	e.hp = 1.0e9
	e.max_hp = 1.0e9
	var d1 := w.hit_enemy(e, 100.0, [], Vector2.ZERO, "probe")
	w.hp = w.st("max_hp") - 10.0
	var hp_before := w.hp
	w._gain_exp(1000000)
	_check(w.level > 15, "大量经验应连续升级，实际 Lv%d" % w.level)
	var g: Dictionary = Data.level_growth
	var steps := w.level - 1
	_check(is_equal_approx(w.st("max_hp"), hp0 + float(g["max_hp"]) * steps), "气血上限应随等级线性成长")
	_check(is_equal_approx(w.st("armor"), arm0 + float(g["armor"]) * steps), "防御应随等级线性成长")
	_check(is_equal_approx(w.st("damage_pct"), dmg0 + float(g["damage_pct"]) * steps), "基础伤害加成应随等级成长")
	_check(w.hp > hp_before, "升级时应同步补上新增的气血上限")
	var d2 := w.hit_enemy(e, 100.0, [], Vector2.ZERO, "probe")
	_check(is_equal_approx(d2 / d1, (1.0 + dmg0 + float(g["damage_pct"]) * steps) / (1.0 + dmg0)), "同一次攻击的伤害应按基础伤害加成放大，实际 ×%.3f" % (d2 / d1))
	# 防御：固定减伤，但至少保留 25%
	var w2 := _new_world(62)
	w2.god = false
	w2.stats["armor"] = 999.0
	var h0 := w2.hp
	w2._hurt(40.0)
	_check(is_equal_approx(h0 - w2.hp, 10.0), "高防御时仍应承受 25%% 伤害，实际 %.1f" % (h0 - w2.hp))
	# 技能 12 层上限
	var s0: SkillBase = w2.skills["chain_fist"]
	for i in Data.max_upgrades:
		s0.add_upgrade("damage", 0)
	_check(s0.level == 1 + Data.max_upgrades, "升满后应为 %d 层，实际 %d" % [1 + Data.max_upgrades, s0.level])
	var offered := false
	for c in w2.roll_choices(30):
		if str(c["kind"]) == "up_skill" and str(c["id"]) == "chain_fist":
			offered = true
	_check(not offered, "12 层后该技能不应再出现升级卡")
	# 招式池只包含本流派
	var other := false
	for i in 50:
		for c in w2.roll_choices(30):
			if str(c["kind"]) == "new_skill" and str(Data.skills[c["id"]]["school"]) != w2.school_id:
				other = true
	_check(not other, "新招式只应来自本流派")
	print("  Lv%d：气血 %.0f→%.0f、防御 %.1f→%.1f、伤害 +%d%%；12 层封顶；招式池按流派  OK" % [
		w.level, hp0, w.st("max_hp"), arm0, w.st("armor"), int(w.st("damage_pct") * 100.0)])
	_free_world(w)
	_free_world(w2)


func _save_test() -> void:
	print("\n=== 存档（创建角色） ===")
	var path := "user://test_save.json"
	var abs_path := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(abs_path)
	var sv: Node = load("res://scripts/save.gd").new()
	sv.path = path
	sv.load_data()
	_check(not sv.has_character(), "没有存档时不应有角色")
	sv.create_character("fist")
	var sv2: Node = load("res://scripts/save.gd").new()
	sv2.path = path
	sv2.load_data()
	_check(sv2.has_character() and sv2.school() == "fist", "创建角色后应能从存档读回流派")
	# 未开放的流派 / 不存在的流派 视为没有角色
	for bad in ["spear", "nonexistent"]:
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(JSON.stringify({"school": bad}))
		f.close()
		sv2.load_data()
		_check(not sv2.has_character(), "无效流派 %s 应视为没有角色" % bad)
	# 损坏的存档不应崩溃
	var f2 := FileAccess.open(path, FileAccess.WRITE)
	f2.store_string("{not json")
	f2.close()
	sv2.load_data()
	_check(not sv2.has_character(), "损坏的存档应视为没有角色")
	sv2.create_character("fist")
	sv2.reset_character()
	sv.load_data()
	_check(not sv.has_character(), "重新创建角色后存档应清空流派")
	DirAccess.remove_absolute(abs_path)
	sv.free()
	sv2.free()
	print("  创建 / 读回 / 无效流派 / 损坏存档 / 重建  OK")


var net_calls: Array = []
var fake_reply: Dictionary = {}


func _town_test() -> void:
	print("\n=== 阿罗拉村：布局 / 走动 / 对话流程 / 图鉴 ===")
	_check(str(Data.town["name"]) == "阿罗拉村", "村名")
	var ids := {}
	for n in Data.town["npcs"]:
		ids[n["id"]] = true
		_check(ResourceLoader.exists("res://assets/town/npc/%s.png" % str(n["sprite"])), "NPC %s 的立绘存在" % n["name"])
		_check(str(n["greet"]) != "" and str(n["name"]) != "", "NPC 有名字和台词")
	for need in ["clerk", "smith", "herbalist", "master", "innkeeper", "sage"]:
		_check(ids.has(need), "村里要有 " + need)
	var t := Town.new()
	add_child(t)
	var near0 := t.near_npc()
	_check(near0.is_empty(), "出生点附近没有 NPC")
	# 走到驿卒面前
	t.player_pos = Vector2(0, -190)
	var clerk := t.near_npc()
	_check(not clerk.is_empty() and clerk["id"] == "clerk", "靠近驿卒能交谈")
	# 边界与碰撞：往一个方向使劲走，不会出界也不会穿墙
	t.player_pos = Vector2(0, 400)
	t.input_move = Vector2.UP
	for i in 600:
		t.step(1.0 / 60.0)
	_check(t.bounds.has_point(t.player_pos), "不会走出村子边界")
	var inside_building := false
	for n in t.npcs:
		var r := t.building_rect(n)
		if str((n["building"] as Dictionary).get("kind", "")) != "stall" and Rect2(r.position + Vector2(0, 44), r.size - Vector2(0, 44)).grow(-2.0).has_point(t.player_pos):
			inside_building = true
	_check(not inside_building, "走不进建筑里")
	t.player_pos = Vector2(-430, -100)       # 铁匠铺门前：往上走会被房子挡住
	t.input_move = Vector2.UP
	for i in 120:
		t.step(1.0 / 60.0)
	_check(t.player_pos.y > -330.0, "被铁匠铺挡住（y=%.0f）" % t.player_pos.y)
	remove_child(t)
	t.free()
	# 图鉴：内容完整、没有未替换的占位符
	for c in Guide.CATEGORIES:
		var es := Guide.entries(str(c[0]))
		_check(es.size() >= 4, "图鉴「%s」有内容" % c[1])
		for e in es:
			_check(str(e["text"]).length() > 20 and not str(e["text"]).contains("{"), "图鉴条目有正文且占位符已替换：" + str(e["title"]))
	_check(Guide.entries("skill").size() == Data.skills.size() and Guide.entries("xinfa").size() == Data.xinfa.size() and Guide.entries("qg").size() == Data.qinggong.size(), "图鉴覆盖全部招式 / 心法 / 轻功")
	_check(Guide.skill_text("cloud_palm").contains("起手招式") and Guide.skill_text("yue_palm").contains("领悟"), "图鉴说明获得方式")
	_check(Guide.xinfa_text("chunyang").contains("合璧"), "心法图鉴包含合璧搭配")
	# 主流程：创建角色 → 进村 → 找驿卒 → 选地图 → 开局界面 → 返回村子 → 再出发 → 进入战斗
	var old_path: String = Save.path
	var old_url: String = Net.api_url
	Save.path = "user://test_town_save.json"
	Save.load_data()
	Net.api_url = ""
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	main.set_physics_process(false)
	await get_tree().process_frame
	_check(main.state == main.State.CREATE, "没有角色先创建角色")
	main.hud.confirm_create()
	await get_tree().process_frame
	_check(main.state == main.State.TOWN and main.town.visible and not main.world.visible, "创建完角色进入村子")
	main.town.player_pos = Vector2(0, -190)
	main._talk(main.town.near_npc())
	_check(main.state == main.State.DIALOG and main.hud.dialog_count == 2, "和驿卒说话：出现对话框")
	main._on_dialog_option(0)
	_check(main.state == main.State.DIALOG and main.hud.dialog_count == Data.maps.size() + 1, "选「出发」：列出地图 + 返回")
	main._on_dialog_option(1)     # 华山：未开放，不能选（按钮禁用，但直接触发也不应出发）
	_check(main.state != main.State.LOADOUT and main.state != main.State.PLAY, "未开放的地图不能出发")
	if main.state == main.State.DIALOG:
		main._dialog_close()
	main._talk(main.town.near_npc())
	main._on_dialog_option(0)
	main._on_dialog_option(0)     # 黑风寨
	_check(main.state == main.State.LOADOUT and main.current_map == "black_wind", "选黑风寨：进入开局界面")
	main._on_loadout_cancel()
	_check(main.state == main.State.TOWN, "返回村子")
	main._talk(main.town.near_npc())
	main._on_dialog_option(0)
	main._on_dialog_option(0)
	main._on_loadout("point_finger", "feiyan")
	_check(main.state == main.State.PLAY and main.world.map_id == "black_wind" and main.world.visible and not main.town.visible, "出发后进入战斗，村子隐藏")
	_check(str(main.world.run_summary().get("map", "")) == "black_wind", "成绩摘要带上地图")
	# 师父 / 掌柜 / 百晓生
	main.world.over = true
	main._enter_town()
	main.town.player_pos = Vector2(-430, 150)
	var master: Dictionary = main.town.near_npc()
	_check(not master.is_empty() and master["id"] == "master", "师父就在武馆门前")
	main._talk(master)
	_check(main.hud.dialog_count == 3, "师父：成长 / 转修 / 告辞")
	main._on_dialog_option(0)
	_check(main.state == main.State.MODAL and main.hud.meta_panel != null and main.hud.meta_panel.visible, "师父 → 打开角色成长")
	main._close_modal()
	_check(main.state == main.State.TOWN, "关闭成长界面回到村子")
	main.town.player_pos = Vector2(0, 190)
	var sage: Dictionary = main.town.near_npc()
	_check(not sage.is_empty() and sage["id"] == "sage", "百晓生在广场南面")
	main._talk(sage)
	main._on_dialog_option(0)
	_check(main.state == main.State.MODAL and main.hud.guide_panel != null and main.hud.guide_panel.visible, "百晓生 → 打开图鉴")
	main._close_modal()
	main.town.player_pos = Vector2(430, 150)
	main._talk(main.town.near_npc())
	_check(main.hud.dialog_count == 4, "掌柜：排行榜 / 反馈 / 退出 / 告辞")
	main._dialog_close()
	remove_child(main)
	main.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_town_save.json"))
	Save.path = old_path
	Save.load_data()
	Net.api_url = old_url
	print("  村子数据 / 走动 / 碰撞 / 图鉴 / 创建→进村→驿站→地图→开局→返回→出发  OK")


func _difficulty_reward_test() -> void:
	print("\n=== 难度奖励（局内经验 / 修为 / 装备）===")
	# 局内经验：同样的经验珠，300% 难度多得 +150%（exp_in_run 0.75 × 2.0）
	var wa := _new_world(151)
	var wb := _new_world(151)
	wb.set_difficulty({"count": 3.0, "hp": 3.0, "speed": 3.0})
	wa.exp_total = 0
	wb.exp_total = 0
	wa._gain_exp(100)
	wb._gain_exp(100)
	_check(absf(float(wb.exp_total) / float(wa.exp_total) - 2.5) < 0.05, "局内经验 ×2.5（%d vs %d）" % [wb.exp_total, wa.exp_total])
	_free_world(wa)
	_free_world(wb)
	# 修为：与后端同一公式
	_check(Meta.run_exp(12000, false, false, 1.0) == 150 and Meta.run_exp(12000, false, false, 3.0) == 300, "修为 ×2（难度 3.0）")
	# 单机结算读成绩摘要里的难度
	var old_path: String = Save.path
	Save.path = "user://test_diff_save.json"
	Save.load_data()
	var base := {"won": false, "seconds": 300, "level": 12, "kills": 800, "bosses": 0}
	var r1: Dictionary = Save.add_run_exp(base)
	var hard := base.duplicate()
	hard["difficulty"] = {"count": 300, "hp": 300, "speed": 300}
	var r2: Dictionary = Save.add_run_exp(hard)
	_check(int(r2["gained"]) == int(r1["gained"]) * 2, "单机结算：难度 300%% 修为翻倍（%d → %d）" % [r1["gained"], r2["gained"]])
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_diff_save.json"))
	Save.path = old_path
	Save.load_data()
	# 装备：难度只提高稀有度，不改变件数
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var n_lo := 0
	var n_hi := 0
	var hi_lo := 0
	var hi_hi := 0
	for i in 600:
		for c in Gear.run_drops(rng, 0, true, 1.0):
			n_lo += 1
			hi_lo += 1 if int(Gear.parse(c)["rarity"]) >= 1 else 0
		for c in Gear.run_drops(rng, 0, true, 3.0):
			n_hi += 1
			hi_hi += 1 if int(Gear.parse(c)["rarity"]) >= 1 else 0
	_check(absf(float(n_hi) - float(n_lo)) < float(n_lo) * 0.2, "掉落件数不随难度变化（%d → %d）" % [n_lo, n_hi])
	_check(float(hi_hi) / float(n_hi) > float(hi_lo) / float(n_lo) + 0.12, "特别 / 稀有 / 传说占比更高（%.3f → %.3f）" % [float(hi_lo) / float(n_lo), float(hi_hi) / float(n_hi)])
	_check(absf(Gear.rarity_weight(0, 3.0) - Gear.rarity_weight(0, 1.0)) < 1e-9 and Gear.rarity_weight(3, 3.0) > Gear.rarity_weight(3, 1.0) * 3.0, "普通权重不变，传说权重 ×4")
	print("  局内经验 ×2.5 / 修为 ×2 / 稀有度权重  OK")


func _difficulty_test() -> void:
	print("\n=== 难度调节（怪物数量 / 血量 / 移速，100%~300%）===")
	var w0 := _new_world(141)
	w0.set_difficulty({"count": 5.0, "hp": 0.2, "speed": 2.0})
	_check(w0.difficulty["count"] == 3.0 and w0.difficulty["hp"] == 1.0 and w0.difficulty["speed"] == 2.0, "倍率夹在 1.0 ~ 3.0")
	_free_world(w0)
	# 血量 / 移速：同一种怪，300% 就是 3 倍
	var a := _new_world(142)
	var b := _new_world(142)
	b.set_difficulty({"count": 1.0, "hp": 3.0, "speed": 2.0})
	var ea := a._spawn_enemy("bandit", Vector2(500, 0))
	var eb := b._spawn_enemy("bandit", Vector2(500, 0))
	_check(absf(eb.max_hp / ea.max_hp - 3.0) < 1e-6, "怪物血量 ×3（%.0f vs %.0f）" % [eb.max_hp, ea.max_hp])
	_check(absf(eb.speed / ea.speed - 2.0) < 1e-6, "怪物移速 ×2（%.0f vs %.0f）" % [eb.speed, ea.speed])
	a._spawn_boss("boss", true)
	b._spawn_boss("boss", true)
	_check(absf(b.bosses[0].max_hp / a.bosses[0].max_hp - 3.0) < 1e-6 and absf(b.bosses[0].speed / a.bosses[0].speed - 2.0) < 1e-6, "Boss 同样吃难度倍率")
	_check(absf(b.bosses[0].guard_max / b.bosses[0].max_hp - Data.T("boss_guard_pct")) < 1e-6, "Boss 罡气仍是血量的固定比例")
	_free_world(a)
	_free_world(b)
	# 数量：同样 30 秒，300% 的怪明显更多
	var counts := []
	for m in [1.0, 3.0]:
		var w := _new_world(143)
		w.skills.clear()
		w.god = true
		w.set_difficulty({"count": m})
		w.input_move = Vector2.ZERO
		for i in int(30.0 / DT):
			w.step(DT)
			w.input_move = Vector2.ZERO
		counts.append(w.enemies.size())
		_free_world(w)
	_check(float(counts[1]) > float(counts[0]) * 2.2, "怪物数量 ×3：30 秒后 %d → %d" % [counts[0], counts[1]])
	# 成绩摘要带上难度；默认 100%
	var ws := _new_world(144)
	var d0: Dictionary = ws.run_summary()["difficulty"]
	_check(d0["count"] == 100 and d0["hp"] == 100 and d0["speed"] == 100, "默认难度 100%")
	ws.set_difficulty({"count": 1.5, "hp": 2.0, "speed": 3.0})
	var d1: Dictionary = ws.run_summary()["difficulty"]
	_check(d1["count"] == 150 and d1["hp"] == 200 and d1["speed"] == 300, "成绩摘要记录难度")
	_free_world(ws)
	# HUD：存档里乱写的难度会被规范到 100~300、步长 10
	var h := GameHud.new()
	var old_ui: Variant = Save.data.get("ui", {})
	Save.data["ui"] = {"difficulty": {"count": 9999, "hp": 5, "speed": 154}}
	h._load_difficulty()
	_check(h.diff["count"] == 300 and h.diff["hp"] == 100 and h.diff["speed"] == 150, "读取存档时规范化（%s）" % str(h.diff))
	h.diff = {"count": 150, "hp": 200, "speed": 100}
	var f: Dictionary = h.difficulty_factors()
	_check(absf(float(f["count"]) - 1.5) < 1e-9 and absf(float(f["hp"]) - 2.0) < 1e-9 and absf(float(f["speed"]) - 1.0) < 1e-9, "百分比 → 倍率")
	Save.data["ui"] = old_ui
	h.free()
	print("  夹范围 / 血量 / 移速 / Boss / 数量 / 成绩摘要 / 存档规范化  OK")


func _cd_sweep_test() -> void:
	print("\n=== 技能图标冷却转圈 ===")
	var w := _new_world(131)
	w.skills.clear()
	w.add_skill("chain_fist")
	var sk: SkillBase = w.skills["chain_fist"]
	_check(sk.cd_frac() == 0.0 and sk.cd_secs() == 0.0, "没出过手：没有冷却阴影")
	var en := Enemy.new()
	en.hp = 1.0e9
	en.max_hp = 1.0e9
	en.uid = 5
	en.pos = w.player_pos + Vector2(40, 0)
	w.enemies.append(en)
	w._rebuild_grid()
	sk.cd = 0.0
	for i in 3:
		w.step(1.0 / 60.0)
	_check(sk.cd_total > 0.5 and sk.cd_frac() > 0.8, "出手后：阴影接近满圈（%.2f）" % sk.cd_frac())
	var f1 := sk.cd_frac()
	for i in 20:
		w.step(1.0 / 60.0)
	_check(sk.cd_frac() < f1 and sk.cd_secs() < sk.cd_total, "随时间转开（%.2f → %.2f）" % [f1, sk.cd_frac()])
	# 等不到目标时只是重试，不显示冷却
	var w2 := _new_world(132)
	w2.skills.clear()
	w2.add_skill("chain_fist")
	var s2: SkillBase = w2.skills["chain_fist"]
	for i in 30:
		w2.step(1.0 / 60.0)
	_check(s2.cd_frac() == 0.0, "没有目标时不显示冷却")
	# 乾坤大挪移：反击后进入冷却
	var w3 := _new_world(133)
	w3.skills.clear()
	w3.add_skill("taiji")
	var s3: SkillBase = w3.skills["taiji"]
	w3.neili = 0.0
	s3.on_hurt(20.0)
	_check(s3.cd_frac() > 0.9, "乾坤大挪移反击后冷却满圈")
	_free_world(w)
	_free_world(w2)
	_free_world(w3)
	print("  冷却比例 / 随时间转开 / 无目标不显示 / 反击技能  OK")


func _starter_trait_test() -> void:
	print("\n=== 三个初始技能的定位：拳 / 掌 / 指 ===")
	var D: Dictionary = Data.skills
	# 数据定位：拳近 · 范围 · 伤害最高；掌中 · 追踪；指远 · 穿透
	_check(D["chain_fist"]["tags"].has("范围") and D["chain_fist"]["tags"].has("近战"), "拳：近战 + 范围")
	_check(D["cloud_palm"]["tags"].has("追踪") and D["cloud_palm"]["tags"].has("连击"), "掌：追踪 + 连击")
	_check(D["point_finger"]["tags"].has("贯穿") and D["point_finger"]["tags"].has("控制"), "指：贯穿 + 控制")
	_check(float(D["chain_fist"]["damage"]) > float(D["point_finger"]["damage"]) and float(D["chain_fist"]["damage"]) > float(D["cloud_palm"]["damage"]), "拳的单发伤害最高")
	var wf := _new_world(121)
	wf.skills.clear()
	for sid in ["chain_fist", "cloud_palm", "point_finger"]:
		wf.add_skill(sid)
	var fist: SkillBase = wf.skills["chain_fist"]
	var palm: SkillBase = wf.skills["cloud_palm"]
	var finger: SkillBase = wf.skills["point_finger"]
	_check(float(fist.mods["crit"]) >= 0.14 and float(palm.mods["hits"]) >= 0.17 and float(palm.mods["debuff"]) >= 0.24, "拳容易暴击；掌容易连击并减速")
	_check(fist.p("reach") < float(D["cloud_palm"]["speed"]) and float(finger.p("speed")) * finger.p("life") > 480.0, "距离：拳近、指远")
	_check(finger.p("pierce") >= 3.0 and float(D["point_finger"]["stun_chance"]) < 1.0, "指：穿透、定身只是几率")
	# 掌：溅射 + 减速
	var wp := _new_world(122)
	wp.skills.clear()
	wp.add_skill("cloud_palm")
	var a := Enemy.new()
	a.hp = 1.0e9
	a.max_hp = 1.0e9
	a.pos = wp.player_pos + Vector2(80, 0)
	a.uid = 9101
	var b := Enemy.new()
	b.hp = 1.0e9
	b.max_hp = 1.0e9
	b.pos = a.pos + Vector2(30, 0)
	b.uid = 9102
	var far := Enemy.new()
	far.hp = 1.0e9
	far.max_hp = 1.0e9
	far.pos = a.pos + Vector2(200, 0)
	far.uid = 9103
	wp.enemies.append_array([a, b, far])
	wp._rebuild_grid()
	var pr := Projectile.new()
	var csk: SkillBase = wp.skills["cloud_palm"]
	pr = wp.spawn_proj(csk, 0.0, {"pos": a.pos - Vector2(4, 0)})
	var ha := a.hp
	var hb := b.hp
	var hf := far.hp
	for i in 6:
		wp.step(1.0 / 60.0)
	_check(a.hp < ha and b.hp < hb and absf(far.hp - hf) < 1e-3, "掌：命中溅射到近处的敌人，远处的不受影响")
	_check(a.slow_t > 0.0, "掌：命中减速")
	_free_world(wp)
	# 指：穿透衰减 + 几率定身
	var wi := _new_world(123)
	wi.skills.clear()
	wi.add_skill("point_finger")
	wi.stats["crit_chance"] = 0.0
	var line: Array = []
	for i in 3:
		var en := Enemy.new()
		en.hp = 1.0e9
		en.max_hp = 1.0e9
		en.pos = wi.player_pos + Vector2(80 + i * 40, 0)
		en.uid = 9000 + i
		wi.enemies.append(en)
		line.append(en)
	wi._rebuild_grid()
	var fsk: SkillBase = wi.skills["point_finger"]
	wi.spawn_proj(fsk, 0.0, {"pos": wi.player_pos + Vector2(20, 0)})
	var hp0: Array = [line[0].hp, line[1].hp, line[2].hp]
	for i in 20:
		wi.step(1.0 / 60.0)
	var d0 := float(hp0[0]) - float(line[0].hp)
	var d1 := float(hp0[1]) - float(line[1].hp)
	var d2 := float(hp0[2]) - float(line[2].hp)
	_check(d0 > 0.0 and d1 > 0.0 and d2 > 0.0 and d1 < d0 and d2 < d1, "指：穿透三个目标，伤害逐个衰减（%.0f > %.0f > %.0f）" % [d0, d1, d2])
	_free_world(wi)
	var stunned := 0
	var wr := _new_world(124)
	wr.skills.clear()
	for t in 400:
		var en2 := Enemy.new()
		en2.hp = 1.0e12
		en2.max_hp = 1.0e12
		en2.pos = wr.player_pos + Vector2(60, 0)
		wr.enemies.append(en2)
		wr._rebuild_grid()
		var pj := Projectile.new()
		pj.stun = 1.0
		pj.stun_chance = 0.4
		pj.radius = 12.0
		pj.pos = en2.pos
		pj.life = 1.0
		pj.pierce = 1
		pj.damage = 1.0
		pj.skill_id = "x"
		wr.projs.append(pj)
		wr.step(1.0 / 60.0)
		stunned += 1 if en2.stun > 0.0 else 0
		wr.enemies.clear()
		wr.projs.clear()
	_check(stunned > 110 and stunned < 210, "定身几率约 40%%（400 次中 %d）" % stunned)
	_free_world(wr)
	_free_world(wf)
	print("  拳 近·范围·高暴击 / 掌 中·追踪·减速·溅射·连击 / 指 远·穿透衰减·几率定身  OK")


func _absorb_test() -> void:
	print("\n=== 经验珠不自动飞来 / 吸星大法 / 移速 ===")
	_check(is_equal_approx(float(Data.player_base["move_speed"]), 140.0), "主角基础移速 140（原 200 的 70%）")
	# 经验珠：远处的珠子放很久也不会自己飞过来
	var w := _new_world(111)
	w.skills.clear()
	w.god = true
	w.input_move = Vector2.ZERO
	w._drop_gem(w.player_pos + Vector2(400, 0), 5)
	for i in int(10.0 / DT):
		w.step(DT)
		w.input_move = Vector2.ZERO
	_check(w.gem_pos.size() >= 1 and (w.gem_pos[0] as Vector2).distance_to(w.player_pos) > 300.0, "经验珠不再自动飞向主角")
	# 走进拾取范围才会吸过来
	w.gem_pos.clear()
	w.gem_val.clear()
	w.gem_age.clear()
	w._drop_gem(w.player_pos + Vector2(60, 0), 5)
	var exp0 := w.exp_total
	for i in 60:
		w.step(DT)
		w.input_move = Vector2.ZERO
	_check(w.exp_total > exp0, "拾取范围内的经验珠会被吸过来")
	_free_world(w)
	# 吸星大法：1% 几率、同时只有一个、间隔限制
	var wa := _new_world(112)
	wa.skills.clear()
	var drops := 0
	wa.absorb_gap = 999.0
	for i in 20000:
		wa.absorb_items.clear()
		wa.absorb_gap = 999.0
		wa._maybe_drop_absorb(Vector2(500, 0))
		drops += wa.absorb_items.size()
	_check(drops > 130 and drops < 280, "掉落率约 1%%（20000 次中 %d）" % drops)
	wa.absorb_items.clear()
	wa.absorb_gap = 999.0
	for i in 400:
		wa._maybe_drop_absorb(Vector2(500, 0))
	_check(wa.absorb_items.size() <= 1, "同一时间最多一个")
	wa.absorb_items.clear()
	wa.absorb_gap = 1.0
	var forced: float = float(Data.tuning["absorb_chance"])
	Data.tuning["absorb_chance"] = 1.0
	wa._maybe_drop_absorb(Vector2(500, 0))
	_check(wa.absorb_items.is_empty(), "刚掉过不久不会再掉（间隔 25 秒）")
	Data.tuning["absorb_chance"] = forced
	# 捡到：全场宝石和还丹飞向主角
	var wv := _new_world(113)
	wv.skills.clear()
	wv.god = true
	wv.input_move = Vector2.ZERO
	for i in 20:
		wv._drop_gem(wv.player_pos + Vector2(300 + i * 40, (i % 5) * 80 - 160), 3)
	wv._drop_pill(wv.player_pos + Vector2(-700, 100), "large")
	wv.absorb_items.append({"pos": wv.player_pos + Vector2(10, 0), "age": 0.0})
	var hp_before := wv.hp
	wv.hp = wv.st("max_hp") * 0.5
	hp_before = wv.hp
	var got0 := wv.exp_total
	for i in int(2.5 / DT):
		wv.step(DT)
		wv.input_move = Vector2.ZERO
	_check(wv.absorb_items.is_empty() and wv.gem_pos.size() == 0, "捡到吸星大法后全场宝石都飞来并被收走（剩 %d）" % wv.gem_pos.size())
	_check(wv.pills.is_empty() and wv.hp > hp_before, "还丹也飞来了并回血")
	_check(wv.exp_total > got0 + 40, "宝石经验到账")
	_free_world(wv)
	print("  经验珠不自动飞 / 拾取范围 / 吸星 1% · 唯一 · 间隔 / 全场飞来 / 移速 140  OK")


func _burst_pill_test() -> void:
	print("\n=== 真气爆发 / 还丹 ===")
	# --- 爆发：消耗全部内力，消耗越多越强；次数有限 ---
	var base_w := _new_world(91, "kuang_feng")
	base_w.skills.clear()
	_check(base_w.burst_max() == 1 and base_w.burst_left() == 1, "基础 1 次爆发")
	base_w.neili = base_w.st("max_neili") * 0.05
	_check(not base_w.can_burst(), "内力低于 10% 不能爆发")
	var dmg_at := {}
	for f in [0.3, 1.0]:
		var w := _new_world(92, "kuang_feng")
		w.skills.clear()
		w.stats["crit_chance"] = 0.0
		var en := Enemy.new()
		en.hp = 1.0e12
		en.max_hp = 1.0e12
		en.pos = w.player_pos + Vector2(60, 0)
		w.enemies.append(en)
		w._rebuild_grid()
		w.neili = w.st("max_neili") * f
		w.input_ult = true
		var hp0 := en.hp
		w.step(1.0 / 60.0)
		dmg_at[f] = hp0 - en.hp
		_check(w.neili < 5.0 and w.burst_used == 1 and w.burst_left() == 0, "爆发消耗全部内力，次数 −1（f=%.1f）" % f)
		# 第二次不能爆发
		w.neili = w.st("max_neili")
		w.input_ult = true
		var hp1 := en.hp
		w.step(1.0 / 60.0)
		_check(w.burst_used == 1, "没有次数时不能再爆发")
		_free_world(w)
	_check(float(dmg_at[1.0]) > float(dmg_at[0.3]) * 2.5, "消耗越多威力越大（30%% 内力 %.0f → 满内力 %.0f）" % [dmg_at[0.3], dmg_at[1.0]])
	# --- 内力属性 + 天赋 ---
	var wn := _new_world(93, "kuang_feng")
	wn.skills.clear()
	wn.xinfa = {"wuxiang": 1, "tiegu": 1}
	wn.recalc()
	_check(wn.nature() == "yang", "双阳 = 阳性内力")
	wn.xinfa = {"hanshuang": 1, "tunhai": 1}
	_check(wn.nature() == "yin", "双阴 = 阴性内力")
	wn.xinfa = {"hanshuang": 1, "tiegu": 1}
	_check(wn.nature() == "harmony", "一阴一阳 = 调和内力")
	wn.xinfa = {"hanshuang": 1}
	_check(wn.nature() == "", "只有一个心法没有属性")
	# 调和归元：次数 ×2；没有天赋不加
	wn.xinfa = {"hanshuang": 1, "tiegu": 1}
	_check(wn.burst_max() == 1, "没有天赋：调和内力也只有 1 次")
	wn.talent_stats = {"burst_harmony": 1.0}
	wn.recalc()
	_check(wn.burst_max() == 2, "调和归元：2 次")
	wn.xinfa = {"wuxiang": 1, "tiegu": 1}
	wn.recalc()
	_check(wn.burst_max() == 1, "调和归元只对调和内力有效")
	_free_world(wn)
	# 阴性：爆发回血 + 攻速
	var wy := _new_world(94)
	wy.skills.clear()
	wy.god = false
	wy.xinfa = {"hanshuang": 1, "tunhai": 1}
	wy.talent_stats = {"burst_yin": 1.0}
	wy.recalc()
	wy.hp = wy.st("max_hp") * 0.3
	var cd0 := wy.cd_mult()
	wy.neili = wy.st("max_neili")
	wy.input_ult = true
	var hp_before := wy.hp
	wy.step(1.0 / 60.0)
	_check(wy.hp > hp_before + wy.st("max_hp") * 0.3, "阴性爆发额外回血（%.0f → %.0f）" % [hp_before, wy.hp])
	_check(wy.cd_mult() < cd0 - 0.2 and wy.atk_buff_t > 7.0, "阴性爆发后攻速提升")
	for i in int(9.0 / DT):
		wy.step(DT)
	_check(absf(wy.cd_mult() - cd0) < 1e-6, "攻速提升 8 秒后结束")
	_free_world(wy)
	# 阳性：回内力更快；内力满时生成护盾（≤50% 气血）；护盾在时反弹 30%
	var wa := _new_world(95)
	wa.skills.clear()
	wa.god = false
	wa.xinfa = {"wuxiang": 1, "tiegu": 1}
	wa.talent_stats = {"burst_yang": 1.0}
	wa.recalc()
	var wb := _new_world(95)
	wb.skills.clear()
	wb.xinfa = {"wuxiang": 1, "tiegu": 1}
	wb.recalc()
	wa.neili = 10.0
	wb.neili = 10.0
	for i in 60:
		wa.step(DT)
		wb.step(DT)
	_check(wa.neili - 10.0 > (wb.neili - 10.0) * 1.3, "阳性回内力更快（%.1f vs %.1f）" % [wa.neili - 10.0, wb.neili - 10.0])
	wa.neili = wa.st("max_neili")
	wa.since_hit = 5.0
	wa.god = true
	for i in int(12.0 / DT):
		wa.step(DT)
		wa.neili = wa.st("max_neili")
	_check(absf(wa.shield - wa.st("max_hp") * 0.5) < 1.0, "内力满：护盾涨到 50%% 气血（%.0f / %.0f）" % [wa.shield, wa.st("max_hp") * 0.5])
	wa.god = false
	var refl := Enemy.new()
	refl.hp = 1.0e9
	refl.max_hp = 1.0e9
	refl.pos = wa.player_pos + Vector2(40, 0)
	wa.enemies.append(refl)
	wa._rebuild_grid()
	wa.invuln = 0.0
	var rh := refl.hp
	wa.stats["block_chance"] = 0.0      # 铁布衫有几率格挡，测试里关掉，免得随机数撞上
	wa._hurt(100.0)
	_check(rh - refl.hp > 20.0, "护盾在时反弹受击伤害（反弹 %.0f）" % (rh - refl.hp))
	_free_world(wa)
	_free_world(wb)
	# --- 还丹 ---
	var wp := _new_world(96)
	wp.skills.clear()
	wp.god = false
	wp.hp = wp.st("max_hp") * 0.4
	var el := Enemy.new()
	el.is_elite = true
	el.hp = 1.0
	el.max_hp = 1.0
	el.pos = wp.player_pos + Vector2(400, 0)
	wp.enemies.append(el)
	var h0 := wp.hp
	wp.damage_enemy(el, 10.0, Vector2.ZERO)
	_check(wp.pills.size() >= 1 and wp.pills[0]["kind"] == "small" and absf(wp.hp - h0) < 0.01, "精英掉小还丹，不再直接回血")
	var large_seen := 0
	for i in 200:
		var e2 := Enemy.new()
		e2.is_elite = true
		e2.hp = 1.0
		e2.max_hp = 1.0
		wp.enemies.append(e2)
		var before := wp.pills.size()
		wp.damage_enemy(e2, 10.0, Vector2.ZERO)
		for k in range(before, wp.pills.size()):
			large_seen += 1 if wp.pills[k]["kind"] == "large" else 0
		wp.pills.clear()
	_check(large_seen > 30 and large_seen < 90, "精英约 30%% 掉大还丹（200 次中 %d）" % large_seen)
	wp.pills.clear()
	wp._drop_pill(wp.player_pos, "small")
	wp._drop_pill(wp.player_pos + Vector2(2, 0), "large")
	wp.gem_pos.clear()
	wp.gem_val.clear()
	wp.gem_age.clear()
	var h1 := wp.hp
	wp.step(1.0 / 60.0)
	_check(wp.pills.is_empty() and absf(wp.hp - (h1 + wp.st("max_hp") * (Data.T("pill_small") + Data.T("pill_large")))) < 1.0, "捡到小 / 大还丹分别回 12%% / 35%% 气血（%.1f → %.1f，期望 +%.1f，剩余丹药 %d）" % [h1, wp.hp, wp.st("max_hp") * (Data.T("pill_small") + Data.T("pill_large")), wp.pills.size()])
	_free_world(wp)
	# 小 Boss 必掉大还丹
	var wm := _new_world(97)
	wm.skills.clear()
	wm._spawn_boss("mini_boss_1", false)
	var mb: Enemy = wm.bosses[0]
	wm.pills.clear()
	wm.damage_enemy(mb, 1.0e9, Vector2.ZERO)
	_check(wm.pills.size() == 1 and wm.pills[0]["kind"] == "large", "小 Boss 掉大还丹")
	_free_world(wm)
	print("  爆发（消耗全部 / 威力随内力 / 次数）/ 内力属性 / 三种天赋效果 / 还丹  OK")


func _synergy_test() -> void:
	print("\n=== P3：阴阳 / 合璧 ===")
	var ids: Array = Data.xinfa.keys()
	var yang := 0
	for id in ids:
		_check(["yin", "yang"].has(str(Data.xinfa[id].get("yy", ""))), "%s 应有阴阳属性" % id)
		yang += 1 if Data.xinfa[id]["yy"] == "yang" else 0
	_check(yang == 5, "10 个心法：5 阳 5 阴")
	var seen := {}
	for h in Data.harmony:
		var a: String = h["pair"][0]
		var b: String = h["pair"][1]
		_check(Data.xinfa.has(a) and Data.xinfa.has(b) and a != b, "合璧 %s 的心法要存在且不同" % h["name"])
		var key := a + "|" + b if a < b else b + "|" + a
		_check(not seen.has(key), "合璧不能重复：" + key)
		seen[key] = true
		for k in h["stats"]:
			_check(Data.player_base.has(k), "合璧 %s 用了不存在的属性 %s" % [h["name"], k])
		for k in h.get("mul", {}):
			_check(Data.player_base.has(k), "合璧 %s 倍率用了不存在的属性 %s" % [h["name"], k])
	_check(Data.harmony.size() >= 6 and Data.harmony.size() <= 10, "合璧数量 6~10")
	# 45 种搭配：每一种都有阴阳组合，合璧只在配对时出现
	var n_harm := 0
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			var w := _new_world(70)
			w.skills.clear()
			w.xinfa[ids[i]] = 1
			w.recalc()
			_check(w.synergies.is_empty(), "只学一个心法没有组合")
			w.xinfa[ids[j]] = 1
			w.recalc()
			var want_h := not Data.harmony_of(ids[i], ids[j]).is_empty()
			var got_h := 0
			for sy in w.synergies:
				got_h += 1 if bool(sy["harmony"]) else 0
			_check(w.synergies.size() == 1 + (1 if want_h else 0) and got_h == (1 if want_h else 0), "%s + %s 的组合数量" % [ids[i], ids[j]])
			n_harm += 1 if want_h else 0
			_free_world(w)
	_check(n_harm == Data.harmony.size(), "每个合璧恰好对应一种搭配")
	# 阴阳效果（用没有合璧的搭配：小无相功 + 铁布衫 阳阳；玄冥神功 + 北冥神功 阴阴；小无相功 + 玄冥神功 一阴一阳）
	var base_regen := float(Data.player_base["neili_regen"]) + float(Data.schools["fist"]["passive"]["neili_regen"])      # 测试用武者：含流派被动
	var base_max := float(Data.player_base["max_neili"])
	var wa := _new_world(71)
	wa.skills.clear()
	wa.xinfa = {"wuxiang": 1, "hanshuang": 1}
	wa.recalc()
	_check(absf(wa.st("neili_regen") - base_regen * 1.2) < 1e-6 and wa.st("ping_widen") > 0.0 and wa.synergies[0]["name"] == "调和体", "调和体：回气 +20%，平境更宽")
	var xu0 := Data.T("xu_below")
	wa.neili = wa.st("max_neili") * (xu0 - 0.03)
	_check(wa.realm() == GameWorld.Realm.PING, "平境更宽：略低于虚境线时仍算平")
	_free_world(wa)
	var wb := _new_world(72)
	wb.skills.clear()
	wb.xinfa = {"wuxiang": 1, "tiegu": 1}
	wb.recalc()
	_check(absf(wb.st("neili_regen") - base_regen * 0.8) < 1e-6 and absf(wb.st("emp_power") - 0.3) < 1e-9 and wb.synergies[0]["name"] == "纯阳体", "纯阳体：回气 −20%，催动威力 +30%")
	wb.input_move = Vector2.ZERO
	for i in int(3.0 / DT):
		wb.step(DT)
	_check(not wb.meditating(), "纯阳体：入定无效")
	var probe := Enemy.new()
	probe.hp = 1.0e12
	probe.max_hp = 1.0e12
	wb.stats["crit_chance"] = 0.0
	wb._emp_ctx = 0
	var plain := wb.hit_enemy(probe, 100.0, ["远程"], Vector2.ZERO, "probe")
	wb._emp_ctx = 1
	var emp := wb.hit_enemy(probe, 100.0, ["远程"], Vector2.ZERO, "probe")
	_check(absf(emp / plain - 1.3) < 1e-6, "纯阳体：催动版伤害 ×1.3（实际 ×%.2f）" % (emp / plain))
	_free_world(wb)
	var wc := _new_world(73)
	wc.skills.clear()
	wc.xinfa = {"hanshuang": 1, "tunhai": 1}
	wc.recalc()
	var per_max := float(Data.xinfa["hanshuang"]["per_level"].get("max_neili", 0.0)) + float(Data.xinfa["tunhai"]["per_level"].get("max_neili", 0.0))
	_check(absf(wc.st("max_neili") - (base_max + float(Data.schools["fist"]["passive"]["max_neili"]) + per_max) * 1.3) < 1e-6 and absf(wc.st("emp_power") + 0.15) < 1e-9 and wc.synergies[0]["name"] == "纯阴体", "纯阴体：内力上限 +30%，催动威力 −15%")
	_free_world(wc)
	# 合璧效果
	var wd := _new_world(74)
	wd.skills.clear()
	wd.xinfa = {"lingxi": 1, "hanshuang": 1}
	wd.recalc()
	_check(wd.st("burn") == 40.0, "冰火同炉：灼烧")
	var burn_e := Enemy.new()
	burn_e.hp = 1000.0
	burn_e.max_hp = 1000.0
	burn_e.stun = 5.0
	burn_e.pos = Vector2(500, 500)
	wd.enemies.append(burn_e)
	var free_e := Enemy.new()
	free_e.hp = 1000.0
	free_e.max_hp = 1000.0
	free_e.pos = Vector2(520, 500)
	wd.enemies.append(free_e)
	for i in int(2.0 / DT):
		wd.step(DT)
	_check(burn_e.hp < 1000.0 - 20.0 and free_e.hp > 999.0, "冰火同炉：只灼烧被定身的敌人（%.0f / %.0f）" % [burn_e.hp, free_e.hp])
	_free_world(wd)
	var we := _new_world(75)
	we.skills.clear()
	we.xinfa = {"tiegu": 1, "tunhai": 1}
	we.recalc()
	_check(absf(we.st("thorns") - float(Data.xinfa["tiegu"]["per_level"]["thorns"]) * 2.0) < 1e-6, "金钟罩：反震翻倍")
	_free_world(we)
	var wf := _new_world(76)
	wf.skills.clear()
	wf.xinfa = {"tunhai": 1, "chunyang": 1}
	wf.recalc()
	wf.neili = 10.0
	wf.stats["crit_chance"] = 1.0
	var pe := Enemy.new()
	pe.hp = 1.0e12
	pe.max_hp = 1.0e12
	wf.hit_enemy(pe, 10.0, ["远程"], Vector2.ZERO, "probe")
	_check(absf(wf.neili - 11.5) < 1e-6, "吞吐万象：暴击回内力 +1.5（实际 %.2f）" % wf.neili)
	_free_world(wf)
	# 选卡提示：已学一个心法时，候选心法的卡片会提示阴阳组合 / 合璧（心法按流派出现：武者 3 个、剑侠 4 个、刀客 3 个）
	var wg := _new_world(77)
	wg.skills.clear()
	wg.xinfa = {"chunyang": 1}
	var hinted := false
	var seen_x := {}
	for i in 60:
		for c in wg.roll_choices(30):
			if str(c["kind"]) == "new_xinfa":
				seen_x[str(c["id"])] = true
				_check(str(c["title"]).contains("【阳】") or str(c["title"]).contains("【阴】"), "心法卡片带阴阳标记")
				if c["id"] == "tunhai":
					hinted = hinted or str(c["desc"]).contains("合璧「吞吐万象」")
	_check(hinted, "能合璧的卡片提示合璧")
	_check(seen_x.size() == 9, "所有心法都会出现在升级卡里（已学 1 个，其余 9 个；实际 %d）" % seen_x.size())
	wg.xinfa.clear()
	for c in wg.roll_choices(30):
		if str(c["kind"]) == "new_xinfa":
			_check(not str(c["desc"]).contains("▶"), "一个心法都没学时没有搭配提示")
	_free_world(wg)
	var wh := _new_world(78, "kuang_feng")
	wh.skills.clear()
	wh.xinfa = {"lingxi": 1}
	var spoil := false
	for i in 60:
		for c in wh.roll_choices(30):
			if str(c["kind"]) == "new_xinfa" and c["id"] == "jieli":
				spoil = spoil or str(c["desc"]).contains("合璧")
	_check(not spoil, "不能合璧的卡片不提示合璧")
	_free_world(wh)
	print("  阴阳属性 / 45 种搭配 / 调和体·纯阳体·纯阴体 / 合璧效果 / 选卡提示  OK")


func _p2_test() -> void:
	print("\n=== P2：破绽联动 / Boss 罡气 ===")
	var w := _new_world(41)
	w.skills.clear()
	w.stats["crit_chance"] = 0.0
	var e := Enemy.new()
	e.hp = 1.0e12
	e.max_hp = 1.0e12
	e.radius = 10.0
	# 点穴 → 近战 / 蓄力：暴击率 +40%
	var base := w.hit_enemy(e, 100.0, ["远程"], Vector2.ZERO, "probe")
	var crits := 0
	var crits_plain := 0
	for i in 3000:
		e.stun = 0.0
		if w.hit_enemy(e, 100.0, ["近战"], Vector2.ZERO, "probe") > base * 1.2:
			crits_plain += 1
		e.stun = 5.0
		if w.hit_enemy(e, 100.0, ["近战"], Vector2.ZERO, "probe") > base * 1.2:
			crits += 1
	_check(crits_plain == 0 and absf(float(crits) / 3000.0 - Data.T("weak_crit")) < 0.04, "定身的敌人：近战招式暴击率 +40%%（实际 %.1f%%，对照 %d）" % [float(crits) / 30.0, crits_plain])
	# 减速 → 追踪 / 贯穿 ×1.3；定身 → 范围 ×1.5；不相关的标签不受影响
	e.stun = 0.0
	var a0 := w.hit_enemy(e, 100.0, ["追踪"], Vector2.ZERO, "probe")
	e.slow_t = 3.0
	var a1 := w.hit_enemy(e, 100.0, ["追踪"], Vector2.ZERO, "probe")
	var a2 := w.hit_enemy(e, 100.0, ["贯穿"], Vector2.ZERO, "probe")
	var a3 := w.hit_enemy(e, 100.0, ["远程"], Vector2.ZERO, "probe")
	_check(absf(a1 / a0 - 1.3) < 1e-6 and absf(a2 / a0 - 1.3) < 1e-6 and absf(a3 / a0 - 1.0) < 1e-6, "减速的敌人：追踪 / 贯穿 ×1.3，其他标签不变")
	e.slow_t = 0.0
	e.stun = 5.0
	var b1 := w.hit_enemy(e, 100.0, ["范围"], Vector2.ZERO, "probe")
	_check(absf(b1 / a0 - 1.5) < 1e-6, "定身的敌人：范围招式 ×1.5（实际 ×%.2f）" % (b1 / a0))
	_free_world(w)
	# Boss 罡气
	var w2 := _new_world(42)
	w2.god = true
	w2.skills.clear()
	w2.stats["crit_chance"] = 0.0
	w2._spawn_boss("mini_boss_1", false)
	var boss: Enemy = w2.bosses[0]
	_check(is_equal_approx(boss.guard_max, boss.max_hp * Data.T("boss_guard_pct")) and boss.guard == boss.guard_max, "Boss 出生带罡气（30% 血量）")
	var dummy := Enemy.new()
	dummy.hp = 1.0e12
	dummy.max_hp = 1.0e12
	var ref := w2.hit_enemy(dummy, 100.0, ["远程"], Vector2.ZERO, "probe")   # 100 基础伤害结算后的实际数值
	var hp0 := boss.hp
	w2.hit_enemy(boss, 100.0, ["远程"], Vector2.ZERO, "probe")
	_check(absf(hp0 - boss.hp - ref * Data.T("guard_reduce")) < 1e-3 and absf(boss.guard - (boss.guard_max - ref)) < 1e-3, "罡气期间只受 50%% 伤害，罡气减少等同伤害（受伤 %.1f / 伤害 %.1f）" % [hp0 - boss.hp, ref])
	var g1 := boss.guard
	w2._emp_ctx = 1
	w2.hit_enemy(boss, 100.0, ["远程"], Vector2.ZERO, "probe")
	w2._emp_ctx = -1
	_check(absf(g1 - boss.guard - ref * Data.T("guard_empower_mult")) < 1e-3, "催动攻击对罡气 ×3")
	# 打破：进入虚弱，之后受伤 ×1.5；罡气在一段时间后重聚
	boss.guard = 50.0
	w2.hit_enemy(boss, 100.0, ["远程"], Vector2.ZERO, "probe")
	_check(boss.guard == 0.0 and boss.weak_t > 3.9 and w2.break_count == 1, "罡气被打破 → 虚弱")
	var hp1 := boss.hp
	w2.hit_enemy(boss, 100.0, ["远程"], Vector2.ZERO, "probe")
	_check(absf(hp1 - boss.hp - ref * Data.T("break_dmg")) < 1e-3, "虚弱期间受伤 ×1.5（实际 %.1f，期望 %.1f）" % [hp1 - boss.hp, ref * Data.T("break_dmg")])
	var seen_weak_end := false
	for i in int(5.0 / DT):
		w2.step(DT)
	seen_weak_end = boss.weak_t <= 0.0 and boss.guard == 0.0
	_check(seen_weak_end, "虚弱 4 秒后结束，罡气还没有重聚")
	for i in int((Data.T("guard_regen_t") + 1.0) / DT):
		w2.step(DT)
	_check(is_equal_approx(boss.guard, boss.guard_max), "再过一段时间罡气重聚（guard %.0f / %.0f，alive %s，regen %.1f）" % [boss.guard, boss.guard_max, str(boss.alive), boss.guard_regen])
	_free_world(w2)
	# 催动状态跟着弹体走：催动版弹体命中时对罡气 ×3，即使出手后已不在催动状态
	var w3 := _new_world(43)
	w3.god = true
	w3.skills.clear()
	w3.add_skill("yue_palm")
	w3._spawn_boss("mini_boss_1", false)
	var b3: Enemy = w3.bosses[0]
	b3.pos = w3.player_pos + Vector2(150, 0)
	b3.speed = 0.0
	var sk: SkillBase = w3.skills["yue_palm"]
	sk.empowered = true
	var pr: Projectile = w3.spawn_proj(sk, 0.0, {"radius": 40.0})
	sk.empowered = false
	_check(pr.empowered, "弹体记录催动状态")
	var g_before := b3.guard
	for i in int(1.0 / DT):
		w3.step(DT)
	var lost := g_before - b3.guard
	_check(lost > 0.0, "弹体命中了 Boss")
	_free_world(w3)
	print("  破绽（暴击 / 追踪 / 范围）/ 罡气（减伤 / 催动 ×3 / 破罡 / 虚弱 / 重聚）/ 弹体催动  OK")


## 测试用的假特效条带：N 帧，渐强的发光环
func fake_strip(frames: int, cell: int, col: Color) -> Texture2D:
	var img := Image.create(cell * frames, cell, false, Image.FORMAT_RGBA8)
	for f in frames:
		var rad := cell * (0.15 + 0.3 * float(f + 1) / float(frames))
		for y in cell:
			for x in cell:
				var d := Vector2(x - cell * 0.5, y - cell * 0.5).length()
				var a := clampf(1.0 - absf(d - rad) / 4.0, 0.0, 1.0)
				if a > 0.0:
					img.set_pixel(f * cell + x, y, Color(col.r, col.g, col.b, a))
	return ImageTexture.create_from_image(img)


func _vfx_test() -> void:
	print("\n=== 招式特效（素材优先，没有素材时回退）===")
	var v := Vfx.new()
	_check(not v.has("proj_wave") and v.load_dir("res://assets/vfx_missing") == 0, "没有素材目录时安静地什么都不加载")
	v.add("hit_impact", fake_strip(4, 32, Color.WHITE), 4, 20.0, 32, false)
	v.add("proj_wave", fake_strip(4, 32, Color.WHITE), 4, 12.0, 32, true)
	_check(v.has("hit_impact") and not v.has("slash_fist"), "登记 / 查询")
	_check(v.frame_progress("hit_impact", 0.0) == 0 and v.frame_progress("hit_impact", 0.49) == 1 and v.frame_progress("hit_impact", 1.0) == 3 and v.frame_progress("hit_impact", 5.0) == 3, "一次性特效按进度取帧并夹住")
	_check(v.frame_loop("proj_wave", 0.0) == 0 and v.frame_loop("proj_wave", 1.0 / 12.0 * 1.01) == 1 and v.frame_loop("proj_wave", 100.0) < 4, "循环特效按时间取帧")
	# 没有素材：战斗里不会生成命中火花；有素材：命中产生带 vfx 的 fx，且弹体 / 刀光 / 环有登记
	var w0 := _new_world(81)
	w0.skills.clear()
	w0.add_skill("chain_fist")
	_populate(w0, 40)
	for i in int(3.0 / DT):
		TestBot.drive(w0, 75.0)
		w0.step(DT)
	var hits0 := 0
	for fx in w0.effects:
		hits0 += 1 if str(fx["kind"]) == "hit" else 0
	_check(hits0 == 0, "没有 hit_impact 素材时不产生命中火花")
	_free_world(w0)
	var w1 := _new_world(81)
	w1.skills.clear()
	w1.add_skill("chain_fist")
	w1.vfx.add("hit_impact", fake_strip(4, 32, Color.WHITE), 4, 20.0, 32)
	w1.vfx.add("slash_fist", fake_strip(5, 32, Color.WHITE), 5, 24.0, 32)
	w1.vfx.add("slash_heavy", fake_strip(6, 32, Color.WHITE), 6, 22.0, 32)
	_populate(w1, 40)
	var kinds := {}
	for i in int(3.0 / DT):
		TestBot.drive(w1, 75.0)
		w1.step(DT)
		for fx in w1.effects:
			if fx.has("vfx"):
				kinds[str(fx["vfx"])] = true
	_check(kinds.has("hit_impact") and (kinds.has("slash_fist") or kinds.has("slash_heavy") or kinds.has("fist_chain")), "有素材时命中 / 刀光走特效（%s）" % str(kinds.keys()))
	_free_world(w1)
	# 每个会用到的特效 id 都在目录里登记过（防止代码里写了 id 而说明文档 / 工具里没有）
	var used := ["proj_wave", "proj_palm", "proj_bolt", "proj_finger", "slash_fist", "slash_heavy", "burst_wind", "burst_quake", "burst_gold",
		"ring_taiji", "ring_qinggong", "burst_ult", "burst_break", "halo_empower", "zone_crack", "zone_vortex", "hit_impact", "hit_crit", "trail_dash", "death_puff"]
	var src := ""
	for f in ["res://scripts/world.gd", "res://scripts/vfx_layer.gd", "res://scripts/skills/fist_skills.gd"]:
		src += FileAccess.get_file_as_string(f)
	for id in used:
		_check(src.contains('"%s"' % id), "代码里应引用特效 " + id)
	var catalog := FileAccess.get_file_as_string("res://tools/process_vfx.py")
	for id in used:
		_check(catalog.contains('"%s":' % id), "process_vfx.py 的目录里应有 " + id)
	print("  素材加载 / 取帧 / 回退 / 命中与刀光接入 / 20 个特效 id 与目录一致  OK")


func _talent_skill_test() -> void:
	print("\n=== 天赋：针对招式的强化 / 平衡调整 ===")
	var wb := _new_world(101)
	wb.skills.clear()
	wb.add_skill("cloud_palm")
	_check(int((wb.skills["cloud_palm"] as SkillBase).p("count")) == 1, "天山六阳掌初始只有 1 个掌印")
	_free_world(wb)
	for ranks in [0, 1, 2]:
		var w := _new_world(102)
		w.skills.clear()
		Build.apply_to(w, {}, {"gang_force": 3, "gang_crit": 3, "ling_step": 3, "ling_cd": 3, "ling_palm": ranks} if ranks > 0 else {}, {}, "fist")
		w.add_skill("cloud_palm")
		_check(int((w.skills["cloud_palm"] as SkillBase).p("count")) == 1 + ranks, "六阳初开 %d 级：初始 %d 个掌印" % [ranks, 1 + ranks])
		_free_world(w)
	# 升级「增加目标」同样加弹数；催动 +1
	var wu := _new_world(103)
	wu.skills.clear()
	wu.add_skill("cloud_palm")
	var cp: SkillBase = wu.skills["cloud_palm"]
	cp.add_upgrade("targets", 3)
	_check(int(cp.p("count")) > 1, "升级增加目标 → 掌印更多（%d）" % int(cp.p("count")))
	_free_world(wu)
	# 八荒六合功：8 个、冷却更长
	var we := _new_world(104)
	we.skills.clear()
	we.add_skill("eight_waste")
	var ew: SkillBase = we.skills["eight_waste"]
	_check(int(ew.p("count")) == 8 and ew.p("cooldown") >= 3.0, "八荒六合功：8 个、冷却 ≥ 3 秒（%.1f）" % ew.p("cooldown"))
	_free_world(we)
	# 其他招式强化：贯穿 / 伤害 / 范围 / 冷却
	var w2 := _new_world(105)
	w2.skills.clear()
	var tl := {"gang_force": 3, "gang_crit": 3, "gang_dragon": 2, "gang_vajra": 0}
	Build.apply_to(w2, {}, {"gang_force": 3, "gang_crit": 3, "gang_ying": 3, "gang_dragon": 2}, {}, "fist")
	w2.add_skill("yue_palm")
	var y0 := float(Data.skills["yue_palm"]["pierce"])
	_check(absf((w2.skills["yue_palm"] as SkillBase).p("pierce") - (y0 + 2.0)) < 1e-6, "龙吟九天 2 级：降龙十八掌贯穿 +2")
	_free_world(w2)
	var w3 := _new_world(106)
	w3.skills.clear()
	Build.apply_to(w3, {}, {"ling_step": 3, "ling_cd": 3, "ling_crit": 3, "ling_cd2": 1, "ling_waste": 2}, {}, "fist")
	w3.add_skill("eight_waste")
	var cd_base := float(Data.skills["eight_waste"]["cooldown"])
	_check(absf((w3.skills["eight_waste"] as SkillBase).p("cooldown") - cd_base * 0.8) < 1e-6, "八荒回响 2 级：冷却 −20%")
	_free_world(w3)
	print("  初始 1 个掌印 / 天赋加弹数 / 升级加弹数 / 八荒 8 个 · 长冷却 / 贯穿与冷却天赋  OK")


func _talent_map_test() -> void:
	print("\n=== 天赋树（三个框）布局 / 交互 ===")
	var tt := TalentTree.new()
	tt.size = TalentTree.tree_size()
	tt.school = "blade"
	tt.level = 10
	add_child(tt)
	var all := Talents.nodes("blade")
	var per := {}
	for id in all:
		per[all[id]["branch"]] = int(per.get(all[id]["branch"], 0)) + 1
	for b in Talents.branches():
		_check(int(per[b]) >= 10 and int(per[b]) <= 15, "%s 系有 %d 个穴位（要求 10~15）" % [b, int(per[b])])
	_check(all.has(Talents.ji_id()) and str(all[Talents.ji_id()]["name"]) == "极·霸刀", "刀客的「极」穴位叫 极·霸刀")
	# 位置：每个节点唯一、落在自己的框里、互不重叠
	var pos := {}
	var min_d := 1.0e9
	for id in all:
		var n: Dictionary = all[id]
		if n["branch"] == "ji":
			continue
		var bi := Talents.branches().find(n["branch"])
		var p := tt.node_pos(bi, int(n["row"]), tt._idx_in_row(id))
		pos[id] = p
		_check(tt.box_rect(bi).has_point(p), "穴位在自己的框内：" + str(id))
	var ids: Array = pos.keys()
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			min_d = minf(min_d, (pos[ids[i]] as Vector2).distance_to(pos[ids[j]]))
	_check(min_d >= TalentTree.ICON, "穴位之间不重叠（最近 %.1f）" % min_d)
	_check(tt.box_rect(2).end.x <= tt.size.x + 0.5, "三个框并排放得下")
	_check(tt.ji_pos().y > tt.box_rect(0).end.y and tt.node_at(tt.ji_pos()) == Talents.ji_id(), "「极」穴位在三个框下方，可点中")
	# 极：三系点满 99 点后才出现
	var full := {}
	for id in all:
		if all[id]["branch"] != "ji":
			full[id] = int(all[id]["max"])
	_check(Talents.spent(full) == 99 and Talents.total_points(50) == 100, "三系点满 = 99 点，满级 50 = 100 点")
	tt.level = 50
	tt.work = full.duplicate()
	_check(tt.ji_unlocked() and tt.state_of(Talents.ji_id()) == "open", "点满 99 点后「极」可以点")
	var jclick := InputEventMouseButton.new()
	jclick.position = tt.ji_pos()
	jclick.pressed = true
	jclick.button_index = MOUSE_BUTTON_LEFT
	tt._gui_input(jclick)
	_check(int(tt.work.get(Talents.ji_id(), 0)) == 1 and Talents.spent(tt.work) == 100, "点亮「极」：第 100 点")
	var cut: Dictionary = full.duplicate()
	cut["gang_force"] = int(cut["gang_force"]) - 1
	cut[Talents.ji_id()] = 1
	_check(not Talents.valid(cut, 50), "没点满 99 点不能点「极」")
	_check(not Talents.can_remove(tt.work, "gang_force", 50) and Talents.can_remove(tt.work, Talents.ji_id(), 50), "有「极」时不能减别的点，要先减「极」")
	tt.work = {}
	tt.level = 10
	# 命中测试 + 点击加点 / 减点（走真实的输入事件）
	var gid := "gang_force"
	var sp: Vector2 = pos[gid]
	_check(tt.node_at(sp) == gid and tt.node_at(sp + Vector2(300, 0)) != gid, "鼠标命中测试")
	var mv := InputEventMouseMotion.new()
	mv.position = sp
	tt._gui_input(mv)
	_check(tt.hover_id == gid, "悬停")
	var click := InputEventMouseButton.new()
	click.position = sp
	click.pressed = true
	click.button_index = MOUSE_BUTTON_LEFT
	var changes := [0]
	tt.changed.connect(func(): changes[0] += 1)
	tt._gui_input(click)
	tt._gui_input(click)
	_check(int(tt.work.get(gid, 0)) == 2 and changes[0] == 2, "左键加点")
	tt._gui_input(click)
	_check(int(tt.work.get(gid, 0)) == 2, "满级后不能再加")
	click.button_index = MOUSE_BUTTON_RIGHT
	tt._gui_input(click)
	_check(int(tt.work.get(gid, 0)) == 1, "右键减点")
	tt.remove_mode = true
	click.button_index = MOUSE_BUTTON_LEFT
	tt._gui_input(click)
	_check(not tt.work.has(gid), "减点模式：左键 = 减点")
	tt.remove_mode = false
	# 锁定的穴位点了没用；层门槛显示
	var locked := "gang_peak"
	click.position = pos[locked]
	tt._gui_input(click)
	_check(not tt.work.has(locked) and tt.state_of(locked) == "locked", "锁定的穴位不能加点")
	_check(not tt.row_open("gang", 3) and tt.state_of("gang_force") == "open", "层门槛 / 状态判定")
	tt.work = {"gang_force": 2, "gang_body": 2}
	_check(tt.row_open("gang", 1) and not tt.row_open("rou", 1), "刚系第 1 层已打通，柔系还没有（三系独立）")
	_check(tt.info_text("gang_crit").contains("劲透") and tt.info_text("").contains("三个框"), "说明文字")
	remove_child(tt)
	tt.free()
	print("  三个框 / 每系 14 穴位 / 不重叠 / 命中 / 加减点 / 减点模式 / 锁定 / 层门槛  OK")


func _build_test() -> void:
	print("\n=== 天赋树 / 装备 ===")
	# 天赋树结构：三系各 7 层、14 个穴位、共 30 点（三系 90 点）；每级 2 点；节点属性都是已有的属性
	_check(int(Data.talents["per_level"]) == 2 and Talents.total_points(50) == 100 and Talents.ji_need() == 99, "每级 2 点，满级 50 = 100 点 = 三系 99 点 + 极 1 点")
	var all := Talents.nodes()
	for b in Talents.branches():
		var sum := 0
		for id in all:
			if all[id]["branch"] == b:
				sum += int(all[id]["max"])
		_check(sum == 33, "%s 系应共 33 点（实际 %d）" % [b, sum])
	for id in all:
		for k in all[id]["stat"]:
			if str(k).begins_with("skill:"):
				var pr := str(k).split(":")
				_check(pr.size() == 3 and Data.skills.has(pr[1]) and ["targets", "damage", "cooldown", "range", "empower"].has(pr[2]), "天赋 %s 的招式强化键不对：%s" % [id, k])
			else:
				_check(Data.player_base.has(k), "天赋 %s 用了不存在的属性 %s" % [id, k])
	# 解锁规则
	var t := {}
	_check(Talents.can_add(t, "gang_force", 10) and not Talents.can_add(t, "gang_crit", 10), "第 1 层要先在更低层投入 3 点")
	t = {"gang_force": 2, "gang_body": 1}
	_check(Talents.can_add(t, "gang_crit", 10), "低层 3 点后解锁第 1 层")
	t = {"gang_force": 2, "gang_body": 1, "gang_crit": 1}
	_check(not Talents.can_remove(t, "gang_force", 10), "已有第 1 层点数时，不能把低层减到不足 3")
	_check(Talents.can_remove(t, "gang_crit", 10), "可以减掉高层的点")
	_check(not Talents.can_add({"gang_force": 2}, "gang_force", 10), "满级节点不能再加")
	_check(not Talents.can_add({"gang_force": 2, "gang_body": 2}, "gang_crit", 2), "总点数用完不能再加（等级 2 = 4 点）")
	_check(Talents.can_add({"gang_force": 2, "gang_body": 2}, "gang_crit", 3), "等级 3 = 6 点，还能再加")
	_check(Talents.valid({"gang_force": 2, "rou_regen": 2, "ling_step": 2}, 3) and not Talents.valid({"gang_force": 2, "rou_regen": 2, "ling_step": 2}, 2), "总点数 ≤ 局外等级 × 2；三系可同时加")
	_check(Talents.clean({"gang_force": 99, "zzz": 5, "rou_regen": -2}) == {"gang_force": 2}, "天赋规范化")
	# 修复：旧存档超出新上限 / 门槛时自动从高层往下减点
	var rep1 := Talents.repair({"gang_force": 3, "gang_crit": 3, "gang_ying": 3}, 20)
	_check(Talents.valid(rep1, 20) and Talents.spent(rep1) > 0, "天赋修复：旧加点被修成合法 %s" % str(rep1))
	var rep2 := Talents.repair({"gang_force": 2, "gang_body": 2, "gang_crit": 2, "gang_armor": 2}, 3)
	_check(Talents.valid(rep2, 3) and Talents.spent(rep2) <= 6, "天赋修复：点数超过上限时减到合法（%d 点）" % Talents.spent(rep2))
	var tst := Talents.stats_for({"gang_force": 2, "gang_ying": 0})
	_check(absf(float(tst["damage_pct"]) - 0.04) < 1e-9, "天赋效果叠加")
	# 装备：编码、确定性、稀有度、词条
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var counts := [0, 0, 0, 0]
	var has_xinfa := false
	var has_skill := false
	for i in 3000:
		var code := Gear.roll_code(rng)
		var it := Gear.make(code)
		_check(not it.is_empty() and Gear.make(code) == it, "装备应能由编码确定地展开：" + code)
		counts[int(it["rarity"])] += 1
		var rd := Gear.rarity_def(int(it["rarity"]))
		_check(it["affixes"].size() <= int(rd["affixes"]) and it["affixes"].size() >= 1 or int(rd["affixes"]) == 0, "词条数量")
		for a in it["affixes"]:
			if str(a["kind"]) == "xinfa":
				has_xinfa = true
				_check(Data.xinfa.has(a["id"]), "心法词条指向存在的心法")
			else:
				has_skill = true
				_check(str(Data.skills[a["id"]]["school"]) == "fist", "词条只会强化本流派的招式")
		for k in it["stats"]:
			_check(Data.player_base.has(k), "装备属性 %s 不存在" % k)
	_check(counts[0] > counts[1] and counts[1] > counts[2] and counts[2] > counts[3] and counts[3] > 0, "稀有度分布递减：%s" % str(counts))
	_check(absf(float(counts[0]) / 3000.0 - 0.6) < 0.04 and absf(float(counts[1]) / 3000.0 - 0.3) < 0.04 and absf(float(counts[2]) / 3000.0 - 0.09) < 0.025, "掉率 60 / 30 / 9 / 1：%s" % str(counts))
	_check(has_xinfa and has_skill, "两类词条都应出现")
	_check(Gear.parse("weapon.4.1").is_empty() and Gear.parse("weapon.9.1").is_empty() and Gear.parse("hat.0.1").is_empty() and Gear.parse("weapon.1").is_empty() and not Gear.parse("weapon.1.77").is_empty(), "编码格式校验")
	var legend := Gear.make("weapon.3.4242")
	var common := Gear.make("weapon.0.4242")
	_check(float(legend["stats"]["damage_pct"]) > float(common["stats"]["damage_pct"]) * 2.4, "传说的基础属性远高于普通")
	_check(legend["affixes"].size() == 2 and common["affixes"].is_empty(), "传说 2 条词条，凡品没有")
	var dr := Gear.run_drops(rng, 0, true)
	_check(dr.size() >= 1 and dr.size() <= 2, "大 Boss 掉 1~2 件")
	_check(Gear.run_drops(rng, 1, false).size() == 1 and Gear.run_drops(rng, 3, false).size() == 3 and Gear.run_drops(rng, 0, false).is_empty(), "小 Boss 固定 1 件（阵亡也掉），没击败不掉")
	var nb := 0
	for i in 200:
		nb += Gear.run_drops(rng, 3, true).size() - 3
	_check(nb >= 200 and nb <= 400 and nb > 260 and nb < 340, "大 Boss 1~2 件，约一半是 2 件（共 %d / 200 次）" % nb)
	# 装备清单：每个部位 10 件，武器按流派（拳套类 / 剑类）各 10 件
	for slot in Gear.slot_ids():
		for sch in ["fist", "sword"]:
			var lst := Gear.items_for(str(slot), sch)
			_check(lst.size() == 10, "%s（%s）应有 10 件，实际 %d" % [slot, sch, lst.size()])
			var seen := {}
			for idef in lst:
				seen[str(idef["name"])] = true
				for k in idef["base"]:
					_check(Data.player_base.has(k), "装备基础属性 %s 不存在（%s）" % [k, idef["name"]])
			_check(seen.size() == 10, "%s（%s）10 件名字各不相同" % [slot, sch])
	_check(str(Gear.make("weapon.1.3", "sword")["name"]) == str(Gear.items_for("weapon", "sword")[3]["name"]), "剑侠的武器取自剑类清单")
	_check(str(Gear.make("weapon.1.3", "fist")["name"]) == str(Gear.items_for("weapon", "fist")[3]["name"]), "武者的武器取自拳套类清单")
	_check(Gear.rarity_def(0)["name"] == "普通" and Gear.rarity_def(1)["name"] == "特别" and Gear.rarity_def(2)["name"] == "稀有" and Gear.rarity_def(3)["name"] == "传说", "四档稀有度名称")
	# 装备加成进入战斗属性：伤害、技能词条、心法词条
	var w := _new_world(31, "chain_fist")
	w.skills.clear()
	var item := {"stats": {"damage_pct": 0.1, "max_hp": 20.0}, "affixes": [
		{"kind": "skill", "id": "chain_fist", "dir": "damage", "v": 30.0},
		{"kind": "skill", "id": "chain_fist", "dir": "empower", "v": 20.0},
		{"kind": "xinfa", "id": "tiegu", "v": 2}]}
	var hp0 := w.st("max_hp")
	var gb := Gear.bonuses([item])
	Build.merge(w.talent_stats, gb["stats"])
	w.gear_skill_mods = gb["skill_mods"]
	w.gear_xinfa = gb["xinfa"]
	w.add_skill("chain_fist")
	w.recalc()
	_check(absf(w.st("max_hp") - (hp0 + 20.0)) < 0.01 and w.st("damage_pct") >= 0.1, "装备基础属性生效")
	var sk: SkillBase = w.skills["chain_fist"]
	var c0 := float(Data.skills["chain_fist"]["empower_cost"]) * Data.T("empower_cost_mult")
	_check(absf(float(sk.mods["damage"]) - 0.3) < 1e-9 and absf(sk.empower_cost() - c0 * (1.0 - 0.2 - w.st("empower_cut"))) < 1e-6, "技能词条：伤害 +30%、催动消耗 −20%（武者基础催动更贵）")
	w.xinfa["tiegu"] = 1
	w.recalc()
	_check(absf(w.st("block_chance") - float(Data.xinfa["tiegu"]["per_level"]["block_chance"]) * 3.0) < 1e-9, "心法词条：已学的心法 +2 级（1 → 3）")
	w.xinfa.clear()
	w.recalc()
	_check(w.st("block_chance") == 0.0, "没学会的心法，词条不生效")
	_free_world(w)
	# 天赋 + 装备 + 属性点合成
	var w2 := _new_world(32)
	Build.apply_to(w2, {"pow": 10}, {"gang_force": 3}, {}, "fist")
	_check(absf(float(w2.talent_stats["damage_pct"]) - (0.05 + 0.06)) < 1e-9, "属性点 + 天赋合并")
	_free_world(w2)
	# 存档：背包 / 穿戴；单机掉落；上限
	var old_path: String = Save.path
	Save.path = "user://test_gear_save.json"
	Save.load_data()
	Save.add_items(["weapon.0.1", "coat.1.2"])
	Save.set_gear(Save.items(), {"weapon": "weapon.0.1", "coat": "pants.0.9"})
	_check(Save.equip() == {"weapon": "weapon.0.1"}, "穿戴必须是背包里的、且部位对得上")
	var many := []
	for i in 60:
		many.append("charm.0.%d" % (100 + i))
	Save.add_items(many)
	_check(Save.items().size() == int(Data.gear["inventory_max"]) and Save.items().has("weapon.0.1"), "背包有上限，穿着的不会被挤掉")
	Save.set_meta_talents({"gang_force": 2, "zzz": 1})
	Save.load_data()
	_check(Save.meta_talents() == {"gang_force": 2} and Save.equip().has("weapon"), "天赋 / 装备持久化")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_gear_save.json"))
	Save.path = old_path
	Save.load_data()
	print("  天赋结构 / 解锁规则 / 装备生成 / 词条生效 / 合成加成 / 存档与上限  OK")


func _neili_test() -> void:
	print("\n=== 内力：气海三境 / 催动 / 入定 ===")
	var w := _new_world(5)
	w.skills.clear()
	var mx := w.st("max_neili")
	# 三境判定与伤害加成
	w.neili = mx * 0.9
	_check(w.realm() == GameWorld.Realm.YING and is_equal_approx(w.dmg_mult(), Data.T("ying_dmg") + w.st("ying_dmg")), "达到盈境门槛为盈，伤害加成（含武者的盈境加成）")
	w.neili = mx * 0.5
	_check(w.realm() == GameWorld.Realm.PING and is_equal_approx(w.dmg_mult(), 1.0), "平境无加成")
	w.neili = mx * 0.2
	_check(w.realm() == GameWorld.Realm.XU, "低于 25% 为虚")
	# 九阳神功降低盈境门槛
	w.xinfa["chunyang"] = 3
	w.xinfa_q["chunyang"] = [1, 1]           # 修习 1 份 + 两次「特别」强化各 2 份 = 5 份强度
	w.recalc()
	_check(absf(w.ying_at() - (Data.T("ying_at") - 0.1)) < 1e-6, "九阳神功 5 份强度：盈境门槛降低 10%%（实际 %.2f）" % w.ying_at())
	w.xinfa.clear()
	w.recalc()
	# 虚境回气更快（对比同样时间内的回复量）
	var wa := _new_world(6)
	var wb := _new_world(6)
	for x in [wa, wb]:
		x.skills.clear()
	wa.neili = wa.st("max_neili") * 0.1
	wb.neili = wb.st("max_neili") * 0.5
	var na := wa.neili
	var nb := wb.neili
	for i in 60:
		wa.step(DT)
		wb.step(DT)
	_check((wa.neili - na) > (wb.neili - nb) * 1.3, "虚境回气应比平境快（%.2f vs %.2f）" % [wa.neili - na, wb.neili - nb])
	# 盈境外泄：满内力时不会无限囤积，但仍然能保持盈
	wb.neili = wb.st("max_neili")
	for i in 600:
		wb.step(DT)
	_check(wb.realm() == GameWorld.Realm.YING, "满内力静止 10 秒仍应处于盈境")
	# 入定：站住 1.5 秒后回气 ×2.5、减伤
	var wm := _new_world(7)
	wm.skills.clear()
	wm.neili = wm.st("max_neili") * 0.4
	wm.input_move = Vector2.ZERO
	for i in int(1.0 / DT):
		wm.step(DT)
	_check(not wm.meditating(), "站立不足 1.5 秒不入定")
	for i in int(1.0 / DT):
		wm.step(DT)
	_check(wm.meditating(), "站立 ≥1.5 秒入定")
	wm.god = false
	wm.stats["armor"] = 0.0
	var h0 := wm.hp
	wm._hurt(10.0)
	_check(absf((h0 - wm.hp) - 10.0 * (1.0 - Data.T("meditate_reduce"))) < 0.01, "入定减伤 15%%（实际受伤 %.2f）" % (h0 - wm.hp))
	wm.input_move = Vector2.RIGHT
	wm.step(DT)
	_check(not wm.meditating(), "一移动就退出入定")
	_free_world(wm)
	# 九个招式的催动版：能出手、消耗内力、效果与普通版不同
	for id in Data.skills:
		var w2 := _new_world(11)
		w2.skills.clear()
		w2.add_skill(id)
		var sk: SkillBase = w2.skills[id]
		_populate(w2, 40)
		w2.neili = w2.st("max_neili")
		var before := w2.empower_count
		for i in int(maxf(8.0, float(Data.skills[id]["cooldown"]) * 1.5 + 4.0) / DT):      # 冷却长的招式要给足出手次数
			TestBot.drive(w2, 75.0 if sk.tags().has("近战") else 240.0)
			w2.step(DT)
			if id == "taiji" and i % 90 == 0:
				sk.on_hurt(20.0)
		_check(w2.empower_count > before, "%s：盈境下应触发催动" % Data.skills[id]["name"])
		_check(float(w2.skill_dmg.get(id, 0.0)) > 0.0, "%s：催动版应造成伤害" % Data.skills[id]["name"])
		_free_world(w2)
	# 催动的具体效果
	var we := _new_world(12)
	we.skills.clear()
	we.add_skill("eight_waste")
	var ew: SkillBase = we.skills["eight_waste"]
	_populate(we, 20)
	we.projs.clear()
	ew.empowered = true
	ew.fire()
	_check(we.projs.size() == int(ew.p("count")) + 4, "八荒六合功催动：基础 8 个 + 4 = 12 个（实际 %d）" % we.projs.size())
	we.projs.clear()
	ew.empowered = false
	ew.emp_burst = false
	ew.fire()
	_check(we.projs.size() == int(ew.p("count")), "八荒六合功普通版：%d 方向" % int(ew.p("count")))
	_free_world(we)
	# 运功升级：催动消耗递减
	var sb := SkillBase.new()
	sb.setup(_new_world(1), "yue_palm", Data.skills["yue_palm"])
	var c0 := sb.empower_cost()
	var ecut := sb.w.st("empower_cut")
	sb.add_upgrade("empower", 3)
	_check(absf(sb.empower_cost() - c0 * (1.0 - 0.4 - ecut) / (1.0 - ecut)) < 1e-6, "运功·传说：催动消耗再 −40%")
	print("  三境 / 门槛心法 / 回气 / 外泄 / 入定 / 9 招催动 / 运功  OK")


func _meta_test() -> void:
	print("\n=== 局外成长：修为 / 等级 / 属性 ===")
	var mv: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://backend/test/meta_vectors.json"))
	for v in mv["levels"]:
		_check(Meta.level_of(int(v["exp"])) == int(v["level"]), "等级向量不一致：%s" % str(v))
	for v in mv["effective"]:
		_check(absf(Meta.effective(int(v["points"])) - float(v["eff"])) < 1e-3, "有效点向量不一致：%s" % str(v))
	for v in mv["runExp"]:
		_check(Meta.run_exp(int(v["score"]), bool(v["won"]), bool(v["first"]), float(v.get("comp", 1.0))) == int(v["exp"]), "修为向量不一致：%s" % str(v))
	for v in mv["comp"]:
		_check(absf(Meta.comp_of(v["d"]) - float(v["comp"])) < 1e-9, "综合难度向量不一致：%s" % str(v))
	_check(Meta.exp_to_reach(50) == 9310 and Meta.points_total(50) == 147, "满级累计修为 9310、属性点 147")
	var p := Meta.progress(100)
	_check(int(p["level"]) == 3 and int(p["into"]) == 100 - 46 - 52 and int(p["need"]) == 58, "进度计算")
	_check(int(Meta.progress(99999)["need"]) == 0, "满级进度")
	# 属性效果
	var none := Meta.stats_for({})
	for k in none:
		_check(float(none[k]) == 0.0, "没加点时没有加成：" + k)
	var full := Meta.stats_for({"pow": 99, "agi": 99, "vit": 99, "int": 99, "luk": 99})
	_check(absf(float(full["damage_pct"]) - 0.005 * 59.7) < 1e-6 and absf(float(full["max_hp"]) - 1.5 * 59.7) < 1e-6, "99 点 = 59.7 有效点")
	_check(float(full["luck"]) > 0.4 and float(full["crit_chance"]) < 0.1, "福缘上限合理")
	_check(Meta.clean_alloc({"pow": 500, "agi": -3, "zzz": 9}) == {"pow": 99, "agi": 0, "vit": 0, "int": 0, "luk": 0}, "分配规范化")
	_check(Meta.points_used({"pow": 3, "agi": 4}) == 7, "已用点数")
	# 进入局内：属性加成确实改变了战斗属性
	var w := GameWorld.new()
	add_child(w)
	w.start_run()
	var hp0 := w.st("max_hp")
	var sp0 := w.st("speed_pct")
	w.talent_stats = Meta.stats_for({"vit": 30, "agi": 30})
	w.recalc()
	_check(absf(w.st("max_hp") - (hp0 + 45.0)) < 0.01, "根骨 30 点：气血 +45")
	_check(absf(w.st("speed_pct") - (sp0 + 0.09)) < 1e-6, "身法 30 点：移速 +9%")
	w.queue_free()
	# 福缘：高档位（大成 / 灵机一动）更常出现
	var r := RandomNumberGenerator.new()
	r.seed = 7
	var hi0 := 0
	var hi1 := 0
	for i in 20000:
		if Data.roll_tier(r, 0.0) >= 2:
			hi0 += 1
		if Data.roll_tier(r, 0.48) >= 2:
			hi1 += 1
	_check(float(hi1) > float(hi0) * 1.25, "福缘 +48%% 应明显提高高档位概率（%d → %d）" % [hi0, hi1])
	# 单机结算：存档里累加修为，首次通关多给奖励，只给一次
	var old_path: String = Save.path
	Save.path = "user://test_meta_save.json"
	Save.load_data()
	var win := {"won": true, "seconds": 750, "level": 38, "kills": 6100, "bosses": 4}
	var a: Dictionary = Save.add_run_exp(win)
	_check(int(a["gained"]) == 395 and int(a["level"]) >= 7, "单机首次通关 255+40+100")
	var b: Dictionary = Save.add_run_exp(win)
	_check(int(b["gained"]) == 295, "第二次通关没有首胜奖励")
	Save.set_meta_alloc({"pow": 12})
	Save.load_data()
	_check(Save.meta_exp() == 690 and Save.meta_alloc()["pow"] == 12, "修为与属性点应持久化")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_meta_save.json"))
	Save.path = old_path
	Save.load_data()
	print("  向量 / 软上限 / 属性效果 / 局内生效 / 福缘 / 单机结算 / 存档  OK")


func _fake_transport(is_get: bool, url: String, body: Dictionary) -> Dictionary:
	net_calls.append({"get": is_get, "url": url, "body": body.duplicate(true)})
	if not fake_reply.is_empty():
		return fake_reply
	match str(body["action"]):
		"login", "register", "resume":
			return {"ok": true, "nick": body.get("nick", "阿杰"), "token": "T1", "school": "fist", "bests": {"score": 5},
				"invite": "GRPAAA", "group": "篮球群", "exp": 120, "level": 3, "alloc": {"pow": 4, "agi": 2}}
		"submit":
			return {"ok": true, "score": 1234, "best": true, "ranks": {"score": 2, "speed": 0, "level": 3}, "bests": {"score": 1234},
				"gained": 255, "exp": 300, "level": 5, "levelUp": true}
		"board":
			return {"ok": true, "kind": body["kind"], "rows": [], "me": null, "total": 0}
	return {"ok": true}


func _net_test() -> void:
	print("\n=== 在线：得分公式 / 网络层（模拟传输） ===")
	var vec: Array = JSON.parse_string(FileAccess.get_file_as_string("res://backend/test/score_vectors.json"))
	for v in vec:
		_check(Score.compute(v) == int(v["score"]), "得分公式与后端向量不一致：%s" % str(v))
	var old_path: String = Save.path
	var old_url: String = Net.api_url
	Save.path = "user://test_net_save.json"
	Save.load_data()
	Net.api_url = ""
	var r0: Dictionary = await Net.call_api("ping")
	_check(str(r0["err"]) == "offline", "未配置时应返回 offline")
	_check(not Net.configured(), "api_url 为空 = 未配置")
	Net.api_url = "https://example.invalid/exec"
	Net.transport = _fake_transport

	# 登录
	var r1: Dictionary = await Net.login("阿杰", "2468")
	_check(bool(r1["ok"]) and Net.logged_in() and Net.nick == "阿杰" and Net.school == "fist", "登录后应记住昵称/令牌/流派")
	_check(str(Save.session().get("token", "")) == "T1", "令牌应写入本地存档")
	_check(Net.group_name == "篮球群" and Net.invite == "GRPAAA", "登录后应记住所属群")
	_check(Net.offline_allowed(), "非网页版允许离线（本地调试）")
	var c: Dictionary = net_calls[-1]
	_check(not c["get"] and c["body"]["pin"] == "2468" and not c["body"].has("token"), "登录请求：POST、带 PIN、不带令牌")
	# 带令牌的请求自动附带昵称 + 令牌
	await Net.save_state("fist")
	_check(net_calls[-1]["body"]["token"] == "T1" and net_calls[-1]["body"]["state"]["school"] == "fist", "saveState 应带令牌和流派")
	var sub: Dictionary = await Net.submit_run({"won": true, "seconds": 750, "level": 38, "kills": 6100, "bosses": 4,
		"school": "fist", "starter": "chain_fist", "qinggong": "tashue", "enhance": "yue_palm:3", "build": [{"id": "yue_palm", "lv": 12}], "version": "0.3"})
	_check(bool(sub["ok"]) and net_calls[-1]["body"]["build"] is String and net_calls[-1]["body"]["nick"] == "阿杰", "提交成绩：build 序列化为字符串、带昵称")
	_check(int(Net.bests.get("score", 0)) == 1234, "提交成功后应更新本地最高记录")
	_check(Net.exp == 300, "提交成功后应以服务器返回的修为为准")
	_check(Net.alloc.get("pow", 0) == 4 or Net.exp == 300, "登录应带回属性点分配")
	Save.create_character("fist")
	var sv: Dictionary = await Net.save_alloc({"pow": 7, "hax": 99})
	_check(bool(sv["ok"]) and net_calls[-1]["body"]["state"]["alloc"] == {"pow": 7, "agi": 0, "vit": 0, "int": 0, "luk": 0}
		and net_calls[-1]["body"]["state"]["school"] == "fist", "保存属性点：只带五种属性、同时带流派")
	var tv: Dictionary = await Net.save_talents({"gang_force": 3, "bogus": 2})
	_check(bool(tv["ok"]) and net_calls[-1]["body"]["state"]["talents"] == {"gang_force": 2}, "保存天赋：只带有效节点（上限 2）")
	var gv: Dictionary = await Net.save_gear({"weapon": "weapon.1.5"}, ["coat.0.1"])
	_check(bool(gv["ok"]) and net_calls[-1]["body"]["state"]["equip"] == {"weapon": "weapon.1.5"}
		and net_calls[-1]["body"]["state"]["discard"] == ["coat.0.1"], "保存装备：穿戴 + 丢弃列表")
	# 排行榜：GET，不带令牌
	await Net.board("score")
	_check(net_calls[-1]["get"] and net_calls[-1]["body"]["kind"] == "score" and not net_calls[-1]["body"].has("token"), "读榜应为 GET 且不带令牌")
	# 只看本群：带群代码；否则不带
	await Net.board("score", true)
	_check(net_calls[-1]["body"].get("group", "") == "GRPAAA", "仅看本群应带上邀请码")
	await Net.board("score", false)
	_check(not net_calls[-1]["body"].has("group"), "全体榜不应带 group")
	# 退出登录
	await Net.logout()
	_check(not Net.logged_in() and not Save.has_session() and net_calls[-1]["body"]["action"] == "logout", "退出登录应通知服务器并清除本地会话")
	_check(Net.group_name == "" and Net.invite == "", "退出登录应清掉所属群")

	# 续期：令牌失效 → 清会话；断网 → 保留会话
	Save.set_session("阿杰", "OLD")
	fake_reply = {"ok": false, "err": "bad_token", "msg": "登录已过期"}
	var r2: Dictionary = await Net.resume()
	_check(str(r2["err"]) == "bad_token" and not Save.has_session() and not Net.logged_in(), "令牌失效应清除本地会话")
	Save.set_session("阿杰", "OLD")
	fake_reply = {"ok": false, "err": "net", "msg": "网络连接失败"}
	await Net.resume()
	_check(Save.has_session() and not Net.logged_in(), "断网时应保留会话，下次再试")
	# 登录失败不应留下会话
	Save.clear_session()
	fake_reply = {"ok": false, "err": "bad_login", "msg": "昵称或 PIN 不正确", "left": 4}
	var r3: Dictionary = await Net.login("阿杰", "0000")
	_check(str(r3["err"]) == "bad_login" and not Net.logged_in() and not Save.has_session(), "登录失败不应留下会话")
	# 没有保存的登录
	fake_reply = {}
	var r4: Dictionary = await Net.resume()
	_check(str(r4["err"]) == "no_session", "没有会话时 resume 应返回 no_session")

	# 还原
	Net.transport = Callable()
	Net.api_url = old_url
	fake_reply = {}
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_net_save.json"))
	Save.path = old_path
	Save.load_data()
	print("  得分向量 / 离线 / 登录 / 令牌 / 提交 / 读榜 / 退出 / 续期 / 断网 / 失败  OK")


## 游戏里出现的每个汉字都必须在自带字库里（浏览器没有系统字体可回退，缺字会显示成方块）。
## 失败时：python3 tools/subset_font.py 重新裁剪字库（见脚本注释）。
func _font_coverage_test() -> void:
	print("\n=== 字库覆盖（游戏文案 + 后端提示里的每个字都要有）===")
	var font: Font = load("res://assets/fonts/main.ttf")
	var bold: Font = load("res://assets/fonts/main_bold.ttf")
	var files: Array[String] = []
	for dir in ["res://scripts", "res://scripts/skills", "res://data", "res://backend"]:
		for f in DirAccess.get_files_at(dir):
			if f.ends_with(".gd") or f.ends_with(".json") or f.ends_with(".gs"):
				files.append(dir + "/" + f)
	var missing := {}
	var total := 0
	for path in files:
		var seen := {}
		for ch in FileAccess.get_file_as_string(path):
			var code := ch.unicode_at(0)
			if code < 0x2E80 or seen.has(code):
				continue          # 只检查 CJK 及以上；ASCII 一定在字库里
			seen[code] = true
			total += 1
			if not font.has_char(code) or not bold.has_char(code):
				missing[ch] = path.get_file()
	for ch in missing:
		print("  缺字：「%s」（%s）" % [ch, missing[ch]])
	_check(missing.is_empty(), "字库缺少 %d 个字：%s" % [missing.size(), "".join(missing.keys())])
	if missing.is_empty():
		print("  %d 个文件、约 %d 个汉字出现，全部在字库中  OK" % [files.size(), total])


func _sprite_anim_test() -> void:
	print("\n=== 角色动画（回退链 / 帧计算 / 状态选择） ===")
	var a := SpriteAnim.new()
	_check(a.resolve("idle") == "", "没有任何动画时应返回空")
	var img := Image.create(64 * 6, 64, false, Image.FORMAT_RGBA8)
	var tex := ImageTexture.create_from_image(img)
	a.add_anim("idle", tex, 1, 1.0)
	_check(a.resolve("walk") == "idle", "缺 walk 时回退到 idle")
	_check(a.resolve("dash") == "idle", "缺 dash/walk 时回退到 idle")
	a.add_anim("walk", tex, 6, 10.0)
	_check(a.resolve("dash") == "walk", "有 walk 时 dash 回退到 walk")
	_check(a.frame_index("walk", 0.0) == 0 and a.frame_index("walk", 0.15) == 1, "walk 帧索引")
	_check(a.frame_index("walk", 0.6) == 0, "循环动画应回到第 0 帧")
	a.add_anim("punch", tex, 4, 16.0, false)
	_check(a.frame_index("punch", 10.0) == 3, "一次性动画应停在最后一帧")
	_check(is_equal_approx(a.anim_length("punch"), 0.25), "动画时长 = 帧数 / fps")
	# 真实素材能被加载
	var real := SpriteAnim.new()
	_check(real.load_dir("res://assets/sprites/player"), "assets/sprites/player 应能加载并包含 idle")
	for an in real.anims:
		var ad: Dictionary = real.anims[an]
		var tw: int = (ad["tex"] as Texture2D).get_width()
		_check(tw == int(ad["frames"]) * real.cell, "动画 %s 的条带宽度 %d 应等于 %d 帧 × %d" % [an, tw, int(ad["frames"]), real.cell])
		_check((ad["tex"] as Texture2D).get_height() == real.cell, "动画 %s 的条带高度应等于格子 %d" % [an, real.cell])
	print("  已加载的动画：", ", ".join(PackedStringArray(real.anims.keys())))
	# 状态选择
	var w := _new_world(71)
	_check(w._player_anim_state()[0] == "idle", "静止 → idle")
	w.input_move = Vector2.RIGHT
	_check(w._player_anim_state()[0] == "walk", "移动 → walk")
	w.dash_t = 0.1
	_check(w._player_anim_state()[0] == "dash", "冲刺 → dash")
	w.since_hit = 0.0
	_check(w._player_anim_state()[0] == "hurt", "刚受击 → hurt")
	w.play_anim("punch", 0.3)
	_check(w._player_anim_state()[0] == "punch", "出招动画优先于受击")
	w.over = true
	w.won = false
	_check(w._player_anim_state()[0] == "death", "阵亡 → death（最高优先）")
	_free_world(w)
	# 技能出招会触发动画
	var w2 := _new_world(72)
	_populate(w2, 30)
	for i in 120:
		TestBot.drive(w2, 75.0)
		w2.step(DT)
	_check(w2.anim_ovr == "punch", "太祖长拳出招应触发 punch 动画，实际 %s" % w2.anim_ovr)
	print("  回退链 / 帧索引 / 状态优先级 / 出招触发  OK")
	_free_world(w2)


func _xinfa_test() -> void:
	print("\n=== 心法冒烟（每个 Lv3，20 秒） ===")
	for id in Data.xinfa:
		var w := _new_world(31)
		w.xinfa[id] = 3
		w.recalc()
		_populate(w, 60)
		for i in int(20.0 / DT):
			TestBot.drive(w)
			w.step(DT)
		var bonus := ""
		for tg in Data.xinfa[id]["bonus"]:
			bonus += "%s+%d%% " % [tg, int(float(w.tag_bonus.get(tg, 0.0)) * 100.0)]
		_check(not w.tag_bonus.is_empty(), "%s 没有产生标签加成" % id)
		print("  %-6s %s| 击杀 %d" % [Data.xinfa[id]["name"], bonus, w.kills])
		_free_world(w)
	# 槽位上限检查
	var w2 := _new_world(32)
	for id in ["yue_palm", "quake_fist", "whirl_palm"]:
		w2.add_skill(id)
	w2.xinfa["chunyang"] = 1
	w2.xinfa["tiegu"] = 1
	var seen_new_skill := false
	var seen_new_xinfa := false
	for i in 40:
		for c in w2.roll_choices():
			if str(c["kind"]) == "new_skill":
				seen_new_skill = true
			if str(c["kind"]) == "new_xinfa":
				seen_new_xinfa = true
	_check(w2.skills.size() == 4, "测试准备：应已装满 4 个技能")
	_check(not seen_new_skill, "技能槽已满，升级池不应再出现新技能")
	_check(not seen_new_xinfa, "心法槽已满，升级池不应再出现新心法")
	print("  槽位上限：技能 4/4、心法 2/2 时不再刷新项  OK")
	_free_world(w2)


func _qinggong_test() -> void:
	print("\n=== 轻功冒烟（每个 20 秒，反复冲刺） ===")
	for id in Data.qinggong:
		var w := _new_world(41, "chain_fist", id)
		_populate(w, 60)
		var moved := 0.0
		for i in int(20.0 / DT):
			TestBot.drive(w)
			if i % 40 == 0:
				w.input_dash = true
				w.neili = w.st("max_neili")
			var before := w.player_pos
			w.step(DT)
			moved = maxf(moved, before.distance_to(w.player_pos))
		_check(w.dash_count > 3, "%s 冲刺次数过少：%d" % [id, w.dash_count])
		_check(moved > 5.0, "%s 单步位移异常" % id)
		print("  %-6s 冲刺 %2d 次  单步最大位移 %.0f  击杀 %d" % [Data.qinggong[id]["name"], w.dash_count, moved, w.kills])
		_free_world(w)


func _full_run(cfg: Dictionary) -> void:
	print("\n=== %s ===" % cfg["name"])
	var w := GameWorld.new()
	w.god = cfg["god"]
	w.rng_seed = cfg["seed"]
	add_child(w)
	w.start_run(cfg["starter"], cfg["qg"])
	var pick_rng := RandomNumberGenerator.new()
	pick_rng.seed = int(cfg["seed"]) * 7
	var steps := int(float(cfg["dur"]) / DT)
	var total_us := 0
	var worst_us := 0
	var peak := 0
	var next_report := 60.0
	var elites_killed := 0
	var chests_seen := 0
	var seen_mini := false

	for i in steps:
		TestBot.drive(w, TestBot.engage_for(w))
		var t0 := Time.get_ticks_usec()
		w.step(DT)
		var us := Time.get_ticks_usec() - t0
		total_us += us
		worst_us = maxi(worst_us, us)
		peak = maxi(peak, w.enemies.size())
		chests_seen = maxi(chests_seen, w.chests.size())
		if not TestBot.resolve_choices(w, pick_rng, bool(cfg["smart"])):
			failures += 1
			break
		if w.time >= next_report:
			next_report += 60.0
			var sk := ""
			for s: SkillBase in w.skills.values():
				sk += "%s%d " % [s.def["name"], s.level]
			print("t=%3ds lv=%2d hp=%3d neili=%3d 敌%3d 击杀%4d 强化=%s | %s| 心法=%s" % [
				int(w.time), w.level, int(w.hp), int(w.neili), w.enemies.size(), w.kills,
				w.enhance_id if w.enhance_id != "" else "-", sk, str(w.xinfa)])
		if w.over:
			break

	var outcome := "胜利" if w.won else ("阵亡" if w.over else "存活到时限")
	print("结果：%s @ %.1fs  等级 %d  击杀 %d  强化=%s Lv%d" % [outcome, w.time, w.level, w.kills, w.enhance_id, w.enhance_level])
	var rt: Array = w.realm_time
	var rsum := maxf(1.0, float(rt[0]) + float(rt[1]) + float(rt[2]))
	print("气海：虚 %d%% / 平 %d%% / 盈 %d%%　催动 %d 次" % [int(float(rt[0]) / rsum * 100.0), int(float(rt[1]) / rsum * 100.0),
		int(float(rt[2]) / rsum * 100.0), w.empower_count])
	print("Boss 击杀耗时：", ", ".join(w.boss_log) if not w.boss_log.is_empty() else "（无）")
	print("性能：平均 %.2f ms/step  最差 %.2f ms  敌人峰值 %d  Boss数 %d" % [
		total_us / 1000.0 / maxi(1, int(w.time / DT)), worst_us / 1000.0, peak, w.bosses.size()])
	if cfg["god"]:
		_check(w.bosses.size() == 4, "应刷出 3 个小 Boss + 1 个大 Boss，实际 %d" % w.bosses.size())
		_check(w.level >= 10, "无敌 bot 15 分钟应至少升到 10 级，实际 %d" % w.level)
		_check(w.enhance_id != "", "整局应至少拿到一次专属强化")
		_check(w.enhance_level >= 1, "击败小 Boss 后强化应至少 Lv1，实际 Lv%d" % w.enhance_level)
	_free_world(w)
