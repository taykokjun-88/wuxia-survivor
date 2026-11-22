extends Node
## 海棠屿截图。运行：SHOT_DIR=/tmp/shots xvfb-run -a godot --path . --rendering-driver opengl3 res://tests/shot_taohua.tscn
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
	Save.create_character("spear")
	main._enter_town()
	await _frames(2)
	main.state = main.State.LOADOUT
	main.hud.show_loadout("spear", "taohua")
	await _frames(3)
	await _snap("th1_loadout")
	main.hud.hide_loadout()
	main.hud.hide_chars()
	main._show_game(true)
	w.start_run("yangjia_spear", "tashue", "taohua", {})
	for i in 60 * 24:
		w.step(DT)
	await _frames(2)
	await _snap("th2_run")
	for i in 60 * 40:
		w.step(DT)
	await _frames(2)
	await _snap("th3_run_late")
	w.god = true
	w.time = 840.0
	for i in 120:
		w.step(DT)
	var hb: Enemy = null
	for b in w.bosses:
		if b.alive and b.type_id == "th_boss":
			hb = b
	hb.speed = 0.0
	hb.hp = 1.0e9
	hb.max_hp = 1.0e9
	for i in 60 * 5:
		w.step(DT)
	hb.pos = w.player_pos + Vector2(0, -90)
	hb.cast_id = ""
	BossAI._start(w, hb, "xiao_wave", Vector2.RIGHT)
	for i in 40:
		w.step(DT)
	await _frames(2)
	print("BOSS ", hb.pos, w.player_pos, hb.alive, hb.cast_id, hb.cast_t, w.enemies.has(hb))
	await _snap("th4_xiao_warn")
	for i in 45:
		w.step(DT)
	await _frames(2)
	await _snap("th5_xiao_hit")
	get_tree().quit()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, name])
