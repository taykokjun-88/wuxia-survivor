extends Node
## 武者新天赋树截图。运行：SHOT_DIR=/tmp/shots xvfb-run -a godot --path . --rendering-driver opengl3 res://tests/shot_talent.tscn
var main: Node
var dir := ""


func _ready() -> void:
	dir = OS.get_environment("SHOT_DIR") if OS.get_environment("SHOT_DIR") != "" else "user://"
	Net.api_url = ""
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	main.set_physics_process(false)
	await get_tree().process_frame
	Save.create_character(OS.get_environment("SHOT_SCHOOL") if OS.get_environment("SHOT_SCHOOL") != "" else "fist")
	Save.store_meta(1900000, {})
	main._enter_town()
	main.hud.talents_work = {"sl_a_1": 3, "sl_a_2": 1, "sl_b_1": 4, "sl_d_1": 2, "sg_a_1": 3, "sr_g_1": 2}
	Save.set_meta_talents(main.hud.talents_work)
	main._open_meta()
	for i in 3:
		await get_tree().process_frame
	main._open_talents()
	for i in 4:
		await get_tree().process_frame
	main.hud.talents_tree.hover_id = "sl_a_2"
	main.hud.talents_tree.hovered.emit("sl_a_2")
	for i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/talent_fist.png" % dir)
	get_tree().quit()
