extends Node
## 刀客特效截图：五煞断岳刀（扇形 / 横扫）与斩蛟沉海刀。
## 运行：SHOT_DIR=/tmp/shots xvfb-run -a godot --path . --rendering-driver opengl3 res://tests/shot_blade.tscn
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
	Save.create_character("blade")
	main._enter_town()
	main.hud.hide_chars()
	main.hud.hide_create()
	main._show_game(true)
	w.start_run("wuhu_blade", "tashue", "black_wind", {})
	w.add_skill("tulong_art")
	for k in 6:
		w._spawn_enemy("soldier", w.player_pos + Vector2.from_angle(k * 1.05) * 80.0)
	var got := {}
	for i in 900:
		w.step(DT)
		for fx in w.effects:
			var id := str(fx.get("vfx", ""))
			if (id == "fx_blade_wuhu" or id == "fx_blade_tulong") and not got.has(id) and float(fx["t"]) > 0.06:
				got[id] = true
				await RenderingServer.frame_post_draw
				await _snap("bl_" + id)
		if got.size() == 2:
			break
		await get_tree().process_frame
	get_tree().quit()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, name])
