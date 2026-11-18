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
	print("\nRESULT: %s" % ("FAIL (%d)" % failures if failures > 0 else "OK"))
	get_tree().quit(1 if failures > 0 else 0)


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


func _fake_transport(is_get: bool, url: String, body: Dictionary) -> Dictionary:
	net_calls.append({"get": is_get, "url": url, "body": body.duplicate(true)})
	if not fake_reply.is_empty():
		return fake_reply
	match str(body["action"]):
		"login", "register", "resume":
			return {"ok": true, "nick": body.get("nick", "阿杰"), "token": "T1", "school": "fist", "bests": {"score": 5}}
		"submit":
			return {"ok": true, "score": 1234, "best": true, "ranks": {"score": 2, "speed": 0, "level": 3}, "bests": {"score": 1234}}
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
	var c: Dictionary = net_calls[-1]
	_check(not c["get"] and c["body"]["pin"] == "2468" and not c["body"].has("token"), "登录请求：POST、带 PIN、不带令牌")
	# 带令牌的请求自动附带昵称 + 令牌
	await Net.save_state("fist")
	_check(net_calls[-1]["body"]["token"] == "T1" and net_calls[-1]["body"]["state"]["school"] == "fist", "saveState 应带令牌和流派")
	var sub: Dictionary = await Net.submit_run({"won": true, "seconds": 750, "level": 38, "kills": 6100, "bosses": 4,
		"school": "fist", "starter": "chain_fist", "qinggong": "tashue", "enhance": "yue_palm:3", "build": [{"id": "yue_palm", "lv": 12}], "version": "0.3"})
	_check(bool(sub["ok"]) and net_calls[-1]["body"]["build"] is String and net_calls[-1]["body"]["nick"] == "阿杰", "提交成绩：build 序列化为字符串、带昵称")
	_check(int(Net.bests.get("score", 0)) == 1234, "提交成功后应更新本地最高记录")
	# 排行榜：GET，不带令牌
	await Net.board("score")
	_check(net_calls[-1]["get"] and net_calls[-1]["body"]["kind"] == "score" and not net_calls[-1]["body"].has("token"), "读榜应为 GET 且不带令牌")
	# 退出登录
	await Net.logout()
	_check(not Net.logged_in() and not Save.has_session() and net_calls[-1]["body"]["action"] == "logout", "退出登录应通知服务器并清除本地会话")

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
	print("Boss 击杀耗时：", ", ".join(w.boss_log) if not w.boss_log.is_empty() else "（无）")
	print("性能：平均 %.2f ms/step  最差 %.2f ms  敌人峰值 %d  Boss数 %d" % [
		total_us / 1000.0 / maxi(1, int(w.time / DT)), worst_us / 1000.0, peak, w.bosses.size()])
	if cfg["god"]:
		_check(w.bosses.size() == 4, "应刷出 3 个小 Boss + 1 个大 Boss，实际 %d" % w.bosses.size())
		_check(w.level >= 10, "无敌 bot 15 分钟应至少升到 10 级，实际 %d" % w.level)
		_check(w.enhance_id != "", "整局应至少拿到一次专属强化")
		_check(w.enhance_level >= 1, "击败小 Boss 后强化应至少 Lv1，实际 Lv%d" % w.enhance_level)
	_free_world(w)
