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
	# 装备：数量与稀有度
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var n_lo := 0
	var n_hi := 0
	var hi_lo := 0
	var hi_hi := 0
	var tot_lo := 0
	var tot_hi := 0
	for i in 600:
		for c in Gear.roll_drops(rng, 1.0):
			n_lo += 1
			tot_lo += 1
			hi_lo += 1 if int(Gear.parse(c)["rarity"]) >= 3 else 0
		for c in Gear.roll_drops(rng, 3.0):
			n_hi += 1
			tot_hi += 1
			hi_hi += 1 if int(Gear.parse(c)["rarity"]) >= 3 else 0
	_check(float(n_hi) > float(n_lo) * 1.8, "掉落件数：难度 300%% 明显更多（%d → %d）" % [n_lo, n_hi])
	_check(float(hi_hi) / float(tot_hi) > float(hi_lo) / float(tot_lo) * 1.5, "极品 / 传说占比更高（%.3f → %.3f）" % [float(hi_lo) / float(tot_lo), float(hi_hi) / float(tot_hi)])
	_check(Gear.drop_count(rng, 1.0) >= 1 and absf(Gear.rarity_weight(0, 3.0) - Gear.rarity_weight(0, 1.0)) < 1e-9 and Gear.rarity_weight(4, 3.0) > Gear.rarity_weight(4, 1.0) * 4.0, "凡品权重不变，传说权重 ×5")
	print("  局内经验 ×2.5 / 修为 ×2 / 掉落件数 / 稀有度权重  OK")


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
	var base_w := _new_world(91)
	base_w.skills.clear()
	_check(base_w.burst_max() == 1 and base_w.burst_left() == 1, "基础 1 次爆发")
	base_w.neili = base_w.st("max_neili") * 0.05
	_check(not base_w.can_burst(), "内力低于 10% 不能爆发")
	var dmg_at := {}
	for f in [0.3, 1.0]:
		var w := _new_world(92)
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
	var wn := _new_world(93)
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
	var base_regen := float(Data.player_base["neili_regen"])
	var base_max := float(Data.player_base["max_neili"])
	var wa := _new_world(71)
	wa.skills.clear()
	wa.xinfa = {"wuxiang": 1, "hanshuang": 1}
	wa.recalc()
	_check(absf(wa.st("neili_regen") - base_regen * 1.2) < 1e-6 and wa.st("ping_widen") > 0.0 and wa.synergies[0]["name"] == "阴阳调和", "阴阳调和：回气 +20%，平境更宽")
	var xu0 := Data.T("xu_below")
	wa.neili = wa.st("max_neili") * (xu0 - 0.03)
	_check(wa.realm() == GameWorld.Realm.PING, "平境更宽：略低于虚境线时仍算平")
	_free_world(wa)
	var wb := _new_world(72)
	wb.skills.clear()
	wb.xinfa = {"wuxiang": 1, "tiegu": 1}
	wb.recalc()
	_check(absf(wb.st("neili_regen") - base_regen * 0.8) < 1e-6 and absf(wb.st("emp_power") - 0.3) < 1e-9 and wb.synergies[0]["name"] == "烈火", "烈火：回气 −20%，催动威力 +30%")
	wb.input_move = Vector2.ZERO
	for i in int(3.0 / DT):
		wb.step(DT)
	_check(not wb.meditating(), "烈火：入定无效")
	var probe := Enemy.new()
	probe.hp = 1.0e12
	probe.max_hp = 1.0e12
	wb.stats["crit_chance"] = 0.0
	wb._emp_ctx = 0
	var plain := wb.hit_enemy(probe, 100.0, ["远程"], Vector2.ZERO, "probe")
	wb._emp_ctx = 1
	var emp := wb.hit_enemy(probe, 100.0, ["远程"], Vector2.ZERO, "probe")
	_check(absf(emp / plain - 1.3) < 1e-6, "烈火：催动版伤害 ×1.3（实际 ×%.2f）" % (emp / plain))
	_free_world(wb)
	var wc := _new_world(73)
	wc.skills.clear()
	wc.xinfa = {"hanshuang": 1, "tunhai": 1}
	wc.recalc()
	var per_max := float(Data.xinfa["hanshuang"]["per_level"].get("max_neili", 0.0)) + float(Data.xinfa["tunhai"]["per_level"].get("max_neili", 0.0))
	_check(absf(wc.st("max_neili") - (base_max + per_max) * 1.3) < 1e-6 and absf(wc.st("emp_power") + 0.15) < 1e-9 and wc.synergies[0]["name"] == "寒潭", "寒潭：内力上限 +30%，催动威力 −15%")
	_free_world(wc)
	# 合璧效果
	var wd := _new_world(74)
	wd.skills.clear()
	wd.xinfa = {"chunyang": 1, "hanshuang": 1}
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
	we.xinfa = {"tiegu": 1, "jieli": 1}
	we.recalc()
	_check(absf(we.st("thorns") - float(Data.xinfa["jieli"]["per_level"]["thorns"]) * 2.0) < 1e-6, "金钟罩：反震翻倍")
	_free_world(we)
	var wf := _new_world(76)
	wf.skills.clear()
	wf.xinfa = {"tunhai": 1, "lingxi": 1}
	wf.recalc()
	wf.neili = 10.0
	wf.stats["crit_chance"] = 1.0
	var pe := Enemy.new()
	pe.hp = 1.0e12
	pe.max_hp = 1.0e12
	wf.hit_enemy(pe, 10.0, ["远程"], Vector2.ZERO, "probe")
	_check(absf(wf.neili - 11.5) < 1e-6, "吞吐万象：暴击回内力 +1.5（实际 %.2f）" % wf.neili)
	_free_world(wf)
	# 选卡提示：已学一个心法时，候选心法的卡片会提示阴阳组合 / 合璧
	var wg := _new_world(77)
	wg.skills.clear()
	wg.xinfa = {"chunyang": 1}
	var hinted := false
	var spoil := false
	for i in 60:
		for c in wg.roll_choices(30):
			if str(c["kind"]) == "new_xinfa":
				_check(str(c["title"]).contains("【阳】") or str(c["title"]).contains("【阴】"), "心法卡片带阴阳标记")
				if c["id"] == "hanshuang":
					hinted = hinted or str(c["desc"]).contains("合璧「冰火同炉」")
				if c["id"] == "puti":
					spoil = spoil or str(c["desc"]).contains("合璧")
	_check(hinted and not spoil, "能合璧的卡片提示合璧，不能的不提示")
	wg.xinfa.clear()
	for c in wg.roll_choices(30):
		if str(c["kind"]) == "new_xinfa":
			_check(not str(c["desc"]).contains("▶"), "一个心法都没学时没有搭配提示")
	_free_world(wg)
	print("  阴阳属性 / 45 种搭配 / 调和·烈火·寒潭 / 合璧效果 / 选卡提示  OK")


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
	_check(kinds.has("hit_impact") and (kinds.has("slash_fist") or kinds.has("slash_heavy")), "有素材时命中 / 刀光走特效（%s）" % str(kinds.keys()))
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
	print("\n=== 经脉图（天赋树）布局 / 交互 ===")
	var tm := TalentMap.new()
	tm.size = Vector2(405, 644)
	add_child(tm)
	var all := Talents.nodes()
	_check(tm.pos_of.size() == all.size() and all.size() == 42, "42 个穴位都有坐标（实际 %d）" % tm.pos_of.size())
	_check(tm.meridians.size() == 6, "六条经脉")
	var ids: Array = tm.pos_of.keys()
	var min_d := 1.0e9
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			min_d = minf(min_d, (tm.pos_of[ids[i]] as Vector2).distance_to(tm.pos_of[ids[j]]))
	_check(min_d >= 2.0 * TalentMap.NODE_R, "穴位之间不重叠（最近 %.1f，需要 ≥ %.1f）" % [min_d, 2.0 * TalentMap.NODE_R])
	var dt := tm.dantian()
	var near := 1.0e9
	for id in ids:
		near = minf(near, (tm.pos_of[id] as Vector2).distance_to(dt))
	_check(near > TalentMap.NODE_R * 2.0, "穴位不压在丹田上")
	var sz := tm.fig_size()
	for id in ids:
		var p: Vector2 = tm.pos_of[id]
		_check(p.x > 10 and p.y > 10 and p.x < sz.x - 10 and p.y < sz.y - 10, "穴位在图内：" + str(id))
	# 每条脉：7 个穴位按层号 0~6 排列，属于同一个系
	for mer in tm.meridians:
		for r in 7:
			var n: Dictionary = all[mer["ids"][r]]
			_check(int(n["row"]) == r and n["branch"] == mer["branch"], "脉 %s 第 %d 个穴位的层号与系" % [mer["name"], r])
	# 命中测试 + 点击加点 / 减点（走真实的输入事件）
	tm.fig_scale = 0.92
	tm.fig_origin = Vector2.ZERO
	tm.level = 10
	var gid := "gang_force"
	var sp := tm.to_screen(tm.pos_of[gid])
	_check(tm.node_at(sp) == gid and tm.node_at(sp + Vector2(60, 60)) == "", "鼠标命中测试")
	var mv := InputEventMouseMotion.new()
	mv.position = sp
	tm._gui_input(mv)
	_check(tm.hover_id == gid, "悬停")
	var click := InputEventMouseButton.new()
	click.position = sp
	click.pressed = true
	click.button_index = MOUSE_BUTTON_LEFT
	var changes := [0]
	tm.changed.connect(func(): changes[0] += 1)
	tm._gui_input(click)
	tm._gui_input(click)
	_check(int(tm.work.get(gid, 0)) == 2 and changes[0] == 2, "左键加点")
	click.button_index = MOUSE_BUTTON_RIGHT
	tm._gui_input(click)
	_check(int(tm.work.get(gid, 0)) == 1, "右键减点")
	# 锁定的穴位点了没用
	var locked := "gang_peak"
	var mv2 := InputEventMouseMotion.new()
	mv2.position = tm.to_screen(tm.pos_of[locked])
	tm._gui_input(mv2)
	click.button_index = MOUSE_BUTTON_LEFT
	tm._gui_input(click)
	_check(not tm.work.has(locked) and tm.state_of(locked) == "locked" and tm.state_of(gid) == "ranked", "锁定的穴位不能加点；状态判定")
	remove_child(tm)
	tm.free()
	print("  42 穴位坐标 / 不重叠 / 层号对应 / 命中 / 加减点 / 锁定  OK")


func _build_test() -> void:
	print("\n=== 天赋树 / 装备 ===")
	# 天赋树结构：三系各 7 层、每层 5 点，共 35 点；节点属性都是已有的属性
	var all := Talents.nodes()
	for b in Talents.branches():
		var sum := 0
		for id in all:
			if all[id]["branch"] == b:
				sum += int(all[id]["max"])
		_check(sum == 35, "%s 系应共 35 点（实际 %d）" % [b, sum])
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
	t = {"gang_force": 3}
	_check(Talents.can_add(t, "gang_crit", 10), "低层 3 点后解锁第 1 层")
	t = {"gang_force": 3, "gang_crit": 1}
	_check(not Talents.can_remove(t, "gang_force", 10), "已有第 1 层点数时，不能把低层减到不足 3")
	_check(Talents.can_remove(t, "gang_crit", 10), "可以减掉高层的点")
	_check(not Talents.can_add({"gang_force": 3}, "gang_force", 10), "满级节点不能再加")
	_check(not Talents.can_add({"gang_force": 3, "gang_body": 1}, "gang_body", 4), "总点数用完不能再加（等级 4）")
	_check(Talents.valid({"gang_force": 3, "rou_regen": 3, "ling_step": 3}, 9) and not Talents.valid({"gang_force": 3, "rou_regen": 3, "ling_step": 3}, 8), "总点数 ≤ 局外等级；三系可同时加")
	_check(Talents.clean({"gang_force": 99, "zzz": 5, "rou_regen": -2}) == {"gang_force": 3}, "天赋规范化")
	var tst := Talents.stats_for({"gang_force": 2, "gang_ying": 0})
	_check(absf(float(tst["damage_pct"]) - 0.04) < 1e-9, "天赋效果叠加")
	# 装备：编码、确定性、稀有度、词条
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var counts := [0, 0, 0, 0, 0]
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
	_check(counts[0] > counts[1] and counts[1] > counts[2] and counts[2] > counts[3] and counts[3] > counts[4] and counts[4] > 0, "稀有度分布递减：%s" % str(counts))
	_check(has_xinfa and has_skill, "两类词条都应出现")
	_check(Gear.parse("weapon.9.1").is_empty() and Gear.parse("hat.0.1").is_empty() and Gear.parse("weapon.1").is_empty() and not Gear.parse("weapon.1.77").is_empty(), "编码格式校验")
	var legend := Gear.make("weapon.4.4242")
	var common := Gear.make("weapon.0.4242")
	_check(float(legend["stats"]["damage_pct"]) > float(common["stats"]["damage_pct"]) * 2.5, "传说的基础属性远高于凡品")
	_check(legend["affixes"].size() == 2 and common["affixes"].is_empty(), "传说 2 条词条，凡品没有")
	var dr := Gear.roll_drops(rng)
	_check(dr.size() >= 1 and dr.size() <= 2, "通关掉落 1~2 件")
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
	_check(absf(float(sk.mods["damage"]) - 0.3) < 1e-9 and absf(sk.empower_cost() - c0 * 0.8) < 1e-6, "技能词条：伤害 +30%、催动消耗 −20%")
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
	_check(w.realm() == GameWorld.Realm.YING and is_equal_approx(w.dmg_mult(), Data.T("ying_dmg")), "达到盈境门槛为盈，伤害加成")
	w.neili = mx * 0.5
	_check(w.realm() == GameWorld.Realm.PING and is_equal_approx(w.dmg_mult(), 1.0), "平境无加成")
	w.neili = mx * 0.2
	_check(w.realm() == GameWorld.Realm.XU, "低于 25% 为虚")
	# 九阳神功降低盈境门槛
	w.xinfa["chunyang"] = 2
	w.recalc()
	_check(absf(w.ying_at() - (Data.T("ying_at") - 0.1)) < 1e-6, "九阳神功 Lv2：盈境门槛降低 10%%（实际 %.2f）" % w.ying_at())
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
	_check(bool(tv["ok"]) and net_calls[-1]["body"]["state"]["talents"] == {"gang_force": 3}, "保存天赋：只带有效节点")
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
