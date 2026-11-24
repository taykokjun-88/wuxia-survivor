extends Node
## 选关界面截图（赤焰巅 / 海棠屿）。运行：SHOT_DIR=/tmp/shots xvfb-run -a godot --path . --rendering-driver opengl3 res://tests/shot_stage.tscn
var main: Node
var dir := ""


func _ready() -> void:
	dir = OS.get_environment("SHOT_DIR") if OS.get_environment("SHOT_DIR") != "" else "user://"
	Net.api_url = ""
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	main.set_physics_process(false)
	await get_tree().process_frame
	Save.create_character("fist")
	main._enter_town()
	await get_tree().process_frame
	for m in ["guangming", "taohua", "black_wind"]:
		main.state = main.State.LOADOUT
		main.hud.show_loadout("fist", m)
		for i in 4:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/stage_%s.png" % [dir, m])
	get_tree().quit()
