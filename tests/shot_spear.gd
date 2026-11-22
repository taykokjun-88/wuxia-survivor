extends Node
## 杨家将截图：创建界面 / 选人 / 小镇 / 局内。
## 运行：SHOT_DIR=/tmp/shots xvfb-run -a godot --path . --rendering-driver opengl3 res://tests/shot_spear.tscn

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
	main.hud.show_create(false)
	await _frames(4)
	await _snap("sp1_create")
	main.hud._on_school_selected("spear")
	await _frames(4)
	await _snap("sp1b_create_spear")
	main.hud.hide_create()
	Save.create_character("spear")
	main._enter_town()
	await _frames(30)
	await _snap("sp2_town")
	main.hud.show_chars(main._char_list(), main._last_char(), false)
	await _frames(4)
	await _snap("sp2b_charselect")
	main.hud.hide_chars()
	main._show_game(true)
	w.start_run("yangjia_spear", "tashue", "black_wind", {})
	w.add_skill("shaolin_staff")
	for i in 240:
		w.step(DT)
	await _frames(2)
	await _snap("sp3_run")
	w.spear_qs = 100.0
	w.spear_gs = 100.0
	for i in 40:
		w.step(DT)
	await _frames(2)
	await _snap("sp4_full")
	get_tree().quit()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, name])
