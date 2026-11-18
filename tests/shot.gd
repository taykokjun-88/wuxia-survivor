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
