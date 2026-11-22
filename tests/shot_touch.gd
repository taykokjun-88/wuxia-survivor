extends Node
## 触控 / 横屏提示截图。运行：SHOT_DIR=/tmp/shots xvfb-run -a godot --path . --rendering-driver opengl3 res://tests/shot_touch.tscn [-- portrait]
const DT := 1.0 / 60.0
var main: Node
var w: GameWorld
var dir := ""


func _ready() -> void:
	dir = OS.get_environment("SHOT_DIR") if OS.get_environment("SHOT_DIR") != "" else "user://"
	Net.api_url = ""
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	main.set_physics_process(false)
	w = main.world
	await _frames(2)
	var portrait := OS.get_cmdline_user_args().has("portrait")
	main.guard.touch_seen = true
	main.touch.touch_seen = true
	if portrait:
		main.hud.hide_auth()
		await _frames(6)
		await _snap("tc_portrait")
		if OS.get_cmdline_user_args().has("--wait"):
			await get_tree().create_timer(30.0).timeout       # 留时间给外部抓整个窗口
		get_tree().quit()
		return
	main.hud.hide_auth()
	main.hud.hide_chars()
	Save.create_character("spear")
	main._enter_town()
	await _frames(20)
	await _snap("tc_town")
	main._show_game(true)
	main.state = main.State.PLAY
	w.start_run("yangjia_spear", "tashue", "black_wind", {})
	for i in 120:
		w.step(DT)
	await _frames(3)
	await _snap("tc_play")
	# 模拟按住摇杆
	var d := InputEventScreenTouch.new()
	d.index = 0
	d.pressed = true
	d.position = Vector2(220, 520)
	main.touch._input(d)
	var dr := InputEventScreenDrag.new()
	dr.index = 0
	dr.position = Vector2(270, 500)
	main.touch._input(dr)
	await _frames(3)
	await _snap("tc_play_stick")
	get_tree().quit()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, name])
