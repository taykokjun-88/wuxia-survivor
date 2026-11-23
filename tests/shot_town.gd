extends Node
## 小镇布局截图：各 NPC 门前。运行：SHOT_DIR=/tmp/shots xvfb-run -a godot --path . --rendering-driver opengl3 res://tests/shot_town.tscn

var main: Node
var dir := ""


func _ready() -> void:
	dir = OS.get_environment("SHOT_DIR") if OS.get_environment("SHOT_DIR") != "" else "user://"
	Net.api_url = ""
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	main.set_physics_process(false)
	await _frames(2)
	main.hud.show_auth("")
	await _frames(2)
	main.hud.hide_auth()
	main.hud.show_create(false)
	await _frames(2)
	main.hud.hide_create()
	Save.create_character("spear")
	main._enter_town()
	main.hud.hide_chars()
	main.hud.hide_create()
	await _frames(20)
	var spots := {"a_center": Vector2(0, -20), "b_west": Vector2(-480, -40), "c_east": Vector2(480, -40), "d_north": Vector2(0, -250), "e_south": Vector2(0, 330), "f_spawn": Vector2(0, 520)}
	for k in spots:
		main.town.player_pos = spots[k]
		main.town.queue_redraw()
		await _frames(25)
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s/town_%s.png" % [dir, k])
	get_tree().quit()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
