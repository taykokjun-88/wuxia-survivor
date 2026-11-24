extends Node
## 八卦阵截图。运行：SHOT_DIR=/tmp/shots xvfb-run -a godot --path . --rendering-driver opengl3 res://tests/shot_bagua.tscn
const DT := 1.0 / 60.0
var main: Node
var w: GameWorld


func _ready() -> void:
	var dir := OS.get_environment("SHOT_DIR") if OS.get_environment("SHOT_DIR") != "" else "user://"
	Net.api_url = ""
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	main.set_physics_process(false)
	w = main.world
	await get_tree().process_frame
	Save.create_character("fist")
	main._enter_town()
	main.hud.hide_chars()
	main.hud.hide_create()
	main._show_game(true)
	w.start_run("chain_fist", "tashue", "taohua", {})
	for i in int(9.5 / DT):
		w.step(DT)
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/bagua.png" % dir)
	get_tree().quit()
