extends Node
## 截图脚本：用真实 Main 场景渲染关键画面。
## 运行：SHOT_DIR=/tmp/shots xvfb-run -a godot --path . --rendering-driver opengl3 res://tests/shot.tscn

const DT := 1.0 / 60.0

var main: Node
var w: GameWorld
var dir := ""


func _ready() -> void:
	dir = OS.get_environment("SHOT_DIR")
	if dir == "":
		dir = "user://"
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	main.set_physics_process(false)
	w = main.world
	w.god = true
	w.rng_seed = 5
	await _frames(3)
	_snap("01_menu")

	main.state = 1  # PLAY
	main.hud.hide_overlay()
	await _advance(75.0)
	_snap("02_play_75s")

	# 升级选择界面
	w.pending_levels = 1
	main._open_levelup()
	await _frames(3)
	_snap("03_levelup")
	main._on_choice(0)

	# 补齐几门武学，看看弹幕/飞剑效果
	for id in ["chuanyun", "huifeng", "chunyang"]:
		w.owned[id] = 3
	w.recalc()
	await _advance(60.0)
	_snap("04_play_135s_multi_skill")

	await _advance(112.0)
	_snap("05_boss_247s")
	get_tree().quit()


func _advance(seconds: float) -> void:
	var n := int(seconds / DT)
	for i in n:
		TestBot.drive(w)
		w.step(DT)
		while w.pending_levels > 0 and not w.over:
			w.apply_choice(w.roll_choices()[0])
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
