extends Node
## 剑侠截图：独孤九剑 HUD / 升级卡 / 真·独孤九剑战斗。
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
	main.hud.show_auth("")
	await _frames(3)
	_snap("u0_auth")
	main.hud.hide_auth() if main.hud.has_method("hide_auth") else null
	main._enter_town()
	main.town.player_pos = Vector2(0, -170)
	main.town.queue_redraw()
	await _frames(3)
	_snap("t1_town_clerk")
	main.town.player_pos = Vector2(-330, 40)
	main.town.queue_redraw()
	await _frames(3)
	_snap("t2_town_west")
	main.town.player_pos = Vector2(330, 40)
	main.town.queue_redraw()
	await _frames(3)
	_snap("t3_town_east")
	main.town.player_pos = Vector2(0, 260)
	main.town.facing = Vector2.UP
	main.town.queue_redraw()
	await _frames(3)
	_snap("t4_town_south")
	Save.set_gear(["weapon.4.4242", "coat.3.77", "charm.2.9", "boots.1.5", "pants.0.12", "weapon.2.31"], {"weapon": "weapon.4.4242", "coat": "coat.3.77"})
	Save.store_silver_enh(1200, {"weapon.4.4242": 3, "coat.3.77": 10})
	main.state = main.State.TOWN
	main._open_smith()
	await _frames(3)
	_snap("m1_smith")
	main._on_enhance("weapon.4.4242")
	await _frames(3)
	_snap("m2_smith_after")
	main._close_modal()
	Save.set_gear([], {})
	Save.store_silver_enh(0, {})
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
	w.props_enabled = false
	for k in [["prop_crate", Vector2(-140, -60)], ["prop_jar", Vector2(-60, -110)], ["prop_brazier", Vector2(40, -120)]]:
		w._spawn_enemy(str(k[0]), w.player_pos + (k[1] as Vector2))
	for i in 6:
		w._drop_gem(w.player_pos + Vector2(100 + i * 24, 60), [1, 2, 4, 8, 15, 30][i])
	w._drop_pill(w.player_pos + Vector2(-100, 80), "small")
	w._drop_pill(w.player_pos + Vector2(-60, 80), "large")
	w.chests.append(w.player_pos + Vector2(0, 90))
	w.absorb_items.append({"pos": w.player_pos + Vector2(60, 90), "age": 0.0})
	await _frames(2)
	_snap("s1_dugu_stage1")
	w.shi = {"po_jian": 10, "po_dao": 10, "po_bian": 6, "zong": 4}
	w.add_shi("zong", 7)
	for i in 12:
		w.step(DT)
	await _frames(2)
	_snap("s1b_awaken")
	main.hud.hud_expanded = true
	for i in 70:
		w.step(DT)
		if i % 6 == 0:
			w._rebuild_grid()
	await _frames(2)
	_snap("s2_dugu_true")
	Save.create_character("sword")
	main.hud.show_end(true)
	await _frames(3)
	_snap("u1_victory")
	main.hud.show_end(false)
	await _frames(3)
	_snap("u2_defeat")
	main.hud.hide_overlay()
	main.state = main.State.PAUSED
	main.hud.show_pause()
	await _frames(3)
	_snap("s4_pause")
	main._on_pause_resume()
	w.pending_levels = 1
	main._check_pending()
	await _frames(3)
	_snap("s3_shi_cards")
	main.hud.hide_overlay()
	main._on_pause_resume()
	main.hud.hide_choices()
	w.pending_levels = 0
	w.pending_chests = 0
	w.enemies.clear()
	w.bosses.clear()
	w.skills.clear()
	w.god = true
	w.time = 721.0
	w.mini_idx = 9
	w._spawn_boss("boss", true)
	var bb: Enemy = w.bosses[w.bosses.size() - 1]
	main.state = main.State.PLAY
	bb.pos = w.player_pos + Vector2(220, 0)
	bb.skill_gap = 0.0
	bb.skills = ["cleave"]
	for i in 40:
		w.step(DT)
	await _frames(2)
	_snap("b1_boss_cleave_warn")
	bb.cast_id = ""
	bb.skills = ["leap"]
	bb.skill_gap = 0.0
	for i in 30:
		w.step(DT)
	await _frames(2)
	_snap("b2_boss_leap_warn")
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
