extends Node
## 截图脚本：用真实 Main 场景渲染关键画面。
## 运行：SHOT_DIR=/tmp/shots xvfb-run -a godot --path . --rendering-driver opengl3 res://tests/shot.tscn

const DT := 1.0 / 60.0

var main: Node
var w: GameWorld
var dir := ""
var pick := RandomNumberGenerator.new()


func _ready() -> void:
	dir = OS.get_environment("SHOT_DIR")
	if dir == "":
		dir = "user://"
	pick.seed = 3
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	main.set_physics_process(false)
	w = main.world
	await _frames(3)
	_snap("00_create_character")
	main.hud.confirm_create()
	await _frames(3)
	_snap("01_loadout")
	# 角色成长界面：假装已有一些修为，并分配了一部分点数
	Save.store_meta(1900, {"pow": 20, "vit": 9})
	main._open_meta()
	await _frames(3)
	_snap("01b_meta")
	main.hud.talents_work = {"gang_force": 3, "gang_crit": 3, "gang_ying": 2, "rou_regen": 2}
	Save.set_meta_talents(main.hud.talents_work)
	main._open_talents()
	await _frames(3)
	main.hud.talents_map.hover_id = "gang_peak"
	main.hud.talents_map.hovered.emit("gang_peak")
	await _frames(3)
	_snap("01c_talents")
	main._close_modal()
	Save.set_gear(["weapon.4.4242", "coat.3.77", "charm.2.9", "boots.1.5", "pants.0.12", "weapon.2.31", "coat.0.5"], {"weapon": "weapon.4.4242", "coat": "coat.3.77"})
	main._open_gear()
	await _frames(3)
	_snap("01d_gear")
	main._close_modal()
	Save.set_gear([], {})
	Save.set_meta_talents({})
	Save.store_meta(0, {})
	await _frames(2)

	# 选择：连环拳 / 飞燕穿林
	main.hud.sel_starter = "chain_fist"
	main.hud.sel_qg = "feiyan"
	main._on_loadout("chain_fist", "feiyan")
	w.god = true
	w.rng_seed = 5
	await _advance(50.0)
	_snap("02_play_start_skill")

	# 升级选择界面（真实 roll_choices）
	w.pending_levels = 1
	main._check_pending()
	# 强制三张卡覆盖三种档位，检查配色与排版
	var s0: SkillBase = w.skills.values()[0]
	var demo: Array = []
	for t in [1, 2, 3]:
		var dirs := s0.available_dirs()
		demo.append({
			"kind": "up_skill", "id": s0.id, "dir": dirs[t], "tier": t, "src": "level",
			"tag": str(Data.tiers[t]["name"]), "color": str(Data.tiers[t]["color"]),
			"title": "%s · %s" % [s0.def["name"], Data.directions[dirs[t]]["name"]],
			"desc": "%s　（已升级 %d/%d）" % [s0.upgrade_text(dirs[t], t), s0.upgrades.size(), Data.max_upgrades]})
	main.choices = demo
	main.hud.show_choices(demo, "突破！选择一项领悟（按 1 / 2 / 3 或点击）")
	await _frames(3)
	_snap("03_levelup")
	main._on_choice(0)

	# 装满四个技能 + 两个心法 + 强化，截一张战斗图
	for id in ["yue_palm", "quake_fist", "cloud_palm"]:
		if not w.skills.has(id):
			w.add_skill(id)
	for s: SkillBase in w.skills.values():
		for dir in ["damage", "cooldown", "range", "crit"]:
			if s.available_dirs().has(dir):
				s.add_upgrade(dir, 2)
	# 让第二个技能升满 12 层，检查「极」标记
	var smax: SkillBase = w.skills.values()[1]
	while smax.upgrades.size() < Data.max_upgrades:
		smax.add_upgrade("damage", 0)
	w.xinfa["chunyang"] = 2
	w.xinfa["lingxi"] = 1
	w.enhance_id = "cloud_palm"
	w.enhance_level = 2
	w.recalc()
	await _advance(70.0)
	_snap("04_play_full_build")

	# 秘籍选择
	w.enhance_id = ""
	w.pending_chests = 1
	main._check_pending()
	await _frames(3)
	_snap("05_chest_choice")
	main._on_choice(0)

	# 角色动画：出招 / 冲刺 / 行走（在游戏里真实绘制）
	w.over = false
	w.invuln = 0.0
	w.since_hit = 9.0
	w.play_anim("punch", 0.4)
	w.anim_ovr_t = 0.2            # 出招动画进行到 0.2s（第 3 帧）
	w.facing = Vector2.RIGHT
	await _frames(3)
	_snap("07_anim_punch")
	w.anim_ovr_t = 0.0
	w.dash_t = 0.1
	await _frames(3)
	_snap("08_anim_dash")
	w.dash_t = 0.0
	w.input_move = Vector2.LEFT
	w.facing = Vector2.LEFT
	await _frames(3)
	_snap("09_anim_walk_left")
	w.input_move = Vector2.ZERO

	# 精英 + 小 Boss
	w.time = 355.0
	await _advance(25.0)
	_snap("06_mini_boss")
	w._spawn_boss("mini_boss_2", false)
	w.bosses[w.bosses.size() - 1].pos = w.player_pos + Vector2(140, -40)
	w.bosses[w.bosses.size() - 1].guard *= 0.6
	await _advance(0.5)
	_snap("06b_boss_guard")
	# 阴阳 / 合璧：已学纯阳诀，选卡里出现寒霜诀（合璧）；再学会后 HUD 显示组合
	w.xinfa = {"chunyang": 1}
	w.recalc()
	main.hud.show_choices([
		{"kind": "new_xinfa", "id": "hanshuang", "tag": "心法", "title": "修习：寒霜诀【阴】", "desc": str(Data.xinfa["hanshuang"]["desc"]) + w._synergy_hint("hanshuang")},
		{"kind": "new_xinfa", "id": "tiegu", "tag": "心法", "title": "修习：铁骨诀【阳】", "desc": str(Data.xinfa["tiegu"]["desc"]) + w._synergy_hint("tiegu")},
		{"kind": "new_xinfa", "id": "puti", "tag": "心法", "title": "修习：菩提诀【阴】", "desc": str(Data.xinfa["puti"]["desc"]) + w._synergy_hint("puti")}], "测试")
	await _frames(3)
	_snap("06c_xinfa_cards")
	main.hud.hide_choices()
	w.xinfa = {"chunyang": 1, "hanshuang": 1}
	w.recalc()
	await _frames(3)
	_snap("06d_synergy_hud")
	# 特效层（用假的发光环素材验证「叠加绘制」确实把特效画出来了）
	var sim = load("res://tests/sim_test.gd").new()
	for id in ["hit_impact", "slash_fist", "slash_heavy", "burst_wind", "proj_wave", "proj_palm", "proj_bolt", "proj_finger", "burst_ult"]:
		if w.vfx.has(id):
			continue
		w.vfx.add(id, sim.fake_strip(5, 64, Color("#7fe8ff") if id.begins_with("proj") else Color("#ffd37f")), 5, 14.0, 64, id.begins_with("proj"))
	sim.free()
	w.xinfa = {}
	w.recalc()
	w.god = true
	await _advance(2.0)
	_snap("06e_vfx_layer")
	# 四个弹体特效：真实招式在战斗里，逐个截图
	w.bosses.clear()
	for e in w.enemies:
		e.alive = false
	w._compact_enemies()
	for sid in ["yue_palm", "cloud_palm", "eight_waste", "point_finger"]:
		w.skills.clear()
		w.add_skill(sid)
		for e in w.enemies:
			e.alive = false
		w._compact_enemies()
		w.projs.clear()
		for i in 10:
			var en := w._spawn_enemy("bandit", w.player_pos + Vector2.from_angle(i * 0.62 + 0.2) * (200.0 + 50.0 * (i % 3)))
			en.speed = 0.0
			en.hp = 1.0e9
			en.max_hp = 1.0e9
		await _advance(0.45)
		_snap("06f_proj_" + sid)
	Save.reset_character()   # 清理截图产生的存档
	get_tree().quit()


func _advance(seconds: float) -> void:
	var n := int(seconds / DT)
	for i in n:
		TestBot.drive(w)
		w.step(DT)
		TestBot.resolve_choices(w, pick)
		if i % 600 == 0:
			await get_tree().process_frame
	await _frames(2)


func _frames(n: int) -> void:
	for i in n:
		w.queue_redraw()
		await get_tree().process_frame
	main.cam.position = w.player_pos


func _snap(name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [dir, name]
	img.save_png(path)
	print("saved ", path, " ", img.get_size())
