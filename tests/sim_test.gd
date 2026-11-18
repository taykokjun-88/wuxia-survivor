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
		_level_growth_test()
		_save_test()
		_sprite_anim_test()
		await _net_test()
		_meta_test()
		_neili_test()
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
	if only == "survive":
		_survive_report()
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
		w.start_run(["chain_fist", "point_finger", "cloud_palm"][sd % 3], ["tashue", "feiyan", "yufeng", "lingshe"][sd % 4])
		var pick_rng := RandomNumberGenerator.new()
		pick_rng.seed = sd
		for i in int(900.0 / DT):
			TestBot.drive(w, TestBot.engage_for(w))
			w.step(DT)
			TestBot.resolve_choices(w, pick_rng, true)
			if w.over:
				break
		wins += 1 if w.won else 0
		tsum += w.time
		for k in 3:
			rsum[k] += float(w.realm_time[k])
		_free_world(w)
	var tot: float = rsum[0] + rsum[1] + rsum[2]
	print("  通关 %d/%d　平均存活 %ds　气海 虚 %d%% / 平 %d%% / 盈 %d%%" % [wins, seeds.size(), int(tsum / seeds.size()),
		int(rsum[0] / tot * 100.0), int(rsum[1] / tot * 100.0), int(rsum[2] / tot * 100.0)])


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


func _run_full() -> void:
	_full_run({"name": "完整局·无敌 + 会选卡（压测 + 3 小 Boss + 大 Boss + 精英/秘籍）", "god": true, "smart": true,
		"seed": 1, "dur": 900.0, "starter": "chain_fist", "qg": "tashue"})
	_full_run({"name": "完整局·会选卡的合格玩家（不无敌）", "god": false, "smart": true,
		"seed": 2, "dur": 900.0, "starter": "cloud_palm", "qg": "feiyan"})
	_full_run({"name": "完整局·纯随机选卡的新手（不无敌，难度下限）", "god": false, "smart": false,
		"seed": 3, "dur": 900.0, "starter": "point_finger", "qg": "yufeng"})


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
				# 太极劲是受击触发：god 模式下直接调用，覆盖反击分支
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
	_check(is_equal_approx(w.st("damage_pct"), float(g["damage_pct"]) * steps), "基础伤害加成应随等级成长")
	_check(w.hp > hp_before, "升级时应同步补上新增的气血上限")
	var d2 := w.hit_enemy(e, 100.0, [], Vector2.ZERO, "probe")
	_check(is_equal_approx(d2 / d1, 1.0 + float(g["damage_pct"]) * steps), "同一次攻击的伤害应按基础伤害加成放大，实际 ×%.3f" % (d2 / d1))
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
	_check(s0.level == 12, "升满后应为 12 层，实际 %d" % s0.level)
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
	for bad in ["sword", "nonexistent"]:
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


func _neili_test() -> void:
	print("\n=== 内力：气海三境 / 催动 / 入定 ===")
	var w := _new_world(5)
	w.skills.clear()
	var mx := w.st("max_neili")
	# 三境判定与伤害加成
	w.neili = mx * 0.9
	_check(w.realm() == GameWorld.Realm.YING and is_equal_approx(w.dmg_mult(), Data.T("ying_dmg")), "达到盈境门槛为盈，伤害加成")
	w.neili = mx * 0.5
	_check(w.realm() == GameWorld.Realm.PING and is_equal_approx(w.dmg_mult(), 1.0), "平境无加成")
	w.neili = mx * 0.2
	_check(w.realm() == GameWorld.Realm.XU, "低于 25% 为虚")
	# 纯阳诀降低盈境门槛
	w.xinfa["chunyang"] = 2
	w.recalc()
	_check(absf(w.ying_at() - (Data.T("ying_at") - 0.1)) < 1e-6, "纯阳诀 Lv2：盈境门槛降低 10%%（实际 %.2f）" % w.ying_at())
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
		for i in int(8.0 / DT):
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
	_check(we.projs.size() == 16, "八荒拳催动：十六方向（实际 %d）" % we.projs.size())
	we.projs.clear()
	ew.empowered = false
	ew.emp_burst = false
	ew.fire()
	_check(we.projs.size() == int(ew.p("count")), "八荒拳普通版：%d 方向" % int(ew.p("count")))
	_free_world(we)
	# 运功升级：催动消耗递减
	var sb := SkillBase.new()
	sb.setup(_new_world(1), "yue_palm", Data.skills["yue_palm"])
	var c0 := sb.empower_cost()
	sb.add_upgrade("empower", 3)
	_check(absf(sb.empower_cost() - c0 * 0.5) < 1e-6, "运功·灵机一动：催动消耗 −50%")
	print("  三境 / 门槛心法 / 回气 / 外泄 / 入定 / 9 招催动 / 运功  OK")


func _meta_test() -> void:
	print("\n=== 局外成长：修为 / 等级 / 属性 ===")
	var mv: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://backend/test/meta_vectors.json"))
	for v in mv["levels"]:
		_check(Meta.level_of(int(v["exp"])) == int(v["level"]), "等级向量不一致：%s" % str(v))
	for v in mv["effective"]:
		_check(absf(Meta.effective(int(v["points"])) - float(v["eff"])) < 1e-3, "有效点向量不一致：%s" % str(v))
	for v in mv["runExp"]:
		_check(Meta.run_exp(int(v["score"]), bool(v["won"]), bool(v["first"])) == int(v["exp"]), "修为向量不一致：%s" % str(v))
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
	_check(w2.anim_ovr == "punch", "连环拳出招应触发 punch 动画，实际 %s" % w2.anim_ovr)
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
