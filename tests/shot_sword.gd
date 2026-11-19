extends Node
## 剑客截图：独孤九剑 HUD / 升级卡 / 真·独孤九剑战斗。
## 运行：SHOT_DIR=/tmp/shots xvfb-run -a godot --path . --rendering-driver opengl3 res://tests/shot_sword.tscn

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
	main.hud.sel_school = "sword"
	main.hud.confirm_create()
	await _frames(2)
	Save.create_character("sword")
	main.state = main.State.LOADOUT
	main.hud.show_loadout("sword", "black_wind")
	await _frames(3)
	_snap("s0_loadout")
	main._on_loadout("dugu", "tashue")
	w.god = true
	w.time = 130.0
	w.shi = {"po_jian": 6, "po_dao": 4, "po_bian": 3, "zong": 3}
	for i in 60:
		var a := w.rng.randf() * TAU
		w._spawn_enemy("bandit", w.player_pos + Vector2.from_angle(a) * w.rng.randf_range(120.0, 420.0))
	for i in 150:
		w.step(DT)
	await _frames(2)
	_snap("s1_dugu_stage1")
	w.shi = {"po_jian": 10, "po_dao": 10, "po_bian": 6, "zong": 10}
	main.hud.hud_expanded = true
	for i in 70:
		w.step(DT)
		if i % 6 == 0:
			w._rebuild_grid()
	await _frames(2)
	_snap("s2_dugu_true")
	w.pending_levels = 1
	main._check_pending()
	await _frames(3)
	_snap("s3_shi_cards")
	get_tree().quit()


func _frames(n: int) -> void:
	for i in n:
		w.queue_redraw()
		await get_tree().process_frame
	main.cam.position = w.player_pos


func _snap(name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [dir, name])
	print("saved ", name)
