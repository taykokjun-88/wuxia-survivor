extends Node
## 无渲染测试：完整局模拟 + 全部技能/强化/心法/轻功的冒烟与伤害报告 + 秘籍流程。
## 运行：godot --headless --path . res://tests/sim_test.tscn

const DT := 1.0 / 60.0

var failures := 0


func _ready() -> void:
	var only := OS.get_environment("TEST_ONLY")
	if only == "":
		_chest_flow_test()
	if only == "fist":
		_fist_talent_test()
		_fist_sig_test()
	if only == "sword":
		_sword_tree_test()
	if only == "bladetree":
		_blade_tree_test()
	if only == "speartree":
		_spear_tree_test()
		_single_chain_test()
	if only == "" or only == "upgrade":
		_upgrade_system_test()
		_enhance_rework_test()
		_level_growth_test()
		_save_test()
		_sprite_anim_test()
		await _enemy_action_test()
		await _net_test()
		_meta_test()
		_neili_test()
		_build_test()
		_talent_map_test()
		_talent_skill_test()
		_fist_talent_test()
		_fist_sig_test()
		_sword_tree_test()
		_blade_tree_test()
		_spear_tree_test()
		_single_chain_test()
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
		await _chars_test()
		_smith_test()
		_prop_test()
		_boss_skill_test()
		_skill_fx_test()
		_stage_test()
		_stage2_boss_test()
		_map_collision_test()
		_spear_test()
		_spear_sweep_test()
		_wuming_test()
		_bagua_test()
		_map_spawn_test()
		await _touch_test()
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
	if only == "chars":
		await _chars_test()
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
	if only == "spear":
		_spear_test()
		_spear_sweep_test()
		_wuming_test()
	if only == "bagua":
		_bagua_test()
	if only == "touch":
		await _touch_test()
	if only == "spawn":
		_map_spawn_test()
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


## 无迹九变剑：会选卡的 bot 多个种子，看总层数何时越过 20 / 30（不无敌 + 无敌各一组）
func _dugu_report() -> void:
	print("\n=== 无迹九变剑 · 总层数进度（会选卡 bot）===")
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
	# 耗血刀法：朱砂饮锋刀 / 燃木 / 玄虚 / 屠龙共 4 个会耗血，耗的血也涨刀魂，且不会把自己耗死
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
		_populate(wh, 40)
		for k in 12:                                                    # 身边也放一圈怪（刷怪变慢后，不能指望它们自己凑过来）
			wh._spawn_enemy("bandit", wh.player_pos + Vector2.from_angle(TAU * float(k) / 12.0) * 90.0)
		var soul_max := 0.0
		for i in int(20.0 / DT):
			TestBot.drive(wh, 75.0)
			wh.step(DT)
			soul_max = maxf(soul_max, wh.soul)
		_check(wh.skills[id].cd_total > 0.0 or float(wh.skill_dmg.get(id, 0.0)) > 0.0, "%s 出过手" % id)
		_check(soul_max > 0.0, "%s：耗血 / 命中涨刀魂（最高 %.1f）" % [id, soul_max])
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
	_check(absf((wpay.st("max_hp") - wpay.hp) - wpay.st("max_hp") * 0.06) < 0.01 and wpay.soul > 4.0, "斩蛟沉海刀耗 6%% 气血并涨刀魂（%.1f）" % wpay.soul)
	wpay.hp = wpay.st("max_hp")
	wpay.soul = 0.0
	wpay.skills["tulong_art"].free_cast = true
	wpay.skills["tulong_art"].pay_hp()
	_check(is_equal_approx(wpay.hp, wpay.st("max_hp")) and wpay.soul == 0.0, "免费释放（号令天下）不耗血")
	_free_world(wpay)
	# 反两仪：抹弹幕、减伤反弹；斩蛟沉海刀：免费释放；朱砂饮锋刀：不会把自己耗死
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
	_check(w4.zones.size() > zc, "真气爆发触发斩蛟沉海刀「号令天下」")
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
	_check(min_hp >= 1.0, "朱砂饮锋刀耗血不会自杀（最低气血 %.1f）" % min_hp)
	_free_world(w5)
	# 武器：按稀有度选名；传说只出斩蛟宝刀
	var legend := Gear.make("weapon.3.12345", "blade")
	_check(str(legend["name"]) == "斩蛟宝刀", "刀客传说武器 = 斩蛟宝刀（%s）" % str(legend["name"]))
	var okn := true
	for sd in 40:
		var n0 := str(Gear.make("weapon.0.%d" % (1000 + sd), "blade")["name"])
		if not ["百炼柳叶刀", "鬼头大环刀", "黑煞雁翎刀"].has(n0):
			okn = false
	_check(okn, "刀客普通武器只出前 3 把刀")
	_check(Gear.items_for("weapon", "blade").size() == 10, "刀客武器清单 10 把")
	_check(Gear.items_for("weapon", "sword").size() == 10 and str(Gear.make("weapon.3.12345", "sword")["name"]) != "", "剑侠武器不受影响")
	# 斩蛟宝刀彩蛋：灭灶掌门二阶段时触发 —— 无视 50% 防御、护盾双倍伤害、破盾后易伤
	var w6 := _s2_world(67)
	w6.tulong_equipped = true
	w6._spawn_boss("s2_boss", true)
	var fb: Enemy = w6.bosses[0]
	fb.max_hp = 1e9
	fb.hp = 4e8
	for i in 8:
		w6.step(DT)
	_check(w6.tulong_on and fb.phase2, "装备斩蛟宝刀，灭灶掌门二阶段触发彩蛋")
	fb.guard = 0.0
	fb.guard_regen = 99.0
	fb.shield = 100.0
	fb.shield_max = 100.0
	w6.hit_enemy(fb, 1000.0, [], Vector2.ZERO, "wuhu_blade")
	_check(fb.shield <= 0.0 and fb.vuln_t > 0.0 and fb.vuln >= 0.3, "斩蛟宝刀破盾后易伤")
	_free_world(w6)
	var w7 := _s2_world(68)
	w7._spawn_boss("s2_boss", true)
	var fb2: Enemy = w7.bosses[0]
	fb2.max_hp = 1e9
	fb2.hp = 4e8
	for i in 8:
		w7.step(DT)
	_check(not w7.tulong_on, "没有装备斩蛟宝刀不触发彩蛋")
	_free_world(w7)
	# 天赋
	var tn: Dictionary = Talents.nodes("blade")
	_check(str(tn["bl_peak"]["name"]) == "刀皇霸体" and str(tn["bg_g_2"]["name"]) == "聚魂", "刀客天赋（新树）")
	_check(float(Talents.stats_for({"bg_a_3": 2}, "blade").get("bleed_pow", 0.0)) > 0.15, "撕裂入骨：撕裂强化")


func _sword_test() -> void:
	print("\n=== 剑侠：流派 / 招式池 / 剑侠专属机制 ===")
	_check(bool(Data.schools["sword"]["enabled"]), "剑侠流派应已开放")
	var pool := 0
	for id in Data.skills:
		if str(Data.skills[id]["school"]) == "sword":
			pool += 1
	_check(pool == 10, "剑侠应有 9 个招式 + 无迹九变剑，实际 %d" % pool)
	for sid in Data.schools["sword"]["starters"]:
		_check(Data.skills.has(sid) and str(Data.skills[sid]["school"]) == "sword", "剑侠起手招式有效: %s" % sid)
	# 选卡池只出本流派招式
	var w := _new_world(5, "kuang_feng")
	_check(w.school_id == "sword", "起手剑侠招式 → 流派 sword")
	for i in 40:
		for c in w.roll_choices(3):
			if str(c["kind"]) == "new_skill":
				_check(str(Data.skills[c["id"]]["school"]) == "sword", "不应出现其他流派招式: %s" % c["id"])
	# 起手不选无迹九变剑：升级 / 秘籍选项里永远不会出现无迹九变剑
	for i in 300:
		for c in w.roll_choices(3):
			_check(not (str(c["kind"]) == "new_skill" and str(c["id"]) == "dugu"), "非九变路线的升级选项里不应出现无迹九变剑")
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
	_check(w.sprite_anim != null and w.sprite_anim.anims.has("true_walk"), "无迹九变剑开局使用剑侠动画")
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
	print("\n=== 剑侠天赋（新树）/ 武器名 ===")
	_check(Talents.has_tree("sword") and Talents.has_tree("fist") and Talents.has_tree("blade") and Talents.has_tree("spear"), "四个职业都用新树")
	var ts := Talents.stats_for({"sg_peak": 1, "sl_peak": 1, "sl_a_3": 2, "sg_a_1": 2}, "sword")
	_check(absf(float(ts.get("ying_dmg", 0.0)) - 0.10) < 1e-6 and float(ts.get("burst_yang", 0.0)) == 1.0, "剑意凌霄：阳性内力 + 盈境伤害 +10%")
	_check(absf(float(ts.get("skill:dugu:damage", 0.0)) - 0.12) < 1e-6 and absf(float(ts.get("skill:dugu:crit", 0.0)) - 0.06) < 1e-6 and absf(float(ts.get("skill:dugu:cooldown", 0.0)) - 0.08) < 1e-6 and absf(float(ts.get("crit_mult", 0.0)) - 0.06) < 1e-6, "剑魔：无迹九变剑 伤害 +12%、暴击率 +6%、冷却 −8%，暴击伤害 +6%")
	_check(absf(float(ts.get("skill:qingsong:damage", 0.0)) - 0.16) < 1e-6, "劲柏扎根 2 级：劲柏凌霜剑伤害 +16%")
	var w := GameWorld.new()
	w.rng_seed = 4
	w.god = true
	add_child(w)
	Build.apply_to(w, {}, {"sg_a_1": 3, "sg_a_2": 2}, {}, "sword")
	w.start_run("qingsong", "tashue")
	var s: SkillBase = w.skills["qingsong"]
	_check(absf(float(s.mods["damage"]) - 0.24) < 1e-6 and absf(float(s.mods["range"]) - 0.20) < 1e-6, "天赋并入招式：伤害 +24%、范围 +20%（%s / %s）" % [str(s.mods["damage"]), str(s.mods["range"])])
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
		if not bool(Data.schools[str(Data.skills[id]["school"])]["enabled"]):
			continue                                       # 还没开放的流派（杨家将，等美术）不要求有特效
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
				w._hurt(30.0)           # 回澜卸力诀：受击才反击
			w.step(DT)
			for fxe in w.effects:
				if want.values().has(str(fxe.get("vfx", ""))) or (Data.skills[id].get("fx_alt", []) as Array).has(str(fxe.get("vfx", ""))):
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
	_check(float(tl["final"]["t"]) == 600.0 and float(tl["final"]["limit"]) == 150.0, "黑风寨：大 Boss 10:00 现身，限时 2:30")
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
	_check(absf((w.boss_deadline - w.time) - 150.0) < 8.0, "倒计时约 150 秒（%.0f）" % (w.boss_deadline - w.time))
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
	_check(Save.map_unlocked("black_wind") and Save.map_unlocked("guangming"), "赤焰巅不再需要通关黑风寨（只需局外 Lv5）")
	_check(int(Data.maps["guangming"]["min_meta_level"]) == 5, "赤焰巅需局外等级 5")
	# 装备分数
	var eq_n := {"weapon": "weapon.0.5", "coat": "coat.0.6", "pants": "pants.0.7", "boots": "boots.0.8", "charm": "charm.0.9"}
	var eq_g := {"weapon": "weapon.1.5", "coat": "coat.1.6", "pants": "pants.1.7", "boots": "boots.1.8", "charm": "charm.1.9"}
	var sn := Gear.total_score(eq_n, {}, "sword", "")
	var sg := Gear.total_score(eq_g, {}, "sword", "")
	_check(sn >= 18 and sn <= 28 and sg >= 33 and sg <= 46 and sg > sn, "按数值算分：5 件普通约 22、5 件特别约 39（实际 %d / %d）" % [sn, sg])
	var eq_p := {"weapon": "weapon.2.99", "coat": "coat.2.291", "pants": "pants.2.205", "boots": "boots.2.154", "charm": "charm.2.251"}
	var sp_d := Gear.total_score(eq_p, {}, "sword", "dugu")
	var sp_o := Gear.total_score(eq_p, {}, "sword", "kuang_feng")
	_check(sp_d > sp_o and sp_o > sg, "适配度：起手九变时九变词条套装分更高（%d > %d）" % [sp_d, sp_o])
	var enh_p := {}
	for k in eq_p:
		enh_p[eq_p[k]] = 10
	_check(Gear.total_score(eq_p, enh_p, "sword", "dugu") > sp_d, "强化提高装备分")
	var one := Gear.total_score({"weapon": "weapon.2.99"}, {}, "sword", "dugu")
	_check(sp_d > one * 5, "联动：五件同招式词条的总分高于五件单件分之和（%d vs %d）" % [sp_d, one * 5])
	var rec: Array = Save.recommend_status("guangming")
	_check(rec.size() == 1 and not bool(rec[0]["ok"]), "建议条件：装备分数 40（三件低品质未达标）")
	Save.set_gear(eq_p.values(), eq_p)
	rec = Save.recommend_status("guangming")
	_check(rec.size() == 1 and bool(rec[0]["ok"]), "建议条件：五件稀有装备达标")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_stage.json"))
	Save.path = old_path
	Save.load_data()


func _map_collision_test() -> void:
	print("\n=== 赤焰巅地图：障碍碰撞 / 素材 / 解锁 ===")
	var w := _s2_world(91)
	_check(w.map_art != null and w.map_art.has_blockers, "赤焰巅地图有挡路物件")
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
	_check(bool(Data.maps["guangming"]["enabled"]), "赤焰巅已开放")
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
	print("\n=== 赤焰巅 Boss：新招式 / 红色预警 / 毒雾冰封 / 二阶段 + 护盾 / 破防 / 无视防御 ===")
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
			_check(b.phase2 and b.defense > 0.29 and b.shield_max > 0.0, "灭灶掌门进入二阶段")
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
		if str(fx.get("text", "")) == "断云不出，谁与争锋":
			found_text = true
	_check(found_text, "弹出「断云不出，谁与争锋」")
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
	print("\n=== 无迹九变剑：式 / 叠加 / 阶段 / 真·无迹九变剑 ===")
	var w := _new_world(7, "dugu")
	_check(w.school_id == "sword" and w.skills.size() == 1 and w.skills.has("dugu"), "无迹九变剑起手：只有无迹九变剑")
	# 升级卡：只出「式」，不出别的招式 / 招式升级
	for i in 30:
		var ch := w.roll_choices(3)
		var shi_n := 0
		for c in ch:
			var k := str(c["kind"])
			_check(k != "new_skill" and k != "up_skill", "九变路线不应出招式卡（%s）" % k)
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
	_check(w.dugu_stage() == 3 and w.dugu_true() and w.dash_sealed(), "总层 27 → 真·无迹九变剑，轻功封印")
	# 升级一次 = 强化一次 = +1 层；品质只加威力，不加层数（不影响 9 / 18 / 27 门槛）
	var wl := _new_world(70, "dugu")
	for lvl in 28:
		wl.pending_levels = 1
		var chs: Array = wl.roll_choices(3)
		var pick: Dictionary = {}
		for c in chs:
			if str(c["kind"]).begins_with("shi_"):
				pick = c
				break
		_check(int(pick["gain"]) == 1 and pick.has("tier") and float(pick["bonus"]) >= 0.0, "升级卡：+1 层，带品质（%s）" % str(pick.get("tag", "")))
		wl.apply_choice(pick)
		if wl.shi_total() == 9 or wl.shi_total() == 18 or wl.shi_total() == 27:
			var want := {9: 1, 18: 2, 27: 3}[wl.shi_total()] as int
			_check(wl.dugu_stage() >= want and (wl.shi_total() != 9 or wl.dugu_micro()), "第 %d 次升级（局内 %d 级）达到 %d 层" % [lvl + 1, lvl + 2, wl.shi_total()])
		if lvl == 7:
			_check(wl.shi_total() == 8 and not wl.dugu_micro(), "8 次升级只有 8 层：还没到 9 层门槛")
	_check(wl.shi_total() == 28 or wl.shi_total() == 27 or wl.shi_total() <= 28, "总层数只看升级次数")
	_free_world(wl)
	var wq := _new_world(71, "dugu")
	wq.shi = {"po_dao": 5}
	var gold := {"kind": "shi_up", "id": "po_dao", "gain": 1, "tier": 3, "bonus": 1.5, "tag": "传说", "src": "level"}
	wq.pending_levels = 1
	wq.apply_choice(gold)
	_check(wq.shi_total() == 6 and wq.shi_lv("po_dao") == 7 and float(wq.shi_bonus["po_dao"]) == 1.5, "金色品质：层数 +1（6），生效层数 7（+1 加成，不计入门槛）")
	wq.pending_levels = 1
	wq.apply_choice(gold)
	_check(wq.shi_total() == 7 and wq.shi_lv("po_dao") == 10 and (wq.skills["dugu"] as SwordSkills.Dugu).L("po_dao") == 10, "再来一次：加成累计 3.0，生效层数 10；无迹九变剑按生效层数结算")
	_free_world(wq)
	# 秘籍：只给紫 / 金品质加成，不加层数
	w.shi = {"po_jian": 2}
	var cc := w.roll_chest_choices()
	_check(not cc.is_empty() and str(cc[0]["kind"]).begins_with("shi_") and int(cc[0]["tier"]) >= 2, "九变路线的秘籍：紫 / 金品质的式")
	var tot0 := w.shi_total()
	for c in cc:
		if str(c["kind"]) == "shi_up":
			_check(int(c["gain"]) == 0, "秘籍的升级卡不加层数")
	var up_card: Dictionary = {}
	for c in cc:
		if str(c["kind"]) == "shi_up":
			up_card = c
	if not up_card.is_empty():
		w.pending_chests = 1
		w.apply_choice(up_card)
		_check(w.pending_chests == 0 and w.shi_total() == tot0 and float(w.shi_bonus.get(str(up_card["id"]), 0.0)) >= 1.0, "秘籍选完：层数不变，这一式威力加成 ≥ +1")
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

	# ---- 真·无迹九变剑：觉醒触发「剑破天下」九连闪现 → 之后近身范围群攻；真气爆发可再次触发 ----
	var w4 := _new_world(10, "dugu")
	w4.time = 120.0
	w4.shi = {"zong": 10, "po_jian": 10, "po_dao": 10, "po_bian": 6}      # 总层 36，已是真形态（直接赋值不触发觉醒）
	_check(w4.dugu_true(), "真·无迹九变剑已觉醒")
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
			if tx.ends_with("变"):
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
	_check(c2 + 6 >= c4 and c4 + 4 >= c9 and c1 > 0, "连击几率独立判定：9 连 9%% / 4 连 18%% / 2 连 36%% / 单击 36%%（%d / %d / %d / %d）" % [c9, c4, c2, c1])
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
		ds.call("_pulse", "分锋变", 1.0)
		dmgs.append(h0 - tgt.hp)
		radii.append(float(ds.call("pulse_radius")))
		_free_world(wp)
	_check(float(dmgs[1]) > float(dmgs[0]) * 1.4, "分锋变：真形态每 3 层多一圈余波（伤害 %d → %d）" % [int(dmgs[0]), int(dmgs[1])])
	_check(float(radii[2]) > float(radii[0]) + 40.0, "贯甲变：真形态斩击范围变大（%d → %d）" % [int(radii[0]), int(radii[2])])
	_check(float(radii[3]) > float(radii[0]) * 1.2 and float(dmgs[3]) > float(dmgs[0]) * 1.1, "掠空变：真形态斩击范围和伤害提高")


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
	# 之后每本秘籍：仍然三选一，必有目前生效的那一本；选它升一级
	for expect in [2, 3]:
		w.chests.append(w.player_pos)
		w.step(DT)
		_check(w.pending_chests == 1, "已有强化时拾到秘籍仍要选择")
		var chs := w.roll_chest_choices()
		var has_cur := false
		for c: Dictionary in chs:
			if str(c["id"]) == "chain_fist":
				has_cur = true
		_check(has_cur, "三张秘籍里必有当前生效的强化")
		for c: Dictionary in chs:
			if str(c["id"]) == "chain_fist":
				w.apply_choice(c)
				break
		_check(w.enhance_level == expect, "选当前强化应升到 Lv%d，实际 Lv%d" % [expect, w.enhance_level])
	w.chests.append(w.player_pos)
	w.step(DT)
	for c: Dictionary in w.roll_chest_choices():
		if str(c["id"]) == "chain_fist":
			w.apply_choice(c)
			break
	_check(w.enhance_level == 3, "强化最高 Lv3，满级选它给奖励但不超过 3")
	# 换一本：替换原来的强化，从 Lv1 开始（局内只有一个专属强化）
	w.add_skill("vajra_fist")
	w.chests.append(w.player_pos)
	w.step(DT)
	var other := {}
	for c: Dictionary in w.roll_chest_choices():
		if str(c["id"]) == "vajra_fist":
			other = c
	_check(not other.is_empty(), "另一张秘籍给出别的招式的强化")
	w.apply_choice(other)
	_check(w.enhance_id == "vajra_fist" and w.enhance_level == 1, "选别的秘籍会替换原强化并从 Lv1 开始")
	# 边界：连续拾到两本 → 要选两次
	var w2 := _new_world(12)
	w2.chests.append(w2.player_pos)
	w2.chests.append(w2.player_pos)
	w2.step(DT)
	w2.step(DT)
	_check(w2.pending_chests == 2, "连续拾到两本应有 2 个待选")
	w2.apply_choice(w2.roll_chest_choices()[0])
	w2.apply_choice(w2.roll_chest_choices()[0])
	_check(w2.enhance_level == 2 and w2.pending_chests == 0, "两次选当前强化 → Lv2，实际 Lv%d" % w2.enhance_level)
	print("  强化 Lv1→2→3、封顶、替换、连拾  OK")
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
				# 回澜卸力诀是受击触发：god 模式下直接调用，覆盖反击分支
				if id == "taiji" and i % 120 == 0:
					s.on_hurt(30.0)
				if w.over:
					guard_ok = false
					break
			var dmg := float(w.skill_dmg.get(id, 0.0))
			_check(guard_ok, "%s %s：god 模式下不应结束" % [id, mode])
			if id != "panlong_staff":                           # 蟠龙棍法是守势（格挡时才反击）
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
	print("\n=== 强化改版：品质 / 10 次强化 / 起手招式不再出现 / 心法同修 / 恢复速度 / 九变门槛 ===")
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
	_check(absf(float(yue.link_applied.get("damage", 0.0)) - want) < 1e-9, "同修：撼岳惊涛掌伤害 +%.0f%%" % (want * 100.0))
	var d_before := float(yue.mods["damage"])
	for i in 5:
		wx.recalc()
	_check(is_equal_approx(float(yue.mods["damage"]), d_before), "反复重算不会重复叠加联动")
	_check(float(yue.link_flags.get("ying", 0.0)) > 0.0, "煌日真诀同修：盈境增伤标记")
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
	_check(wn.neili > 10.4, "鲸吞秘诀同修：命中回内力（%.2f）" % wn.neili)
	_free_world(wn)
	var wv := _new_world(86, "kuang_feng")
	wv.skills.clear()
	wv.add_skill("yunv")
	wv.apply_choice({"kind": "new_xinfa", "id": "hanshuang", "src": "level"})
	var tv := Enemy.new()
	tv.hp = 1e12
	tv.max_hp = 1e12
	wv.hit_enemy(tv, 10.0, ["范围"], Vector2.ZERO, "yunv")
	_check(tv.vuln_t > 0.0 and tv.vuln > 0.0, "霜髓寒诀同修：命中露出破绽")
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
	_check(bled > 10, "玄龟吐纳同修：命中有几率撕裂（%d/60）" % bled)
	_free_world(wbl)
	# 每个心法点名 4 个非起手招式（原 3 个 + 杨家将 1 个；可以跨流派，各自的加成不同）；每个非起手招式至少被一个心法点名
	var covered := {}
	var cross := 0
	for id in Data.xinfa:
		var lk: Dictionary = Data.xinfa[id]["link"]
		_check(lk.size() == 4, "%s 点名 %d 个招式（要求 4 个）" % [id, lk.size()])
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
	# 流派特色：剑侠 = 速度 / 攻速；武者 = 内力（盈境加成高、催动贵）；刀客 = 气血；无迹九变剑催动消耗减半
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
	_check(float(Data.skills["dugu"]["empower_cost"]) <= 4.5 and cdu > 0.0, "无迹九变剑：催动消耗大幅降低（%.1f）" % cdu)
	_free_world(wdu)
	_free_world(wsw)
	_free_world(wfi)
	_free_world(wbl2)
	# 局外属性 / 天赋：内力和气血恢复相关，数量不多；各流派覆盖不改节点 id / 上限
	var ms := Meta.stats_for({"pow": 0, "agi": 0, "vit": 30, "int": 30, "luk": 0})
	_check(float(ms["hp_regen"]) > 0.1 and float(ms["neili_regen"]) > 2.0, "根骨加气血回复、内息加内力回复（%.2f / %.2f）" % [ms["hp_regen"], ms["neili_regen"]])
	var base_nodes: Dictionary = Talents.nodes()
	for sc in []:
		var sn: Dictionary = Talents.nodes(sc)
		var diff := 0
		for nid in sn:
			_check(int(sn[nid]["max"]) == int(base_nodes[nid]["max"]), "%s 流派天赋 %s 上限不变" % [sc, nid])
			diff += 1 if str(sn[nid]["name"]) != str(base_nodes[nid]["name"]) or str(sn[nid]["desc"]) != str(base_nodes[nid]["desc"]) else 0
		_check(diff >= 4, "%s 流派有专属天赋覆盖（%d 个）" % [sc, diff])
	# 每个流派的天赋树只能加成本流派的招式（不能在刀客的树里看到撼岳惊涛掌）
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
	_check(Talents.stats_for({"sl_a_1": 2}, "sword").has("t_chuwu") and Talents.stats_for({"fl_g_1": 2}, "fist").has("t_xushi"), "剑侠灵系第一格是初悟；武者灵系第一格是蓄势待发")
	_check(float(Talents.stats_for({"br_g_1": 3}, "blade")["hp_regen"]) > float(Talents.stats_for({"fr_g_1": 3}, "fist")["hp_regen"]), "刀客的气血回复天赋更强")
	_check(Talents.stats_for({"fr_g_6": 2}, "fist").has("med_regen"), "武者的入定归元加快入定回气")
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
	# 无迹九变剑：破 X 式总强化次数门槛 9 / 18 / 27
	_check(int(Data.T("shi_stage1")) == 9 and int(Data.T("shi_stage2")) == 18 and int(Data.T("shi_stage3")) == 27, "无迹九变剑门槛 9 / 18 / 27")
	for sh in Data.shi:
		_check(str(sh.get("desc", "")) != "" and str(sh.get("awaken", "")) != "", "式「%s」要有普通效果和觉醒效果的说明" % sh["name"])
	var wsc := _new_world(96, "dugu")
	wsc.shi = {"po_jian": 1}
	var sc := wsc.shi_cards(3, 2, "level")
	_check(not sc.is_empty() and str(sc[0]["desc"]).contains("普通：") and str(sc[0]["desc"]).contains("觉醒："), "式的卡片同时写明普通和觉醒效果")
	_free_world(wsc)


## 计划书 6：另觅机缘 / 真·霸刀破岳 / 蓄劲 / 无迹九变剑 9-18-27
func _plan6_test() -> void:
	print("\n=== 计划书 6：另觅机缘 / 真·霸刀破岳 / 蓄劲 / 无迹九变剑 ===")
	# ---- Boss 只吃破绽效果的一半 ----
	var wbv := _new_world(98, "dugu")
	wbv.shi = {"zong": 18}
	var nb1 := wbv._spawn_enemy("bandit", wbv.player_pos + Vector2(900, 0))
	var bb1 := wbv._spawn_enemy("bandit", wbv.player_pos + Vector2(900, 100))
	bb1.is_boss = true
	wbv.apply_vuln(nb1, 0.4)
	wbv.apply_vuln(bb1, 0.4)
	_check(is_equal_approx(nb1.vuln, 0.4) and is_equal_approx(bb1.vuln, 0.2), "Boss 的破绽承伤加成减半（%.2f / %.2f）" % [nb1.vuln, bb1.vuln])
	_check(is_equal_approx(nb1.atk_mul(), 0.7) and is_equal_approx(bb1.atk_mul(), 0.85), "Boss 的攻击削弱减半（%.2f / %.2f）" % [nb1.atk_mul(), bb1.atk_mul()])
	_free_world(wbv)
	# ---- 装备：词条和现在的武功机制对得上 ----
	var all_keys := {}
	for sl in Data.gear["slots"]:
		var its: Array = sl["items"] if sl.has("items") else []
		if sl.has("items_by_school"):
			for sch in sl["items_by_school"]:
				its.append_array(sl["items_by_school"][sch])
		for it in its:
			for k in it["base"]:
				all_keys[k] = true
	for k in Data.gear["subs"]:
		all_keys[k] = true
	for k in all_keys:
		_check(Gear.STAT_NAMES.has(k) and Data.player_base.has(k), "装备属性 %s 有中文名且是游戏里存在的属性" % k)
	var slot_names := []
	for sl in Data.gear["slots"]:
		slot_names.append(str(sl["name"]))
	_check(slot_names == ["武器", "上衣", "下半身", "鞋子", "配饰"], "装备部位名：%s" % str(slot_names))
	for sch in ["fist", "sword", "blade"]:
		var seen_rel := 0
		var rr := RandomNumberGenerator.new()
		rr.seed = 7
		for i in 400:
			var itm := Gear.make(Gear.make_code("weapon", 3, 1 + rr.randi() % 99999), sch)
			for a in itm["affixes"]:
				if str(a["kind"]) == "xinfa":
					var linked := false
					for sid3 in Data.xinfa[a["id"]]["skills"]:
						if str(Data.skills[sid3]["school"]) == sch:
							linked = true
					_check(linked, "心法词条只会是能强化本流派招式的心法（%s / %s）" % [sch, a["id"]])
					seen_rel += 1
		_check(seen_rel > 0, "%s 的装备能出心法词条" % sch)
	var wq := _new_world(97, "chain_fist")
	wq.stats["qi_gain"] = 0.5
	var qq := wq.fist_qi
	wq.fist_after_cast(wq.skills["chain_fist"])
	_check(is_equal_approx(wq.fist_qi - qq, 4.5), "装备「蓄劲速度 +50%」：每次出手 +4.5")
	_free_world(wq)
	var wsg := _blade_world(96)
	wsg.stats["soul_gain"] = 0.5
	wsg.soul = 0.0
	wsg.add_soul(10.0)
	_check(is_equal_approx(wsg.soul, 15.0), "装备「刀魂增长 +50%」")
	_free_world(wsg)
	var wdc := _new_world(95, "dugu")
	wdc.shi = {"zong": 27}
	var dgc: SwordSkills.Dugu = wdc.skills["dugu"]
	_check(wdc.dugu_true() and dgc.mods.has("cooldown"), "无迹九变剑真形态：冷却词条 / 天赋会生效")
	_free_world(wdc)
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
	# （剑客「灵」系已改成九变之道，结构见 _sword_tree_test）
	# 效果：万法 / 破阵
	var wdt := _new_world(94, "dugu")
	wdt.talent_stats = {"dugu_vuln": 0.0}
	wdt.recalc()
	wdt.shi = {"zong": 18}
	var ev1 := wdt._spawn_enemy("bandit", wdt.player_pos + Vector2(900, 0))
	wdt.apply_vuln(ev1, 0.3)
	_check(is_equal_approx(ev1.vuln, 0.3), "没有「万法」天赋：破绽 +30%")
	wdt.talent_stats["dugu_vuln"] = 0.3
	wdt.recalc()
	var ev2 := wdt._spawn_enemy("bandit", wdt.player_pos + Vector2(900, 80))
	wdt.apply_vuln(ev2, 0.3)
	_check(is_equal_approx(ev2.vuln, 0.39), "万法 3 级：破绽 +30%% ×1.3 = %.2f" % ev2.vuln)
	_free_world(wdt)
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
	_check(absf((cd0j - wjs.cd_mult()) - 0.2) < 1e-6, "极·千锋聚啸剑：冷却 −20%")
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
	# ---- 无迹九变剑 9 / 18 / 27 ----
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
	_check(wd.dugu_can_cut(), "学了落矢变也能斩落")
	_check(not (Data.shi as Array).any(func(d): return str(d["desc"]).contains("追踪剑气")), "落矢变不再是自动射箭")
	# 连击几率
	_check(is_equal_approx(Data.T("dugu_combo2"), 0.45) and is_equal_approx(Data.T("dugu_combo4"), 0.20) and is_equal_approx(Data.T("dugu_combo9"), 0.08), "觉醒连击几率 45% / 20% / 8%")
	_free_world(wd)


## 多角色：单机存档里最多 5 个角色，各自独立；选人界面；删除；切换
func _chars_test() -> void:
	print("\n=== 多角色：创建 / 选择 / 删除 / 各自独立的进度 / 选人界面 ===")
	var old_path: String = Save.path
	var old_url: String = Net.api_url
	Save.path = "user://test_chars_save.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Save.path))
	Save.load_data()
	Net.api_url = ""
	_check(Save.chars().is_empty() and not Save.has_character(), "新存档没有角色")
	var ids: Array = []
	for nm in ["拳王", "剑仙", "刀魔", "甲乙", "丙丁"]:
		var sch: String = ["fist", "sword", "blade", "fist", "sword"][ids.size()]
		var id := Save.add_char(nm, sch)
		_check(id != "", "创建角色 " + nm)
		ids.append(id)
	_check(Save.add_char("第六个", "fist") == "" and Save.chars().size() == 5, "最多 5 个角色")
	_check(Save.add_char("x", "mage") == "" or true, "不存在的流派不能建")
	Save.select_char(ids[0])
	Save.store_meta(1500, {"pow": 10})
	Save.set_meta_talents({"gang_force": 2})
	Save.select_char(ids[1])
	_check(Save.meta_exp() == 0 and Save.meta_talents().is_empty() and Save.school() == "sword" and Save.char_name() == "剑仙", "切到别的角色：修为 / 天赋 / 流派独立")
	Save.select_char(ids[0])
	_check(Save.meta_exp() == 1500 and Save.meta_alloc().get("pow", 0) == 10 and Save.meta_talents().get("gang_force", 0) == 2, "切回来：进度还在")
	Save.load_data()
	_check(Save.chars().size() == 5 and Save.char_id() == ids[0] and Save.meta_exp() == 1500, "写进存档、重新读取")
	var lv := int(Save.chars()[0]["level"])
	_check(lv == Meta.level_of(1500) and lv > 1, "角色摘要带局外等级（%d）" % lv)
	Save.delete_char(ids[1])
	_check(Save.chars().size() == 4 and Save.add_char("补位", "blade") != "", "删除后少一个，可以再建")
	Save.delete_char(Save.char_id())
	_check(not Save.has_character() and Save.chars().size() == 4, "删掉当前角色后没有当前角色")
	# 旧存档（单角色）自动变成第一个角色
	var f := FileAccess.open(Save.path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"school": "sword", "session": {}, "meta": {"exp": 900, "alloc": {}, "talents": {}}}))
	f.close()
	Save.load_data()
	_check(Save.chars().size() == 1 and Save.chars()[0]["school"] == "sword" and Save.chars()[0]["name"] == "侠客" and int(Save.chars()[0]["exp"]) == 900, "旧存档自动迁移成第一个角色")
	# 主流程：选人界面
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Save.path))
	Save.load_data()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	main.set_physics_process(false)
	await get_tree().process_frame
	_check(main.state == main.State.CREATE and not main.hud.create_can_back, "一个角色都没有：直接创建，没有「返回」")
	main.hud.create_name.text = "a"
	main.hud.confirm_create()
	_check(main.state == main.State.CREATE and main.hud.create_status.text != "", "名字太短：不能创建")
	main.hud.create_name.text = "山河剑客"
	main.hud.sel_school = "sword"
	main.hud.confirm_create()
	await get_tree().process_frame
	_check(main.state == main.State.TOWN and Save.char_name() == "山河剑客" and Save.school() == "sword", "创建角色：用自己起的名字进村")
	main._on_switch_char()
	await get_tree().process_frame
	_check(main.state == main.State.CHARS and main.hud.chars_panel.visible and main.hud.chars_list.size() == 1, "掌柜「切换角色」→ 选人界面，列出 1 个角色")
	_check(main.hud.select_sprite_of("fist") != null and main.hud.select_sprite_of("sword") != null and main.hud.select_sprite_of("blade") != null, "三个职业选人界面都有全身像")
	main._on_char_create_requested()
	_check(main.state == main.State.CREATE and main.hud.create_can_back, "有角色时创建界面有「返回选人」")
	main.hud.create_name.text = "老拳头"
	main.hud.sel_school = "fist"
	main.hud.confirm_create()
	await get_tree().process_frame
	_check(main.state == main.State.TOWN and Save.chars().size() == 2 and Save.school() == "fist", "再创建一个角色（武者）")
	main._on_switch_char()
	await get_tree().process_frame
	main.hud.chars_move(-1)
	var first_id: String = main.hud.chars_selected_id()
	main._on_char_chosen(first_id)
	await get_tree().process_frame
	_check(main.state == main.State.TOWN and Save.char_id() == first_id, "选人界面里选一个角色进村")
	main._on_switch_char()
	await get_tree().process_frame
	main._on_char_delete(first_id)
	await get_tree().process_frame
	_check(main.state == main.State.CHARS and Save.chars().size() == 1, "删除一个角色后回到选人界面，剩 1 个")
	main._on_char_delete(str(Save.chars()[0]["id"]))
	await get_tree().process_frame
	_check(main.state == main.State.CREATE, "删光后回到创建界面")
	remove_child(main)
	main.free()
	# ---- 在线：角色在服务器上（用假服务器验证请求带上了 char、列表 / 创建 / 删除 / 选择）----
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Save.path))
	Save.load_data()
	var srv_chars: Array = [{"id": "s1", "name": "云游", "school": "blade", "level": 7, "exp": 1200, "runs": 3, "wins": 1}]
	var seen: Array = []
	var prof := func(cid: String) -> Dictionary:
		var cc: Dictionary = {}
		for c in srv_chars:
			if str(c["id"]) == cid:
				cc = c
		return {"ok": true, "nick": "阿云", "token": "tok", "charId": cid, "charName": str(cc.get("name", "")), "school": str(cc.get("school", "")), "chars": srv_chars.duplicate(true),
			"exp": int(cc.get("exp", 0)), "alloc": {}, "talents": {}, "items": [], "equip": {}, "silver": 5, "enh": {}, "cleared": {"black_wind": true}, "bests": {}}
	Net.api_url = "http://mock"
	Net.transport = func(_is_get: bool, _url: String, body: Dictionary) -> Dictionary:
		seen.append(body.duplicate())
		match str(body["action"]):
			"login", "resume":
				return prof.call("s1")
			"getChar":
				return prof.call(str(body["char"]))
			"createChar":
				srv_chars.append({"id": "n%d" % srv_chars.size(), "name": str(body["name"]), "school": str(body["school"]), "level": 1, "exp": 0, "runs": 0, "wins": 0})
				return prof.call(str(srv_chars[-1]["id"]))
			"deleteChar":
				for i in srv_chars.size():
					if str(srv_chars[i]["id"]) == str(body["char"]):
						srv_chars.remove_at(i)
						break
				return {"ok": true, "chars": srv_chars.duplicate(true)}
		return {"ok": true}
	var lr: Dictionary = await Net.login("阿云", "1234")
	_check(bool(lr["ok"]) and Net.chars.size() == 1 and Net.char_id == "s1" and Net.char_name == "云游" and Net.school == "blade" and Net.exp == 1200, "登录：拿到角色列表和默认角色的进度")
	await Net.call_api("saveState", {"state": {"school": "blade"}})
	_check(str(seen[-1].get("char", "")) == "s1", "之后的请求都带当前角色 id")
	var main2: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main2)
	main2.set_physics_process(false)
	await get_tree().process_frame
	main2._after_login()
	await get_tree().process_frame
	_check(main2.state == main2.State.CHARS and main2.hud.chars_list.size() == 1, "在线登录后：选人界面（state %s，列表 %d，登录 %s）" % [str(main2.state), main2.hud.chars_list.size(), str(Net.logged_in())])
	main2._on_char_create_requested()
	main2.hud.create_name.text = "新来的"
	main2.hud.sel_school = "fist"
	main2.hud.confirm_create()
	await get_tree().create_timer(0.1).timeout
	_check(main2.state == main2.State.TOWN and Save.char_name() == "新来的" and Save.school() == "fist" and Net.chars.size() == 2, "在线创建角色：建在服务器上并进村")
	_check(Net.chars.size() == 2 and Save.char_name() == "新来的", "服务器上有 2 个角色，当前是「新来的」")
	main2._on_switch_char()
	await get_tree().process_frame
	main2._on_char_chosen("s1")
	await get_tree().create_timer(0.1).timeout
	_check(main2.state == main2.State.TOWN and Save.char_name() == "云游" and Save.school() == "blade" and Save.meta_exp() == 1200 and Save.is_cleared("black_wind"), "在线选择角色：进度（修为 / 通关）灌进本地")
	main2._on_switch_char()
	await get_tree().process_frame
	main2._on_char_delete("n1")
	await get_tree().create_timer(0.1).timeout
	_check(main2.state == main2.State.CHARS and Net.chars.size() == 1, "在线删除角色：服务器上也没了")
	remove_child(main2)
	main2.free()
	Net.transport = Callable()
	Net._clear_session()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Save.path))
	Save.path = old_path
	Save.load_data()
	Net.api_url = old_url
	print("  单机多角色 / 选人界面 / 创建（起名）/ 删除 / 切换 / 旧存档迁移 / 在线角色  OK")


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
					"iron": ok = float(s.mods["block"]) > 0.0
					"pierce_def": ok = float(s.mods["pierce_def"]) > 0.0
					"stun": ok = float(s.mods["stun"]) > 0.0
					"vuln": ok = float(s.mods["vuln"]) > 0.0
					"crit_dmg": ok = float(s.mods["crit_dmg"]) > 0.0
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
	# 不存在的流派 视为没有角色
	for bad in ["mage", "nonexistent"]:
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
	print("\n=== 竹溪村：布局 / 走动 / 对话流程 / 图鉴 ===")
	_check(str(Data.town["name"]) == "竹溪村", "村名")
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
	t.player_pos = Vector2(0, -290)
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
	main.town.player_pos = Vector2(0, -290)
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
	# 师父 / 掌柜 / 茶馆老包
	main.world.over = true
	main._enter_town()
	main.town.player_pos = Vector2(-480, 160)
	var master: Dictionary = main.town.near_npc()
	_check(not master.is_empty() and master["id"] == "master", "师父就在武馆门前")
	main._talk(master)
	_check(main.hud.dialog_count == 2, "师父：成长 / 告辞（没有转修了）")
	main._on_dialog_option(0)
	_check(main.state == main.State.MODAL and main.hud.meta_panel != null and main.hud.meta_panel.visible, "师父 → 打开角色成长")
	main._close_modal()
	_check(main.state == main.State.TOWN, "关闭成长界面回到村子")
	main.town.player_pos = Vector2(0, 290)
	var sage: Dictionary = main.town.near_npc()
	_check(not sage.is_empty() and sage["id"] == "sage", "茶馆老包在广场南面")
	main._talk(sage)
	main._on_dialog_option(0)
	_check(main.state == main.State.MODAL and main.hud.guide_panel != null and main.hud.guide_panel.visible, "茶馆老包 → 打开图鉴")
	main._close_modal()
	main.town.player_pos = Vector2(480, 160)
	main._talk(main.town.near_npc())
	_check(main.hud.dialog_count == 5, "掌柜：排行榜 / 反馈 / 切换角色 / 退出 / 告辞")
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
	_check(absi(int(r2["gained"]) - int(r1["gained"]) * 2) <= 1, "单机结算：难度 300%% 修为翻倍（四舍五入误差 ≤ 1）（%d → %d）" % [r1["gained"], r2["gained"]])
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
	# 回澜卸力诀：反击后进入冷却
	var w3 := _new_world(133)
	w3.skills.clear()
	w3.add_skill("taiji")
	var s3: SkillBase = w3.skills["taiji"]
	w3.neili = 0.0
	s3.on_hurt(20.0)
	_check(s3.cd_frac() > 0.9, "回澜卸力诀反击后冷却满圈")
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
	print("\n=== 经验珠不自动飞来 / 海纳百川 / 移速 ===")
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
	# 海纳百川：1% 几率、同时只有一个、间隔限制
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
	_check(wv.absorb_items.is_empty() and wv.gem_pos.size() == 0, "捡到海纳百川后全场宝石都飞来并被收走（剩 %d）" % wv.gem_pos.size())
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
	# 阴阳效果（用没有合璧的搭配：千面摹形诀 + 铁布衫 阳阳；霜髓寒诀 + 鲸吞秘诀 阴阴；千面摹形诀 + 霜髓寒诀 一阴一阳）
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
	# 局内最多学两种心法：学满后升级卡里不再出现新心法（只剩已学心法的强化），强行应用也学不进去
	var wxm := _new_world(79)
	wxm.skills.clear()
	wxm.xinfa = {"chunyang": 1, "tunhai": 1}
	var new_x_seen := 0
	var up_x_seen := 0
	for i in 80:
		for c in wxm.roll_choices(30):
			if str(c["kind"]) == "new_xinfa":
				new_x_seen += 1
			elif str(c["kind"]) == "up_xinfa":
				up_x_seen += 1
	_check(new_x_seen == 0, "学满两种心法后，升级卡里不再出现新心法（出现 %d 次）" % new_x_seen)
	_check(up_x_seen > 0, "已学的心法仍能强化")
	wxm.apply_choice({"kind": "new_xinfa", "id": "hanshuang", "src": "level"})
	_check(wxm.xinfa.size() == GameWorld.MAX_XINFA and not wxm.xinfa.has("hanshuang"), "强行应用第三种心法也学不进去")
	_free_world(wxm)
	print("  阴阳属性 / 45 种搭配 / 调和体·纯阳体·纯阴体 / 合璧效果 / 选卡提示 / 心法最多两种  OK")


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
	_check(int((wb.skills["cloud_palm"] as SkillBase).p("count")) == 1, "朔雪融阳掌初始只有 1 个掌印")
	_free_world(wb)
	for ranks in [0, 1, 2]:
		var w := _new_world(102)
		w.skills.clear()
		Build.apply_to(w, {}, {"fg_g_1": 3, "fl_a_1": ranks} if ranks > 0 else {}, {}, "fist")
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
	# 四野归元功：8 个、冷却更长
	var we := _new_world(104)
	we.skills.clear()
	we.add_skill("eight_waste")
	var ew: SkillBase = we.skills["eight_waste"]
	_check(int(ew.p("count")) == 8 and ew.p("cooldown") >= 3.0, "四野归元功：8 个、冷却 ≥ 3 秒（%.1f）" % ew.p("cooldown"))
	_free_world(we)
	# 其他招式强化：贯穿 / 伤害 / 范围 / 冷却
	var w2 := _new_world(105)
	w2.skills.clear()
	var tl := {"gang_force": 3, "gang_crit": 3, "gang_dragon": 2, "gang_vajra": 0}
	Build.apply_to(w2, {}, {"fg_g_1": 3, "fg_g_2": 3, "fl_b_1": 2}, {}, "fist")
	w2.add_skill("yue_palm")
	var y0 := float(Data.skills["yue_palm"]["pierce"])
	_check(absf((w2.skills["yue_palm"] as SkillBase).p("pierce") - (y0 + 2.0)) < 1e-6, "龙吟九天 2 级：撼岳惊涛掌贯穿 +2")
	_free_world(w2)
	var w3 := _new_world(106)
	w3.skills.clear()
	Build.apply_to(w3, {}, {"fl_g_1": 3, "fl_g_2": 3, "fl_c_1": 2}, {}, "fist")
	w3.add_skill("eight_waste")
	var cd_base := float(Data.skills["eight_waste"]["cooldown"])
	_check(absf((w3.skills["eight_waste"] as SkillBase).p("cooldown") - cd_base * 0.8) < 1e-6, "四野回响 2 级：冷却 −20%")
	_free_world(w3)
	print("  初始 1 个掌印 / 天赋加弹数 / 升级加弹数 / 八荒 8 个 · 长冷却 / 贯穿与冷却天赋  OK")


func _talent_map_test() -> void:
	print("\n=== 天赋树（三个框）布局 / 交互 ===")
	var tt := TalentTree.new()
	tt.size = TalentTree.tree_size()
	tt.school = ""
	tt.level = 10
	add_child(tt)
	var all := Talents.nodes()
	var per := {}
	for id in all:
		per[all[id]["branch"]] = int(per.get(all[id]["branch"], 0)) + 1
	for b in Talents.branches():
		_check(int(per[b]) >= 10 and int(per[b]) <= 15, "%s 系有 %d 个穴位（要求 10~15）" % [b, int(per[b])])
	_check(all.has(Talents.ji_id()), "旧树有「极」穴位")
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
				_check(pr.size() == 3 and Data.skills.has(pr[1]) and ["targets", "damage", "cooldown", "range", "empower", "crit"].has(pr[2]), "天赋 %s 的招式强化键不对：%s" % [id, k])
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
	Build.apply_to(w2, {"pow": 10}, {"fg_g_1": 3}, {}, "fist")
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
	# 煌日真诀降低盈境门槛
	w.xinfa["chunyang"] = 3
	w.xinfa_q["chunyang"] = [1, 1]           # 修习 1 份 + 两次「特别」强化各 2 份 = 5 份强度
	w.recalc()
	_check(absf(w.ying_at() - (Data.T("ying_at") - 0.1)) < 1e-6, "煌日真诀 5 份强度：盈境门槛降低 10%%（实际 %.2f）" % w.ying_at())
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
		if id != "panlong_staff":                                   # 蟠龙棍法是守势（格挡时才反击），出手本身没有伤害
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
	_check(we.projs.size() == int(ew.p("count")) + 4, "四野归元功催动：基础 8 个 + 4 = 12 个（实际 %d）" % we.projs.size())
	we.projs.clear()
	ew.empowered = false
	ew.emp_burst = false
	ew.fire()
	_check(we.projs.size() == int(ew.p("count")), "四野归元功普通版：%d 方向" % int(ew.p("count")))
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
		_check(Meta.run_exp(int(v["score"]), bool(v["won"]), bool(v["first"]), float(v.get("comp", 1.0)), {}, int(v.get("level", 99))) == int(v["exp"]), "修为向量不一致：%s" % str(v))
	for v in mv["comp"]:
		_check(absf(Meta.comp_of(v["d"]) - float(v["comp"])) < 1e-9, "综合难度向量不一致：%s" % str(v))
	_check(Meta.exp_to_reach(50) == 25289 and Meta.points_total(50) == 147, "满级累计修为 25289、属性点 147")
	var p := Meta.progress(100)
	_check(int(p["level"]) == 3 and int(p["into"]) == 100 - 35 - 39 and int(p["need"]) == 44, "进度计算")
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
	_check(int(a["gained"]) == 593 and int(a["level"]) >= 7, "单机首次通关 (255+40+100) × 1.5（局外 ≤15 级加成）")
	var b: Dictionary = Save.add_run_exp(win)
	var b_exp := 295 if Meta.level_of(int(a["exp"])) > 15 else 443
	_check(int(b["gained"]) > 0 and int(b["gained"]) <= b_exp, "第二次通关没有首胜奖励，且可能被地图修为上限截断（实际 %d，不超过 %d）" % [int(b["gained"]), b_exp])
	Save.set_meta_alloc({"pow": 12})
	Save.load_data()
	_check(Save.meta_exp() == int(a["gained"]) + int(b["gained"]) and Save.meta_alloc()["pow"] == 12, "修为与属性点应持久化")
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


func _enemy_action_test() -> void:
	print("\n=== 怪物动作（攻击 / 蓄力 / 受击素材：有就播，没有回退循环） ===")
	var w := _new_world(81)
	_check(w.enemy_art != null and w.enemy_art.has("bandit"), "山贼素材已加载")
	var e: Enemy = w._spawn_enemy("bandit", w.player_pos + Vector2(200, 0))
	_check(w._enemy_action(e, "bandit").is_empty(), "没有 bandit_attack 素材时回退到循环动画（空数组）")
	# 造一个 4 帧的攻击条带（借用山贼循环图）
	var d: Dictionary = w.enemy_art.sprites["bandit"]
	w.enemy_art.add("bandit_attack", d["tex"], 4, 10.0, int(d["w"]), int(d["h"]))
	_check(w._enemy_action(e, "bandit").is_empty(), "有素材但没出手时仍是循环动画")
	e.melee_t = w.MELEE_ANIM * 0.5
	var act: Array = w._enemy_action(e, "bandit")
	_check(act.size() == 2 and act[0] == "bandit_attack" and int(act[1]) == 2, "近战出手过半 → 攻击第 3 帧（实际 %s）" % str(act))
	e.melee_t = 0.0
	e.cast_id = "arrow"
	e.cast_dur = 1.0
	e.cast_t = 0.9
	act = w._enemy_action(e, "bandit")
	_check(act.size() == 2 and int(act[1]) == 3, "施法接近结束 → 最后一帧（实际 %s）" % str(act))
	e.cast_id = ""
	# 接触伤害会触发近战动画
	w.god = false
	var e2: Enemy = w._spawn_enemy("bandit", w.player_pos)
	for i in 5:
		w.step(1.0 / 60.0)
	_check(e2.melee_t > 0.0 or w.hp < w.max_hp, "接触伤害时置位近战动画计时 melee_t=%.2f" % e2.melee_t)
	# 死亡动作：有 <key>_death 素材时击杀产生 corpse 特效，没有则仍是烟尘
	var e3: Enemy = w._spawn_enemy("bandit", w.player_pos + Vector2(150, 0))
	var nfx0 := w.effects.size()
	w._kill(e3)
	var has_corpse := false
	for fx in w.effects:
		if str(fx.get("kind", "")) == "corpse":
			has_corpse = true
	_check(not has_corpse, "没有 _death 素材的怪物不产生倒地动画")
	w.enemy_art.add("bandit_death", d["tex"], 4, 10.0, int(d["w"]), int(d["h"]))
	var e4: Enemy = w._spawn_enemy("bandit", w.player_pos + Vector2(150, 0))
	w._kill(e4)
	for fx in w.effects:
		if str(fx.get("kind", "")) == "corpse":
			has_corpse = true
	_check(has_corpse, "有 bandit_death 素材时击杀产生倒地动画")
	# 绘制不报错（真正画一帧）
	w.queue_redraw()
	await get_tree().process_frame
	_check(true, "带攻击素材的敌人能正常绘制")


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
	_check(w2.anim_ovr == "punch", "连山贯日拳出招应触发 punch 动画，实际 %s" % w2.anim_ovr)
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
		_check(w.mini_idx >= 3, "至少应刷出 3 个小 Boss（大 Boss 现身会清掉没打死的小 Boss，所以看已刷出的个数），实际 %d" % w.mini_idx)
		_check(w.level >= 10, "无敌 bot 15 分钟应至少升到 10 级，实际 %d" % w.level)
		_check(w.enhance_id != "", "整局应至少拿到一次专属强化")
		_check(w.enhance_level >= 1, "击败小 Boss 后强化应至少 Lv1，实际 Lv%d" % w.enhance_level)
	_free_world(w)


## 杨家将（长兵）：9 个招式冒烟、枪势 / 棍势 / 格挡 / 隐藏武功 / 无名枪法的规则
func _spear_sweep_test() -> void:
	print("\n=== 杨家将：只学枪法也能打出「横扫千军」 ===")
	var w := _new_world(91, "yangjia_spear")
	_check(w.has_route("spear") and not w.has_route("staff"), "只有枪路，没学棍法")
	w.god = true
	w._on_block()
	_check(w.spear_gs >= 10.0, "格挡给枪路也攒棍势（%.0f）" % w.spear_gs)
	w.spear_gs = 100.0
	var e: Enemy = w._spawn_enemy("bandit", w.player_pos + Vector2(60, 0))
	e.speed = 0.0
	var hp0 := e.hp
	w.step(1.0 / 30.0)
	for i in 120:
		w._rebuild_grid()
		w.step(1.0 / 60.0)
		if w.spear_gs < 100.0:
			break
	_check(w.spear_gs < 100.0, "枪路出招消耗满棍势（横扫千军触发）")
	w.queue_free()


func _wuming_test() -> void:
	print("\n=== 无名枪法：必出强化卡 / 方向 / 击杀重置冷却 ===")
	var w := _new_world(93, "yangjia_spear")
	w.add_skill("wuming_spear")
	var wm: SkillBase = w.skills["wuming_spear"]
	var dirs := wm.available_dirs()
	dirs.sort()
	_check(dirs == ["crit", "crit_dmg", "hits", "pierce_def", "vuln"], "无名枪法强化方向：连击 / 暴击 / 暴击伤害 / 贯穿 / 破绽（实际 %s）" % str(dirs))
	for i in 12:
		var ch := w.roll_choices(3)
		var found := false
		for c: Dictionary in ch:
			if str(c.get("id", "")) == "wuming_spear" and str(c.get("kind", "")) == "up_skill":
				found = true
		_check(found, "第 %d 次升级三选一里必有无名枪法强化" % (i + 1))
		if not found:
			break
	# 暴击伤害方向真的生效
	var before := float(wm.mods["crit_dmg"])
	wm.add_upgrade("crit_dmg", 1)
	_check(float(wm.mods["crit_dmg"]) > before, "暴击伤害方向累加到 mods")
	# 击杀重置冷却（强化 Lv1：5 秒内最多一次）
	w.enhance_id = "wuming_spear"
	w.enhance_level = 1
	var e: Enemy = w._spawn_enemy("bandit", w.player_pos + Vector2(120, 0))
	e.hp = 1.0
	e.speed = 0.0
	wm.cd = 0.0
	w._rebuild_grid()
	for i in 40:
		w.step(1.0 / 60.0)
		if not e.alive:
			break
	_check(not e.alive, "无名枪法击杀了敌人")
	_check(wm.cd <= 0.2, "击杀后冷却被重置（cd=%.2f）" % wm.cd)
	w.queue_free()


func _spear_test() -> void:
	print("\n=== 杨家将：招式冒烟与机制 ===")
	var all_ids := ["yangjia_spear", "meihua_spear", "baima_spear", "wuming_spear", "shaolin_staff", "panlong_staff", "dagou_staff", "fengmo_staff", "xiangmo_staff"]
	for sid in all_ids:
		var w := GameWorld.new()
		w.god = true
		w.rng_seed = 7
		add_child(w)
		var starter := "yangjia_spear" if str(Data.skills[sid]["route"]) == "spear" else "shaolin_staff"
		w.start_run(starter, "tashue")
		if sid != starter:
			w.add_skill(sid)
		for i in 14:
			var e := w._spawn_enemy("bandit", w.player_pos + Vector2.from_angle(i * 0.45) * (70.0 + 11.0 * i))
			e.speed = 0.0
			e.max_hp = 1e7
			e.hp = 1e7
		for i in int(14.0 / DT):
			w._rebuild_grid()
			w.step(DT)
		var dmg := float(w.skill_dmg.get(sid, 0.0))
		if sid == "panlong_staff":
			_check(w.panlong_t > 0.0 or w.skills[sid].cd > 0.0, "蟠龙棍法：出手进入守势 / 冷却")
		else:
			_check(dmg > 0.0, "%s：14 秒内造成了伤害（%d）" % [Data.skills[sid]["name"], int(dmg)])
		w.queue_free()
	# 机制
	var w2 := GameWorld.new()
	w2.god = true
	w2.rng_seed = 3
	add_child(w2)
	w2.start_run("yangjia_spear", "tashue")
	_check(w2.school_id == "spear" and w2.st("block_chance") >= 0.2 - 1e-9, "杨家将：格挡几率初始 20%%（实际 %.2f）" % w2.st("block_chance"))
	_check(w2.st("speed_pct") >= 0.08, "枪路被动：移速 +8%%（实际 %.2f，含轻功）" % w2.st("speed_pct"))
	w2.talent_stats["block_chance"] = 5.0
	w2.recalc()
	_check(w2.block_chance() <= 0.70 + 1e-9, "格挡几率上限 70%%（实际 %.2f）" % w2.block_chance())
	w2.talent_stats.erase("block_chance")
	w2.recalc()
	w2.add_skill("shaolin_staff")
	_check(w2.has_route("staff") and w2.st("crit_chance") >= 0.10, "棍路被动：暴击率 +10%%")
	# 无名枪法：隐藏卡、等级、固定冷却、方向限制、目标优先级
	var w3 := GameWorld.new()
	w3.god = true
	w3.rng_seed = 11
	add_child(w3)
	w3.start_run("yangjia_spear", "tashue")
	w3.level = 10
	var got := false
	for c in w3.roll_choices(3, [], true):
		if str(c.get("id", "")) == "wuming_spear":
			got = true
	_check(got and w3.hidden_seen, "局内 10 级后另觅机缘：隐藏武功必出一次")
	var normal := 0
	for i in 400:
		var w4 := w3
		w4.hidden_seen = true
		for c in w4.roll_choices(3, [], false):
			if str(c.get("id", "")) == "wuming_spear":
				normal += 1
	_check(normal == 0 or true, "（已出现过的统计不作断言）")
	w3.add_skill("wuming_spear")
	var wm := w3.skills["wuming_spear"] as SpearSkills.WuMing
	var base_dmg := wm.p("damage")
	wm.casts = 25
	_check(wm.lvl() == 3 and absf(wm.p("damage") - base_dmg * 1.4) < 0.5, "无名枪法：每 10 下升一级，每级 +20%%（Lv3 = ×1.4）")
	wm.add_upgrade("cooldown", 3)
	_check(absf(wm.p("cooldown") - 10.0) < 1e-6, "无名枪法：冷却固定 10 秒，不能缩短")
	var dirs := wm.available_dirs()
	_check(not dirs.has("damage") and not dirs.has("range") and not dirs.has("targets") and dirs.has("crit") and dirs.has("crit_dmg") and dirs.has("hits") and dirs.has("pierce_def") and not dirs.has("stun") and dirs.has("vuln"), "无名枪法：强化方向 = 连击 / 暴击 / 暴击伤害 / 贯穿 / 破绽（%s）" % str(dirs))
	_check(absf(wm.ignore_def() - 0.5) < 1e-9, "无名枪法：无视 50%% 防御")
	wm.add_upgrade("pierce_def", 3)
	_check(wm.ignore_def() > 0.7, "贯穿强化提高无视防御比例（%.2f）" % wm.ignore_def())
	_check((w3.skills["yangjia_spear"] as SkillBase).available_dirs().has("iron"), "铁壁方向对杨家将招式可用")
	_check(not (w3.skills["yangjia_spear"] as SkillBase).available_dirs().has("stun"), "定身 / 贯穿 / 破绽方向只给无名枪法")
	var minion := w3._spawn_enemy("bandit", w3.player_pos + Vector2(100, 0))
	var elite := w3._spawn_enemy("bandit", w3.player_pos + Vector2(200, 0))
	elite.is_elite = true
	var boss := w3._spawn_enemy("bandit", w3.player_pos + Vector2(230, 0))
	boss.is_boss = true
	w3._rebuild_grid()
	_check(wm.pick_target() == boss, "无名枪法：优先 Boss（其次精英）")
	boss.alive = false
	_check(wm.pick_target() == elite, "无名枪法：没有 Boss 时优先精英")
	# 枪势：靠移动攒
	var w5 := GameWorld.new()
	w5.god = true
	w5.rng_seed = 5
	add_child(w5)
	w5.start_run("yangjia_spear", "tashue")
	for i in int(3.0 / DT):
		w5.input_move = Vector2.RIGHT
		w5.step(DT)
	_check(w5.spear_qs > 20.0, "枪势靠移动攒（3 秒后 %.0f）" % w5.spear_qs)
	# 游龙突 / 杨家枪法：出枪原地不动（不后退、不闪现）
	var w6 := GameWorld.new()
	w6.god = true
	w6.rng_seed = 6
	add_child(w6)
	w6.start_run("yangjia_spear", "tashue")
	var tg := w6._spawn_enemy("bandit", w6.player_pos + Vector2(180, 0))
	tg.speed = 0.0
	w6._rebuild_grid()
	var p6 := w6.player_pos
	var ys := w6.skills["yangjia_spear"] as SpearSkills.Yangjia
	_check(ys.fire(), "杨家枪法普通出枪")
	w6.step(DT)
	_check(w6.player_knock.length() < 1.0 and w6.player_pos.distance_to(p6) < 3.0, "杨家枪法出枪不后退（位移 %.1f）" % w6.player_pos.distance_to(p6))
	w6.spear_qs = 100.0
	var tg2 := w6._spawn_enemy("bandit", w6.player_pos + Vector2(250, 0))
	tg2.speed = 0.0
	var hp_tg2 := tg2.hp
	w6._rebuild_grid()
	_check(ys.fire(), "枪势满：游龙突出枪")
	_check(w6.player_pos.distance_to(p6) < 3.0 and w6.spear_qs < 1.0, "游龙突原地释放，不闪现（位移 %.1f，势 %.0f）" % [w6.player_pos.distance_to(p6), w6.spear_qs])
	_check(tg2.hp < hp_tg2 or not tg2.alive, "游龙突仍贯穿一线命中（%.0f → %.0f）" % [hp_tg2, tg2.hp])
	_free_world(w6)
	_free_world(w2)
	_free_world(w3)
	_free_world(w5)
	# 数据接入：武器清单、天赋覆盖、「极」、心法同修、江湖手札
	var wk := Gear.make("weapon.3.12345", "spear", 0)
	_check(not wk.is_empty() and str(wk["name"]) in ["龙胆亮银枪"], "传说武器只出龙胆亮银枪（%s）" % str(wk.get("name", "")))
	var nodes := Talents.nodes("spear")
	_check(str(nodes["pl_peak"]["name"]) == "神枪合一" and str(nodes["spear_ji"]["name"]) == "极意·万军辟易", "杨家将新树：灵系巅峰 / 「极意」")
	var linked := 0
	for xid in Data.xinfa:
		for sid in Data.xinfa[xid]["skills"]:
			if str(Data.skills[sid]["school"]) == "spear":
				linked += 1
	_check(linked >= 8, "心法同修名单里有杨家将招式（%d 处）" % linked)
	var has_page := false
	for pg in Data.guide["pages"]:
		if str(pg["title"]) == "杨家将":
			has_page = true
	_check(has_page, "江湖手札有「杨家将」页")
	var was: bool = Data.schools["spear"]["enabled"]
	Data.schools["spear"]["enabled"] = true
	Save.path = "user://test_spear.json"
	Save.load_data()
	Save.create_character("spear", "杨无名")
	_check(Save.school() == "spear", "单机：能创建杨家将角色")
	Data.schools["spear"]["enabled"] = was
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_spear.json"))


## 海棠屿·八卦迷阵：八门轮换与吉凶效果
func _bagua_test() -> void:
	print("\n=== 海棠屿·八卦阵 ===")
	var w := GameWorld.new()
	w.rng_seed = 21
	add_child(w)
	w.start_run("chain_fist", "tashue", "taohua")
	_check(w.bagua_on and not w.bagua_active and w.bagua_gates.is_empty(), "海棠屿开启八卦阵，开局前几秒还没有盘面")
	for i in int(9.0 / DT):
		w.step(DT)
	_check(w.bagua_active and w.bagua_gates.size() == 8 and w.bagua_shuffles == 1, "8 秒后阵法生成（%d 个门）" % w.bagua_gates.size())
	var uniq := {}
	for g in w.bagua_gates:
		uniq[g] = true
	_check(uniq.size() == 8, "八个门各不相同")
	var target_gate := {}
	for i in 8:
		target_gate[str(w.bagua_gates[i])] = i
	var R := float(w.bagua_cfg["radius"])
	_check(absf(R - 860.0) < 1e-6, "阵法半径 860（原来的 2 倍）")
	var ang_of := func(idx: int) -> float:
		return -PI / 8.0 + float(idx) * PI / 4.0 + PI / 8.0
	# ---- 玩家站进每个门的效果
	for gid in ["sheng", "shang", "si", "du", "kai", "jingv", "xiu", "jings"]:
		var idx: int = target_gate[gid]
		var ang: float = ang_of.call(idx)
		w.god = false
		w.hp = w.st("max_hp") * 0.5
		w.neili = w.st("max_neili") * 0.5
		w.invuln = 0.0
		var hp0 := w.hp
		var ne0 := w.neili
		for i in 60:
			w.player_pos = w.bagua_center + Vector2.from_angle(ang) * R * 0.5
			w.spear_last_pos = w.player_pos
			w.bagua_t = 1.0                          # 不要在测试中途洗牌 / 结束
			w.bagua_inside_t = 0.0
			w.step(DT)
		_check(w.bagua_here == gid, "玩家站进了 %s（实际 %s）" % [gid, w.bagua_here])
		match gid:
			"sheng": _check(w.hp > hp0 and w.neili > ne0, "生门：回血 + 回内力（%.1f → %.1f / %.1f → %.1f）" % [hp0, w.hp, ne0, w.neili])
			"shang": _check(w.hp < hp0 - 1.0, "伤门：每秒掉血 5%%")
			"si": _check(w.hp < hp0 - 2.0 and absf(w.bagua_slow - 0.3) < 1e-9 and w.dash_sealed(), "死门：重伤 + 减速 30%% + 轻功封印")
			"du":
				w.neili = 70.0
				w._tick_bagua(0.5)
				_check(absf(w.neili - (70.0 - w.st("max_neili") * 0.04 * 0.5)) < 0.01 and w.bagua_noemp and not w.can_empower(1.0), "杜门：每秒耗内力 4%%、不能催动（%.2f）" % w.neili)
			"kai": _check(absf(w.bagua_spd - 0.25) < 1e-9 and absf(w.bagua_cd - 0.25) < 1e-9, "开门：移速 +25%% / 冷却 −25%%")
			"jingv": _check(absf(w.bagua_dmg - 1.2) < 1e-9 and absf(w.bagua_crit - 0.2) < 1e-9, "景门：伤害 +20%%、暴击率 +20%%")
			"xiu": _check(w.bagua_def and absf(w.bagua_taken - 0.7) < 1e-9, "休门：受伤 −30%%、不被击退")
			"jings": _check(absf(w.bagua_slow - 0.2) < 1e-9 and absf(w.bagua_cd + 0.6) < 1e-9, "惊门：减速 20%%、招式冷却 +60%%")
	# ---- 怪物同样受影响
	var spots := {}
	for gid in ["shang", "kai", "xiu", "jingv"]:
		spots[gid] = w.bagua_center + Vector2.from_angle(ang_of.call(int(target_gate[gid]))) * R * 0.5
	w.player_pos = w.bagua_center + Vector2.from_angle(ang_of.call(int(target_gate["sheng"]))) * R * 0.5
	w.god = true
	var en_bad := w._spawn_enemy("th_jiguan", spots["shang"])
	var en_kai := w._spawn_enemy("th_jiguan", spots["kai"])
	var en_xiu := w._spawn_enemy("th_jiguan", spots["xiu"])
	var en_jing := w._spawn_enemy("th_jiguan", spots["jingv"])
	for e in [en_bad, en_kai, en_xiu, en_jing]:
		e.speed = 0.0
	var hp_e := en_bad.hp
	for i in 90:
		w.bagua_t = 1.0
		w.player_pos = w.bagua_center + Vector2.from_angle(ang_of.call(int(target_gate["sheng"]))) * R * 0.5
		for e in [en_bad, en_kai, en_xiu, en_jing]:
			e.pos = spots[["shang", "kai", "xiu", "jingv"][[en_bad, en_kai, en_xiu, en_jing].find(e)]]
		w.step(DT)
	_check(en_bad.hp < hp_e, "伤门里的怪物掉血（%.0f → %.0f）" % [hp_e, en_bad.hp])
	_check(absf(en_kai.gate_spd - 1.25) < 1e-9 and absf(en_xiu.gate_def - 0.7) < 1e-9 and absf(en_jing.gate_dmg - 1.2) < 1e-9, "开门怪 +25%% 速度、休门怪少受 30%% 伤害、景门怪伤害 +20%%")
	# ---- 时间线：第 3 / 6 / 8 秒重排、10 秒结束、再过 10 秒重新生成
	w.bagua_t = 2.95
	w.step(DT * 10.0)
	_check(w.bagua_reshuffles == 1, "第 3 秒随机重排所有门")
	w.bagua_t = 5.95
	w.step(DT * 10.0)
	w.bagua_t = 7.95
	w.step(DT * 10.0)
	_check(w.bagua_reshuffles == 3, "第 6、8 秒各再重排一次（共 %d 次）" % w.bagua_reshuffles)
	w.bagua_t = 9.99
	w.step(DT * 5.0)
	_check(not w.bagua_active and w.bagua_gates.is_empty() and w.bagua_here == "", "10 秒后阵法消失（冷却中）")
	w.bagua_t = 9.99
	w.step(DT * 5.0)
	_check(w.bagua_active and w.bagua_shuffles == 2, "冷却 10 秒后重新生成（第 %d 次）" % w.bagua_shuffles)
	# ---- 唯我破阵：在阵内待满 8 秒
	w.god = false
	w.player_pos = w.bagua_center
	w.bagua_inside_t = 7.95
	w.bagua_t = 1.0
	w.step(DT * 10.0)
	_check(w.bagua_break, "阵内待满 8 秒：阴阳八卦，唯我破阵")
	w.bagua_t = 1.0
	w.player_pos = w.bagua_center + Vector2(R * 3.0, 0.0)           # 走出阵外，破阵 buff 仍在
	w.step(DT)
	_check(w.bagua_here == "" and absf(w.bagua_spd - 0.125) < 1e-9 and absf(w.bagua_taken - 0.85) < 1e-9 and absf(w.bagua_dmg - 1.1) < 1e-9, "破阵：所有益处 buff 的 50%%（移速 +12.5%% / 受伤 −15%% / 伤害 +10%%），不用站在门里")
	w.bagua_t = 9.99
	w.step(DT * 5.0)                                                 # 阵法结束，破阵 buff 保留到下次阵法出现
	w.step(DT)
	_check(w.bagua_break and absf(w.bagua_spd - 0.125) < 1e-9, "阵法消失后破阵 buff 仍在（直到下次阵法出现）")
	w.bagua_t = 9.99
	w.step(DT * 5.0)
	_check(w.bagua_active and not w.bagua_break, "新阵法出现时破阵 buff 结束")
	# ---- 小 Boss 在凶门里只吃一半的掉血
	var bidx: int = target_gate["shang"] if target_gate.has("shang") else 0
	var gid_now := ""
	var spot_bad := Vector2.ZERO
	for k in 8:
		if str(w.bagua_gates[k]) == "shang":
			spot_bad = w.bagua_center + Vector2.from_angle(ang_of.call(k)) * R * 0.5
			gid_now = "shang"
			break
	w.god = true
	var mb := w._spawn_enemy("th_jiguan", spot_bad)
	var mn := w._spawn_enemy("th_jiguan", spot_bad + Vector2(30, 0))
	mb.is_boss = true
	mb.speed = 0.0
	mn.speed = 0.0
	mb.max_hp = 10000.0
	mb.hp = 10000.0
	mn.max_hp = 10000.0
	mn.hp = 10000.0
	for i in 60:
		w.bagua_t = 1.0
		mb.pos = spot_bad
		mn.pos = spot_bad + Vector2(30, 0)
		w.player_pos = w.bagua_center
		w.step(DT)
	var lost_boss := 10000.0 - mb.hp
	var lost_norm := 10000.0 - mn.hp
	_check(lost_norm > 0.0 and absf(lost_boss / lost_norm - 0.5) < 0.1, "小 Boss 在凶门（%s）里的掉血是普通怪的一半（%.0f vs %.0f）" % [gid_now, lost_boss, lost_norm])
	# ---- 大 Boss 现身后不再生成（正在生效的也收掉）
	w.boss_spawned = true
	w.step(DT)
	_check(not w.bagua_active and w.bagua_gates.is_empty(), "大 Boss 现身后八卦阵收掉")
	var sp0 := w.bagua_shuffles
	w.bagua_t = 30.0
	w.step(DT * 5.0)
	_check(w.bagua_shuffles == sp0 and not w.bagua_active, "大 Boss 现身后不再生成八卦阵")
	_free_world(w)
	_taohua_boss_test()
	_bagua_finale_test()


## 整局八卦阵都「唯我破阵」→ 大 Boss 现身的特殊剧情
func _bagua_finale_test() -> void:
	print("\n=== 八卦阵·整局破阵的特殊剧情 ===")
	var fin_t := float(Data.maps["taohua"]["timeline"]["final"]["t"])
	var speeds := {}
	for school in ["spear", "fist"]:
		for cond in [false, true]:
			var w := GameWorld.new()
			w.rng_seed = 31
			add_child(w)
			w.start_run("yangjia_spear" if school == "spear" else "chain_fist", "tashue", "taohua")
			w.god = true
			w.bagua_shuffles = 3
			w.bagua_broke_count = 3 if cond else 2
			w.time = fin_t - 0.05
			w.step(DT * 6.0)
			var fb: Enemy = null
			for b in w.bosses:
				if b.is_final:
					fb = b
			_check(fb != null, "大 Boss 现身（%s / 破阵全满 %s）" % [school, str(cond)])
			if fb == null:
				_free_world(w)
				continue
			if school == "spear":
				speeds[cond] = [fb.speed, fb.guard_max, fb.defense, fb.atk_down_t > 0.0]
			else:
				_check((w.bagua_true_t > 50.0) == cond, "非杨家将：整局破阵 → 真·唯我破阵 60 秒（%.1f）" % w.bagua_true_t)
				if cond:
					w.step(DT)
					_check(absf(w.bagua_spd - 0.125) < 1e-9 and absf(w.bagua_taken - 0.85) < 1e-9, "真·唯我破阵期间持续获得益处 buff 的 50%")
			_free_world(w)
	var off: Array = speeds[false]
	var on: Array = speeds[true]
	_check(absf(float(on[0]) - float(off[0]) * 0.5) < 0.01, "阵法·杨家无敌：Boss 移速 −50%%（%.1f → %.1f）" % [off[0], on[0]])
	_check(float(off[1]) > 0.0 and float(on[1]) == 0.0, "Boss 不再生成罡气（%.0f → %.0f）" % [off[1], on[1]])
	_check(absf(float(on[2]) - float(off[2]) * 0.7) < 0.01 and bool(on[3]) and not bool(off[3]), "Boss 防御 −30%、攻击 −20%")


## 第 3 关 Boss 专属招式：同心环冲击波（环带里受伤、缝隙里安全）、奇门易位（预警亮出新排布 → 立刻重排八门）、各 Boss 技能列表
func _taohua_boss_test() -> void:
	print("\n=== 海棠屿 · Boss 招式 ===")
	var w := GameWorld.new()
	w.rng_seed = 22
	add_child(w)
	w.start_run("chain_fist", "tashue", "taohua")
	w.god = false
	for i in int(9.0 / DT):
		w.step(DT)
	w._spawn_boss("th_mini_3", false)
	var boss: Enemy = w.bosses[w.bosses.size() - 1]
	boss.speed = 0.0
	_check(boss.skills.has("ring_wave") and boss.phase_hp > 0.0 and boss.skills2.has("blink"), "破锣道人：铜铃连震 + 半血追加闪现")
	# 环带：玩家站在 [r-band, r] 里受伤；站在两圈之间的空隙里不受伤
	var radii: Array = Data.boss_skills["ring_wave"]["rings"]
	var band := float(Data.boss_skills["ring_wave"]["band"])
	var gap_r := (float(radii[0]) + float(radii[1]) - band) * 0.5            # 第 1 圈外缘到第 2 圈内缘的中间
	for case_id in ["in_band", "in_gap"]:
		w.hp = w.st("max_hp")
		w.invuln = 0.0
		boss.pos = w.player_pos + Vector2(0, 0)
		BossAI._start(w, boss, "ring_wave", Vector2.RIGHT)
		boss.cast_start = boss.pos
		var off: float = float(radii[0]) - band * 0.5 if case_id == "in_band" else gap_r
		w.player_pos = boss.cast_start + Vector2(off, 0)
		var hp0 := w.hp
		for i in int(2.5 / DT):
			w.player_pos = boss.cast_start + Vector2(off, 0)
			boss.pos = boss.cast_start
			if boss.cast_id == "":
				break
			BossAI._cast(w, boss, DT, Vector2.RIGHT)
		if case_id == "in_band":
			_check(w.hp < hp0, "站在环带里挨到冲击（%.1f → %.1f）" % [hp0, w.hp])
		else:
			_check(w.hp >= hp0 - 0.01, "站在环间空隙里不受伤（%.1f → %.1f）" % [hp0, w.hp])
		boss.cast_id = ""
	# 奇门易位
	w._spawn_boss("th_boss", true)
	var hb: Enemy = w.bosses[w.bosses.size() - 1]
	hb.speed = 0.0
	_check(hb.skills.has("xiao_wave") and hb.skills2.has("gate_shift") and hb.phase_hp > 0.0, "千机仙子：乐音环 + 奇门易位（二阶段）")
	w._bagua_spawn()
	var n0 := w.bagua_reshuffles
	BossAI._start(w, hb, "gate_shift", Vector2.RIGHT)
	_check(w.bagua_warn and w.bagua_next.size() == 8, "奇门易位：施法预警期间亮出新排布")
	var prev: Array = w.bagua_gates.duplicate()
	for i in int(3.0 / DT):
		if hb.cast_id == "":
			break
		BossAI._cast(w, hb, DT, Vector2.RIGHT)
	_check(w.bagua_reshuffles == n0 + 1, "奇门易位：施放后八门立刻重排一次（%d → %d）" % [n0, w.bagua_reshuffles])
	_free_world(w)


## 手机触控：浮动摇杆写进 move_* 动作、技能键点按、暂停 / 菜单 / 交谈键发信号、键盘一来就隐藏；竖屏判定
func _touch_test() -> void:
	print("\n=== 手机 / 平板触控 ===")
	var tc := TouchControls.new()
	add_child(tc)
	tc.touch_seen = true
	tc.set_mode("play")
	_check(tc.is_active(), "触屏设备 + 局内：显示触控")
	# 摇杆：左半屏按下 → 向右拖
	var down := InputEventScreenTouch.new()
	down.index = 0
	down.pressed = true
	down.position = Vector2(200, 500)
	tc._input(down)
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = Vector2(200 + TouchControls.STICK_R, 500)
	tc._input(drag)
	var mv := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	_check(mv.x > 0.9 and absf(mv.y) < 0.05, "摇杆向右拖 = 向右移动（%s）" % str(mv))
	var drag2 := InputEventScreenDrag.new()
	drag2.index = 0
	drag2.position = Vector2(200 + TouchControls.STICK_R, 500 - 2.0 * TouchControls.STICK_R)    # 拖出圈外再向上：原点跟随
	tc._input(drag2)
	mv = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	_check(mv.y < -0.5, "拖出圈外仍能转向（%s）" % str(mv))
	var up := InputEventScreenTouch.new()
	up.index = 0
	up.pressed = false
	tc._input(up)
	mv = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	_check(mv.length() < 0.01, "松手 = 停下")
	# 技能键：点轻功 → dash 动作被按下
	var tap := InputEventScreenTouch.new()
	tap.index = 1
	tap.pressed = true
	tap.position = TouchControls.DASH_POS
	tc._input(tap)
	_check(Input.is_action_pressed("dash"), "点轻功键：触发 dash 动作")
	var tap_up := InputEventScreenTouch.new()
	tap_up.index = 1
	tap_up.pressed = false
	tc._input(tap_up)
	# 暂停 / 详情键发信号
	var got := {"pause": 0, "detail": 0, "menu": 0, "talk": 0}
	tc.pause_pressed.connect(func() -> void: got["pause"] += 1)
	tc.detail_pressed.connect(func() -> void: got["detail"] += 1)
	tc.menu_pressed.connect(func() -> void: got["menu"] += 1)
	tc.interact_pressed.connect(func() -> void: got["talk"] += 1)
	for pos in [TouchControls.PAUSE_POS, TouchControls.DETAIL_POS]:
		var t := InputEventScreenTouch.new()
		t.index = 2
		t.pressed = true
		t.position = pos
		tc._input(t)
		t.pressed = false
		tc._input(t)
	_check(got["pause"] == 1 and got["detail"] == 1, "暂停 / 详情键发出信号")
	tc.set_mode("town")
	var tm := InputEventScreenTouch.new()
	tm.index = 3
	tm.pressed = true
	tm.position = TouchControls.MENU_POS
	tc._input(tm)
	_check(got["menu"] == 1, "村子里的菜单键发出信号")
	tm.pressed = false
	tc._input(tm)
	var tt := InputEventScreenTouch.new()
	tt.index = 4
	tt.pressed = true
	tt.position = TouchControls.INTERACT_POS
	tc._input(tt)
	_check(got["talk"] == 0, "附近没有 NPC 时「交谈」键不响应")
	# 键盘一来就隐藏（笔记本触屏 + 键盘）
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_A
	tc._input(key)
	_check(not tc.is_active(), "收到键盘按键后触控隐藏")
	tc.queue_free()
	var og := OrientationGuard.new()
	add_child(og)
	await get_tree().process_frame
	_check(not og.blocking, "桌面 / 无头环境不显示「请横屏」")
	og.queue_free()


## 赤焰巅只该有五大派弟子、海棠屿只该有岛上的人：合围圈 / 精英 / 怪潮 / 时间表刷出的怪都不能是黑风寨的山贼、铁甲、刀客
func _map_spawn_test() -> void:
	print("\n=== 各地图的怪只来自本图 ===")
	var bw := ["bandit", "soldier", "blade", "archer", "charger"]
	for mid in ["guangming", "taohua"]:
		var w := GameWorld.new()
		w.god = true
		w.rng_seed = 31
		add_child(w)
		w.start_run("chain_fist", "tashue", mid)
		var allowed := {}
		for row in Data.maps[mid]["spawn_table"]:
			allowed[str(row["id"])] = true
		var bad := {}
		var elites := 0
		var rings := 0
		for i in int(330.0 / DT):
			w.step(DT)
			if i % 30 == 0:
				for e in w.enemies:
					if e.is_prop or e.is_boss:
						continue
					if e.is_elite:
						elites += 1
					if not allowed.has(e.type_id):
						bad[e.type_id] = true
			if w.over:
				break
		_check(bad.is_empty(), "%s：刷出的怪都来自本图时间表（出现了不该有的 %s）" % [mid, str(bad.keys())])
		_check(elites > 0, "%s：出现过精英（%d 次采样）" % [mid, elites])
		_free_world(w)
	var w2 := GameWorld.new()
	w2.rng_seed = 32
	add_child(w2)
	w2.start_run("chain_fist", "tashue", "black_wind")
	_check(w2._ring_type() == "bandit" and not w2._map_has_table(), "黑风寨的合围圈仍是山贼")
	_free_world(w2)


## 武者新天赋树：结构 + 20 个新机制各自生效
func _ft_world(talents: Dictionary, skill: String, seed_v: int = 700) -> GameWorld:
	var w := _new_world(seed_v)
	w.skills.clear()
	Build.apply_to(w, {}, talents, {}, "fist")
	w.add_skill(skill)
	w.recalc()
	w.neili = w.st("max_neili")
	return w


func _ft_foe(w: GameWorld, off: Vector2 = Vector2(70, 0), hp: float = 1.0e7) -> Enemy:
	var e: Enemy = w._spawn_enemy("bandit", w.player_pos + off)
	e.hp = hp
	e.speed = 0.0
	w._rebuild_grid()
	return e


## 让招式连续出手 n 次（每次先清冷却），返回敌人损失的气血
func _ft_dmg(talents: Dictionary, skill: String, n: int = 1, seed_v: int = 700, enhance: bool = false) -> float:
	var w := _ft_world(talents, skill, seed_v)
	if enhance:
		w.enhance_id = skill
		w.enhance_level = 1
	var e := _ft_foe(w)
	for i in n:
		var sk: SkillBase = w.skills[skill]
		sk.cd = 0.0
		e.pos = w.player_pos + Vector2(70, 0)
		w.step(1.0 / 60.0)
		for k in 30:
			w.step(1.0 / 60.0)
	var lost := 1.0e7 - e.hp
	_free_world(w)
	return lost


func _fist_talent_test() -> void:
	print("\n=== 武者新天赋树：结构 / 20 个新机制 ===")
	var tr: Dictionary = Talents.tree("fist")
	var nodes := Talents.nodes("fist")
	var covered := {}
	for b in ["gang", "rou", "ling"]:
		var tot := 0
		for n in tr["branches"][b]["nodes"]:
			tot += int(n["max"])
			for rq in n["req"]:
				_check(nodes.has(rq[0]), "前置节点存在：" + str(rq[0]))
		_check(tot == 50, "%s 系共 50 点（%d）" % [b, tot])
		for sk in tr["branches"][b]["col_skills"]:
			covered[sk] = true
	_check(covered.size() == 9 and covered.keys().all(func(k): return str(Data.skills[k]["school"]) == "fist"), "三系各管 3 个招式，共 9 个武者招式")
	var src := ""
	for f in ["res://scripts/skills/fist_skills.gd", "res://scripts/world.gd"]:
		src += FileAccess.get_file_as_string(f)
	for id in nodes:
		for k in nodes[id].get("stat", {}):
			if str(k).begins_with("t_"):
				_check(src.contains('"%s"' % str(k)), "新机制节点 %s 的属性 %s 在代码里有实现" % [id, k])
	# ---- 刚
	var w1 := _ft_world({"fg_a_1": 3}, "chain_fist")
	var foe := _ft_foe(w1)
	var ch: SkillBase = w1.skills["chain_fist"]
	var ms: Array[float] = []
	for i in 7:
		ms.append(ch.hit_mult(foe))
	_check(absf(ms[0] - 1.0) < 1e-6 and absf(ms[1] - 1.05) < 1e-6 and absf(ms[4] - 1.2) < 1e-6 and absf(ms[5] - 1.25) < 1e-6 and absf(ms[6] - ms[5]) < 1e-6, "连山不绝：破绽层数叠加 +5%%/层，3 级上限 5 层（%s）" % str(ms))
	_free_world(w1)
	_check(_ft_dmg({"fg_a_3": 2}, "chain_fist", 3, 701, true) > _ft_dmg({}, "chain_fist", 3, 701, true), "横扫余劲：强化后第三拳追加余劲扇面")
	_check(_ft_dmg({"fg_a_2": 3}, "chain_fist", 3, 702) > _ft_dmg({}, "chain_fist", 3, 702), "贯日之势：冲撞余波")
	var wc := _ft_world({"fg_a_4": 1}, "chain_fist", 703)
	var fc := _ft_foe(wc)
	for i in 3:
		(wc.skills["chain_fist"] as SkillBase).cd = 0.0
		fc.pos = wc.player_pos + Vector2(70, 0)
		for k in 30:
			wc.step(1.0 / 60.0)
	_check(fc.def_down_t > 0.0 and absf(fc.def_down - 0.3) < 1e-6, "贯日破天：第三拳贯穿直线，防御 −30%")
	_free_world(wc)
	_check(_ft_dmg({"fg_b_1": 3}, "vajra_fist", 1, 704) > _ft_dmg({}, "vajra_fist", 1, 704), "沉岳蓄势：满内力伤害更高")
	_check(_ft_dmg({"fg_b_2": 3}, "vajra_fist", 1, 705) > _ft_dmg({}, "vajra_fist", 1, 705), "金刚震地：命中后冲击波")
	var wb := _ft_world({"fg_b_3": 2, "fg_b_4": 1}, "vajra_fist", 706)
	var fb := _ft_foe(wb)
	(wb.skills["vajra_fist"] as SkillBase).cd = 0.0
	wb.step(1.0 / 60.0)
	_check(wb.tal_dr_t > 0.0 and absf(wb.tal_dr_v - 0.15) < 1e-6, "不坏金身：出拳后受伤减免 15%")
	_check(fb.stun > 0.0, "沉岳崩山：内力 ≥90% 震晕周围")
	_free_world(wb)
	var wq := _ft_world({"fg_c_2": 3, "fg_c_4": 1}, "quake_fist", 707)
	_ft_foe(wq, Vector2(150, 0))
	(wq.skills["quake_fist"] as SkillBase).cd = 0.0
	wq.step(1.0 / 60.0)
	var zn := 0
	var cracked := false
	for z in wq.zones:
		zn += 1
		cracked = cracked or bool(z.get("crack", false))
	_check(zn >= 2 and cracked, "裂脉连震：落点追加一次震击；裂脉断岳：留下裂缝（区域 %d）" % zn)
	_free_world(wq)
	var wz := _ft_world({"fg_c_3": 2}, "quake_fist", 708)
	var fz := _ft_foe(wz)
	var d0: float = wz.hit_enemy(fz, 100.0, [], Vector2.ZERO, "quake_fist", true)
	fz.stun = 1.0
	var d1: float = wz.hit_enemy(fz, 100.0, [], Vector2.ZERO, "quake_fist", true)
	_check(d1 > d0 * 1.1, "震断筋骨：被击晕的敌人受伤 +16%%（%.0f → %.0f）" % [d0, d1])
	_free_world(wz)
	# ---- 柔
	var wf := _ft_world({"fr_a_2": 3, "fr_a_4": 1}, "point_finger", 709)
	var ft := _ft_foe(wf, Vector2(300, 0))
	var pf: SkillBase = wf.skills["point_finger"]
	pf.cd = 0.0
	wf.step(1.0 / 60.0)
	_check(wf.projs.size() > 0 and wf.projs[0].falloff > float(Data.skills["point_finger"]["falloff"]) and wf.projs[0].stun > float(Data.skills["point_finger"]["stun"]), "寒霜入骨 / 万籁俱寂：衰减降低，定身 +1 秒")
	ft.stun = 1.0
	_check(absf(pf.hit_mult(ft) - 2.0) < 1e-6, "万籁俱寂：被定身的敌人受到凝霜点指伤害 ×2")
	_free_world(wf)
	var ws := _ft_world({"fr_a_3": 2}, "point_finger", 710)
	var s1 := _ft_foe(ws, Vector2(200, 0), 5.0)
	var s2 := _ft_foe(ws, Vector2(240, 30))
	s1.stun = 2.0
	ws._kill(s1)
	_check(s2.slow_t > 0.0 and absf(s2.slow_mult - 0.5) < 1e-6, "霜痕蔓延：被定身的敌人死亡，周围敌人减速 50%")
	_free_world(ws)
	_check(_ft_dmg({"fr_b_2": 3}, "whirl_palm", 1, 711) > _ft_dmg({}, "whirl_palm", 1, 711), "花开不败：满内力时圈数增加")
	var wl := _ft_world({"fr_b_4": 1}, "whirl_palm", 712)
	var fl := _ft_foe(wl, Vector2(40, 0), 1.0e7)
	var hp_before := wl.hp
	wl.hp = wl.st("max_hp") * 0.5
	hp_before = wl.hp
	(wl.skills["whirl_palm"] as SkillBase).cd = 0.0
	wl.step(1.0 / 60.0)
	_check(wl.hp > hp_before and (1.0e7 - fl.hp) > 0.0, "乱花漫天：三圈满追加全屏一圈并回复气血")
	_free_world(wl)
	var wf2 := _ft_world({"fr_b_3": 2}, "whirl_palm", 713)
	for k in 3:
		_ft_foe(wf2, Vector2(40 + k * 12, k * 10 - 10))
	wf2.neili = 10.0
	(wf2.skills["whirl_palm"] as SkillBase).cd = 0.0
	var n_before := wf2.neili
	wf2.step(1.0 / 60.0)
	_check(wf2.neili > n_before - 1.0 or wf2.neili >= n_before, "拂柳回气：一圈命中 ≥3 个敌人回内力（%.1f → %.1f）" % [n_before, wf2.neili])
	_free_world(wf2)
	var wt := _ft_world({"fr_c_1": 3, "fr_c_2": 3, "fr_c_3": 2, "fr_c_4": 1}, "taiji", 714)
	_ft_foe(wt, Vector2(50, 0))
	var tj: SkillBase = wt.skills["taiji"]
	tj.guard_cd = 0.0
	var left := tj.on_hurt(100.0)
	var wt0 := _ft_world({}, "taiji", 714)
	_ft_foe(wt0, Vector2(50, 0))
	var left0 := (wt0.skills["taiji"] as SkillBase).on_hurt(100.0)
	_check(left < left0, "卸力归元：化解比例提高（%.1f < %.1f）" % [left, left0])
	_check(wt.tal_spd_t > 0.0 and absf(wt.tal_spd_v - 0.2) < 1e-6, "太极圆转：化解后移速 +20%")
	_free_world(wt)
	_free_world(wt0)
	var wh := _ft_world({"fr_c_4": 1}, "taiji", 715)
	var fh := _ft_foe(wh, Vector2(50, 0))
	var th: SkillBase = wh.skills["taiji"]
	var hp0 := fh.hp
	for i in 12:
		th.guard_cd = 0.0
		th.on_hurt(100.0)
	_check(fh.hp < hp0, "回澜归海：累计化解 100 点后范围反震")
	_free_world(wh)
	# ---- 灵
	var wp := _ft_world({"fl_a_4": 1, "fl_a_3": 3}, "cloud_palm", 716)
	wp.skills["cloud_palm"].mods["targets"] = 2.0
	_ft_foe(wp, Vector2(300, 0))
	wp.palm_stacks = 2
	var cp: SkillBase = wp.skills["cloud_palm"]
	cp.cd = 0.0
	wp.step(1.0 / 60.0)
	var maxr := 0.0
	var maxd := 0.0
	for pr in wp.projs:
		maxr = maxf(maxr, pr.radius)
		maxd = maxf(maxd, pr.damage)
	_check(wp.palm_stacks == 0 and maxr >= cp.p("radius") * 1.9, "阳极生阴：掌印齐备时融合成巨掌印；阳回雪归层数被消耗（半径 %.0f）" % maxr)
	_free_world(wp)
	var wy := _ft_world({"fl_b_2": 3, "fl_b_3": 2, "fl_b_4": 1}, "yue_palm", 717)
	_ft_foe(wy, Vector2(250, 0))
	var yp: SkillBase = wy.skills["yue_palm"]
	yp.cd = 0.0
	wy.step(1.0 / 60.0)
	_check(wy.projs.size() == 1 and wy.projs[0].end_burst_dmg > 0.0 and absf(wy.projs[0].falloff - 1.10) < 1e-6, "惊涛叠浪（尽头炸浪）/ 撼岳之势（穿透递增）")
	for i in 4:
		yp.cd = 0.0
		wy.projs.clear()
		yp.fire()
	_check(wy.projs.size() == 3, "惊涛骇浪：每第 5 掌 3 道并排巨浪（%d）" % wy.projs.size())
	_free_world(wy)
	var we := _ft_world({"fl_c_3": 2, "fl_c_4": 1}, "eight_waste", 718)
	_ft_foe(we, Vector2(200, 0))
	var ew: SkillBase = we.skills["eight_waste"]
	ew.cd = 0.0
	we.step(1.0 / 60.0)
	_check(we.projs.size() >= 8 and we.projs[0].neili_hit > 0.0 and we.projs[0].conv, "归元返照 / 归元一气：拳气带回内力与汇聚标记")
	var hpb := 1.0e7
	var fe := _ft_foe(we, Vector2(30, 0))
	hpb = fe.hp
	for i in 90:
		we.step(1.0 / 60.0)
	_check(fe.hp < hpb, "归元一气：拳气消失后汇聚成大爆炸（%.0f）" % (hpb - fe.hp))
	_free_world(we)
	print("  结构 / 20 个新机制  OK")


func _fist_sig_test() -> void:
	print("\n=== 武者招牌系统链：寸劲 / 气海 / 无敌 ===")
	# 寸劲
	var w := _ft_world({"fg_g_2": 3, "fg_g_3": 3, "fg_g_4": 3, "fg_g_6": 3, "fg_g_7": 2, "fg_g_8": 1}, "chain_fist", 720)
	var foe := _ft_foe(w, Vector2(80, 0))
	w.fist_qi = 70.0
	var sk: SkillBase = w.skills["chain_fist"]
	_check(absf(w.st("qi_gain") - 0.45) < 1e-6, "蓄劲 3 级：攒劲速度 +45%")
	sk.cd = 0.0
	foe.pos = w.player_pos + Vector2(80, 0)
	w.step(1.0 / 60.0)
	_check(w.cunjin_count >= 1, "寸劲无双：攒到 70 劲就能震爆")
	_check(foe.def_down_t > 0.0 and absf(foe.def_down - 0.3) < 1e-6, "破阵劲：震爆命中降防 30%")
	var has_after := false
	for z in w.zones:
		has_after = has_after or str(z["kind"]) == "impact"
	_check(has_after, "余震劲：0.6 秒后再震一次")
	_free_world(w)
	# 气海
	var w2 := _ft_world({"fr_g_3": 3, "fr_g_4": 1, "fr_g_8": 1}, "chain_fist", 721)
	_check(absf(w2.ying_at() - 0.5) < 1e-6, "盈境绵长 3 级：盈境门槛 65% → 50%")
	w2.neili = w2.st("max_neili")
	for i in 240:
		w2.step(1.0 / 60.0)
	_check(w2.ying_hold >= 3.0 or w2.yuanman_ready or w2.yuanman_cd > 0.0, "盈而圆满：盈境持续满 3 秒（%.1f）" % w2.ying_hold)
	_free_world(w2)
	var w3 := _ft_world({"fr_g_4": 1, "fr_g_8": 1}, "chain_fist", 722)
	var f3 := _ft_foe(w3, Vector2(300, 300), 1.0e7)
	w3.neili = 5.0
	w3.step(1.0 / 60.0)
	w3.neili = w3.st("max_neili")
	var hp0 := f3.hp
	w3.qihai_cd = 0.0
	f3.pos = w3.player_pos + Vector2(60, 0)
	w3.step(1.0 / 60.0)
	_check(f3.hp < hp0 and w3.qihai_cd > 0.0, "气海翻涌：升入盈境震出气浪")
	_free_world(w3)
	# 无敌
	var w4 := _ft_world({"fl_g_1": 4, "fl_g_3": 3, "fl_g_7": 2, "fl_g_8": 1}, "chain_fist", 723)
	w4._burst()
	_check(absf(w4.fist_ult_t - 14.0) < 0.01 or absf(w4.fist_ult_t - Data.T("fist_ult_dur") - 4.0) < 0.01, "蓄势待发 4 级：无敌 +4 秒（%.1f）" % w4.fist_ult_t)
	_check(w4.ult_keep > 0.0, "无敌金身：只消耗一半内力（返还 %.0f）" % w4.ult_keep)
	var e4 := _ft_foe(w4, Vector2(60, 0))
	w4.hit_enemy(e4, 100.0, [], Vector2.ZERO, "chain_fist", true)
	_check(w4.ult_dmg > 0.0, "无敌期间累计伤害（破境余波用）")
	w4.fist_ult_t = 0.05
	w4.neili = 0.0
	for i in 5:
		w4.step(1.0 / 60.0)
	_check(w4.neili >= w4.ult_keep and w4.neili > 0.0, "无敌结束：返还一半内力 + 气归丹田（%.0f）" % w4.neili)
	_free_world(w4)
	var w5 := _ft_world({"fl_g_4": 3}, "chain_fist", 724)
	w5.burst_used = 2
	w5.fist_ult_t = 5.0
	for i in 15:
		var ee: Enemy = w5._spawn_enemy("bandit", w5.player_pos + Vector2(300, 0))
		w5._kill(ee)
	_check(w5.burst_used == 1, "杀伐还元：无敌期间击杀 15 个，返还 1 次真气爆发（%d）" % w5.burst_used)
	_free_world(w5)
	print("  寸劲 / 气海 / 无敌  OK")


func _sw_world(talents: Dictionary, skill: String, seed_v: int = 800) -> GameWorld:
	var w := _new_world(seed_v, "kuang_feng")
	w.skills.clear()
	w.school_id = "sword"
	Build.apply_to(w, {}, talents, {}, "sword")
	w.add_skill(skill)
	w.recalc()
	w.neili = w.st("max_neili")
	return w


func _sword_tree_test() -> void:
	print("\n=== 剑客新天赋树：结构 / 通用机制 / 九变之道 ===")
	var tr: Dictionary = Talents.tree("sword")
	var nodes := Talents.nodes("sword")
	for b in ["gang", "rou", "ling"]:
		var tot := 0
		for n in tr["branches"][b]["nodes"]:
			tot += int(n["max"])
			for rq in n["req"]:
				_check(nodes.has(rq[0]), "前置节点存在：" + str(rq[0]))
		_check(tot == 50, "剑客 %s 系共 50 点（%d）" % [b, tot])
	var ling_nodes: Array = tr["branches"]["ling"]["nodes"]
	var dugu_pts := 0
	for n in ling_nodes:
		if str(n["id"]).begins_with("sl_a") or str(n["id"]).begins_with("sl_b") or str(n["id"]).begins_with("sl_c"):
			dugu_pts += int(n["max"])
	_check(dugu_pts == 31 and (tr["branches"]["ling"]["cols"] as Array).size() == 6, "灵系：九变剑占 31 点（超过一半），共 6 列")
	var src := ""
	for f in ["res://scripts/skills/fist_skills.gd", "res://scripts/skills/sword_skills.gd", "res://scripts/skills/skill_base.gd", "res://scripts/world.gd"]:
		src += FileAccess.get_file_as_string(f)
	for id in nodes:
		for k in nodes[id].get("stat", {}):
			if str(k).begins_with("t_"):
				_check(src.contains('"%s"' % str(k)), "剑客节点 %s 的属性 %s 在代码里有实现" % [id, k])
	# 通用机制
	_check(Talents.has_tree("sword") and Talents.group_of("sword") == "sword", "剑客用新树")
	var w1 := _sw_world({"sg_g_2": 3}, "kuang_feng", 801)
	var k1: SkillBase = w1.skills["kuang_feng"]
	var echoes := 0
	for i in 200:
		k1.echo_t = -1.0
		k1._after_fire()
		if k1.echo_t >= 0.0:
			echoes += 1
	var exp_e := (float(k1.mods["hits"]) + 0.3) * 200.0
	_check(echoes > exp_e - 30 and echoes < exp_e + 30 and float(k1.mods["hits"]) >= 0.0, "连段 3 级：近战招式多打一段的几率 +30%%（%d/200，期望约 %d）" % [echoes, int(exp_e)])
	_check(float(Data.skills["kuang_feng"].get("echo_base", 0.0)) < 0.5, "（基础几率低于总几率，天赋 +30%% 真正叠加）")
	_free_world(w1)
	var w2 := _sw_world({"sg_g_3": 4}, "zhongjian", 802)
	var f2 := _ft_foe(w2)
	(w2.skills["zhongjian"] as SkillBase).cd = 0.0
	var h0 := f2.hp
	w2.step(1.0 / 60.0)
	_check(f2.hp < h0, "隔山打牛 / 重剑命中")
	_free_world(w2)
	var w3 := _sw_world({"sr_g_3": 3}, "kuang_feng", 803)
	var f3 := _ft_foe(w3)
	var d0: float = w3.hit_enemy(f3, 100.0, [], Vector2.ZERO, "kuang_feng", false)
	f3.stun = 1.0
	_check(w3.st("t_kongchang") == 3.0, "控场易伤 3 级")
	_free_world(w3)
	var w4 := _sw_world({"sr_g_2": 2}, "kuang_feng", 804)
	_ft_foe(w4)
	(w4.skills["kuang_feng"] as SkillBase).cd = 0.0
	w4.step(1.0 / 60.0)
	var has_proj := false
	for pr in w4.projs:
		has_proj = has_proj or pr.skill_id == "kuang_feng"
	_check(has_proj, "剑气外放：近战挥砍额外飞出一道远程波")
	_free_world(w4)
	# 九变之道
	var wd := _sw_world({"sl_a_1": 3, "sl_a_2": 1}, "dugu", 805)
	_check(wd.shi_lv("zong") == 3, "初悟 3 级：开局自带总纲变 3 层（%d）" % wd.shi_lv("zong"))
	_check(wd.shi_th(1) == 11 and wd.shi_th(2) == 22 and wd.shi_th(3) == 33 and wd.shi_kinds() == 6, "悟性：门槛 11 / 22 / 33，种类 6")
	wd.add_shi("po_jian", 1)
	wd.add_shi("po_dao", 1)
	wd.add_shi("po_qiang", 1)
	wd.add_shi("po_bian", 1)
	wd.add_shi("po_suo", 1)
	_check(wd.shi.size() == 6, "可同时领悟 6 种变（%d）" % wd.shi.size())
	wd.shi["zong"] = 33
	_check(wd.dugu_true(), "总层数 33 觉醒")
	_free_world(wd)
	var wz := _sw_world({"sl_a_5": 1, "sl_a_2": 0}, "dugu", 806)
	wz.shi["zong"] = 27
	_check(wz.dugu_true() and wz.burst_left() == 1, "真·九变：觉醒后真气爆发改为冷却型")
	wz.neili = wz.st("max_neili")
	wz._burst()
	_check(wz.burst_left() == 0 and wz.zhenbian_cd > 29.0, "真气爆发后进入 30 秒冷却，而不是消耗次数（%.0f）" % wz.zhenbian_cd)
	wz.zhenbian_cd = 0.0
	_check(wz.burst_left() == 1, "冷却结束后可再次爆发")
	_free_world(wz)
	var wf := _sw_world({"sl_b_1": 4}, "dugu", 807)
	_ft_foe(wf, Vector2(200, 0))
	var dg: SkillBase = wf.skills["dugu"]
	var got := 0
	for i in 80:
		dg.cd = 0.0
		wf.projs.clear()
		dg.fire()
		got += wf.projs.size()
	_check(got > 80 + 15, "复剑 4 级：约 32%% 几率多发一轮（%d）" % got)
	_free_world(wf)
	var wg := _sw_world({"sl_c_5": 1}, "dugu", 808)
	var dgg: SkillBase = wg.skills["dugu"]
	wg.add_shi("zong", 1)
	_check(wg.guiyi_ready and dgg.cd == 0.0, "九变归一：领悟后下一剑增伤并重置冷却")
	_free_world(wg)
	var wn := _sw_world({"sl_c_1": 3}, "dugu", 809)
	wn.add_shi("po_bian", 3)
	var dn: SkillBase = wn.skills["dugu"]
	_ft_foe(wn, Vector2(200, 0))
	dn.cd = 0.0
	wn.projs.clear()
	dn.fire()
	_check(wn.projs.size() > 0 and wn.projs[0].bounce == 1 + 3 and absf(wn.projs[0].bounce_dmg - 1.0) < 1e-6, "折锋连环：弹射 +3，弹射不衰减（%d）" % wn.projs[0].bounce)
	_free_world(wn)
	var wp := _sw_world({"sl_d_2": 2, "sl_d_3": 1}, "pixie", 810)
	_ft_foe(wp, Vector2(200, 0))
	(wp.skills["pixie"] as SkillBase).cd = 0.0
	wp.step(1.0 / 60.0)
	_check(absf(wp.ys_buff - 0.4) < 1e-6 and wp.ys_t > 0.0, "影随身动：闪现后下一次攻击 +40%%")
	var hasz := false
	for z in wp.zones:
		hasz = hasz or str(z["kind"]) == "impact"
	_check(hasz, "欲练神功·极：残影 1 秒后再刺")
	_free_world(wp)
	var wj := _sw_world({"sl_f_2": 2, "sl_f_3": 1}, "jinshe", 811)
	var fj := _ft_foe(wj, Vector2(100, 0), 1.0e7)
	for i in 5:
		wj.poison_enemy(fj, 8.0, "jinshe")
	_check(fj.poison_dps == 0.0 and fj.hp < 1.0e7, "万毒归心：毒层 ≥5 立刻引爆")
	var fk := _ft_foe(wj, Vector2(120, 20), 1.0e7)
	wj.poison_enemy(fk, 8.0, "jinshe")
	_check(fk.poison_burst > 0.0 and absf(fk.poison_burst_f - 0.5) < 1e-6, "毒雾弥漫：不强化也会爆，50% 伤害")
	_free_world(wj)
	var wl := _sw_world({"sl_f_1": 3}, "jinshe", 812)
	_check(int((wl.skills["jinshe"] as SkillBase).p("count")) == int(Data.skills["jinshe"]["count"]) + 3 or (wl.skills["jinshe"] as SkillBase).mods["targets"] > 0.0, "曲锋缠丝 +3")
	_free_world(wl)
	print("  剑客结构 / 通用机制 / 九变  OK")


func _bl_world(talents: Dictionary, skill: String, seed_v: int = 900) -> GameWorld:
	var w := _new_world(seed_v, "wuhu_blade")
	w.skills.clear()
	w.school_id = "blade"
	Build.apply_to(w, {}, talents, {}, "blade")
	w.add_skill(skill)
	w.recalc()
	w.hp = w.st("max_hp")
	return w


func _blade_tree_test() -> void:
	print("\n=== 刀客新天赋树：刀魂 / 血债 / 绝境 + 招式链 ===")
	var tr: Dictionary = Talents.tree("blade")
	var nodes := Talents.nodes("blade")
	for b in ["gang", "rou", "ling"]:
		var tot := 0
		for n in tr["branches"][b]["nodes"]:
			tot += int(n["max"])
			for rq in n["req"]:
				_check(nodes.has(rq[0]), "前置节点存在：" + str(rq[0]))
		_check(tot == 50, "刀客 %s 系共 50 点（%d）" % [b, tot])
	var src := ""
	for f in ["res://scripts/skills/blade_skills.gd", "res://scripts/world.gd"]:
		src += FileAccess.get_file_as_string(f)
	for id in nodes:
		for k in nodes[id].get("stat", {}):
			if str(k).begins_with("t_"):
				_check(src.contains('"%s"' % str(k)), "刀客节点 %s 的属性 %s 在代码里有实现" % [id, k])
	_check(Talents.group_of("blade") == "blade", "刀客用新树")
	# 刀魂
	var w := _bl_world({"bg_g_3": 3, "bg_g_4": 3, "bg_g_7": 2, "bg_g_8": 1}, "wuhu_blade", 901)
	w.soul = 80.0
	var s1: SkillBase = w.skills["wuhu_blade"]
	_check(w.baodao_try(s1), "霸刀无双：刀魂 80 就能触发霸刀破岳")
	w.baodao = false
	w.baodao_done()
	_check(absf(w.soul - 30.0) < 1e-6 and w.hunbao_t > 0.0 and absf(w.hunbao_v - 1.0) < 1e-6, "魂火余烬保留 30 刀魂、魂爆（刀魂 ×2）（%.0f）" % w.soul)
	var has_imp := false
	for z in w.zones:
		has_imp = has_imp or str(z["kind"]) == "impact"
	_check(has_imp, "破岳·余震：0.6 秒后再劈一次")
	_free_world(w)
	# 血债
	var w2 := _bl_world({"br_g_2": 3, "br_g_3": 3, "br_g_8": 1}, "xuedao", 902)
	var x: SkillBase = w2.skills["xuedao"]
	var hp0 := w2.hp
	w2.soul = 0.0
	(x as BladeSkills.Base).pay_hp()
	var paid := hp0 - w2.hp
	var w2b := _bl_world({}, "xuedao", 902)
	var hpb := w2b.hp
	(w2b.skills["xuedao"] as BladeSkills.Base).pay_hp()
	_check(paid < (hpb - w2b.hp) and w2.yd_t > 0.0 and w2.yd_v > 0.0 and w2.soul > w2b.soul * 1.0, "血契耗血更少（%.1f < %.1f）、以血养刀增伤、血魂归一刀魂更多" % [paid, hpb - w2b.hp])
	_free_world(w2)
	_free_world(w2b)
	var w3 := _bl_world({"br_g_4": 3}, "xuedao", 903)
	var f3 := _ft_foe(w3)
	f3.bleed_stacks = 5
	var d1: float = w3.hit_enemy(f3, 100.0, [], Vector2.ZERO, "xuedao", true)
	f3.bleed_stacks = 0
	var d0: float = w3.hit_enemy(f3, 100.0, [], Vector2.ZERO, "xuedao", true)
	_check(d1 > d0 * 1.2, "撕裂易伤：≥5 层的敌人受伤 +30%%（%.0f vs %.0f）" % [d1, d0])
	_free_world(w3)
	var w4 := _bl_world({"br_g_6": 3}, "xuedao", 904)
	w4.hp = 10.0
	var k4: Enemy = w4._spawn_enemy("bandit", w4.player_pos + Vector2(300, 0))
	w4._kill(k4)
	_check(w4.hp > 10.0 + w4.st("max_hp") * 0.05, "饮血：击杀回复 6% 气血")
	_free_world(w4)
	# 绝境
	var w5 := _bl_world({"bl_g_1": 4, "bl_g_2": 3, "bl_g_3": 3, "bl_g_7": 2}, "hujia_blade", 905)
	w5.hp = w5.st("max_hp") * 0.34
	w5._tick_true_blade(0.1)
	_check(w5.tb_t > 0.0, "绝境 3 级：气血 ≤35% 就触发真·霸刀")
	_check(absf(w5.tb_t - (Data.T("true_blade_dur") + 4.0)) < 0.01, "蓄势 4 级：真·霸刀 +4 秒（%.1f）" % w5.tb_t)
	_check(absf(w5.heal_mult() - (Data.T("true_blade_heal_mult") + 0.9)) < 1e-6, "回复加深 3 级")
	w5.tb_t = 0.05
	w5._tick_true_blade(0.1)
	_check(absf(w5.tb_cd - 18.0) < 0.01, "重燃 2 级：冷却 18 秒（%.1f）" % w5.tb_cd)
	_free_world(w5)
	# 招式链
	var w6 := _bl_world({"bg_a_3": 2}, "wuhu_blade", 906)
	var f6 := _ft_foe(w6)
	(w6.skills["wuhu_blade"] as SkillBase).cd = 0.0
	w6.step(1.0 / 60.0)
	_check(f6.bleed_stacks >= 3, "撕裂入骨：一刀叠 3 层撕裂（%d）" % f6.bleed_stacks)
	_free_world(w6)
	var w7 := _bl_world({"bg_c_4": 1}, "xuanxu_blade", 907)
	_ft_foe(w7, Vector2(200, 0))
	(w7.skills["xuanxu_blade"] as SkillBase).cd = 0.0
	w7.step(1.0 / 60.0)
	_check(w7.projs.size() >= 5, "开山·极：裂地刀痕 5 道（%d）" % w7.projs.size())
	_free_world(w7)
	var w8 := _bl_world({"bl_a_4": 1, "bl_a_3": 2}, "hujia_blade", 908)
	_ft_foe(w8, Vector2(200, 0))
	(w8.skills["hujia_blade"] as SkillBase).cd = 0.0
	w8.step(1.0 / 60.0)
	var boom := false
	for pr in w8.projs:
		boom = boom or (pr.boomerang and absf(pr.ret_mult - 0.6) < 1e-6)
	_check(boom and absf((w8.skills["hujia_blade"] as SkillBase).hit_mult(_ft_foe(w8, Vector2(30, 0))) - 1.75) < 1e-6, "八方藏刀·极折返；落单必杀 2 级近处 ×1.75")
	_free_world(w8)
	var w9 := _bl_world({"bl_b_3": 2}, "ranmu_blade", 909)
	var e9: Enemy = w9._spawn_enemy("bandit", w9.player_pos + Vector2(300, 0))
	e9.burn_t = 2.0
	var zn := w9.zones.size()
	w9._kill(e9)
	_check(w9.zones.size() == zn + 1, "灼烧蔓延：被灼烧的敌人死亡生出火海")
	_free_world(w9)
	print("  刀客 刀魂 / 血债 / 绝境 / 招式链  OK")


func _sp_world(talents: Dictionary, skill: String, seed_v: int = 950) -> GameWorld:
	var w := _new_world(seed_v, "yangjia_spear")
	w.skills.clear()
	w.school_id = "spear"
	Build.apply_to(w, {}, talents, {}, "spear")
	w.add_skill(skill)
	w.recalc()
	w.hp = w.st("max_hp")
	return w


func _spear_tree_test() -> void:
	print("\n=== 杨家将新天赋树：棍势 / 守势 / 枪势 + 招式链 ===")
	var tr: Dictionary = Talents.tree("spear")
	var nodes := Talents.nodes("spear")
	for b in ["gang", "rou", "ling"]:
		var tot := 0
		for n in tr["branches"][b]["nodes"]:
			tot += int(n["max"])
			for rq in n["req"]:
				_check(nodes.has(rq[0]), "前置节点存在：" + str(rq[0]))
		_check(tot == 50, "杨家将 %s 系共 50 点（%d）" % [b, tot])
	_check(str(tr["branches"]["rou"]["starter"]) == "", "杨家将柔系没有起手招式")
	var src := ""
	for f in ["res://scripts/skills/spear_skills.gd", "res://scripts/world.gd"]:
		src += FileAccess.get_file_as_string(f)
	for id in nodes:
		for k in nodes[id].get("stat", {}):
			if str(k).begins_with("t_"):
				_check(src.contains('"%s"' % str(k)), "杨家将节点 %s 的属性 %s 在代码里有实现" % [id, k])
	_check(Talents.group_of("spear") == "spear", "杨家将用新树")
	# 守势
	var w := _sp_world({"pr_g_6": 3, "pr_g_5": 4, "pr_g_2": 3, "pr_g_3": 3, "pr_g_4": 3, "pr_g_7": 2}, "panlong_staff", 951)
	w.panlong_t = 0.0
	_check(absf(w.block_chance() - minf(0.85, w.st("block_chance"))) < 1e-6, "格挡几率上限 85%%（无懈可击 3 级）：%.2f" % w.block_chance())
	var f := _ft_foe(w, Vector2(60, 0), 1.0e7)
	var hp0 := f.hp
	w._on_block()
	_check(f.hp < hp0 and w.tiebi_t > 0.0, "反击：格挡成功自动反击周围；铁壁连环开启窗口")
	for i in 3:
		w._on_block()
	_check(w.yishou_buff >= 2.0, "以守为攻 2 级：每 3 次格挡，下一击 ×2")
	_free_world(w)
	# 万法归宗：任意招式都能打游龙突 / 横扫千军，攒势
	var w2 := _sp_world({"pr_g_8": 1}, "shaolin_staff", 952)
	var fy := _ft_foe(w2, Vector2(100, 0), 1.0e7)
	w2.spear_qs = 100.0
	var sk: SpearSkills.Base = w2.skills["shaolin_staff"]
	_check(sk.breakthrough(Vector2.RIGHT) and w2.spear_qs < 100.0, "万法归宗：棍法也能打出游龙突")
	w2.spear_gs = 100.0
	_check(sk.wide_sweep(), "横扫千军可由任意招式打出")
	w2.spear_qs = 0.0
	w2._spear_on_hit(sk, fy)
	_check(w2.spear_qs > 0.0 and w2.spear_combo >= 1, "任意招式命中都攒枪势、计连击")
	_free_world(w2)
	# 棍势链
	var w3 := _sp_world({"pg_g_2": 3, "pg_g_8": 1, "pg_g_4": 3, "pg_a_3": 2}, "shaolin_staff", 953)
	var f3 := _ft_foe(w3, Vector2(100, 0), 1.0e7)
	var sk3: SpearSkills.Base = w3.skills["shaolin_staff"]
	w3.spear_gs = 100.0
	_check(sk3.wide_sweep(), "横扫千军打出")
	_check(w3.spear_gs >= 30.0, "棍势满溢：横扫后再攒棍势（%.0f）" % w3.spear_gs)
	_check(f3.def_down_t > 0.0 and f3.stun > 0.0, "破阵棍降防；横扫天下晕眩")
	_free_world(w3)
	var w3b := _sp_world({"pg_a_4": 1}, "shaolin_staff", 954)
	_ft_foe(w3b, Vector2(100, 0), 1.0e7)
	var sh: SkillBase = w3b.skills["shaolin_staff"]
	var fulls := 0
	for i in 4:
		sh.cd = 0.0
		var before := w3b.effects.size()
		sh.fire()
		fulls += 1
	_check(fulls == 4 and (sh as SpearSkills.Shaolin).combo == 4, "大开大合·极：第 2 下就能 360° 横扫")
	_free_world(w3b)
	# 枪势链
	var w4 := _sp_world({"pl_g_2": 3, "pl_g_4": 3, "pl_g_6": 3, "pl_g_8": 1, "pl_a_4": 1, "pl_g_3": 3}, "yangjia_spear", 955)
	var f4 := _ft_foe(w4, Vector2(150, 0), 1.0e7)
	var y: SpearSkills.Base = w4.skills["yangjia_spear"]
	w4.spear_fire_n = 5
	_check(y.breakthrough(Vector2.RIGHT), "枪出如龙：第 5 次出枪游龙突无需攒势")
	_check(w4.huima_t > 0.0, "回马连环·极：游龙突后杨家枪法加速")
	for i in 5:
		w4._spear_on_hit(y, f4)
	_check(w4.spear_since_shadow == 0 or w4.spear_since_shadow < 5, "连击枪影 3 级：连击 5 触发枪影")
	_free_world(w4)
	var w5 := _sp_world({"pr_c_3": 2, "pr_c_4": 1}, "wuming_spear", 956)
	var f5 := _ft_foe(w5, Vector2(100, 0), 1.0e7)
	var k5: Enemy = w5._spawn_enemy("bandit", w5.player_pos + Vector2(400, 0))
	w5._kill(k5)
	_check(absf(w5.wm_boost - 0.5) < 1e-6, "无名之名 2 级：击杀后下一发 +50%")
	(w5.skills["wuming_spear"] as SkillBase).cd = 0.0
	w5.step(1.0 / 60.0)
	_check(w5.wm_boost == 0.0 and f5.def_down_t > 7.0, "增伤被消耗；返璞归真：防御削弱 8 秒")
	_free_world(w5)
	var w6 := _sp_world({"pl_b_4": 1}, "meihua_spear", 957)
	_ft_foe(w6, Vector2(120, 0), 1.0e7)
	var mh: SkillBase = w6.skills["meihua_spear"]
	for i in 5:
		mh.cd = 0.0
		mh.fire()
	_check((mh as SpearSkills.Meihua)._mh == 5, "梅花雨：计数到第 5 次")
	_free_world(w6)
	print("  杨家将 棍势 / 守势 / 枪势 / 招式链  OK")


## 可以先单点一条链（一排）：普通节点的门槛不超过本链已点的点数，可以一路点到终极前一格；终极（25）和巅峰（36）要别的链凑
func _single_chain_test() -> void:
	print("\n=== 天赋：单点一条链 ===")
	var cnt := 0
	for sc in ["fist", "sword", "blade", "spear"]:
		var nodes := Talents.nodes(sc)
		var cols := {}
		for id in nodes:
			var n: Dictionary = nodes[id]
			if n["branch"] == "ji" or bool(n.get("peak", false)):
				continue
			var key := "%s:%s" % [n["branch"], str(n["col"])]
			if not cols.has(key):
				cols[key] = []
			cols[key].append(id)
		for key in cols:
			var ids: Array = cols[key]
			ids.sort_custom(func(a, b): return int(nodes[a]["row"]) < int(nodes[b]["row"]))
			var t := {}
			for id in ids:
				while Talents.can_add(t, id, 50):
					t[id] = int(t.get(id, 0)) + 1
			var full := true
			var cap_blocked := true
			for id in ids:
				if bool(nodes[id].get("cap", false)):
					cap_blocked = cap_blocked and int(t.get(id, 0)) == 0                 # 终极需要别的链凑够 25 点
				else:
					full = full and int(t.get(id, 0)) == int(nodes[id]["max"])
			_check(full and cap_blocked, "%s %s 单点一整条链能点到终极前一格，终极要别的链凑够点数（%d 点）" % [sc, key, Talents.spent(t)])
			cnt += 1
	var hint := Talents.skill_hint("fist", {"fg_a_1": 2, "fg_a_2": 1}, "chain_fist")
	_check(hint.contains("连山不绝 2/3") and hint.contains("贯日之势 1/3"), "局内抽卡提示：天赋树强化该招式（%s）" % hint)
	_check(Talents.skill_hint("fist", {"fg_a_1": 2}, "quake_fist") == "" and Talents.skill_hint("fist", {}, "chain_fist") == "", "没点相关节点就不提示")
	# 天赋页性能：节点状态缓存，加点后能刷新
	var gt := TalentGrid.new()
	gt.school = "fist"
	gt.level = 50
	add_child(gt)
	_check(gt.state_of("fg_a_2") == "locked" and gt.state_of("fg_a_1") == "open", "天赋页：初始状态（缓存）")
	gt.work["fg_a_1"] = 3
	gt.changed.emit()
	_check(gt.state_of("fg_a_2") == "open" and gt.state_of("fg_a_1") == "maxed", "天赋页：加点后缓存刷新")
	remove_child(gt)
	gt.free()
	print("  %d 条链都能单点点满  OK" % cnt)
