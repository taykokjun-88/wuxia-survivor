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
	await _frames(3)
	_snap("03_levelup")
	main._on_choice(0)

	# 装满四个技能 + 两个心法 + 强化，截一张战斗图
	for id in ["yue_palm", "quake_fist", "cloud_palm"]:
		if not w.skills.has(id):
			w.add_skill(id)
	for s: SkillBase in w.skills.values():
		s.level = 4
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

	# 精英 + 小 Boss
	w.time = 355.0
	await _advance(25.0)
	_snap("06_mini_boss")
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
